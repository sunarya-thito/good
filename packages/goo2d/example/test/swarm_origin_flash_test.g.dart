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
part of 'swarm_origin_flash_test.dart';

List<ScannableField> _collect$OriginProbe(Object object) {
  final owner = object as _OriginProbe;
  return <ScannableField>[
    owner._renderables,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$ProbedState(Object object) {
  final owner = object as _ProbedState;
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

List<ScannableField> _collect$ProbedGame(Object object) {
  final owner = object as _ProbedGame;
  return <ScannableField>[
    owner.caseMicros,
    owner.systemMicros,
    owner.bestSystemMicros,
    owner.stepMicros,
    owner.presentMicros,
    owner.advanceMicros,
    owner.intervalMicros,
    owner.renderMicros,
    owner.stepsPerAdvance,
    owner.spawnedCount,
    owner.spritesDrawn,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _swarmOriginFlashTestDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/example/test/swarm_origin_flash_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_OriginProbe, _collect$OriginProbe),
        DeclarationCollector(_ProbedState, _collect$ProbedState),
        DeclarationCollector(_ProbedGame, _collect$ProbedGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );

/// Installs [_swarmOriginFlashTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_swarmOriginFlashTestDeclarations],
);
