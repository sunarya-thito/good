import 'package:goo2d/goo2d.dart';
import 'package:flutter_test/flutter_test.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

class _CamEntity extends EntityStruct
    with Transform2D, WorldTransform2D, Camera {}

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
    cam = descriptor.has(_CamEntity.new);
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
      expect(
        ActiveCameraResolver().resolve(query, views.declareDetached()),
        isNull,
      );
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
      // Tests run with asserts enabled, so this is the debug-build behaviour:
      // two cameras is a development mistake that stops the run (the
      // assert-not-print rule - an assert, never a swallowed `print`). In a
      // release build the assert compiles out and the first camera is used.
      expect(
        () => ActiveCameraResolver().resolve(query, view),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('CameraProjection', () {
    test('defaults to identity at origin with zero viewport', () {
      final projection = CameraProjection();
      expect(projection.originX, 0);
      expect(projection.originY, 0);
      expect(projection.zoom, 1);
      expect(projection.halfViewWidth, 0);
      expect(projection.halfViewHeight, 0);
      expect(projection.sceneSlot, -1);
      expect(projection.camera, isNull);

      // Without a viewport offset and at zoom 1:
      // world X is view X; world Y is negated view Y (+y is up).
      expect(projection.worldToViewX(15), 15);
      expect(projection.worldToViewY(25), -25);
      expect(projection.viewToWorldX(15), 15);
      expect(projection.viewToWorldY(-25), 25);
    });

    test('world to view matches the projection formula directly', () {
      final projection = CameraProjection()
        ..originX = 100
        ..originY = 50
        ..zoom = 2
        ..halfViewWidth = 400
        ..halfViewHeight = 300;

      // view = (world - origin) * zoom + viewSize / 2, y negated.
      // The camera origin (100, 50) projects to the viewport center (400, 300).
      expect(projection.worldToViewX(100), 400);
      expect(projection.worldToViewY(50), 300);

      // Points away from origin:
      // (150, 70) -> x: (150 - 100)*2 + 400 = 500, y: (50 - 70)*2 + 300 = 260
      expect(projection.worldToViewX(150), 500);
      expect(projection.worldToViewY(70), 260);

      // (50, 30) -> x: (50 - 100)*2 + 400 = 300, y: (50 - 30)*2 + 300 = 340
      expect(projection.worldToViewX(50), 300);
      expect(projection.worldToViewY(30), 340);
    });

    test('view to world accurately inverts world to view', () {
      final projection = CameraProjection()
        ..originX = 100
        ..originY = 50
        ..zoom = 2
        ..halfViewWidth = 400
        ..halfViewHeight = 300;

      // View center (400, 300) inverts to camera origin (100, 50).
      expect(projection.viewToWorldX(400), 100);
      expect(projection.viewToWorldY(300), 50);

      // (500, 260) inverts to (150, 70)
      expect(projection.viewToWorldX(500), 150);
      expect(projection.viewToWorldY(260), 70);

      // (300, 340) inverts to (50, 30)
      expect(projection.viewToWorldX(300), 50);
      expect(projection.viewToWorldY(340), 30);

      // View top-left (0, 0):
      // worldX = (0 - 400)/2 + 100 = -100
      // worldY = 50 - (0 - 300)/2 = 200
      expect(projection.viewToWorldX(0), -100);
      expect(projection.viewToWorldY(0), 200);
    });

    test('round trip preserves coordinates in both directions', () {
      final projection = CameraProjection()
        ..originX = -32.5
        ..originY = 148.25
        ..zoom = 1.75
        ..halfViewWidth = 480
        ..halfViewHeight = 270;

      final testWorldPoints = <(double, double)>[
        (0.0, 0.0),
        (-32.5, 148.25),
        (100.0, -200.0),
        (-500.5, 300.25),
        (1234.56, 7890.12),
      ];

      for (final (wx, wy) in testWorldPoints) {
        final vx = projection.worldToViewX(wx);
        final vy = projection.worldToViewY(wy);
        expect(projection.viewToWorldX(vx), closeTo(wx, 1e-9));
        expect(projection.viewToWorldY(vy), closeTo(wy, 1e-9));
      }

      final testViewPoints = <(double, double)>[
        (0.0, 0.0),
        (480.0, 270.0),
        (960.0, 540.0),
        (-100.0, -50.0),
        (1920.0, 1080.0),
      ];

      for (final (vx, vy) in testViewPoints) {
        final wx = projection.viewToWorldX(vx);
        final wy = projection.viewToWorldY(vy);
        expect(projection.worldToViewX(wx), closeTo(vx, 1e-9));
        expect(projection.worldToViewY(wy), closeTo(vy, 1e-9));
      }
    });

    test('changing zoom scales distance from camera center', () {
      final projection = CameraProjection()
        ..originX = 0
        ..originY = 0
        ..halfViewWidth = 400
        ..halfViewHeight = 300;

      // At zoom 1, a point 50 units right is 50 pixels right of center (450)
      projection.zoom = 1;
      expect(projection.worldToViewX(50), 450);

      // At zoom 2, 50 units right is 100 pixels right of center (500)
      projection.zoom = 2;
      expect(projection.worldToViewX(50), 500);

      // At zoom 0.5, 50 units right is 25 pixels right of center (425)
      projection.zoom = 0.5;
      expect(projection.worldToViewX(50), 425);
    });

    test('changing camera origin translates the projected point', () {
      final projection = CameraProjection()
        ..zoom = 1
        ..halfViewWidth = 400
        ..halfViewHeight = 300;

      // Target point in world space
      const worldX = 100.0;
      const worldY = 100.0;

      projection.originX = 0;
      projection.originY = 0;
      expect(projection.worldToViewX(worldX), 500);
      expect(projection.worldToViewY(worldY), 200);

      // Panning camera +50 along world X moves view projection 50 pixels left
      projection.originX = 50;
      expect(projection.worldToViewX(worldX), 450);

      // Panning camera +50 along world Y moves view projection 50 pixels down
      projection.originY = 50;
      expect(projection.worldToViewY(worldY), 250);
    });

    test('changing viewport size shifts the center anchor', () {
      final projection = CameraProjection()
        ..originX = 0
        ..originY = 0
        ..zoom = 1;

      // In 800x600 viewport: center is (400, 300)
      projection.halfViewWidth = 400;
      projection.halfViewHeight = 300;
      expect(projection.worldToViewX(0), 400);
      expect(projection.worldToViewY(0), 300);

      // In 1600x1200 viewport: center is (800, 600)
      projection.halfViewWidth = 800;
      projection.halfViewHeight = 600;
      expect(projection.worldToViewX(0), 800);
      expect(projection.worldToViewY(0), 600);
    });

    test('up in world (+y) maps to down in view (-y) and vice versa', () {
      final projection = CameraProjection()
        ..originX = 0
        ..originY = 0
        ..zoom = 1
        ..halfViewWidth = 400
        ..halfViewHeight = 300;

      const lowerWorldY = 10.0;
      const higherWorldY = 50.0;

      // Higher world Y produces smaller view Y (higher on screen/canvas)
      expect(
        projection.worldToViewY(higherWorldY),
        lessThan(projection.worldToViewY(lowerWorldY)),
      );

      const topViewY = 100.0;
      const bottomViewY = 500.0;

      // Smaller view Y (higher on screen) produces larger world Y (higher in world)
      expect(
        projection.viewToWorldY(topViewY),
        greaterThan(projection.viewToWorldY(bottomViewY)),
      );
    });

    test('zero zoom returns camera origin instead of infinity or NaN', () {
      final projection = CameraProjection()
        ..originX = 42
        ..originY = -84
        ..zoom = 0
        ..halfViewWidth = 400
        ..halfViewHeight = 300;

      expect(projection.viewToWorldX(100), 42);
      expect(projection.viewToWorldY(100), -84);
      expect(projection.viewToWorldX(-999), 42);
      expect(projection.viewToWorldY(999), -84);
    });

    test('shows filters entities by sceneSlot', () {
      final sceneA = _scene();
      final sceneB = _scene();

      sceneA.pool.beginTick();
      final entityA = sceneA.addEntity(sceneA.cam);
      sceneA.pool.commitTick();

      sceneB.pool.beginTick();
      final entityB = sceneB.addEntity(sceneB.cam);
      sceneB.pool.commitTick();

      final projection = CameraProjection()..sceneSlot = entityA.sceneSlot;
      expect(projection.shows(entityA), isTrue);
      expect(projection.shows(entityB), isFalse);

      // When sceneSlot < 0, everything is shown (no scoping)
      projection.sceneSlot = -1;
      expect(projection.shows(entityA), isTrue);
      expect(projection.shows(entityB), isTrue);
    });

    test('resolve populates projection from active camera and CameraView', () async {
      final scene = _scene();
      final query = await _query(scene);
      final game = run as _CamGame;
      game.view.setViewport(800, 600);

      final view = views.declareDetached();
      scene.pool.beginTick();
      final camera = scene.addEntity(scene.cam);
      scene.cam.view[camera] = view;
      scene.cam.zoom[camera] = 3;
      scene.cam.worldX[camera] = 120;
      scene.cam.worldY[camera] = -60;
      scene.pool.commitTick();

      // The active camera matches view by pack() address, while game.view
      // supplies the live viewport dimensions from Game's shared memory.
      final projection = CameraProjection()..resolve(query, game.view);

      expect(projection.camera, camera);
      expect(projection.originX, 120);
      expect(projection.originY, -60);
      expect(projection.zoom, 3);
      expect(projection.halfViewWidth, 400);
      expect(projection.halfViewHeight, 300);
      expect(projection.sceneSlot, camera.sceneSlot);
      expect(projection.shows(camera), isTrue);
    });

    test('resolve resets to identity when no camera occupies the view', () async {
      final scene = _scene();
      final query = await _query(scene);
      final game = run as _CamGame;
      game.view.setViewport(800, 600);

      final projection = CameraProjection()..resolve(query, game.view);

      expect(projection.camera, isNull);
      expect(projection.originX, 0);
      expect(projection.originY, 0);
      expect(projection.zoom, 1);
      expect(projection.halfViewWidth, 400);
      expect(projection.halfViewHeight, 300);
      expect(projection.sceneSlot, -1);
    });

    test('resolve takes the culling rectangle off the viewport', () async {
      final scene = _scene();
      final query = await _query(scene);
      final game = run as _CamGame;
      game.view.setViewport(800, 600);

      final projection = CameraProjection()..resolve(query, game.view);

      expect(projection.viewLeft, 0);
      expect(projection.viewTop, 0);
      expect(projection.viewRight, 800);
      expect(projection.viewBottom, 600);
    });

    test('a view nobody laid out culls nothing', () async {
      final scene = _scene();
      final query = await _query(scene);
      final game = run as _CamGame;
      // Deliberately no setViewport: a headless run, and the first tick of
      // every real game before its GameView has laid out once.

      final projection = CameraProjection()..resolve(query, game.view);

      expect(projection.viewLeft, double.negativeInfinity);
      expect(projection.viewTop, double.negativeInfinity);
      expect(projection.viewRight, double.infinity);
      expect(projection.viewBottom, double.infinity);
      expect(
        projection.showsCircle(1e9, -1e9, 0),
        isTrue,
        reason:
            'zero is not a small viewport, it is an unknown one - culling '
            'against it would hide the whole world from every test that '
            'never built a widget',
      );
    });

    test('a view that loses its size stops culling', () async {
      final scene = _scene();
      final query = await _query(scene);
      final game = run as _CamGame;
      game.view.setViewport(800, 600);
      final projection = CameraProjection()..resolve(query, game.view);
      expect(projection.viewRight, 800);

      // A GameView that goes away, or a resize that passes through zero.
      // The rectangle has to come back off the view every tick rather than
      // being latched, or the last size a view had would keep culling for a
      // view nothing is showing.
      game.view.setViewport(0, 0);
      projection.resolve(query, game.view);

      expect(projection.viewRight, double.infinity);
      expect(projection.showsCircle(1e9, 1e9, 0), isTrue);
    });

    test('one axis without the other is still an unknown viewport', () async {
      final scene = _scene();
      final query = await _query(scene);
      final game = run as _CamGame;
      // Mid-layout: a width has arrived and a height has not. Half a
      // rectangle is not a rectangle, and treating it as a 800x0 one would
      // cull the entire scene for that frame.
      game.view.setViewport(800, 0);

      final projection = CameraProjection()..resolve(query, game.view);

      expect(projection.viewRight, double.infinity);
      expect(projection.showsCircle(4000, 4000, 0), isTrue);
    });

    test('showsCircle accepts anything that reaches the rectangle', () {
      final projection = CameraProjection()
        ..viewLeft = 0
        ..viewTop = 0
        ..viewRight = 800
        ..viewBottom = 600;

      // Inside, with no extent at all.
      expect(projection.showsCircle(400, 300, 0), isTrue);
      // Outside each edge by 10, with a radius of 20 (squared: 400).
      expect(projection.showsCircle(-10, 300, 400), isTrue);
      expect(projection.showsCircle(810, 300, 400), isTrue);
      expect(projection.showsCircle(400, -10, 400), isTrue);
      expect(projection.showsCircle(400, 610, 400), isTrue);
      // Exactly touching a corner counts. `<=`, not `<`: a sprite whose edge
      // lands on the border is on screen, and half a pixel of rounding must
      // not be what decides it.
      expect(projection.showsCircle(-3, -4, 25), isTrue);
    });

    test('showsCircle rejects only what clears the rectangle', () {
      final projection = CameraProjection()
        ..viewLeft = 0
        ..viewTop = 0
        ..viewRight = 800
        ..viewBottom = 600;

      // Outside each edge by 30, radius 20 (squared: 400 < 900).
      expect(projection.showsCircle(-30, 300, 400), isFalse);
      expect(projection.showsCircle(830, 300, 400), isFalse);
      expect(projection.showsCircle(400, -30, 400), isFalse);
      expect(projection.showsCircle(400, 630, 400), isFalse);

      // Diagonally clear of the top-left corner. 30 out on each axis is 1800
      // squared away, so a radius of 40 (1600) does not reach - even though
      // 40 clears 30 on either axis taken alone. Testing the corner rather
      // than two independent slabs is what makes this a rejection.
      expect(projection.showsCircle(-30, -30, 1600), isFalse);
      expect(projection.showsCircle(-30, -30, 1801), isTrue);
    });

    test('showsCircle keeps a sprite whose transform has gone wrong', () {
      final projection = CameraProjection()
        ..viewLeft = 0
        ..viewTop = 0
        ..viewRight = 800
        ..viewBottom = 600;

      // NaN loses every comparison, so the distance comes out zero and the
      // circle is treated as sitting on the view. Drawing something wrong in
      // an obvious place beats making it disappear, which reads as a culling
      // bug rather than as the transform bug it is.
      expect(projection.showsCircle(double.nan, 300, 0), isTrue);
      expect(projection.showsCircle(400, double.nan, 0), isTrue);
      expect(projection.showsCircle(400, 300, double.nan), isTrue);
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
  final cameras = Query.all(Camera);
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
    super.describeSystems(descriptor);
    descriptor.has(_CameraQuerySystem());
  }
}

class _CamGame extends Game {
  @override
  int get pageSize => 4096;

  _CamGame(this._scene);

  final _Scene _scene;

  late final CameraView view;

  @override
  void describeCameras(CameraDescriptor descriptor) {
    super.describeCameras(descriptor);
    view = descriptor.has();
  }

  @override
  GameState createState() => _CamState(_scene);
}
