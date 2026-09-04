// Screen-space entities (#132) - `ScreenTransform2D`, an entity placed against
// the view instead of against the camera.
//
// The assertions are on the published batch, in draw order. A count cannot
// tell "the backdrop drew" from "the backdrop drew at the wrong size, in the
// wrong layer, scaled by a zoom it was supposed to ignore", and each of those
// is a way this can be wrong while every counter reads right.
//
// Numbers are equalities and not tolerances: the view sizes, fractions,
// widths and offsets here are all exact in binary, so a `closeTo` would only
// hide which digit moved. The main view is 800x600 and the minimap 400x200.

import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

part 'screen_transform_test.g.dart';

/// The live run under test. A file-level binding, as in the other renderer
/// suites: the bring-up helper returns the `Game` while the tests also need
/// the run, and one inline run per isolate means one binding is enough.
late Game run;

const int _worldColor = 0xFF102030;
const int _pinnedColor = 0xFF00FF00;
const int _cornerColor = 0xFF0000FF;
const int _backdropColor = 0xFFFF0000;
const int _panelColor = 0xFF00FFFF;
const int _spinColor = 0xFFFFFF00;
const int _labelColor = 0xFFFF00FF;
const int _rigColor = 0xFF808080;

const double _mainWidth = 800;
const double _mainHeight = 600;
const double _miniWidth = 400;
const double _miniHeight = 200;

const Duration _step = Duration(milliseconds: 10);

/// A 2x1 PNG. Nothing here reads a pixel - a nine-slice cuts fractions of the
/// source and a glyph cell comes out of the grid by division - so the image
/// has to exist and no more.
final Uint8List _png2x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR42mP4z8AAQv8BD/kD'
  '/Zh51wAAAAAASUVORK5CYII=',
);

final TextureKey _textureKey = TextureKey(
  MemorySource(_png2x1, name: 'panel.png'),
);

/// An ordinary world sprite, and the control for most of what follows: it is
/// what moves when the camera moves and grows when the camera zooms, so a
/// screen-space quad that does neither is measured against something in the
/// same frame that could have.
class _World extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    quad = descriptor.has(width: 10, height: 10, color: _worldColor);
  }
}

class _Eye extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

/// Something to hang a screen-space entity off: a world entity that moves and
/// turns, and can be a parent.
class _Rig extends EntityStruct
    with Transform2D, WorldTransform2D, Parent, Renderable2D {
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    quad = descriptor.has(width: 10, height: 10, color: _rigColor);
  }
}

/// The plain screen-space case: every getter left at its default, so the
/// anchor is the middle of the view and both sizes are view units.
class _Pinned extends EntityStruct
    with Transform2D, ScreenTransform2D, Child, Renderable2D {
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    quad = descriptor.has(width: 20, height: 10, color: _pinnedColor);
  }
}

/// Anchored to the bottom-right and pivoted on its own top-left corner, so
/// the four corners below are the anchor arithmetic and nothing else.
class _Corner extends EntityStruct
    with Transform2D, ScreenTransform2D, Renderable2D {
  static const double width = 8;
  static const double height = 4;

  late final Sprite quad;

  @override
  final screenAnchor = ScreenAnchor.bottomRight;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    quad = descriptor.has(
      width: width,
      height: height,
      color: _cornerColor,
      pivot: RelativeOffset2D.zero,
    );
  }
}

/// A viewport-filling backdrop: both axes sized as a fraction, `1` on each,
/// centred, behind every world sprite.
class _Backdrop extends EntityStruct
    with Transform2D, ScreenTransform2D, Renderable2D {
  late final Sprite fill;

  @override
  final screenLayer = ScreenLayer.behind;

  @override
  final screenWidthAxis = ScreenAxis.fraction;

  @override
  final screenHeightAxis = ScreenAxis.fraction;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    fill = descriptor.has(width: 1, height: 1, color: _backdropColor);
  }
}

/// Half the view wide and a fixed twenty units tall - the non-uniform case
/// two independent axes exist for.
class _Banner extends EntityStruct
    with Transform2D, ScreenTransform2D, Renderable2D {
  late final Sprite quad;

  @override
  final screenAnchor = ScreenAnchor.topLeft;

  @override
  final screenWidthAxis = ScreenAxis.fraction;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    quad = descriptor.has(
      width: 0.5,
      height: 20,
      color: _pinnedColor,
      pivot: RelativeOffset2D.zero,
    );
  }
}

