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
part of 'event_lifecycle_test.dart';

List<ScannableField> _collect$Unit(Object object) {
  final owner = object as _Unit;
  return <ScannableField>[
    owner.mark,
  ];
}

List<ScannableField> _collect$Watcher(Object object) {
  object as _Watcher;
  return const <ScannableField>[];
}

List<ScannableField> _collect$Bystander(Object object) {
  object as _Bystander;
  return const <ScannableField>[];
}

List<ScannableField> _collect$Observing(Object object) {
  object as _Observing;
  return const <ScannableField>[];
}

List<ScannableField> _collect$Level(Object object) {
  final owner = object as _Level;
  return <ScannableField>[
    owner.unit,
  ];
}

List<ScannableField> _collect$Observer(Object object) {
  object as _Observer;
  return const <ScannableField>[];
}

List<ScannableField> _collect$NosyScene(Object object) {
  final owner = object as _NosyScene;
  return <ScannableField>[
    owner.unit,
  ];
}

List<ScannableField> _collect$Tracked(Object object) {
  final owner = object as _Tracked;
  return <ScannableField>[
    owner.mark,
  ];
}

List<ScannableField> _collect$Indexed(Object object) {
  final owner = object as _Indexed;
  return <ScannableField>[
    owner.mark,
  ];
}

List<ScannableField> _collect$Census(Object object) {
  object as _Census;
  return const <ScannableField>[];
}

List<ScannableField> _collect$TrackedScene(Object object) {
  final owner = object as _TrackedScene;
  return <ScannableField>[
    owner.tracked,
    owner.indexed,
  ];
}

List<ScannableField> _collect$LifecycleState(Object object) {
  final owner = object as _LifecycleState;
  return <ScannableField>[
    owner.watcher,
    owner.census,
    owner.bystander,
    owner.observing,
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

List<ScannableField> _collect$LifecycleGame(Object object) {
  object as _LifecycleGame;
  return const <ScannableField>[];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _eventLifecycleTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/event_lifecycle_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Unit, _collect$Unit),
        DeclarationCollector(_Watcher, _collect$Watcher),
        DeclarationCollector(_Bystander, _collect$Bystander),
        DeclarationCollector(_Observing, _collect$Observing),
        DeclarationCollector(_Level, _collect$Level),
        DeclarationCollector(_Observer, _collect$Observer),
        DeclarationCollector(_NosyScene, _collect$NosyScene),
        DeclarationCollector(_Tracked, _collect$Tracked),
        DeclarationCollector(_Indexed, _collect$Indexed),
        DeclarationCollector(_Census, _collect$Census),
        DeclarationCollector(_TrackedScene, _collect$TrackedScene),
        DeclarationCollector(_LifecycleState, _collect$LifecycleState),
        DeclarationCollector(_LifecycleGame, _collect$LifecycleGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_eventLifecycleTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_eventLifecycleTestDeclarations],
);
