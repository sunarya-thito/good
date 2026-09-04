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
part of 'particles.dart';

List<ScannableField> _collect$SetAblations(Object object) {
  final owner = object as SetAblations;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$Mote(Object object) {
  final owner = object as Mote;
  return <ScannableField>[
    owner.texture,
    owner.angle,
    owner.radius,
    owner.spin,
    owner.life,
    owner.lifespan,
    owner.baseSize,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Eye(Object object) {
  final owner = object as Eye;
  return <ScannableField>[
    owner.cameraZoom,
    owner.cameraView,
    owner.worldX,
    owner.worldY,
    owner.worldScaleX,
    owner.worldScaleY,
    owner.worldRotation,
    owner.worldCachedOffsetX,
    owner.worldCachedOffsetY,
    owner.worldCachedRotation,
    owner.worldCachedScaleX,
    owner.worldCachedScaleY,
    owner.worldCachedParent,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Galaxy(Object object) {
  final owner = object as Galaxy;
  return <ScannableField>[
    owner.mote,
    owner.eye,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$SwirlSystem(Object object) {
  final owner = object as SwirlSystem;
  return <ScannableField>[
    owner.motes,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$ParticlesState(Object object) {
  final owner = object as ParticlesState;
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

List<ScannableField> _collect$ParticlesGame(Object object) {
  final owner = object as ParticlesGame;
  return <ScannableField>[
    owner.caseMicros,
    owner.systemMicros,
    owner.bestSystemMicros,
    owner.stepMicros,
    owner.presentMicros,
    owner.advanceMicros,
    owner.intervalMicros,
    owner.renderMicros,
    owner.stepsPerAdvance,
    owner.spawnedCount,
    owner.spritesDrawn,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _particlesDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/example/lib/demo/particles.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(SetAblations, _collect$SetAblations),
        DeclarationCollector(Mote, _collect$Mote),
        DeclarationCollector(Eye, _collect$Eye),
        DeclarationCollector(Galaxy, _collect$Galaxy),
        DeclarationCollector(SwirlSystem, _collect$SwirlSystem),
        DeclarationCollector(ParticlesState, _collect$ParticlesState),
        DeclarationCollector(ParticlesGame, _collect$ParticlesGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );
