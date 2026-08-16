import 'dart:math' as math;
import 'dart:typed_data';

import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

import 'package:goo2d_example/demo/demo.dart';
import 'package:goo2d_example/demo/demo_game.dart';

/// **Units are metres, and the camera is what converts.**
///
/// Box2D is tuned for metres, kilograms and seconds, and behaves best with
/// moving objects between roughly 0.1 m and 10 m. A game that treats one world
/// unit as one pixel gives a 32-pixel crate the mass and inertia of a 32-metre
/// building - still simulated, visibly wrong, and usually diagnosed as "the
/// physics feels floaty".
///
/// So this case works in metres throughout and applies the scale **once**, at
/// the camera's zoom. Nothing in the simulation knows about pixels.
///
/// This particular value is only the fallback, used when nothing is showing
/// the camera yet and the viewport therefore reports zero. Once a `GameView`
/// has laid out, [Arena.zoomFor] computes the scale from the arena's size.
const double _fallbackPixelsPerMetre = 18.0;

/// Floor space one body is given, in square metres.
///
/// **This constant is the whole reason the arena is not a fixed size**, and it
/// was put here after measuring. A crate is 1 m x 1 m and a ball is about
/// 0.5 m^2, so 2 m^2 each is a loose pile with room to move.
///
/// The original demo used a fixed 32 m x 13 m box - about 420 m^2, or room for
/// roughly 200 bodies - behind a slider that went to 20 000. Everything past a
/// few hundred was not a pile but a **crush**: bodies overlapping, the solver
/// pushing them apart every step and never converging, and no island ever
/// quiet enough to sleep. Box2D's cost follows the contact graph, so a box
/// that cannot hold what it is given costs far more than one that can.
///
/// **This was not the whole story, and scaling the arena alone barely moved
/// the numbers.** The rest was a leak in `goo` - `Entity.destroy()` did not
/// fire the world-observation despawn event, so every recycled body stayed in
/// the Box2D world forever. Both had to be fixed, and only the diagnostic
/// counters told them apart: the arena explains a *large* cost, but only a
/// leak explains Box2D reporting 57 882 awake bodies for a scene of 4000.
///
/// The one thing measurement was unambiguous about throughout: the ECS layer
/// around the solver - `fill`, `sync` and contact dispatch together - never
/// exceeded 0.8 ms of a 40 ms frame.
const double _areaPerBody = 2.0;

/// Interior width divided by interior height. Roughly a window's shape, so the
/// arena fills the view rather than leaving bars at the sides.
const double _arenaAspect = 2.4;

/// The smallest the arena gets, in metres. Below this a handful of bodies
/// would rattle around in a box far larger than the pile, which shows less
/// than the same bodies in a box they nearly fill.
const double _minArenaHalfWidth = 15.0;

/// The interior of the box, in metres, sized to hold a given population.
///
/// **Positive y is DOWN** - goo2d projects world space into Flutter's canvas,
/// where y grows downward - so the floor sits at a *larger* y than the bodies
/// falling onto it, and the drop zone is at a negative one. Box2D's own
/// examples are written y-up; this engine is not.
///
/// Centred on the world origin, so the camera never has to move.
class Arena {
  const Arena(this.halfWidth, this.halfHeight);

  /// Sized so [population] bodies have [_areaPerBody] each, never smaller than
  /// [_minArenaHalfWidth].
  factory Arena.forPopulation(int population) {
    final halfWidth = halfWidthFor(population);
    return Arena(halfWidth, halfWidth / _arenaAspect);
  }

  /// What [forPopulation] would produce, without building one.
  ///
  /// Split out because [SandboxSystem] asks this question on **every** fixed
  /// tick to decide whether the box still fits, and allocating an object per
  /// tick to answer it is the kind of thing RULES.md rule 1 is about. The
  /// rebuild itself is rare enough to allocate freely.
  static double halfWidthFor(int population) {
    // area = (2 * halfWidth) * (2 * halfHeight) and halfWidth / halfHeight is
    // fixed at _arenaAspect, so halfHeight falls straight out.
    final area = (population < 1 ? 1 : population) * _areaPerBody;
    final halfWidth = math.sqrt(area / (4 * _arenaAspect)) * _arenaAspect;
    return halfWidth < _minArenaHalfWidth ? _minArenaHalfWidth : halfWidth;
  }

