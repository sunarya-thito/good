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
part of 'event_declaration_test.dart';

List<ScannableField> _collect$NotedSystem(Object object) {
  final owner = object as _NotedSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$UnitA(Object object) {
  final owner = object as _UnitA;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$UnitB(Object object) {
  final owner = object as _UnitB;
  return <ScannableField>[
    owner.own,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$NotedScene(Object object) {
  final owner = object as _NotedScene;
  return <ScannableField>[
    owner.a,
    owner.b,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$FieldState(Object object) {
  final owner = object as _FieldState;
  return <ScannableField>[
    owner.alpha,
    owner.beta,
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

List<ScannableField> _collect$HookState(Object object) {
  final owner = object as _HookState;
  return <ScannableField>[
    owner.alpha,
    owner.beta,
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

List<ScannableField> _collect$MixedState(Object object) {
  final owner = object as _MixedState;
  return <ScannableField>[
    owner.alpha,
    owner.beta,
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

List<ScannableField> _collect$FieldGame(Object object) {
  object as _FieldGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$HookGame(Object object) {
  object as _HookGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$MixedGame(Object object) {
  object as _MixedGame;
  return const <ScannableField>[];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _eventDeclarationTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/event_declaration_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_NotedSystem, _collect$NotedSystem),
        DeclarationCollector(_UnitA, _collect$UnitA),
        DeclarationCollector(_UnitB, _collect$UnitB),
        DeclarationCollector(_NotedScene, _collect$NotedScene),
        DeclarationCollector(_FieldState, _collect$FieldState),
        DeclarationCollector(_HookState, _collect$HookState),
        DeclarationCollector(_MixedState, _collect$MixedState),
        DeclarationCollector(_FieldGame, _collect$FieldGame),
        DeclarationCollector(_HookGame, _collect$HookGame),
        DeclarationCollector(_MixedGame, _collect$MixedGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_eventDeclarationTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_eventDeclarationTestDeclarations],
);
