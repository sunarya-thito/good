import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_ffi_box2d/goo2d_ffi_box2d.dart';
import 'package:meta/meta.dart';

import 'effector.dart';
import 'effectors.dart';
import 'joint.dart';
import 'rigid_body.dart';

/// Steps a Box2D world in lockstep with `good`'s fixed tick, creating one
/// Box2D body per `RigidBody2D` entity and one Box2D shape per
/// `ColliderBody` that entity declared.
///
/// Declared like any other system:
///
/// ```dart
/// @override
/// void describeSystems(SystemDescriptor descriptor) {
///   super.describeSystems(descriptor);
///   physics = descriptor.has(Box2DPhysicsSystem.new);
/// }
/// ```
///
/// # Where the native state lives
///
/// The world handle is created **lazily, on first use**, and never during a
/// declare pass. `Game` runs every `describe*` on the main isolate and then
/// hands the whole object graph to the game isolate by deep copy, so a world
/// created at declare time would be created by the copy that never simulates
/// and then inherited - leaving two copies believing they own one world, and
/// `stop()` destroying it out from under nothing.
///
/// Creating it on first body creation puts it on the simulating copy, which
/// is the only copy that ever mounts an entity or runs a tick. The handle is
/// a plain `int`, so it *would* cross the copy harmlessly; it is simply
/// never non-zero on the side that does not simulate.
///
/// (Isolates share one process, so the native memory itself would be
/// reachable from either side. Box2D is not thread-safe, which is the real
/// reason only one copy may ever touch it.)
///
/// # Ordering: this system runs FIRST, and it has to
///
/// `compareTo` sorts this system before **every** other system - which is
/// normally the wrong shape (`WorldTransformSystem`'s doc argues against
/// dragging systems with no opinion into an order they never asked for).
/// Physics is the exception, for a concrete reason:
///
/// This system writes `Transform2D` on every tick, for every simulated body.
/// A gameplay system that also writes a transform - a teleport, a respawn -
/// writes into the *same* write slot in the same tick, so whichever runs
/// later wins. If physics ran later, every gameplay transform write would be
/// silently overwritten by the solver's result and simply never take effect.
///
/// Reads are unaffected by order either way: `_readRow` always serves the
/// last *published* snapshot, so a system reading a transform sees the
/// previous tick's value no matter where it sits. Only writes conflict, and
/// putting physics first is what makes gameplay's write the winner - picked
/// up by the next tick's push.
class Box2DPhysicsSystem extends GameSystem
    with
        FixedTickable,
        EntitySpawnListener,
        SceneLoadListener,
        GameSystemLifecycleListener {
  Box2DPhysicsSystem({
    this.gravityX = 0,
    this.gravityY = -10,
    this.subStepCount = 4,
    this.workerCount = 1,
  });

  /// World gravity, in metres per second squared.
  ///
  /// **Negative [gravityY] is down, because goo2d's world +y is up.** A body
  /// under the default falls toward a smaller y, and the camera is what turns
  /// that into "down the screen" - see `CameraProjection`.
  ///
  /// This is Box2D's own convention, unchanged: goo2d, Box2D and goo3d all
  /// put +y up, so the solver's numbers are this engine's numbers and nothing
  /// between them flips a sign. Gravity, a body's velocity, an applied force
  /// and a joint anchor all mean here exactly what they mean in Box2D's
  /// documentation and samples.
  ///
  /// The magnitude is 10 and not 9.81, matching Box2D; this is a game engine,
  /// not a geodesy package.
  final double gravityX;

  /// The Y component of world gravity, in metres per second squared. Negative
  /// pulls down, since +y is up - see [gravityX].
  final double gravityY;

  /// Box2D's solver iteration count per step. 4 is upstream's recommended
  /// default; raising it trades time for stiffer stacks.
  final int subStepCount;

  /// Threads the solver may spread a step across. **1 by default**, which
  /// creates no threads at all and is exactly the behaviour every test here
  /// measures - raising it is opt-in.
  ///
  /// Measured on this project's AOT bench, a dense 5000-body stack
  /// (`tool/physics_bench.dart`, desktop, 8 physical cores):
  ///
  /// ```
  ///   workers      step   speedup
  ///         1   5347.9us     1.00x
  ///         2   3943.3us     1.45x
  ///         4   2461.6us     2.32x
  ///         8   1969.4us     2.90x
  /// ```
  ///
  /// End to end through the ECS, on the physics demo in profile mode - the
  /// number that actually matters, since the bench above is the solver alone:
  ///
  /// ```
  ///   awake bodies    solve 1 thread    solve 8 threads    sim fps
  ///           4000           3.77 ms            1.17 ms    60.4 -> 62.5
  ///          20000          30.73 ms            8.86 ms     3.8 -> 8.1
  /// ```
  ///
  /// **It only helps a scene that is awake.** A settled pile sleeps and costs
  /// almost nothing on one thread already, so threading buys nothing there;
  /// what it buys is headroom for the moments when everything is moving. At
  /// 8000 *settled* bodies the solve is 0.02 ms either way.
  ///
  /// It does not make 20 000 awake bodies a 60 Hz scene: that frame is still
  /// ~13 ms of physics plus ~5 ms of other systems per step. What it does is
  /// move Box2D out of first place.
  ///
  /// Box2D's own guidance is that only performance cores help - efficiency
  /// cores and hyper-threading "provide little benefit and may even harm
  /// performance" - so more workers than physical cores usually costs time
  /// instead of saving it. Nothing here picks a count for you: the right
  /// number depends on what else the game is doing with those cores, which
  /// this system cannot know.
  final int workerCount;

  /// Whether to dispatch `onCollisionStay2D`/`onTriggerStay2D`.
  ///
  /// **This is the expensive phase, and the only one that is O(contacts) on
  /// every tick.** Enter and exit fire only on transitions, which are rare
  /// once a scene settles; stay fires for every touching pair, every tick,
  /// to both sides. A resting pile of a few thousand bodies is tens of
  /// thousands of dispatches per tick that most games never read.
  ///
  /// Left on by default for parity with Unity, but turn it off if nothing
  /// overrides those two methods - it costs nothing to keep enter/exit.
  bool dispatchStayEvents = true;

  /// Rotation difference below which a body is considered not to have been
  /// moved by gameplay.
  ///
  /// **Must exceed Box2D's own angle round-trip error**, measured at
  /// 1.658e-3 rad across 20000 angles - `b2MakeRot` is a Bhaskara rational
  /// approximation, not libm. Below this threshold the approximation itself
  /// would read as a gameplay edit on every tick, the push would happen
  /// anyway, and the drift this whole mechanism exists to prevent would
  /// arrive by the front door. See `goo2d_ffi_box2d`'s README.
  ///
  /// For static bodies scripted with sub-epsilon rotation per tick, this causes
  /// angle changes to accumulate in `Transform2D` and sync to Box2D in steps
  /// once the accumulated delta exceeds this threshold. Moving platforms or
  /// continuously rotating bodies should use [BodyType2D.kinematicBody] instead.
  static const double angleEpsilon = 5e-3;

  /// Position difference below which a body is considered not to have been
  /// moved by gameplay. Positions round-trip through `float32`, so the
  /// error here is ordinary narrowing, not an approximation.
  static const double positionEpsilon = 1e-4;

  /// One Box2D world per loaded scene, by `Scene.slot`.
  ///
  /// **A scene is this engine's isolation boundary, and physics is the last
  /// subsystem to say so.** Hierarchy edges refuse to cross a scene, pages
  /// carry `ownerSceneSlot` and are freed per scene, and a view draws only the
  /// scene its camera occupies. One world for the whole game made physics the
  /// exception: a dynamic body in one scene rested on static geometry in
  /// another, and `overlapBox` returned shapes from both interleaved, with
  /// `layerMask` the only way to tell them apart - a budget that exists for
  /// something else entirely (#106).
  ///
  /// Created on demand by [worldOf] and destroyed in [onSceneUnloaded], so a
  /// scene that declares no body never makes one.
  final Map<int, int> _worlds = <int, int>{};

  // Transform2D is required, not optional: a body with no transform has
  // nowhere to report its position, and silently skipping such an entity
  // would look exactly like physics not working.
  @internal
  final bodies = Query.where()
      .withAll(RigidBody2D, Transform2D)
      .withOptional(Collider2D)
      .build();

  // Scratch buffers for the bulk transfer. Allocated once, grown only when
  // the population outgrows them - never per tick (the no-allocation rule).
  //
  // Native rather than Dart-heap because they are handed straight to the
  // shim. They are deliberately NOT cached typed-data views over the memory
  // pool: a cached view is copied by value across Isolate.spawn, and more
  // importantly the pool is bit-packed, so a C-side mirror of a row would be
  // a second copy of a layout that must agree with data_layout.dart by hand.
  /// Every simulated body, in slot order. Used for the *pull*, which must
  /// read back every body regardless of whether it was pushed.
  Pointer<Int64> _handles = nullptr;

  /// The same slots, but zeroed wherever the body should not be pushed - the
  /// shim skips a null handle, so "push only what gameplay changed" needs no
  /// second call and no compaction.
  ///
  /// **A separate array, and it has to be.** Zeroing entries of [_handles]
  /// instead would make the pull skip exactly the bodies that were not
  /// pushed - so a dynamic body nobody had touched would never be read back
  /// and would appear frozen at its spawn position. That is precisely the
  /// bug the falling-body tests caught.
  Pointer<Int64> _pushHandles = nullptr;

  /// The same slots again, zeroed wherever the body is static - so the
  /// transform pull skips exactly the bodies whose pulled transform
  /// [_writeBack] was going to discard.
  ///
  /// A static body's transform is an input, and since #74 the pull's answer
  /// for one is thrown away on arrival. The pull still ran, though, because
  /// [_handles] drove it and the velocity pull alike, and the velocity mirror
  /// is load-bearing: #67 needs a body turned static to report zero. Hence a
  /// third array and not a filter on the second.
  ///
  /// Zeroed and not compacted, which is what keeps this cheap. The shim skips
  /// a null handle, so every surviving index still lines up with the slot it
  /// came from and [_writeBack] needs no second mapping to find its row. A
  /// compacted array would save another ~0.5 ns per static body and cost that
  /// mapping; measured, it was not worth it (#76).
  Pointer<Int64> _pullTransformHandles = nullptr;

  Pointer<Float> _transforms = nullptr;
  Pointer<Float> _velocities = nullptr;
  int _capacity = 0;

  /// Entities in the same slot order as the scratch buffers, so the pull can
  /// write each result back to the row it came from without a second walk.
  List<Entity> _slots = const [];

  /// Which entity and which declared collider each Box2D shape belongs to,
  /// indexed by the shape handle's own dense slot.
  ///
  /// **No `userData` is involved.** Box2D's per-shape `void* userData` is
  /// 4 bytes on 32-bit Android, and an `Entity` packs all 64 bits, so
  /// stashing one there would truncate silently. The shape
  /// handle's high 32 bits are `index1` (see `b2StoreShapeId`), which Box2D's
  /// id pool keeps dense and reuses - exactly the property an index into a
  /// flat list wants. Resolving a contact is then one indexed read.
  ///
  /// One small object per shape, not two parallel lists: it is allocated
  /// once at shape creation, never on the hot path, and two lists that must
  /// agree by index is the coupling the one-fact-one-place rule describes.
  List<_ShapeOwner?> _shapeOwners = <_ShapeOwner?>[];

  /// Drained contact/sensor records, 3 int64 each: [kind, shapeA, shapeB].
  Pointer<Int64> _events = nullptr;
  int _eventCapacity = 0;

  /// The pairs currently touching, as parallel shape handles. Box2D reports
  /// only transitions, so "still touching" has to be maintained here for
  /// `onCollisionStay2D`/`onTriggerStay2D` to exist at all.
  ///
  /// Parallel `Int64List`s, not a `Set` of packed pairs: two int64 handles do
  /// not pack into one int, and a `Set<int>` of a hash would have to handle
  /// collisions. Removal is a linear scan plus swap-with-last, which is fine
  /// at realistic contact counts - contacts are bounded by what is touching,
  /// not by body count.
  Int64List _touchingA = Int64List(0);
  Int64List _touchingB = Int64List(0);
  Uint8List _touchingSensor = Uint8List(0);
  int _touchingCount = 0;

  /// One reused event for every dispatch - see `Collision2DEvent`'s doc.
  final Collision2DEvent _event = Collision2DEvent();

  /// How many pairs are currently touching, as tracked for the stay events.
  ///
  /// The companion to a step time: a step time on its own cannot distinguish
  /// "a lot of bodies" from "a lot of bodies overlapping each other", and
  /// Box2D's cost follows the contact graph, not the population.
  int get touchingPairCount => _touchingCount;

  /// Threads the **live world** is using, asked of Box2D and not read back
  /// off [workerCount].
  ///
  /// Those two can disagree, and the difference is invisible in a step time.
  /// [workerCount] is what this object was constructed with; this is what the
  /// world got. 0 means no world exists yet.
  /// Every world this system makes is built with the same [workerCount], so
  /// any of them answers for all; 0 when none exists yet.
  int get activeWorkerCount =>
      _worlds.isEmpty ? 0 : box2d.gooWorldWorkerCount(_worlds.values.first);

  /// Bodies Box2D is still integrating, as opposed to asleep.
  ///
  /// **The number that says whether a heavy scene is heavy or merely
  /// agitated.** A settled pile sleeps and costs almost nothing; one that
  /// keeps twitching - bouncy restitution, bodies with nowhere to separate
  /// to, something being teleported into it every tick - pays full price
  /// forever. Those have completely different fixes and the same step time.
  /// Summed over every loaded scene's world, so this reads the same for a
  /// one-scene game as it always did.
  int get awakeBodyCount {
    var total = 0;
    for (final world in _worlds.values) {
      total += box2d.gooWorldAwakeBodyCount(world);
    }
    return total;
  }

  /// Box2D's own view of the world: `[bodies, shapes, contacts, joints,
  /// islands]`, written into [into] (at least 5 long) and returned.
  ///
  /// `contacts` here are **potential** (broad-phase) pairs, not touching
  /// ones - see [touchingPairCount] for those. A count that climbs far faster
  /// than the population is the signature of overlap.
  Int32List counters(Int32List into) {
    final n = into.length < 5 ? into.length : 5;
    for (var i = 0; i < n; i++) {
      into[i] = 0;
    }
    if (_worlds.isEmpty) return into;
    _countersOut ??= calloc<Int32>(5);
    final out = _countersOut!;
    // Summed over every world. All five are counts of things, so they add;
    // for a game with one scene this is what it always reported.
    for (final world in _worlds.values) {
      box2d.gooWorldCounters(world, out, 5);
      for (var i = 0; i < n; i++) {
        into[i] += out[i];
      }
    }
    return into;
  }

  Pointer<Int32>? _countersOut;

  // Effector entities are a different population from bodies: a wind zone
  // has a region and a transform and usually no RigidBody2D at all.
  @internal
  final effectorZones = Query.all(Effector2D, Transform2D);

  /// Applies every declared effector, once, before the step.
  ///
  /// Ordering between effectors is unspecified, and safe to leave that way.
  /// Forces accumulate, and addition is commutative, so two overlapping zones
  /// produce the same total whichever runs first, which is what makes walking
  /// them in archetype order sound.
  ///
  /// The region is resolved as an axis-aligned box around the entity's
  /// `Transform2D`, so a rotated effector zone acts through its bounding box.
  /// That matches the primitives underneath, which are all broad-phase AABB
  /// queries - an exact boundary is not something a force field's player can
  /// see anyway.
  void _applyEffectors() {
    for (final group in effectorZones.groups()) {
      final zone = group<Effector2D>();
      if (zone.effectors.isEmpty) continue;
      final transform = group<Transform2D>();
      for (final entity in group) {
        final centreX = transform.transformOffsetX[entity];
        final centreY = transform.transformOffsetY[entity];
        for (var i = 0; i < zone.effectors.length; i++) {
          final effector = zone.effectors[i];
          if (!effector.enable[entity]) continue;
          _applyOne(effector, entity, centreX, centreY);
        }
      }
    }
  }

  /// The `sealed` dispatch. Adding a fifth effector kind fails to compile here
  /// until it is handled, which is the whole reason [Effector] is sealed.
  void _applyOne(
    Effector effector,
    Entity entity,
    double centreX,
    double centreY,
  ) {
    final region = effector.region;
    final offsetX = centreX + region.offsetX[entity];
    final offsetY = centreY + region.offsetY[entity];
    final double halfWidth;
    final double halfHeight;
    switch (region) {
      case BoxBody():
        halfWidth = region.halfWidth[entity];
        halfHeight = region.halfHeight[entity];
      case CircleBody():
        halfWidth = region.radius[entity];
        halfHeight = halfWidth;
      case CapsuleBody() || PolygonBody():
        // Deliberately not silently approximated: a capsule or polygon region
        // would act through a bounding box that is visibly bigger than the
        // shape drawn, and a force field that reaches further than it looks is
        // worse than one that refuses to be declared.
        assert(
          false,
          'an effector region must be a box or a circle collider - '
          '\${region.runtimeType} has no meaningful axis-aligned extent for '
          'this to query. Declare the zone with hasBoxCollider or '
          'hasCircleCollider.',
        );
        return;
    }

    final minX = offsetX - halfWidth;
    final maxX = offsetX + halfWidth;
    final minY = offsetY - halfHeight;
    final maxY = offsetY + halfHeight;
    final layerMask = effector.layerMask[entity];
    // A declared effector acts in its own scene and nowhere else: it reaches
    // bodies through an overlap query, and that query belongs to one world.
    final scene = entity.scene;

    switch (effector) {
      case AreaEffector():
        areaEffector(
          scene,
          minX,
          minY,
          maxX,
          maxY,
          forceX: effector.forceX[entity],
          forceY: effector.forceY[entity],
          torque: effector.torque[entity],
          layerMask: layerMask,
        );
      case PointEffector():
        pointEffector(
          scene,
          offsetX,
          offsetY,
          radius: halfWidth > halfHeight ? halfWidth : halfHeight,
          force: effector.force[entity],
          minDistance: effector.minDistance[entity],
          layerMask: layerMask,
        );
      case BuoyancyEffector():
        // The water line is the region's *top* edge, which is its largest y:
        // goo2d's +y is up, and [buoyancyEffector] hangs the fluid below the
        // surface it is given. Passing minY put the water a whole region
        // height underneath the region it was declared on - see
        // BuoyancyEffector's own doc, and on why it is horizontal regardless.
        buoyancyEffector(
          scene,
          minX,
          maxX,
          surfaceY: maxY,
          depth: maxY - minY,
          density: effector.density[entity],
          linearDrag: effector.linearDrag[entity],
          angularDrag: effector.angularDrag[entity],
          layerMask: layerMask,
        );
      case SurfaceEffector():
        surfaceEffector(
          scene,
          minX,
          minY,
          maxX,
          maxY,
          speed: effector.speed[entity],
          speedY: effector.speedY[entity],
          force: effector.force[entity],
          layerMask: layerMask,
        );
    }
  }

  @override
  int compareTo(GameSystem other) => other is Box2DPhysicsSystem ? 0 : -1;

  /// The Box2D world [scene]'s bodies live in, created on first use.
  ///
  /// There is no world-for-the-game to ask for. A body belongs to an entity,
  /// an entity belongs to exactly one scene, and that is what decides which
  /// solver it is in.
  int worldOf(Scene scene) => _worldOfSlot(scene.slot);

  int _worldOfSlot(int slot) {
    final existing = _worlds[slot];
    if (existing != null) return existing;
    {
      // The threads, if any, are created here rather than in the constructor
      // - and that matters as much as the world does. `Game` runs every
      // declare pass on the main isolate and deep-copies the graph to the
      // game isolate, so a pool built at construction time would be built by
      // the copy that never simulates, and the copy that does would inherit a
      // handle to threads it does not own.
      final created = workerCount > 1
          ? box2d.gooWorldCreateThreaded(gravityX, gravityY, workerCount)
          : box2d.gooWorldCreate(gravityX, gravityY);
      _worlds[slot] = created;
      return created;
    }
  }

  // --- lifecycle ------------------------------------------------------------

  /// Creates a Box2D body for any spawned entity that has a [RigidBody2D].
  ///
  /// `EntitySpawnListener` hears **every** entity in the game, so filtering by
  /// archetype here is the expected shape at this scope, not a smell - see
  /// that mixin's doc.
  /// Entities that need a Box2D body, created on the **next** fixed step.
  ///
  /// See [onEntitySpawned] for why creation cannot happen on the spawn.
  final List<Entity> _pendingCreate = <Entity>[];

  /// Bodies created during the **current** tick, by entity.
  ///
  /// A second home for something `bodyHandle` already holds, which normally
  /// this codebase forbids (the one-fact-one-place rule) - justified because
  /// the component field genuinely cannot answer the question yet. Its write is
  /// not published until the tick ends, so between creation and the end of that
  /// tick the row reports 0 and nothing else knows the body exists.
  ///
  /// Cleared at the end of every fixed step, so it holds at most one tick's
  /// worth of spawns and never grows with the population.
  final Map<Entity, int> _freshHandles = <Entity, int>{};

  @override
  void onEntitySpawned(Entity entity) {
    if (!entity.has<RigidBody2D>()) return;

    if (!entity.has<Transform2D>()) {
      assert(
        false,
        'A prefab mixing in RigidBody2D must also mix in Transform2D - a '
        'body with no transform has nowhere to report its position. '
        '(archetype ${entity.archetypeId})',
      );
      return;
    }

    // **Queued, not created here, and that is load-bearing.**
    //
    // Creating the body on the spawn means reading the entity's transform and
    // collider in the *same tick* they were written - a prefab sets its
    // position and size in `onEntityMounted`, which the engine fires just
    // before this. But `_readRow` serves the last **published** snapshot, so a
    // same-tick write is invisible to a same-tick read on any page that has
    // published before. A freshly allocated row therefore reads back whatever
    // its **previous occupant** left there.
    //
    // That worked for a long time by accident: it is correct on a page that
    // has never published (the read falls through to the write slot), which is
    // every early spawn and every test fixture. It breaks the moment a row is
    // recycled - and recycling is the normal case in any game that spawns and
    // destroys.
    //
    // It also hid itself well. A body's *position* is pushed into Box2D every
    // tick for static and kinematic bodies, so a wrong spawn position corrects
    // itself on the next step and looks fine. A **shape's extents are fixed at
    // creation** and are never pushed again, so only the size stayed wrong. In
    // the physics demo that produced a floor built at the previous arena's
    // width while the sprite drew the new one: visibly a wide floor, actually
    // a narrow collider, and bodies pouring through the gap into the void.
    //
    // Deferring one tick puts creation after `commitTick` has published the
    // mount-time writes, so it reads exactly what the prefab wrote. The cost
    // is that a body does not exist until the next fixed step, which is the
    // same one-tick pipeline every other read in this engine has.
    _pendingCreate.add(entity);
  }

  /// Destroys the world [scene] owned, and every body and joint in it.
  ///
  /// **Before its entities are despawned**, which is the ordering
  /// `SceneLoadListener` gives and the reason this is safe: one
  /// `gooWorldDestroy` takes the bodies with it, so there is no per-entity
  /// teardown to get wrong and nothing left behind if a handle was written
  /// this tick and not yet published.
  ///
  /// It does mean [onEntityDespawned] then runs for every entity of a scene
  /// whose world is already gone. That path checks, and it has to: calling
  /// `gooBodyDestroy` on a handle in a destroyed world is a native
  /// use-after-free, which kills the isolate with no Dart exception and no
  /// output - the failure mode this file already carries a scar from.
  @override
  void onSceneUnloaded(Scene scene) {
    final world = _worlds.remove(scene.slot);
    if (world != null && world != 0) box2d.gooWorldDestroy(world);
  }

  /// Creates the bodies queued by [onEntitySpawned] since the last step.
  void _createPending() {
    if (_pendingCreate.isEmpty) return;
    for (var i = 0; i < _pendingCreate.length; i++) {
      final entity = _pendingCreate[i];
      // Destroyed before it ever got a body - `onEntityDespawned` clears the
      // queue, but an entity whose whole scene went away does not come
      // through there with a resolvable archetype.
      if (!entity.has<RigidBody2D>() || !entity.has<Transform2D>()) continue;
      final body = entity<RigidBody2D>().component;
      final transform = entity<Transform2D>().component;
      // Its scene unloaded between the spawn and this step, so there is no
      // world to build it in and no entity left to build it for.
      if (entity.sceneSlot < 0) continue;
      _createBody(entity, body, transform);
    }
    _pendingCreate.clear();
  }

  @override
  void onEntityDespawned(Entity entity) {
    if (!entity.has<RigidBody2D>()) return;
    final body = entity<RigidBody2D>().component;

    // Spawned and destroyed inside one tick, before its body was ever made.
    // Leaving it queued would create a body for a freed row on the next step.
    if (_pendingCreate.isNotEmpty) _pendingCreate.remove(entity);

    // If this entity's world is already gone there is nothing to destroy, and
    // trying is a use-after-free: b2DestroyBody would walk a freed world.
    //
    // Two ordinary paths reach here with no world, neither of them misuse.
    // [dispose] destroys every world, and stopping a game afterwards unloads
    // its scenes, which unmounts every entity and lands here. And
    // [onSceneUnloaded] destroys one scene's world *before* that scene's
    // entities are despawned, so every one of them arrives here with its
    // world already released.
    //
    // It cost real debugging time precisely because a native crash kills the
    // isolate with no Dart exception and no output at all: the test simply
    // "did not complete".
    //
    // `sceneSlot` reads the row's page, and answers -1 once that page is gone,
    // so a slot that was never a world and a slot whose world has been
    // destroyed both miss the same way.
    if (!_worlds.containsKey(entity.sceneSlot)) return;

    // **The freshly created map is consulted first, and it has to be.**
    //
    // `bodyHandle[entity]` is an ordinary component read, so it serves the
    // last *published* snapshot. A body created earlier in **this** tick had
    // its handle written this tick, and that write is not published until the
    // tick ends - so this read returns 0 and the body is silently never
    // destroyed. The entity goes away, its sprite with it, and an invisible
    // collider is left behind in the world forever.
    //
    // It is not a corner case: the physics demo's arena rebuild destroys and
    // respawns its walls, and dragging the slider fast enough to rebuild on
    // consecutive ticks leaves a ghost arena behind each time. That presents
    // as "there is an invisible small container in the middle of the scene",
    // which is exactly how it was reported.
    final handle = _freshHandles[entity] ?? body.bodyHandle[entity];
    if (handle != 0) {
      // Destroying the body destroys its shapes with it, so the colliders
      // need no separate teardown.
      box2d.gooBodyDestroy(handle);
    }

    // `bodyHandle` is deliberately NOT cleared here. Unmount runs *outside*
    // a tick window, and `_writeRow` asserts that all mutation happens
    // between beginTick() and commitTick() - a write here is one the next
    // beginTick would silently discard anyway, which is exactly what that
    // assert exists to catch. The row is being torn down regardless, so
    // there is nothing the stale handle can be read through: `_fill` only
    // ever walks live rows.
  }

  void _createBody(Entity entity, RigidBody2D body, Transform2D transform) {
    final type = body.bodyType[entity];
    final handle = box2d.gooBodyCreate(
      // Routed by the entity, not by anything ambient: this is the line that
      // decides which solver a body is in, and it reads the answer off the row.
      _worldOfSlot(entity.sceneSlot),
      type.index,
      transform.transformOffsetX[entity],
      transform.transformOffsetY[entity],
      transform.transformRotation[entity],
    );
    body.bodyHandle[entity] = handle;
    // Readable *this* tick, which the row above will not be until it is
    // published - see [_freshHandles].
    _freshHandles[entity] = handle;

    // Seeds `bodySyncedType` through the same call that will later change it,
    // rather than assigning the column here, so that one method is the only
    // writer of the mirror and it cannot disagree with what the shim was
    // told. The shim call itself does nothing: `gooBodyCreate` was just
    // handed this exact value and `b2Body_SetType` returns immediately when
    // the type already matches.
    _applyBodyType(body, entity, handle, type);

    box2d
      ..gooBodySetGravityScale(handle, body.bodyGravityScale[entity])
      ..gooBodySetDamping(
        handle,
        body.bodyLinearDamping[entity],
        body.bodyAngularDamping[entity],
      )
      ..gooBodySetFixedRotation(handle, body.bodyFixedRotation[entity] ? 1 : 0)
      ..gooBodySetBullet(handle, body.bodyIsBullet[entity] ? 1 : 0);

    // Seed the sync cache from what was just pushed in, so a body does not
    // read as "gameplay moved me" on its very first tick.
    body.bodySyncedX[entity] = transform.transformOffsetX[entity];
    body.bodySyncedY[entity] = transform.transformOffsetY[entity];
    body.bodySyncedAngle[entity] = transform.transformRotation[entity];

    if (entity.has<Collider2D>()) {
      final shapes = entity<Collider2D>().component.bodies;
      for (var i = 0; i < shapes.length; i++) {
        _createShape(entity, handle, shapes[i]);
      }
    }
  }

  /// Translates one goo2d [ColliderBody] into a Box2D shape.
  ///
  /// A `switch` over the sealed hierarchy, so adding a shape kind to
  /// `collider.dart` fails to compile here until it is handled - which is
  /// exactly why `ColliderBody` was made `sealed`, and its own class doc says
  /// so, naming this as the intended use.
  void _createShape(Entity entity, int handle, ColliderBody shape) {
    final created = _addShape(entity, handle, shape);
    if (created != 0) _rememberShape(created, entity, shape);
  }

  /// Records which entity and collider a shape belongs to, indexed by the
  /// handle's dense `index1` slot (its high 32 bits).
  void _rememberShape(int shapeHandle, Entity entity, ColliderBody shape) {
    final slot = shapeHandle >> 32;
    while (_shapeOwners.length <= slot) {
      _shapeOwners.add(null);
    }
    // Overwrites whatever previously held this slot, which is correct:
    // Box2D only reuses an index after the old shape is destroyed.
    _shapeOwners[slot] = _ShapeOwner(
      entity,
      shape,
      entity.has<CollisionListener>()
          ? entity<CollisionListener>().component
          : null,
    );
  }

  _ShapeOwner? _ownerOf(int shapeHandle) {
    final slot = shapeHandle >> 32;
    if (slot < 0 || slot >= _shapeOwners.length) return null;
    return _shapeOwners[slot];
  }

  int _addShape(Entity entity, int handle, ColliderBody shape) {
    final density = shape.density[entity];
    final friction = shape.friction[entity];
    final restitution = shape.restitution[entity];
    final isSensor = shape.isTrigger[entity] ? 1 : 0;

    // goo2d stores `layer` as a bit index and `excludeLayers` as a mask of
    // layers to ignore; Box2D wants a category bit and a mask of categories
    // to accept. A disabled body is expressed as a zero mask, since Box2D v3
    // has no per-shape enable flag.
    final category = 1 << shape.layer[entity];
    final mask = shape.enable[entity] ? ~shape.excludeLayers[entity] : 0;

    final offsetX = shape.offsetX[entity];
    final offsetY = shape.offsetY[entity];

    switch (shape) {
      case CircleBody():
        return box2d.gooShapeAddCircle(
          handle,
          offsetX,
          offsetY,
          shape.radius[entity],
          density,
          friction,
          restitution,
          category,
          mask,
          isSensor,
        );
      case BoxBody():
        return box2d.gooShapeAddBox(
          handle,
          offsetX,
          offsetY,
          shape.halfWidth[entity],
          shape.halfHeight[entity],
          0,
          density,
          friction,
          restitution,
          category,
          mask,
          isSensor,
        );
      case CapsuleBody():
        return box2d.gooShapeAddCapsule(
          handle,
          offsetX,
          offsetY,
          shape.radius[entity],
          shape.halfHeight[entity],
          density,
          friction,
          restitution,
          category,
          mask,
          isSensor,
        );
      case PolygonBody():
        return _createPolygonShape(
          entity,
          handle,
          shape,
          density,
          friction,
          restitution,
          category,
          mask,
          isSensor,
        );
    }
  }

  /// Box2D's `b2_maxPolygonVertices`. Not re-exported by the shim, so it is
  /// repeated here; a mismatch shows up as the throw below firing on a shape
  /// the solver would have taken.
  static const int _maxPolygonVertices = 8;

  int _createPolygonShape(
    Entity entity,
    int handle,
    PolygonBody shape,
    double density,
    double friction,
    double restitution,
    int category,
    int mask,
    int isSensor,
  ) {
    final count = shape.pointCount[entity];
    if (count < 3) {
      // Matches PolygonBody.containsLocalPoint: fewer than three points
      // encloses no area, including the default empty polygon a prefab that
      // forgot to populate its points leaves behind.
      return 0;
    }
    if (count > _maxPolygonVertices) {
      // goo2d accepts a longer outline than this, because containment there
      // is even-odd crossing and handles any shape. Box2D's own cap is 8, so
      // this is the layer that has to refuse it, and it names the entity
      // because a truncated shape would otherwise just collide oddly.
      throw StateError(
        'Box2D takes at most $_maxPolygonVertices vertices in one polygon, '
        'and entity $entity declares $count. Split the outline across several '
        'colliders, or keep the long one for picking and give the body a '
        'simpler shape.',
      );
    }

    // Reuses the transform scratch, which is always at least 3 floats per
    // slot and so comfortably larger than the 16 floats an 8-gon needs -
    // asserted rather than assumed.
    _ensureCapacity(_slots.isEmpty ? 8 : _slots.length);
    assert(
      _capacity * 3 >= count * 2,
      'the transform scratch is too small to stage a polygon',
    );

    final points = _transforms;
    for (var i = 0; i < count; i++) {
      points[i * 2] = offsetXOf(shape, entity, i);
      points[i * 2 + 1] = offsetYOf(shape, entity, i);
    }

    return box2d.gooShapeAddPolygon(
      handle,
      points,
      count,
      density,
      friction,
      restitution,
      category,
      mask,
      isSensor,
    );
  }

  /// A polygon point in body-local space: the declared vertex plus the
  /// collider's own offset, which is how `PolygonBody.containsLocalPoint`
  /// reads them too.
  @visibleForTesting
  static double offsetXOf(PolygonBody shape, Entity entity, int i) =>
      shape.pointsX.get(entity, i) + shape.offsetX[entity];

  @visibleForTesting
  static double offsetYOf(PolygonBody shape, Entity entity, int i) =>
      shape.pointsY.get(entity, i) + shape.offsetY[entity];

  // --- the tick -------------------------------------------------------------

  @override
  void onFixedUpdate() {
    // Cleared at the *start* rather than the end, so it covers every path out
    // of this method - including the early return for an empty world, which
    // is the one taken on the very tick the first bodies are created.
    _freshHandles.clear();

    // Before anything else, so a body queued last tick simulates on this one
    // and the world is complete for the rest of the step.
    _createPending();

    // After creation and before the step: a force applied outside a tick
    // window is discarded, and one applied after the step lands late. This is
    // the ordering every game used to have to reproduce by hand with a
    // compareTo against this system.
    _applyEffectors();

    final count = _fill();

    if (count == 0) {
      // Still step, so a world with only static geometry keeps a consistent
      // clock - and so `time` in Box2D does not diverge from the game's.
      _stepWorlds();
      _dispatchContacts();
      return;
    }

    // Velocity is PULLED but never pushed. It is a read-only mirror of what
    // the solver last reported; writes go through `RigidBody2D.setVelocity`
    // and the force methods, straight into Box2D.
    //
    // Pushing it unconditionally - as an earlier draft did - silently undoes
    // every impulse: `applyImpulse` changes Box2D's velocity, the component
    // still holds last tick's value, and the next push writes that stale
    // value back over the impulse. Dirty-checking it instead would need a
    // third cache and would still lose a force applied in the same tick a
    // gameplay write happened.
    // Push and pull are per *body*, so they stay one bulk call across every
    // scene; only the solve and its event queues belong to a world.
    box2d.gooBodiesPushTransforms(_pushHandles, _transforms, count);
    _stepWorlds();

    // Transforms come back through the static-zeroed array and velocities
    // through the full one - see [_pullTransformHandles]. A skipped body
    // leaves its three transform slots untouched, which is exactly right:
    // they still hold what `_fill` staged from `Transform2D`, and
    // `_writeBack` does not read them for a static body anyway.
    box2d
      ..gooBodiesPullTransforms(_pullTransformHandles, _transforms, count)
      ..gooBodiesPullVelocities(_handles, _velocities, count);
    _writeBack(count);

    _dispatchContacts();
  }

  /// Steps every loaded scene's world, each by the same fixed delta.
  ///
  /// Order across worlds is not observable: they share no body, no contact and
  /// no constraint, which is the whole point of there being more than one.
  void _stepWorlds() {
    for (final world in _worlds.values) {
      box2d.gooWorldStep(world, _stepSeconds, subStepCount);
    }
  }

  double get _stepSeconds =>
      state.game.fixedTimeStep.inMicroseconds / 1000000.0;

  /// Stages every simulated body into the scratch buffers, returning how many
  /// slots were used.
  ///
  /// A body whose transform gameplay did **not** change has its handle zeroed
  /// in the push array, which the shim skips - so "only push what changed"
  /// costs no extra call and no compaction. The entity keeps its slot, so the
  /// pull still writes back to the right row.
  int _fill() {
    var index = 0;
    for (final group in bodies.groups()) {
      final body = group<RigidBody2D>();
      final transform = group<Transform2D>();

      for (final entity in group) {
        final handle = body.bodyHandle[entity];
        if (handle == 0) continue;

        _ensureCapacity(index + 1);
        _growSlots(index + 1);
        _slots[index] = entity;

        final x = transform.transformOffsetX[entity];
        final y = transform.transformOffsetY[entity];
        final angle = transform.transformRotation[entity];

        // A `bodyType` write reaches Box2D here, before the step it should
        // take effect on. The comparison is one narrow column read against
        // another on a row already in cache - cheaper than the three float
        // reads `_movedByGameplay` does below - and the call it guards fires
        // only on the tick a type actually changes.
        final type = body.bodyType[entity];
        if (type != body.bodySyncedType[entity]) {
          _applyBodyType(body, entity, handle, type);
        }

        // Every type is pushed on the same rule: only when gameplay's
        // transform differs from the sync cache. Static and kinematic bodies
        // were pushed unconditionally until #74, which round-tripped their
        // angle through `b2MakeRot` once per tick - and that approximation
        // converges on multiples of pi/4, taking a floor authored at 0.3 rad
        // to 0.718 in 1000 ticks and to pi/4 in 10000.
        //
        // A body that just changed type does not push on that account: it is
        // already where the solver left it and the cache says so. What
        // freezes a body turned static is `_writeBack` no longer overwriting
        // its transform.
        final push = _movedByGameplay(body, entity, x, y, angle);

        if (push && type == BodyType2D.staticBody) {
          // `_writeBack` leaves a static body's transform alone, so nothing
          // on the pull side refreshes its cache and it would go on pushing
          // every tick. Caching what is about to be pushed is sound only
          // because of that: the value left in `Transform2D` is this one,
          // bit for bit, so the next comparison is exact rather than against
          // Box2D's approximation of it.
          body
            ..bodySyncedX[entity] = x
            ..bodySyncedY[entity] = y
            ..bodySyncedAngle[entity] = angle;
        }

        _handles[index] = handle;
        _pushHandles[index] = push ? handle : 0;
        // `type` is already in hand from the check above, so skipping a
        // static body's transform pull costs no extra column read here.
        _pullTransformHandles[index] = type == BodyType2D.staticBody
            ? 0
            : handle;
        _transforms[index * 3] = x;
        _transforms[index * 3 + 1] = y;
        _transforms[index * 3 + 2] = angle;

        index++;
      }
    }
    return index;
  }

  /// Points Box2D at [type] and records it as the type this body now has.
  ///
  /// The only caller of `gooBodySetType` and the only writer of
  /// [RigidBody2D.bodySyncedType], which is what keeps the mirror honest.
  ///
  /// The change is not a rebuild: `b2Body_SetType` keeps the body id, its
  /// shapes and its joints, and does the work around them - it drops the
  /// body's contacts, wakes it, moves it between the static and awake solver
  /// sets, recreates its shape proxies in the matching broad-phase tree,
  /// relinks its joints and recomputes its mass from its shapes. Nothing is
  /// left for this side to do.
  void _applyBodyType(
    RigidBody2D body,
    Entity entity,
    int handle,
    BodyType2D type,
  ) {
    box2d.gooBodySetType(handle, type.index);
    body.bodySyncedType[entity] = type;
  }

  bool _movedByGameplay(
    RigidBody2D body,
    Entity entity,
    double x,
    double y,
    double angle,
  ) {
    final lastX = body.bodySyncedX[entity];
    // NaN on a never-synced body, and NaN fails every comparison - so the
    // first tick always counts as moved, with no separate "have I synced"
    // flag to keep in step.
    if (lastX.isNaN) return true;
    if ((x - lastX).abs() > positionEpsilon) return true;
    if ((y - body.bodySyncedY[entity]).abs() > positionEpsilon) return true;
    return (angle - body.bodySyncedAngle[entity]).abs() > angleEpsilon;
  }

  /// Writes the solver's results back into `Transform2D` and refreshes the
  /// sync cache, for every body the solver actually moves. A static body
  /// gets only its velocity mirror - see the comment on the branch below.
  void _writeBack(int count) {
    Entity? previous;
    RigidBody2D? body;
    Transform2D? transform;

    for (var i = 0; i < count; i++) {
      final entity = _slots[i];

      // Resolving the archetype's component instances per row would cost the
      // ~7% of CPU that Query.groups() exists to remove. Slots are filled in
      // group order, so consecutive entities usually share an archetype and
      // this resolves once per run of them.
      if (previous == null || entity.archetypeId != previous.archetypeId) {
        body = entity<RigidBody2D>().component;
        transform = entity<Transform2D>().component;
        previous = entity;
      }

      // A static body's transform is an input, so the pulled value can only
      // be Box2D's own reading of what was pushed in - asking a question
      // whose answer is already known, and paying `b2MakeRot`'s
      // approximation error for the answer. Writing it back once per tick is
      // what took a floor authored at 0.3 rad to pi/4 in 10000 ticks (#74).
      //
      // Kinematic bodies are not this case. Gameplay sets their velocity,
      // but the solver is what integrates it into a transform, so theirs is
      // a result to be read back exactly like a dynamic body's.
      if (body!.bodyType[entity] != BodyType2D.staticBody) {
        final x = _transforms[i * 3];
        final y = _transforms[i * 3 + 1];
        final angle = _transforms[i * 3 + 2];

        transform!
          ..transformOffsetX[entity] = x
          ..transformOffsetY[entity] = y
          ..transformRotation[entity] = angle;

        body
          ..bodySyncedX[entity] = x
          ..bodySyncedY[entity] = y
          ..bodySyncedAngle[entity] = angle;
      }

      // Velocity is mirrored for every body, static included: Box2D reports
      // zero for a static one, which is what a body frozen mid-flight by a
      // type change has to read as.
      body
        ..bodyLinearVelocityX[entity] = _velocities[i * 3]
        ..bodyLinearVelocityY[entity] = _velocities[i * 3 + 1]
        ..bodyAngularVelocity[entity] = _velocities[i * 3 + 2];
    }
  }

  // --- joints ----------------------------------------------------------------
  //
  // Joints are created **imperatively**, by a system, rather than declared as
  // a component. That is a deliberate scope choice rather than an oversight:
  // a joint is a relationship between *two* entities, and a component lives
  // on one row. Expressing it declaratively means one side naming the other
  // and a rule for which side owns it, plus a story for what happens when the
  // named entity does not exist yet or has been destroyed. Ropes, ragdolls
  // and vehicles are all built at runtime anyway, where an imperative call is
  // what the code wants. A `Joint2D` component can be layered on later
  // without changing any of this.
  //
  // The returned handle is a plain packed int, so it crosses nothing and
  // needs no table. **Box2D destroys a joint when either of its bodies is
  // destroyed**, so a handle can go stale on its own; `Joint.exists` asks,
  // and every call here is a no-op on a stale one rather than a crash.

  /// Ties two bodies together at a fixed distance, optionally sprung.
  ///
  /// Ropes, springs and suspension. Anchors are in each body's **local**
  /// space - `(0, 0)` is the body's origin, which is what a caller almost
  /// always wants.
  ///
  /// [length], [minLength] and [maxLength] left at 0 keep Box2D's own
  /// defaults, and do not mean zero; a zero-length distance joint is
  /// degenerate and Box2D only catches it with an assert, which is absent
  /// from a release build.
  ///
  /// Returns 0 if either entity has no body **yet** - see [createRevoluteJoint]
  /// for why that is easy to hit.
  /// Refuses a joint whose two bodies are in different scenes.
  ///
  /// The same rule `ParentAccessor._sameScene` states for hierarchy edges, and
  /// for the same reason: whichever scene unloads first would leave the other
  /// holding a constraint into freed memory. It is spelled as a real throw
  /// and not an `assert`, which is where it differs. Hierarchy can repair a
  /// stray edge at unload; this cannot, because the bodies are in two separate
  /// `b2World`s and Box2D has no defined answer for jointing across them. What
  /// it does instead is not something to expose, so the refusal is ours and it
  /// happens before the native call.
  void _requireSameScene(Entity a, Entity b) {
    final slotA = a.sceneSlot;
    final slotB = b.sceneSlot;
    if (slotA == slotB) return;
    throw ArgumentError(
      'Cannot joint $a in scene slot $slotA to $b in scene slot $slotB. Each '
      'loaded scene simulates in its own Box2D world, so two bodies from '
      'different scenes have no solver in common and no constraint between '
      'them could be stepped. Spawn both in one scene - '
      '`a.scene.addEntity(...)` - or connect each to something in its own.',
    );
  }

  Joint createDistanceJoint(
    Entity a,
    Entity b, {
    double anchorAX = 0,
    double anchorAY = 0,
    double anchorBX = 0,
    double anchorBY = 0,
    double length = 0,
    bool enableSpring = false,
    double hertz = 0,
    double dampingRatio = 0,
    bool enableLimit = false,
    double minLength = 0,
    double maxLength = 0,
    bool collideConnected = false,
  }) {
    final handleA = _bodyHandleOf(a);
    final handleB = _bodyHandleOf(b);
    if (handleA == 0 || handleB == 0) return Joint.none;
    _requireSameScene(a, b);

    return Joint(
      box2d.gooJointCreateDistance(
        handleA,
        handleB,
        anchorAX,
        anchorAY,
        anchorBX,
        anchorBY,
        length,
        enableSpring ? 1 : 0,
        hertz,
        dampingRatio,
        enableLimit ? 1 : 0,
        minLength,
        maxLength,
        collideConnected ? 1 : 0,
      ),
    );
  }

  /// Pins two bodies to a shared pivot, optionally limited and motorised.
  ///
  /// Hinges, wheels, ragdoll joints. Anchors are in each body's **local**
  /// space, so a hinge at the point where the two overlap is the same world
  /// point expressed twice - once in each body's frame.
  ///
  /// # Both entities must already have bodies, and that takes TWO ticks
  ///
  /// Returns 0 if either does not, and the timing is easy to get wrong by one:
  ///
  ///  * tick N - `addEntity`, and whatever the caller writes to the entity's
  ///    transform. Published at the end of N.
  ///  * tick N+1 - this system reads that and creates the body, writing
  ///    `bodyHandle`. Published at the end of N+1.
  ///  * tick N+2 - **the first tick a joint can be made**, because the handle
  ///    is read through an ordinary component read and those serve the last
  ///    published snapshot.
  ///
  /// Joining at N+1 looks like it works and is the trap: on a page that has
  /// never published, a read falls through to the write slot and happens to
  /// see the fresh handle. As soon as rows are recycled that fall-through
  /// stops, and the same code silently produces no joints at all. The joints
  /// demo shows it: the first chain hangs, and every chain rebuilt afterwards
  /// falls apart.
  ///
  /// It returns 0 instead of asserting, because "not yet" is a legitimate
  /// state a caller can poll out of, but the asymmetry is worth knowing:
  /// nothing else in this class fails quietly.
  Joint createRevoluteJoint(
    Entity a,
    Entity b, {
    double anchorAX = 0,
    double anchorAY = 0,
    double anchorBX = 0,
    double anchorBY = 0,
    double referenceAngle = 0,
    bool enableLimit = false,
    double lowerAngle = 0,
    double upperAngle = 0,
    bool enableMotor = false,
    double motorSpeed = 0,
    double maxMotorTorque = 0,
    bool collideConnected = false,
  }) {
    final handleA = _bodyHandleOf(a);
    final handleB = _bodyHandleOf(b);
    if (handleA == 0 || handleB == 0) return Joint.none;
    _requireSameScene(a, b);

    return Joint(
      box2d.gooJointCreateRevolute(
        handleA,
        handleB,
        anchorAX,
        anchorAY,
        anchorBX,
        anchorBY,
        referenceAngle,
        enableLimit ? 1 : 0,
        lowerAngle,
        upperAngle,
        enableMotor ? 1 : 0,
        motorSpeed,
        maxMotorTorque,
        collideConnected ? 1 : 0,
      ),
    );
  }

  /// Constrains two bodies to slide along one axis - Unity's Slider Joint 2D.
  ///
  /// Lifts, sliding doors, pistons. ([axisX], [axisY]) is the free axis in
  /// **body A's local frame** and is normalised for you; a zero axis falls
  /// back to horizontal, and does not trip an assert that is absent from a
  /// release build.
  Joint createPrismaticJoint(
    Entity a,
    Entity b, {
    double anchorAX = 0,
    double anchorAY = 0,
    double anchorBX = 0,
    double anchorBY = 0,
    double axisX = 1,
    double axisY = 0,
    double referenceAngle = 0,
    bool enableLimit = false,
    double lowerTranslation = 0,
    double upperTranslation = 0,
    bool enableMotor = false,
    double motorSpeed = 0,
    double maxMotorForce = 0,
    bool collideConnected = false,
  }) {
    final ha = _bodyHandleOf(a);
    final hb = _bodyHandleOf(b);
    if (ha == 0 || hb == 0) return Joint.none;
    _requireSameScene(a, b);
    return Joint(
      box2d.gooJointCreatePrismatic(
        ha,
        hb,
        anchorAX,
        anchorAY,
        anchorBX,
        anchorBY,
        axisX,
        axisY,
        referenceAngle,
        enableLimit ? 1 : 0,
        lowerTranslation,
        upperTranslation,
        enableMotor ? 1 : 0,
        motorSpeed,
        maxMotorForce,
        collideConnected ? 1 : 0,
      ),
    );
  }

  /// Holds two bodies rigidly together - Unity's Fixed Joint 2D.
  ///
  /// A hertz of 0 on an axis welds it rigidly; above 0 gives that axis spring
  /// under load, which is what makes a weld look like it is straining rather
  /// than simply holding or breaking.
  Joint createWeldJoint(
    Entity a,
    Entity b, {
    double anchorAX = 0,
    double anchorAY = 0,
    double anchorBX = 0,
    double anchorBY = 0,
    double referenceAngle = 0,
    double linearHertz = 0,
    double linearDampingRatio = 0,
    double angularHertz = 0,
    double angularDampingRatio = 0,
    bool collideConnected = false,
  }) {
    final ha = _bodyHandleOf(a);
    final hb = _bodyHandleOf(b);
    if (ha == 0 || hb == 0) return Joint.none;
    _requireSameScene(a, b);
    return Joint(
      box2d.gooJointCreateWeld(
        ha,
        hb,
        anchorAX,
        anchorAY,
        anchorBX,
        anchorBY,
        referenceAngle,
        linearHertz,
        linearDampingRatio,
        angularHertz,
        angularDampingRatio,
        collideConnected ? 1 : 0,
      ),
    );
  }

  /// A suspension axis plus a free spin - Unity's Wheel Joint 2D, and what a
  /// driven vehicle wheel is made of.
  ///
  /// The axis defaults to **(0, -1), which is down**, because that is the way
  /// a suspension spring compresses under a gravity of (0, -10).
  Joint createWheelJoint(
    Entity a,
    Entity b, {
    double anchorAX = 0,
    double anchorAY = 0,
    double anchorBX = 0,
    double anchorBY = 0,
    double axisX = 0,
    double axisY = -1,
    bool enableSpring = true,
    double hertz = 4,
    double dampingRatio = 0.7,
    bool enableLimit = false,
    double lowerTranslation = 0,
    double upperTranslation = 0,
    bool enableMotor = false,
    double motorSpeed = 0,
    double maxMotorTorque = 0,
    bool collideConnected = false,
  }) {
    final ha = _bodyHandleOf(a);
    final hb = _bodyHandleOf(b);
    if (ha == 0 || hb == 0) return Joint.none;
    _requireSameScene(a, b);
    return Joint(
      box2d.gooJointCreateWheel(
        ha,
        hb,
        anchorAX,
        anchorAY,
        anchorBX,
        anchorBY,
        axisX,
        axisY,
        enableSpring ? 1 : 0,
        hertz,
        dampingRatio,
        enableLimit ? 1 : 0,
        lowerTranslation,
        upperTranslation,
        enableMotor ? 1 : 0,
        motorSpeed,
        maxMotorTorque,
        collideConnected ? 1 : 0,
      ),
    );
  }

  /// Drives body [b] towards a position and angle relative to body [a] -
  /// Unity's **Relative Joint 2D**.
  ///
  /// The same joint is Unity's **Friction Joint 2D**: leave the offsets at
  /// zero and it drives towards *no relative motion*, which with a capped
  /// [maxForce]/[maxTorque] is exactly friction. Two Unity components, one
  /// Box2D joint, and the difference is only what you ask it to hold.
  Joint createMotorJoint(
    Entity a,
    Entity b, {
    double offsetX = 0,
    double offsetY = 0,
    double angularOffset = 0,
    double maxForce = 0,
    double maxTorque = 0,
    double correctionFactor = 0,
    bool collideConnected = false,
  }) {
    final ha = _bodyHandleOf(a);
    final hb = _bodyHandleOf(b);
    if (ha == 0 || hb == 0) return Joint.none;
    _requireSameScene(a, b);
    return Joint(
      box2d.gooJointCreateMotor(
        ha,
        hb,
        offsetX,
        offsetY,
        angularOffset,
        maxForce,
        maxTorque,
        correctionFactor,
        collideConnected ? 1 : 0,
      ),
    );
  }

  /// Drags body [b] towards a **world-space** target - Unity's Target Joint
  /// 2D. Mouse dragging, tractor beams, anything that pulls instead of pins.
  ///
  /// [a] is a reference body Box2D needs but does not move; a static one is
  /// the usual choice. Move the target with `Joint.moveTarget`, which is the
  /// one joint parameter meant to change every frame.
  ///
  /// Zero for [hertz], [dampingRatio] or [maxForce] keeps Box2D's default,
  /// and does not mean zero - a zero-force drag would simply do nothing.
  ///
  /// The joint **grabs the body where it is** and then aims at the target, so
  /// it pulls, and does not pin a point that is already in place. That
  /// ordering is not cosmetic - creating it at the target instead anchors
  /// whichever part of the body is already there, and the joint then does
  /// nothing at all. The shim header has the measurements.
  Joint createMouseJoint(
    Entity a,
    Entity b, {
    double targetX = 0,
    double targetY = 0,
    double hertz = 0,
    double dampingRatio = 0,
    double maxForce = 0,
    bool collideConnected = false,
  }) {
    final ha = _bodyHandleOf(a);
    final hb = _bodyHandleOf(b);
    if (ha == 0 || hb == 0) return Joint.none;
    _requireSameScene(a, b);
    return Joint(
      box2d.gooJointCreateMouse(
        ha,
        hb,
        targetX,
        targetY,
        hertz,
        dampingRatio,
        maxForce,
        collideConnected ? 1 : 0,
      ),
    );
  }

  /// The body behind an entity, or 0 if it has none yet.
  int _bodyHandleOf(Entity entity) {
    if (!entity.has<RigidBody2D>()) return 0;
    final body = entity<RigidBody2D>().component;
    return body.bodyHandle[entity];
  }

  // --- spatial queries -------------------------------------------------------
  //
  // Results land in fields rather than a returned object, matching the reused
  // `Collision2DEvent`: a raycast per entity per tick is an ordinary thing for
  // a game to do, and returning a fresh result object would allocate on
  // exactly that path (the no-allocation rule).
  //
  // The consequence is stated on each query: the fields are valid only until
  // the next one.

  /// The entity hit by the last successful [raycast]. Undefined if it missed.
  Entity hitEntity = const Entity(0);

  /// The specific collider hit - an entity may declare several.
  ColliderBody? hitCollider;

  /// Where the ray met the shape, in world space.
  double hitX = 0;
  double hitY = 0;

  /// The surface normal at [hitX], [hitY].
  double hitNormalX = 0;
  double hitNormalY = 0;

  /// How far along the ray the hit was, `0..1`.
  double hitFraction = 0;

  Pointer<Float> _queryFloats = nullptr;
  Pointer<Int64> _queryShapes = nullptr;
  int _queryShapeCapacity = 0;

  /// Casts a ray from ([x], [y]) along ([dx], [dy]) and reports the closest
  /// collider hit.
  ///
  /// ([dx], [dy]) is a **translation, not a direction** - its length is the
  /// ray's length, so a ray 10 units long to the right is `(10, 0)`. That is
  /// Box2D's own convention and avoids a separate `maxDistance` argument
  /// that could disagree with a normalised direction.
  ///
  /// Returns whether anything was hit; on `true` the `hit*` fields describe
  /// it, and they stay valid **only until the next query**.
  ///
  /// [layerMask] is a bitmask of layers to test against, defaulting to all.
  ///
  /// [scene] says which world to cast in, and there is no default for it.
  /// Defaulting it to "the one loaded scene" would give a call that works for
  /// months and then queries the wrong world - or throws - the day a HUD scene
  /// loads, and the symptom would be a silently wrong answer instead of a
  /// clean failure. A one-scene game passes the scene it has.
  bool raycast(
    Scene scene,
    double x,
    double y,
    double dx,
    double dy, {
    int layerMask = -1,
  }) {
    final world = _worlds[scene.slot];
    if (world == null) return false;
    _queryFloats = _queryFloats == nullptr ? calloc<Float>(5) : _queryFloats;

    final shape = box2d.gooWorldCastRayClosest(
      world,
      x,
      y,
      dx,
      dy,
      1,
      layerMask,
      _queryFloats,
    );
    if (shape == 0) return false;

    final owner = _ownerOf(shape);
    if (owner == null) return false;

    hitEntity = owner.entity;
    hitCollider = owner.body;
    hitX = _queryFloats[0];
    hitY = _queryFloats[1];
    hitNormalX = _queryFloats[2];
    hitNormalY = _queryFloats[3];
    hitFraction = _queryFloats[4];
    return true;
  }

  /// Collects the colliders whose bounding box overlaps the given world-space
  /// box, returning how many were found. Read them with [overlapEntityAt] and
  /// [overlapColliderAt].
  ///
  /// **Broad-phase**: this is an AABB test, not an exact shape overlap, so a
  /// shape near a corner of the box can be reported without truly overlapping
  /// it. That is the useful primitive - "roughly what is in this region" -
  /// and a caller needing exactness re-tests the survivors, which is cheap
  /// once the set is small.
  ///
  /// Results are valid until the next query. [maxResults] bounds the work;
  /// anything beyond it is dropped, and no buffer grows without limit.
  /// [scene] says which world to search, and is required for the reason
  /// [raycast] gives.
  int overlapBox(
    Scene scene,
    double minX,
    double minY,
    double maxX,
    double maxY, {
    int layerMask = -1,
    int maxResults = 256,
  }) {
    final world = _worlds[scene.slot];
    if (world == null) return 0;
    if (maxResults > _queryShapeCapacity) {
      if (_queryShapeCapacity != 0) calloc.free(_queryShapes);
      _queryShapes = calloc<Int64>(maxResults);
      _queryShapeCapacity = maxResults;
    }
    return box2d.gooWorldOverlapAABB(
      world,
      minX,
      minY,
      maxX,
      maxY,
      1,
      layerMask,
      _queryShapes,
      maxResults,
    );
  }

  /// The entity of the `i`th result from the last [overlapBox].
  Entity overlapEntityAt(int i) =>
      _ownerOf(_queryShapes[i])?.entity ?? const Entity(0);

  /// The collider of the `i`th result from the last [overlapBox], or null if
  /// its shape has since been destroyed.
  ColliderBody? overlapColliderAt(int i) => _ownerOf(_queryShapes[i])?.body;

  // --- contact and sensor events ---------------------------------------------

  /// Drains this step's touch transitions, dispatches enter/exit, then
  /// dispatches stay for everything still touching.
  void _dispatchContacts() {
    for (final world in _worlds.values) {
      _drain(world, sensors: false);
      _drain(world, sensors: true);
    }
    // Once, not per world: the touching set is keyed by shape and a pair can
    // only ever come from the world both its shapes are in.
    if (dispatchStayEvents) _dispatchStay();
  }

  void _drain(int world, {required bool sensors}) {
    final available = sensors
        ? box2d.gooWorldSensorEventCount(world)
        : box2d.gooWorldContactEventCount(world);
    if (available == 0) return;

    _ensureEventCapacity(available);
    final count = sensors
        ? box2d.gooWorldDrainSensors(world, _events, _eventCapacity)
        : box2d.gooWorldDrainContacts(world, _events, _eventCapacity);

    for (var i = 0; i < count; i++) {
      final kind = _events[i * 3];
      final shapeA = _events[i * 3 + 1];
      final shapeB = _events[i * 3 + 2];

      if (kind == _touchBegin) {
        _remember(shapeA, shapeB, sensors);
        _dispatchPair(shapeA, shapeB, sensors, _Phase.enter);
      } else {
        _forget(shapeA, shapeB);
        _dispatchPair(shapeA, shapeB, sensors, _Phase.exit);
      }
    }
  }

  /// Fires stay for every pair that is still touching.
  ///
  /// Box2D has no "still touching" event - it reports transitions only - so
  /// this is derived from the begin/end pairs tracked above. That is the one
  /// part of `CollisionListener` that costs a data structure instead of a
  /// translation.
  void _dispatchStay() {
    for (var i = 0; i < _touchingCount; i++) {
      _dispatchPair(
        _touchingA[i],
        _touchingB[i],
        _touchingSensor[i] == 1,
        _Phase.stay,
      );
    }
  }

  /// Delivers one collision to both sides, each hearing itself as `source`.
  void _dispatchPair(int shapeA, int shapeB, bool sensor, _Phase phase) {
    final a = _ownerOf(shapeA);
    final b = _ownerOf(shapeB);
    // A shape destroyed in the same step that reported it - its owner slot
    // may already be gone. Nothing to tell.
    if (a == null || b == null) return;

    // BOTH directions, sensors included, so a listener always reads `source`
    // as its own collider and `target` as the other.
    //
    // Sensors are not an exception, though an earlier draft made them one on
    // the reasoning that Box2D guarantees sensor-then-visitor ordering.
    // That confused *who Box2D names first* with *who wants to be told*: the
    // object walking into a trigger is usually the one with the listener -
    // a pickup, a checkpoint, a damage volume - and it heard nothing at all.
    // Unity fires OnTriggerEnter2D on both sides too.
    _deliver(a, b, sensor, phase);
    _deliver(b, a, sensor, phase);
  }

  void _deliver(
    _ShapeOwner source,
    _ShapeOwner target,
    bool sensor,
    _Phase phase,
  ) {
    final listener = source.listener;
    if (listener == null) return;

    // Repointed, never reallocated - a step can produce hundreds of these.
    _event.set(source.body, source.entity, target.body, target.entity);

    if (sensor) {
      switch (phase) {
        case _Phase.enter:
          listener.onTriggerEnter2D(_event);
        case _Phase.exit:
          listener.onTriggerExit2D(_event);
        case _Phase.stay:
          listener.onTriggerStay2D(_event);
      }
    } else {
      switch (phase) {
        case _Phase.enter:
          listener.onCollisionEnter2D(_event);
        case _Phase.exit:
          listener.onCollisionExit2D(_event);
        case _Phase.stay:
          listener.onCollisionStay2D(_event);
      }
    }
  }

  void _remember(int shapeA, int shapeB, bool sensor) {
    if (_touchingCount == _touchingA.length) {
      final capacity = _touchingCount == 0 ? 64 : _touchingCount * 2;
      _touchingA = Int64List(capacity)..setRange(0, _touchingCount, _touchingA);
      _touchingB = Int64List(capacity)..setRange(0, _touchingCount, _touchingB);
      _touchingSensor = Uint8List(capacity)
        ..setRange(0, _touchingCount, _touchingSensor);
    }
    _touchingA[_touchingCount] = shapeA;
    _touchingB[_touchingCount] = shapeB;
    _touchingSensor[_touchingCount] = sensor ? 1 : 0;
    _touchingCount++;
  }

  /// Linear scan plus swap-with-last. Order is not meaningful here, so
  /// compacting properly would cost a move per removal for nothing.
  void _forget(int shapeA, int shapeB) {
    for (var i = 0; i < _touchingCount; i++) {
      if (_touchingA[i] != shapeA || _touchingB[i] != shapeB) continue;
      final last = _touchingCount - 1;
      _touchingA[i] = _touchingA[last];
      _touchingB[i] = _touchingB[last];
      _touchingSensor[i] = _touchingSensor[last];
      _touchingCount = last;
      return;
    }
  }

  void _ensureEventCapacity(int needed) {
    if (needed <= _eventCapacity) return;
    var capacity = _eventCapacity == 0 ? 64 : _eventCapacity;
    while (capacity < needed) {
      capacity *= 2;
    }
    if (_eventCapacity != 0) calloc.free(_events);
    // 3 int64 per record: [kind, shapeA, shapeB].
    _events = calloc<Int64>(capacity * 3);
    _eventCapacity = capacity;
  }

  // --- scratch management ---------------------------------------------------

  void _ensureCapacity(int needed) {
    if (needed <= _capacity) return;

    // Doubling, so a scene that spawns bodies one at a time does not
    // reallocate on every one.
    var capacity = _capacity == 0 ? 64 : _capacity;
    while (capacity < needed) {
      capacity *= 2;
    }

    final handles = calloc<Int64>(capacity);
    final pushHandles = calloc<Int64>(capacity);
    final pullTransformHandles = calloc<Int64>(capacity);
    final transforms = calloc<Float>(capacity * 3);
    final velocities = calloc<Float>(capacity * 3);

    if (_capacity != 0) {
      // The FULL old capacity, not `_count`. `_count` is last tick's total,
      // and this can be reached part-way through a fill that has already
      // staged more slots than that - copying `_count` would silently
      // discard them, which showed up as bodies flying off after the
      // population first grew past the initial capacity of 64.
      final old = _capacity;
      for (var i = 0; i < old; i++) {
        handles[i] = _handles[i];
        pushHandles[i] = _pushHandles[i];
        pullTransformHandles[i] = _pullTransformHandles[i];
      }
      for (var i = 0; i < old * 3; i++) {
        transforms[i] = _transforms[i];
        velocities[i] = _velocities[i];
      }
      calloc
        ..free(_handles)
        ..free(_pushHandles)
        ..free(_pullTransformHandles)
        ..free(_transforms)
        ..free(_velocities);
    }

    _handles = handles;
    _pushHandles = pushHandles;
    _pullTransformHandles = pullTransformHandles;
    _transforms = transforms;
    _velocities = velocities;
    _capacity = capacity;
  }

  void _growSlots(int needed) {
    if (_slots.length >= needed) return;
    final grown = List<Entity>.filled(_capacity, const Entity(0));
    for (var i = 0; i < _slots.length && i < grown.length; i++) {
      grown[i] = _slots[i];
    }
    _slots = grown;
  }

  /// Releases the Box2D world, its worker threads and the scratch buffers,
  /// when the game stops.
  ///
  /// **You do not have to call it.** `GameState.unmount` fires
  /// `GameSystem.unmountEvent` after the scenes are down, which is the only
  /// safe moment: releasing the world while entities still hold bodies in it
  /// is a use-after-free, and that one is a native crash with no Dart
  /// exception. Left to a game to call, it goes uncalled, and a run leaks a
  /// Box2D world and - with threading on - its worker threads too.
  ///
  /// [dispose] is public and idempotent, so a test or a harness that wants to
  /// reclaim the world early can, and calling it twice is harmless.
  @override
  void onUnmounted() => dispose();

  /// See [onUnmounted] - this is what it calls.
  void dispose() {
    for (final world in _worlds.values) {
      box2d.gooWorldDestroy(world);
    }
    _worlds.clear();
    if (_capacity != 0) {
      calloc
        ..free(_handles)
        ..free(_pushHandles)
        ..free(_pullTransformHandles)
        ..free(_transforms)
        ..free(_velocities);
      _handles = nullptr;
      _pushHandles = nullptr;
      _pullTransformHandles = nullptr;
      _transforms = nullptr;
      _velocities = nullptr;
      _capacity = 0;
    }
    if (_eventCapacity != 0) {
      calloc.free(_events);
      _events = nullptr;
      _eventCapacity = 0;
    }
    if (_queryFloats != nullptr) {
      calloc.free(_queryFloats);
      _queryFloats = nullptr;
    }
    if (_queryShapeCapacity != 0) {
      calloc.free(_queryShapes);
      _queryShapes = nullptr;
      _queryShapeCapacity = 0;
    }
    final counters = _countersOut;
    if (counters != null) {
      calloc.free(counters);
      _countersOut = null;
    }
    _touchingCount = 0;
    _shapeOwners = <_ShapeOwner?>[];
    // Both name a world that no longer exists; leaving them would have the
    // next step create bodies for freed rows in a freed world.
    _pendingCreate.clear();
    _freshHandles.clear();
  }
}

/// Which entity and which declared collider a Box2D shape belongs to, plus
/// that entity's collision listener if it has one.
///
/// [listener] is resolved **once, at shape creation**, and that is a real
/// optimisation, not tidiness. Resolving it costs an archetype lookup and a
/// subtype test - two of them here, since the listener may be absent and
/// `has` asks the same question first - and dispatch would pay that twice per
/// touching pair per tick - a settled pile of 20 000 bodies is tens of
/// thousands of contacts, so resolving on the fly is tens of thousands of
/// resolves every tick. The answer cannot change: the lookup returns the
/// *prefab*, which is one
/// object per archetype, and a shape's entity never changes archetype.
class _ShapeOwner {
  const _ShapeOwner(this.entity, this.body, this.listener);

  final Entity entity;
  final ColliderBody body;

  /// Null when this entity's prefab does not mix in `CollisionListener` - so
  /// dispatch skips it with a null check instead of a type test.
  final CollisionListener? listener;
}

/// Which of `CollisionListener`'s three phases a dispatch is.
enum _Phase { enter, exit, stay }

/// Mirrors GOO_TOUCH_BEGIN in goo_box2d.h.
const int _touchBegin = 0;