  final double halfWidth;
  final double halfHeight;

  /// Half-thickness of the floor and walls. They sit *outside* the interior,
  /// so making them thicker never steals room from the pile.
  static const double wallHalfThickness = 1.0;

  /// The floor's centre.
  double get floorY => halfHeight + wallHalfThickness;

  /// Each wall's centre, on the x it is given.
  double get wallX => halfWidth + wallHalfThickness;

  /// Where bodies are released - just inside the ceiling, so they have the
  /// whole box to fall through.
  double get dropY => -halfHeight + 1;

  /// How far either side of centre a body may be released. Kept clear of the
  /// walls so nothing spawns overlapping one.
  double get dropHalfWidth => halfWidth - 2;

  /// Pixels per metre that fits the whole arena in a viewport of the given
  /// size, or [_fallbackPixelsPerMetre] if nothing is showing it yet.
  ///
  /// Fits **both** axes and takes the smaller: fitting width alone would crop
  /// the top off the tall end of the range, where the pile is.
  double zoomFor(double viewWidth, double viewHeight) {
    if (viewWidth <= 0 || viewHeight <= 0) return _fallbackPixelsPerMetre;
    final x = viewWidth / (2 * (halfWidth + 2 * wallHalfThickness));
    final y = viewHeight / (2 * (halfHeight + 2 * wallHalfThickness));
    return x < y ? x : y;
  }
}

const int _crateColor = 0xFF8D6E63;
const int _crateHitColor = 0xFFFFCA28;
const int _ballColor = 0xFF4FC3F7;
const int _ballHitColor = 0xFFFF7043;
const int _floorColor = 0xFF37474F;

/// How long a crate stays lit after a collision, in seconds. Without this the
/// flash lasts one tick and is invisible at 60 Hz - the point of the case is
/// to make the *event path* visible, not just plausible.
const double _flashSeconds = 0.12;

/// A falling crate, lit by its own `CollisionListener`.
///
/// Mixes in `CollisionListener` directly on the prefab, which is the narrow
/// scope: this hears collisions involving *its own* colliders, and needs no
/// filtering. A system wanting every collision in the game would instead be a
/// broad observer.
class Crate extends EntityStruct
    with
        Transform2D,
        Renderable2D,
        Collider2D,
        RigidBody2D,
        CollisionListener,
        EntityLifecycleListener {
  late final Sprite body;
  late final BoxBody box;

  /// Seconds of flash remaining. A component field rather than plain Dart
  /// state on the prefab, because it is per *entity* - the prefab is one
  /// object shared by every crate.
  late final DataPointer<double> flash;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    flash = data.hasFloat64();
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    // 1 m x 1 m, in WORLD units - the same units the collider below uses,
    // and the same units Box2D simulates in. `Sprite.width` is world units,
    // not pixels; the camera's `zoom` is the only thing that converts to
    // pixels. Sizing sprites in pixels here *and* setting zoom applies the
    // scale twice and draws everything _pixelsPerMetre times too large,
    // which is exactly how this was first written.
    body = descriptor.has(width: 1, height: 1, color: _crateColor);
  }

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(
      halfWidth: 0.5,
      halfHeight: 0.5,
      friction: 0.4,
      restitution: 0.15,
    );
  }

  /// Enter only, not stay: a resting crate collides every single tick, so
  /// lighting on stay would leave the whole pile permanently lit and show
  /// nothing.
  @override
  void onCollisionEnter2D(Collision2DEvent event) {
    flash[event.sourceEntity] = _flashSeconds;
  }

  /// Plain Dart state on the prefab - it lives on the game isolate and is
  /// never shared, exactly as the Galaxy case's own spawn counter is.
  int _spawned = 0;

  /// The arena to drop into, refreshed by [SandboxSystem] whenever it resizes
  /// the box. A prefab field rather than an argument because
  /// [onEntityMounted] is called by the engine and takes only the entity.
  Arena arena = Arena.forPopulation(0);

  /// Positions this body **before** the physics system creates it.
  ///
  /// This is the load-bearing half of the case. `onEntityMounted` is the
  /// prefab's own narrow lifecycle event, and the engine fires it *before*
  /// the broad `onEntitySpawned` that `Box2DPhysicsSystem` listens to - so a
  /// transform written here is the one the Box2D body is created at.
  ///
  /// Writing it after `addEntity` instead does not work, and fails in a way
  /// worth knowing: the body has already been created at the origin, physics
  /// writes the body's position back over the transform on the same tick, and
  /// every body in the scene is born in one overlapping heap at (0, 0) which
  /// the solver then blasts apart. It looks like a spawn bug and is an
  /// ordering one.
  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    final i = _spawned++;
    // A golden-ratio spread across the drop zone, so a batch spawned in one
    // tick does not stack into a single column.
    final spread = ((i * 0.6180339887498949) % 1.0) * 2 - 1;
    this
      ..transformOffsetX[entity] = spread * arena.dropHalfWidth
      // Three rows *below* the drop line, never above it. Stacking upward put
      // bodies over the tops of the walls, where a shove from a neighbour
      // sends them out of the box - they then fall until the recycler
      // destroys them and the case respawns them, so the population churns
      // forever instead of settling.
      ..transformOffsetY[entity] = arena.dropY + (i % 3)
      ..transformRotation[entity] = spread * math.pi;
  }
}

