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
part of 'event_reach_test.dart';

List<ScannableField> _collect$PingSystem(Object object) {
  object as _PingSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$PingSystem = <Type>[
  _PingSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  _Ping,
];

List<ScannableField> _collect$DeafSystem(Object object) {
  object as _DeafSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$DeafSystem = <Type>[
  _DeafSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$SelfishSystem(Object object) {
  final owner = object as _SelfishSystem;
  return <ScannableField>[
    owner.ping,
  ];
}

const List<Type> _supertypes$SelfishSystem = <Type>[
  _SelfishSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  _Ping,
];

List<ScannableField> _collect$PingUnit(Object object) {
  object as _PingUnit;
  return const <ScannableField>[];
}

const List<Type> _supertypes$PingUnit = <Type>[
  _PingUnit,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$PingScene(Object object) {
  final owner = object as _PingScene;
  return <ScannableField>[
    owner.unit,
  ];
}

const List<Type> _supertypes$PingScene = <Type>[
  _PingScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$PingState(Object object) {
  final owner = object as _PingState;
  return <ScannableField>[
    owner.ping,
    owner.pingSystem,
    owner.deafSystem,
    owner.selfishSystem,
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
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  _Ping,
];

List<ScannableField> _collect$PingGame(Object object) {
  object as _PingGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$PingGame = <Type>[
  _PingGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _eventReachTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/event_reach_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(
          _PingSystem,
          _collect$PingSystem,
          _supertypes$PingSystem,
        ),
        DeclarationCollector(
          _DeafSystem,
          _collect$DeafSystem,
          _supertypes$DeafSystem,
        ),
        DeclarationCollector(
          _SelfishSystem,
          _collect$SelfishSystem,
          _supertypes$SelfishSystem,
        ),
        DeclarationCollector(
          _PingUnit,
          _collect$PingUnit,
          _supertypes$PingUnit,
        ),
        DeclarationCollector(
          _PingScene,
          _collect$PingScene,
          _supertypes$PingScene,
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
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_eventReachTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_eventReachTestDeclarations],
);
