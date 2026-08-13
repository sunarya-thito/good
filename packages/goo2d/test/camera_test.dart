import 'package:goo2d/goo2d.dart';
import 'package:flutter_test/flutter_test.dart';

class _CamEntity extends EntityStruct<_CamEntity> with Transform2D, WorldTransform2D, Camera {}

class _Scene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct<T>>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Scene();

  late final _CamEntity cam;

  @override
  void describeScene(SceneDescriptor descriptor) {
    cam = descriptor.has(_CamEntity());
  }
}

_Scene _scene() {
  final scene = _Scene()..initializeScene(MemoryPool(pageSize: 4096));
  scene.handle = SceneRegistry.register(scene);
  addTearDown(scene.pool.dispose);
  return scene;
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('zoom defaults to 1', () {
    final scene = _scene();
    scene.pool.beginTick();
    final camera = scene.addEntity(scene.cam);
    scene.pool.commitTick();
    expect(scene.cam.zoom[camera], 1);
  });

  group('ActiveCameraResolver', () {
    test('returns null when no camera is active', () async {
      final scene = _scene();
      final query = await _query(scene);
      expect(ActiveCameraResolver().resolve(query), isNull);
    });

    test('returns the only active camera', () async {
      final scene = _scene();
      scene.pool.beginTick();
      final camera = scene.addEntity(scene.cam);
      scene.pool.commitTick();
      final query = await _query(scene);
      expect(ActiveCameraResolver().resolve(query), camera);
    });

    test('a second enabled camera trips a debug assert rather than being ignored', () async {
      final scene = _scene();
      scene.pool.beginTick();
      scene.addEntity(scene.cam);
      scene.addEntity(scene.cam);
      scene.pool.commitTick();
      final query = await _query(scene);
      // Tests run with asserts enabled, so this is the debug-build
      // behaviour: two cameras is a development mistake that stops the run
      // (RULES.md rule 7 - an assert, never a swallowed `print`). In a
      // release build the assert compiles out and the first camera is used.
      expect(() => ActiveCameraResolver().resolve(query), throwsA(isA<AssertionError>()));
    });
  });
}

Future<Query> _query(_Scene scene) async {
  // A minimal standalone GameSystem, only to get a bound QueryDescriptor -
  // ActiveCameraResolver itself takes a plain Query, not a Game/GameSystem.
  final game = _CamGame(scene);
  await game.start(inline: true, autoTick: false);
  addTearDown(() async {
    if (game.isRunning) await game.stop();
  });
  return game.getSystem<_CameraQuerySystem>().cameras;
}

class _CameraQuerySystem extends GameSystem {
  late final Query cameras;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    cameras = descriptor.query().withAll(Camera).build();
  }
}

class _CamState extends GameState<_CamGame> with LifecycleListener {
  _CamState(this._scene);

  final _Scene _scene;

  @override
  void onMounted() {
    loadScene(_scene);
  }
}

class _CamGame extends Game {
  @override
  int get pageSize => 4096;

  _CamGame(this._scene);

  final _Scene _scene;

  @override
  GameState createState() => _CamState(_scene);

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_CameraQuerySystem());
  }
}
