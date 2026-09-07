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
part of 'game_widget_test.dart';

List<ScannableField> _collect$BareState(Object object) {
  final owner = object as _BareState;
  return <ScannableField>[
    owner.tickingSystem,
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

List<ScannableField> _collect$BareScene(Object object) {
  object as _BareScene;
  return const <ScannableField>[];
}

const List<Type> _supertypes$BareScene = <Type>[
  _BareScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$TickingSystem(Object object) {
  object as _TickingSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$TickingSystem = <Type>[
  _TickingSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$ViewGame(Object object) {
  object as _ViewGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ViewGame = <Type>[
  _ViewGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$SilentGame(Object object) {
  object as _SilentGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$SilentGame = <Type>[
  _SilentGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$VisibilitySystem(Object object) {
  object as _VisibilitySystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$VisibilitySystem = <Type>[
  _VisibilitySystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  AppVisibilityListener,
  FixedTickable,
];

List<ScannableField> _collect$VisibilityState(Object object) {
  final owner = object as _VisibilityState;
  return <ScannableField>[
    owner.visibility,
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

const List<Type> _supertypes$VisibilityState = <Type>[
  _VisibilityState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$VisibilityGame(Object object) {
  object as _VisibilityGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$VisibilityGame = <Type>[
  _VisibilityGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _gameWidgetTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/game_widget_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(
          _BareState,
          _collect$BareState,
          _supertypes$BareState,
        ),
        DeclarationCollector(
          _BareScene,
          _collect$BareScene,
          _supertypes$BareScene,
        ),
        DeclarationCollector(
          _TickingSystem,
          _collect$TickingSystem,
          _supertypes$TickingSystem,
        ),
        DeclarationCollector(
          _ViewGame,
          _collect$ViewGame,
          _supertypes$ViewGame,
        ),
        DeclarationCollector(
          _SilentGame,
          _collect$SilentGame,
          _supertypes$SilentGame,
        ),
        DeclarationCollector(
          _VisibilitySystem,
          _collect$VisibilitySystem,
          _supertypes$VisibilitySystem,
        ),
        DeclarationCollector(
          _VisibilityState,
          _collect$VisibilityState,
          _supertypes$VisibilityState,
        ),
        DeclarationCollector(
          _VisibilityGame,
          _collect$VisibilityGame,
          _supertypes$VisibilityGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_gameWidgetTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_gameWidgetTestDeclarations],
);
