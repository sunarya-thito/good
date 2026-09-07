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
part of 'coroutine_test.dart';

List<ScannableField> _collect$Mover(Object object) {
  final owner = object as _Mover;
  return <ScannableField>[
    owner.marker,
  ];
}

const List<Type> _supertypes$Mover = <Type>[
  _Mover,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$Scene(Object object) {
  final owner = object as _Scene;
  return <ScannableField>[
    owner.mover,
  ];
}

const List<Type> _supertypes$Scene = <Type>[
  _Scene,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$State(Object object) {
  final owner = object as _State;
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

const List<Type> _supertypes$State = <Type>[
  _State,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
];

List<ScannableField> _collect$Game(Object object) {
  object as _Game;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Game = <Type>[
  _Game,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _coroutineTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/coroutine_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Mover, _collect$Mover, _supertypes$Mover),
        DeclarationCollector(_Scene, _collect$Scene, _supertypes$Scene),
        DeclarationCollector(_State, _collect$State, _supertypes$State),
        DeclarationCollector(_Game, _collect$Game, _supertypes$Game),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_coroutineTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_coroutineTestDeclarations],
);
