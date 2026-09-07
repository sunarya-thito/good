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
part of 'physics.dart';

List<ScannableField> _collect$Crate(Object object) {
  final owner = object as Crate;
  return <ScannableField>[
    owner.body,
    owner.box,
    owner.flash,
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

const List<Type> _supertypes$Crate = <Type>[
  Crate,
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

List<ScannableField> _collect$Ball(Object object) {
  final owner = object as Ball;
  return <ScannableField>[
    owner.body,
    owner.circle,
    owner.flash,
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

const List<Type> _supertypes$Ball = <Type>[
  Ball,
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

List<ScannableField> _collect$Ground(Object object) {
  final owner = object as Ground;
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

const List<Type> _supertypes$Ground = <Type>[
  Ground,
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

List<ScannableField> _collect$Wall(Object object) {
  final owner = object as Wall;
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

const List<Type> _supertypes$Wall = <Type>[
  Wall,
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

List<ScannableField> _collect$Sandbox(Object object) {
  final owner = object as Sandbox;
  return <ScannableField>[
    owner.crate,
    owner.ball,
    owner.ground,
    owner.wall,
    owner.eye,
  ];
}

const List<Type> _supertypes$Sandbox = <Type>[
  Sandbox,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$PhysicsPhaseStart(Object object) {
  object as _PhysicsPhaseStart;
  return const <ScannableField>[];
}

const List<Type> _supertypes$PhysicsPhaseStart = <Type>[
  _PhysicsPhaseStart,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$PhysicsPhaseEnd(Object object) {
  object as _PhysicsPhaseEnd;
  return const <ScannableField>[];
}

const List<Type> _supertypes$PhysicsPhaseEnd = <Type>[
  _PhysicsPhaseEnd,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$FlashSystem(Object object) {
  object as FlashSystem;
  return const <ScannableField>[];
}

const List<Type> _supertypes$FlashSystem = <Type>[
  FlashSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  CollisionListener,
];

List<ScannableField> _collect$SandboxSystem(Object object) {
  final owner = object as SandboxSystem;
  return <ScannableField>[
    owner.bodies,
  ];
}

const List<Type> _supertypes$SandboxSystem = <Type>[
  SandboxSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$PhysicsState(Object object) {
  final owner = object as PhysicsState;
  return <ScannableField>[
    owner.fixedPhaseStart,
    owner.presentPhaseStart,
    owner.physicsPhaseStart,
    owner.physics,
    owner.physicsPhaseEnd,
    owner.sandboxSystem,
    owner.flashSystem,
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

const List<Type> _supertypes$PhysicsState = <Type>[
  PhysicsState,
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

List<ScannableField> _collect$PhysicsGame(Object object) {
  final owner = object as PhysicsGame;
  return <ScannableField>[
    owner.physicsMicros,
    owner.solverThreads,
    owner.physicsBodies,
    owner.escapedBodies,
    owner.awakeBodies,
    owner.touchingPairs,
    owner.broadPhasePairs,
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

const List<Type> _supertypes$PhysicsGame = <Type>[
  PhysicsGame,
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
const GeneratedDeclarations _physicsDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/example/lib/demo/physics.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(Crate, _collect$Crate, _supertypes$Crate),
        DeclarationCollector(Ball, _collect$Ball, _supertypes$Ball),
        DeclarationCollector(Ground, _collect$Ground, _supertypes$Ground),
        DeclarationCollector(Wall, _collect$Wall, _supertypes$Wall),
        DeclarationCollector(Eye, _collect$Eye, _supertypes$Eye),
        DeclarationCollector(Sandbox, _collect$Sandbox, _supertypes$Sandbox),
        DeclarationCollector(
          _PhysicsPhaseStart,
          _collect$PhysicsPhaseStart,
          _supertypes$PhysicsPhaseStart,
        ),
        DeclarationCollector(
          _PhysicsPhaseEnd,
          _collect$PhysicsPhaseEnd,
          _supertypes$PhysicsPhaseEnd,
        ),
        DeclarationCollector(
          FlashSystem,
          _collect$FlashSystem,
          _supertypes$FlashSystem,
        ),
        DeclarationCollector(
          SandboxSystem,
          _collect$SandboxSystem,
          _supertypes$SandboxSystem,
        ),
        DeclarationCollector(
          PhysicsState,
          _collect$PhysicsState,
          _supertypes$PhysicsState,
        ),
        DeclarationCollector(
          PhysicsGame,
          _collect$PhysicsGame,
          _supertypes$PhysicsGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dPhysicsBox2dDeclarations,
      ],
    );
