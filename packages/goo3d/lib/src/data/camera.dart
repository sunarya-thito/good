import 'package:good/good.dart';
import 'package:meta/meta.dart';

/// Declares a prefab's camera. The named parameters double as that
/// archetype's row defaults, the same shape `ColliderDescriptor` and
/// `RigidBody2DDescriptor` use - so the common case needs no write at mount
/// time at all, and a game that *does* want to change the field of view at
/// run time still writes the column.
class Camera3DDescriptor {
  Camera3DDescriptor._();

  double _fieldOfView = 60;
  double _near = 0.1;
  double _far = 1000;

  /// [fieldOfView] is in degrees, vertical. [near] and [far] bound what is
  /// drawn: anything closer than [near] or further than [far] is skipped.
  void has({double fieldOfView = 60, double near = 0.1, double far = 1000}) {
    _fieldOfView = fieldOfView;
    _near = near;
    _far = far;
  }
}

/// Marks an entity as a camera - where a view is looked at the world from,
/// and how much of it is in shot.
///
/// A camera is an entity, not a global. Position and orientation are whatever
/// its own `WorldTransform3D` resolves to (an entity with `Camera3D` must
/// also mix in `Transform3D`/`WorldTransform3D`), so a follow camera is a
/// camera parented to something - there is no separate camera-controller
/// concept.
///
/// It looks down its own **-Z**, because -Z is forward; see `Transform3D`.
///
/// ```dart
/// class Eye extends EntityStruct with Transform3D, WorldTransform3D, Camera3D {
///   @override
///   void describeCamera(Camera3DDescriptor descriptor) {
///     super.describeCamera(descriptor);
///     descriptor.has(fieldOfView: 60, near: 0.1, far: 1000);
///   }
/// }
/// ```
mixin Camera3D on Component {
  /// Vertical field of view, in **degrees**. Degrees rather than radians
  /// because this is a number a person types into a prefab, and 60 is a
  /// choice while 1.0471975511965976 is a transcription.
  late final DataPointer<double> fieldOfView;

  /// The near and far clip distances, in world units, measured along the
  /// camera's forward axis.
  ///
  /// Both are positive distances in front of the camera. A near plane very
  /// close to zero is not free - the depth buffer's precision is spent
  /// mostly between `near` and a small multiple of it, so a `near` of 0.001
  /// buys detail nobody can see at the cost of z-fighting everywhere else.
  late final DataPointer<double> near;
  late final DataPointer<double> far;

  /// Which declared view this camera fills, or null for a camera that is not
  /// currently shown anywhere.
  ///
  /// Set it from the game isolate with the handle the game declared:
  ///
  /// ```dart
  /// eye.camera.view[entity] = game.mainCamera;
  /// ```
  ///
  /// Typed rather than an int, which is the payoff of `CameraView` being a
  /// `GlobalObject`: a stray integer does not compile here.
  ///
  /// More than one camera on one view has no meaning, because a view has one
  /// origin, and it is the renderer that will have to say so. That renderer
  /// is not written yet; `goo2d`'s `ActiveCameraResolver` is the shape the
  /// check takes there.
  late final DataPointer<CameraView?> view;

  /// Implemented by the concrete prefab - declares this entity type's camera
  /// through the [Camera3DDescriptor] passed in.
  @mustCallSuper
  void describeCamera(Camera3DDescriptor descriptor) {}

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Camera3D>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    final descriptor = Camera3DDescriptor._();
    describeCamera(descriptor);
    fieldOfView = data.hasFloat64(descriptor._fieldOfView);
    near = data.hasFloat64(descriptor._near);
    far = data.hasFloat64(descriptor._far);
    // The declaring game's own view table - not a shared registry. An address
    // read out of this field means nothing except against this table.
    view = data.optPacked(getScene<SceneStruct>().cameraViews);
  }
}
