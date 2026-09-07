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
part of 'world_observation_test.dart';

List<ScannableField> _collect$Rock(Object object) {
  object as _Rock;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Rock = <Type>[
  _Rock,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$Tree(Object object) {
  object as _Tree;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Tree = <Type>[
  _Tree,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$Node(Object object) {
  final owner = object as _Node;
  return <ScannableField>[
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
  ];
}

const List<Type> _supertypes$Node = <Type>[
  _Node,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Child,
  Parent,
];

List<ScannableField> _collect$Watched(Object object) {
  object as _Watched;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Watched = <Type>[
  _Watched,
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
    owner.rock,
    owner.tree,
    owner.node,
    owner.watched,
  ];
}

const List<Type> _supertypes$Scene = <Type>[
  _Scene,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$Observer(Object object) {
  object as _Observer;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Observer = <Type>[
  _Observer,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  EntitySpawnListener,
  SceneLoadListener,
];

List<ScannableField> _collect$GameState(Object object) {
  final owner = object as _GameState;
  return <ScannableField>[
    owner.observer,
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

const List<Type> _supertypes$GameState = <Type>[
  _GameState,
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
const GeneratedDeclarations _worldObservationTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/world_observation_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Rock, _collect$Rock, _supertypes$Rock),
        DeclarationCollector(_Tree, _collect$Tree, _supertypes$Tree),
        DeclarationCollector(_Node, _collect$Node, _supertypes$Node),
        DeclarationCollector(_Watched, _collect$Watched, _supertypes$Watched),
        DeclarationCollector(_Scene, _collect$Scene, _supertypes$Scene),
        DeclarationCollector(
          _Observer,
          _collect$Observer,
          _supertypes$Observer,
        ),
        DeclarationCollector(
          _GameState,
          _collect$GameState,
          _supertypes$GameState,
        ),
        DeclarationCollector(_Game, _collect$Game, _supertypes$Game),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_worldObservationTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_worldObservationTestDeclarations],
);
