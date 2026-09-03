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
part of 'describe_scenes_test.dart';

List<ScannableField> _collect$Unit(Object object) {
  final owner = object as _Unit;
  return <ScannableField>[
    owner.mark,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Prop(Object object) {
  final owner = object as _Prop;
  return <ScannableField>[
    owner.tag,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Level(Object object) {
  final owner = object as _Level;
  return <ScannableField>[
    owner.unit,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Menu(Object object) {
  final owner = object as _Menu;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Mixed(Object object) {
  final owner = object as _Mixed;
  return <ScannableField>[
    owner.unit,
    owner.prop,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$HookCensusSystem(Object object) {
  final owner = object as _HookCensusSystem;
  return <ScannableField>[
    owner.marked,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$HookState(Object object) {
  final owner = object as _HookState;
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

List<ScannableField> _collect$HookGame(Object object) {
  object as _HookGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$Bare(Object object) {
  final owner = object as _Bare;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$CensusSystem(Object object) {
  final owner = object as _CensusSystem;
  return <ScannableField>[
    owner.query,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$DeclaringState(Object object) {
  final owner = object as _DeclaringState;
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

List<ScannableField> _collect$DeclaringGame(Object object) {
  object as _DeclaringGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$DoubleDeclaringGame(Object object) {
  object as _DoubleDeclaringGame;
  return const <ScannableField>[];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _describeScenesTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/describe_scenes_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Unit, _collect$Unit),
        DeclarationCollector(_Prop, _collect$Prop),
        DeclarationCollector(_Level, _collect$Level),
        DeclarationCollector(_Menu, _collect$Menu),
        DeclarationCollector(_Mixed, _collect$Mixed),
        DeclarationCollector(_HookCensusSystem, _collect$HookCensusSystem),
        DeclarationCollector(_HookState, _collect$HookState),
        DeclarationCollector(_HookGame, _collect$HookGame),
        DeclarationCollector(_Bare, _collect$Bare),
        DeclarationCollector(_CensusSystem, _collect$CensusSystem),
        DeclarationCollector(_DeclaringState, _collect$DeclaringState),
        DeclarationCollector(_DeclaringGame, _collect$DeclaringGame),
        DeclarationCollector(_DoubleDeclaringGame, _collect$DoubleDeclaringGame),
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
