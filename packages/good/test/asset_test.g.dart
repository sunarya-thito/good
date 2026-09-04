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
part of 'asset_test.dart';

List<ScannableField> _collect$Prop(Object object) {
  final owner = object as _Prop;
  return <ScannableField>[
    owner.texture,
    owner.spriteField,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Bare(Object object) {
  final owner = object as _Bare;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$PropScene(Object object) {
  final owner = object as _PropScene;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Ambient(Object object) {
  final owner = object as _Ambient;
  return <ScannableField>[
    owner.texture,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$AmbientTwin(Object object) {
  final owner = object as _AmbientTwin;
  return <ScannableField>[
    owner.texture,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$AmbientParent(Object object) {
  final owner = object as _AmbientParent;
  return <ScannableField>[
    owner.child,
    owner.texture,
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$AmbientChild(Object object) {
  final owner = object as _AmbientChild;
  return <ScannableField>[
    owner.texture,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$AmbientScene(Object object) {
  final owner = object as _AmbientScene;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$SceneFieldAmbient(Object object) {
  final owner = object as _SceneFieldAmbient;
  return <ScannableField>[
    owner.texture,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$BareScene(Object object) {
  final owner = object as _BareScene;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$GameSceneStub(Object object) {
  final owner = object as GameSceneStub;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$DiffGame(Object object) {
  object as _DiffGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$DiffState(Object object) {
  final owner = object as _DiffState;
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

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _assetTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/asset_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Prop, _collect$Prop),
        DeclarationCollector(_Bare, _collect$Bare),
        DeclarationCollector(_PropScene, _collect$PropScene),
        DeclarationCollector(_Ambient, _collect$Ambient),
        DeclarationCollector(_AmbientTwin, _collect$AmbientTwin),
        DeclarationCollector(_AmbientParent, _collect$AmbientParent),
        DeclarationCollector(_AmbientChild, _collect$AmbientChild),
        DeclarationCollector(_AmbientScene, _collect$AmbientScene),
        DeclarationCollector(_SceneFieldAmbient, _collect$SceneFieldAmbient),
        DeclarationCollector(_BareScene, _collect$BareScene),
        DeclarationCollector(GameSceneStub, _collect$GameSceneStub),
        DeclarationCollector(_DiffGame, _collect$DiffGame),
        DeclarationCollector(_DiffState, _collect$DiffState),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_assetTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_assetTestDeclarations],
);
