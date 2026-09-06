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
// A generic fixture also gets an `is` test. Nothing at run
// time can take the type arguments off a `Type`, so the
// literal in the table below never equals an instance's
// `runtimeType` - the test is what matches the two.
part of 'system_declaration_test.dart';

List<ScannableField> _collect$EarA(Object object) {
  object as _EarA;
  return const <ScannableField>[];
}

List<ScannableField> _collect$EarB(Object object) {
  object as _EarB;
  return const <ScannableField>[];
}

List<ScannableField> _collect$FieldSystem(Object object) {
  final owner = object as _FieldSystem;
  return <ScannableField>[
    owner.alpha,
    owner.beta,
  ];
}

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

List<ScannableField> _collect$FieldEventGame(Object object) {
  object as _FieldEventGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$FieldInputSystem(Object object) {
  final owner = object as _FieldInputSystem;
  return <ScannableField>[
    owner.fire,
    owner.alt,
    owner.unbound,
  ];
}

List<ScannableField> _collect$MixedInputSystem(Object object) {
  final owner = object as _MixedInputSystem;
  return <ScannableField>[
    owner.fire,
    owner.throttle,
  ];
}

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

List<ScannableField> _collect$FieldInputGame(Object object) {
  object as _FieldInputGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$MixedInputGame(Object object) {
  object as _MixedInputGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$Counting(Object object) {
  object as _Counting;
  return const <ScannableField>[];
}

List<ScannableField> _collect$MarkedSystem(Object object) {
  object as _MarkedSystem;
  return const <ScannableField>[];
}

List<ScannableField> _collect$SpareSystem(Object object) {
  object as _SpareSystem;
  return const <ScannableField>[];
}

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

List<ScannableField> _collect$MarkerGame(Object object) {
  object as _MarkerGame;
  return const <ScannableField>[];
}

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

List<ScannableField> _collect$TwinGame(Object object) {
  object as _TwinGame;
  return const <ScannableField>[];
}

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
        DeclarationCollector(_EarA, _collect$EarA),
        DeclarationCollector(_EarB, _collect$EarB),
        DeclarationCollector(_FieldSystem, _collect$FieldSystem),
        DeclarationCollector.generic(
          _EventState,
          _collect$EventState,
          _is$EventState,
        ),
        DeclarationCollector(_FieldEventGame, _collect$FieldEventGame),
        DeclarationCollector(_FieldInputSystem, _collect$FieldInputSystem),
        DeclarationCollector(_MixedInputSystem, _collect$MixedInputSystem),
        DeclarationCollector.generic(
          _InputState,
          _collect$InputState,
          _is$InputState,
        ),
        DeclarationCollector(_FieldInputGame, _collect$FieldInputGame),
        DeclarationCollector(_MixedInputGame, _collect$MixedInputGame),
        DeclarationCollector(_Counting, _collect$Counting),
        DeclarationCollector(_MarkedSystem, _collect$MarkedSystem),
        DeclarationCollector(_SpareSystem, _collect$SpareSystem),
        DeclarationCollector(_MarkerState, _collect$MarkerState),
        DeclarationCollector(_MarkerGame, _collect$MarkerGame),
        DeclarationCollector(_TwinState, _collect$TwinState),
        DeclarationCollector(_TwinGame, _collect$TwinGame),
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
