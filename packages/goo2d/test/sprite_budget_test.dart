// What happens when a frame asks for more records than `maxSpritesPerTick`
// allows (#175).
//
// The excess used to disappear with nothing anywhere saying so:
// `lastWriteDropped` is about the handoff slot and stayed false, and no
// counter existed. `GameRenderer2D.lastRecordsOverBudget` is that number now.
//
// Every test here runs against a budget of 64 records rather than the default
// 4096, so "over budget" is reachable from a hundred entities instead of five
// thousand. The mechanism is the same at either size.
//
// Two archetypes with different `zIndex`, deliberately: a single-archetype
// scene has nothing for the fill order to get wrong, so it would pass against
// any drop policy at all and could not tell one from another.

import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

/// The live run under test - one inline run per isolate, so one binding.
late Game run;

const Duration _step = Duration(milliseconds: 10);

/// The record budget every game in this file declares.
const int _budget = 64;

const int _firstColor = 0xFF00FF00;
const int _secondColor = 0xFFFF0000;
const int _panelColor = 0xFF0000FF;

/// A 2x1 PNG. Nothing here looks at a pixel; a nine-sliced sprite needs a
/// texture to exist because slicing subdivides image space, and this is the
/// smallest thing that is one.
final Uint8List _png2x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR42mP4z8AAQv8BD/kD'
  '/Zh51wAAAAAASUVORK5CYII=',
);

final TextureKey _panelTextureKey = TextureKey(
  MemorySource(_png2x1, name: 'panel.png'),
);

/// One plain quad, `zIndex` 0, registered first.
class _First extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    quad = descriptor.has(width: 8, height: 8, color: _firstColor);
  }
}

/// One plain quad on top of [_First], registered second.
///
/// Higher `zIndex` and registered later is the combination that matters: the
/// budget is spent in *encounter* order, which is archetype registration, and
/// the sort by depth happens afterwards. So the layer nearest the camera is
/// the one that vanishes, which is the sharp part of #175.
class _Second extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    quad = descriptor.has(width: 8, height: 8, color: _secondColor, zIndex: 10);
  }
}

/// One nine-sliced sprite: one sprite, nine records.
class _Panel extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final TextureAsset skin;
  late final Sprite frame;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    skin = descriptor.has(_panelTextureKey);
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    frame = descriptor.has(
      texture: skin,
      width: 40,
      height: 40,
      color: _panelColor,
      nineSliceBorder: NineSliceBorder.all(4, sourceSize: 16),
    );
  }
}

class _BudgetScene extends SceneStruct {
  late Scene _handle;

  @override
  void onSceneMounted(Scene scene) => _handle = scene;

  Entity add<T extends EntityStruct>(T prefab) => _handle.addEntity(prefab);

  late final _First first;
  late final _Panel panel;
  late final _Second second;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    // Declaration order is archetype order is fill order. The whole file
    // depends on it, so it is stated once, here.
    first = descriptor.has(_First.new);
    panel = descriptor.has(_Panel.new);
    second = descriptor.has(_Second.new);
  }
}

class _BudgetState extends GameState2D<_BudgetGame> {
  final _BudgetScene budgetScene = _BudgetScene();

  @override
  void onMounted() {
    super.onMounted();
    loadScene(budgetScene);
  }
}

class _BudgetGame extends Game2D {
  CameraView get view => defaultCamera;

  @override
  int get pageSize => 4096;

  @override
  int get maxSpritesPerTick => _budget;

  @override
  Duration get fixedTimeStep => _step;

  @override
  GameState2D<_BudgetGame> createState() => _BudgetState();
}

