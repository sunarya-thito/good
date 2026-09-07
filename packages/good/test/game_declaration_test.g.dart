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
part of 'game_declaration_test.dart';

List<ScannableField> _collect$BareState(Object object) {
  final owner = object as _BareState;
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

const List<Type> _supertypes$BareState = <Type>[
  _BareState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$FieldGame(Object object) {
  final owner = object as _FieldGame;
  return <ScannableField>[
    owner.score,
    owner.health,
    owner.alive,
  ];
}

const List<Type> _supertypes$FieldGame = <Type>[
  _FieldGame,
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$FieldInputGame(Object object) {
  final owner = object as _FieldInputGame;
  return <ScannableField>[
    owner.fire,
    owner.unbound,
  ];
}

const List<Type> _supertypes$FieldInputGame = <Type>[
  _FieldInputGame,
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$MixedInputGame(Object object) {
  final owner = object as _MixedInputGame;
  return <ScannableField>[
    owner.throttleField,
  ];
}

const List<Type> _supertypes$MixedInputGame = <Type>[
  _MixedInputGame,
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$Nested(Object object) {
  final owner = object as _Nested;
  return <ScannableField>[
    owner.score,
    owner.fire,
  ];
}

const List<Type> _supertypes$Nested = <Type>[
  _Nested,
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$NestingGame(Object object) {
  final owner = object as _NestingGame;
  return <ScannableField>[
    owner.own,
  ];
}

const List<Type> _supertypes$NestingGame = <Type>[
  _NestingGame,
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$InputOnly(Object object) {
  final owner = object as _InputOnly;
  return <ScannableField>[
    owner.fire,
  ];
}

const List<Type> _supertypes$InputOnly = <Type>[
  _InputOnly,
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$GameBuildingSystem(Object object) {
  object as _GameBuildingSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$GameBuildingSystem = <Type>[
  _GameBuildingSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$SystemHostGame(Object object) {
  object as _SystemHostGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$SystemHostGame = <Type>[
  _SystemHostGame,
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$SystemHostState(Object object) {
  final owner = object as _SystemHostState;
  return <ScannableField>[
    owner.gameBuildingSystem,
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

const List<Type> _supertypes$SystemHostState = <Type>[
  _SystemHostState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$NoTableGame(Object object) {
  object as _NoTableGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$NoTableGame = <Type>[
  _NoTableGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$NoTableState(Object object) {
  final owner = object as _NoTableState;
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

const List<Type> _supertypes$NoTableState = <Type>[
  _NoTableState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$CrossingGame(Object object) {
  final owner = object as _CrossingGame;
  return <ScannableField>[
    owner.first,
    owner.second,
  ];
}

const List<Type> _supertypes$CrossingGame = <Type>[
  _CrossingGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$CrossingState(Object object) {
  final owner = object as _CrossingState;
  return <ScannableField>[
    owner.crossingSystem,
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

const List<Type> _supertypes$CrossingState = <Type>[
  _CrossingState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$CrossingSystem(Object object) {
  object as _CrossingSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$CrossingSystem = <Type>[
  _CrossingSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _gameDeclarationTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/game_declaration_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(
          _BareState,
          _collect$BareState,
          _supertypes$BareState,
        ),
        DeclarationCollector(
          _FieldGame,
          _collect$FieldGame,
          _supertypes$FieldGame,
        ),
        DeclarationCollector(
          _FieldInputGame,
          _collect$FieldInputGame,
          _supertypes$FieldInputGame,
        ),
        DeclarationCollector(
          _MixedInputGame,
          _collect$MixedInputGame,
          _supertypes$MixedInputGame,
        ),
        DeclarationCollector(_Nested, _collect$Nested, _supertypes$Nested),
        DeclarationCollector(
          _NestingGame,
          _collect$NestingGame,
          _supertypes$NestingGame,
        ),
        DeclarationCollector(
          _InputOnly,
          _collect$InputOnly,
          _supertypes$InputOnly,
        ),
        DeclarationCollector(
          _GameBuildingSystem,
          _collect$GameBuildingSystem,
          _supertypes$GameBuildingSystem,
        ),
        DeclarationCollector(
          _SystemHostGame,
          _collect$SystemHostGame,
          _supertypes$SystemHostGame,
        ),
        DeclarationCollector(
          _SystemHostState,
          _collect$SystemHostState,
          _supertypes$SystemHostState,
        ),
        DeclarationCollector(
          _NoTableGame,
          _collect$NoTableGame,
          _supertypes$NoTableGame,
        ),
        DeclarationCollector(
          _NoTableState,
          _collect$NoTableState,
          _supertypes$NoTableState,
        ),
        DeclarationCollector(
          _CrossingGame,
          _collect$CrossingGame,
          _supertypes$CrossingGame,
        ),
        DeclarationCollector(
          _CrossingState,
          _collect$CrossingState,
          _supertypes$CrossingState,
        ),
        DeclarationCollector(
          _CrossingSystem,
          _collect$CrossingSystem,
          _supertypes$CrossingSystem,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_gameDeclarationTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_gameDeclarationTestDeclarations],
);
