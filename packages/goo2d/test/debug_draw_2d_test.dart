// Debug draw (#122) - world-space lines, circles and labels a system draws
// from the game isolate, published through a handoff buffer of their own and
// replayed over the scene.
//
// The assertions are on the **published debug batch**, in the order it was
// written, and on corner coordinates worked out from the projection by hand.
// A count cannot tell "the line drew" from "the line drew somewhere else, in
// the wrong colour, at the wrong thickness".
//
// The view is 800x600 and the camera sits at the origin at zoom 1 unless a
// test moves it, so `worldToView` is `(x + 400, 300 - y)`.
//
// # Both halves of the compile-out switch are tested here
//
// `debugDrawEnabled` is a `const bool`, so a single run only ever exercises
// one side of it. The suite is split: the groups below that need shapes are
// skipped when it is false, the release group is skipped when it is true, and
// the buffer-declaration test asserts the mechanism in both. Run it twice:
//
// ```
// flutter test test/debug_draw_2d_test.dart
// flutter test test/debug_draw_2d_test.dart --dart-define=goo2d.debugDraw=false
// ```

import 'dart:ffi' hide Size;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

part 'debug_draw_2d_test.g.dart';

late Game run;

const Duration _step = Duration(milliseconds: 10);

const double _viewWidth = 800;
const double _viewHeight = 600;

const int _spriteColor = 0xFF00FF00;
const int _lineColor = 0xFF00FFFF;

/// A plain sprite, so a test can watch the scene batch while debug shapes go
/// somewhere else.
class _Box extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    quad = descriptor.has(width: 16, height: 16, color: _spriteColor);
  }
}

class _Eye extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

class _Scene extends SceneStruct {
  late Scene handle;

  @override
  void onSceneMounted(Scene scene) => handle = scene;

  Entity addEntity<T extends EntityStruct>(T prefab) =>
      handle.addEntity(prefab);

  late final _Box box;
  late final _Eye eye;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    box = descriptor.has(_Box.new);
    eye = descriptor.has(_Eye.new);
  }
}

/// Draws whatever [paint] is set to, once per fixed step, through the
/// `debugDraw` accessor a game's own system would use.
///
/// A `FixedTickable`, matching the issue's own example, and that is what puts
/// it before the renderer: the presentation phase runs after every fixed step
/// of the tick has committed, so nothing here depends on system ordering.
class _Painter extends GameSystem with FixedTickable {
  static void Function(DebugDraw2D draw)? paint;

  @override
  void onFixedUpdate() => paint?.call(debugDraw);
}

class _State extends GameState2D<_DebugGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_Painter.new);
  }

  @override
  void onMounted() {
    super.onMounted();
    loadScene(_Scene());
  }
}

/// What the next [_game] declares as its sprite budget, or null for the
/// engine default. Set before `startInline`, because a budget sizes the
/// handoff slots during boot.
int? _declaredSpriteBudget;

/// What the next [_game] declares as its debug budget, or null for the
/// default.
int? _declaredDebugBudget;

class _DebugGame extends Game2D {
  CameraView get view => defaultCamera;

  /// A handoff declared *after* the renderer's, so its index counts what the
  /// renderer declared before it. This is what the release test reads to see
  /// whether the debug buffer exists at all.
  late final HandoffHandle probe;

  @override
  int get pageSize => 4096;

  @override
  int get maxSpritesPerTick =>
      _declaredSpriteBudget ?? super.maxSpritesPerTick;

  @override
  int get maxDebugRecordsPerTick =>
      _declaredDebugBudget ?? super.maxDebugRecordsPerTick;

  @override
  Duration get fixedTimeStep => _step;

  @override
  void describeBuffers(BufferDescriptor descriptor) {
    super.describeBuffers(descriptor);
    probe = descriptor.hasHandoff(slotBytes: 64);
  }

  @override
  GameState2D<_DebugGame> createState() => _State();
}

