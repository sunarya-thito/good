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
part of 'main.dart';

List<ScannableField> _collect$Breath(Object object) {
  object as Breath;
  return const <ScannableField>[];
}

List<ScannableField> _collect$Player(Object object) {
  final owner = object as Player;
  return <ScannableField>[
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

List<ScannableField> _collect$Enemy(Object object) {
  final owner = object as Enemy;
  return <ScannableField>[
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

List<ScannableField> _collect$Wingman(Object object) {
  final owner = object as Wingman;
  return <ScannableField>[
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

List<ScannableField> _collect$MainScene(Object object) {
  final owner = object as MainScene;
  return <ScannableField>[
    owner.playerPrefab,
    owner.enemyPrefab,
    owner.wingmanPrefab,
    owner.eyePrefab,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$SpinSystem(Object object) {
  final owner = object as SpinSystem;
  return <ScannableField>[
    owner.spinnable,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$SpawnEnemy(Object object) {
  final owner = object as SpawnEnemy;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$MyGameState(Object object) {
  final owner = object as MyGameState;
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

List<ScannableField> _collect$MyAwesomeGame(Object object) {
  object as MyAwesomeGame;
  return const <ScannableField>[];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _mainDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/example/lib/main.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(Breath, _collect$Breath),
        DeclarationCollector(Player, _collect$Player),
        DeclarationCollector(Enemy, _collect$Enemy),
        DeclarationCollector(Wingman, _collect$Wingman),
        DeclarationCollector(Eye, _collect$Eye),
        DeclarationCollector(MainScene, _collect$MainScene),
        DeclarationCollector(SpinSystem, _collect$SpinSystem),
        DeclarationCollector(SpawnEnemy, _collect$SpawnEnemy),
        DeclarationCollector(MyGameState, _collect$MyGameState),
        DeclarationCollector(MyAwesomeGame, _collect$MyAwesomeGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );

/// Installs [_mainDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_mainDeclarations],
);