/// A nine-sliced screen-space panel. The sliced path reads the row again in
/// the write pass instead of using the corners the fill pass parked, so it is
/// the one place a sprite can be filled in one space and drawn in another.
class _Panel extends EntityStruct
    with Transform2D, ScreenTransform2D, Renderable2D {
  late final TextureAsset skin;
  late final Sprite frame;

  @override
  final screenAnchor = ScreenAnchor.topLeft;

  @override
  final screenWidthAxis = ScreenAxis.fraction;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    skin = descriptor.has(_textureKey);
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    frame = descriptor.has(
      texture: skin,
      // Half the view wide, so the write pass has to know this sprite was
      // filled against the view: read as view units it would be half a pixel
      // and collapse to nothing.
      width: 0.5,
      height: 40,
      color: _panelColor,
      pivot: RelativeOffset2D.zero,
      nineSliceBorder: const NineSliceBorder.all(4, sourceSize: 16),
    );
  }
}

/// A screen-space entity that turns. Its own rotation has to reach the quad,
/// or "a screen-space entity inherits no rotation" would also be true of an
/// implementation that threw every rotation away.
class _Spinner extends EntityStruct
    with Transform2D, ScreenTransform2D, Renderable2D {
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    quad = descriptor.has(width: 10, height: 10, color: _spinColor);
  }
}

/// A world-space label sorted above every sprite in the world, so the layer
/// split is measured against a label that would otherwise draw last.
class _Label extends EntityStruct with Transform2D, WorldTransform2D, Text2D {
  late final TextureAsset atlas;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    atlas = descriptor.has(_textureKey);
  }

  @override
  BitmapFont get textFont =>
      BitmapFont(texture: atlas, columns: 16, rows: 6, glyphCount: 95);

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    textCodeUnits.length = 8;
    textCellWidth.initialValue = 8;
    textCellHeight.initialValue = 8;
    textColor.initialValue = _labelColor;
    textZIndex.initialValue = 9000;
  }
}

class _Stage extends SceneStruct {
  @override
  void onSceneMounted(Scene scene) => handle = scene;

  late Scene handle;

  @sub
  final world = _World();
  @sub
  final rig = _Rig();
  @sub
  final eye = _Eye();
  @sub
  final pinned = _Pinned();
  @sub
  final corner = _Corner();
  @sub
  final backdrop = _Backdrop();
  @sub
  final banner = _Banner();
  @sub
  final panel = _Panel();
  @sub
  final spinner = _Spinner();
  @sub
  final label = _Label();
}

class _StageState extends GameState2D<_StageGame> {
  late final _Stage stage;

  @override
  void onMounted() {
    stage = _Stage();
    loadScene(stage);
  }
}

class _StageGame extends Game2D {
  @override
  int get pageSize => 8192;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  /// `defaultCamera` is address 0 and comes from `Renderer2D`; this is the
  /// second view, and calling super is what keeps that ordering.
  late final CameraView mini;

  @override
  void describeCameras(CameraDescriptor descriptor) {
    super.describeCameras(descriptor);
    mini = descriptor.has();
  }

  @override
  GameState2D<_StageGame> createState() => _StageState();
}

/// The same stage with room for one record, so the trim has to choose between
/// a screen-space element and a wall of world sprites.
class _TightGame extends _StageGame {
  @override
  int get maxSpritesPerTick => 1;
}

class _Quad {
  _Quad(this.x, this.y, this.color);

  final List<double> x;
  final List<double> y;
  final int color;

  double get left {
    var v = x[0];
    for (final n in x) {
      if (n < v) v = n;
    }
    return v;
  }

  double get right {
    var v = x[0];
    for (final n in x) {
      if (n > v) v = n;
    }
    return v;
  }

  double get top {
    var v = y[0];
    for (final n in y) {
      if (n < v) v = n;
    }
    return v;
  }

  double get bottom {
    var v = y[0];
    for (final n in y) {
      if (n > v) v = n;
    }
    return v;
  }

  @override
  String toString() =>
      'Quad(x: $x, y: $y, color: 0x${color.toRadixString(16)})';
}

