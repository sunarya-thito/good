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
part of 'main.dart';

List<ScannableField> _collect$Breath(Object object) {
  final owner = object as Breath;
  return <ScannableField>[
    owner.scale,
    owner.pulse,
  ];
}

const List<Type> _supertypes$Breath = <Type>[
  Breath,
  TimelineStruct,
  Scannable,
];

List<ScannableField> _collect$Player(Object object) {
  final owner = object as Player;
  return <ScannableField>[
    owner.body,
    owner.visor,
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

const List<Type> _supertypes$Player = <Type>[
  Player,
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

List<ScannableField> _collect$Enemy(Object object) {
  final owner = object as Enemy;
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

const List<Type> _supertypes$Enemy = <Type>[
  Enemy,
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

List<ScannableField> _collect$Wingman(Object object) {
  final owner = object as Wingman;
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

const List<Type> _supertypes$Wingman = <Type>[
  Wingman,
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

List<ScannableField> _collect$MainScene(Object object) {
  final owner = object as MainScene;
  return <ScannableField>[
    owner.playerPrefab,
    owner.enemyPrefab,
    owner.wingmanPrefab,
    owner.eyePrefab,
  ];
}

const List<Type> _supertypes$MainScene = <Type>[
  MainScene,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$SpinSystem(Object object) {
  final owner = object as SpinSystem;
  return <ScannableField>[
    owner.spinnable,
  ];
}

const List<Type> _supertypes$SpinSystem = <Type>[
  SpinSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$SpawnEnemy(Object object) {
  final owner = object as SpawnEnemy;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$SpawnEnemy = <Type>[
  SpawnEnemy,
  ValueSupplier,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$MyGameState(Object object) {
  final owner = object as MyGameState;
  return <ScannableField>[
    owner.spinSystem,
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

const List<Type> _supertypes$MyGameState = <Type>[
  MyGameState,
  GameState2D,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  Renderer2DState,
];

List<ScannableField> _collect$MyAwesomeGame(Object object) {
  object as MyAwesomeGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$MyAwesomeGame = <Type>[
  MyAwesomeGame,
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
const GeneratedDeclarations _mainDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/example/lib/main.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(Breath, _collect$Breath, _supertypes$Breath),
        DeclarationCollector(Player, _collect$Player, _supertypes$Player),
        DeclarationCollector(Enemy, _collect$Enemy, _supertypes$Enemy),
        DeclarationCollector(Wingman, _collect$Wingman, _supertypes$Wingman),
        DeclarationCollector(Eye, _collect$Eye, _supertypes$Eye),
        DeclarationCollector(
          MainScene,
          _collect$MainScene,
          _supertypes$MainScene,
        ),
        DeclarationCollector(
          SpinSystem,
          _collect$SpinSystem,
          _supertypes$SpinSystem,
        ),
        DeclarationCollector(
          SpawnEnemy,
          _collect$SpawnEnemy,
          _supertypes$SpawnEnemy,
        ),
        DeclarationCollector(
          MyGameState,
          _collect$MyGameState,
          _supertypes$MyGameState,
        ),
        DeclarationCollector(
          MyAwesomeGame,
          _collect$MyAwesomeGame,
          _supertypes$MyAwesomeGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );

/// Installs [_mainDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_mainDeclarations],
);