/// A bouncier ball, so the case shows restitution and the circle shape.
class Ball extends EntityStruct
    with
        Transform2D,
        Renderable2D,
        Collider2D,
        RigidBody2D,
        CollisionListener,
        EntityLifecycleListener {
  late final Sprite body;
  late final CircleBody circle;

  late final DataPointer<double> flash;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    flash = data.hasFloat64();
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    // Matches the 0.4 m collider radius below.
    body = descriptor.has(width: 0.8, height: 0.8, color: _ballColor);
  }

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    circle = descriptor.hasCircleCollider(
      radius: 0.4,
      friction: 0.3,
      restitution: 0.72,
    );
  }

  @override
  void onCollisionEnter2D(Collision2DEvent event) {
    flash[event.sourceEntity] = _flashSeconds;
  }

  /// Plain Dart state on the prefab - it lives on the game isolate and is
  /// never shared, exactly as the Galaxy case's own spawn counter is.
  int _spawned = 0;

  /// The arena to drop into. See [Crate.arena].
  Arena arena = Arena.forPopulation(0);

  /// Positions this body **before** the physics system creates it.
  ///
  /// This is the load-bearing half of the case. `onEntityMounted` is the
  /// prefab's own narrow lifecycle event, and the engine fires it *before*
  /// the broad `onEntitySpawned` that `Box2DPhysicsSystem` listens to - so a
  /// transform written here is the one the Box2D body is created at.
  ///
  /// Writing it after `addEntity` instead does not work, and fails in a way
  /// worth knowing: the body has already been created at the origin, physics
  /// writes the body's position back over the transform on the same tick, and
  /// every body in the scene is born in one overlapping heap at (0, 0) which
  /// the solver then blasts apart. It looks like a spawn bug and is an
  /// ordering one.
  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    final i = _spawned++;
    // A golden-ratio spread across the drop zone, so a batch spawned in one
    // tick does not stack into a single column.
    final spread = ((i * 0.6180339887498949) % 1.0) * 2 - 1;
    this
      ..transformOffsetX[entity] = spread * arena.dropHalfWidth
      // Three rows *below* the drop line, never above it. Stacking upward put
      // bodies over the tops of the walls, where a shove from a neighbour
      // sends them out of the box - they then fall until the recycler
      // destroys them and the case respawns them, so the population churns
      // forever instead of settling.
      ..transformOffsetY[entity] = arena.dropY + (i % 3)
      ..transformRotation[entity] = spread * math.pi;
  }
}

