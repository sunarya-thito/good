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
part of 'scene_graph.dart';

List<ScannableField> _collect$Critter(Object object) {
  final owner = object as Critter;
  return <ScannableField>[
    owner.body,
    owner.angle,
    owner.radius,
    owner.spin,
    owner.life,
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
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
  ];
}

const List<Type> _supertypes$Critter = <Type>[
  Critter,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  WorldTransform2D,
  Child,
  Parent,
  Renderable2D,
];

List<ScannableField> _collect$Limb(Object object) {
  final owner = object as Limb;
  return <ScannableField>[
    owner.body,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
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
  ];
}

const List<Type> _supertypes$Limb = <Type>[
  Limb,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  WorldTransform2D,
  Child,
  Renderable2D,
];

List<ScannableField> _collect$Hub(Object object) {
  final owner = object as Hub;
  return <ScannableField>[
    owner.parentFirstChild,
    owner.parentLastChild,
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
  ];
}

const List<Type> _supertypes$Hub = <Type>[
  Hub,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  WorldTransform2D,
  Parent,
];

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
  ];
}

const List<Type> _supertypes$Eye = <Type>[
  Eye,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  WorldTransform2D,
  Camera,
];

List<ScannableField> _collect$Swarm(Object object) {
  final owner = object as Swarm;
  return <ScannableField>[
    owner.critter,
    owner.limb,
    owner.hub,
    owner.eye,
  ];
}

const List<Type> _supertypes$Swarm = <Type>[
  Swarm,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$CritterSystem(Object object) {
  final owner = object as CritterSystem;
  return <ScannableField>[
    owner.critters,
    owner.hubs,
  ];
}

const List<Type> _supertypes$CritterSystem = <Type>[
  CritterSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$SceneGraphState(Object object) {
  final owner = object as SceneGraphState;
  return <ScannableField>[
    owner.fixedPhaseStart,
    owner.presentPhaseStart,
    owner.critterSystem,
    owner.fixedPhaseEnd,
    owner.renderPhaseStart,
    owner.renderPhaseEnd,
    owner.demoStats,
    owner.worldTransform,
    owner.renderer,
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

const List<Type> _supertypes$SceneGraphState = <Type>[
  SceneGraphState,
  DemoState,
  GameState2D,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  Renderer2DState,
];

List<ScannableField> _collect$SceneGraphGame(Object object) {
  final owner = object as SceneGraphGame;
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

const List<Type> _supertypes$SceneGraphGame = <Type>[
  SceneGraphGame,
  DemoGame,
  Game2D,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
  Renderer2D,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _sceneGraphDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/example/lib/demo/scene_graph.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(Critter, _collect$Critter, _supertypes$Critter),
        DeclarationCollector(Limb, _collect$Limb, _supertypes$Limb),
        DeclarationCollector(Hub, _collect$Hub, _supertypes$Hub),
        DeclarationCollector(Eye, _collect$Eye, _supertypes$Eye),
        DeclarationCollector(Swarm, _collect$Swarm, _supertypes$Swarm),
        DeclarationCollector(
          CritterSystem,
          _collect$CritterSystem,
          _supertypes$CritterSystem,
        ),
        DeclarationCollector(
          SceneGraphState,
          _collect$SceneGraphState,
          _supertypes$SceneGraphState,
        ),
        DeclarationCollector(
          SceneGraphGame,
          _collect$SceneGraphGame,
          _supertypes$SceneGraphGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );
