// GENERATED - do not edit.
//
// Regenerate with `dart run good_tool --tests` from
// packages/good_tool, and commit what changes.
// `dart run good_tool --tests --check` is what CI runs; it
// fails if this file is not what the generator would write.
//
// One function per fixture this library declares. It is a
// part of that library because a fixture is private, and a
// private class can only be named from inside the library
// that declares it.
//
// The order inside each list is the order the fields would
// have been initialised in, which is the field order of every
// row of that archetype.
//
// A commented-out line is a declaration a mixin from a
// package's lib/ holds privately. That is another library,
// so nothing here can read it - it keeps its place so that
// what the row is missing, and where, is visible.
part of 'camera_3d_test.dart';

List<ScannableField> _collect$DefaultEye(Object object) {
  final owner = object as _DefaultEye;
  return <ScannableField>[
    owner.cameraFieldOfView,
    owner.cameraNear,
    owner.cameraFar,
    owner.cameraView,
    owner.worldX,
    owner.worldY,
    owner.worldZ,
    owner.worldScaleX,
    owner.worldScaleY,
    owner.worldScaleZ,
    owner.worldRotationX,
    owner.worldRotationY,
    owner.worldRotationZ,
    owner.worldRotationW,
    owner.worldCachedOffsetX,
    owner.worldCachedOffsetY,
    owner.worldCachedOffsetZ,
    owner.worldCachedRotationX,
    owner.worldCachedRotationY,
    owner.worldCachedRotationZ,
    owner.worldCachedRotationW,
    owner.worldCachedScaleX,
    owner.worldCachedScaleY,
    owner.worldCachedScaleZ,
    owner.worldCachedParent,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformOffsetZ,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformScaleZ,
    owner.transformRotationX,
    owner.transformRotationY,
    owner.transformRotationZ,
    owner.transformRotationW,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$WideEye(Object object) {
  final owner = object as _WideEye;
  return <ScannableField>[
    owner.cameraFieldOfView,
    owner.cameraNear,
    owner.cameraFar,
    owner.cameraView,
    owner.worldX,
    owner.worldY,
    owner.worldZ,
    owner.worldScaleX,
    owner.worldScaleY,
    owner.worldScaleZ,
    owner.worldRotationX,
    owner.worldRotationY,
    owner.worldRotationZ,
    owner.worldRotationW,
    owner.worldCachedOffsetX,
    owner.worldCachedOffsetY,
    owner.worldCachedOffsetZ,
    owner.worldCachedRotationX,
    owner.worldCachedRotationY,
    owner.worldCachedRotationZ,
    owner.worldCachedRotationW,
    owner.worldCachedScaleX,
    owner.worldCachedScaleY,
    owner.worldCachedScaleZ,
    owner.worldCachedParent,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformOffsetZ,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformScaleZ,
    owner.transformRotationX,
    owner.transformRotationY,
    owner.transformRotationZ,
    owner.transformRotationW,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Scene(Object object) {
  final owner = object as _Scene;
  return <ScannableField>[
    owner.defaultEye,
    owner.wideEye,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _camera3dTestDeclarations =
    GeneratedDeclarations(
      package: 'goo3d/test/camera_3d_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_DefaultEye, _collect$DefaultEye),
        DeclarationCollector(_WideEye, _collect$WideEye),
        DeclarationCollector(_Scene, _collect$Scene),
      ],
      dependencies: <GeneratedDeclarations>[
        goo3dDeclarations,
      ],
    );

/// Installs [_camera3dTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_camera3dTestDeclarations],
);
