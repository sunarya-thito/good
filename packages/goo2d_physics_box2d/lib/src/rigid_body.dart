import 'package:goo2d/goo2d.dart';
import 'package:goo2d_ffi_box2d/goo2d_ffi_box2d.dart';
import 'package:meta/meta.dart';

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

/// Per-prefab defaults for a [RigidBody2D], collected during the declare
/// pass and baked into the archetype's row defaults - so the common case
/// needs no `onEntityMounted` write at all.
///
/// The same shape as `ColliderDescriptor`'s `has*Collider` methods: named
/// parameters that double as that archetype's defaults.
class RigidBody2DDescriptor {
  RigidBody2DDescriptor._();

  BodyType2D _type = BodyType2D.dynamicBody;
  double _gravityScale = 1;
  double _linearDamping = 0;
  double _angularDamping = 0;
  bool _fixedRotation = false;
  bool _isBullet = false;

  /// Declares this prefab's body.
  ///
  /// [isBullet] turns on continuous collision detection, which is the fix for
  /// a fast body tunnelling through a thin wall between two steps. It costs
  /// real solver time, so it is off by default and belongs on projectiles
  /// rather than on everything that happens to move quickly.
  void has({
    BodyType2D type = BodyType2D.dynamicBody,
    double gravityScale = 1,
    double linearDamping = 0,
    double angularDamping = 0,
    bool fixedRotation = false,
    bool isBullet = false,
  }) {
    _type = type;
    _gravityScale = gravityScale;
    _linearDamping = linearDamping;
    _angularDamping = angularDamping;
    _fixedRotation = fixedRotation;
    _isBullet = isBullet;
  }
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
/// * [BodyType2D.staticBody] and [BodyType2D.kinematicBody] - **you** own the
///   transform. Write `Transform2D` and the system pushes it into Box2D.
/// * [BodyType2D.dynamicBody] - **Box2D** owns it. The solver's output is
///   written back into `Transform2D` each tick. Writing `Transform2D`
///   yourself still works and is treated as a teleport, but doing it every
///   tick would fight the solver and destroy the simulation.
///
/// A dynamic body is therefore pushed into Box2D only when its transform
/// actually differs from what was last pulled out - see [syncedX]. That is
/// not merely an optimisation: Box2D's `b2MakeRot` is an *approximation*
/// (Bhaskara rational, not libm), and round-tripping an angle through it
/// repeatedly converges on multiples of pi/4 - measured, about 27 degrees of
/// drift from 0.3 rad after 10000 cycles. Pushing back a value that was only
/// ever pulled is how that drift would get in.
/// # How a body gets created
///
/// Nothing here - `Box2DPhysicsSystem` mixes in `EntitySpawnListener` and
/// creates the body itself. This mixin is pure data.
///
/// It briefly was not: an earlier draft had this mixin implement
/// `EntityLifecycleListener` and call the system by hand, because *lifecycle*
/// events are scoped to their own prefab's composition and a `GameSystem`
/// mixing one in is never offered to any prefab's dispatcher - it compiles and
/// silently never fires. `EntitySpawnListener` is the world-observation
/// counterpart added for exactly this, and it removed the workaround along
/// with the `@mustCallSuper` obligation it imposed on every prefab that wanted
/// to override `onEntityMounted`.
mixin RigidBody2D on Component {
  /// The packed Box2D body handle, or `0` before the system has created one.
  ///
  /// Zero being "no body" is Box2D's own null convention, so the field's
  /// natural `0` default already means the right thing - nothing has to
  /// initialise it.
  ///
  /// Read-only from game code. It is `@internal`-in-spirit rather than in
  /// annotation because a game legitimately wants it for a raycast filter or
  /// a debug overlay.
  late final DataPointer<int> bodyHandle;

  /// Which [BodyType2D] this body is.
  ///
  /// Changing this at runtime is honoured: the system notices and calls
  /// Box2D's own type change rather than rebuilding the body.
  late final DataPointer<BodyType2D> bodyType;

  /// The solver's velocity, refreshed every tick. **Read-only** - these are a
  /// mirror, not an input.
  ///
  /// Assigning to them does nothing: the system pulls velocity out of Box2D
  /// each tick and never pushes it back, so the write is simply overwritten
  /// on the next step. Use [setVelocity], [setAngularVelocity] or the force
  /// methods, which write straight through.
  ///
  /// It was briefly an input, and that silently undid every impulse -
  /// `applyImpulse` changed Box2D's velocity while the component still held
  /// last tick's, and the push wrote the stale value back over it.
  late final DataPointer<double> linearVelocityX;
  late final DataPointer<double> linearVelocityY;
  late final DataPointer<double> angularVelocity;

  /// Multiplier on world gravity for this body alone. Defaults to 1 for the
  /// same reason `Transform2D.transformScaleX` does: 0 is a degenerate value
  /// that would silently make every body float, with nothing saying why.
  late final DataPointer<double> gravityScale;

  late final DataPointer<double> linearDamping;
  late final DataPointer<double> angularDamping;

  /// `0`/`1`. This engine has no boolean field kind - see `ColliderBody`'s
  /// own note on the `uint1` convention.
  late final DataPointer<bool> fixedRotation;
  late final DataPointer<bool> isBullet;

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
  // Written after every pull, so the comparison is always against what Box2D
  // last reported - never against what was last pushed in. That direction is
  // what keeps b2MakeRot's approximation error from ever reading as a
  // gameplay edit.

  @internal
  late final DataPointer<double> syncedX;
  @internal
  late final DataPointer<double> syncedY;
  @internal
  late final DataPointer<double> syncedAngle;

  /// Overridden by the prefab to configure its body. A prefab that wants a
  /// plain dynamic body with default damping does not need to override this
  /// at all - unlike `Collider2D.describeCollider`, which is abstract because
  /// a collider with no shapes would be meaningless.
  @mustCallSuper
  void describeRigidBody(RigidBody2DDescriptor descriptor) {}

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<RigidBody2D>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);

