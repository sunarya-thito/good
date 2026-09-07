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
//
// A generic fixture also gets an `is` test. Nothing at run
// time can take the type arguments off a `Type`, so the
// literal in the table below never equals an instance's
// `runtimeType` - the test is what matches the two.
part of 'system_declaration_test.dart';

List<ScannableField> _collect$EarA(Object object) {
  object as _EarA;
  return const <ScannableField>[];
}

const List<Type> _supertypes$EarA = <Type>[
  _EarA,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  _Noted,
];

List<ScannableField> _collect$EarB(Object object) {
  object as _EarB;
  return const <ScannableField>[];
}

const List<Type> _supertypes$EarB = <Type>[
  _EarB,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  _Noted,
];

List<ScannableField> _collect$FieldSystem(Object object) {
  final owner = object as _FieldSystem;
  return <ScannableField>[
    owner.alpha,
    owner.beta,
  ];
}

const List<Type> _supertypes$FieldSystem = <Type>[
  _FieldSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  _Noted,
];

List<ScannableField> _collect$EventState(Object object) {
  final owner = object as _EventState;
  return <ScannableField>[
    owner.source,
    owner.earA,
    owner.earB,
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

const List<Type> _supertypes$EventState = <Type>[
  _EventState,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$FieldEventGame(Object object) {
  object as _FieldEventGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$FieldEventGame = <Type>[
  _FieldEventGame,
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$FieldInputSystem(Object object) {
  final owner = object as _FieldInputSystem;
  return <ScannableField>[
    owner.fire,
    owner.alt,
    owner.unbound,
  ];
}

const List<Type> _supertypes$FieldInputSystem = <Type>[
  _FieldInputSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$MixedInputSystem(Object object) {
  final owner = object as _MixedInputSystem;
  return <ScannableField>[
    owner.fire,
    owner.throttle,
  ];
}

const List<Type> _supertypes$MixedInputSystem = <Type>[
  _MixedInputSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
];

List<ScannableField> _collect$InputState(Object object) {
  final owner = object as _InputState;
  return <ScannableField>[
    owner.source,
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

const List<Type> _supertypes$InputState = <Type>[
  _InputState,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$FieldInputGame(Object object) {
  object as _FieldInputGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$FieldInputGame = <Type>[
  _FieldInputGame,
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$MixedInputGame(Object object) {
  object as _MixedInputGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$MixedInputGame = <Type>[
  _MixedInputGame,
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$Counting(Object object) {
  object as _Counting;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Counting = <Type>[
  _Counting,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$MarkedSystem(Object object) {
  object as _MarkedSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$MarkedSystem = <Type>[
  _MarkedSystem,
  _Counting,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$SpareSystem(Object object) {
  object as _SpareSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$SpareSystem = <Type>[
  _SpareSystem,
  _Counting,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$MarkerState(Object object) {
  final owner = object as _MarkerState;
  return <ScannableField>[
    owner.marked,
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

const List<Type> _supertypes$MarkerState = <Type>[
  _MarkerState,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$MarkerGame(Object object) {
  object as _MarkerGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$MarkerGame = <Type>[
  _MarkerGame,
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$TwinState(Object object) {
  final owner = object as _TwinState;
  return <ScannableField>[
    owner.first,
    owner.second,
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

const List<Type> _supertypes$TwinState = <Type>[
  _TwinState,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$TwinGame(Object object) {
  object as _TwinGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$TwinGame = <Type>[
  _TwinGame,
  _BareGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Whether an object is a _EventState, whatever its type arguments are.
bool _is$EventState(Object object) => object is _EventState;

/// Whether an object is a _InputState, whatever its type arguments are.
bool _is$InputState(Object object) => object is _InputState;

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _systemDeclarationTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/system_declaration_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_EarA, _collect$EarA, _supertypes$EarA),
        DeclarationCollector(_EarB, _collect$EarB, _supertypes$EarB),
        DeclarationCollector(
          _FieldSystem,
          _collect$FieldSystem,
          _supertypes$FieldSystem,
        ),
        DeclarationCollector.generic(
          _EventState,
          _collect$EventState,
          _is$EventState,
          _supertypes$EventState,
        ),
        DeclarationCollector(
          _FieldEventGame,
          _collect$FieldEventGame,
          _supertypes$FieldEventGame,
        ),
        DeclarationCollector(
          _FieldInputSystem,
          _collect$FieldInputSystem,
          _supertypes$FieldInputSystem,
        ),
        DeclarationCollector(
          _MixedInputSystem,
          _collect$MixedInputSystem,
          _supertypes$MixedInputSystem,
        ),
        DeclarationCollector.generic(
          _InputState,
          _collect$InputState,
          _is$InputState,
          _supertypes$InputState,
        ),
        DeclarationCollector(
          _FieldInputGame,
          _collect$FieldInputGame,
          _supertypes$FieldInputGame,
        ),
        DeclarationCollector(
          _MixedInputGame,
          _collect$MixedInputGame,
          _supertypes$MixedInputGame,
        ),
        DeclarationCollector(
          _Counting,
          _collect$Counting,
          _supertypes$Counting,
        ),
        DeclarationCollector(
          _MarkedSystem,
          _collect$MarkedSystem,
          _supertypes$MarkedSystem,
        ),
        DeclarationCollector(
          _SpareSystem,
          _collect$SpareSystem,
          _supertypes$SpareSystem,
        ),
        DeclarationCollector(
          _MarkerState,
          _collect$MarkerState,
          _supertypes$MarkerState,
        ),
        DeclarationCollector(
          _MarkerGame,
          _collect$MarkerGame,
          _supertypes$MarkerGame,
        ),
        DeclarationCollector(
          _TwinState,
          _collect$TwinState,
          _supertypes$TwinState,
        ),
        DeclarationCollector(
          _TwinGame,
          _collect$TwinGame,
          _supertypes$TwinGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_systemDeclarationTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_systemDeclarationTestDeclarations],
);
