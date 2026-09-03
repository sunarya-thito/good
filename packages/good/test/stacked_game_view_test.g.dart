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
part of 'stacked_game_view_test.dart';

List<ScannableField> _collect$ContactSystem(Object object) {
  final owner = object as _ContactSystem;
  return <ScannableField>[
    owner.contacts,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$StackedState(Object object) {
  final owner = object as _StackedState;
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

List<ScannableField> _collect$StackedGame(Object object) {
  object as _StackedGame;
  return const <ScannableField>[];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _stackedGameViewTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/stacked_game_view_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_ContactSystem, _collect$ContactSystem),
        DeclarationCollector(_StackedState, _collect$StackedState),
        DeclarationCollector(_StackedGame, _collect$StackedGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_stackedGameViewTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_stackedGameViewTestDeclarations],
);