/// The quads the newest frame for [view] carries, in draw order.
List<_Quad> _quads(CameraView view) {
  final buffer = run.state.getSystem<GameRenderer2D>().framesFor(view).buffer;
  final slot = buffer.beginRead();
  if (slot == null) return const <_Quad>[];
  final used = buffer.readUsedBytes;
  final batch = ByteData.sublistView(slot.asTypedList(used));
  final quads = <_Quad>[];
  var offset = DrawData2D.batchHeaderBytes;
  final count = const DrawSpriteData2D().itemCount(used);
  for (var i = 0; i < count; i++) {
    quads.add(
      _Quad(
        <double>[
          for (var c = 0; c < 4; c++)
            batch.getFloat32(offset + c * 8, Endian.little),
        ],
        <double>[
          for (var c = 0; c < 4; c++)
            batch.getFloat32(offset + c * 8 + 4, Endian.little),
        ],
        batch.getUint32(offset + 32, Endian.little),
      ),
    );
    offset += DrawSpriteData2D.strideBytes;
  }
  return quads;
}

_Quad _only(List<_Quad> quads, int color) {
  final matches = quads.where((q) => q.color == color).toList();
  expect(
    matches,
    hasLength(1),
    reason: 'looking for one 0x${color.toRadixString(16)} in $quads',
  );
  return matches.single;
}

List<int> _order(CameraView view) => _quads(view).map((q) => q.color).toList();

