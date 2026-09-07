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
part of 'event_declaration_test.dart';

List<ScannableField> _collect$NotedSystem(Object object) {
  object as _NotedSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$NotedSystem = <Type>[
  _NotedSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  _Noted,
];

List<ScannableField> _collect$PublisherSystem(Object object) {
  final owner = object as _PublisherSystem;
  return <ScannableField>[
    owner.own,
  ];
}

const List<Type> _supertypes$PublisherSystem = <Type>[
  _PublisherSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  _Noted,
];

List<ScannableField> _collect$UnitA(Object object) {
  object as _UnitA;
  return const <ScannableField>[];
}

const List<Type> _supertypes$UnitA = <Type>[
  _UnitA,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$UnitB(Object object) {
  object as _UnitB;
  return const <ScannableField>[];
}

const List<Type> _supertypes$UnitB = <Type>[
  _UnitB,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$NotedScene(Object object) {
  final owner = object as _NotedScene;
  return <ScannableField>[
    owner.a,
    owner.b,
  ];
}

const List<Type> _supertypes$NotedScene = <Type>[
  _NotedScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$FieldState(Object object) {
  final owner = object as _FieldState;
  return <ScannableField>[
    owner.alpha,
    owner.beta,
    owner.notedSystem,
    owner.publisher,
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

const List<Type> _supertypes$FieldState = <Type>[
  _FieldState,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  _Noted,
];

List<ScannableField> _collect$FieldGame(Object object) {
  object as _FieldGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$FieldGame = <Type>[
  _FieldGame,
  _NotedGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$Pair(Object object) {
  final owner = object as _Pair;
  return <ScannableField>[
    owner.eager,
  ];
}

const List<Type> _supertypes$Pair = <Type>[
  _Pair,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  _Noted,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _eventDeclarationTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/event_declaration_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(
          _NotedSystem,
          _collect$NotedSystem,
          _supertypes$NotedSystem,
        ),
        DeclarationCollector(
          _PublisherSystem,
          _collect$PublisherSystem,
          _supertypes$PublisherSystem,
        ),
        DeclarationCollector(_UnitA, _collect$UnitA, _supertypes$UnitA),
        DeclarationCollector(_UnitB, _collect$UnitB, _supertypes$UnitB),
        DeclarationCollector(
          _NotedScene,
          _collect$NotedScene,
          _supertypes$NotedScene,
        ),
        DeclarationCollector(
          _FieldState,
          _collect$FieldState,
          _supertypes$FieldState,
        ),
        DeclarationCollector(
          _FieldGame,
          _collect$FieldGame,
          _supertypes$FieldGame,
        ),
        DeclarationCollector(_Pair, _collect$Pair, _supertypes$Pair),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_eventDeclarationTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_eventDeclarationTestDeclarations],
);
