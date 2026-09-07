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
part of 'render_2d_test.dart';

List<ScannableField> _collect$Sprite(Object object) {
  final owner = object as _Sprite;
  return <ScannableField>[
    owner.quad,
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
  Child,
  Parent,
  Renderable2D,
];

List<ScannableField> _collect$Flat(Object object) {
  final owner = object as _Flat;
  return <ScannableField>[
    owner.quad,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Flat = <Type>[
  _Flat,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Renderable2D,
];

List<ScannableField> _collect$Invisible(Object object) {
  final owner = object as _Invisible;
  return <ScannableField>[
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Invisible = <Type>[
  _Invisible,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
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
  Child,
  Parent,
];

List<ScannableField> _collect$TwoSprite(Object object) {
  final owner = object as _TwoSprite;
  return <ScannableField>[
    owner.body,
    owner.hat,
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

const List<Type> _supertypes$TwoSprite = <Type>[
  _TwoSprite,
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

List<ScannableField> _collect$HalfHidden(Object object) {
  final owner = object as _HalfHidden;
  return <ScannableField>[
    owner.shown,
    owner.hidden,
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

const List<Type> _supertypes$HalfHidden = <Type>[
  _HalfHidden,
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

List<ScannableField> _collect$Stack(Object object) {
  final owner = object as _Stack;
  return <ScannableField>[
    owner.high,
    owner.low,
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

const List<Type> _supertypes$Stack = <Type>[
  _Stack,
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

List<ScannableField> _collect$TopLeft(Object object) {
  final owner = object as _TopLeft;
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

const List<Type> _supertypes$TopLeft = <Type>[
  _TopLeft,
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
  Child,
  Camera,
];

List<ScannableField> _collect$Textured(Object object) {
  final owner = object as _Textured;
  return <ScannableField>[
    owner.tile,
    owner.textured,
    owner.plain,
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

const List<Type> _supertypes$Textured = <Type>[
  _Textured,
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

List<ScannableField> _collect$Panel(Object object) {
  final owner = object as _Panel;
  return <ScannableField>[
    owner.skin,
    owner.frame,
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

const List<Type> _supertypes$Panel = <Type>[
  _Panel,
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

List<ScannableField> _collect$UnsizedPanel(Object object) {
  final owner = object as _UnsizedPanel;
  return <ScannableField>[
    owner.frame,
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

const List<Type> _supertypes$UnsizedPanel = <Type>[
  _UnsizedPanel,
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

List<ScannableField> _collect$PlainPanel(Object object) {
  final owner = object as _PlainPanel;
  return <ScannableField>[
    owner.frame,
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

const List<Type> _supertypes$PlainPanel = <Type>[
  _PlainPanel,
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

List<ScannableField> _collect$HorizontalBar(Object object) {
  final owner = object as _HorizontalBar;
  return <ScannableField>[
    owner.bar,
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

const List<Type> _supertypes$HorizontalBar = <Type>[
  _HorizontalBar,
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

List<ScannableField> _collect$SingleCellPanel(Object object) {
  final owner = object as _SingleCellPanel;
  return <ScannableField>[
    owner.frame,
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

const List<Type> _supertypes$SingleCellPanel = <Type>[
  _SingleCellPanel,
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

List<ScannableField> _collect$BorderedUntextured(Object object) {
  final owner = object as _BorderedUntextured;
  return <ScannableField>[
    owner.frame,
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

const List<Type> _supertypes$BorderedUntextured = <Type>[
  _BorderedUntextured,
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

List<ScannableField> _collect$PivotBody(Object object) {
  final owner = object as _PivotBody;
  return <ScannableField>[
    owner.quad,
    owner.box,
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

const List<Type> _supertypes$PivotBody = <Type>[
  _PivotBody,
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
];

List<ScannableField> _collect$SpriteScene(Object object) {
  final owner = object as _SpriteScene;
  return <ScannableField>[
    owner.sprite,
    owner.invisible,
    owner.group,
    owner.twoSprite,
    owner.halfHidden,
    owner.stack,
    owner.topLeft,
    owner.eye,
    owner.texturedPair,
    owner.panel,
    owner.unsizedPanel,
    owner.borderedUntextured,
    owner.flat,
    owner.pivotBody,
    owner.plainPanel,
    owner.horizontalBar,
    owner.singleCellPanel,
  ];
}

const List<Type> _supertypes$SpriteScene = <Type>[
  _SpriteScene,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$RenderState(Object object) {
  final owner = object as _RenderState;
  return <ScannableField>[
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

const List<Type> _supertypes$RenderState = <Type>[
  _RenderState,
  GameState2D,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  Renderer2DState,
];

List<ScannableField> _collect$RenderGame(Object object) {
  object as _RenderGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$RenderGame = <Type>[
  _RenderGame,
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
const GeneratedDeclarations _render2dTestDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/test/render_2d_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Sprite, _collect$Sprite, _supertypes$Sprite),
        DeclarationCollector(_Flat, _collect$Flat, _supertypes$Flat),
        DeclarationCollector(
          _Invisible,
          _collect$Invisible,
          _supertypes$Invisible,
        ),
        DeclarationCollector(_Group, _collect$Group, _supertypes$Group),
        DeclarationCollector(
          _TwoSprite,
          _collect$TwoSprite,
          _supertypes$TwoSprite,
        ),
        DeclarationCollector(
          _HalfHidden,
          _collect$HalfHidden,
          _supertypes$HalfHidden,
        ),
        DeclarationCollector(_Stack, _collect$Stack, _supertypes$Stack),
        DeclarationCollector(_TopLeft, _collect$TopLeft, _supertypes$TopLeft),
        DeclarationCollector(_Eye, _collect$Eye, _supertypes$Eye),
        DeclarationCollector(
          _Textured,
          _collect$Textured,
          _supertypes$Textured,
        ),
        DeclarationCollector(_Panel, _collect$Panel, _supertypes$Panel),
        DeclarationCollector(
          _UnsizedPanel,
          _collect$UnsizedPanel,
          _supertypes$UnsizedPanel,
        ),
        DeclarationCollector(
          _PlainPanel,
          _collect$PlainPanel,
          _supertypes$PlainPanel,
        ),
        DeclarationCollector(
          _HorizontalBar,
          _collect$HorizontalBar,
          _supertypes$HorizontalBar,
        ),
        DeclarationCollector(
          _SingleCellPanel,
          _collect$SingleCellPanel,
          _supertypes$SingleCellPanel,
        ),
        DeclarationCollector(
          _BorderedUntextured,
          _collect$BorderedUntextured,
          _supertypes$BorderedUntextured,
        ),
        DeclarationCollector(
          _PivotBody,
          _collect$PivotBody,
          _supertypes$PivotBody,
        ),
        DeclarationCollector(
          _SpriteScene,
          _collect$SpriteScene,
          _supertypes$SpriteScene,
        ),
        DeclarationCollector(
          _RenderState,
          _collect$RenderState,
          _supertypes$RenderState,
        ),
        DeclarationCollector(
          _RenderGame,
          _collect$RenderGame,
          _supertypes$RenderGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );

/// Installs [_render2dTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_render2dTestDeclarations],
);
