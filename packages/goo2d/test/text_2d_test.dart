// Text in the world (#127) - a `Text2D` label, laid out on the game isolate
// from a grid font and expanded into one draw record per glyph inside the
// sprite write pass.
//
// The assertions here are on the **published batch**, in draw order, and not
// on a count. A count cannot tell "the label drew" from "the label drew in the
// wrong place, in the wrong order, sampling the wrong cell of the atlas", and
// each of those is a way this can be wrong while every counter reads right.
//
// Geometry is checked against numbers worked out from the projection by hand
// rather than against whatever the renderer produced, so a change to the
// layout arithmetic has to be argued for and not merely re-recorded. The view
// is 800x600, the camera sits at the origin at zoom 1 unless a test moves it,
// so `worldToView` is `(x + 400, 300 - y)`.

import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

part 'text_2d_test.g.dart';

late Game run;

const Duration _step = Duration(milliseconds: 10);

const double _viewWidth = 800;
const double _viewHeight = 600;

const int _backColor = 0xFF112233;
const int _enemyColor = 0xFF00FF00;
const int _labelColor = 0xFFFF0000;
const int _frontColor = 0xFF0000FF;

/// A 2x1 PNG standing in for a font atlas. Nothing here reads a pixel - a
/// glyph's rectangle comes out of the grid by division, which is the whole
/// point of a normalised frame, so the atlas needs to exist and no more.
final Uint8List _png2x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR42mP4z8AAQv8BD/kD'
  '/Zh51wAAAAAASUVORK5CYII=',
);

final TextureKey _atlasKey = TextureKey(MemorySource(_png2x1, name: 'font.png'));

/// 16 across, 6 down, starting at space. 95 glyphs and not 96, so the last
/// cell of the last row holds nothing - which is the ordinary shape of a
/// hand-made ASCII font, and it puts a code point inside the grid but outside
/// the font where a test can reach it.
const int _columns = 16;
const int _rows = 6;
const int _glyphs = 95;

/// One glyph cell, in world units.
const double _cell = 8;

/// Behind everything. Registered first, so it is also first in encounter
/// order, which is what an equal-`zIndex` tie would fall back on.
class _Back extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    quad = descriptor.has(
      width: 8,
      height: 8,
      color: _backColor,
      zIndex: -10,
    );
  }
}

/// The thing a damage number goes over. 16x16 at the world origin puts its
/// top edge at view y 292.
class _Enemy extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    quad = descriptor.has(width: 16, height: 16, color: _enemyColor);
  }
}

/// The label. Eight code units of capacity, which is deliberately small - the
/// overflow tests need a capacity a test string can reach.
class _Damage extends EntityStruct with Transform2D, WorldTransform2D, Text2D {
  late final TextureAsset atlas;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    textCodeUnits.length = 8;
  }

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    atlas = descriptor.has(_atlasKey);
  }

  /// How many times [textFont] has been read. The override builds a font, so
  /// a read allocates one, and a frame that reached the getter would allocate
  /// one per archetype per frame.
  int fontReads = 0;

  @override
  BitmapFont get textFont {
    fontReads++;
    return BitmapFont(
      texture: atlas,
      columns: _columns,
      rows: _rows,
      glyphCount: _glyphs,
    );
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    textCellWidth.initialValue = _cell;
    textCellHeight.initialValue = _cell;
    textColor.initialValue = _labelColor;
    textZIndex.initialValue = 10;
  }
}

/// A label prefab that declares no font. Every entity of it draws nothing,
/// whatever its text says.
class _Silent extends EntityStruct with Transform2D, WorldTransform2D, Text2D {
  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    textCellWidth.initialValue = _cell;
    textCellHeight.initialValue = _cell;
    textZIndex.initialValue = 40;
  }
}

/// In front of the label.
class _Front extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    quad = descriptor.has(width: 4, height: 4, color: _frontColor, zIndex: 20);
  }
}

