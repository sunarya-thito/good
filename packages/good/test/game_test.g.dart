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
part of 'game_test.dart';

List<ScannableField> _collect$Unit(Object object) {
  final owner = object as _Unit;
  return <ScannableField>[
    owner.x,
    owner.marker,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$TestScene(Object object) {
  final owner = object as _TestScene;
  return <ScannableField>[
    owner.unit,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$PresentSystem(Object object) {
  final owner = object as _PresentSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$BothPhases(Object object) {
  final owner = object as _BothPhases;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$PhaseState(Object object) {
  final owner = object as _PhaseState;
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

List<ScannableField> _collect$PhaseGame(Object object) {
  object as _PhaseGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ThrowingSystem(Object object) {
  final owner = object as _ThrowingSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$AfterThrowerSystem(Object object) {
  final owner = object as _AfterThrowerSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$ThrowState(Object object) {
  final owner = object as _ThrowState;
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

List<ScannableField> _collect$ThrowGame(Object object) {
  object as _ThrowGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ReportingThrowGame(Object object) {
  object as _ReportingThrowGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$BadReportGame(Object object) {
  object as _BadReportGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$VisibilitySystem(Object object) {
  final owner = object as _VisibilitySystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$VisibilityState(Object object) {
  final owner = object as _VisibilityState;
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

List<ScannableField> _collect$VisibilityGame(Object object) {
  object as _VisibilityGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$AlwaysTickingGame(Object object) {
  object as _AlwaysTickingGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$SystemA(Object object) {
  final owner = object as _SystemA;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$SystemB(Object object) {
  final owner = object as _SystemB;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$InertSystem(Object object) {
  final owner = object as _InertSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$SortsFirst(Object object) {
  final owner = object as _SortsFirst;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$Indifferent1(Object object) {
  final owner = object as _Indifferent1;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$Indifferent2(Object object) {
  final owner = object as _Indifferent2;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$AlsoSortsFirst(Object object) {
  final owner = object as _AlsoSortsFirst;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$Composer(Object object) {
  final owner = object as _Composer;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$Spawner(Object object) {
  final owner = object as _Spawner;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$OrderingState(Object object) {
  final owner = object as _OrderingState;
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

List<ScannableField> _collect$CycleA(Object object) {
  final owner = object as _CycleA;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$CycleB(Object object) {
  final owner = object as _CycleB;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$CycleC(Object object) {
  final owner = object as _CycleC;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$CyclicState(Object object) {
  final owner = object as _CyclicState;
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

List<ScannableField> _collect$CyclicGame(Object object) {
  object as _CyclicGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$OrderingGame(Object object) {
  object as _OrderingGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$CensusSystem(Object object) {
  final owner = object as _CensusSystem;
  return <ScannableField>[
    owner.query,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$SpawnUnit(Object object) {
  final owner = object as _SpawnUnit;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$FixtureState(Object object) {
  final owner = object as _FixtureState;
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

List<ScannableField> _collect$TestState(Object object) {
  final owner = object as _TestState;
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

List<ScannableField> _collect$TestGame(Object object) {
  object as _TestGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$WriteOutsideTick(Object object) {
  object as _WriteOutsideTick;
  return const <ScannableField>[];
}

List<ScannableField> _collect$BadControlState(Object object) {
  final owner = object as _BadControlState;
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

List<ScannableField> _collect$BadControlGame(Object object) {
  object as _BadControlGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$Answering(Object object) {
  final owner = object as _Answering;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$AnsweringState(Object object) {
  final owner = object as _AnsweringState;
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

List<ScannableField> _collect$AnsweringGame(Object object) {
  object as _AnsweringGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$AnsweringMainGame(Object object) {
  object as _AnsweringMainGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$Inspect(Object object) {
  final owner = object as _Inspect;
  return <ScannableField>[
    owner.atTick,
    owner.wasStopped,
  ];
}

List<ScannableField> _collect$Arrival(Object object) {
  final owner = object as _Arrival;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$TickBound(Object object) {
  object as _TickBound;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ReadOnlyState(Object object) {
  final owner = object as _ReadOnlyState;
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

List<ScannableField> _collect$ReadOnlyGame(Object object) {
  object as _ReadOnlyGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$Mute(Object object) {
  object as _Mute;
  return const <ScannableField>[];
}

List<ScannableField> _collect$MuteReadOnlyState(Object object) {
  final owner = object as _MuteReadOnlyState;
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

List<ScannableField> _collect$MuteReadOnlyGame(Object object) {
  object as _MuteReadOnlyGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ControlWrite(Object object) {
  object as _ControlWrite;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ControlSpawn(Object object) {
  object as _ControlSpawn;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ControlDestroy(Object object) {
  object as _ControlDestroy;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ControlUnload(Object object) {
  object as _ControlUnload;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ControlChannelWrite(Object object) {
  object as _ControlChannelWrite;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ControlStateWrite(Object object) {
  object as _ControlStateWrite;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ReadOnlyComponentWrite(Object object) {
  final owner = object as _ReadOnlyComponentWrite;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$ReadOnlySpawn(Object object) {
  final owner = object as _ReadOnlySpawn;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$ReadOnlyUnload(Object object) {
  final owner = object as _ReadOnlyUnload;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$ReadOnlyChannelWrite(Object object) {
  final owner = object as _ReadOnlyChannelWrite;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$ReadOnlyRead(Object object) {
  final owner = object as _ReadOnlyRead;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$MarkerSystem(Object object) {
  final owner = object as _MarkerSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$WindowState(Object object) {
  final owner = object as _WindowState;
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

List<ScannableField> _collect$WindowGame(Object object) {
  final owner = object as _WindowGame;
  return <ScannableField>[
    owner.score,
  ];
}

List<ScannableField> _collect$MuteSink(Object object) {
  final owner = object as _MuteSink;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$MuteReadOnlyMainGame(Object object) {
  object as _MuteReadOnlyMainGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$DrawsFromA(Object object) {
  final owner = object as _DrawsFromA;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$DrawsFromB(Object object) {
  final owner = object as _DrawsFromB;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$RandomState(Object object) {
  final owner = object as _RandomState;
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

List<ScannableField> _collect$RandomGame(Object object) {
  object as _RandomGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$NudgeCommand(Object object) {
  final owner = object as _NudgeCommand;
  return <ScannableField>[
    owner.entity,
    owner.amount,
  ];
}

List<ScannableField> _collect$CommandGame(Object object) {
  object as _CommandGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$CommandState(Object object) {
  final owner = object as _CommandState;
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

List<ScannableField> _collect$BadCommandState(Object object) {
  final owner = object as _BadCommandState;
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

List<ScannableField> _collect$BadCommandGame(Object object) {
  object as _BadCommandGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$DuplicateSystemState(Object object) {
  final owner = object as _DuplicateSystemState;
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

List<ScannableField> _collect$DuplicateSystemGame(Object object) {
  object as _DuplicateSystemGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$UndeclaredSystem(Object object) {
  final owner = object as _UndeclaredSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$ScenelessState(Object object) {
  final owner = object as _ScenelessState;
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

List<ScannableField> _collect$ScenelessGame(Object object) {
  object as _ScenelessGame;
  return const <ScannableField>[];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _gameTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/game_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Unit, _collect$Unit),
        DeclarationCollector(_TestScene, _collect$TestScene),
        DeclarationCollector(_PresentSystem, _collect$PresentSystem),
        DeclarationCollector(_BothPhases, _collect$BothPhases),
        DeclarationCollector(_PhaseState, _collect$PhaseState),
        DeclarationCollector(_PhaseGame, _collect$PhaseGame),
        DeclarationCollector(_ThrowingSystem, _collect$ThrowingSystem),
        DeclarationCollector(_AfterThrowerSystem, _collect$AfterThrowerSystem),
        DeclarationCollector(_ThrowState, _collect$ThrowState),
        DeclarationCollector(_ThrowGame, _collect$ThrowGame),
        DeclarationCollector(_ReportingThrowGame, _collect$ReportingThrowGame),
        DeclarationCollector(_BadReportGame, _collect$BadReportGame),
        DeclarationCollector(_VisibilitySystem, _collect$VisibilitySystem),
        DeclarationCollector(_VisibilityState, _collect$VisibilityState),
        DeclarationCollector(_VisibilityGame, _collect$VisibilityGame),
        DeclarationCollector(_AlwaysTickingGame, _collect$AlwaysTickingGame),
        DeclarationCollector(_SystemA, _collect$SystemA),
        DeclarationCollector(_SystemB, _collect$SystemB),
        DeclarationCollector(_InertSystem, _collect$InertSystem),
        DeclarationCollector(_SortsFirst, _collect$SortsFirst),
        DeclarationCollector(_Indifferent1, _collect$Indifferent1),
        DeclarationCollector(_Indifferent2, _collect$Indifferent2),
        DeclarationCollector(_AlsoSortsFirst, _collect$AlsoSortsFirst),
        DeclarationCollector(_Composer, _collect$Composer),
        DeclarationCollector(_Spawner, _collect$Spawner),
        DeclarationCollector(_OrderingState, _collect$OrderingState),
        DeclarationCollector(_CycleA, _collect$CycleA),
        DeclarationCollector(_CycleB, _collect$CycleB),
        DeclarationCollector(_CycleC, _collect$CycleC),
        DeclarationCollector(_CyclicState, _collect$CyclicState),
        DeclarationCollector(_CyclicGame, _collect$CyclicGame),
        DeclarationCollector(_OrderingGame, _collect$OrderingGame),
        DeclarationCollector(_CensusSystem, _collect$CensusSystem),
        DeclarationCollector(_SpawnUnit, _collect$SpawnUnit),
        DeclarationCollector(_FixtureState, _collect$FixtureState),
        DeclarationCollector(_TestState, _collect$TestState),
        DeclarationCollector(_TestGame, _collect$TestGame),
        DeclarationCollector(_WriteOutsideTick, _collect$WriteOutsideTick),
        DeclarationCollector(_BadControlState, _collect$BadControlState),
        DeclarationCollector(_BadControlGame, _collect$BadControlGame),
        DeclarationCollector(_Answering, _collect$Answering),
        DeclarationCollector(_AnsweringState, _collect$AnsweringState),
        DeclarationCollector(_AnsweringGame, _collect$AnsweringGame),
        DeclarationCollector(_AnsweringMainGame, _collect$AnsweringMainGame),
        DeclarationCollector(_Inspect, _collect$Inspect),
        DeclarationCollector(_Arrival, _collect$Arrival),
        DeclarationCollector(_TickBound, _collect$TickBound),
        DeclarationCollector(_ReadOnlyState, _collect$ReadOnlyState),
        DeclarationCollector(_ReadOnlyGame, _collect$ReadOnlyGame),
        DeclarationCollector(_Mute, _collect$Mute),
        DeclarationCollector(_MuteReadOnlyState, _collect$MuteReadOnlyState),
        DeclarationCollector(_MuteReadOnlyGame, _collect$MuteReadOnlyGame),
        DeclarationCollector(_ControlWrite, _collect$ControlWrite),
        DeclarationCollector(_ControlSpawn, _collect$ControlSpawn),
        DeclarationCollector(_ControlDestroy, _collect$ControlDestroy),
        DeclarationCollector(_ControlUnload, _collect$ControlUnload),
        DeclarationCollector(_ControlChannelWrite, _collect$ControlChannelWrite),
        DeclarationCollector(_ControlStateWrite, _collect$ControlStateWrite),
        DeclarationCollector(_ReadOnlyComponentWrite, _collect$ReadOnlyComponentWrite),
        DeclarationCollector(_ReadOnlySpawn, _collect$ReadOnlySpawn),
        DeclarationCollector(_ReadOnlyUnload, _collect$ReadOnlyUnload),
        DeclarationCollector(_ReadOnlyChannelWrite, _collect$ReadOnlyChannelWrite),
        DeclarationCollector(_ReadOnlyRead, _collect$ReadOnlyRead),
        DeclarationCollector(_MarkerSystem, _collect$MarkerSystem),
        DeclarationCollector(_WindowState, _collect$WindowState),
        DeclarationCollector(_WindowGame, _collect$WindowGame),
        DeclarationCollector(_MuteSink, _collect$MuteSink),
        DeclarationCollector(_MuteReadOnlyMainGame, _collect$MuteReadOnlyMainGame),
        DeclarationCollector(_DrawsFromA, _collect$DrawsFromA),
        DeclarationCollector(_DrawsFromB, _collect$DrawsFromB),
        DeclarationCollector(_RandomState, _collect$RandomState),
        DeclarationCollector(_RandomGame, _collect$RandomGame),
        DeclarationCollector(_NudgeCommand, _collect$NudgeCommand),
        DeclarationCollector(_CommandGame, _collect$CommandGame),
        DeclarationCollector(_CommandState, _collect$CommandState),
        DeclarationCollector(_BadCommandState, _collect$BadCommandState),
        DeclarationCollector(_BadCommandGame, _collect$BadCommandGame),
        DeclarationCollector(_DuplicateSystemState, _collect$DuplicateSystemState),
        DeclarationCollector(_DuplicateSystemGame, _collect$DuplicateSystemGame),
        DeclarationCollector(_UndeclaredSystem, _collect$UndeclaredSystem),
        DeclarationCollector(_ScenelessState, _collect$ScenelessState),
        DeclarationCollector(_ScenelessGame, _collect$ScenelessGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_gameTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_gameTestDeclarations],
);
