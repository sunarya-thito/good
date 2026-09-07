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
part of 'game_buffer_test.dart';

List<ScannableField> _collect$Empty(Object object) {
  object as _Empty;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Empty = <Type>[
  _Empty,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$EmptyScene(Object object) {
  object as _EmptyScene;
  return const <ScannableField>[];
}

const List<Type> _supertypes$EmptyScene = <Type>[
  _EmptyScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
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

List<ScannableField> _collect$BufferState(Object object) {
  final owner = object as _BufferState;
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

const List<Type> _supertypes$BufferState = <Type>[
  _BufferState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$BufferGame(Object object) {
  object as _BufferGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$BufferGame = <Type>[
  _BufferGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$TwoBufferGame(Object object) {
  object as _TwoBufferGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$TwoBufferGame = <Type>[
  _TwoBufferGame,
  _BufferGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$TinyBufferGame(Object object) {
  object as _TinyBufferGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$TinyBufferGame = <Type>[
  _TinyBufferGame,
  _BufferGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

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

List<ScannableField> _collect$BareGame(Object object) {
  object as _BareGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$BareGame = <Type>[
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _gameBufferTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/game_buffer_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Empty, _collect$Empty, _supertypes$Empty),
        DeclarationCollector(
          _EmptyScene,
          _collect$EmptyScene,
          _supertypes$EmptyScene,
        ),
        DeclarationCollector(
          _PingSystem,
          _collect$PingSystem,
          _supertypes$PingSystem,
        ),
        DeclarationCollector(
          _BufferState,
          _collect$BufferState,
          _supertypes$BufferState,
        ),
        DeclarationCollector(
          _BufferGame,
          _collect$BufferGame,
          _supertypes$BufferGame,
        ),
        DeclarationCollector(
          _TwoBufferGame,
          _collect$TwoBufferGame,
          _supertypes$TwoBufferGame,
        ),
        DeclarationCollector(
          _TinyBufferGame,
          _collect$TinyBufferGame,
          _supertypes$TinyBufferGame,
        ),
        DeclarationCollector(
          _BareState,
          _collect$BareState,
          _supertypes$BareState,
        ),
        DeclarationCollector(
          _BareGame,
          _collect$BareGame,
          _supertypes$BareGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_gameBufferTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_gameBufferTestDeclarations],
);
