import 'package:good/good.dart';

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
/// A prefab that wants different clip planes or a different field of view
/// overrides the column defaults in its own `describeStruct`:
///
/// ```dart
/// class Eye extends EntityStruct with Transform3D, WorldTransform3D, Camera3D {
///   @override
///   void describeStruct(DataDescriptor data) {
///     super.describeStruct(data);
///     cameraFieldOfView.defaultValue = 90;
///     cameraNear.defaultValue = 10;
///   }
/// }
/// ```
mixin Camera3D on Component {
  /// Vertical field of view, in **degrees**, not radians: this is a number
  /// you type into a prefab, and 60 is a choice while 1.0471975511965976 is a
  /// transcription.
  final cameraFieldOfView = Field.float64(60);

  /// The near clip distance, in world units, measured along the camera's
  /// forward axis. A positive distance in front of the camera.
  ///
  /// Very close to zero is not free - the depth buffer's precision is spent
  /// mostly between `cameraNear` and a small multiple of it, so a
  /// `cameraNear` of 0.001 buys detail nobody can see at the cost of
  /// z-fighting everywhere else.
  final cameraNear = Field.float64(0.1);

  /// The far clip distance, in world units, measured along the camera's
  /// forward axis. Nothing past it is drawn.
  final cameraFar = Field.float64(1000);

  /// Which declared view this camera fills, or null for a camera that is not
  /// currently shown anywhere.
  ///
  /// Set it from the game isolate with the handle the game declared:
  ///
  /// ```dart
  /// eye.camera.cameraView[entity] = game.mainCamera;
  /// ```
  ///
  /// Typed, not an int: `CameraView` is a `GlobalObject`, so a stray integer
  /// does not compile here.
  ///
  /// The one field here that needs [describeStruct]: the view table it is
  /// declared against comes from `getScene`, an instance method a field
  /// initialiser cannot reach.
  ///
  /// More than one camera on one view has no meaning - a view has one origin
  /// - and nothing here checks for it. `goo2d` makes that check in
  /// `ActiveCameraResolver`.
  late final DataPointer<CameraView?> cameraView;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Camera3D>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    // The declaring game's own view table - not a shared registry. An address
    // read out of this field means nothing except against this table.
    cameraView = data.optPacked(getScene<SceneStruct>().cameraViews);
  }
}
