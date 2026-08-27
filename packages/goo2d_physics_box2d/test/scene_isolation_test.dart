// #106: one Box2D world per loaded scene.
//
// Requires the native library. packages/goo2d_ffi_box2d/README.md has the
// build for each platform.
//
// Physics was the last subsystem treating something per-scene as global. One
// world for the whole game meant a dynamic body in one scene rested on static
// geometry in another, and `overlapBox` returned shapes from two scenes
// interleaved with `layerMask` the only way to tell them apart - a budget that
// exists for something else. A scene is this engine's isolation boundary
// everywhere else: hierarchy edges refuse to cross one, pages carry
// `ownerSceneSlot` and are freed per scene, and a view draws only the scene its
// camera occupies.
//
// The scenes here are two loaded copies of **one** `SceneStruct`, which is the
// case that matters and the one a single-scene fixture cannot reach. Their
// handles come from `loadScene`'s return rather than a field on the
// declaration, because such a field is overwritten by the second mount
// (#104).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_ffi_box2d/goo2d_ffi_box2d.dart' show box2d;
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

late Game run;
late Box2DPhysicsSystem physics;
late _PhysScene _declaration;

/// Static, one unit half-height, so its top face is at y = +1.
class _Wall extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor d) {
    super.describeCollider(d);
    box = d.hasBoxCollider(halfWidth: 4, halfHeight: 1);
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    bodyType.defaultValue = BodyType2D.staticBody;
  }
}

/// Dynamic, half a unit high, so it comes to rest at y = 1.5 on the wall.
class _Ball extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor d) {
    super.describeCollider(d);
    box = d.hasBoxCollider(halfWidth: 0.5, halfHeight: 0.5);
  }
}

class _PhysScene extends SceneStruct {
  late final _Wall wall;
  late final _Ball ball;

  @override
  void describeScene(SceneDescriptor d) {
    super.describeScene(d);
    wall = d.has(_Wall.new);
    ball = d.has(_Ball.new);
  }
}

class _GameState extends GameState<_Game> {
  @override
  void onMounted() {}

  @override
  void describeSystems(SystemDescriptor d) {
    super.describeSystems(d);
    physics = d.has(Box2DPhysicsSystem.new);
  }
}

class _Game extends Game {
  @override
  int get pageSize => 4096;

  late final _PhysScene arena;

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    arena = descriptor.has(_PhysScene());
  }

  @override
  GameState createState() => _GameState();
}

void _settle([int steps = 150]) {
  for (var i = 0; i < steps; i++) {
    run.state.advance(const Duration(milliseconds: 20));
  }
}

Future<GameState> _boot() async {
  final game = _Game();
  run = await Game.startInline(game);
  _declaration = game.arena;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
    physics.dispose();
  });
  return run.state;
}

