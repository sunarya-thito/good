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
part of 'heap_object_lifetime_test.dart';

List<ScannableField> _collect$Thing(Object object) {
  final owner = object as _Thing;
  return <ScannableField>[
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.owned,
    owner.maybe,
  ];
}

const List<Type> _supertypes$Thing = <Type>[
  _Thing,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Holder,
  Child,
  Parent,
];

List<ScannableField> _collect$Level(Object object) {
  final owner = object as _Level;
  return <ScannableField>[
    owner.thing,
  ];
}

const List<Type> _supertypes$Level = <Type>[
  _Level,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$GameLevel(Object object) {
  final owner = object as _GameLevel;
  return <ScannableField>[
    owner.thing,
  ];
}

const List<Type> _supertypes$GameLevel = <Type>[
  _GameLevel,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$HeapState(Object object) {
  final owner = object as _HeapState;
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

const List<Type> _supertypes$HeapState = <Type>[
  _HeapState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$HeapGame(Object object) {
  object as _HeapGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$HeapGame = <Type>[
  _HeapGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _heapObjectLifetimeTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/heap_object_lifetime_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Thing, _collect$Thing, _supertypes$Thing),
        DeclarationCollector(_Level, _collect$Level, _supertypes$Level),
        DeclarationCollector(
          _GameLevel,
          _collect$GameLevel,
          _supertypes$GameLevel,
        ),
        DeclarationCollector(
          _HeapState,
          _collect$HeapState,
          _supertypes$HeapState,
        ),
        DeclarationCollector(
          _HeapGame,
          _collect$HeapGame,
          _supertypes$HeapGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_heapObjectLifetimeTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_heapObjectLifetimeTestDeclarations],
);
