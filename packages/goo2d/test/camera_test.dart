import 'package:goo2d/goo2d.dart';
import 'package:flutter_test/flutter_test.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;


class _CamEntity extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

class _Scene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Scene();

  late final _CamEntity cam;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    cam = descriptor.has(_CamEntity());
  }
}

/// The fixture's own view table - a headless scene has no `Game`, so it owns
/// one, exactly as it owns its own `GameAssets`.
late CameraViewTable views;
late CameraView mainView;

_Scene _scene() {
  views = CameraViewTable();
  final scene = _Scene()
    ..initializeScene(MemoryPool(pageSize: 4096), cameraViews: views);
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
      expect(ActiveCameraResolver().resolve(query, views.declareDetached()), isNull);
    });

    test('returns the only active camera', () async {
      final scene = _scene();
      scene.pool.beginTick();
      final camera = scene.addEntity(scene.cam);
      scene.pool.commitTick();
      final view = views.declareDetached();
      scene.pool.beginTick();
      scene.cam.view[camera] = view;
      scene.pool.commitTick();
      final query = await _query(scene);
      expect(ActiveCameraResolver().resolve(query, view), camera);
    });

    test('a second camera in the same view trips a debug assert', () async {
      final scene = _scene();
      final view = views.declareDetached();
      scene.pool.beginTick();
      final a = scene.addEntity(scene.cam);
      final b = scene.addEntity(scene.cam);
      scene.pool.commitTick();
      scene.pool.beginTick();
      scene.cam.view[a] = view;
      scene.cam.view[b] = view;
      scene.pool.commitTick();
      final query = await _query(scene);
      // Tests run with asserts enabled, so this is the debug-build
      // behaviour: two cameras is a development mistake that stops the run
      // (RULES.md rule 7 - an assert, never a swallowed `print`). In a
      // release build the assert compiles out and the first camera is used.
      expect(() => ActiveCameraResolver().resolve(query, view),
          throwsA(isA<AssertionError>()));
    });
  });
}

Future<Query> _query(_Scene scene) async {
  // A minimal standalone GameSystem, only to get a bound QueryDescriptor -
  // ActiveCameraResolver itself takes a plain Query, not a Game/GameSystem.
  final game = _CamGame(scene);
  run = await Game.startInline(game);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return run.state.getSystem<_CameraQuerySystem>().cameras;
}

class _CameraQuerySystem extends GameSystem {
  late final Query cameras;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    cameras = descriptor.query().withAll(Camera).build();
  }
}

class _CamState extends GameState<_CamGame> {
  _CamState(this._scene);

  final _Scene _scene;

  @override
  void onMounted() {
    loadScene(_scene);
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_CameraQuerySystem());
  }
}

class _CamGame extends Game {
  @override
  int get pageSize => 4096;

  _CamGame(this._scene);

  final _Scene _scene;

  @override
  GameState createState() => _CamState(_scene);
}
