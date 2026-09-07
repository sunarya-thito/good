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
part of 'component_bits_test.dart';

List<ScannableField> _collect$Player(Object object) {
  final owner = object as _Player;
  return <ScannableField>[
    owner.betaValue,
    owner.alphaValue,
  ];
}

const List<Type> _supertypes$Player = <Type>[
  _Player,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Alpha,
  _Beta,
];

List<ScannableField> _collect$Prop(Object object) {
  final owner = object as _Prop;
  return <ScannableField>[
    owner.alphaValue,
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
  _Alpha,
];

List<ScannableField> _collect$Level(Object object) {
  object as _Level;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Level = <Type>[
  _Level,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$SeededState(Object object) {
  final owner = object as _SeededState;
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

const List<Type> _supertypes$SeededState = <Type>[
  _SeededState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$SeededGame(Object object) {
  object as _SeededGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$SeededGame = <Type>[
  _SeededGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$UnseededGame(Object object) {
  object as _UnseededGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$UnseededGame = <Type>[
  _UnseededGame,
  _SeededGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _componentBitsTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/component_bits_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Player, _collect$Player, _supertypes$Player),
        DeclarationCollector(_Prop, _collect$Prop, _supertypes$Prop),
        DeclarationCollector(_Level, _collect$Level, _supertypes$Level),
        DeclarationCollector(
          _SeededState,
          _collect$SeededState,
          _supertypes$SeededState,
        ),
        DeclarationCollector(
          _SeededGame,
          _collect$SeededGame,
          _supertypes$SeededGame,
        ),
        DeclarationCollector(
          _UnseededGame,
          _collect$UnseededGame,
          _supertypes$UnseededGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_componentBitsTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_componentBitsTestDeclarations],
);
