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
part of 'game_state_test.dart';

List<ScannableField> _collect$Probe(Object object) {
  final owner = object as _Probe;
  return <ScannableField>[
    owner.hits,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$StateScene(Object object) {
  final owner = object as _StateScene;
  return <ScannableField>[
    owner.probe,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$StateSystem(Object object) {
  final owner = object as _StateSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$StateGameState(Object object) {
  final owner = object as _StateGameState;
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

List<ScannableField> _collect$StateGame(Object object) {
  final owner = object as _StateGame;
  return <ScannableField>[
    owner.gameCount,
    owner.stateCount,
    owner.health,
    owner.probeCount,
    owner.mana,
    owner.alive,
  ];
}

List<ScannableField> _collect$GameSceneStub(Object object) {
  final owner = object as GameSceneStub;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$OrphanScene(Object object) {
  final owner = object as _OrphanScene;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$WidthState(Object object) {
  final owner = object as _WidthState;
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

List<ScannableField> _collect$WidthGame(Object object) {
  final owner = object as _WidthGame;
  return <ScannableField>[
    owner.u8,
    owner.i8,
    owner.u16,
    owner.i16,
    owner.u32,
    owner.i32,
    owner.u64,
    owner.i64,
    owner.f32,
    owner.f64,
    owner.flag,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _gameStateTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/game_state_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Probe, _collect$Probe),
        DeclarationCollector(_StateScene, _collect$StateScene),
        DeclarationCollector(_StateSystem, _collect$StateSystem),
        DeclarationCollector(_StateGameState, _collect$StateGameState),
        DeclarationCollector(_StateGame, _collect$StateGame),
        DeclarationCollector(GameSceneStub, _collect$GameSceneStub),
        DeclarationCollector(_OrphanScene, _collect$OrphanScene),
        DeclarationCollector(_WidthState, _collect$WidthState),
        DeclarationCollector(_WidthGame, _collect$WidthGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_gameStateTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_gameStateTestDeclarations],
);
