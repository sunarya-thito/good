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
part of 'screen_transform_test.dart';

List<ScannableField> _collect$World(Object object) {
  final owner = object as _World;
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

const List<Type> _supertypes$World = <Type>[
  _World,
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

List<ScannableField> _collect$Rig(Object object) {
  final owner = object as _Rig;
  return <ScannableField>[
    owner.quad,
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

const List<Type> _supertypes$Rig = <Type>[
  _Rig,
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
  Renderable2D,
];

List<ScannableField> _collect$Pinned(Object object) {
  final owner = object as _Pinned;
  return <ScannableField>[
    owner.quad,
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

const List<Type> _supertypes$Pinned = <Type>[
  _Pinned,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  ScreenTransform2D,
  Child,
  Renderable2D,
];

List<ScannableField> _collect$Corner(Object object) {
  final owner = object as _Corner;
  return <ScannableField>[
    owner.quad,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Corner = <Type>[
  _Corner,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  ScreenTransform2D,
  Renderable2D,
];

List<ScannableField> _collect$Backdrop(Object object) {
  final owner = object as _Backdrop;
  return <ScannableField>[
    owner.fill,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Backdrop = <Type>[
  _Backdrop,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  ScreenTransform2D,
  Renderable2D,
];

List<ScannableField> _collect$Banner(Object object) {
  final owner = object as _Banner;
  return <ScannableField>[
    owner.quad,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Banner = <Type>[
  _Banner,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  ScreenTransform2D,
  Renderable2D,
];

List<ScannableField> _collect$Panel(Object object) {
  final owner = object as _Panel;
  return <ScannableField>[
    owner.frame,
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
  ScreenTransform2D,
  Renderable2D,
];

List<ScannableField> _collect$Spinner(Object object) {
  final owner = object as _Spinner;
  return <ScannableField>[
    owner.quad,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Spinner = <Type>[
  _Spinner,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  ScreenTransform2D,
  Renderable2D,
];

List<ScannableField> _collect$Label(Object object) {
  final owner = object as _Label;
  return <ScannableField>[
    owner.atlas,
    owner.textCodeUnits,
    owner.textLength,
    owner.textColor,
    owner.textCellWidth,
    owner.textCellHeight,
    owner.textLetterSpacing,
    owner.textZIndex,
    owner.textVisible,
    owner.textFilter,
    owner.textPivotFractionX,
    owner.textPivotFractionY,
    owner.textPivotOffsetX,
    owner.textPivotOffsetY,
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

const List<Type> _supertypes$Label = <Type>[
  _Label,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  WorldTransform2D,
  Text2D,
];

List<ScannableField> _collect$Stage(Object object) {
  final owner = object as _Stage;
  return <ScannableField>[
    owner.world,
    owner.rig,
    owner.eye,
    owner.pinned,
    owner.corner,
    owner.backdrop,
    owner.banner,
    owner.panel,
    owner.spinner,
    owner.label,
  ];
}

const List<Type> _supertypes$Stage = <Type>[
  _Stage,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$StageState(Object object) {
  final owner = object as _StageState;
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

const List<Type> _supertypes$StageState = <Type>[
  _StageState,
  GameState2D,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  Renderer2DState,
];

List<ScannableField> _collect$StageGame(Object object) {
  object as _StageGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$StageGame = <Type>[
  _StageGame,
  Game2D,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
  Renderer2D,
];

List<ScannableField> _collect$TightGame(Object object) {
  object as _TightGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$TightGame = <Type>[
  _TightGame,
  _StageGame,
  Game2D,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
  Renderer2D,
];

List<ScannableField> _collect$Clash(Object object) {
  final owner = object as _Clash;
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

const List<Type> _supertypes$Clash = <Type>[
  _Clash,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  WorldTransform2D,
  ScreenTransform2D,
  Renderable2D,
];

List<ScannableField> _collect$LabelClash(Object object) {
  final owner = object as _LabelClash;
  return <ScannableField>[
    owner.textCodeUnits,
    owner.textLength,
    owner.textColor,
    owner.textCellWidth,
    owner.textCellHeight,
    owner.textLetterSpacing,
    owner.textZIndex,
    owner.textVisible,
    owner.textFilter,
    owner.textPivotFractionX,
    owner.textPivotFractionY,
    owner.textPivotOffsetX,
    owner.textPivotOffsetY,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$LabelClash = <Type>[
  _LabelClash,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  ScreenTransform2D,
  Text2D,
];

List<ScannableField> _collect$ClashScene(Object object) {
  final owner = object as _ClashScene;
  return <ScannableField>[
    owner.clash,
  ];
}

const List<Type> _supertypes$ClashScene = <Type>[
  _ClashScene,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$LabelClashScene(Object object) {
  final owner = object as _LabelClashScene;
  return <ScannableField>[
    owner.clash,
  ];
}

const List<Type> _supertypes$LabelClashScene = <Type>[
  _LabelClashScene,
  SceneStruct,
  Coroutines,
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _screenTransformTestDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/test/screen_transform_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_World, _collect$World, _supertypes$World),
        DeclarationCollector(_Eye, _collect$Eye, _supertypes$Eye),
        DeclarationCollector(_Rig, _collect$Rig, _supertypes$Rig),
        DeclarationCollector(_Pinned, _collect$Pinned, _supertypes$Pinned),
        DeclarationCollector(_Corner, _collect$Corner, _supertypes$Corner),
        DeclarationCollector(
          _Backdrop,
          _collect$Backdrop,
          _supertypes$Backdrop,
        ),
        DeclarationCollector(_Banner, _collect$Banner, _supertypes$Banner),
        DeclarationCollector(_Panel, _collect$Panel, _supertypes$Panel),
        DeclarationCollector(_Spinner, _collect$Spinner, _supertypes$Spinner),
        DeclarationCollector(_Label, _collect$Label, _supertypes$Label),
        DeclarationCollector(_Stage, _collect$Stage, _supertypes$Stage),
        DeclarationCollector(
          _StageState,
          _collect$StageState,
          _supertypes$StageState,
        ),
        DeclarationCollector(
          _StageGame,
          _collect$StageGame,
          _supertypes$StageGame,
        ),
        DeclarationCollector(
          _TightGame,
          _collect$TightGame,
          _supertypes$TightGame,
        ),
        DeclarationCollector(_Clash, _collect$Clash, _supertypes$Clash),
        DeclarationCollector(
          _LabelClash,
          _collect$LabelClash,
          _supertypes$LabelClash,
        ),
        DeclarationCollector(
          _ClashScene,
          _collect$ClashScene,
          _supertypes$ClashScene,
        ),
        DeclarationCollector(
          _LabelClashScene,
          _collect$LabelClashScene,
          _supertypes$LabelClashScene,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );

/// Installs [_screenTransformTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_screenTransformTestDeclarations],
);
