import 'dart:math' as math;

import 'package:goo2d/goo2d.dart';

import 'package:goo2d_example/demo/demo.dart';
import 'package:goo2d_example/demo/demo_game.dart';
import 'package:goo2d_example/demo/textures.dart';

/// A body with orbiting limbs - the shape a character, a vehicle or anything
/// with attachments has.
///
/// `Parent` because it owns limbs, `Child` because the whole swarm hangs off
/// one [Hub], `WorldTransform2D` because its limbs need a composed transform
/// to compose against. That full set is what a scene graph costs, and it is
/// the entire difference between this case and the flat one - same sprite,
/// same texture, same movement.
class Critter extends EntityStruct
    with
        Transform2D,
        WorldTransform2D,
        Child,
        Parent,
        Renderable2D,
        EntityLifecycleListener {
  late final Sprite body;
  final texture = Asset.of(discTexture);

  final angle = Field.float64();
  final radius = Field.float64();
  final spin = Field.float64();

  /// Seconds left. A critter that expires takes its limbs with it, because
  /// `Scene.removeEntity` destroys the subtree - which is the cheapest
  /// demonstration there is that the hierarchy is real.
  final life = Field.float64();

  int _spawned = 0;


  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    body = descriptor.has(width: 22, height: 22, texture: texture);
  }

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    final i = _spawned++;
    final t = i * 2.39996322972865332;
    // Inside a fixed disc, for the reason `Mote` spells out: a radius that
    // grew with the index put every batch after the first off-screen, so
    // spawning changed a counter and nothing you could see.
    final u = (i * 0.6180339887498949) % 1.0;
    final r = 90 + 300 * math.sqrt(u);
    angle[entity] = t;
    radius[entity] = r;
    spin[entity] = 0.9 / (1 + r * 0.004);
    life[entity] = 2.2 + 3.6 * ((i * 0.7548776662466927) % 1.0);
    transformOffsetX[entity] = math.cos(t) * r;
    transformOffsetY[entity] = math.sin(t) * r;
    // The **same expression** the update loop uses, evaluated at this
    // entity's starting angle. Leaving it out left the field at its default
    // 0 for the one frame between mounting and the first update, and the
    // update then wrote an angle thousands of radians in - so a freshly
    // spawned critter snapped through an arbitrary rotation on its second
    // frame, dragging its limbs with it. An entity has to be *finished* when
    // it is mounted, not finished by the first pass that happens to see it.
    transformRotation[entity] = t * 3;
    body
      ..color[entity] = 0xFFFFE9A8
      ..zIndex[entity] = 1000;
  }
}

/// One limb, parented to a [Critter] and never moved directly.
///
/// Its own `Transform2D` is a *fixed* local offset written once at spawn, and
/// nothing ever writes it again. Everything you see it do on screen - orbiting
/// its body, travelling with it across the field, swinging as the body turns -
/// is `WorldTransformSystem` composing that constant against its ancestors.
/// That is the whole demonstration: no system in this file touches a limb
/// after it is created.
class Limb extends EntityStruct
    with
        Transform2D,
        WorldTransform2D,
        Child,
        Renderable2D,
        EntityLifecycleListener {
  late final Sprite body;
  final texture = Asset.of(discTexture);

  int _spawned = 0;


  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    body = descriptor.has(width: 11, height: 11, texture: texture);
  }

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    final i = _spawned++;
    // Three limbs per critter, spaced round it. Constant from here on.
    final slot = i % limbsPerCritter;
    final a = slot * (2 * math.pi / limbsPerCritter);
    transformOffsetX[entity] = math.cos(a) * 26;
    transformOffsetY[entity] = math.sin(a) * 26;
    body
      ..color[entity] = switch (slot) {
        0 => 0xFF7FD1FF,
        1 => 0xFFFF8FB1,
        _ => 0xFFA8F0C6,
      }
      ..zIndex[entity] = 900;
  }

  static const int limbsPerCritter = 3;
}

/// The single node the whole swarm hangs off, so there is a real two-level
/// chain above every limb: hub -> critter -> limb. Rotating this alone moves
/// every entity in the case, and nothing but this is written to do it.
class Hub extends EntityStruct with Transform2D, WorldTransform2D, Parent {}

class Eye extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

class Swarm extends SceneStruct {
  @child
  final critter = Critter();
  @child
  final limb = Limb();
  @child
  final hub = Hub();
  @child
  final eye = Eye();

  /// The one entity this scene creates itself, so spawns have something to
  /// parent to. Scene *content* rather than a handle - which is why it lives
  /// here and the `Scene` does not.
  late Entity hubEntity;