class _Eye extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

class _Scene extends SceneStruct {
  late Scene handle;

  @override
  void onSceneMounted(Scene scene) => handle = scene;

  Entity addEntity<T extends EntityStruct>(T prefab) =>
      handle.addEntity(prefab);

  late final _Back back;
  late final _Enemy enemy;
  late final _Damage damage;
  late final _Silent silent;
  late final _Front front;
  late final _Eye eye;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    back = descriptor.has(_Back.new);
    enemy = descriptor.has(_Enemy.new);
    damage = descriptor.has(_Damage.new);
    silent = descriptor.has(_Silent.new);
    front = descriptor.has(_Front.new);
    eye = descriptor.has(_Eye.new);
  }
}

class _State extends GameState2D<_TextGame> {
  @override
  void onMounted() {
    super.onMounted();
    loadScene(_Scene());
  }
}

/// What the next [_game] declares as its record budget, or null for the
/// engine default. Set before `startInline`, because the budget sizes the
/// handoff slots during boot.
int? _declaredBudget;

class _TextGame extends Game2D {
  CameraView get view => defaultCamera;

  @override
  int get pageSize => 4096;

  @override
  int get maxSpritesPerTick => _declaredBudget ?? super.maxSpritesPerTick;

  @override
  Duration get fixedTimeStep => _step;

  @override
  GameState2D<_TextGame> createState() => _State();
}

