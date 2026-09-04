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

List<ScannableField> _collect$FieldGame(Object object) {
  final owner = object as _FieldGame;
  return <ScannableField>[
    owner.score,
    owner.health,
    owner.alive,
  ];
}

List<ScannableField> _collect$FieldInputGame(Object object) {
  final owner = object as _FieldInputGame;
  return <ScannableField>[
    owner.fire,
    owner.unbound,
  ];
}

List<ScannableField> _collect$MixedInputGame(Object object) {
  final owner = object as _MixedInputGame;
  return <ScannableField>[
    owner.throttleField,
  ];
}

List<ScannableField> _collect$Nested(Object object) {
  final owner = object as _Nested;
  return <ScannableField>[
    owner.score,
    owner.fire,
  ];
}

List<ScannableField> _collect$NestingGame(Object object) {
  final owner = object as _NestingGame;
  return <ScannableField>[
    owner.own,
  ];
}

List<ScannableField> _collect$InputOnly(Object object) {
  final owner = object as _InputOnly;
  return <ScannableField>[
    owner.fire,
  ];
}

List<ScannableField> _collect$GameBuildingSystem(Object object) {
  final owner = object as _GameBuildingSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$SystemHostGame(Object object) {
  object as _SystemHostGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$SystemHostState(Object object) {
  final owner = object as _SystemHostState;
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

List<ScannableField> _collect$NoTableGame(Object object) {
  object as _NoTableGame;
  return const <ScannableField>[];
}

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

List<ScannableField> _collect$CrossingGame(Object object) {
  final owner = object as _CrossingGame;
  return <ScannableField>[
    owner.first,
    owner.second,
  ];
}

List<ScannableField> _collect$CrossingState(Object object) {
  final owner = object as _CrossingState;
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

List<ScannableField> _collect$CrossingSystem(Object object) {
  final owner = object as _CrossingSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _gameDeclarationTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/game_declaration_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_BareState, _collect$BareState),
        DeclarationCollector(_FieldGame, _collect$FieldGame),
        DeclarationCollector(_FieldInputGame, _collect$FieldInputGame),
        DeclarationCollector(_MixedInputGame, _collect$MixedInputGame),
        DeclarationCollector(_Nested, _collect$Nested),
        DeclarationCollector(_NestingGame, _collect$NestingGame),
        DeclarationCollector(_InputOnly, _collect$InputOnly),
        DeclarationCollector(_GameBuildingSystem, _collect$GameBuildingSystem),
        DeclarationCollector(_SystemHostGame, _collect$SystemHostGame),
        DeclarationCollector(_SystemHostState, _collect$SystemHostState),
        DeclarationCollector(_NoTableGame, _collect$NoTableGame),
        DeclarationCollector(_NoTableState, _collect$NoTableState),
        DeclarationCollector(_CrossingGame, _collect$CrossingGame),
        DeclarationCollector(_CrossingState, _collect$CrossingState),
        DeclarationCollector(_CrossingSystem, _collect$CrossingSystem),
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
