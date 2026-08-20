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
///     fieldOfView.defaultValue = 90;
///     near.defaultValue = 10;
///   }
/// }
/// ```
///
/// That used to be a `Camera3DDescriptor` handed to a `describeCamera` hook,
/// which existed only to carry three numbers into `hasFloat64`. `goo2d`'s
/// `Camera` never had one and now does not need one either.
mixin Camera3D on Component {
  /// Vertical field of view, in **degrees**. Degrees rather than radians
  /// because this is a number a person types into a prefab, and 60 is a
  /// choice while 1.0471975511965976 is a transcription.
  final fieldOfView = Field.float64(60);

  /// The near and far clip distances, in world units, measured along the
  /// camera's forward axis.
  ///
  /// Both are positive distances in front of the camera. A near plane very
  /// close to zero is not free - the depth buffer's precision is spent
  /// mostly between `near` and a small multiple of it, so a `near` of 0.001
  /// buys detail nobody can see at the cost of z-fighting everywhere else.
  final near = Field.float64(0.1);
  final far = Field.float64(1000);

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
  /// The one field here that still needs [describeStruct]: the view table it
  /// is declared against comes from `getScene`, an instance method a field
  /// initialiser cannot reach.
  ///
  /// More than one camera on one view has no meaning, because a view has one
  /// origin, and it is the renderer that will have to say so. That renderer
  /// is not written yet; `goo2d`'s `ActiveCameraResolver` is the shape the
  /// check takes there.
  late final DataPointer<CameraView?> view;

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
    view = data.optPacked(getScene<SceneStruct>().cameraViews);
  }
}
