import 'package:goo2d/goo2d.dart';
import 'package:goo2d_ffi_box2d/goo2d_ffi_box2d.dart';

/// How the physics backend treats a body.
///
/// The indices are Box2D's own `b2BodyType` values (0/1/2), which
/// `goo_box2d.c` pins with `_Static_assert`s - so this enum's `index` can be
/// handed straight to the shim without a translation table that could drift.
///
/// Every name carries the `Body` suffix because `static` and `dynamic` are
/// both reserved words in Dart. Box2D spells them the same way
/// (`b2_staticBody`), so the suffix costs nothing in familiarity.
enum BodyType2D {
  /// Never moves and is never moved by the solver. Infinite mass. The right
  /// choice for level geometry - a static body is far cheaper than a dynamic
  /// one that happens to be sitting still.
  staticBody,

  /// Moves only when *you* move it, and pushes dynamic bodies out of the way
  /// without being pushed back. Moving platforms, lifts, sliding doors.
  kinematicBody,

  /// Fully simulated: gravity, forces, collision response.
  dynamicBody,
}

/// An entity simulated by `Box2DPhysicsSystem`.
///
/// Mixed in alongside `Transform2D` (which it reads and writes) and usually
/// `Collider2D` (which gives it shape). A `RigidBody2D` with no collider is
/// legal and simulates as a point mass - it just never touches anything.
///
/// `on Component`, not `MultiComponent`: an entity has exactly one body.
/// Several *shapes* on one body is what `Collider2D` already expresses.
///
/// # Who owns the transform
///
/// This is the load-bearing rule of the whole physics integration, and it is
/// **per body type**:
///
/// * [BodyType2D.staticBody] - **you** own the transform outright. Write
///   `Transform2D` and the system pushes it into Box2D; nothing is ever
///   written back, because the solver does not move a static body and so has
///   nothing to report about one. Small scripted rotations below `angleEpsilon`
///   (5e-3 rad) accumulate in `Transform2D` and push in steps once the
///   threshold is crossed; use [BodyType2D.kinematicBody] for smooth continuous
///   rotation.
/// * [BodyType2D.kinematicBody] - **you** own the motion, the solver owns
///   the transform. You set the velocity; the solver integrates it, and that
///   result is written back into `Transform2D` each tick. Writing
///   `Transform2D` yourself is a teleport, as it is for a dynamic body.
/// * [BodyType2D.dynamicBody] - **Box2D** owns it. The solver's output is
///   written back into `Transform2D` each tick. Writing `Transform2D`
///   yourself still works and is treated as a teleport, but doing it every
///   tick would fight the solver and destroy the simulation.
///
/// A body of any type is therefore pushed into Box2D only when its transform
/// actually differs from what the sync cache holds - see [bodySyncedX]. That is
/// not merely an optimisation: Box2D's `b2MakeRot` is an *approximation*
/// (Bhaskara rational, not libm), and round-tripping an angle through it
/// repeatedly converges on multiples of pi/4 - measured, about 27 degrees of
/// drift from 0.3 rad after 10000 cycles. Pushing back a value that was only
/// ever pulled is how that drift would get in.
///
/// # How a prefab configures its body
///
/// By moving the column defaults in its own `describeStruct`. Every field
/// here starts at the value a plain dynamic body wants, so a prefab only
/// says what differs:
///
/// ```dart
/// class Wall extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
///   @override
///   void describeStruct(DataDescriptor data) {
///     super.describeStruct(data);
///     bodyType.initialValue = BodyType2D.staticBody;
///   }
/// }
/// ```
///
/// There is no `RigidBody2D` factory to go with `ColliderBody.box`. A
/// collider is a group of columns under one name and a prefab declares
/// however many of them it has; a body is six columns this mixin already
/// declares, and a column default carries each of them.
///
/// # How a body gets created
///
/// Nothing here - `Box2DPhysicsSystem` mixes in `EntitySpawnListener` and
/// creates the body itself. This mixin is pure data.
///
/// `EntityLifecycleListener` cannot do this job. Lifecycle events are scoped
/// to their own prefab's composition, and a `GameSystem` mixing one in is
/// never offered to any prefab's dispatcher: it compiles and silently never
/// fires. `EntitySpawnListener` is the world-observation counterpart, and it
/// is the one a system mixes in.
mixin RigidBody2D on Component {
  /// The packed Box2D body handle, or `0` before the system has created one.
  ///
  /// Zero being "no body" is Box2D's own null convention, so the field's
  /// natural `0` default already means the right thing - nothing has to
  /// initialise it.
  ///
  /// Read-only from game code. It is internal in spirit and not in
  /// annotation, because a game legitimately wants it for a raycast filter or
  /// a debug overlay.
  final bodyHandle = Field.int64();

  /// Which [BodyType2D] this body is.
  ///
  /// Writing it on a live body is honoured. The next fixed step compares it
  /// against [bodySyncedType] and, when they differ, calls Box2D's own
  /// `b2Body_SetType` - which keeps the body's handle, its shapes and its
  /// joints, moves it between the solver's static and awake sets, rebuilds
  /// its broad-phase proxies and recomputes its mass. Nothing is destroyed
  /// and nothing is recreated.
  ///
  /// So a dynamic body turned static stops where it is, and a static one
  /// turned dynamic starts falling. Like every other component write it is
  /// read from the next step onward, not the one already in flight.
  final bodyType = Field.enumOf(BodyType2D.values, BodyType2D.dynamicBody);

  /// The solver's velocity, refreshed every tick. **Read-only** - these are a
  /// mirror, not an input.
  ///
  /// Assigning to them does nothing: the system pulls velocity out of Box2D
  /// each tick and never pushes it back, so the write is simply overwritten
  /// on the next step. Use [setVelocity], [setAngularVelocity] or the force
  /// methods, which write straight through.
  ///
  /// Treating them as an input would silently undo every impulse:
  /// `applyImpulse` changes Box2D's velocity while the component still holds
  /// last tick's, and the push would write the stale value back over it.
  final bodyLinearVelocityX = Field.float64();

  /// The Y component of the solver's linear velocity. **Read-only** - see
  /// [bodyLinearVelocityX].
  final bodyLinearVelocityY = Field.float64();

  /// The solver's angular velocity in radians per second, refreshed every
  /// tick. **Read-only** - see [bodyLinearVelocityX], and use
  /// [setAngularVelocity] or [applyTorque] to change it.
  final bodyAngularVelocity = Field.float64();

  /// Multiplier on world gravity for this body alone. Defaults to 1 for the
  /// same reason `Transform2D.transformScaleX` does: 0 is a degenerate value
  /// that would silently make every body float, with nothing saying why.
  final bodyGravityScale = Field.float64(1);

  /// How fast this body loses linear speed with nothing acting on it. 0 is
  /// no damping at all; a small value gives the drift of air resistance.
  final bodyLinearDamping = Field.float64();

  /// The same, for spin.
  final bodyAngularDamping = Field.float64();

  /// Whether the solver refuses to rotate this body. On for a character that
  /// should stay upright whatever it walks into.
  final bodyFixedRotation = Field.boolean();

  /// Whether this body gets continuous collision detection, the fix for a
  /// fast body tunnelling through a thin wall between two steps.
  ///
  /// It costs real solver time, so it is off by default and belongs on
  /// projectiles instead of on everything that happens to move quickly.
  final bodyIsBullet = Field.boolean();

  // --- sync cache -----------------------------------------------------------
  //
  // The last transform this body exchanged with Box2D. Compared against the
  // live Transform2D to answer "did gameplay move this?" without a second
  // "dirty" flag that something would eventually forget to set (the
  // one-fact-one-place rule - derive it rather than store a fact that must be
  // kept in step).
  //
  // Same mechanism WorldTransform2D already uses for change detection, and
  // for the same reason: comparing a handful of fields beats redoing the
  // work.
  //
  // For a body the solver moves, written after every pull, so the comparison
  // is against what Box2D last reported and never against what was last
  // pushed in. That direction is what keeps b2MakeRot's approximation error
  // from ever reading as a gameplay edit.
  //
  // A static body has no pull to be written after - its transform is never
  // read back - so its cache is written from the value being pushed instead.
  // That is safe here and only here: the pushed value is also the one left
  // standing in Transform2D, so the next comparison is against itself.

  // NaN so the very first comparison always reports "changed" - NaN never
  // equals anything, including itself. The same trick, for the same reason,
  // as WorldTransform2D's own cache defaults: it removes the need for a
  // separate "have I ever synced this" flag.
  @hide
  final bodySyncedX = Field.float64(double.nan);
  @hide
  final bodySyncedY = Field.float64(double.nan);
  @hide
  final bodySyncedAngle = Field.float64(double.nan);

  /// The [BodyType2D] Box2D was last told to simulate this body as, which is
  /// what it is simulating it as - unlike the transform, the solver never
  /// changes a body's type on its own, so what it was told is the whole
  /// truth.
  ///
  /// Mirrored here because the shim exposes no `b2Body_GetType`, and reading
  /// the type back one body at a time would cost an FFI call per body per
  /// tick - the very thing `gooBodiesPushTransforms` batches away. A column
  /// makes the per-tick comparison two bits out of a row that is already
  /// being read.
  ///
  /// `Box2DPhysicsSystem._applyBodyType` is the only writer, and it is also
  /// the only caller of `gooBodySetType`, so the mirror cannot claim a type
  /// the shim was not given.
  ///
  /// The default is never read, unlike the three NaNs above. `_fill` skips a
  /// row whose handle is still 0, and `_createBody` seeds this column through
  /// `_applyBodyType` on the way past - so by the time anything compares the
  /// two, both hold what the shim was told.
  @hide
  final bodySyncedType = Field.enumOf(
    BodyType2D.values,
    BodyType2D.dynamicBody,
  );

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<RigidBody2D>();
  }

  // --- forces ---------------------------------------------------------------
  //
  // These write **straight through to Box2D** rather than into a component
  // field, and that is deliberate. A force is not state: it is accumulated by
  // the solver and cleared at the end of the step it applies to. Storing one
  // in a row would need a matching "clear it after the step" pass, and a
  // second write anywhere in the same tick would silently replace rather than
  // add - the opposite of what applying a force means.
  //
  // Writing through also means these are legal at any point in a tick, and
  // take effect on that tick's step rather than the next one - unlike a
  // transform write, which is pipelined through the published snapshot. That
  // is the *reason* to have them at all: `bodyLinearVelocityX[e] = 5` sets a
  // velocity next tick, `applyImpulse` changes motion now.
  //
  // Each is a no-op on a body that does not exist yet, so calling one from a
  // prefab's `onEntityMounted` - before the physics system has created the
  // body - is silently ignored rather than crashing. Apply forces from a
  // system, not from a mount hook.

  /// Applies a continuous force at [entity]'s centre of mass, in newtons.
  ///
  /// Scaled by the step, so this is what you want for thrust, wind or a
  /// conveyor - something pushing for as long as you keep calling it. For a
  /// one-off kick use [applyImpulse].
  void applyForce(Entity entity, double fx, double fy, {bool wake = true}) {
    final handle = bodyHandle[entity];
    if (handle == 0) return;
    box2d.gooBodyApplyForce(handle, fx, fy, wake ? 1 : 0);
  }

  /// Applies an instantaneous change in momentum at [entity]'s centre of
  /// mass, in newton-seconds. A jump, an explosion, a bullet hit.
  void applyImpulse(Entity entity, double ix, double iy, {bool wake = true}) {
    final handle = bodyHandle[entity];
    if (handle == 0) return;
    box2d.gooBodyApplyImpulse(handle, ix, iy, wake ? 1 : 0);
  }

  /// Applies a continuous torque about [entity]'s centre, in newton-metres.
  /// Positive spins the same way positive [bodyAngularVelocity] does.
  void applyTorque(Entity entity, double torque, {bool wake = true}) {
    final handle = bodyHandle[entity];
    if (handle == 0) return;
    box2d.gooBodyApplyTorque(handle, torque, wake ? 1 : 0);
  }

  /// Sets [entity]'s velocity immediately, taking effect on this tick's step.
  ///
  /// Writing [bodyLinearVelocityX]/[bodyLinearVelocityY] instead is also
  /// supported and is the right choice inside a system already reading rows -
  /// but it goes through the component snapshot and so lands on the *next*
  /// step.
  void setVelocity(Entity entity, double vx, double vy) {
    final handle = bodyHandle[entity];
    if (handle == 0) return;
    box2d.gooBodySetLinearVelocity(handle, vx, vy);
  }

  /// Sets [entity]'s angular velocity immediately. Same timing note as
  /// [setVelocity].
  void setAngularVelocity(Entity entity, double omega) {
    final handle = bodyHandle[entity];
    if (handle == 0) return;
    box2d.gooBodySetAngularVelocity(handle, omega);
  }

  /// Removes [entity] from simulation without destroying its body, or puts it
  /// back. A disabled body keeps its handle, its shapes and its transform, and
  /// simply stops moving and colliding.
  void setSimulated(Entity entity, bool simulated) {
    final handle = bodyHandle[entity];
    if (handle == 0) return;
    box2d.gooBodySetEnabled(handle, simulated ? 1 : 0);
  }
}
