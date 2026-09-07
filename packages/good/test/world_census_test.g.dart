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
part of 'world_census_test.dart';

List<ScannableField> _collect$Rock(Object object) {
  final owner = object as _Rock;
  return <ScannableField>[
    owner.weight,
  ];
}

const List<Type> _supertypes$Rock = <Type>[
  _Rock,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Grounded,
];

List<ScannableField> _collect$Bird(Object object) {
  final owner = object as _Bird;
  return <ScannableField>[
    owner.span,
  ];
}

const List<Type> _supertypes$Bird = <Type>[
  _Bird,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Winged,
];

List<ScannableField> _collect$Habitat(Object object) {
  final owner = object as _Habitat;
  return <ScannableField>[
    owner.rock,
    owner.bird,
  ];
}

const List<Type> _supertypes$Habitat = <Type>[
  _Habitat,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$AlphaSystem(Object object) {
  object as _AlphaSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$AlphaSystem = <Type>[
  _AlphaSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$BetaSystem(Object object) {
  object as _BetaSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$BetaSystem = <Type>[
  _BetaSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$TakeCensus(Object object) {
  final owner = object as _TakeCensus;
  return <ScannableField>[
    owner.blob,
  ];
}

const List<Type> _supertypes$TakeCensus = <Type>[
  _TakeCensus,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$NeedsTick(Object object) {
  object as _NeedsTick;
  return const <ScannableField>[];
}

const List<Type> _supertypes$NeedsTick = <Type>[
  _NeedsTick,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$CensusState(Object object) {
  final owner = object as _CensusState;
  return <ScannableField>[
    owner.alphaSystem,
    owner.betaSystem,
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

const List<Type> _supertypes$CensusState = <Type>[
  _CensusState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$CensusGame(Object object) {
  object as _CensusGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$CensusGame = <Type>[
  _CensusGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

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

const List<Type> _supertypes$BareState = <Type>[
  _BareState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$BareGame(Object object) {
  object as _BareGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$BareGame = <Type>[
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _worldCensusTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/world_census_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Rock, _collect$Rock, _supertypes$Rock),
        DeclarationCollector(_Bird, _collect$Bird, _supertypes$Bird),
        DeclarationCollector(_Habitat, _collect$Habitat, _supertypes$Habitat),
        DeclarationCollector(
          _AlphaSystem,
          _collect$AlphaSystem,
          _supertypes$AlphaSystem,
        ),
        DeclarationCollector(
          _BetaSystem,
          _collect$BetaSystem,
          _supertypes$BetaSystem,
        ),
        DeclarationCollector(
          _TakeCensus,
          _collect$TakeCensus,
          _supertypes$TakeCensus,
        ),
        DeclarationCollector(
          _NeedsTick,
          _collect$NeedsTick,
          _supertypes$NeedsTick,
        ),
        DeclarationCollector(
          _CensusState,
          _collect$CensusState,
          _supertypes$CensusState,
        ),
        DeclarationCollector(
          _CensusGame,
          _collect$CensusGame,
          _supertypes$CensusGame,
        ),
        DeclarationCollector(
          _BareState,
          _collect$BareState,
          _supertypes$BareState,
        ),
        DeclarationCollector(
          _BareGame,
          _collect$BareGame,
          _supertypes$BareGame,
        ),
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
