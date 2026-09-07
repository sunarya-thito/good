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
part of 'game_input_test.dart';

List<ScannableField> _collect$PlayerSystem(Object object) {
  final owner = object as _PlayerSystem;
  return <ScannableField>[
    owner.movement,
    owner.triggerSkill,
    owner.ping,
    owner.aim,
  ];
}

const List<Type> _supertypes$PlayerSystem = <Type>[
  _PlayerSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$InputGameState(Object object) {
  final owner = object as _InputGameState;
  return <ScannableField>[
    owner.playerSystem,
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

const List<Type> _supertypes$InputGameState = <Type>[
  _InputGameState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$InputGame(Object object) {
  object as _InputGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$InputGame = <Type>[
  _InputGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$ListenerSystemA(Object object) {
  final owner = object as _ListenerSystemA;
  return <ScannableField>[
    owner.fire,
  ];
}

const List<Type> _supertypes$ListenerSystemA = <Type>[
  _ListenerSystemA,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$ListenerSystemB(Object object) {
  final owner = object as _ListenerSystemB;
  return <ScannableField>[
    owner.fire,
  ];
}

const List<Type> _supertypes$ListenerSystemB = <Type>[
  _ListenerSystemB,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$ListenerState(Object object) {
  final owner = object as _ListenerState;
  return <ScannableField>[
    owner.listenerSystemA,
    owner.listenerSystemB,
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

const List<Type> _supertypes$ListenerState = <Type>[
  _ListenerState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$ListenerGame(Object object) {
  object as _ListenerGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ListenerGame = <Type>[
  _ListenerGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$ShorthandSystem(Object object) {
  final owner = object as _ShorthandSystem;
  return <ScannableField>[
    owner.attack,
    owner.movement,
    owner.jump,
    owner.cursor,
  ];
}

const List<Type> _supertypes$ShorthandSystem = <Type>[
  _ShorthandSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$ShorthandState(Object object) {
  final owner = object as _ShorthandState;
  return <ScannableField>[
    owner.shorthandSystem,
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

const List<Type> _supertypes$ShorthandState = <Type>[
  _ShorthandState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$ShorthandGame(Object object) {
  object as _ShorthandGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ShorthandGame = <Type>[
  _ShorthandGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$CtorSubSystem(Object object) {
  final owner = object as _CtorSubSystem;
  return <ScannableField>[
    owner.fire,
  ];
}

const List<Type> _supertypes$CtorSubSystem = <Type>[
  _CtorSubSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$CtorSubOldSpelling(Object object) {
  final owner = object as _CtorSubOldSpelling;
  return <ScannableField>[
    owner.jump,
  ];
}

const List<Type> _supertypes$CtorSubOldSpelling = <Type>[
  _CtorSubOldSpelling,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$CtorSubState(Object object) {
  final owner = object as _CtorSubState;
  return <ScannableField>[
    owner.ctorSubSystem,
    owner.ctorSubOldSpelling,
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

const List<Type> _supertypes$CtorSubState = <Type>[
  _CtorSubState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$CtorSubGame(Object object) {
  object as _CtorSubGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$CtorSubGame = <Type>[
  _CtorSubGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$NoSuperGame(Object object) {
  final owner = object as _NoSuperGame;
  return <ScannableField>[
    owner.orphan,
    owner.ownDefault,
  ];
}

const List<Type> _supertypes$NoSuperGame = <Type>[
  _NoSuperGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$NoSuperState(Object object) {
  final owner = object as _NoSuperState;
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

const List<Type> _supertypes$NoSuperState = <Type>[
  _NoSuperState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$DuplicateDefaultGame(Object object) {
  object as _DuplicateDefaultGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$DuplicateDefaultGame = <Type>[
  _DuplicateDefaultGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$DuplicateDefaultState(Object object) {
  final owner = object as _DuplicateDefaultState;
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

const List<Type> _supertypes$DuplicateDefaultState = <Type>[
  _DuplicateDefaultState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$LateDefaultSystem(Object object) {
  object as _LateDefaultSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$LateDefaultSystem = <Type>[
  _LateDefaultSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$SharedDescriptorGame(Object object) {
  final owner = object as _SharedDescriptorGame;
  return <ScannableField>[
    owner.throttle,
  ];
}

const List<Type> _supertypes$SharedDescriptorGame = <Type>[
  _SharedDescriptorGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$SharedDescriptorState(Object object) {
  final owner = object as _SharedDescriptorState;
  return <ScannableField>[
    owner.lateDefaultSystem,
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

const List<Type> _supertypes$SharedDescriptorState = <Type>[
  _SharedDescriptorState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$CursorSystem(Object object) {
  final owner = object as _CursorSystem;
  return <ScannableField>[
    owner.cursor,
    owner.click,
  ];
}

const List<Type> _supertypes$CursorSystem = <Type>[
  _CursorSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$MouseGameState(Object object) {
  final owner = object as _MouseGameState;
  return <ScannableField>[
    owner.cursorSystem,
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

const List<Type> _supertypes$MouseGameState = <Type>[
  _MouseGameState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$MouseGame(Object object) {
  object as _MouseGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$MouseGame = <Type>[
  _MouseGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$PrecedenceGame(Object object) {
  final owner = object as _PrecedenceGame;
  return <ScannableField>[
    owner.loud,
    owner.quiet,
  ];
}

const List<Type> _supertypes$PrecedenceGame = <Type>[
  _PrecedenceGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$PrecedenceState(Object object) {
  final owner = object as _PrecedenceState;
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

const List<Type> _supertypes$PrecedenceState = <Type>[
  _PrecedenceState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _gameInputTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/game_input_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(
          _PlayerSystem,
          _collect$PlayerSystem,
          _supertypes$PlayerSystem,
        ),
        DeclarationCollector(
          _InputGameState,
          _collect$InputGameState,
          _supertypes$InputGameState,
        ),
        DeclarationCollector(
          _InputGame,
          _collect$InputGame,
          _supertypes$InputGame,
        ),
        DeclarationCollector(
          _ListenerSystemA,
          _collect$ListenerSystemA,
          _supertypes$ListenerSystemA,
        ),
        DeclarationCollector(
          _ListenerSystemB,
          _collect$ListenerSystemB,
          _supertypes$ListenerSystemB,
        ),
        DeclarationCollector(
          _ListenerState,
          _collect$ListenerState,
          _supertypes$ListenerState,
        ),
        DeclarationCollector(
          _ListenerGame,
          _collect$ListenerGame,
          _supertypes$ListenerGame,
        ),
        DeclarationCollector(
          _ShorthandSystem,
          _collect$ShorthandSystem,
          _supertypes$ShorthandSystem,
        ),
        DeclarationCollector(
          _ShorthandState,
          _collect$ShorthandState,
          _supertypes$ShorthandState,
        ),
        DeclarationCollector(
          _ShorthandGame,
          _collect$ShorthandGame,
          _supertypes$ShorthandGame,
        ),
        DeclarationCollector(
          _CtorSubSystem,
          _collect$CtorSubSystem,
          _supertypes$CtorSubSystem,
        ),
        DeclarationCollector(
          _CtorSubOldSpelling,
          _collect$CtorSubOldSpelling,
          _supertypes$CtorSubOldSpelling,
        ),
        DeclarationCollector(
          _CtorSubState,
          _collect$CtorSubState,
          _supertypes$CtorSubState,
        ),
        DeclarationCollector(
          _CtorSubGame,
          _collect$CtorSubGame,
          _supertypes$CtorSubGame,
        ),
        DeclarationCollector(
          _NoSuperGame,
          _collect$NoSuperGame,
          _supertypes$NoSuperGame,
        ),
        DeclarationCollector(
          _NoSuperState,
          _collect$NoSuperState,
          _supertypes$NoSuperState,
        ),
        DeclarationCollector(
          _DuplicateDefaultGame,
          _collect$DuplicateDefaultGame,
          _supertypes$DuplicateDefaultGame,
        ),
        DeclarationCollector(
          _DuplicateDefaultState,
          _collect$DuplicateDefaultState,
          _supertypes$DuplicateDefaultState,
        ),
        DeclarationCollector(
          _LateDefaultSystem,
          _collect$LateDefaultSystem,
          _supertypes$LateDefaultSystem,
        ),
        DeclarationCollector(
          _SharedDescriptorGame,
          _collect$SharedDescriptorGame,
          _supertypes$SharedDescriptorGame,
        ),
        DeclarationCollector(
          _SharedDescriptorState,
          _collect$SharedDescriptorState,
          _supertypes$SharedDescriptorState,
        ),
        DeclarationCollector(
          _CursorSystem,
          _collect$CursorSystem,
          _supertypes$CursorSystem,
        ),
        DeclarationCollector(
          _MouseGameState,
          _collect$MouseGameState,
          _supertypes$MouseGameState,
        ),
        DeclarationCollector(
          _MouseGame,
          _collect$MouseGame,
          _supertypes$MouseGame,
        ),
        DeclarationCollector(
          _PrecedenceGame,
          _collect$PrecedenceGame,
          _supertypes$PrecedenceGame,
        ),
        DeclarationCollector(
          _PrecedenceState,
          _collect$PrecedenceState,
          _supertypes$PrecedenceState,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_gameInputTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_gameInputTestDeclarations],
);
