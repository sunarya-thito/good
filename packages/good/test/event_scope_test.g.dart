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
part of 'event_scope_test.dart';

List<ScannableField> _collect$PingSystem(Object object) {
  final owner = object as _PingSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$DeafSystem(Object object) {
  final owner = object as _DeafSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$PingUnit(Object object) {
  final owner = object as _PingUnit;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$SelfishUnit(Object object) {
  final owner = object as _SelfishUnit;
  return <ScannableField>[
    owner.ping,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$PingScene(Object object) {
  final owner = object as _PingScene;
  return <ScannableField>[
    owner.unit,
    owner.selfish,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$PingState(Object object) {
  final owner = object as _PingState;
  return <ScannableField>[
    owner.ping,
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

List<ScannableField> _collect$PingGame(Object object) {
  object as _PingGame;
  return const <ScannableField>[];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _eventScopeTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/event_scope_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_PingSystem, _collect$PingSystem),
        DeclarationCollector(_DeafSystem, _collect$DeafSystem),
        DeclarationCollector(_PingUnit, _collect$PingUnit),
        DeclarationCollector(_SelfishUnit, _collect$SelfishUnit),
        DeclarationCollector(_PingScene, _collect$PingScene),
        DeclarationCollector(_PingState, _collect$PingState),
        DeclarationCollector(_PingGame, _collect$PingGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_eventScopeTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_eventScopeTestDeclarations],
);