Future<_TextGame> _game({int? budget}) async {
  _declaredBudget = budget;
  final game = await Game.startInline(_TextGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  // The atlas decode is still in flight when `start` resolves; awaiting the
  // same key keeps it from landing after teardown.
  await game.assets.load(_atlasKey);
  game.view.setViewport(_viewWidth, _viewHeight);
  return game;
}

_Scene _scene() => run.state.singleScene<_Scene>();

GameRenderer2D get _renderer => run.state.getSystem<GameRenderer2D>();

/// One record as it crossed to main.
class _Rec {
  _Rec(this.color, this.corners, this.uvs);

  final int color;

  /// `x0, y0, x1, y1, x2, y2, x3, y3` in winding order.
  final List<double> corners;

  /// The eight UVs, in the same corner order.
  final List<double> uvs;

  double get left => corners[0];
  double get top => corners[1];
  double get right => corners[2];
  double get bottom => corners[5];
}

List<_Rec> _batch(_TextGame game) {
  final buffer = _renderer.framesFor(game.view).buffer;
  final slot = buffer.beginRead();
  if (slot == null) return const [];
  final bytes = Uint8List.fromList(slot.asTypedList(buffer.readUsedBytes));
  final view = ByteData.sublistView(bytes);
  final count = const DrawSpriteData2D().itemCount(bytes.length);
  final records = <_Rec>[];
  var offset = DrawData2D.batchHeaderBytes;
  for (var i = 0; i < count; i++) {
    records.add(
      _Rec(
        view.getUint32(offset + 32, Endian.little),
        [
          for (var k = 0; k < 8; k++)
            view.getFloat32(offset + k * 4, Endian.little),
        ],
        [
          for (var k = 0; k < 8; k++)
            view.getFloat32(offset + 40 + k * 4, Endian.little),
        ],
      ),
    );
    offset += DrawSpriteData2D.strideBytes;
  }
  return records;
}

List<int> _colors(_TextGame game) => [for (final r in _batch(game)) r.color];

Entity _eyeAt(_TextGame game, _Scene scene, {double x = 0, double zoom = 1}) {
  final eye = scene.addEntity(scene.eye);
  scene.eye
    ..cameraView[eye] = game.view
    ..cameraZoom[eye] = zoom
    ..transformOffsetX[eye] = x;
  return eye;
}

Entity _labelAt(_Scene scene, String text, {double x = 0, double y = 0}) {
  final entity = scene.addEntity(scene.damage);
  scene.damage
    ..transformOffsetX[entity] = x
    ..transformOffsetY[entity] = y;
  entity<Text2D>().setText(text);
  return entity;
}

Entity _spriteAt<T extends EntityStruct>(
  _Scene scene,
  T prefab, {
  double x = 0,
  double y = 0,
}) {
  final entity = scene.addEntity(prefab);
  final transform = entity<Transform2D>().component;
  transform
    ..transformOffsetX[entity] = x
    ..transformOffsetY[entity] = y;
  return entity;
}

void main() {
  _installDeclarations();

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
    _declaredBudget = null;
  });

  group('a number over an entity', () {
    test('draws one record per glyph, in depth order with the sprites', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      _spriteAt(scene, scene.back);
      _spriteAt(scene, scene.enemy);
      _spriteAt(scene, scene.front);
      _labelAt(scene, '-24', y: 20);
      run.state.advance(_step);

      expect(
        _colors(game),
        [
          _backColor,
          _enemyColor,
          _labelColor,
          _labelColor,
          _labelColor,
          _frontColor,
        ],
        reason:
            'the label is one candidate at zIndex 10 and three records, and it '
            'sorts as one thing: behind the zIndex-20 sprite and in front of '
            'the enemy, with its three glyphs contiguous. Colour is the '
            'identity here - each prefab declares its own.',
      );
      expect(_renderer.lastSpriteCount, 4);
      expect(_renderer.lastRecordCount, 6);
    });

    test('the font is read while the archetype is described, and no '
        'more', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      _labelAt(scene, '-24', y: 20);
      _labelAt(scene, '99', x: 40);
      final described = scene.damage.fontReads;
      expect(described, 1, reason: 'once for the archetype, not per entity');
      final resolved = scene.damage.textFontResolved;
      expect(resolved, isNotNull);

      run.state.advance(_step);
      run.state.advance(_step);

      expect(_batch(game), hasLength(5), reason: 'both labels drew');
      expect(
        scene.damage.fontReads,
        described,
        reason:
            'the write pass reads textFontResolved, and reaching the getter '
            'would build a BitmapFont per archetype per frame',
      );
      expect(scene.damage.textFontResolved, same(resolved));
    });

    test('the glyphs sit above the entity they label', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      _spriteAt(scene, scene.enemy);
      _labelAt(scene, '-24', y: 20);
      run.state.advance(_step);

      final records = _batch(game);
      final enemy = records.first;
      expect(enemy.top, 292, reason: '16x16 centred on the world origin');
      for (final glyph in records.skip(1)) {
        expect(
          glyph.bottom,
          lessThan(enemy.top),
          reason:
              'world +y is up and view y is down, so a label 20 world units '
              'above the enemy has to come out entirely above its top edge',
        );
      }
    });

    test('the glyphs run left to right from the pivot', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      _labelAt(scene, '-24', y: 20);
      run.state.advance(_step);

      final glyphs = _batch(game);
      expect(glyphs, hasLength(3));
      // Three cells of 8 is a 24-wide box; the default pivot is its centre, so
      // it starts 12 left of the entity. The entity is at world (0, 20), which
      // is view (400, 280), and the cell's own centre puts its top at 280 - 4.
      expect(glyphs[0].corners, [388, 276, 396, 276, 396, 284, 388, 284]);
      expect(glyphs[1].left, 396);
      expect(glyphs[2].left, 404);
      expect(glyphs[2].right, 412);
    });

    test('each glyph samples its own cell of the atlas', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      _labelAt(scene, '-24', y: 20);
      run.state.advance(_step);

      final glyphs = _batch(game);
      // `-` is code unit 45, so cell 13 of a grid starting at 32: column 13 of
      // row 0. `2` is 50, cell 18: column 2 of row 1. `4` is 52, cell 20.
      expect(glyphs[0].uvs[0], closeTo(13 / _columns, 1e-6));
      expect(glyphs[0].uvs[1], closeTo(0, 1e-6));
      expect(glyphs[0].uvs[2], closeTo(14 / _columns, 1e-6));
      expect(glyphs[0].uvs[7], closeTo(1 / _rows, 1e-6));
      expect(glyphs[1].uvs[0], closeTo(2 / _columns, 1e-6));
      expect(glyphs[1].uvs[1], closeTo(1 / _rows, 1e-6));
      expect(glyphs[2].uvs[0], closeTo(4 / _columns, 1e-6));
      expect(glyphs[2].uvs[1], closeTo(1 / _rows, 1e-6));
    });

    test('a label and a sprite at one depth put the label in front', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      _spriteAt(scene, scene.enemy);
      final label = _labelAt(scene, '9', y: 20);
      scene.damage.textZIndex[label] = 0;
      run.state.advance(_step);

      expect(
        _colors(game),
        [_enemyColor, _labelColor],
        reason:
            'labels are walked after every sprite, so the encounter tie-break '
            'at one zIndex puts the name over the character and not under it',
      );
    });

    test('an invisible label produces no record', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      _spriteAt(scene, scene.enemy);
      final label = _labelAt(scene, '-24', y: 20);
      scene.damage.textVisible[label] = false;
      run.state.advance(_step);

      expect(_colors(game), [_enemyColor]);
      expect(_renderer.lastSpriteCount, 1);
    });

    test('a label clear of the view is never queued', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      _labelAt(scene, '-24', x: 10000);
      run.state.advance(_step);
      expect(_renderer.lastSpriteCount, 0);
      expect(_batch(game), isEmpty);
    });

    test('the pivot is the alignment', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      final label = _labelAt(scene, '-24');
      scene.damage
        ..textPivotFractionX[label] = 0
        ..textPivotFractionY[label] = 0;
      run.state.advance(_step);

      final glyphs = _batch(game);
      expect(
        glyphs[0].left,
        400,
        reason:
            "fraction 0 puts the box's own left edge on the entity, so the "
            'first glyph starts there however long the label is',
      );
      expect(glyphs[0].top, 300);
      expect(glyphs[2].right, 424);
    });

    test('a rotated label turns as one line, not glyph by glyph', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      final label = _labelAt(scene, '-24');
      scene.damage.transformRotation[label] = math.pi / 2;
      run.state.advance(_step);

      final glyphs = _batch(game);
      // A quarter turn counter-clockwise on screen: the line now runs up the
      // view, so each glyph is eight further up than the one before it and
      // the cell's own width is what became vertical.
      expect(glyphs[0].corners[0], closeTo(396, 1e-3));
      expect(glyphs[0].corners[1], closeTo(312, 1e-3));
      expect(glyphs[0].corners[2], closeTo(396, 1e-3));
      expect(glyphs[0].corners[3], closeTo(304, 1e-3));
      expect(glyphs[1].corners[1], closeTo(304, 1e-3));
      expect(glyphs[2].corners[1], closeTo(296, 1e-3));
    });

    test("a cell past the font's glyph count is not a glyph", () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      // `~` is 126, cell 94, the last one this font declares. 127 is cell 95:
      // inside the 16x6 grid and outside the 95 glyphs, so the atlas has
      // nothing there and nothing draws.
      _labelAt(scene, '~\u007F');
      run.state.advance(_step);

      final glyphs = _batch(game);
      expect(glyphs, hasLength(1));
      expect(glyphs[0].uvs[0], closeTo(14 / _columns, 1e-6));
      expect(glyphs[0].uvs[1], closeTo(5 / _rows, 1e-6));
    });

    test('a prefab with no font draws nothing at all', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      _spriteAt(scene, scene.enemy);
      final mute = scene.addEntity(scene.silent);
      mute<Text2D>().setText('-24');
      run.state.advance(_step);

      expect(mute<Text2D>().text, '-24', reason: 'the row still holds it');
      expect(_colors(game), [_enemyColor]);
      expect(_renderer.lastSpriteCount, 1);
    });
  });

  group('the camera', () {
    test('text scales with the zoom', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene, zoom: 2);
      _labelAt(scene, '-24', y: 20);
      run.state.advance(_step);

      final glyphs = _batch(game);
      expect(glyphs, hasLength(3));
      // Zoom doubles the cell and the distance from the camera alike: the
      // entity's view y is 300 - 40, the box is 48 wide, and each glyph is 16.
      expect(glyphs[0].corners, [376, 252, 392, 252, 392, 268, 376, 268]);
      expect(glyphs[1].left, 392);
      expect(glyphs[2].left, 408);
    });

    test('text moves with the camera', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene, x: 50);
      _labelAt(scene, '-24', y: 20);
      run.state.advance(_step);

      final glyphs = _batch(game);
      expect(
        glyphs[0].left,
        338,
        reason:
            'the camera 50 to the right of the label puts it 50 further left '
            'on screen - 388 at the origin, 338 here',
      );
      expect(glyphs[2].left, 354);
    });
  });

  group('capacity', () {
    test('a string past capacity trips the assert', () async {
      await _game();
      final scene = _scene();
      final label = scene.addEntity(scene.damage);
      expect(
        () => label<Text2D>().setText('123456789'),
        throwsA(isA<AssertionError>()),
        reason:
            'the capacity is declared on the prefab, so a longer string means '
            'the prefab reserved too little - a programming error, and a '
            'debug run stops on it',
      );
    });

    test('it truncates instead of overrunning, in either build', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      final label = scene.addEntity(scene.damage);
      try {
        label<Text2D>().setText('123456789');
      } on AssertionError {
        // The assert fires after the write, so what follows is the row a
        // release build would have been left with as well.
      }
      expect(label<Text2D>().text, '12345678');
      expect(label<Text2D>().textLength, 8);
      run.state.advance(_step);
      expect(
        _batch(game).length,
        8,
        reason:
            'eight code units of storage draw eight glyphs. A ninth would '
            'have had to come from somewhere outside the row.',
      );
    });

    test('the dropped code units are counted, where an assert would not be', () async {
      await _game();
      final scene = _scene();
      final label = scene.addEntity(scene.damage);
      expect(scene.damage.textCodeUnitsDropped, 0);
      try {
        label<Text2D>().setText('123456789');
      } on AssertionError {
        // Ignored - the count is the half of the guard a release build keeps.
      }
      expect(scene.damage.textCodeUnitsDropped, 1);
      try {
        label<Text2D>().setText('1234567890123');
      } on AssertionError {
        // As above.
      }
      expect(
        scene.damage.textCodeUnitsDropped,
        6,
        reason: 'it accumulates over every label of the archetype',
      );
    });

    test('setInt writes digits with no string, and keeps the leading ones', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      final label = scene.addEntity(scene.damage);
      label<Text2D>().setInt(-24);
      expect(label<Text2D>().text, '-24');
      label<Text2D>().setInt(0);
      expect(label<Text2D>().text, '0');
      label<Text2D>().setInt(12345678);
      expect(label<Text2D>().text, '12345678');
      try {
        label<Text2D>().setInt(-123456789);
      } on AssertionError {
        // Ignored; the truncation below is what is under test.
      }
      expect(
        label<Text2D>().text,
        '-1234567',
        reason:
            'a number too long for its capacity keeps its sign and its most '
            'significant digits - dropping those would read as a different '
            'number rather than as a clipped one',
      );
      run.state.advance(_step);
      expect(_batch(game).length, 8);
    });
  });

  group('a label with nothing to draw', () {
    test('is not queued at all', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      _spriteAt(scene, scene.enemy);
      scene.addEntity(scene.damage);
      run.state.advance(_step);

      expect(_colors(game), [_enemyColor]);
      expect(
        _renderer.lastSpriteCount,
        1,
        reason:
            'a label of no characters draws no part of itself, so counting it '
            'among the sprites the frame drew would be a lie',
      );
    });

    test('a label whose every character is outside the font is not queued',
        () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      _spriteAt(scene, scene.enemy);
      // Three tabs. The row is not empty and the label has a size, so this
      // reaches the charge and comes out of it at zero - the case the length
      // of the string cannot answer.
      _labelAt(scene, '\t\t\t', y: 20);
      run.state.advance(_step);

      expect(_colors(game), [_enemyColor]);
      expect(_renderer.lastSpriteCount, 1);
      expect(_renderer.lastRecordCount, 1);
    });

    test('cannot slip past a budget that has already closed', () async {
      final game = await _game(budget: 4);
      final scene = _scene();
      _eyeAt(game, scene);
      for (var i = 0; i < 6; i++) {
        _spriteAt(scene, scene.front);
      }
      // In front of every one of them, so the trim reaches it first. Costing
      // zero records, `recordCount + 0 > 4` is false however closed the
      // budget is - which is exactly why the fill pass has to skip it rather
      // than let the budget test filter it.
      final empty = scene.addEntity(scene.damage);
      scene.damage.textZIndex[empty] = 30;
      run.state.advance(_step);

      expect(_renderer.lastRecordCount, 4);
      expect(_renderer.lastRecordsOverBudget, 2);
      expect(
        _renderer.lastSpriteCount,
        4,
        reason:
            'the four sprites the budget admitted, and not five - the empty '
            'label in front of them is not a candidate',
      );
      expect(_colors(game), [
        _frontColor,
        _frontColor,
        _frontColor,
        _frontColor,
      ]);
    });
  });

  group('the record charge', () {
    test('is exactly what the write pass emits', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      _spriteAt(scene, scene.enemy);
      _labelAt(scene, '-24', y: 20);
      _labelAt(scene, '99', y: 40);
      run.state.advance(_step);

      expect(
        _renderer.lastRecordCount,
        _batch(game).length,
        reason:
            'the charge and the emission are the same number counted twice, '
            'and #252 is what happens when they drift',
      );
      expect(_renderer.lastRecordsOverBudget, 0);
    });

    test('a code unit the font has no cell for costs nothing and leaves a gap', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      // Tab is code unit 9, below the font's first code point; the euro sign
      // is 8364, past the end of its 96 cells. Neither has a cell, so neither
      // draws - and both still advance, so `4` stays in the fourth column
      // instead of sliding left into the hole.
      _labelAt(scene, '-\t€4', y: 20);
      run.state.advance(_step);

      final records = _batch(game);
      expect(records, hasLength(2));
      expect(
        _renderer.lastRecordCount,
        records.length,
        reason: 'charged for the two it drew, not the four it holds',
      );
      expect(records[0].left, 384, reason: 'a 32-wide box, so 16 left of 400');
      expect(
        records[1].left,
        384 + 3 * _cell,
        reason:
            'the fourth character is in the fourth column - a skipped glyph '
            'leaves its gap instead of pulling the line left',
      );
      expect(records[1].uvs[0], closeTo(4 / _columns, 1e-6));
    });

    test('letter spacing changes the advance and not the cell', () async {
      final game = await _game();
      final scene = _scene();
      _eyeAt(game, scene);
      final label = _labelAt(scene, '-24', y: 20);
      scene.damage.textLetterSpacing[label] = 2;
      run.state.advance(_step);

      final glyphs = _batch(game);
      // Three cells of 8 and two gaps of 2 is a 28-wide box, centred on 400.
      expect(glyphs[0].left, 386);
      expect(glyphs[0].right, 394, reason: 'the cell itself is still 8 wide');
      expect(glyphs[1].left, 396);
      expect(glyphs[2].left, 406);
    });
  });
}
