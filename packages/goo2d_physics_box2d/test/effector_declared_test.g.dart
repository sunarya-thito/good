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
part of 'effector_declared_test.dart';

List<ScannableField> _collect$Zone(Object object) {
  final owner = object as _Zone;
  return <ScannableField>[
    owner.region,
    owner.wind,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Zone = <Type>[
  _Zone,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Collider2D,
  Effector2D,
];

List<ScannableField> _collect$Pool(Object object) {
  final owner = object as _Pool;
  return <ScannableField>[
    owner.region,
    owner.water,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Pool = <Type>[
  _Pool,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Collider2D,
  Effector2D,
];

List<ScannableField> _collect$Box(Object object) {
  final owner = object as _Box;
  return <ScannableField>[
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

const List<Type> _supertypes$Box = <Type>[
  _Box,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Collider2D,
  RigidBody2D,
];

List<ScannableField> _collect$Loose(Object object) {
  final owner = object as _Loose;
  return <ScannableField>[
    owner.wind,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Loose = <Type>[
  _Loose,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Collider2D,
  Effector2D,
];

List<ScannableField> _collect$LooseScene(Object object) {
  final owner = object as _LooseScene;
  return <ScannableField>[
    owner.zone,
  ];
}

const List<Type> _supertypes$LooseScene = <Type>[
  _LooseScene,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$Scene(Object object) {
  final owner = object as _Scene;
  return <ScannableField>[
    owner.box,
    owner.zone,
    owner.waterZone,
  ];
}

const List<Type> _supertypes$Scene = <Type>[
  _Scene,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$Setup(Object object) {
  object as _Setup;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Setup = <Type>[
  _Setup,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$OneShot(Object object) {
  object as _OneShot;
  return const <ScannableField>[];
}

const List<Type> _supertypes$OneShot = <Type>[
  _OneShot,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$GameState(Object object) {
  final owner = object as _GameState;
  return <ScannableField>[
    owner.setup,
    owner.oneShot,
    owner.physics,
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

const List<Type> _supertypes$GameState = <Type>[
  _GameState,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
];

List<ScannableField> _collect$Game(Object object) {
  object as _Game;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Game = <Type>[
  _Game,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _effectorDeclaredTestDeclarations =
    GeneratedDeclarations(
      package: 'goo2d_physics_box2d/test/effector_declared_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Zone, _collect$Zone, _supertypes$Zone),
        DeclarationCollector(_Pool, _collect$Pool, _supertypes$Pool),
        DeclarationCollector(_Box, _collect$Box, _supertypes$Box),
        DeclarationCollector(_Loose, _collect$Loose, _supertypes$Loose),
        DeclarationCollector(
          _LooseScene,
          _collect$LooseScene,
          _supertypes$LooseScene,
        ),
        DeclarationCollector(_Scene, _collect$Scene, _supertypes$Scene),
        DeclarationCollector(_Setup, _collect$Setup, _supertypes$Setup),
        DeclarationCollector(_OneShot, _collect$OneShot, _supertypes$OneShot),
        DeclarationCollector(
          _GameState,
          _collect$GameState,
          _supertypes$GameState,
        ),
        DeclarationCollector(_Game, _collect$Game, _supertypes$Game),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dPhysicsBox2dDeclarations,
      ],
    );

/// Installs [_effectorDeclaredTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_effectorDeclaredTestDeclarations],
);
