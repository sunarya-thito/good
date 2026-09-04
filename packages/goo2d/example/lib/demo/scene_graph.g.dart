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
part of 'scene_graph.dart';

List<ScannableField> _collect$Critter(Object object) {
  final owner = object as Critter;
  return <ScannableField>[
    owner.texture,
    owner.angle,
    owner.radius,
    owner.spin,
    owner.life,
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
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

List<ScannableField> _collect$Limb(Object object) {
  final owner = object as Limb;
  return <ScannableField>[
    owner.texture,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
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

List<ScannableField> _collect$Hub(Object object) {
  final owner = object as Hub;
  return <ScannableField>[
    owner.parentFirstChild,
    owner.parentLastChild,
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

List<ScannableField> _collect$Swarm(Object object) {
  final owner = object as Swarm;
  return <ScannableField>[
    owner.critter,
    owner.limb,
    owner.hub,
    owner.eye,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$CritterSystem(Object object) {
  final owner = object as CritterSystem;
  return <ScannableField>[
    owner.critters,
    owner.hubs,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$SceneGraphState(Object object) {
  final owner = object as SceneGraphState;
  return <ScannableField>[
    owner.fixedTickEvent,
    owner.tickEvent,
    owner.gameMountedEvent,
    owner.gameUnmountedEvent,
    owner.appHiddenEvent,
    owner.appShownEvent,
    owner.entitySpawnedEvent,
    owner.entityDespawnedEvent,
    owner.sceneLoadedEvent,
    owner.sceneUnloadedEvent,
  ];
}

List<ScannableField> _collect$SceneGraphGame(Object object) {
  final owner = object as SceneGraphGame;
  return <ScannableField>[
    owner.caseMicros,
    owner.systemMicros,
    owner.bestSystemMicros,
    owner.stepMicros,
    owner.presentMicros,
    owner.advanceMicros,
    owner.intervalMicros,
    owner.renderMicros,
    owner.stepsPerAdvance,
    owner.spawnedCount,
    owner.spritesDrawn,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _sceneGraphDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/example/lib/demo/scene_graph.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(Critter, _collect$Critter),
        DeclarationCollector(Limb, _collect$Limb),
        DeclarationCollector(Hub, _collect$Hub),
        DeclarationCollector(Eye, _collect$Eye),
        DeclarationCollector(Swarm, _collect$Swarm),
        DeclarationCollector(CritterSystem, _collect$CritterSystem),
        DeclarationCollector(SceneGraphState, _collect$SceneGraphState),
        DeclarationCollector(SceneGraphGame, _collect$SceneGraphGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );

/// Installs [_sceneGraphDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_sceneGraphDeclarations],
);