/// The ground. Static, so Box2D never integrates it and the solver treats it
/// as infinite mass - far cheaper than a dynamic body that happens to sit
/// still, and the reason level geometry should always be static.
///
/// # Why this sizes itself per entity
///
/// The arena grows with the population, so the floor's extent is not a
/// constant. `describeCollider` can only set the field's *default*, and the
/// Box2D shape is built from whatever the field holds when the body is
/// created - which is during `onEntitySpawned`, immediately after
/// [onEntityMounted]. So writing the size here is the only point early enough
/// for Box2D to see it, exactly as `Crate.onEntityMounted` is the only point
/// early enough for the position.
///
/// Changing the field *later* would move the sprite and leave the collider
/// where it was, which looks like the physics having drifted out of sync with
/// the graphics. [SandboxSystem] rebuilds these entities instead.
class Ground extends EntityStruct
    with Transform2D, Renderable2D, Collider2D, RigidBody2D,
        EntityLifecycleListener {
  late final Sprite body;
  late final BoxBody box;

  /// Set by [SandboxSystem] before the entity is added.
  Arena arena = Arena.forPopulation(0);

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    body = descriptor.has(color: _floorColor);
  }

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(friction: 0.6);
  }

  @override
  void describeRigidBody(RigidBody2DDescriptor descriptor) {
    descriptor.has(type: BodyType2D.staticBody);
  }

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    // Wider than the interior by the wall thickness on each side, so the
    // corners are closed and nothing squeezes out between floor and wall.
    final halfWidth = arena.wallX + Arena.wallHalfThickness;
    box
      ..halfWidth[entity] = halfWidth
      ..halfHeight[entity] = Arena.wallHalfThickness;
    body
      ..width[entity] = halfWidth * 2
      ..height[entity] = Arena.wallHalfThickness * 2;
    transformOffsetY[entity] = arena.floorY;
  }
}

/// A side wall, so a body that reaches the edge is turned back rather than
/// leaving the view and quietly inflating the population.
///
/// Sizes itself per entity for the same reason [Ground] does.
class Wall extends EntityStruct
    with Transform2D, Renderable2D, Collider2D, RigidBody2D,
        EntityLifecycleListener {
  late final Sprite body;
  late final BoxBody box;

  /// Set by [SandboxSystem] before the entity is added.
  Arena arena = Arena.forPopulation(0);

  /// Which side this one is: -1 for left, 1 for right.
  double side = -1;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    body = descriptor.has(color: _floorColor);
  }

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider();
  }

  @override
  void describeRigidBody(RigidBody2DDescriptor descriptor) {
    descriptor.has(type: BodyType2D.staticBody);
  }

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    box
      ..halfWidth[entity] = Arena.wallHalfThickness
      ..halfHeight[entity] = arena.halfHeight;
    body
      ..width[entity] = Arena.wallHalfThickness * 2
      ..height[entity] = arena.halfHeight * 2;
    transformOffsetX[entity] = side * arena.wallX;
  }
}

class Eye extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

class Sandbox extends SceneStruct {
  /// This scene's loaded handle. Entity creation lives on `Scene` (one
  /// `SceneStruct` can back several loaded scenes), so the struct captures it
  /// on mount and spawning goes through it.
  late Scene handle;

  late final Crate crate;
  late final Ball ball;
  late final Ground ground;
  late final Wall wall;
  late final Eye eye;

  @override
  void describeScene(SceneDescriptor descriptor) {
    crate = descriptor.has(Crate());
    ball = descriptor.has(Ball());
    ground = descriptor.has(Ground());
    wall = descriptor.has(Wall());
    eye = descriptor.has(Eye());
  }

  /// The camera. Held so [SandboxSystem] can rezoom it when the arena
  /// resizes.
  late Entity camera;

  /// The floor and the two walls, in the order they were added, so a rebuild
  /// can destroy exactly them and nothing else.
  final List<Entity> walls = <Entity>[];

  /// The arena the [walls] were last built for.
  Arena arena = Arena.forPopulation(0);