double _ballY(Entity entity) => _declaration.ball.transformOffsetY[entity];

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('a body does not rest on geometry in another scene', () async {
    final state = await _boot();
    final a = await state.loadScene(_declaration);
    final b = await state.loadScene(_declaration);
    expect(a, isNot(b));

    // The wall is in B; the ball is in A, directly above where that wall sits.
    final wall = b.addEntity(_declaration.wall);
    _declaration.wall.transformOffsetY[wall] = 0;

    final ball = a.addEntity(_declaration.ball);
    _declaration.ball.transformOffsetY[ball] = 6;

    _settle();

    // One shared world: it lands on B's wall and stops at 1.5. Its own world:
    // that wall is not in it, so nothing catches it.
    expect(
      _ballY(ball),
      lessThan(0),
      reason:
          'the ball fell past where a wall in another scene would have caught '
          'it. Resting near 1.5 is the shared-world behaviour this fixes',
    );
  });

  test('each loaded scene gets its own world', () async {
    final state = await _boot();
    final a = await state.loadScene(_declaration);
    final b = await state.loadScene(_declaration);
    a.addEntity(_declaration.wall);
    b.addEntity(_declaration.wall);
    _settle(2);

    expect(physics.worldOf(a), isNot(0));
    expect(physics.worldOf(b), isNot(0));
    expect(
      physics.worldOf(a),
      isNot(physics.worldOf(b)),
      reason: 'two loaded copies of one declaration are two worlds',
    );
  });

  test('a query sees only the scene it names', () async {
    final state = await _boot();
    final a = await state.loadScene(_declaration);
    final b = await state.loadScene(_declaration);

    final wall = b.addEntity(_declaration.wall);
    _declaration.wall.transformOffsetY[wall] = 0;
    _settle(2);

    expect(physics.overlapBox(b, -5, -5, 5, 5), 1, reason: 'the wall is in B');
    expect(
      physics.overlapBox(a, -5, -5, 5, 5),
      0,
      reason:
          'and A cannot see it. One shared world used to return both scenes '
          'interleaved, with layerMask the only way to separate them',
    );
    expect(physics.raycast(b, -10, 0, 20, 0), isTrue);
    expect(physics.raycast(a, -10, 0, 20, 0), isFalse);
  });

  test('a joint refuses to cross scenes, in our words', () async {
    final state = await _boot();
    final a = await state.loadScene(_declaration);
    final b = await state.loadScene(_declaration);

    final here = a.addEntity(_declaration.wall);
    final there = b.addEntity(_declaration.ball);
    _settle(2);

    expect(
      () => physics.createDistanceJoint(here, there),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          allOf(contains('no solver in common'), contains('scene slot')),
        ),
      ),
      reason:
          'two bodies in different b2Worlds cannot be jointed at all, so the '
          'refusal has to be ours and legible rather than whatever Box2D does',
    );
  });

  test('unloading a scene with live bodies leaves the rest simulating', () async {
    // The ordering trap. `onSceneUnloaded` destroys the world *before* the
    // scene's entities are despawned, so every one of them then reaches
    // `onEntityDespawned` with its world already released. Calling
    // `gooBodyDestroy` there walks freed memory - a native use-after-free that
    // kills the isolate with no Dart exception, so the symptom is a run that
    // simply stops rather than a failure.
    final state = await _boot();
    final a = await state.loadScene(_declaration);
    final b = await state.loadScene(_declaration);

    final doomedWall = a.addEntity(_declaration.wall);
    _declaration.wall.transformOffsetY[doomedWall] = 0;
    a.addEntity(_declaration.ball);

    final keptWall = b.addEntity(_declaration.wall);
    _declaration.wall.transformOffsetY[keptWall] = 0;
    final keptBall = b.addEntity(_declaration.ball);
    _declaration.ball.transformOffsetY[keptBall] = 6;
    _settle(3);

    state.unloadScene(a);
    _settle();

    expect(run.isRunning, isTrue, reason: 'the isolate survived the unload');
    expect(
      _ballY(keptBall),
      closeTo(1.5, 0.2),
      reason:
          'B still has its own world, its wall and its ball, and the ball '
          'came to rest on it after A went away',
    );
  });

  test('unloading destroys the world itself, not just the bookkeeping', () async {
    // Break 3 in the falsification pass - dropping the map entry without
    // calling `gooWorldDestroy` - leaked a world and every body in it, and no
    // other case here noticed: from Dart the entry is gone either way. Box2D
    // is the only witness, so this asks it. A destroyed world takes its bodies
    // with it, which is exactly what makes the per-body teardown unnecessary
    // and the guard above necessary.
    final state = await _boot();
    final a = await state.loadScene(_declaration);
    final b = await state.loadScene(_declaration);
    final doomed = a.addEntity(_declaration.wall);
    b.addEntity(_declaration.wall);
    _settle(3);

    final handle = _declaration.wall.bodyHandle[doomed];
    expect(handle, isNot(0), reason: 'the wall got a body');
    expect(box2d.gooBodyIsValid(handle), isNot(0), reason: 'alive before');

    state.unloadScene(a);

    expect(
      box2d.gooBodyIsValid(handle),
      0,
      reason: 'the scene took its whole world with it',
    );
  });

  test('destroying one entity still destroys its body', () async {
    // The ordinary case, which the unload guard must not regress: the scene is
    // still loaded, so the world is still there and the body has to go.
    final state = await _boot();
    final a = await state.loadScene(_declaration);

    final wall = a.addEntity(_declaration.wall);
    _settle(2);
    final before = physics.counters(Int32List(5))[0];
    expect(before, greaterThan(0), reason: 'the wall has a body');

    wall.destroy();
    _settle(2);

    expect(
      physics.counters(Int32List(5))[0],
      before - 1,
      reason: 'its body went with it, and the world is still there',
    );
  });
}
