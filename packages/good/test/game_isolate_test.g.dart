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
part of 'game_isolate_test.dart';

List<ScannableField> _collect$Mover(Object object) {
  final owner = object as _Mover;
  return <ScannableField>[
    owner.x,
    owner.census,
    owner.marker,
  ];
}

const List<Type> _supertypes$Mover = <Type>[
  _Mover,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Moving,
];

List<ScannableField> _collect$MoverScene(Object object) {
  final owner = object as _MoverScene;
  return <ScannableField>[
    owner.mover,
  ];
}

const List<Type> _supertypes$MoverScene = <Type>[
  _MoverScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$MoverSystem(Object object) {
  final owner = object as _MoverSystem;
  return <ScannableField>[
    owner.query,
  ];
}

const List<Type> _supertypes$MoverSystem = <Type>[
  _MoverSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$SpawnMover(Object object) {
  final owner = object as _SpawnMover;
  return <ScannableField>[
    owner.spawned,
  ];
}

const List<Type> _supertypes$SpawnMover = <Type>[
  _SpawnMover,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ResumeByControl(Object object) {
  object as _ResumeByControl;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ResumeByControl = <Type>[
  _ResumeByControl,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ResumeByTick(Object object) {
  object as _ResumeByTick;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ResumeByTick = <Type>[
  _ResumeByTick,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ControlProbe(Object object) {
  object as _ControlProbe;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ControlProbe = <Type>[
  _ControlProbe,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$PauseMover(Object object) {
  final owner = object as _PauseMover;
  return <ScannableField>[
    owner.paused,
  ];
}

const List<Type> _supertypes$PauseMover = <Type>[
  _PauseMover,
  SinkCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$IsolateState(Object object) {
  final owner = object as _IsolateState;
  return <ScannableField>[
    owner.moverSystem,
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

const List<Type> _supertypes$IsolateState = <Type>[
  _IsolateState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$DyingSystem(Object object) {
  object as _DyingSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$DyingSystem = <Type>[
  _DyingSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$DyingState(Object object) {
  final owner = object as _DyingState;
  return <ScannableField>[
    owner.dyingSystem,
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

const List<Type> _supertypes$DyingState = <Type>[
  _DyingState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$DyingGame(Object object) {
  object as _DyingGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$DyingGame = <Type>[
  _DyingGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

List<ScannableField> _collect$RandomReporter(Object object) {
  object as _RandomReporter;
  return const <ScannableField>[];
}

const List<Type> _supertypes$RandomReporter = <Type>[
  _RandomReporter,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$RandomIsolateState(Object object) {
  final owner = object as _RandomIsolateState;
  return <ScannableField>[
    owner.randomReporter,
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

const List<Type> _supertypes$RandomIsolateState = <Type>[
  _RandomIsolateState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$RandomIsolateGame(Object object) {
  final owner = object as _RandomIsolateGame;
  return <ScannableField>[
    owner.drawn,
  ];
}

const List<Type> _supertypes$RandomIsolateGame = <Type>[
  _RandomIsolateGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

List<ScannableField> _collect$IsolateGame(Object object) {
  final owner = object as _IsolateGame;
  return <ScannableField>[
    owner.firstX,
    owner.population,
    owner.firstMarker,
    owner.probeRefused,
  ];
}

const List<Type> _supertypes$IsolateGame = <Type>[
  _IsolateGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

List<ScannableField> _collect$PingSystem(Object object) {
  object as _PingSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$PingSystem = <Type>[
  _PingSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$PingState(Object object) {
  final owner = object as _PingState;
  return <ScannableField>[
    owner.pingSystem,
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

const List<Type> _supertypes$PingState = <Type>[
  _PingState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$PingGame(Object object) {
  object as _PingGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$PingGame = <Type>[
  _PingGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

List<ScannableField> _collect$CounterSystem(Object object) {
  object as _CounterSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$CounterSystem = <Type>[
  _CounterSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$ChannelState(Object object) {
  final owner = object as _ChannelState;
  return <ScannableField>[
    owner.counterSystem,
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

const List<Type> _supertypes$ChannelState = <Type>[
  _ChannelState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$ChannelGame(Object object) {
  final owner = object as _ChannelGame;
  return <ScannableField>[
    owner.ticks,
    owner.alive,
  ];
}

const List<Type> _supertypes$ChannelGame = <Type>[
  _ChannelGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

List<ScannableField> _collect$InputProbeSystem(Object object) {
  final owner = object as _InputProbeSystem;
  return <ScannableField>[
    owner.fire,
    owner.move,
  ];
}

const List<Type> _supertypes$InputProbeSystem = <Type>[
  _InputProbeSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$InputProbeState(Object object) {
  final owner = object as _InputProbeState;
  return <ScannableField>[
    owner.inputProbeSystem,
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

const List<Type> _supertypes$InputProbeState = <Type>[
  _InputProbeState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$InputProbeGame(Object object) {
  final owner = object as _InputProbeGame;
  return <ScannableField>[
    owner.fireHeld,
    owner.presses,
    owner.releases,
    owner.moveX,
  ];
}

const List<Type> _supertypes$InputProbeGame = <Type>[
  _InputProbeGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

List<ScannableField> _collect$Textured(Object object) {
  final owner = object as _Textured;
  return <ScannableField>[
    owner.texture,
    owner.seenAddress,
    owner.seenLoaded,
  ];
}

const List<Type> _supertypes$Textured = <Type>[
  _Textured,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$TexturedScene(Object object) {
  final owner = object as _TexturedScene;
  return <ScannableField>[
    owner.textured,
  ];
}

const List<Type> _supertypes$TexturedScene = <Type>[
  _TexturedScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$TexturedSystem(Object object) {
  final owner = object as _TexturedSystem;
  return <ScannableField>[
    owner.query,
  ];
}

const List<Type> _supertypes$TexturedSystem = <Type>[
  _TexturedSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$TexturedState(Object object) {
  final owner = object as _TexturedState;
  return <ScannableField>[
    owner.texturedSystem,
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

const List<Type> _supertypes$TexturedState = <Type>[
  _TexturedState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$TexturedGame(Object object) {
  final owner = object as _TexturedGame;
  return <ScannableField>[
    owner.reportedAddress,
    owner.reportedLoaded,
  ];
}

const List<Type> _supertypes$TexturedGame = <Type>[
  _TexturedGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

List<ScannableField> _collect$LateProp(Object object) {
  final owner = object as _LateProp;
  return <ScannableField>[
    owner.texture,
  ];
}

const List<Type> _supertypes$LateProp = <Type>[
  _LateProp,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$LateScene(Object object) {
  final owner = object as _LateScene;
  return <ScannableField>[
    owner.prop,
  ];
}

const List<Type> _supertypes$LateScene = <Type>[
  _LateScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$LoadLate(Object object) {
  object as _LoadLate;
  return const <ScannableField>[];
}

const List<Type> _supertypes$LoadLate = <Type>[
  _LoadLate,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$UnloadLate(Object object) {
  object as _UnloadLate;
  return const <ScannableField>[];
}

const List<Type> _supertypes$UnloadLate = <Type>[
  _UnloadLate,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

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

const List<Type> _supertypes$LateState = <Type>[
  _LateState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$LateGame(Object object) {
  final owner = object as _LateGame;
  return <ScannableField>[
    owner.progress,
    owner.lateAddress,
  ];
}

const List<Type> _supertypes$LateGame = <Type>[
  _LateGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

List<ScannableField> _collect$DropScene(Object object) {
  object as _DropScene;
  return const <ScannableField>[];
}

const List<Type> _supertypes$DropScene = <Type>[
  _DropScene,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$UnloadState(Object object) {
  final owner = object as _UnloadState;
  return <ScannableField>[
    owner.moverSystem2,
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

const List<Type> _supertypes$UnloadState = <Type>[
  _UnloadState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$UnloadGame(Object object) {
  object as _UnloadGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$UnloadGame = <Type>[
  _UnloadGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

List<ScannableField> _collect$AskMain(Object object) {
  final owner = object as _AskMain;
  return <ScannableField>[
    owner.answer,
  ];
}

const List<Type> _supertypes$AskMain = <Type>[
  _AskMain,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$AskGame(Object object) {
  object as _AskGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$AskGame = <Type>[
  _AskGame,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$StartAsking(Object object) {
  object as _StartAsking;
  return const <ScannableField>[];
}

const List<Type> _supertypes$StartAsking = <Type>[
  _StartAsking,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$AskingSystem(Object object) {
  object as _AskingSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$AskingSystem = <Type>[
  _AskingSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  Tickable,
];

List<ScannableField> _collect$AskingState(Object object) {
  final owner = object as _AskingState;
  return <ScannableField>[
    owner.askingSystem,
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

const List<Type> _supertypes$AskingState = <Type>[
  _AskingState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

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

const List<Type> _supertypes$AskingGame = <Type>[
  _AskingGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

List<ScannableField> _collect$ReadPaused(Object object) {
  final owner = object as _ReadPaused;
  return <ScannableField>[
    owner.atTick,
    owner.wasStopped,
  ];
}

const List<Type> _supertypes$ReadPaused = <Type>[
  _ReadPaused,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$ReadOrder(Object object) {
  final owner = object as _ReadOrder;
  return <ScannableField>[
    owner.ordinal,
  ];
}

const List<Type> _supertypes$ReadOrder = <Type>[
  _ReadOrder,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$NeedsTick(Object object) {
  object as _NeedsTick;
  return const <ScannableField>[];
}

const List<Type> _supertypes$NeedsTick = <Type>[
  _NeedsTick,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

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

const List<Type> _supertypes$PausedAskState = <Type>[
  _PausedAskState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$PausedAskGame(Object object) {
  final owner = object as _PausedAskGame;
  return <ScannableField>[
    owner.tickRan,
  ];
}

const List<Type> _supertypes$PausedAskGame = <Type>[
  _PausedAskGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

List<ScannableField> _collect$Pebble(Object object) {
  final owner = object as _Pebble;
  return <ScannableField>[
    owner.weight,
  ];
}

const List<Type> _supertypes$Pebble = <Type>[
  _Pebble,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Counted,
];

List<ScannableField> _collect$CensusScene(Object object) {
  final owner = object as _CensusScene;
  return <ScannableField>[
    owner.pebble,
  ];
}

const List<Type> _supertypes$CensusScene = <Type>[
  _CensusScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$IdleSystem(Object object) {
  object as _IdleSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$IdleSystem = <Type>[
  _IdleSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$SleepySystem(Object object) {
  object as _SleepySystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$SleepySystem = <Type>[
  _SleepySystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$TakeWorldCensus(Object object) {
  final owner = object as _TakeWorldCensus;
  return <ScannableField>[
    owner.blob,
  ];
}

const List<Type> _supertypes$TakeWorldCensus = <Type>[
  _TakeWorldCensus,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$SleepASystem(Object object) {
  object as _SleepASystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$SleepASystem = <Type>[
  _SleepASystem,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$CensusIsolateState(Object object) {
  final owner = object as _CensusIsolateState;
  return <ScannableField>[
    owner.idleSystem,
    owner.sleepySystem,
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

const List<Type> _supertypes$CensusIsolateState = <Type>[
  _CensusIsolateState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$CensusIsolateGame(Object object) {
  object as _CensusIsolateGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$CensusIsolateGame = <Type>[
  _CensusIsolateGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

List<ScannableField> _collect$RegistrarSystem(Object object) {
  object as _RegistrarSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$RegistrarSystem = <Type>[
  _RegistrarSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$RegistrarState(Object object) {
  final owner = object as _RegistrarState;
  return <ScannableField>[
    owner.registrarSystem,
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

const List<Type> _supertypes$RegistrarState = <Type>[
  _RegistrarState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$RegistrarGame(Object object) {
  final owner = object as _RegistrarGame;
  return <ScannableField>[
    owner.registeredHere,
  ];
}

const List<Type> _supertypes$RegistrarGame = <Type>[
  _RegistrarGame,
  Game,
  RandomOwner,
  Scannable,
  _Declares,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _gameIsolateTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/game_isolate_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Mover, _collect$Mover, _supertypes$Mover),
        DeclarationCollector(
          _MoverScene,
          _collect$MoverScene,
          _supertypes$MoverScene,
        ),
        DeclarationCollector(
          _MoverSystem,
          _collect$MoverSystem,
          _supertypes$MoverSystem,
        ),
        DeclarationCollector(
          _SpawnMover,
          _collect$SpawnMover,
          _supertypes$SpawnMover,
        ),
        DeclarationCollector(
          _ResumeByControl,
          _collect$ResumeByControl,
          _supertypes$ResumeByControl,
        ),
        DeclarationCollector(
          _ResumeByTick,
          _collect$ResumeByTick,
          _supertypes$ResumeByTick,
        ),
        DeclarationCollector(
          _ControlProbe,
          _collect$ControlProbe,
          _supertypes$ControlProbe,
        ),
        DeclarationCollector(
          _PauseMover,
          _collect$PauseMover,
          _supertypes$PauseMover,
        ),
        DeclarationCollector(
          _IsolateState,
          _collect$IsolateState,
          _supertypes$IsolateState,
        ),
        DeclarationCollector(
          _DyingSystem,
          _collect$DyingSystem,
          _supertypes$DyingSystem,
        ),
        DeclarationCollector(
          _DyingState,
          _collect$DyingState,
          _supertypes$DyingState,
        ),
        DeclarationCollector(
          _DyingGame,
          _collect$DyingGame,
          _supertypes$DyingGame,
        ),
        DeclarationCollector(
          _RandomReporter,
          _collect$RandomReporter,
          _supertypes$RandomReporter,
        ),
        DeclarationCollector(
          _RandomIsolateState,
          _collect$RandomIsolateState,
          _supertypes$RandomIsolateState,
        ),
        DeclarationCollector(
          _RandomIsolateGame,
          _collect$RandomIsolateGame,
          _supertypes$RandomIsolateGame,
        ),
        DeclarationCollector(
          _IsolateGame,
          _collect$IsolateGame,
          _supertypes$IsolateGame,
        ),
        DeclarationCollector(
          _PingSystem,
          _collect$PingSystem,
          _supertypes$PingSystem,
        ),
        DeclarationCollector(
          _PingState,
          _collect$PingState,
          _supertypes$PingState,
        ),
        DeclarationCollector(
          _PingGame,
          _collect$PingGame,
          _supertypes$PingGame,
        ),
        DeclarationCollector(
          _CounterSystem,
          _collect$CounterSystem,
          _supertypes$CounterSystem,
        ),
        DeclarationCollector(
          _ChannelState,
          _collect$ChannelState,
          _supertypes$ChannelState,
        ),
        DeclarationCollector(
          _ChannelGame,
          _collect$ChannelGame,
          _supertypes$ChannelGame,
        ),
        DeclarationCollector(
          _InputProbeSystem,
          _collect$InputProbeSystem,
          _supertypes$InputProbeSystem,
        ),
        DeclarationCollector(
          _InputProbeState,
          _collect$InputProbeState,
          _supertypes$InputProbeState,
        ),
        DeclarationCollector(
          _InputProbeGame,
          _collect$InputProbeGame,
          _supertypes$InputProbeGame,
        ),
        DeclarationCollector(
          _Textured,
          _collect$Textured,
          _supertypes$Textured,
        ),
        DeclarationCollector(
          _TexturedScene,
          _collect$TexturedScene,
          _supertypes$TexturedScene,
        ),
        DeclarationCollector(
          _TexturedSystem,
          _collect$TexturedSystem,
          _supertypes$TexturedSystem,
        ),
        DeclarationCollector(
          _TexturedState,
          _collect$TexturedState,
          _supertypes$TexturedState,
        ),
        DeclarationCollector(
          _TexturedGame,
          _collect$TexturedGame,
          _supertypes$TexturedGame,
        ),
        DeclarationCollector(
          _LateProp,
          _collect$LateProp,
          _supertypes$LateProp,
        ),
        DeclarationCollector(
          _LateScene,
          _collect$LateScene,
          _supertypes$LateScene,
        ),
        DeclarationCollector(
          _LoadLate,
          _collect$LoadLate,
          _supertypes$LoadLate,
        ),
        DeclarationCollector(
          _UnloadLate,
          _collect$UnloadLate,
          _supertypes$UnloadLate,
        ),
        DeclarationCollector(
          _LateState,
          _collect$LateState,
          _supertypes$LateState,
        ),
        DeclarationCollector(
          _LateGame,
          _collect$LateGame,
          _supertypes$LateGame,
        ),
        DeclarationCollector(
          _DropScene,
          _collect$DropScene,
          _supertypes$DropScene,
        ),
        DeclarationCollector(
          _UnloadState,
          _collect$UnloadState,
          _supertypes$UnloadState,
        ),
        DeclarationCollector(
          _UnloadGame,
          _collect$UnloadGame,
          _supertypes$UnloadGame,
        ),
        DeclarationCollector(_AskMain, _collect$AskMain, _supertypes$AskMain),
        DeclarationCollector(_AskGame, _collect$AskGame, _supertypes$AskGame),
        DeclarationCollector(
          _StartAsking,
          _collect$StartAsking,
          _supertypes$StartAsking,
        ),
        DeclarationCollector(
          _AskingSystem,
          _collect$AskingSystem,
          _supertypes$AskingSystem,
        ),
        DeclarationCollector(
          _AskingState,
          _collect$AskingState,
          _supertypes$AskingState,
        ),
        DeclarationCollector(
          _AskingGame,
          _collect$AskingGame,
          _supertypes$AskingGame,
        ),
        DeclarationCollector(
          _ReadPaused,
          _collect$ReadPaused,
          _supertypes$ReadPaused,
        ),
        DeclarationCollector(
          _ReadOrder,
          _collect$ReadOrder,
          _supertypes$ReadOrder,
        ),
        DeclarationCollector(
          _NeedsTick,
          _collect$NeedsTick,
          _supertypes$NeedsTick,
        ),
        DeclarationCollector(
          _PausedAskState,
          _collect$PausedAskState,
          _supertypes$PausedAskState,
        ),
        DeclarationCollector(
          _PausedAskGame,
          _collect$PausedAskGame,
          _supertypes$PausedAskGame,
        ),
        DeclarationCollector(_Pebble, _collect$Pebble, _supertypes$Pebble),
        DeclarationCollector(
          _CensusScene,
          _collect$CensusScene,
          _supertypes$CensusScene,
        ),
        DeclarationCollector(
          _IdleSystem,
          _collect$IdleSystem,
          _supertypes$IdleSystem,
        ),
        DeclarationCollector(
          _SleepySystem,
          _collect$SleepySystem,
          _supertypes$SleepySystem,
        ),
        DeclarationCollector(
          _TakeWorldCensus,
          _collect$TakeWorldCensus,
          _supertypes$TakeWorldCensus,
        ),
        DeclarationCollector(
          _SleepASystem,
          _collect$SleepASystem,
          _supertypes$SleepASystem,
        ),
        DeclarationCollector(
          _CensusIsolateState,
          _collect$CensusIsolateState,
          _supertypes$CensusIsolateState,
        ),
        DeclarationCollector(
          _CensusIsolateGame,
          _collect$CensusIsolateGame,
          _supertypes$CensusIsolateGame,
        ),
        DeclarationCollector(
          _RegistrarSystem,
          _collect$RegistrarSystem,
          _supertypes$RegistrarSystem,
        ),
        DeclarationCollector(
          _RegistrarState,
          _collect$RegistrarState,
          _supertypes$RegistrarState,
        ),
        DeclarationCollector(
          _RegistrarGame,
          _collect$RegistrarGame,
          _supertypes$RegistrarGame,
        ),
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