  @override
  void onSceneMounted(Scene scene) {
    handle = scene;
    camera = scene.addEntity(eye);
    // Without this the camera occupies no view, `ActiveCameraResolver` finds
    // none, and the renderer falls back to an implicit camera at the world
    // origin with zoom 1 - so `zoom` below is simply ignored and one metre
    // draws as one pixel. The whole scene then renders about 32 px across.
    eye.view[camera] = (game as Game2D).defaultCamera;
    eye.zoom[camera] = _fallbackPixelsPerMetre;
    buildArena(arena);
  }

  /// Replaces the floor and walls with ones sized for [next].
  ///
  /// A rebuild rather than a resize: a Box2D shape's extents are fixed when
  /// the shape is created, so writing `halfWidth` on a live entity would move
  /// the sprite and leave the collider behind. Three entities is cheap enough
  /// that the honest version wins.
  void buildArena(Arena next) {
    for (final wall in walls) {
      wall.destroy();
    }
    walls.clear();
    arena = next;

    ground.arena = next;
    walls.add(handle.addEntity(ground));

    for (final side in <double>[-1, 1]) {
      wall
        ..arena = next
        ..side = side;
      walls.add(handle.addEntity(wall));
    }

    // Every spawner works in the new arena's coordinates from here on.
    crate.arena = next;
    ball.arena = next;
  }
}

/// Spawns towards the target population, ages the collision flashes, and
/// recycles anything that escapes.
class SandboxSystem extends GameSystem with FixedTickable {
  final Stopwatch _clock = Stopwatch();

  /// Every simulated body. Public so a test can check *where* they ended up
  /// rather than only how many there are - the population alone is happy with
  /// a world where every body sits at the origin.
  late final Query bodies;

  int _spawnCount = 0;

  /// How many bodies have ever left the box and been recycled.
  ///
  /// Cumulative, not per tick: the question it answers is "is this scene
  /// leaking out of its own container", and a per-tick figure of 8 looks
  /// harmless while being exactly the spawn rate.
  int escapes = 0;

  /// Capped per tick so dragging the slider is a fill you can watch rather
  /// than one frame that stalls - the same reasoning as the Galaxy case.
  static const int _maxSpawnPerTick = 8;

