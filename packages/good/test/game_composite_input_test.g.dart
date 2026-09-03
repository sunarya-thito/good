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
part of 'game_composite_input_test.dart';

List<ScannableField> _collect$CompositeSystem(Object object) {
  final owner = object as _CompositeSystem;
  return <ScannableField>[
    owner.keyboards,
    owner.mixed,
    owner.attack,
    owner.throttle,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$CompositeGameState(Object object) {
  final owner = object as _CompositeGameState;
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

List<ScannableField> _collect$CompositeGame(Object object) {
  object as _CompositeGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$RestoreSystem(Object object) {
  final owner = object as _RestoreSystem;
  return <ScannableField>[
    owner.attack,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$RestoreGameState(Object object) {
  final owner = object as _RestoreGameState;
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

List<ScannableField> _collect$RestoreGame(Object object) {
  object as _RestoreGame;
  return const <ScannableField>[];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _gameCompositeInputTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/game_composite_input_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_CompositeSystem, _collect$CompositeSystem),
        DeclarationCollector(_CompositeGameState, _collect$CompositeGameState),
        DeclarationCollector(_CompositeGame, _collect$CompositeGame),
        DeclarationCollector(_RestoreSystem, _collect$RestoreSystem),
        DeclarationCollector(_RestoreGameState, _collect$RestoreGameState),
        DeclarationCollector(_RestoreGame, _collect$RestoreGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_gameCompositeInputTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_gameCompositeInputTestDeclarations],
);
