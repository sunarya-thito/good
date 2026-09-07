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
part of 'describe_scenes_test.dart';

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

List<ScannableField> _collect$Prop(Object object) {
  final owner = object as _Prop;
  return <ScannableField>[
    owner.tag,
  ];
}

const List<Type> _supertypes$Prop = <Type>[
  _Prop,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Unmarked,
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

List<ScannableField> _collect$Menu(Object object) {
  object as _Menu;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Menu = <Type>[
  _Menu,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$Mixed(Object object) {
  final owner = object as _Mixed;
  return <ScannableField>[
    owner.unit,
    owner.prop,
  ];
}

const List<Type> _supertypes$Mixed = <Type>[
  _Mixed,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$SecondCensusSystem(Object object) {
  final owner = object as _SecondCensusSystem;
  return <ScannableField>[
    owner.marked,
  ];
}

const List<Type> _supertypes$SecondCensusSystem = <Type>[
  _SecondCensusSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$SecondCensusState(Object object) {
  final owner = object as _SecondCensusState;
  return <ScannableField>[
    owner.secondCensusSystem,
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

const List<Type> _supertypes$SecondCensusState = <Type>[
  _SecondCensusState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$SecondCensusGame(Object object) {
  object as _SecondCensusGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$SecondCensusGame = <Type>[
  _SecondCensusGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$Bare(Object object) {
  object as _Bare;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Bare = <Type>[
  _Bare,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$CensusSystem(Object object) {
  final owner = object as _CensusSystem;
  return <ScannableField>[
    owner.query,
  ];
}

const List<Type> _supertypes$CensusSystem = <Type>[
  _CensusSystem,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$DeclaringState(Object object) {
  final owner = object as _DeclaringState;
  return <ScannableField>[
    owner.censusSystem,
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

const List<Type> _supertypes$DeclaringState = <Type>[
  _DeclaringState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$DeclaringGame(Object object) {
  object as _DeclaringGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$DeclaringGame = <Type>[
  _DeclaringGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$DoubleDeclaringGame(Object object) {
  object as _DoubleDeclaringGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$DoubleDeclaringGame = <Type>[
  _DoubleDeclaringGame,
  _DeclaringGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _describeScenesTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/describe_scenes_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Unit, _collect$Unit, _supertypes$Unit),
        DeclarationCollector(_Prop, _collect$Prop, _supertypes$Prop),
        DeclarationCollector(_Level, _collect$Level, _supertypes$Level),
        DeclarationCollector(_Menu, _collect$Menu, _supertypes$Menu),
        DeclarationCollector(_Mixed, _collect$Mixed, _supertypes$Mixed),
        DeclarationCollector(
          _SecondCensusSystem,
          _collect$SecondCensusSystem,
          _supertypes$SecondCensusSystem,
        ),
        DeclarationCollector(
          _SecondCensusState,
          _collect$SecondCensusState,
          _supertypes$SecondCensusState,
        ),
        DeclarationCollector(
          _SecondCensusGame,
          _collect$SecondCensusGame,
          _supertypes$SecondCensusGame,
        ),
        DeclarationCollector(_Bare, _collect$Bare, _supertypes$Bare),
        DeclarationCollector(
          _CensusSystem,
          _collect$CensusSystem,
          _supertypes$CensusSystem,
        ),
        DeclarationCollector(
          _DeclaringState,
          _collect$DeclaringState,
          _supertypes$DeclaringState,
        ),
        DeclarationCollector(
          _DeclaringGame,
          _collect$DeclaringGame,
          _supertypes$DeclaringGame,
        ),
        DeclarationCollector(
          _DoubleDeclaringGame,
          _collect$DoubleDeclaringGame,
          _supertypes$DoubleDeclaringGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_describeScenesTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_describeScenesTestDeclarations],
);
