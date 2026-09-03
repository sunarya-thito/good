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
part of 'system_declaration_test.dart';

List<ScannableField> _collect$EarA(Object object) {
  final owner = object as _EarA;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$EarB(Object object) {
  final owner = object as _EarB;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$FieldSystem(Object object) {
  final owner = object as _FieldSystem;
  return <ScannableField>[
    owner.alpha,
    owner.beta,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$HookSystem(Object object) {
  final owner = object as _HookSystem;
  return <ScannableField>[
    owner.alpha,
    owner.beta,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$MixedSystem(Object object) {
  final owner = object as _MixedSystem;
  return <ScannableField>[
    owner.alpha,
    owner.beta,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$EventState(Object object) {
  final owner = object as _EventState;
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

List<ScannableField> _collect$FieldEventGame(Object object) {
  object as _FieldEventGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$HookEventGame(Object object) {
  object as _HookEventGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$MixedEventGame(Object object) {
  object as _MixedEventGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$FieldInputSystem(Object object) {
  final owner = object as _FieldInputSystem;
  return <ScannableField>[
    owner.fire,
    owner.alt,
    owner.unbound,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$HookInputSystem(Object object) {
  final owner = object as _HookInputSystem;
  return <ScannableField>[
    owner.fire,
    owner.alt,
    owner.unbound,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$MixedInputSystem(Object object) {
  final owner = object as _MixedInputSystem;
  return <ScannableField>[
    owner.fire,
    owner.throttle,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$InputState(Object object) {
  final owner = object as _InputState;
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

List<ScannableField> _collect$FieldInputGame(Object object) {
  object as _FieldInputGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$HookInputGame(Object object) {
  object as _HookInputGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$MixedInputGame(Object object) {
  object as _MixedInputGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$LateSystem(Object object) {
  final owner = object as _LateSystem;
  return <ScannableField>[
    owner.lazyEvent,
    owner.lazyInput,
    owner.eagerEvent,
    owner.eagerInput,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$LateState(Object object) {
  final owner = object as _LateState;
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

List<ScannableField> _collect$LateGame(Object object) {
  object as _LateGame;
  return const <ScannableField>[];
}

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
        DeclarationCollector(_HookSystem, _collect$HookSystem),
        DeclarationCollector(_MixedSystem, _collect$MixedSystem),
        DeclarationCollector(_EventState, _collect$EventState),
        DeclarationCollector(_FieldEventGame, _collect$FieldEventGame),
        DeclarationCollector(_HookEventGame, _collect$HookEventGame),
        DeclarationCollector(_MixedEventGame, _collect$MixedEventGame),
        DeclarationCollector(_FieldInputSystem, _collect$FieldInputSystem),
        DeclarationCollector(_HookInputSystem, _collect$HookInputSystem),
        DeclarationCollector(_MixedInputSystem, _collect$MixedInputSystem),
        DeclarationCollector(_InputState, _collect$InputState),
        DeclarationCollector(_FieldInputGame, _collect$FieldInputGame),
        DeclarationCollector(_HookInputGame, _collect$HookInputGame),
        DeclarationCollector(_MixedInputGame, _collect$MixedInputGame),
        DeclarationCollector(_LateSystem, _collect$LateSystem),
        DeclarationCollector(_LateState, _collect$LateState),
        DeclarationCollector(_LateGame, _collect$LateGame),
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