Future<_BudgetGame> _game() async {
  final game = await Game.startInline(_BudgetGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  // The decode is still in flight when `start` resolves - `loadScene`'s
  // readiness future has nowhere to be returned from a void `onMounted`.
  // Awaiting the same key is free and keeps it from landing after teardown.
  await game.assets.load(_panelTextureKey);
  return game;
}

GameRenderer2D get _renderer => run.state.getSystem<GameRenderer2D>();

_BudgetScene get _scene => run.state.singleScene<_BudgetScene>();

/// The colour of every record in the published batch, in draw order.
///
/// Colour is the identity here: each archetype declares its own, so counting
/// them is how "which archetype survived the budget" is asked.
List<int> _batchColors(_BudgetGame game) {
  final buffer = _renderer.framesFor(game.view).buffer;
  final slot = buffer.beginRead();
  if (slot == null) return const <int>[];
  final used = buffer.readUsedBytes;
  final batch = ByteData.sublistView(slot.asTypedList(used));
  final colors = <int>[];
  var offset = DrawData2D.batchHeaderBytes;
  final count = const DrawSpriteData2D().itemCount(used);
  for (var i = 0; i < count; i++) {
    colors.add(batch.getUint32(offset + 32, Endian.little));
    offset += DrawSpriteData2D.strideBytes;
  }
  return colors;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the record budget', () {
    test('a frame inside the budget reports no shortfall', () async {
      final game = await _game();
      final scene = _scene;
      for (var i = 0; i < 20; i++) {
        scene.add(scene.first);
      }
      for (var i = 0; i < 20; i++) {
        scene.add(scene.second);
      }
      run.state.advance(_step);

      expect(_renderer.lastRecordCount, 40);
      expect(
        _renderer.lastRecordsOverBudget,
        0,
        reason:
            'the control for every expectation below - 40 of a 64 budget '
            'fits, so a non-zero shortfall here would mean the counter '
            'reports one whether or not anything was turned away',
      );
      expect(_batchColors(game), hasLength(40));
    });

    test('an over-budget frame reports the whole shortfall', () async {
      final game = await _game();
      final scene = _scene;
      for (var i = 0; i < 50; i++) {
        scene.add(scene.first);
      }
      for (var i = 0; i < 50; i++) {
        scene.add(scene.second);
      }
      run.state.advance(_step);

      expect(_renderer.lastRecordCount, _budget);
      expect(
        _renderer.lastRecordsOverBudget,
        36,
        reason:
            'the scene asked for 100 records against a budget of 64, so 36 '
            'did not fit. Not "at least 1", and not the 9 or 1 of whichever '
            'candidate happened to trip the limit: the fill pass finishes '
            'its walk counting what it turns away, because a game that is '
            '36 over needs to raise the budget by 36',
      );
      expect(
        _renderer.lastRecordCount + _renderer.lastRecordsOverBudget,
        100,
        reason: 'drawn plus turned away is what the scene asked for',
      );
      expect(
        _renderer.lastWriteDropped,
        isFalse,
        reason:
            'a spent budget is not a busy handoff slot. Conflating the two '
            'would send a game looking for a frame-pacing problem it does '
            'not have - #175 was invisible partly because this flag looked '
            'like it might already cover it',
      );

      final colors = _batchColors(game);
      expect(colors, hasLength(_budget));
      expect(
        colors.where((c) => c == _firstColor).length,
        50,
        reason:
            'the first-registered archetype is encountered first and keeps '
            'everything it asked for',
      );
      expect(
        colors.where((c) => c == _secondColor).length,
        14,
        reason:
            'and the second one loses 36 of its 50 - not because it is '
            'further away or less important, but because its archetype was '
            'declared later. Pinned rather than endorsed: choosing what to '
            'drop is the other half of #175, and when that lands this '
            'number is what has to change with it',
      );
    });

    test('the shortfall counts records, not sprites', () async {
      await _game();
      final scene = _scene;
      for (var i = 0; i < 60; i++) {
        scene.add(scene.first);
      }
      // One nine-sliced sprite: 9 records against the 4 left of the budget.
      scene.add(scene.panel);
      run.state.advance(_step);

      expect(_renderer.lastRecordCount, 60);
      expect(
        _renderer.lastSpriteCount,
        60,
        reason: 'the panel is one sprite and none of it was drawn',
      );
      expect(
        _renderer.lastRecordsOverBudget,
        9,
        reason:
            'a refused nine-sliced sprite is nine records short, not one. '
            'Counting it as one would understate what raising the budget '
            'has to cover, which is the same error that made counting '
            'sprites instead of records overrun the scratch',
      );
    });

    test('nothing slips in behind a candidate the budget refused', () async {
      final game = await _game();
      final scene = _scene;
      for (var i = 0; i < 60; i++) {
        scene.add(scene.first);
      }
      scene.add(scene.panel);
      scene.add(scene.second);
      run.state.advance(_step);

      final colors = _batchColors(game);
      expect(
        colors.where((c) => c == _secondColor),
        isEmpty,
        reason:
            'the panel needed 9 and left 60 of 64 spent, so a 1-record '
            'sprite behind it would still have fit. It is refused anyway: '
            'once the budget trips the pass admits nothing more, which is '
            'exactly what the `break outer` that used to be here did. #175 '
            'is about reporting the drop policy, not changing it',
      );
      expect(_renderer.lastRecordCount, 60);
      expect(
        _renderer.lastRecordsOverBudget,
        10,
        reason: 'nine for the panel and one for the quad behind it',
      );
    });

    test('the shortfall is cleared by the next frame that fits', () async {
      await _game();
      final scene = _scene;
      final over = <Entity>[];
      for (var i = 0; i < 100; i++) {
        over.add(scene.add(scene.first));
      }
      run.state.advance(_step);
      expect(_renderer.lastRecordsOverBudget, 36);

      // Between ticks, so the write lands in an open tick rather than in a
      // slot the next `beginTick` would copy over - see `data_layout.dart`'s
      // assertion. Every other write in this file happens before the first
      // tick, where that is not yet a concern.
      final pool = run.state.scene!.pool;
      pool.beginTick();
      for (var i = 0; i < 90; i++) {
        scene.first.quad.visible[over[i]] = false;
      }
      pool.commitTick();

      run.state.advance(_step);
      expect(
        _renderer.lastRecordsOverBudget,
        0,
        reason:
            'it describes the last frame, like every other `last*` field on '
            'the renderer - a latch would report a scene that has since '
            'been fixed',
      );
    });
  });
}