  @override
  void onSceneMounted(Scene scene) {
    scene.addEntity(eye);
    hubEntity = scene.addEntity(hub);
  }
}

/// Moves **only** bodies and the hub. Limbs follow because they are parented,
/// which is the point.
class CritterSystem extends GameSystem with FixedTickable {
  final critters = Query.all(Transform2D, Critter);
  final hubs = Query.all(Transform2D, Hub);

  final Stopwatch _clock = Stopwatch();

  double _time = 0;

  /// After `WorldTransformSystem` would be wrong and before it is required:
  /// this writes the *local* transforms that pass then composes, so it has to
  /// run first. Declaring it the other way round would show every entity one
  /// frame behind its own body.
  @override
  int compareTo(GameSystem other) => other is WorldTransformSystem ? -1 : 0;

  /// Capped per step so dragging the slider is a fill you can watch. Lower
  /// than the flat case's, because one spawn here is four entities and a
  /// three-link splice rather than one row.
  static const int _maxSpawnPerTick = 80;

  @override
  void onFixedUpdate() {
    _clock
      ..reset()
      ..start();
    final demo = getState<SceneGraphState>();
    final dt = state.game.fixedTimeStep.inMicroseconds / 1000000.0;
    _time += dt;
    var alive = 0;

    for (final group in hubs.groups()) {
      final transform = group<Transform2D>();
      for (final entity in group) {
        // One entity, one field. Every critter and every limb in the case
        // moves because of this line and nothing else.
        transform.transformRotation[entity] = _time * 0.25;
      }
    }

    for (final group in critters.groups()) {
      final transform = group<Transform2D>();
      final critter = group<Critter>();
      for (final entity in group) {
        final remaining = critter.life[entity] - dt;
        if (remaining <= 0) {
          // One call, four entities: the body and the three limbs under it.
          entity.destroy();
          continue;
        }
        critter.life[entity] = remaining;
        alive++;

        final a = critter.angle[entity] + critter.spin[entity] * dt;
        final r = critter.radius[entity];
        critter.angle[entity] = a;
        transform
          ..transformOffsetX[entity] = math.cos(a) * r
          ..transformOffsetY[entity] = math.sin(a) * r
          // The body turns, so its limbs swing round it - composed, not
          // animated. Nothing writes a limb's transform after spawn.
          ..transformRotation[entity] = a * 3;
      }
    }
    final shortfall = demo.targetPopulation - alive;
    if (shortfall > 0) {
      final batch = shortfall < _maxSpawnPerTick ? shortfall : _maxSpawnPerTick;
      for (var i = 0; i < batch; i++) {
        demo.spawnCritter();
      }
      alive += batch;
    }

    // Every entity, not every critter: the limbs are what the sprite count and
    // the timings are actually paying for.
    demo
      ..spawnedCount = alive * (1 + Limb.limbsPerCritter)
      ..caseMicros = _clock.elapsedMicroseconds;
    _clock.stop();
  }
}

class SceneGraphState extends DemoState<SceneGraphGame> {
  final Swarm swarm = Swarm();

  @override
  void onMounted() => loadScene(swarm);

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(CritterSystem.new);
  }

  /// One critter and its three limbs, **all in the same tick**.
  ///
  /// That is worth saying out loud: `Parent.addChild` reads the tail of the
  /// child chain to append to it, and an ordinary read sees the last published
  /// snapshot - so three `addChild` calls in one tick each read the same stale
  /// tail, and every limb but the last used to be silently orphaned. It reads
  /// the pending slot now (`DataPointer.readPending`); this case is what
  /// found it.
  void spawnCritter() {
    final scene = loadedScenes.single;
    final critter = scene.addEntity(swarm.critter, parent: swarm.hubEntity);
    for (var i = 0; i < Limb.limbsPerCritter; i++) {
      scene.addEntity(swarm.limb, parent: critter);
    }
  }
}

class SceneGraphGame extends DemoGame {
  @override
  SceneGraphState createState() => SceneGraphState();
}

/// A two-level hierarchy under one root, where only the roots and the bodies
/// are ever written and everything else follows by composition.
class SceneGraphDemo extends Demo {
  SceneGraphDemo();

  late final SceneGraphGame _game;

  @override
  String get name => 'Swarm';

  @override
  String get blurb =>
      'hub -> body -> limb. Only bodies move; limbs are composed, never '
      'animated.';

  @override
  DemoGame create() => _game = SceneGraphGame();

  @override
  DemoGame get game => _game;

  @override
  List<DemoSlider> get sliders => <DemoSlider>[
    DemoSlider(
      'critters',
      (value) => _game.setPopulation(value),
      min: 0,
      max: 4000,
      initial: 400,
    ),
  ];
}
