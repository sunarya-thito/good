import 'package:flutter_test/flutter_test.dart';
import 'package:goo3d/goo3d.dart';

/// A camera that declares nothing, to pin what a prefab gets for free.
class _DefaultEye extends EntityStruct
    with Transform3D, WorldTransform3D, Camera3D {}

/// A camera that declares all three, the way the guide writes one.
class _WideEye extends EntityStruct
    with Transform3D, WorldTransform3D, Camera3D {
  @override
  void describeCamera(Camera3DDescriptor descriptor) {
    super.describeCamera(descriptor);
    descriptor.has(fieldOfView: 90, near: 0.5, far: 250);
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

    expect(scene.defaultEye.fieldOfView[eye], 60);
    expect(scene.defaultEye.near[eye], 0.1);
    expect(scene.defaultEye.far[eye], 1000);
    expect(scene.defaultEye.view[eye], isNull);
  });

  test('describeCamera lands in the row defaults, with nothing written at '
      'mount time', () {
    final scene = _scene();
    scene.pool.beginTick();
    final eye = scene.addEntity(scene.wideEye);
    scene.pool.commitTick();

    expect(scene.wideEye.fieldOfView[eye], 90);
    expect(scene.wideEye.near[eye], 0.5);
    expect(scene.wideEye.far[eye], 250);
  });

  test('the declared values are defaults, not constants', () {
    final scene = _scene();
    scene.pool.beginTick();
    final eye = scene.addEntity(scene.wideEye);
    scene.pool.commitTick();

    // A zoom-in is a field-of-view change at run time, so the declaration
    // cannot be the last word on it.
    scene.pool.beginTick();
    scene.wideEye.fieldOfView[eye] = 30;
    scene.pool.commitTick();
    expect(scene.wideEye.fieldOfView[eye], 30);
  });

  test('two entities of one camera prefab carry their own field of view', () {
    final scene = _scene();
    scene.pool.beginTick();
    final a = scene.addEntity(scene.wideEye);
    final b = scene.addEntity(scene.wideEye);
    scene.pool.commitTick();

    scene.pool.beginTick();
    scene.wideEye.fieldOfView[a] = 20;
    scene.pool.commitTick();

    expect(scene.wideEye.fieldOfView[a], 20);
    expect(scene.wideEye.fieldOfView[b], 90, reason: 'per row, not per prefab');
  });

  test('a camera takes the view it was pointed at', () {
    final scene = _scene();
    scene.pool.beginTick();
    final eye = scene.addEntity(scene.defaultEye);
    scene.pool.commitTick();

    final view = views.declareDetached();
    scene.pool.beginTick();
    scene.defaultEye.view[eye] = view;
    scene.pool.commitTick();

    expect(scene.defaultEye.view[eye]?.pack(), view.pack());
  });
}
