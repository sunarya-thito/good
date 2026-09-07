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
part of 'world_transform_3d_test.dart';

List<ScannableField> _collect$Node(Object object) {
  final owner = object as _Node;
  return <ScannableField>[
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.worldX,
    owner.worldY,
    owner.worldZ,
    owner.worldScaleX,
    owner.worldScaleY,
    owner.worldScaleZ,
    owner.worldRotationX,
    owner.worldRotationY,
    owner.worldRotationZ,
    owner.worldRotationW,
    owner.worldCachedOffsetX,
    owner.worldCachedOffsetY,
    owner.worldCachedOffsetZ,
    owner.worldCachedRotationX,
    owner.worldCachedRotationY,
    owner.worldCachedRotationZ,
    owner.worldCachedRotationW,
    owner.worldCachedScaleX,
    owner.worldCachedScaleY,
    owner.worldCachedScaleZ,
    owner.worldCachedParent,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformOffsetZ,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformScaleZ,
    owner.transformRotationX,
    owner.transformRotationY,
    owner.transformRotationZ,
    owner.transformRotationW,
  ];
}

const List<Type> _supertypes$Node = <Type>[
  _Node,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform3D,
  WorldTransform3D,
  Child,
  Parent,
];

List<ScannableField> _collect$Leaf(Object object) {
  final owner = object as _Leaf;
  return <ScannableField>[
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.worldX,
    owner.worldY,
    owner.worldZ,
    owner.worldScaleX,
    owner.worldScaleY,
    owner.worldScaleZ,
    owner.worldRotationX,
    owner.worldRotationY,
    owner.worldRotationZ,
    owner.worldRotationW,
    owner.worldCachedOffsetX,
    owner.worldCachedOffsetY,
    owner.worldCachedOffsetZ,
    owner.worldCachedRotationX,
    owner.worldCachedRotationY,
    owner.worldCachedRotationZ,
    owner.worldCachedRotationW,
    owner.worldCachedScaleX,
    owner.worldCachedScaleY,
    owner.worldCachedScaleZ,
    owner.worldCachedParent,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformOffsetZ,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformScaleZ,
    owner.transformRotationX,
    owner.transformRotationY,
    owner.transformRotationZ,
    owner.transformRotationW,
  ];
}

const List<Type> _supertypes$Leaf = <Type>[
  _Leaf,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform3D,
  WorldTransform3D,
  Child,
];

List<ScannableField> _collect$Group(Object object) {
  final owner = object as _Group;
  return <ScannableField>[
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformOffsetZ,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformScaleZ,
    owner.transformRotationX,
    owner.transformRotationY,
    owner.transformRotationZ,
    owner.transformRotationW,
  ];
}

const List<Type> _supertypes$Group = <Type>[
  _Group,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform3D,
  Child,
  Parent,
];

List<ScannableField> _collect$Prop(Object object) {
  final owner = object as _Prop;
  return <ScannableField>[
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformOffsetZ,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformScaleZ,
    owner.transformRotationX,
    owner.transformRotationY,
    owner.transformRotationZ,
    owner.transformRotationW,
  ];
}

const List<Type> _supertypes$Prop = <Type>[
  _Prop,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform3D,
];

List<ScannableField> _collect$Scene(Object object) {
  final owner = object as _Scene;
  return <ScannableField>[
    owner.node,
    owner.leaf,
    owner.group,
    owner.prop,
  ];
}

const List<Type> _supertypes$Scene = <Type>[
  _Scene,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$Spawner(Object object) {
  object as _Spawner;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Spawner = <Type>[
  _Spawner,
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
    owner.worldTransform3DSystem,
    owner.spawner2,
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
const GeneratedDeclarations _worldTransform3dTestDeclarations =
    GeneratedDeclarations(
      package: 'goo3d/test/world_transform_3d_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Node, _collect$Node, _supertypes$Node),
        DeclarationCollector(_Leaf, _collect$Leaf, _supertypes$Leaf),
        DeclarationCollector(_Group, _collect$Group, _supertypes$Group),
        DeclarationCollector(_Prop, _collect$Prop, _supertypes$Prop),
        DeclarationCollector(_Scene, _collect$Scene, _supertypes$Scene),
        DeclarationCollector(_Spawner, _collect$Spawner, _supertypes$Spawner),
        DeclarationCollector(
          _GameState,
          _collect$GameState,
          _supertypes$GameState,
        ),
        DeclarationCollector(_Game, _collect$Game, _supertypes$Game),
      ],
      dependencies: <GeneratedDeclarations>[
        goo3dDeclarations,
      ],
    );

/// Installs [_worldTransform3dTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_worldTransform3dTestDeclarations],
);
