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
//
// Beside each list is every type an instance of that fixture
// is, the fixture itself first, then the names in its
// extends, with and implements clauses in that order, each
// followed by its own supertypes. Nothing reads that order
// positionally; it is fixed so two machines write one file.
//
// A type the generator did not read is not listed. A type it
// read and this part cannot name keeps its place as a
// comment - a part writes no imports of its own, so what it
// may name is what its library already does.
part of 'game_test.dart';

List<ScannableField> _collect$Unit(Object object) {
  final owner = object as _Unit;
  return <ScannableField>[
    owner.x,
    owner.marker,
  ];
}

const List<Type> _supertypes$Unit = <Type>[
  _Unit,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Counter,
];

List<ScannableField> _collect$TestScene(Object object) {
  final owner = object as _TestScene;
  return <ScannableField>[
    owner.unit,
  ];
}

const List<Type> _supertypes$TestScene = <Type>[
  _TestScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$PresentSystem(Object object) {
  object as _PresentSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$PresentSystem = <Type>[
  _PresentSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  Tickable,
];

List<ScannableField> _collect$BothPhases(Object object) {
  object as _BothPhases;
  return const <ScannableField>[];
}

const List<Type> _supertypes$BothPhases = <Type>[
  _BothPhases,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
  Tickable,
];

List<ScannableField> _collect$PhaseState(Object object) {
  final owner = object as _PhaseState;
  return <ScannableField>[
    owner.presentSystem,
    owner.bothPhases,
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

const List<Type> _supertypes$PhaseState = <Type>[
  _PhaseState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$PhaseGame(Object object) {
  object as _PhaseGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$PhaseGame = <Type>[
  _PhaseGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$ThrowingSystem(Object object) {
  object as _ThrowingSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ThrowingSystem = <Type>[
  _ThrowingSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$AfterThrowerSystem(Object object) {
  object as _AfterThrowerSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$AfterThrowerSystem = <Type>[
  _AfterThrowerSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$ThrowState(Object object) {
  final owner = object as _ThrowState;
  return <ScannableField>[
    owner.thrower,
    owner.afterThrower,
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

const List<Type> _supertypes$ThrowState = <Type>[
  _ThrowState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$ThrowGame(Object object) {
  object as _ThrowGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ThrowGame = <Type>[
  _ThrowGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$ReportingThrowGame(Object object) {
  object as _ReportingThrowGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ReportingThrowGame = <Type>[
  _ReportingThrowGame,
  _ThrowGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$BadReportGame(Object object) {
  object as _BadReportGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$BadReportGame = <Type>[
  _BadReportGame,
  _ThrowGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$VisibilitySystem(Object object) {
  object as _VisibilitySystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$VisibilitySystem = <Type>[
  _VisibilitySystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  AppVisibilityListener,
];

List<ScannableField> _collect$VisibilityState(Object object) {
  final owner = object as _VisibilityState;
  return <ScannableField>[
    owner.visibility,
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

const List<Type> _supertypes$VisibilityState = <Type>[
  _VisibilityState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$VisibilityGame(Object object) {
  object as _VisibilityGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$VisibilityGame = <Type>[
  _VisibilityGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$AlwaysTickingGame(Object object) {
  object as _AlwaysTickingGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$AlwaysTickingGame = <Type>[
  _AlwaysTickingGame,
  _VisibilityGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$SystemA(Object object) {
  object as _SystemA;
  return const <ScannableField>[];
}

const List<Type> _supertypes$SystemA = <Type>[
  _SystemA,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$SystemB(Object object) {
  object as _SystemB;
  return const <ScannableField>[];
}

const List<Type> _supertypes$SystemB = <Type>[
  _SystemB,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$InertSystem(Object object) {
  object as _InertSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$InertSystem = <Type>[
  _InertSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$SortsFirst(Object object) {
  object as _SortsFirst;
  return const <ScannableField>[];
}

const List<Type> _supertypes$SortsFirst = <Type>[
  _SortsFirst,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$Indifferent1(Object object) {
  object as _Indifferent1;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Indifferent1 = <Type>[
  _Indifferent1,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$Indifferent2(Object object) {
  object as _Indifferent2;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Indifferent2 = <Type>[
  _Indifferent2,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$AlsoSortsFirst(Object object) {
  object as _AlsoSortsFirst;
  return const <ScannableField>[];
}

const List<Type> _supertypes$AlsoSortsFirst = <Type>[
  _AlsoSortsFirst,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$Composer(Object object) {
  object as _Composer;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Composer = <Type>[
  _Composer,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$Spawner(Object object) {
  object as _Spawner;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Spawner = <Type>[
  _Spawner,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$OrderingState(Object object) {
  final owner = object as _OrderingState;
  return <ScannableField>[
    owner.indifferent1,
    owner.indifferent2,
    owner.sortsFirst,
    owner.alsoSortsFirst,
    owner.composer,
    owner.spawner,
    owner.systemA,
    owner.inertSystem,
    owner.systemB,
    owner.censusSystem,
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

const List<Type> _supertypes$OrderingState = <Type>[
  _OrderingState,
  _TestState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$CycleA(Object object) {
  object as _CycleA;
  return const <ScannableField>[];
}

const List<Type> _supertypes$CycleA = <Type>[
  _CycleA,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$CycleB(Object object) {
  object as _CycleB;
  return const <ScannableField>[];
}

const List<Type> _supertypes$CycleB = <Type>[
  _CycleB,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$CycleC(Object object) {
  object as _CycleC;
  return const <ScannableField>[];
}

const List<Type> _supertypes$CycleC = <Type>[
  _CycleC,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$CyclicState(Object object) {
  final owner = object as _CyclicState;
  return <ScannableField>[
    owner.cycleA,
    owner.cycleB,
    owner.cycleC,
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

const List<Type> _supertypes$CyclicState = <Type>[
  _CyclicState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$CyclicGame(Object object) {
  object as _CyclicGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$CyclicGame = <Type>[
  _CyclicGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$OrderingGame(Object object) {
  object as _OrderingGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$OrderingGame = <Type>[
  _OrderingGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$CensusSystem(Object object) {
  final owner = object as _CensusSystem;
  return <ScannableField>[
    owner.query,
  ];
}

const List<Type> _supertypes$CensusSystem = <Type>[
  _CensusSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$SpawnUnit(Object object) {
  final owner = object as _SpawnUnit;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$SpawnUnit = <Type>[
  _SpawnUnit,
  ValueSupplier,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

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

const List<Type> _supertypes$FixtureState = <Type>[
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$TestState(Object object) {
  final owner = object as _TestState;
  return <ScannableField>[
    owner.systemA,
    owner.inertSystem,
    owner.systemB,
    owner.censusSystem,
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

const List<Type> _supertypes$TestState = <Type>[
  _TestState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$TestGame(Object object) {
  object as _TestGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$TestGame = <Type>[
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$WriteOutsideTick(Object object) {
  object as _WriteOutsideTick;
  return const <ScannableField>[];
}

const List<Type> _supertypes$WriteOutsideTick = <Type>[
  _WriteOutsideTick,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

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

const List<Type> _supertypes$BadControlState = <Type>[
  _BadControlState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$BadControlGame(Object object) {
  object as _BadControlGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$BadControlGame = <Type>[
  _BadControlGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$Answering(Object object) {
  final owner = object as _Answering;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$Answering = <Type>[
  _Answering,
  ValueSupplier,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

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

const List<Type> _supertypes$AnsweringState = <Type>[
  _AnsweringState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$AnsweringGame(Object object) {
  object as _AnsweringGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$AnsweringGame = <Type>[
  _AnsweringGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$AnsweringMainGame(Object object) {
  object as _AnsweringMainGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$AnsweringMainGame = <Type>[
  _AnsweringMainGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$Inspect(Object object) {
  final owner = object as _Inspect;
  return <ScannableField>[
    owner.atTick,
    owner.wasStopped,
  ];
}

const List<Type> _supertypes$Inspect = <Type>[
  _Inspect,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$Arrival(Object object) {
  final owner = object as _Arrival;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$Arrival = <Type>[
  _Arrival,
  ValueSupplier,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$TickBound(Object object) {
  object as _TickBound;
  return const <ScannableField>[];
}

const List<Type> _supertypes$TickBound = <Type>[
  _TickBound,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

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

const List<Type> _supertypes$ReadOnlyState = <Type>[
  _ReadOnlyState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$ReadOnlyGame(Object object) {
  object as _ReadOnlyGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ReadOnlyGame = <Type>[
  _ReadOnlyGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$Mute(Object object) {
  object as _Mute;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Mute = <Type>[
  _Mute,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

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

const List<Type> _supertypes$MuteReadOnlyState = <Type>[
  _MuteReadOnlyState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$MuteReadOnlyGame(Object object) {
  object as _MuteReadOnlyGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$MuteReadOnlyGame = <Type>[
  _MuteReadOnlyGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$ControlWrite(Object object) {
  object as _ControlWrite;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ControlWrite = <Type>[
  _ControlWrite,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ControlSpawn(Object object) {
  object as _ControlSpawn;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ControlSpawn = <Type>[
  _ControlSpawn,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ControlDestroy(Object object) {
  object as _ControlDestroy;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ControlDestroy = <Type>[
  _ControlDestroy,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ControlUnload(Object object) {
  object as _ControlUnload;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ControlUnload = <Type>[
  _ControlUnload,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ControlChannelWrite(Object object) {
  object as _ControlChannelWrite;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ControlChannelWrite = <Type>[
  _ControlChannelWrite,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ControlStateWrite(Object object) {
  object as _ControlStateWrite;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ControlStateWrite = <Type>[
  _ControlStateWrite,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ReadOnlyComponentWrite(Object object) {
  final owner = object as _ReadOnlyComponentWrite;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$ReadOnlyComponentWrite = <Type>[
  _ReadOnlyComponentWrite,
  _IntAnswer,
  ValueSupplier,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ReadOnlySpawn(Object object) {
  final owner = object as _ReadOnlySpawn;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$ReadOnlySpawn = <Type>[
  _ReadOnlySpawn,
  _IntAnswer,
  ValueSupplier,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ReadOnlyUnload(Object object) {
  final owner = object as _ReadOnlyUnload;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$ReadOnlyUnload = <Type>[
  _ReadOnlyUnload,
  _IntAnswer,
  ValueSupplier,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ReadOnlyChannelWrite(Object object) {
  final owner = object as _ReadOnlyChannelWrite;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$ReadOnlyChannelWrite = <Type>[
  _ReadOnlyChannelWrite,
  _IntAnswer,
  ValueSupplier,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ReadOnlyRead(Object object) {
  final owner = object as _ReadOnlyRead;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$ReadOnlyRead = <Type>[
  _ReadOnlyRead,
  _IntAnswer,
  ValueSupplier,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$MarkerSystem(Object object) {
  object as _MarkerSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$MarkerSystem = <Type>[
  _MarkerSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$WindowState(Object object) {
  final owner = object as _WindowState;
  return <ScannableField>[
    owner.marker,
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

const List<Type> _supertypes$WindowState = <Type>[
  _WindowState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$WindowGame(Object object) {
  final owner = object as _WindowGame;
  return <ScannableField>[
    owner.score,
  ];
}

const List<Type> _supertypes$WindowGame = <Type>[
  _WindowGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$MuteSink(Object object) {
  final owner = object as _MuteSink;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$MuteSink = <Type>[
  _MuteSink,
  ValueSink,
  SinkCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$MuteReadOnlyMainGame(Object object) {
  object as _MuteReadOnlyMainGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$MuteReadOnlyMainGame = <Type>[
  _MuteReadOnlyMainGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$DrawsFromA(Object object) {
  object as _DrawsFromA;
  return const <ScannableField>[];
}

const List<Type> _supertypes$DrawsFromA = <Type>[
  _DrawsFromA,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$DrawsFromB(Object object) {
  object as _DrawsFromB;
  return const <ScannableField>[];
}

const List<Type> _supertypes$DrawsFromB = <Type>[
  _DrawsFromB,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$RandomState(Object object) {
  final owner = object as _RandomState;
  return <ScannableField>[
    owner.drawsA,
    owner.drawsB,
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

const List<Type> _supertypes$RandomState = <Type>[
  _RandomState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$RandomGame(Object object) {
  object as _RandomGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$RandomGame = <Type>[
  _RandomGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$NudgeCommand(Object object) {
  final owner = object as _NudgeCommand;
  return <ScannableField>[
    owner.entity,
    owner.amount,
  ];
}

const List<Type> _supertypes$NudgeCommand = <Type>[
  _NudgeCommand,
  SinkCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$CommandGame(Object object) {
  object as _CommandGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$CommandGame = <Type>[
  _CommandGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

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

const List<Type> _supertypes$CommandState = <Type>[
  _CommandState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$BadCommandState(Object object) {
  final owner = object as _BadCommandState;
  return <ScannableField>[
    owner.systemA,
    owner.inertSystem,
    owner.systemB,
    owner.censusSystem,
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

const List<Type> _supertypes$BadCommandState = <Type>[
  _BadCommandState,
  _TestState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$BadCommandGame(Object object) {
  object as _BadCommandGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$BadCommandGame = <Type>[
  _BadCommandGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$DuplicateSystemState(Object object) {
  final owner = object as _DuplicateSystemState;
  return <ScannableField>[
    owner.systemA2,
    owner.systemA,
    owner.inertSystem,
    owner.systemB,
    owner.censusSystem,
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

const List<Type> _supertypes$DuplicateSystemState = <Type>[
  _DuplicateSystemState,
  _TestState,
  _FixtureState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$DuplicateSystemGame(Object object) {
  object as _DuplicateSystemGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$DuplicateSystemGame = <Type>[
  _DuplicateSystemGame,
  _TestGame,
  Game,
  RandomOwner,
  Scannable,
];

List<ScannableField> _collect$UndeclaredSystem(Object object) {
  object as _UndeclaredSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$UndeclaredSystem = <Type>[
  _UndeclaredSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$ScenelessState(Object object) {
  final owner = object as _ScenelessState;
  return <ScannableField>[
    owner.systemA3,
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

const List<Type> _supertypes$ScenelessState = <Type>[
  _ScenelessState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$ScenelessGame(Object object) {
  object as _ScenelessGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ScenelessGame = <Type>[
  _ScenelessGame,
  Game,
  RandomOwner,
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _gameTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/game_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Unit, _collect$Unit, _supertypes$Unit),
        DeclarationCollector(
          _TestScene,
          _collect$TestScene,
          _supertypes$TestScene,
        ),
        DeclarationCollector(
          _PresentSystem,
          _collect$PresentSystem,
          _supertypes$PresentSystem,
        ),
        DeclarationCollector(
          _BothPhases,
          _collect$BothPhases,
          _supertypes$BothPhases,
        ),
        DeclarationCollector(
          _PhaseState,
          _collect$PhaseState,
          _supertypes$PhaseState,
        ),
        DeclarationCollector(
          _PhaseGame,
          _collect$PhaseGame,
          _supertypes$PhaseGame,
        ),
        DeclarationCollector(
          _ThrowingSystem,
          _collect$ThrowingSystem,
          _supertypes$ThrowingSystem,
        ),
        DeclarationCollector(
          _AfterThrowerSystem,
          _collect$AfterThrowerSystem,
          _supertypes$AfterThrowerSystem,
        ),
        DeclarationCollector(
          _ThrowState,
          _collect$ThrowState,
          _supertypes$ThrowState,
        ),
        DeclarationCollector(
          _ThrowGame,
          _collect$ThrowGame,
          _supertypes$ThrowGame,
        ),
        DeclarationCollector(
          _ReportingThrowGame,
          _collect$ReportingThrowGame,
          _supertypes$ReportingThrowGame,
        ),
        DeclarationCollector(
          _BadReportGame,
          _collect$BadReportGame,
          _supertypes$BadReportGame,
        ),
        DeclarationCollector(
          _VisibilitySystem,
          _collect$VisibilitySystem,
          _supertypes$VisibilitySystem,
        ),
        DeclarationCollector(
          _VisibilityState,
          _collect$VisibilityState,
          _supertypes$VisibilityState,
        ),
        DeclarationCollector(
          _VisibilityGame,
          _collect$VisibilityGame,
          _supertypes$VisibilityGame,
        ),
        DeclarationCollector(
          _AlwaysTickingGame,
          _collect$AlwaysTickingGame,
          _supertypes$AlwaysTickingGame,
        ),
        DeclarationCollector(_SystemA, _collect$SystemA, _supertypes$SystemA),
        DeclarationCollector(_SystemB, _collect$SystemB, _supertypes$SystemB),
        DeclarationCollector(
          _InertSystem,
          _collect$InertSystem,
          _supertypes$InertSystem,
        ),
        DeclarationCollector(
          _SortsFirst,
          _collect$SortsFirst,
          _supertypes$SortsFirst,
        ),
        DeclarationCollector(
          _Indifferent1,
          _collect$Indifferent1,
          _supertypes$Indifferent1,
        ),
        DeclarationCollector(
          _Indifferent2,
          _collect$Indifferent2,
          _supertypes$Indifferent2,
        ),
        DeclarationCollector(
          _AlsoSortsFirst,
          _collect$AlsoSortsFirst,
          _supertypes$AlsoSortsFirst,
        ),
        DeclarationCollector(
          _Composer,
          _collect$Composer,
          _supertypes$Composer,
        ),
        DeclarationCollector(_Spawner, _collect$Spawner, _supertypes$Spawner),
        DeclarationCollector(
          _OrderingState,
          _collect$OrderingState,
          _supertypes$OrderingState,
        ),
        DeclarationCollector(_CycleA, _collect$CycleA, _supertypes$CycleA),
        DeclarationCollector(_CycleB, _collect$CycleB, _supertypes$CycleB),
        DeclarationCollector(_CycleC, _collect$CycleC, _supertypes$CycleC),
        DeclarationCollector(
          _CyclicState,
          _collect$CyclicState,
          _supertypes$CyclicState,
        ),
        DeclarationCollector(
          _CyclicGame,
          _collect$CyclicGame,
          _supertypes$CyclicGame,
        ),
        DeclarationCollector(
          _OrderingGame,
          _collect$OrderingGame,
          _supertypes$OrderingGame,
        ),
        DeclarationCollector(
          _CensusSystem,
          _collect$CensusSystem,
          _supertypes$CensusSystem,
        ),
        DeclarationCollector(
          _SpawnUnit,
          _collect$SpawnUnit,
          _supertypes$SpawnUnit,
        ),
        DeclarationCollector(
          _FixtureState,
          _collect$FixtureState,
          _supertypes$FixtureState,
        ),
        DeclarationCollector(
          _TestState,
          _collect$TestState,
          _supertypes$TestState,
        ),
        DeclarationCollector(
          _TestGame,
          _collect$TestGame,
          _supertypes$TestGame,
        ),
        DeclarationCollector(
          _WriteOutsideTick,
          _collect$WriteOutsideTick,
          _supertypes$WriteOutsideTick,
        ),
        DeclarationCollector(
          _BadControlState,
          _collect$BadControlState,
          _supertypes$BadControlState,
        ),
        DeclarationCollector(
          _BadControlGame,
          _collect$BadControlGame,
          _supertypes$BadControlGame,
        ),
        DeclarationCollector(
          _Answering,
          _collect$Answering,
          _supertypes$Answering,
        ),
        DeclarationCollector(
          _AnsweringState,
          _collect$AnsweringState,
          _supertypes$AnsweringState,
        ),
        DeclarationCollector(
          _AnsweringGame,
          _collect$AnsweringGame,
          _supertypes$AnsweringGame,
        ),
        DeclarationCollector(
          _AnsweringMainGame,
          _collect$AnsweringMainGame,
          _supertypes$AnsweringMainGame,
        ),
        DeclarationCollector(_Inspect, _collect$Inspect, _supertypes$Inspect),
        DeclarationCollector(_Arrival, _collect$Arrival, _supertypes$Arrival),
        DeclarationCollector(
          _TickBound,
          _collect$TickBound,
          _supertypes$TickBound,
        ),
        DeclarationCollector(
          _ReadOnlyState,
          _collect$ReadOnlyState,
          _supertypes$ReadOnlyState,
        ),
        DeclarationCollector(
          _ReadOnlyGame,
          _collect$ReadOnlyGame,
          _supertypes$ReadOnlyGame,
        ),
        DeclarationCollector(_Mute, _collect$Mute, _supertypes$Mute),
        DeclarationCollector(
          _MuteReadOnlyState,
          _collect$MuteReadOnlyState,
          _supertypes$MuteReadOnlyState,
        ),
        DeclarationCollector(
          _MuteReadOnlyGame,
          _collect$MuteReadOnlyGame,
          _supertypes$MuteReadOnlyGame,
        ),
        DeclarationCollector(
          _ControlWrite,
          _collect$ControlWrite,
          _supertypes$ControlWrite,
        ),
        DeclarationCollector(
          _ControlSpawn,
          _collect$ControlSpawn,
          _supertypes$ControlSpawn,
        ),
        DeclarationCollector(
          _ControlDestroy,
          _collect$ControlDestroy,
          _supertypes$ControlDestroy,
        ),
        DeclarationCollector(
          _ControlUnload,
          _collect$ControlUnload,
          _supertypes$ControlUnload,
        ),
        DeclarationCollector(
          _ControlChannelWrite,
          _collect$ControlChannelWrite,
          _supertypes$ControlChannelWrite,
        ),
        DeclarationCollector(
          _ControlStateWrite,
          _collect$ControlStateWrite,
          _supertypes$ControlStateWrite,
        ),
        DeclarationCollector(
          _ReadOnlyComponentWrite,
          _collect$ReadOnlyComponentWrite,
          _supertypes$ReadOnlyComponentWrite,
        ),
        DeclarationCollector(
          _ReadOnlySpawn,
          _collect$ReadOnlySpawn,
          _supertypes$ReadOnlySpawn,
        ),
        DeclarationCollector(
          _ReadOnlyUnload,
          _collect$ReadOnlyUnload,
          _supertypes$ReadOnlyUnload,
        ),
        DeclarationCollector(
          _ReadOnlyChannelWrite,
          _collect$ReadOnlyChannelWrite,
          _supertypes$ReadOnlyChannelWrite,
        ),
        DeclarationCollector(
          _ReadOnlyRead,
          _collect$ReadOnlyRead,
          _supertypes$ReadOnlyRead,
        ),
        DeclarationCollector(
          _MarkerSystem,
          _collect$MarkerSystem,
          _supertypes$MarkerSystem,
        ),
        DeclarationCollector(
          _WindowState,
          _collect$WindowState,
          _supertypes$WindowState,
        ),
        DeclarationCollector(
          _WindowGame,
          _collect$WindowGame,
          _supertypes$WindowGame,
        ),
        DeclarationCollector(
          _MuteSink,
          _collect$MuteSink,
          _supertypes$MuteSink,
        ),
        DeclarationCollector(
          _MuteReadOnlyMainGame,
          _collect$MuteReadOnlyMainGame,
          _supertypes$MuteReadOnlyMainGame,
        ),
        DeclarationCollector(
          _DrawsFromA,
          _collect$DrawsFromA,
          _supertypes$DrawsFromA,
        ),
        DeclarationCollector(
          _DrawsFromB,
          _collect$DrawsFromB,
          _supertypes$DrawsFromB,
        ),
        DeclarationCollector(
          _RandomState,
          _collect$RandomState,
          _supertypes$RandomState,
        ),
        DeclarationCollector(
          _RandomGame,
          _collect$RandomGame,
          _supertypes$RandomGame,
        ),
        DeclarationCollector(
          _NudgeCommand,
          _collect$NudgeCommand,
          _supertypes$NudgeCommand,
        ),
        DeclarationCollector(
          _CommandGame,
          _collect$CommandGame,
          _supertypes$CommandGame,
        ),
        DeclarationCollector(
          _CommandState,
          _collect$CommandState,
          _supertypes$CommandState,
        ),
        DeclarationCollector(
          _BadCommandState,
          _collect$BadCommandState,
          _supertypes$BadCommandState,
        ),
        DeclarationCollector(
          _BadCommandGame,
          _collect$BadCommandGame,
          _supertypes$BadCommandGame,
        ),
        DeclarationCollector(
          _DuplicateSystemState,
          _collect$DuplicateSystemState,
          _supertypes$DuplicateSystemState,
        ),
        DeclarationCollector(
          _DuplicateSystemGame,
          _collect$DuplicateSystemGame,
          _supertypes$DuplicateSystemGame,
        ),
        DeclarationCollector(
          _UndeclaredSystem,
          _collect$UndeclaredSystem,
          _supertypes$UndeclaredSystem,
        ),
        DeclarationCollector(
          _ScenelessState,
          _collect$ScenelessState,
          _supertypes$ScenelessState,
        ),
        DeclarationCollector(
          _ScenelessGame,
          _collect$ScenelessGame,
          _supertypes$ScenelessGame,
        ),
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
