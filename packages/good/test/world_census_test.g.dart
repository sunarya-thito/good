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
part of 'world_census_test.dart';

List<ScannableField> _collect$Rock(Object object) {
  final owner = object as _Rock;
  return <ScannableField>[
    owner.weight,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Bird(Object object) {
  final owner = object as _Bird;
  return <ScannableField>[
    owner.span,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Habitat(Object object) {
  final owner = object as _Habitat;
  return <ScannableField>[
    owner.rock,
    owner.bird,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$AlphaSystem(Object object) {
  final owner = object as _AlphaSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$BetaSystem(Object object) {
  final owner = object as _BetaSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$TakeCensus(Object object) {
  final owner = object as _TakeCensus;
  return <ScannableField>[
    owner.blob,
  ];
}

List<ScannableField> _collect$NeedsTick(Object object) {
  object as _NeedsTick;
  return const <ScannableField>[];
}

List<ScannableField> _collect$CensusState(Object object) {
  final owner = object as _CensusState;
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

List<ScannableField> _collect$CensusGame(Object object) {
  object as _CensusGame;
  return const <ScannableField>[];
}

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

List<ScannableField> _collect$BareGame(Object object) {
  object as _BareGame;
  return const <ScannableField>[];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _worldCensusTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/world_census_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Rock, _collect$Rock),
        DeclarationCollector(_Bird, _collect$Bird),
        DeclarationCollector(_Habitat, _collect$Habitat),
        DeclarationCollector(_AlphaSystem, _collect$AlphaSystem),
        DeclarationCollector(_BetaSystem, _collect$BetaSystem),
        DeclarationCollector(_TakeCensus, _collect$TakeCensus),
        DeclarationCollector(_NeedsTick, _collect$NeedsTick),
        DeclarationCollector(_CensusState, _collect$CensusState),
        DeclarationCollector(_CensusGame, _collect$CensusGame),
        DeclarationCollector(_BareState, _collect$BareState),
        DeclarationCollector(_BareGame, _collect$BareGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_worldCensusTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_worldCensusTestDeclarations],
);