Future<_StageGame> _start([_StageGame Function()? create]) async {
  final game = await Game.startInline(create ?? _StageGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  // No widget lays a test's views out, so the sizes the projection centres on
  // and the screen pass anchors against are stated here.
  game.defaultCamera.setViewport(_mainWidth, _mainHeight);
  game.mini.setViewport(_miniWidth, _miniHeight);
  return game;
}

_Stage _stage() => (run.state as _StageState).stage;

/// Adds a camera to [view] at ([x], [y]) with [zoom]. Written straight into
/// the fresh row, whose page has never published - the same path every other
/// default here takes.
Entity _eye(CameraView view, {double x = 0, double y = 0, double zoom = 1}) {
  final stage = _stage();
  final eye = stage.handle.addEntity(stage.eye);
  stage.eye.cameraView[eye] = view;
  stage.eye.transformOffsetX[eye] = x;
  stage.eye.transformOffsetY[eye] = y;
  stage.eye.cameraZoom[eye] = zoom;
  return eye;
}

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('placement', () {
    test(
      'the anchor is a point on the view, not a point in the world',
      () async {
        final game = await _start();
        final stage = _stage();
        _eye(game.defaultCamera);
        final e = stage.handle.addEntity(stage.corner);
        // Neither offset matches the sprite's own 8x4, so a confusion
        // between an offset and a size would move a corner this can see.
        stage.corner.transformOffsetX[e] = -30;
        stage.corner.transformOffsetY[e] = 10;
        run.state.advance(_step);

        final quad = _only(_quads(game.defaultCamera), _cornerColor);
        // bottomRight is (viewWidth, viewHeight) in view space, and the
        // offsets are view units with +y up - so -8 goes left and +4 goes
        // up, putting the origin at (770, 590). The pivot is the sprite's
        // own top-left corner, so it runs right and down from there.
        expect(quad.left, _mainWidth - 30);
        expect(quad.right, _mainWidth - 30 + _Corner.width);
        expect(quad.top, _mainHeight - 10);
        expect(quad.bottom, _mainHeight - 10 + _Corner.height);
      },
    );

    test('the default anchor is the middle of the view', () async {
      final game = await _start();
      final stage = _stage();
      _eye(game.defaultCamera);
      stage.handle.addEntity(stage.pinned);
      run.state.advance(_step);

      final quad = _only(_quads(game.defaultCamera), _pinnedColor);
      expect(quad.left, 390);
      expect(quad.right, 410);
      expect(quad.top, 295);
      expect(quad.bottom, 305);
    });

    test('a screen-space entity is drawn once, not once per space', () async {
      final game = await _start();
      final stage = _stage();
      _eye(game.defaultCamera);
      stage.handle.addEntity(stage.pinned);
      run.state.advance(_step);

      expect(
        _quads(game.defaultCamera),
        hasLength(1),
        reason:
            'the world query forbids ScreenTransform2D, so this entity is in '
            'exactly one of the two passes',
      );
    });

    test('an unsized view collapses every anchor onto its top-left', () async {
      final game = await _start();
      game.defaultCamera.setViewport(0, 0);
      final stage = _stage();
      _eye(game.defaultCamera);
      final e = stage.handle.addEntity(stage.corner);
      stage.corner.transformOffsetX[e] = 12;
      stage.corner.transformOffsetY[e] = -6;
      run.state.advance(_step);

      final quad = _only(_quads(game.defaultCamera), _cornerColor);
      expect(quad.left, 12, reason: 'a view of no width has no right edge');
      expect(quad.top, 6, reason: '+y is up, so -6 is six down the view');
    });
  });

  group('the camera is out', () {
    test(
      'zoom scales a world sprite and does not touch a screen one',
      () async {
        final game = await _start();
        final stage = _stage();
        final eye = _eye(game.defaultCamera);
        stage.handle.addEntity(stage.world);
        stage.handle.addEntity(stage.pinned);

        run.state.advance(_step);
        // One read per published frame. `beginRead` takes the frame, so a
        // second call in the same tick sees nothing at all and every
        // expectation under it would be answering a different question.
        final atOne = _quads(game.defaultCamera);
        final worldAtOne = _only(atOne, _worldColor);
        final screenAtOne = _only(atOne, _pinnedColor);
        expect(worldAtOne.right - worldAtOne.left, 10);

        stage.pool.beginTick();
        stage.eye.cameraZoom[eye] = 3;
        stage.pool.commitTick();
        run.state.advance(_step);
        final atThree = _quads(game.defaultCamera);
        final worldAtThree = _only(atThree, _worldColor);
        final screenAtThree = _only(atThree, _pinnedColor);

        // The control. Without it the four assertions below would pass on a
        // frame where the zoom change never reached anything.
        expect(
          worldAtThree.right - worldAtThree.left,
          30,
          reason: 'zoom is live in this frame',
        );
        expect(screenAtThree.left, screenAtOne.left);
        expect(screenAtThree.right, screenAtOne.right);
        expect(screenAtThree.top, screenAtOne.top);
        expect(screenAtThree.bottom, screenAtOne.bottom);
      },
    );

    test('zoom does not change what a fraction of the view means', () async {
      final game = await _start();
      final stage = _stage();
      final eye = _eye(game.defaultCamera, zoom: 4);
      stage.handle.addEntity(stage.backdrop);
      stage.handle.addEntity(stage.world);
      run.state.advance(_step);

      final quads = _quads(game.defaultCamera);
      final world = _only(quads, _worldColor);
      expect(
        world.right - world.left,
        40,
        reason: 'zoom 4 really did reach this frame',
      );
      final quad = _only(quads, _backdropColor);
      expect(quad.left, 0);
      expect(quad.right, _mainWidth);
      expect(quad.top, 0);
      expect(quad.bottom, _mainHeight);
      expect(stage.eye.cameraZoom[eye], 4);
    });

    test(
      'moving the camera moves a world sprite and not a screen one',
      () async {
        final game = await _start();
        final stage = _stage();
        final eye = _eye(game.defaultCamera);
        stage.handle.addEntity(stage.world);
        stage.handle.addEntity(stage.pinned);

        run.state.advance(_step);
        final before = _quads(game.defaultCamera);
        final worldBefore = _only(before, _worldColor);
        final screenBefore = _only(before, _pinnedColor);

        stage.pool.beginTick();
        stage.eye.transformOffsetX[eye] = 100;
        stage.eye.transformOffsetY[eye] = 50;
        stage.pool.commitTick();
        run.state.advance(_step);
        final after = _quads(game.defaultCamera);
        final worldAfter = _only(after, _worldColor);
        final screenAfter = _only(after, _pinnedColor);

        expect(
          worldAfter.left,
          worldBefore.left - 100,
          reason: 'the camera moved, and the world moved with it',
        );
        expect(worldAfter.top, worldBefore.top + 50);
        expect(screenAfter.left, screenBefore.left);
        expect(screenAfter.top, screenBefore.top);
      },
    );
  });

  group('rotation', () {
    test('a screen-space entity turns on its own rotation', () async {
      final game = await _start();
      final stage = _stage();
      _eye(game.defaultCamera);
      final e = stage.handle.addEntity(stage.spinner);
      stage.spinner.transformRotation[e] = 1.5707963267948966;
      run.state.advance(_step);

      final quad = _only(_quads(game.defaultCamera), _spinColor);
      // Unrotated, a 10x10 centred on the view has its first two corners at
      // (395, 295) and (405, 295). A quarter turn about the pivot takes them
      // to (395, 305) and (395, 295) - so both coordinates below would read
      // differently if the screen pass dropped rotation on the floor.
      expect(quad.y[0], closeTo(305, 1e-9));
      expect(quad.x[1], closeTo(395, 1e-9));
    });

    test(
      'a parent moves and turns and its screen-space child does neither',
      () async {
        final game = await _start();
        final stage = _stage();
        _eye(game.defaultCamera);
        final rig = stage.handle.addEntity(stage.rig);
        stage.rig.transformOffsetX[rig] = 250;
        stage.rig.transformRotation[rig] = 0.7;
        stage.handle.addEntity(stage.pinned, parent: rig);
        run.state.advance(_step);

        final quads = _quads(game.defaultCamera);
        final parent = _only(quads, _rigColor);
        // The control. Composition really is running on this frame, and it is
        // turning as well as moving - so a child that came out at the view's
        // middle, upright, did not merely get lucky.
        expect((parent.left + parent.right) / 2, closeTo(650, 1e-9));
        expect(
          parent.right - parent.left,
          greaterThan(10),
          reason: 'a turned square has a wider bounding box than its own side',
        );

        final child = _only(quads, _pinnedColor);
        expect(child.left, 390);
        expect(child.right, 410);
        expect(child.top, 295);
        expect(child.bottom, 305);
      },
    );

    test('ScreenTransform2D and WorldTransform2D cannot both be mixed in', () {
      // Declared headless: `describeType` runs when a scene declares the
      // prefab, which is inside `initializeScene`, so this is the failure a
      // game would hit at boot with no game to boot.
      Object? caught;
      try {
        _ClashScene().initializeScene(
          MemoryPool(pageSize: 4096),
          cameraViews: CameraViewTable(),
        );
      } catch (error) {
        caught = error;
      }
      expect(caught, isNotNull, reason: 'declaring the prefab has to fail');
      expect(
        caught.toString(),
        allOf(
          contains('ScreenTransform2D'),
          contains('WorldTransform2D'),
          contains('_Clash'),
        ),
        reason:
            'an entity WorldTransformSystem composes arrives at the fill pass '
            'carrying an ancestor position and an ancestor rotation, and the '
            'screen pass would read both as view units. Refusing the pair is '
            'what makes "a screen-space entity inherits nothing" true by '
            'construction rather than by a correction the pass has to apply.',
      );
    });

    test('Text2D and ScreenTransform2D cannot both be mixed in', () {
      Object? caught;
      try {
        _LabelClashScene().initializeScene(
          MemoryPool(pageSize: 4096),
          cameraViews: CameraViewTable(),
        );
      } catch (error) {
        caught = error;
      }
      expect(caught, isNotNull);
      expect(
        caught.toString(),
        allOf(contains('Text2D'), contains('ScreenTransform2D')),
        reason: 'there is no screen-space text, and it has to say so',
      );
    });
  });

  group('sizing', () {
    test(
      'one entity is correct in two views of different sizes at once',
      () async {
        final game = await _start();
        final stage = _stage();
        _eye(game.defaultCamera);
        _eye(game.mini);
        stage.handle.addEntity(stage.backdrop);
        run.state.advance(_step);

        final main = _only(_quads(game.defaultCamera), _backdropColor);
        expect(main.left, 0);
        expect(main.right, _mainWidth);
        expect(main.top, 0);
        expect(main.bottom, _mainHeight);

        final mini = _only(_quads(game.mini), _backdropColor);
        expect(mini.left, 0);
        expect(mini.right, _miniWidth);
        expect(mini.top, 0);
        expect(mini.bottom, _miniHeight);
      },
    );

    test('a units axis is the same size in both views', () async {
      final game = await _start();
      final stage = _stage();
      _eye(game.defaultCamera);
      _eye(game.mini);
      stage.handle.addEntity(stage.pinned);
      run.state.advance(_step);

      final main = _only(_quads(game.defaultCamera), _pinnedColor);
      final mini = _only(_quads(game.mini), _pinnedColor);
      expect(main.right - main.left, 20);
      expect(mini.right - mini.left, 20);
      expect(
        mini.left,
        _miniWidth / 2 - 10,
        reason: 'the anchor follows the view even where the size does not',
      );
    });

    test('the two axes are independent', () async {
      final game = await _start();
      final stage = _stage();
      _eye(game.defaultCamera);
      stage.handle.addEntity(stage.banner);
      run.state.advance(_step);

      final quad = _only(_quads(game.defaultCamera), _pinnedColor);
      expect(quad.right - quad.left, _mainWidth / 2);
      expect(
        quad.bottom - quad.top,
        20,
        reason: 'the height axis is units, and the view is 600 tall',
      );
    });

    test('a nine-sliced screen sprite is sliced at its view size', () async {
      final game = await _start();
      final stage = _stage();
      _eye(game.defaultCamera);
      stage.handle.addEntity(stage.panel);
      run.state.advance(_step);

      final cells = _quads(game.defaultCamera)
          .where((q) => q.color == _panelColor)
          .toList();
      expect(cells, hasLength(9));
      var left = double.infinity;
      var right = double.negativeInfinity;
      for (final cell in cells) {
        if (cell.left < left) left = cell.left;
        if (cell.right > right) right = cell.right;
      }
      expect(left, 0, reason: 'anchored top-left, at no offset');
      expect(
        right - left,
        _mainWidth / 2,
        reason:
            'the write pass rebuilds a sliced sprite from its row, so it has '
            'to rebuild the space it was filled in as well',
      );
    });
  });

  group('layers', () {
    test('behind draws first and front draws last, whatever the z', () async {
      final game = await _start();
      final stage = _stage();
      _eye(game.defaultCamera);
      final backdrop = stage.handle.addEntity(stage.backdrop);
      final world = stage.handle.addEntity(stage.world);
      final pinned = stage.handle.addEntity(stage.pinned);
      // Depth values that put the layers in exactly the wrong order if z
      // alone decided: the backdrop on top, the pinned element at the back.
      stage.backdrop.fill.zIndex[backdrop] = 100;
      stage.world.quad.zIndex[world] = 50;
      stage.pinned.quad.zIndex[pinned] = -100;
      run.state.advance(_step);

      expect(_order(game.defaultCamera), <int>[
        _backdropColor,
        _worldColor,
        _pinnedColor,
      ]);
    });

    test('a front element draws over a label sorted above the world', () async {
      final game = await _start();
      final stage = _stage();
      _eye(game.defaultCamera);
      stage.handle.addEntity(stage.world);
      final label = stage.handle.addEntity(stage.label);
      stage.handle.addEntity(stage.pinned);
      label<Text2D>().setText('AB');
      run.state.advance(_step);

      final order = _order(game.defaultCamera);
      expect(
        order,
        containsAllInOrder(<int>[_labelColor, _labelColor, _pinnedColor]),
        reason:
            'the label sits at z 9000 and the pinned element at 0, so z alone '
            'would draw the label last',
      );
      expect(order.last, _pinnedColor);
    });

    test('z still orders within one layer', () async {
      final game = await _start();
      final stage = _stage();
      _eye(game.defaultCamera);
      final low = stage.handle.addEntity(stage.pinned);
      final high = stage.handle.addEntity(stage.corner);
      stage.pinned.quad.zIndex[low] = 5;
      stage.corner.quad.zIndex[high] = 1;
      run.state.advance(_step);

      expect(_order(game.defaultCamera), <int>[
        _cornerColor,
        _pinnedColor,
      ], reason: 'both are front-layer, so the sort inside the layer decides');
    });

    test('the budget keeps the pinned layer and drops the world', () async {
      final game = await _start(_TightGame.new);
      final stage = _stage();
      _eye(game.defaultCamera);
      for (var i = 0; i < 8; i++) {
        final e = stage.handle.addEntity(stage.world);
        // Well above the screen element's own depth, so a frame spending its
        // one record on the highest z would spend it on a world sprite.
        stage.world.quad.zIndex[e] = 1000 + i;
      }
      final pinned = stage.handle.addEntity(stage.pinned);
      stage.pinned.quad.zIndex[pinned] = -5000;
      run.state.advance(_step);

      final quads = _quads(game.defaultCamera);
      expect(quads, hasLength(1));
      expect(
        quads.single.color,
        _pinnedColor,
        reason:
            'the trim admits from the front of the scene backwards, and the '
            'front layer is the front of the scene',
      );
    });
  });
}

/// A prefab asking for both transform spaces at once.
class _Clash extends EntityStruct
    with Transform2D, WorldTransform2D, ScreenTransform2D, Renderable2D {
  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    descriptor.has(width: 1, height: 1);
  }
}

/// A prefab asking for screen-space text.
class _LabelClash extends EntityStruct
    with Transform2D, ScreenTransform2D, Text2D {}

class _ClashScene extends SceneStruct {
  @sub
  final clash = _Clash();
}

class _LabelClashScene extends SceneStruct {
  @sub
  final clash = _LabelClash();
}
