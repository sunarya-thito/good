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
part of 'event_lifecycle_test.dart';

List<ScannableField> _collect$Unit(Object object) {
  final owner = object as _Unit;
  return <ScannableField>[
    owner.mark,
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
  _Marked,
];

List<ScannableField> _collect$Watcher(Object object) {
  object as _Watcher;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Watcher = <Type>[
  _Watcher,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  GameLifecycleListener,
];

List<ScannableField> _collect$Bystander(Object object) {
  object as _Bystander;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Bystander = <Type>[
  _Bystander,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$Observing(Object object) {
  object as _Observing;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Observing = <Type>[
  _Observing,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  SceneLoadListener,
  EntitySpawnListener,
];

List<ScannableField> _collect$Level(Object object) {
  final owner = object as _Level;
  return <ScannableField>[
    owner.unit,
  ];
}

const List<Type> _supertypes$Level = <Type>[
  _Level,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$Observer(Object object) {
  object as _Observer;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Observer = <Type>[
  _Observer,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$NosyScene(Object object) {
  final owner = object as _NosyScene;
  return <ScannableField>[
    owner.unit,
  ];
}

const List<Type> _supertypes$NosyScene = <Type>[
  _NosyScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$Tracked(Object object) {
  final owner = object as _Tracked;
  return <ScannableField>[
    owner.mark,
  ];
}

const List<Type> _supertypes$Tracked = <Type>[
  _Tracked,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Marked,
];

List<ScannableField> _collect$Indexed(Object object) {
  final owner = object as _Indexed;
  return <ScannableField>[
    owner.mark,
  ];
}

const List<Type> _supertypes$Indexed = <Type>[
  _Indexed,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Marked,
];

List<ScannableField> _collect$Census(Object object) {
  object as _Census;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Census = <Type>[
  _Census,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  EntitySpawnListener,
];

List<ScannableField> _collect$TrackedScene(Object object) {
  final owner = object as _TrackedScene;
  return <ScannableField>[
    owner.tracked,
    owner.indexed,
  ];
}

const List<Type> _supertypes$TrackedScene = <Type>[
  _TrackedScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$LifecycleState(Object object) {
  final owner = object as _LifecycleState;
  return <ScannableField>[
    owner.watcher,
    owner.census,
    owner.bystander,
    owner.observing,
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

const List<Type> _supertypes$LifecycleState = <Type>[
  _LifecycleState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$LifecycleGame(Object object) {
  object as _LifecycleGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$LifecycleGame = <Type>[
  _LifecycleGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _eventLifecycleTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/event_lifecycle_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Unit, _collect$Unit, _supertypes$Unit),
        DeclarationCollector(_Watcher, _collect$Watcher, _supertypes$Watcher),
        DeclarationCollector(
          _Bystander,
          _collect$Bystander,
          _supertypes$Bystander,
        ),
        DeclarationCollector(
          _Observing,
          _collect$Observing,
          _supertypes$Observing,
        ),
        DeclarationCollector(_Level, _collect$Level, _supertypes$Level),
        DeclarationCollector(
          _Observer,
          _collect$Observer,
          _supertypes$Observer,
        ),
        DeclarationCollector(
          _NosyScene,
          _collect$NosyScene,
          _supertypes$NosyScene,
        ),
        DeclarationCollector(_Tracked, _collect$Tracked, _supertypes$Tracked),
        DeclarationCollector(_Indexed, _collect$Indexed, _supertypes$Indexed),
        DeclarationCollector(_Census, _collect$Census, _supertypes$Census),
        DeclarationCollector(
          _TrackedScene,
          _collect$TrackedScene,
          _supertypes$TrackedScene,
        ),
        DeclarationCollector(
          _LifecycleState,
          _collect$LifecycleState,
          _supertypes$LifecycleState,
        ),
        DeclarationCollector(
          _LifecycleGame,
          _collect$LifecycleGame,
          _supertypes$LifecycleGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_eventLifecycleTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_eventLifecycleTestDeclarations],
);