    final descriptor = RigidBody2DDescriptor._();
    describeRigidBody(descriptor);

    bodyHandle = data.hasInt64();
    bodyType = data.hasEnum(BodyType2D.values, descriptor._type);

    linearVelocityX = data.hasFloat64();
    linearVelocityY = data.hasFloat64();
    angularVelocity = data.hasFloat64();

    gravityScale = data.hasFloat64(descriptor._gravityScale);
    linearDamping = data.hasFloat64(descriptor._linearDamping);
    angularDamping = data.hasFloat64(descriptor._angularDamping);

    fixedRotation = data.hasBool(descriptor._fixedRotation);
    isBullet = data.hasBool(descriptor._isBullet);

    // NaN so the very first comparison always reports "changed" - NaN never
    // equals anything, including itself. The same trick, for the same
    // reason, as WorldTransform2D's own cache defaults: it removes the need
    // for a separate "have I ever synced this" flag.
    syncedX = data.hasFloat64(double.nan);
    syncedY = data.hasFloat64(double.nan);
    syncedAngle = data.hasFloat64(double.nan);
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
  // is the *reason* to have them at all: `linearVelocityX[e] = 5` sets a
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
  /// Positive spins the same way positive [angularVelocity] does.
  void applyTorque(Entity entity, double torque, {bool wake = true}) {
    final handle = bodyHandle[entity];
    if (handle == 0) return;
    box2d.gooBodyApplyTorque(handle, torque, wake ? 1 : 0);
  }

  /// Sets [entity]'s velocity immediately, taking effect on this tick's step.
  ///
  /// Writing [linearVelocityX]/[linearVelocityY] instead is also supported and
  /// is the right choice inside a system that is already reading rows - but it
  /// goes through the component snapshot and so lands on the *next* step.
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
