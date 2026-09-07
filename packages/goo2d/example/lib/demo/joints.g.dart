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
part of 'joints.dart';

List<ScannableField> _collect$Anchor(Object object) {
  final owner = object as Anchor;
  return <ScannableField>[
    owner.body,
    owner.box,
    owner.bodyHandle,
    owner.bodyType,
    owner.bodyLinearVelocityX,
    owner.bodyLinearVelocityY,
    owner.bodyAngularVelocity,
    owner.bodyGravityScale,
    owner.bodyLinearDamping,
    owner.bodyAngularDamping,
    owner.bodyFixedRotation,
    owner.bodyIsBullet,
    owner.bodySyncedX,
    owner.bodySyncedY,
    owner.bodySyncedAngle,
    owner.bodySyncedType,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Anchor = <Type>[
  Anchor,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Renderable2D,
  Collider2D,
  RigidBody2D,
];

List<ScannableField> _collect$Link(Object object) {
  final owner = object as Link;
  return <ScannableField>[
    owner.body,
    owner.box,
    owner.bodyHandle,
    owner.bodyType,
    owner.bodyLinearVelocityX,
    owner.bodyLinearVelocityY,
    owner.bodyAngularVelocity,
    owner.bodyGravityScale,
    owner.bodyLinearDamping,
    owner.bodyAngularDamping,
    owner.bodyFixedRotation,
    owner.bodyIsBullet,
    owner.bodySyncedX,
    owner.bodySyncedY,
    owner.bodySyncedAngle,
    owner.bodySyncedType,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Link = <Type>[
  Link,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Renderable2D,
  Collider2D,
  RigidBody2D,
];

List<ScannableField> _collect$Weight(Object object) {
  final owner = object as Weight;
  return <ScannableField>[
    owner.body,
    owner.box,
    owner.bodyHandle,
    owner.bodyType,
    owner.bodyLinearVelocityX,
    owner.bodyLinearVelocityY,
    owner.bodyAngularVelocity,
    owner.bodyGravityScale,
    owner.bodyLinearDamping,
    owner.bodyAngularDamping,
    owner.bodyFixedRotation,
    owner.bodyIsBullet,
    owner.bodySyncedX,
    owner.bodySyncedY,
    owner.bodySyncedAngle,
    owner.bodySyncedType,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Weight = <Type>[
  Weight,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Renderable2D,
  Collider2D,
  RigidBody2D,
];

List<ScannableField> _collect$Wheel(Object object) {
  final owner = object as Wheel;
  return <ScannableField>[
    owner.body,
    owner.spoke,
    owner.circle,
    owner.bodyHandle,
    owner.bodyType,
    owner.bodyLinearVelocityX,
    owner.bodyLinearVelocityY,
    owner.bodyAngularVelocity,
    owner.bodyGravityScale,
    owner.bodyLinearDamping,
    owner.bodyAngularDamping,
    owner.bodyFixedRotation,
    owner.bodyIsBullet,
    owner.bodySyncedX,
    owner.bodySyncedY,
    owner.bodySyncedAngle,
    owner.bodySyncedType,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Wheel = <Type>[
  Wheel,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Renderable2D,
  Collider2D,
  RigidBody2D,
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

List<ScannableField> _collect$JointScene(Object object) {
  final owner = object as JointScene;
  return <ScannableField>[
    owner.anchor,
    owner.link,
    owner.weight,
    owner.wheel,
    owner.eye,
  ];
}

const List<Type> _supertypes$JointScene = <Type>[
  JointScene,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$JointSystem(Object object) {
  object as JointSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$JointSystem = <Type>[
  JointSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$JointState(Object object) {
  final owner = object as JointState;
  return <ScannableField>[
    owner.fixedPhaseStart,
    owner.presentPhaseStart,
    owner.box2DPhysicsSystem,
    owner.jointSystem,
    owner.jointStats,
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

const List<Type> _supertypes$JointState = <Type>[
  JointState,
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

List<ScannableField> _collect$JointStats(Object object) {
  object as _JointStats;
  return const <ScannableField>[];
}

const List<Type> _supertypes$JointStats = <Type>[
  _JointStats,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  Tickable,
];

List<ScannableField> _collect$JointGame(Object object) {
  final owner = object as JointGame;
  return <ScannableField>[
    owner.intactJoints,
    owner.brokenJoints,
    owner.peakJointForce,
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

const List<Type> _supertypes$JointGame = <Type>[
  JointGame,
  DemoGame,
  Game2D,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
  Renderer2D,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the generated tables this library imports,
/// so installing this installs the collectors for the
/// engine classes a fixture is built on as well. Not this
/// package's own: either it has none, or one of these
/// already names it.
const GeneratedDeclarations _jointsDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/example/lib/demo/joints.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(Anchor, _collect$Anchor, _supertypes$Anchor),
        DeclarationCollector(Link, _collect$Link, _supertypes$Link),
        DeclarationCollector(Weight, _collect$Weight, _supertypes$Weight),
        DeclarationCollector(Wheel, _collect$Wheel, _supertypes$Wheel),
        DeclarationCollector(Eye, _collect$Eye, _supertypes$Eye),
        DeclarationCollector(
          JointScene,
          _collect$JointScene,
          _supertypes$JointScene,
        ),
        DeclarationCollector(
          JointSystem,
          _collect$JointSystem,
          _supertypes$JointSystem,
        ),
        DeclarationCollector(
          JointState,
          _collect$JointState,
          _supertypes$JointState,
        ),
        DeclarationCollector(
          _JointStats,
          _collect$JointStats,
          _supertypes$JointStats,
        ),
        DeclarationCollector(
          JointGame,
          _collect$JointGame,
          _supertypes$JointGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dPhysicsBox2dDeclarations,
      ],
    );