  /// Higher than [_maxSpawnPerTick] because destroying a body is much cheaper
  /// than creating one with its shapes, and because dragging the slider *down*
  /// should feel like an answer rather than a wait.
  static const int _maxDespawnPerTick = 256;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    bodies = descriptor.query().withAll(RigidBody2D, Transform2D).build();
  }

  /// After the physics system, so a flash set by a collision this tick is
  /// aged starting next tick rather than immediately.
  @override
  int compareTo(GameSystem other) => other is Box2DPhysicsSystem ? 1 : 0;

  @override
  void onFixedUpdate() {
    _clock
      ..reset()
      ..start();

    final demo = getState<PhysicsState>();
    final scene = demo.sandbox;
    final dt = state.game.fixedTimeStep.inMicroseconds / 1000000.0;

    _resizeArena(demo, scene);

    // How many bodies still have to go to reach the target. Counted down as
    // the walk below destroys them, so the walk sheds and the walk counts in
    // one pass. Population is last tick's, which is close enough for a cap
    // that only paces the change.
    var toDespawn = demo.spawnedCount - demo.targetPopulation;
    if (toDespawn > _maxDespawnPerTick) toDespawn = _maxDespawnPerTick;

    // Shed every [_shedStride]th body rather than the first N of them.
    // Entities are walked archetype by archetype, so taking a prefix would
    // destroy every crate before touching a single ball - and the mix of two
    // collider kinds under load is half of what the case is for. Spreading
    // the removals also avoids carving a hole in one region of the pile and
    // watching the rest avalanche into it.
    final shedStride = toDespawn > 0 ? demo.spawnedCount ~/ toDespawn : 0;
    var walked = 0;

    final floorY = scene.arena.floorY;

    var alive = 0;
    for (final group in bodies.groups()) {
      final transform = group.get<Transform2D>();
      // Only the two prefabs that flash; the ground and walls match the query
      // too and have neither field.
      final crate = group.tryGet<Crate>();
      final ball = group.tryGet<Ball>();
      if (crate == null && ball == null) continue;

      for (final entity in group) {
        alive++;
        final index = walked++;

        // Shedding, and the reason the slider is a *target* rather than a
        // spawn button. Without this the population could only ever go up:
        // dragging from 20 000 down to 500 left 20 000 bodies simulating and
        // looked exactly like the engine failing to recover.
        if (toDespawn > 0 && (shedStride < 2 || index % shedStride == 0)) {
          toDespawn--;
          entity.destroy();
          alive--;
          continue;
        }

        // Anything that finds a way out of the box is recycled rather than
        // left to fall forever, which would make the population meaningless.
        //
        // **Counted, because a silent recycler hides a real fault.** If bodies
        // escape as fast as the case spawns them the population plateaus, and
        // every measurement above that plateau is quietly describing a much
        // smaller world than its label claims. `escapes` climbing steadily is
        // the tell; a healthy scene recycles almost nothing.
        if (transform.transformOffsetY[entity] > floorY + 40) {
          escapes++;
          entity.destroy();
          alive--;
          continue;
        }

        final flash = crate?.flash ?? ball!.flash;
        final remaining = flash[entity] - dt;
        if (remaining <= 0) {
          if (flash[entity] > 0) {
            flash[entity] = 0;
            _setColor(crate, ball, entity, false);
          }
        } else {
          if (flash[entity] >= _flashSeconds - dt) {
            _setColor(crate, ball, entity, true);
          }
          flash[entity] = remaining;
        }
      }
    }

    final shortfall = demo.targetPopulation - alive;
    if (shortfall > 0) {
      final batch = shortfall < _maxSpawnPerTick ? shortfall : _maxSpawnPerTick;
      for (var i = 0; i < batch; i++) {
        _spawn(scene);
      }
      alive += batch;
    }

    demo
      ..spawnedCount = alive
      ..caseMicros = _clock.elapsedMicroseconds;
    _clock.stop();

    // Published from inside the fixed step rather than from `DemoStats`, and
    // that is safe *here* specifically: this system sorts after the physics
    // system, so all four phase totals are final by the time this line runs.
    // The warning on `DemoStats` is about the step's own accumulating totals,
    // which are not final until the step returns.
    final physics = state.getSystem<Box2DPhysicsSystem>();
    physics.counters(_counters);
    getGame<PhysicsGame>()
      ..fillMicros.value = physics.lastFillMicros
      ..solveMicros.value = physics.lastSolveMicros
      ..syncMicros.value = physics.lastSyncMicros
      ..contactMicros.value = physics.lastContactMicros
      ..escapedBodies.value = escapes
      ..solverThreads.value = physics.activeWorkerCount
      ..physicsBodies.value = _counters[0]
      ..awakeBodies.value = physics.awakeBodyCount
      ..touchingPairs.value = physics.touchingPairCount
      ..broadPhasePairs.value = _counters[2];
  }

  /// Reused across ticks - `counters` fills a caller's list precisely so this
  /// costs no allocation per tick.
  final Int32List _counters = Int32List(5);

  /// Rebuilds the box, and rezooms the camera, when the target population no
  /// longer fits what is there.
  ///
  /// # Why this exists at all
  ///
  /// Measured, not guessed. With a fixed 32 m x 13 m box the solver cost 0.94
  /// ms at 1000 bodies and 36.22 ms at 4000 - 11x for 2x the bodies - because
  /// past a few hundred the box was not holding a pile, it was crushing one.
  /// Box2D's cost follows the contact graph, and bodies with nowhere to go
  /// overlap, never separate and never sleep. See [_areaPerBody].
  ///
  /// # Hysteresis
  ///
  /// Rebuilding destroys and recreates three static bodies, so doing it on
  /// every slider pixel while a drag is in flight would be a stutter. A 15%
  /// band means a drag rebuilds a handful of times across its whole range.
  void _resizeArena(PhysicsState demo, Sandbox scene) {
    final wanted = Arena.halfWidthFor(demo.targetPopulation);
    final current = scene.arena.halfWidth;
    if ((wanted - current).abs() < current * 0.15) return;

    final next = Arena.forPopulation(demo.targetPopulation);
    scene.buildArena(next);

    // Zero until a `GameView` has laid out - a headless test never has one -
    // in which case `zoomFor` keeps the fallback rather than dividing by it.
    final view = getGame<PhysicsGame>().defaultCamera;
    scene.eye.zoom[scene.camera] = next.zoomFor(
      view.viewportWidth,
      view.viewportHeight,
    );
  }

  void _setColor(Crate? crate, Ball? ball, Entity entity, bool lit) {
    if (crate != null) {
      crate.body.color[entity] = lit ? _crateHitColor : _crateColor;
    } else {
      ball!.body.color[entity] = lit ? _ballHitColor : _ballColor;
    }
  }

  /// Alternating shapes, so both collider kinds are under load rather than
  /// one being decorative.
  ///
  /// The spawn *position* is not set here - each prefab places itself in its
  /// own `onEntityMounted`, which is the only point early enough for the
  /// Box2D body to be created there. See `Crate.onEntityMounted`.
  void _spawn(Sandbox scene) {
    final isBall = (_spawnCount++).isEven;
    if (isBall) {
      scene.handle.addEntity(scene.ball);
    } else {
      scene.handle.addEntity(scene.crate);
    }
  }
}