Future<_DebugGame> _game({int? spriteBudget, int? debugBudget}) async {
  _declaredSpriteBudget = spriteBudget;
  _declaredDebugBudget = debugBudget;
  final game = await Game.startInline(_DebugGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  game.view.setViewport(_viewWidth, _viewHeight);
  return game;
}

_Scene _scene() => run.state.singleScene<_Scene>();

GameRenderer2D get _renderer => run.state.getSystem<GameRenderer2D>();

/// One record as it crossed to main.
class _Rec {
  _Rec(this.color, this.corners);

  final int color;

  /// `x0, y0, x1, y1, x2, y2, x3, y3` in winding order.
  final List<double> corners;

  double get minX => corners[0] < corners[4] ? corners[0] : corners[4];
  double get maxX => corners[0] > corners[4] ? corners[0] : corners[4];
  double get minY => corners[1] < corners[5] ? corners[1] : corners[5];
  double get maxY => corners[1] > corners[5] ? corners[1] : corners[5];

  /// The quad's centre, which for a stroke is the middle of the segment it
  /// was expanded from.
  double get centreX => (corners[0] + corners[4]) / 2;
  double get centreY => (corners[1] + corners[5]) / 2;
}

List<_Rec> _read(HandoffHandle handle) {
  final buffer = handle.buffer;
  final slot = buffer.beginRead();
  if (slot == null) return const [];
  final bytes = Uint8List.fromList(slot.asTypedList(buffer.readUsedBytes));
  final view = ByteData.sublistView(bytes);
  final count = const DrawSpriteData2D().itemCount(bytes.length);
  final records = <_Rec>[];
  var offset = DrawData2D.batchHeaderBytes;
  for (var i = 0; i < count; i++) {
    records.add(
      _Rec(view.getUint32(offset + 32, Endian.little), [
        for (var k = 0; k < 8; k++)
          view.getFloat32(offset + k * 4, Endian.little),
      ]),
    );
    offset += DrawSpriteData2D.strideBytes;
  }
  return records;
}

List<_Rec> _debugBatch(_DebugGame game) => _read(game.debugFramesFor(game.view));

List<_Rec> _sceneBatch(_DebugGame game) => _read(game.framesFor(game.view));

Entity _eyeAt(_DebugGame game, _Scene scene, {double x = 0, double zoom = 1}) {
  final eye = scene.addEntity(scene.eye);
  scene.eye
    ..cameraView[eye] = game.view
    ..cameraZoom[eye] = zoom
    ..transformOffsetX[eye] = x;
  return eye;
}

void main() {
  _installDeclarations();

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
    _Painter.paint = null;
    _declaredSpriteBudget = null;
    _declaredDebugBudget = null;
  });

  // Runs whichever way the constant went: it reads the same mechanism from
  // both sides. With debug draw compiled in the renderer declares one handoff
  // per view and then the debug one, so a game's own third handoff has index
  // 2; compiled out, `describeBuffers` declares no debug handoff at all and
  // the same handle has index 1.
  test('the debug handoff is declared only where debug draw is compiled in',
      () async {
    final game = await _game();
    expect(game.framesFor(game.view).index, 0);
    expect(game.probe.index, debugDrawEnabled ? 2 : 1);
    if (debugDrawEnabled) {
      expect(game.debugFramesFor(game.view).index, 1);
      expect(game.debugFramesFor(game.view).slotBytes, game.debugBatchBytes);
    } else {
      // No list entry, so nothing was reserved and nothing can be asked for.
      expect(() => game.debugFramesFor(game.view), throwsA(isA<RangeError>()));
    }
  });

  group('a line', () {
    test('draws one quad across the two world points', () async {
      final game = await _game();
      _eyeAt(game, _scene());
      _Painter.paint = (draw) =>
          draw.line(0, 0, 10, 0, color: _lineColor, thickness: 2);
      run.state.advance(_step);

      final batch = _debugBatch(game);
      expect(batch, hasLength(1));
      expect(batch.single.color, _lineColor);
      // (0,0) and (10,0) land on view (400,300) and (410,300); a thickness of
      // 2 puts the corners one pixel either side of that segment.
      expect(batch.single.corners, [
        400.0, 301.0, //
        410.0, 301.0,
        410.0, 299.0,
        400.0, 299.0,
      ]);
      expect(_renderer.lastDebugRecordCount, 1);
    });

    test('follows the camera and keeps its thickness in pixels', () async {
      final game = await _game();
      _eyeAt(game, _scene(), x: 5, zoom: 2);
      _Painter.paint = (draw) => draw.line(5, 0, 15, 0, thickness: 2);
      run.state.advance(_step);

      final batch = _debugBatch(game);
      expect(batch, hasLength(1));
      // World x 5 is the camera's own x, so it lands on the middle of the
      // view; x 15 is ten world units away, which zoom 2 makes twenty pixels.
      expect(batch.single.corners, [
        400.0, 301.0, //
        420.0, 301.0,
        420.0, 299.0,
        400.0, 299.0,
      ]);
    });

    test('is not written when the camera cannot see it', () async {
      final game = await _game();
      _eyeAt(game, _scene());
      _Painter.paint = (draw) {
        draw.line(0, 0, 10, 0);
        draw.line(10000, 10000, 10010, 10000);
      };
      run.state.advance(_step);

      // Both are stored; only the one the viewport reaches becomes a record.
      expect(_renderer.debugDraw.segmentCount, 2);
      expect(_debugBatch(game), hasLength(1));
      expect(_renderer.lastDebugRecordCount, 1);
    });

    test('draws nothing for a zero-length segment', () async {
      final game = await _game();
      _eyeAt(game, _scene());
      _Painter.paint = (draw) => draw.line(3, 4, 3, 4);
      run.state.advance(_step);

      expect(_renderer.debugDraw.segmentCount, 1);
      expect(_debugBatch(game), isEmpty);
    });
  }, skip: debugDrawEnabled ? false : 'debug draw is compiled out');

  group('a circle', () {
    test('costs one record per segment, all on the circle', () async {
      final game = await _game();
      _eyeAt(game, _scene());
      _Painter.paint = (draw) =>
          draw.circle(20, 10, radius: 5, segments: 12, thickness: 1);
      run.state.advance(_step);

      final batch = _debugBatch(game);
      expect(batch, hasLength(12));
      // The centre is world (20, 10), which is view (420, 290). Every chord's
      // endpoints are on the circle, so every endpoint is 5 pixels out at
      // zoom 1.
      for (final record in batch) {
        final dx = record.corners[0] - 420;
        final dy = record.corners[1] - 290;
        // A half-thickness of 0.5 moves each corner off the circle by that
        // much, either way.
        expect((dx * dx + dy * dy), closeTo(25, 5.5));
      }
    });

    test('draws nothing at zero radius or under three segments', () async {
      final game = await _game();
      _eyeAt(game, _scene());
      _Painter.paint = (draw) {
        draw.circle(0, 0, radius: 0);
        draw.circle(0, 0, radius: 5, segments: 2);
      };
      run.state.advance(_step);

      expect(_renderer.debugDraw.segmentCount, 0);
      expect(_debugBatch(game), isEmpty);
    });
  }, skip: debugDrawEnabled ? false : 'debug draw is compiled out');

  group('a label', () {
    test('draws with no font, no atlas and no asset declared', () async {
      final game = await _game();
      _eyeAt(game, _scene());
      // A game that has declared no `TextureAsset` at all - the whole point of
      // a stroke alphabet over a `BitmapFont` for this one job.
      _Painter.paint = (draw) => draw.label(0, 0, 'A', size: 12);
      run.state.advance(_step);

      final batch = _debugBatch(game);
      // 'A' is three strokes: two legs and a crossbar.
      expect(batch, hasLength(3));
      // The box is centred on the anchor: 12 pixels tall, and four lattice
      // columns of two pixels each wide.
      const unit = 12 / 6;
      const halfWidth = 4 * unit / 2;
      for (final record in batch) {
        expect(record.minX, greaterThanOrEqualTo(400 - halfWidth - 1));
        expect(record.maxX, lessThanOrEqualTo(400 + halfWidth + 1));
        expect(record.minY, greaterThanOrEqualTo(300 - 6 - 1));
        expect(record.maxY, lessThanOrEqualTo(300 + 6 + 1));
      }
    });

    test('is sized in pixels, so zoom moves it and does not scale it',
        () async {
      final game = await _game();
      _eyeAt(game, _scene(), zoom: 4);
      _Painter.paint = (draw) => draw.label(10, 0, 'I', size: 12);
      run.state.advance(_step);

      final batch = _debugBatch(game);
      // 'I' is a top bar, a stem and a bottom bar.
      expect(batch, hasLength(3));
      // World x 10 at zoom 4 is view x 440, and the glyph is still 12 pixels
      // tall there.
      for (final record in batch) {
        expect(record.centreX, closeTo(440, 5));
      }
      final top = batch.map((r) => r.minY).reduce((a, b) => a < b ? a : b);
      final bottom = batch.map((r) => r.maxY).reduce((a, b) => a > b ? a : b);
      expect(bottom - top, closeTo(12, 2));
    });

    test('folds lower case and skips what the alphabet has no shape for',
        () async {
      final game = await _game();
      _eyeAt(game, _scene());
      _Painter.paint = (draw) => draw.label(0, 0, 'a');
      run.state.advance(_step);
      final lower = _debugBatch(game).length;

      _Painter.paint = (draw) => draw.label(0, 0, 'A');
      run.state.advance(_step);
      expect(_debugBatch(game), hasLength(lower));

      // Outside printable ASCII: it advances the pen and draws nothing. The
      // clear is what empties the store, since a call that stores nothing
      // leaves the previous frame's shapes standing.
      _Painter.paint = (draw) => draw
        ..clear()
        ..label(0, 0, 'é');
      run.state.advance(_step);
      expect(_debugBatch(game), isEmpty);
    });

    test('draws nothing for an empty string or a non-positive size', () async {
      final game = await _game();
      _eyeAt(game, _scene());
      _Painter.paint = (draw) {
        draw.label(0, 0, '');
        draw.label(0, 0, 'X', size: 0);
      };
      run.state.advance(_step);

      expect(_renderer.debugDraw.segmentCount, 0);
    });
  }, skip: debugDrawEnabled ? false : 'debug draw is compiled out');

  group('the store', () {
    test('keeps its shapes until something draws again', () async {
      final game = await _game();
      _eyeAt(game, _scene());
      _Painter.paint = (draw) => draw.line(0, 0, 10, 0);
      run.state.advance(_step);
      expect(_debugBatch(game), hasLength(1));

      // A fixed step that draws nothing at all. The shapes stay, so a system
      // drawing slower than the display does not flicker.
      _Painter.paint = null;
      run.state.advance(_step);
      expect(_debugBatch(game), hasLength(1));

      _Painter.paint = (draw) => draw.clear();
      run.state.advance(_step);
      expect(_debugBatch(game), isEmpty);
    });

    test('replaces, and does not accumulate, across frames that draw',
        () async {
      final game = await _game();
      _eyeAt(game, _scene());
      _Painter.paint = (draw) => draw.line(0, 0, 10, 0);
      run.state.advance(_step);
      run.state.advance(_step);
      run.state.advance(_step);
      expect(_debugBatch(game), hasLength(1));
      expect(_renderer.debugDraw.segmentCount, 1);
    });

    test('drops past capacity and counts what it dropped', () async {
      final game = await _game(debugBudget: 4);
      _eyeAt(game, _scene());
      _Painter.paint = (draw) {
        for (var i = 0; i < 10; i++) {
          draw.line(0, i.toDouble(), 10, i.toDouble());
        }
      };
      run.state.advance(_step);

      expect(_renderer.debugDraw.segmentCapacity, 4);
      expect(_renderer.debugDraw.segmentCount, 4);
      expect(_renderer.debugDraw.droppedSegments, 6);
      expect(_debugBatch(game), hasLength(4));
    });

    test('stores nothing for a category that is switched off', () async {
      final game = await _game();
      _eyeAt(game, _scene());
      _Painter.paint = (draw) {
        draw.categories = ~(1 << 3);
        draw.line(0, 0, 10, 0, category: 3);
        draw.line(0, 1, 10, 1, category: 4);
      };
      run.state.advance(_step);

      expect(_renderer.debugDraw.segmentCount, 1);
      expect(_renderer.debugDraw.droppedSegments, 0);
      expect(_debugBatch(game), hasLength(1));
    });
  }, skip: debugDrawEnabled ? false : 'debug draw is compiled out');

  group('against the scene', () {
    test('debug shapes do not spend the sprite budget', () async {
      // Exactly enough for the one sprite in the scene, so a debug record
      // charged against it would push the sprite out of the frame.
      final game = await _game(spriteBudget: 1);
      _eyeAt(game, _scene());
      final scene = _scene();
      scene.addEntity(scene.box);
      _Painter.paint = (draw) {
        for (var i = 0; i < 50; i++) {
          draw.line(0, i.toDouble(), 10, i.toDouble());
        }
      };
      run.state.advance(_step);

      final sceneBatch = _sceneBatch(game);
      expect(sceneBatch, hasLength(1));
      expect(sceneBatch.single.color, _spriteColor);
      expect(_renderer.lastRecordCount, 1);
      expect(_renderer.lastRecordsOverBudget, 0);
      expect(_debugBatch(game), hasLength(50));
      expect(_renderer.lastDebugRecordCount, 50);
    });

    test('the sprite batch carries no debug record', () async {
      final game = await _game();
      _eyeAt(game, _scene());
      final scene = _scene();
      scene.addEntity(scene.box);
      _Painter.paint = (draw) => draw.line(0, 0, 10, 0, color: _lineColor);
      run.state.advance(_step);

      expect(_sceneBatch(game).map((r) => r.color), [_spriteColor]);
      expect(_debugBatch(game).map((r) => r.color), [_lineColor]);
    });
  }, skip: debugDrawEnabled ? false : 'debug draw is compiled out');

  // The other side of the constant. Run with
  // `--dart-define=goo2d.debugDraw=false`.
  group('compiled out', () {
    test('the accessor hands back the shared disabled instance', () async {
      await _game();
      expect(
        identical(_renderer.debugDraw, const DebugDraw2D.disabled()),
        isTrue,
      );
    });

    test('no store is allocated and no call stores anything', () async {
      final game = await _game();
      _eyeAt(game, _scene());
      final draw = _renderer.debugDraw;
      expect(draw.segmentCapacity, 0);

      _Painter.paint = (d) {
        d.line(0, 0, 10, 0);
        d.circle(0, 0, radius: 5);
        d.label(0, 0, 'HELLO');
      };
      run.state.advance(_step);

      expect(draw.segmentCount, 0);
      expect(draw.droppedSegments, 0);
      expect(_renderer.lastDebugRecordCount, 0);
    });

    test('the scene still draws', () async {
      final game = await _game();
      _eyeAt(game, _scene());
      final scene = _scene();
      scene.addEntity(scene.box);
      _Painter.paint = (draw) => draw.line(0, 0, 10, 0);
      run.state.advance(_step);

      expect(_sceneBatch(game).map((r) => r.color), [_spriteColor]);
    });
  }, skip: debugDrawEnabled ? 'debug draw is compiled in' : false);
}
