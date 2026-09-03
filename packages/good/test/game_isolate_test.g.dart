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
part of 'game_isolate_test.dart';

List<ScannableField> _collect$Mover(Object object) {
  final owner = object as _Mover;
  return <ScannableField>[
    owner.x,
    owner.census,
    owner.marker,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$MoverScene(Object object) {
  final owner = object as _MoverScene;
  return <ScannableField>[
    owner.mover,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$MoverSystem(Object object) {
  final owner = object as _MoverSystem;
  return <ScannableField>[
    owner.query,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$SpawnMover(Object object) {
  final owner = object as _SpawnMover;
  return <ScannableField>[
    owner.spawned,
  ];
}

List<ScannableField> _collect$ResumeByControl(Object object) {
  object as _ResumeByControl;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ResumeByTick(Object object) {
  object as _ResumeByTick;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ControlProbe(Object object) {
  object as _ControlProbe;
  return const <ScannableField>[];
}

List<ScannableField> _collect$PauseMover(Object object) {
  final owner = object as _PauseMover;
  return <ScannableField>[
    owner.paused,
  ];
}

List<ScannableField> _collect$IsolateState(Object object) {
  final owner = object as _IsolateState;
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

List<ScannableField> _collect$DyingSystem(Object object) {
  final owner = object as _DyingSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$DyingState(Object object) {
  final owner = object as _DyingState;
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

List<ScannableField> _collect$DyingGame(Object object) {
  object as _DyingGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$RandomReporter(Object object) {
  final owner = object as _RandomReporter;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$RandomIsolateState(Object object) {
  final owner = object as _RandomIsolateState;
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

List<ScannableField> _collect$RandomIsolateGame(Object object) {
  final owner = object as _RandomIsolateGame;
  return <ScannableField>[
    owner.drawn,
  ];
}

List<ScannableField> _collect$IsolateGame(Object object) {
  final owner = object as _IsolateGame;
  return <ScannableField>[
    owner.firstX,
    owner.population,
    owner.firstMarker,
    owner.probeRefused,
  ];
}

List<ScannableField> _collect$PingSystem(Object object) {
  final owner = object as _PingSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$PingState(Object object) {
  final owner = object as _PingState;
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

List<ScannableField> _collect$PingGame(Object object) {
  object as _PingGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$CounterSystem(Object object) {
  final owner = object as _CounterSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$ChannelState(Object object) {
  final owner = object as _ChannelState;
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

List<ScannableField> _collect$ChannelGame(Object object) {
  final owner = object as _ChannelGame;
  return <ScannableField>[
    owner.ticks,
    owner.alive,
  ];
}

List<ScannableField> _collect$InputProbeSystem(Object object) {
  final owner = object as _InputProbeSystem;
  return <ScannableField>[
    owner.fire,
    owner.move,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$InputProbeState(Object object) {
  final owner = object as _InputProbeState;
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

List<ScannableField> _collect$InputProbeGame(Object object) {
  final owner = object as _InputProbeGame;
  return <ScannableField>[
    owner.fireHeld,
    owner.presses,
    owner.releases,
    owner.moveX,
  ];
}

List<ScannableField> _collect$Textured(Object object) {
  final owner = object as _Textured;
  return <ScannableField>[
    owner.texture,
    owner.seenAddress,
    owner.seenLoaded,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$TexturedScene(Object object) {
  final owner = object as _TexturedScene;
  return <ScannableField>[
    owner.textured,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$TexturedSystem(Object object) {
  final owner = object as _TexturedSystem;
  return <ScannableField>[
    owner.query,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$TexturedState(Object object) {
  final owner = object as _TexturedState;
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

List<ScannableField> _collect$TexturedGame(Object object) {
  final owner = object as _TexturedGame;
  return <ScannableField>[
    owner.reportedAddress,
    owner.reportedLoaded,
  ];
}

List<ScannableField> _collect$LateProp(Object object) {
  final owner = object as _LateProp;
  return <ScannableField>[
    owner.texture,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$LateScene(Object object) {
  final owner = object as _LateScene;
  return <ScannableField>[
    owner.prop,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$LoadLate(Object object) {
  object as _LoadLate;
  return const <ScannableField>[];
}

List<ScannableField> _collect$UnloadLate(Object object) {
  object as _UnloadLate;
  return const <ScannableField>[];
}

List<ScannableField> _collect$LateState(Object object) {
  final owner = object as _LateState;
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

List<ScannableField> _collect$LateGame(Object object) {
  final owner = object as _LateGame;
  return <ScannableField>[
    owner.progress,
    owner.lateAddress,
  ];
}

List<ScannableField> _collect$DropScene(Object object) {
  object as _DropScene;
  return const <ScannableField>[];
}

List<ScannableField> _collect$UnloadState(Object object) {
  final owner = object as _UnloadState;
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

List<ScannableField> _collect$UnloadGame(Object object) {
  object as _UnloadGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$AskMain(Object object) {
  final owner = object as _AskMain;
  return <ScannableField>[
    owner.answer,
  ];
}

List<ScannableField> _collect$AskGame(Object object) {
  object as _AskGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$StartAsking(Object object) {
  object as _StartAsking;
  return const <ScannableField>[];
}

List<ScannableField> _collect$AskingSystem(Object object) {
  final owner = object as _AskingSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$AskingState(Object object) {
  final owner = object as _AskingState;
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

List<ScannableField> _collect$AskingGame(Object object) {
  final owner = object as _AskingGame;
  return <ScannableField>[
    owner.asked,
    owner.mainAnswered,
    owner.gameAnswered,
    owner.mainAnswer,
    owner.askedTick,
    owner.answeredTick,
    owner.answeredStopped,
  ];
}

List<ScannableField> _collect$ReadPaused(Object object) {
  final owner = object as _ReadPaused;
  return <ScannableField>[
    owner.atTick,
    owner.wasStopped,
  ];
}

List<ScannableField> _collect$ReadOrder(Object object) {
  final owner = object as _ReadOrder;
  return <ScannableField>[
    owner.ordinal,
  ];
}

List<ScannableField> _collect$NeedsTick(Object object) {
  object as _NeedsTick;
  return const <ScannableField>[];
}

List<ScannableField> _collect$PausedAskState(Object object) {
  final owner = object as _PausedAskState;
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

List<ScannableField> _collect$PausedAskGame(Object object) {
  final owner = object as _PausedAskGame;
  return <ScannableField>[
    owner.tickRan,
  ];
}

List<ScannableField> _collect$Pebble(Object object) {
  final owner = object as _Pebble;
  return <ScannableField>[
    owner.weight,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$CensusScene(Object object) {
  final owner = object as _CensusScene;
  return <ScannableField>[
    owner.pebble,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$IdleSystem(Object object) {
  final owner = object as _IdleSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$SleepySystem(Object object) {
  final owner = object as _SleepySystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$TakeWorldCensus(Object object) {
  final owner = object as _TakeWorldCensus;
  return <ScannableField>[
    owner.blob,
  ];
}

List<ScannableField> _collect$SleepASystem(Object object) {
  object as _SleepASystem;
  return const <ScannableField>[];
}

List<ScannableField> _collect$CensusIsolateState(Object object) {
  final owner = object as _CensusIsolateState;
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

List<ScannableField> _collect$CensusIsolateGame(Object object) {
  object as _CensusIsolateGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$RegistrarSystem(Object object) {
  final owner = object as _RegistrarSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$RegistrarState(Object object) {
  final owner = object as _RegistrarState;
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

List<ScannableField> _collect$RegistrarGame(Object object) {
  final owner = object as _RegistrarGame;
  return <ScannableField>[
    owner.registeredHere,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _gameIsolateTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/game_isolate_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Mover, _collect$Mover),
        DeclarationCollector(_MoverScene, _collect$MoverScene),
        DeclarationCollector(_MoverSystem, _collect$MoverSystem),
        DeclarationCollector(_SpawnMover, _collect$SpawnMover),
        DeclarationCollector(_ResumeByControl, _collect$ResumeByControl),
        DeclarationCollector(_ResumeByTick, _collect$ResumeByTick),
        DeclarationCollector(_ControlProbe, _collect$ControlProbe),
        DeclarationCollector(_PauseMover, _collect$PauseMover),
        DeclarationCollector(_IsolateState, _collect$IsolateState),
        DeclarationCollector(_DyingSystem, _collect$DyingSystem),
        DeclarationCollector(_DyingState, _collect$DyingState),
        DeclarationCollector(_DyingGame, _collect$DyingGame),
        DeclarationCollector(_RandomReporter, _collect$RandomReporter),
        DeclarationCollector(_RandomIsolateState, _collect$RandomIsolateState),
        DeclarationCollector(_RandomIsolateGame, _collect$RandomIsolateGame),
        DeclarationCollector(_IsolateGame, _collect$IsolateGame),
        DeclarationCollector(_PingSystem, _collect$PingSystem),
        DeclarationCollector(_PingState, _collect$PingState),
        DeclarationCollector(_PingGame, _collect$PingGame),
        DeclarationCollector(_CounterSystem, _collect$CounterSystem),
        DeclarationCollector(_ChannelState, _collect$ChannelState),
        DeclarationCollector(_ChannelGame, _collect$ChannelGame),
        DeclarationCollector(_InputProbeSystem, _collect$InputProbeSystem),
        DeclarationCollector(_InputProbeState, _collect$InputProbeState),
        DeclarationCollector(_InputProbeGame, _collect$InputProbeGame),
        DeclarationCollector(_Textured, _collect$Textured),
        DeclarationCollector(_TexturedScene, _collect$TexturedScene),
        DeclarationCollector(_TexturedSystem, _collect$TexturedSystem),
        DeclarationCollector(_TexturedState, _collect$TexturedState),
        DeclarationCollector(_TexturedGame, _collect$TexturedGame),
        DeclarationCollector(_LateProp, _collect$LateProp),
        DeclarationCollector(_LateScene, _collect$LateScene),
        DeclarationCollector(_LoadLate, _collect$LoadLate),
        DeclarationCollector(_UnloadLate, _collect$UnloadLate),
        DeclarationCollector(_LateState, _collect$LateState),
        DeclarationCollector(_LateGame, _collect$LateGame),
        DeclarationCollector(_DropScene, _collect$DropScene),
        DeclarationCollector(_UnloadState, _collect$UnloadState),
        DeclarationCollector(_UnloadGame, _collect$UnloadGame),
        DeclarationCollector(_AskMain, _collect$AskMain),
        DeclarationCollector(_AskGame, _collect$AskGame),
        DeclarationCollector(_StartAsking, _collect$StartAsking),
        DeclarationCollector(_AskingSystem, _collect$AskingSystem),
        DeclarationCollector(_AskingState, _collect$AskingState),
        DeclarationCollector(_AskingGame, _collect$AskingGame),
        DeclarationCollector(_ReadPaused, _collect$ReadPaused),
        DeclarationCollector(_ReadOrder, _collect$ReadOrder),
        DeclarationCollector(_NeedsTick, _collect$NeedsTick),
        DeclarationCollector(_PausedAskState, _collect$PausedAskState),
        DeclarationCollector(_PausedAskGame, _collect$PausedAskGame),
        DeclarationCollector(_Pebble, _collect$Pebble),
        DeclarationCollector(_CensusScene, _collect$CensusScene),
        DeclarationCollector(_IdleSystem, _collect$IdleSystem),
        DeclarationCollector(_SleepySystem, _collect$SleepySystem),
        DeclarationCollector(_TakeWorldCensus, _collect$TakeWorldCensus),
        DeclarationCollector(_SleepASystem, _collect$SleepASystem),
        DeclarationCollector(_CensusIsolateState, _collect$CensusIsolateState),
        DeclarationCollector(_CensusIsolateGame, _collect$CensusIsolateGame),
        DeclarationCollector(_RegistrarSystem, _collect$RegistrarSystem),
        DeclarationCollector(_RegistrarState, _collect$RegistrarState),
        DeclarationCollector(_RegistrarGame, _collect$RegistrarGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_gameIsolateTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_gameIsolateTestDeclarations],
);
