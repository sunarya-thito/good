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
part of 'multi_view_test.dart';

List<ScannableField> _collect$Sprite(Object object) {
  final owner = object as _Sprite;
  return <ScannableField>[
    owner.quad,
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

const List<Type> _supertypes$Sprite = <Type>[
  _Sprite,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  WorldTransform2D,
  Renderable2D,
];

List<ScannableField> _collect$Eye(Object object) {
  final owner = object as _Eye;
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
  _Eye,
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

List<ScannableField> _collect$Target(Object object) {
  final owner = object as _Target;
  return <ScannableField>[
    owner.quad,
    owner.hitArea,
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

const List<Type> _supertypes$Target = <Type>[
  _Target,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  WorldTransform2D,
  Renderable2D,
  Collider2D,
  PointerReceiver,
  PointerListener,
  HoverReceiver,
  HoverListener,
];

List<ScannableField> _collect$Level(Object object) {
  final owner = object as _Level;
  return <ScannableField>[
    owner.sprite,
    owner.eye,
    owner.target,
  ];
}

const List<Type> _supertypes$Level = <Type>[
  _Level,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$Overlay(Object object) {
  final owner = object as _Overlay;
  return <ScannableField>[
    owner.sprite,
    owner.eye,
    owner.target,
  ];
}

const List<Type> _supertypes$Overlay = <Type>[
  _Overlay,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$MultiState(Object object) {
  final owner = object as _MultiState;
  return <ScannableField>[
    owner.pointerPickingSystem,
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

const List<Type> _supertypes$MultiState = <Type>[
  _MultiState,
  GameState2D,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  Renderer2DState,
];

List<ScannableField> _collect$MultiGame(Object object) {
  object as _MultiGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$MultiGame = <Type>[
  _MultiGame,
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
const GeneratedDeclarations _multiViewTestDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/test/multi_view_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Sprite, _collect$Sprite, _supertypes$Sprite),
        DeclarationCollector(_Eye, _collect$Eye, _supertypes$Eye),
        DeclarationCollector(_Target, _collect$Target, _supertypes$Target),
        DeclarationCollector(_Level, _collect$Level, _supertypes$Level),
        DeclarationCollector(_Overlay, _collect$Overlay, _supertypes$Overlay),
        DeclarationCollector(
          _MultiState,
          _collect$MultiState,
          _supertypes$MultiState,
        ),
        DeclarationCollector(
          _MultiGame,
          _collect$MultiGame,
          _supertypes$MultiGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );

/// Installs [_multiViewTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_multiViewTestDeclarations],
);
