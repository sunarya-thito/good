// #77: what the push guard does to a scripted static body.
//
// Requires the native library. packages/goo2d_ffi_box2d/README.md has the
// build for each platform.
//
// #74 gave static and kinematic bodies the same guard dynamic ones already had:
// a transform reaches Box2D only when it differs from what was last sent, by
// more than `positionEpsilon` or `angleEpsilon`. So a static body turned in
// increments below the angle threshold no longer reaches the solver every tick.
// It arrives where it was told; it arrives in steps.
//
// These pin the numbers `docs/guide/physics.md` now quotes, so the guide cannot
// drift away from the code without something going red.
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

late Game run;
late Box2DPhysicsSystem physics;
late _Scene _declaration;

class _Slab extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  final box = BoxBody.of(halfWidth: 2, halfHeight: 0.5);

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    bodyType.initialValue = BodyType2D.staticBody;
  }
}

class _Scene extends SceneStruct {
  late final _Slab slab;

  @override
  void describeScene(SceneDescriptor d) {
    super.describeScene(d);
    slab = d.has(_Slab.new);
  }
}

/// Scripts the slab from inside the tick window, the way a game would.
///
/// A component write outside a tick is discarded by the next `beginTick`, and
/// `data_layout` asserts on it - so a test cannot drive this from the outside
/// once the page has published.
class _Turner extends GameSystem with FixedTickable {
  Entity? target;
  double perTick = 0;
  double angle = 0;

  @override
  void onFixedUpdate() {
    final entity = target;
    if (entity == null) return;
    angle += perTick;
    _declaration.slab.transformRotation[entity] = angle;
  }
}

late _Turner _turner;

class _GameState extends GameState<_Game> {
  @override
  void onMounted() {}

  @override
  void describeSystems(SystemDescriptor d) {
    super.describeSystems(d);
    physics = d.has(Box2DPhysicsSystem.new);
    _turner = d.has(_Turner.new);
  }
}

class _Game extends Game {
  @override
  int get pageSize => 4096;

  late final _Scene arena;

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    arena = descriptor.has(_Scene.new);
  }

  @override
  GameState createState() => _GameState();
}

void _step([int times = 1]) {
  for (var i = 0; i < times; i++) {
    run.state.advance(const Duration(milliseconds: 20));
  }
}

Future<Scene> _boot() async {
  final game = await Game.startInline(_Game.new);
  run = game;
  _declaration = game.arena;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
    physics.dispose();
  });
  return run.state.loadScene(_declaration);
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test(
    'a static body turned below the angle threshold is sent in steps',
    () async {
      final scene = await _boot();
      final slab = scene.addEntity(_declaration.slab);
      final body = _declaration.slab;
      _step(2);

      _turner
        ..angle = _declaration.slab.transformRotation[slab]
        ..perTick = 0.001
        ..target = slab;

      // 0.001 rad a tick against a 5e-3 threshold: the guard lets one write
      // through per six, carrying the whole accumulated 0.006.
      var sends = 0;
      var last = body.bodySyncedAngle[slab];
      for (var tick = 0; tick < 24; tick++) {
        _step();
        final synced = body.bodySyncedAngle[slab];
        if ((synced - last).abs() > 1e-9) {
          sends++;
          last = synced;
        }
      }

      expect(
        sends,
        lessThan(8),
        reason:
            '24 ticks were written and far fewer reached the solver. Sending '
            'every tick is what #74 stopped doing, and what the guide now says '
            'happens instead',
      );
      expect(
        sends,
        greaterThan(0),
        reason: 'and it does keep arriving - nothing is dropped, only delayed',
      );
      expect(
        body.bodySyncedAngle[slab],
        closeTo(_turner.angle, 6e-3),
        reason:
            'the body ends within one threshold of everything written to it, '
            'so the difference is when it moves and not where it ends up',
      );
    },
  );

  test('a kinematic body never meets the angle threshold', () async {
    // The guide's recommendation, and why it is the recommendation: a
    // kinematic body is driven by velocity, so no transform write is compared
    // against anything and nothing is held back.
    final scene = await _boot();
    final slab = scene.addEntity(_declaration.slab);
    _declaration.slab.bodyType[slab] = BodyType2D.kinematicBody;
    _step(2);

    _declaration.slab.setAngularVelocity(slab, 0.05);
    final before = _declaration.slab.transformRotation[slab];
    _step(10);

    expect(
      _declaration.slab.transformRotation[slab],
      greaterThan(before),
      reason: 'it turned under its own velocity, with no threshold in the way',
    );
  });
}