class PhysicsState extends DemoState<PhysicsGame> {
  final Sandbox sandbox = Sandbox();

  @override
  void onMounted() => loadScene(sandbox);

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    // Gravity in metres per second squared. Box2D's own default is -10 rather
    // than -9.81; it is a game engine, not a geodesy package.
    // Positive is down; see Box2DPhysicsSystem.gravityY.
    // **Read off the Game, not a top-level.** `describeSystems` runs on the
    // game isolate, and top-level state does not cross `Isolate.spawn` - a
    // top-level `physicsWorkerCount` set on main read back as its default of
    // 1 here, so the world was built single-threaded no matter what the
    // caller asked for, and the bench dutifully reported that threading
    // changed nothing. A field on the `Game` travels with the copied object
    // graph and arrives.
    descriptor.has(
      Box2DPhysicsSystem(gravityY: 18, workerCount: game.solverWorkerCount),
    );
    descriptor.has(SandboxSystem());
  }
}

class PhysicsGame extends DemoGame {
  /// Threads the solver may spread a step across, set **before**
  /// `Game.start`.
  ///
  /// A plain field on the `Game` because that object is deep-copied to the
  /// game isolate, so a value set here arrives where the world is actually
  /// built. A top-level would not: `describeSystems` runs on the game
  /// isolate, where top-level state is back at its default.
  ///
  /// Not a slider, because `workerCount` is fixed when the Box2D world is
  /// created and a world cannot change it afterwards - a control that
  /// appeared to change it live would be lying. 1 creates no threads at all,
  /// so the interactive app measures what it always did.
  ///
  /// Whether it took effect is [solverThreads], which asks Box2D rather than
  /// echoing this back.
  int solverWorkerCount = 1;


  /// `Box2DPhysicsSystem`'s four phases, in microseconds, from the last fixed
  /// step.
  ///
  /// One total for "physics" cannot direct anything, because the four have
  /// four unrelated fixes: [fillMicros] and [syncMicros] are the ECS read and
  /// write sides and scale with body count; [solveMicros] is Box2D itself and
  /// scales with the *contact graph*; [contactMicros] is event dispatch and
  /// scales with touching pairs.
  late final StateChannel<int> fillMicros;
  late final StateChannel<int> solveMicros;
  late final StateChannel<int> syncMicros;
  late final StateChannel<int> contactMicros;

