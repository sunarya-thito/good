import 'package:flutter_test/flutter_test.dart';
import 'package:goo3d/goo3d.dart';

part 'camera_3d_test.g.dart';

/// A camera that declares nothing, to pin what a prefab gets for free.
class _DefaultEye extends EntityStruct
    with Transform3D, WorldTransform3D, Camera3D {}

/// A camera that moves all three defaults, the way the guide writes one.
class _WideEye extends EntityStruct
    with Transform3D, WorldTransform3D, Camera3D {
  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    cameraFieldOfView.initialValue = 90;
    cameraNear.initialValue = 0.5;
    cameraFar.initialValue = 250;
  }
}

class _Scene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene`, so a
  /// headless fixture registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Scene();

  late final _DefaultEye defaultEye;
  late final _WideEye wideEye;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    defaultEye = descriptor.has(_DefaultEye.new);
    wideEye = descriptor.has(_WideEye.new);
  }
}

/// The fixture's own view table - a headless scene has no `Game`, so it owns
/// one.
late CameraViewTable views;

_Scene _scene() {
  views = CameraViewTable();
  final scene = _Scene()
    ..initializeScene(MemoryPool(pageSize: 4096), cameraViews: views);
  scene.handle = SceneRegistry.register(scene);
  addTearDown(scene.pool.dispose);
  return scene;
}

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('a camera that declares nothing gets the documented defaults', () {
    final scene = _scene();
    scene.pool.beginTick();
    final eye = scene.addEntity(scene.defaultEye);
    scene.pool.commitTick();

    expect(scene.defaultEye.cameraFieldOfView[eye], 60);
    expect(scene.defaultEye.cameraNear[eye], 0.1);
    expect(scene.defaultEye.cameraFar[eye], 1000);
    expect(scene.defaultEye.cameraView[eye], isNull);
  });

  test('an overridden default lands in the row, with nothing written at '
      'mount time', () {
    final scene = _scene();
    scene.pool.beginTick();
    final eye = scene.addEntity(scene.wideEye);
    scene.pool.commitTick();

    expect(scene.wideEye.cameraFieldOfView[eye], 90);
    expect(scene.wideEye.cameraNear[eye], 0.5);
    expect(scene.wideEye.cameraFar[eye], 250);
  });

  test('one prefab moving its defaults leaves another mixing Camera3D '
      'alone', () {
    final scene = _scene();
    scene.pool.beginTick();
    final wide = scene.addEntity(scene.wideEye);
    final plain = scene.addEntity(scene.defaultEye);
    scene.pool.commitTick();

    expect(scene.wideEye.cameraNear[wide], 0.5);
    expect(scene.defaultEye.cameraNear[plain], 0.1, reason: 'per archetype');
  });

  test('the declared values are defaults, not constants', () {
    final scene = _scene();
    scene.pool.beginTick();
    final eye = scene.addEntity(scene.wideEye);
    scene.pool.commitTick();

    // A zoom-in is a field-of-view change at run time, so the declaration
    // cannot be the last word on it.
    scene.pool.beginTick();
    scene.wideEye.cameraFieldOfView[eye] = 30;
    scene.pool.commitTick();
    expect(scene.wideEye.cameraFieldOfView[eye], 30);
  });

  test('two entities of one camera prefab carry their own field of view', () {
    final scene = _scene();
    scene.pool.beginTick();
    final a = scene.addEntity(scene.wideEye);
    final b = scene.addEntity(scene.wideEye);
    scene.pool.commitTick();

    scene.pool.beginTick();
    scene.wideEye.cameraFieldOfView[a] = 20;
    scene.pool.commitTick();

    expect(scene.wideEye.cameraFieldOfView[a], 20);
    expect(
      scene.wideEye.cameraFieldOfView[b],
      90,
      reason: 'per row, not per prefab',
    );
  });

  test('a camera takes the view it was pointed at', () {
    final scene = _scene();
    scene.pool.beginTick();
    final eye = scene.addEntity(scene.defaultEye);
    scene.pool.commitTick();

    final view = views.declareDetached();
    scene.pool.beginTick();
    scene.defaultEye.cameraView[eye] = view;
    scene.pool.commitTick();

    expect(scene.defaultEye.cameraView[eye]?.pack(), view.pack());
  });
}
