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
part of 'physics.dart';

List<ScannableField> _collect$Crate(Object object) {
  final owner = object as Crate;
  return <ScannableField>[
    owner.flash,
    owner.bodyHandle,
    owner.bodyType,
    owner.bodyLinearVelocityX,
    owner.bodyLinearVelocityY,
    owner.bodyAngularVelocity,
    owner.bodyGravityScale,
    owner.bodyLinearDamping,
    owner.bodyAngularDamping,
    owner.bodyFixedRotation,
    owner.bodyIsBullet,
    owner.bodySyncedX,
    owner.bodySyncedY,
    owner.bodySyncedAngle,
    owner.bodySyncedType,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Ball(Object object) {
  final owner = object as Ball;
  return <ScannableField>[
    owner.flash,
    owner.bodyHandle,
    owner.bodyType,
    owner.bodyLinearVelocityX,
    owner.bodyLinearVelocityY,
    owner.bodyAngularVelocity,
    owner.bodyGravityScale,
    owner.bodyLinearDamping,
    owner.bodyAngularDamping,
    owner.bodyFixedRotation,
    owner.bodyIsBullet,
    owner.bodySyncedX,
    owner.bodySyncedY,
    owner.bodySyncedAngle,
    owner.bodySyncedType,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Ground(Object object) {
  final owner = object as Ground;
  return <ScannableField>[
    owner.bodyHandle,
    owner.bodyType,
    owner.bodyLinearVelocityX,
    owner.bodyLinearVelocityY,
    owner.bodyAngularVelocity,
    owner.bodyGravityScale,
    owner.bodyLinearDamping,
    owner.bodyAngularDamping,
    owner.bodyFixedRotation,
    owner.bodyIsBullet,
    owner.bodySyncedX,
    owner.bodySyncedY,
    owner.bodySyncedAngle,
    owner.bodySyncedType,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Wall(Object object) {
  final owner = object as Wall;
  return <ScannableField>[
    owner.bodyHandle,
    owner.bodyType,
    owner.bodyLinearVelocityX,
    owner.bodyLinearVelocityY,
    owner.bodyAngularVelocity,
    owner.bodyGravityScale,
    owner.bodyLinearDamping,
    owner.bodyAngularDamping,
    owner.bodyFixedRotation,
    owner.bodyIsBullet,
    owner.bodySyncedX,
    owner.bodySyncedY,
    owner.bodySyncedAngle,
    owner.bodySyncedType,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Eye(Object object) {
  final owner = object as Eye;
  return <ScannableField>[
    owner.cameraZoom,
    owner.cameraView,
    owner.worldX,
    owner.worldY,
    owner.worldScaleX,
    owner.worldScaleY,
    owner.worldRotation,
    owner.worldCachedOffsetX,
    owner.worldCachedOffsetY,
    owner.worldCachedRotation,
    owner.worldCachedScaleX,
    owner.worldCachedScaleY,
    owner.worldCachedParent,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Sandbox(Object object) {
  final owner = object as Sandbox;
  return <ScannableField>[
    owner.crate,
    owner.ball,
    owner.ground,
    owner.wall,
    owner.eye,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$PhysicsPhaseStart(Object object) {
  final owner = object as _PhysicsPhaseStart;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$PhysicsPhaseEnd(Object object) {
  final owner = object as _PhysicsPhaseEnd;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$SandboxSystem(Object object) {
  final owner = object as SandboxSystem;
  return <ScannableField>[
    owner.bodies,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _physicsDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/example/lib/demo/physics.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(Crate, _collect$Crate),
        DeclarationCollector(Ball, _collect$Ball),
        DeclarationCollector(Ground, _collect$Ground),
        DeclarationCollector(Wall, _collect$Wall),
        DeclarationCollector(Eye, _collect$Eye),
        DeclarationCollector(Sandbox, _collect$Sandbox),
        DeclarationCollector(_PhysicsPhaseStart, _collect$PhysicsPhaseStart),
        DeclarationCollector(_PhysicsPhaseEnd, _collect$PhysicsPhaseEnd),
        DeclarationCollector(SandboxSystem, _collect$SandboxSystem),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );

/// Installs [_physicsDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_physicsDeclarations],
);