  /// What the world *contains*, which is what a solve time cannot say on its
  /// own.
  ///
  /// [awakeBodies] against the population separates a scene that is heavy
  /// from one that is merely agitated - a sleeping body is nearly free, so
  /// 4000 bodies of which 40 are awake and 4000 of which 4000 are awake cost
  /// two completely different amounts and need two completely different
  /// fixes. [broadPhasePairs] climbing much faster than the population is the
  /// signature of a pile that is overlapping rather than stacking.
  /// Bodies **Box2D** holds, which is not the same question as how many
  /// entities the case has. The two disagreeing is the signature of a leak,
  /// and they did: `Entity.destroy` did not fire the world-observation
  /// despawn event, so the physics system never released a destroyed entity's
  /// body and this number climbed without bound while `entities` held steady.
  /// Threads the **live** Box2D world is using, asked of Box2D on the game
  /// isolate rather than read off the value this side asked for.
  ///
  /// Those are different questions, and the difference is invisible in a step
  /// time: `physicsWorkerCount` is a top-level, and **top-level state does not
  /// cross `Isolate.spawn`** - so if the physics system is constructed on the
  /// game isolate it reads the default, whatever main was told.
  late final StateChannel<int> solverThreads;

  late final StateChannel<int> physicsBodies;

  /// Bodies that have ever left the box and been recycled, cumulatively. A
  /// number that keeps climbing means the population is capped by escapes
  /// rather than by the slider, and every reading taken above that cap is
  /// describing a smaller world than its label says.
  late final StateChannel<int> escapedBodies;
  late final StateChannel<int> awakeBodies;
  late final StateChannel<int> touchingPairs;
  late final StateChannel<int> broadPhasePairs;

  @override
  void describeState(StateDescriptor descriptor) {
    super.describeState(descriptor);
    fillMicros = descriptor.hasInt32();
    solveMicros = descriptor.hasInt32();
    syncMicros = descriptor.hasInt32();
    contactMicros = descriptor.hasInt32();
    solverThreads = descriptor.hasInt32();
    physicsBodies = descriptor.hasInt32();
    escapedBodies = descriptor.hasInt32();
    awakeBodies = descriptor.hasInt32();
    touchingPairs = descriptor.hasInt32();
    broadPhasePairs = descriptor.hasInt32();
  }

  @override
  PhysicsState createState() => PhysicsState();
}

/// Real Box2D, stepped in lockstep with the fixed tick.
class PhysicsDemo extends Demo {
  PhysicsDemo();

  late final PhysicsGame _game;

  @override
  String get name => 'Physics';

  @override
  String get blurb =>
      'Box2D v3 through FFI. Bodies flash on collision, so the event path '
      'is visible rather than merely plausible.';

  @override
  DemoGame create() => _game = PhysicsGame();

  @override
  DemoGame get game => _game;

  @override
  List<DemoSlider> get sliders => <DemoSlider>[
    DemoSlider(
      'bodies',
      (value) => _game.setPopulation(value),
      min: 0,
      // Well past what a phone will hold at 60 Hz on purpose: the point of
      // the slider is to find where the solver stops keeping up, and a
      // ceiling that never gets there cannot show it.
      max: 20000,
      initial: 120,
    ),
  ];

  /// The four phases of `Box2DPhysicsSystem`, so the overlay says *which* part
  /// of physics a frame went into rather than only that it did.
  ///
  /// The split is the whole point. On this machine at 4000 crushed bodies the
  /// step was 40 ms, of which the solver was 36 and everything on the Dart
  /// side - the ECS read, the ECS write and contact dispatch together - was
  /// 0.8. Without these lines that frame reads as "physics is slow" and sends
  /// you optimising the 2%.
  @override
  List<DemoStat> get stats => <DemoStat>[
    DemoStat('fill', _game.fillMicros, ms: true),
    DemoStat('solve', _game.solveMicros, ms: true),
    DemoStat('sync', _game.syncMicros, ms: true),
    DemoStat('contact', _game.contactMicros, ms: true),
    DemoStat('threads', _game.solverThreads),
    DemoStat('b2 bodies', _game.physicsBodies),
    DemoStat('escaped', _game.escapedBodies),
    DemoStat('awake', _game.awakeBodies),
    DemoStat('touching', _game.touchingPairs),
    DemoStat('bp pairs', _game.broadPhasePairs),
  ];
}
