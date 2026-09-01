// What happens when a frame asks for more records than `maxSpritesPerTick`
// allows (#175).
//
// The excess used to disappear with nothing anywhere saying so:
// `lastWriteDropped` is about the handoff slot and stayed false, and no
// counter existed. `GameRenderer2D.lastRecordsOverBudget` is that number now.
//
// And what disappeared was decided by archetype registration order. The budget
// is spent after the sort now, walking from the camera backwards, so a frame
// that cannot fit loses its furthest layers and keeps everything in front of
// them - and the survivors are a contiguous depth slab, never a front layer
// with a hole punched through it.
//
// Most tests here run against a budget of 64 records rather than the default,
// so "over budget" is reachable from a hundred entities instead of seventeen
// thousand. The mechanism is the same at either size.
//
// Two archetypes with different `zIndex`, deliberately: a single-archetype
// scene at one depth has nothing for the drop policy to get wrong, so it would
// pass against any policy at all and could not tell one from another.

import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

/// The live run under test - one inline run per isolate, so one binding, and
/// [_game] stops whatever was up before it starts another.
Game? _run;

Game get run => _run!;

const Duration _step = Duration(milliseconds: 10);

/// The record budget most games in this file declare.
const int _budget = 64;

/// Room for every scene here, for the runs that need to measure what a scene
/// asks for rather than assert a number somebody typed.
const int _roomyBudget = 256;

const int _firstColor = 0xFF00FF00;
const int _secondColor = 0xFFFF0000;
const int _panelColor = 0xFF0000FF;
const int _barColor = 0xFF00FFFF;
const int _columnColor = 0xFFFF00FF;

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

/// The batch a scene of twenty records published on `fedd772`, the commit
/// before the budget moved after the sort.
///
/// Captured by dumping the slot on that commit and pasted here unaltered.
/// Twenty records is comfortably under the 64 this file budgets, so the trim
/// returns on its first comparison and every byte below has to come out the
/// same - which is the regression that matters most, because it is the frame
/// every game renders every tick.
const String _fittingFrameGolden =
    'AQAAAAAAAAAAAIDAAACAwAAAgEAAAIDAAACAQAAAgEAAAIDAAACAQAD/AP//////'
    'AAAAAAAAAAAAAIA/AAAAAAAAgD8AAIA/AAAAAAAAgD8CAAAA7uOfQD6yuD5uOkpB'
    'JTgAwAkOcEHcdLRAJIvrQAkOAEEA/wD//////wAAAAAAAAAAAACAPwAAAAAAAIA/'
    'AACAPwAAAAAAAIA/AgAAAJkKZ0GboZ5AmVeoQStT4T6zesxBZV7hQGeol0Fn9ThB'
    'AP8A//////8AAAAAAAAAAAAAgD8AAAAAAACAPwAAgD8AAAAAAACAPwIAAADCCsNB'
    'klkaQTfT6kEPVlhAn3oOQm6mBUHJLPVBfOppQQD/AP//////AAAAAAAAAAAAAIA/'
    'AAAAAAAAgD8AAIA/AAAAAAAAgD8CAAAAJ0oLQql1ZEGW4hZCNFHaQNm1NEJXihtB'
    'ah0pQrNriUEA/wD//////wAAAAAAAAAAAACAPwAAAAAAAIA/AACAPwAAAAAAAIA/'
    'AgAAAAAAoMEAAPzBAACAwQAA/MEAAIDBAADcwQAAoMEAANzB/wAA/wAAAAAAAAAA'
    'AAAAAAAAgD4AAAAAAACAPgAAgD4AAAAAAACAPgIAAAAAAIDBAAD8wQAAgEEAAPzB'
    'AACAQQAA3MEAAIDBAADcwf8AAP8AAAAAAACAPgAAAAAAAEA/AAAAAAAAQD8AAIA+'
    'AACAPgAAgD4CAAAAAACAQQAA/MEAAKBBAAD8wQAAoEEAANzBAACAQQAA3MH/AAD/'
    'AAAAAAAAQD8AAAAAAACAPwAAAAAAAIA/AACAPgAAQD8AAIA+AgAAAAAAoMEAANzB'
    'AACAwQAA3MEAAIDBAACQQAAAoMEAAJBA/wAA/wAAAAAAAAAAAACAPgAAgD4AAIA+'
    'AACAPgAAQD8AAAAAAABAPwIAAAAAAIDBAADcwQAAgEEAANzBAACAQQAAkEAAAIDB'
    'AACQQP8AAP8AAAAAAACAPgAAgD4AAEA/AACAPgAAQD8AAEA/AACAPgAAQD8CAAAA'
    'AACAQQAA3MEAAKBBAADcwQAAoEEAAJBAAACAQQAAkED/AAD/AAAAAAAAQD8AAIA+'
    'AACAPwAAgD4AAIA/AABAPwAAQD8AAEA/AgAAAAAAoMEAAJBAAACAwQAAkEAAAIDB'
    'AAAIQQAAoMEAAAhB/wAA/wAAAAAAAAAAAABAPwAAgD4AAEA/AACAPgAAgD8AAAAA'
    'AACAPwIAAAAAAIDBAACQQAAAgEEAAJBAAACAQQAACEEAAIDBAAAIQf8AAP8AAAAA'
    'AACAPgAAQD8AAEA/AABAPwAAQD8AAIA/AACAPgAAgD8CAAAAAACAQQAAkEAAAKBB'
    'AACQQAAAoEEAAAhBAACAQQAACEH/AAD/AAAAAAAAQD8AAEA/AACAPwAAQD8AAIA/'
    'AACAPwAAQD8AAIA/AgAAAAAAhsEAAKDBAABMwQAAoMEAAEzBAACgQQAAhsEAAKBB'
    '//8A/wAAAAAAAAAAAAAAAAAAgD4AAAAAAACAPgAAgD8AAAAAAACAPwIAAAAAAEzB'
    'AACgwQAAmkEAAKDBAACaQQAAoEEAAEzBAACgQf//AP8AAAAAAACAPgAAAAAAAEA/'
    'AAAAAAAAQD8AAIA/AACAPgAAgD8CAAAAAACaQQAAoMEAALpBAACgwQAAukEAAKBB'
    'AACaQQAAoEH//wD/AAAAAAAAQD8AAAAAAACAPwAAAAAAAIA/AACAPwAAQD8AAIA/'
    'AgAAAAAAgMAAAIDAAACAQAAAgMAAAIBAAACAQAAAgMAAAIBAAAD///////8AAAAA'
    'AAAAAAAAgD8AAAAAAACAPwAAgD8AAAAAAACAPwIAAAAAADDBAACAwAAAQMAAAIDA'
    'AABAwAAAgEAAADDBAACAQAAA////////AAAAAAAAAAAAAIA/AAAAAAAAgD8AAIA/'
    'AAAAAAAAgD8CAAAAAACQwQAAgMAAACDBAACAwAAAIMEAAIBAAACQwQAAgEAAAP//'
    '/////wAAAAAAAAAAAACAPwAAAAAAAIA/AACAPwAAAAAAAIA/AgAAAA==';

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
/// Higher `zIndex` and registered later is the combination that matters, and
/// it is the shape of the scene #175 was filed about: a tilemap declared first
/// and the player declared last. Spending the budget in encounter order made
/// the player the thing that vanished. Spending it in depth order makes the
/// player the last thing to go.
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
  final skin = Asset.of(_panelTextureKey);
  late final Sprite frame;

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

/// Sliced on the horizontal axis only - a capsule button, a progress bar, a
/// panel that stretches sideways. Three records, not nine: with nothing
/// declared top or bottom, two of the four horizontal grid lines coincide and
/// the writer has always skipped the rows they bound.
///
/// The whole of #252 is that the fill pass charged this nine.
class _Bar extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  final skin = Asset.of(_panelTextureKey);
  late final Sprite bar;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    bar = descriptor.has(
      texture: skin,
      width: 40,
      height: 40,
      color: _barColor,
      nineSliceBorder: const NineSliceBorder(
        left: 0.25,
        right: 0.25,
        insetLeft: 4,
        insetRight: 4,
      ),
    );
  }
}

/// The same shape turned ninety degrees: sliced top and bottom only, so it is
/// the *columns* that coincide. Here to keep the count from being right for
/// one axis by accident - a fix that counted rows and applied the answer to
/// both would pass [_Bar] and fail this.
class _Column extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  final skin = Asset.of(_panelTextureKey);
  late final Sprite bar;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    bar = descriptor.has(
      texture: skin,
      width: 40,
      height: 40,
      color: _columnColor,
      nineSliceBorder: const NineSliceBorder(
        top: 0.25,
        bottom: 0.25,
        insetTop: 4,
        insetBottom: 4,
      ),
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
  late final _Bar bar;
  late final _Column column;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    // Declaration order is archetype order is fill order. The whole file
    // depends on it, so it is stated once, here.
    first = descriptor.has(_First.new);
    panel = descriptor.has(_Panel.new);
    second = descriptor.has(_Second.new);
    // Appended, so the three above keep the encounter order the equal-`zIndex`
    // tie-break puts them in.
    bar = descriptor.has(_Bar.new);
    column = descriptor.has(_Column.new);
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

/// What the next [_game] will declare as its budget, or null for the engine
/// default.
///
/// A top-level variable and not a constructor argument because
/// `maxSpritesPerTick` sizes the handoff slots during boot and their addresses
/// cross to the game isolate at spawn - so it has to be settled before
/// `startInline` and cannot move while a run is up.
int? _declaredBudget = _budget;

class _BudgetGame extends Game2D {
  CameraView get view => defaultCamera;

  @override
  int get pageSize => 4096;

  // Raised only for the default-budget test, which needs five thousand
  // entities to get past 4096 records with plain quads. Pages are allocated
  // on demand, so this costs the other tests here nothing.
  @override
  int get maxPages => 1024;

  @override
  int get maxSpritesPerTick => _declaredBudget ?? super.maxSpritesPerTick;

  @override
  Duration get fixedTimeStep => _step;

  @override
  GameState2D<_BudgetGame> createState() => _BudgetState();
}

/// Boots a run declaring [budget] records, stopping whatever was up first.
///
/// `budget: null` takes the engine's own default, which is the only way to
/// assert on it.
Future<_BudgetGame> _game({int? budget = _budget}) async {
  await _stop();
  _declaredBudget = budget;
  final game = await Game.startInline(_BudgetGame.new);
  _run = game;
  addTearDown(_stop);
  // The decode is still in flight when `start` resolves - `loadScene`'s
  // readiness future has nowhere to be returned from a void `onMounted`.
  // Awaiting the same key is free and keeps it from landing after teardown.
  await game.assets.load(_panelTextureKey);
  return game;
}

Future<void> _stop() async {
  final current = _run;
  _run = null;
  if (current != null && current.isRunning) await current.stop();
}

GameRenderer2D get _renderer => run.state.getSystem<GameRenderer2D>();

_BudgetScene get _scene => run.state.singleScene<_BudgetScene>();

/// A scene of 79 records across four archetypes and two depths - plain quads,
/// full nine-slices and three-sliced bars, so the trim has to get
/// all-or-nothing right on a sliced candidate and not only on a quad.
///
/// Built twice by the shortfall test, against two different budgets, so it is
/// one function and not two copies that could drift.
void _mixedScene() {
  final scene = _scene;
  for (var i = 0; i < 30; i++) {
    scene.add(scene.first);
  }
  for (var i = 0; i < 3; i++) {
    scene.add(scene.panel);
  }
  for (var i = 0; i < 4; i++) {
    scene.add(scene.bar);
  }
  for (var i = 0; i < 10; i++) {
    scene.add(scene.second);
  }
}

/// The published batch, byte for byte as it crossed to main.
///
/// Reads the slot, so it is called once per frame under test - [_batchColors]
/// goes through it rather than reading the slot a second time.
Uint8List _batchBytes(_BudgetGame game) {
  final buffer = _renderer.framesFor(game.view).buffer;
  final slot = buffer.beginRead();
  if (slot == null) return Uint8List(0);
  return Uint8List.fromList(slot.asTypedList(buffer.readUsedBytes));
}

/// The colour of every record in [batch], in draw order.
///
/// Colour is the identity here: each archetype declares its own, so reading
/// them off in order is how "which sprites survived the budget, and in what
/// depth order" is asked. A count on its own cannot tell one drop set from
/// another.
List<int> _colorsOf(Uint8List batch) {
  final view = ByteData.sublistView(batch);
  final colors = <int>[];
  var offset = DrawData2D.batchHeaderBytes;
  final count = const DrawSpriteData2D().itemCount(batch.length);
  for (var i = 0; i < count; i++) {
    colors.add(view.getUint32(offset + 32, Endian.little));
    offset += DrawSpriteData2D.strideBytes;
  }
  return colors;
}

List<int> _batchColors(_BudgetGame game) => _colorsOf(_batchBytes(game));

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

    test('a frame that fits publishes the bytes it always did', () async {
      final game = await _game();
      final scene = _scene;
      // Offsets and rotations that differ per entity, so the golden pins
      // geometry and not twenty copies of one quad at the origin.
      for (var i = 0; i < 5; i++) {
        final entity = scene.add(scene.first);
        scene.first.transformOffsetX[entity] = i * 10.0;
        scene.first.transformOffsetY[entity] = -i * 3.0;
        scene.first.transformRotation[entity] = i * 0.3;
      }
      for (var i = 0; i < 3; i++) {
        final entity = scene.add(scene.second);
        scene.second.transformOffsetX[entity] = i * -7.0;
      }
      final panel = scene.add(scene.panel);
      scene.panel.transformOffsetY[panel] = 11.5;
      final bar = scene.add(scene.bar);
      scene.bar.transformOffsetX[bar] = 3.25;
      run.state.advance(_step);

      final bytes = _batchBytes(game);
      expect(
        base64Encode(bytes),
        _fittingFrameGolden,
        reason:
            'moving the budget after the sort must not move one byte of a '
            'frame that fits. Header, order, geometry, colours, UVs - all '
            'of it, against a capture taken before the change. Counts would '
            'not have caught a reordered batch or a shifted field',
      );
      expect(_renderer.lastRecordCount, 20);
      expect(_renderer.lastSpriteCount, 10);
      expect(_renderer.lastRecordsOverBudget, 0);
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
        colors.where((c) => c == _secondColor).length,
        50,
        reason:
            'the near layer is walked first and keeps everything it asked '
            'for. This read 14 until #175 landed, because the budget was '
            'spent in archetype registration order and this archetype was '
            'registered second',
      );
      expect(
        colors.where((c) => c == _firstColor).length,
        14,
        reason:
            'and the far layer loses 36 of its 50, because it is the far '
            'layer. The policy is depth now, not encounter order - the '
            'mirror image of what this file pinned before, and the number '
            'that says so',
      );
      expect(
        colors.sublist(0, 14).every((c) => c == _firstColor),
        isTrue,
        reason:
            'draw order still runs back to front, so what survived of the '
            'far layer is written first',
      );
      expect(
        colors.sublist(14).every((c) => c == _secondColor),
        isTrue,
        reason:
            'and the near layer after it, whole. Asserted on the batch and '
            'not on two counts, because two counts pass against a batch '
            'that interleaved them',
      );
    });

    test('the near layer survives when the far one cannot fit', () async {
      final game = await _game();
      final scene = _scene;
      // The scene #175 was filed about, in miniature: a map declared first,
      // and one player declared last and drawn on top of it.
      for (var i = 0; i < 70; i++) {
        scene.add(scene.first);
      }
      scene.add(scene.second);
      run.state.advance(_step);

      final colors = _batchColors(game);
      expect(colors, hasLength(_budget));
      expect(
        colors.last,
        _secondColor,
        reason:
            'the player is drawn. It was the one thing missing from this '
            'frame before #175 landed: 70 tiles filled the budget in '
            'encounter order and the player, registered last, was refused '
            'with 6 records of tile to spare',
      );
      expect(
        colors.where((c) => c == _secondColor).length,
        1,
        reason: 'one player, drawn once',
      );
      expect(
        colors.where((c) => c == _firstColor).length,
        63,
        reason: 'and the map loses seven tiles instead',
      );
      expect(_renderer.lastRecordsOverBudget, 7);
    });

    test('a sprite behind a refused one is refused too', () async {
      final game = await _game();
      final scene = _scene;
      // Front to back: 60 quads, then a panel that will not fit, then a
      // single quad that would.
      for (var i = 0; i < 60; i++) {
        scene.add(scene.first);
      }
      final panel = scene.add(scene.panel);
      scene.panel.frame.zIndex[panel] = -10;
      final behind = scene.add(scene.second);
      scene.second.quad.zIndex[behind] = -20;
      run.state.advance(_step);

      final colors = _batchColors(game);
      expect(
        colors.where((c) => c == _panelColor),
        isEmpty,
        reason: 'the panel needed 9 records and 4 were left',
      );
      expect(
        colors.where((c) => c == _secondColor),
        isEmpty,
        reason:
            'and the quad behind it is refused as well, though one record '
            'would have held it. Survivors are a contiguous depth slab: '
            'admitting this one would draw a background quad while the '
            'panel in front of it is missing, which is a worse frame than '
            'a missing back layer, not a better one',
      );
      expect(colors, hasLength(60));
      expect(
        _renderer.lastRecordsOverBudget,
        10,
        reason: 'nine for the panel and one for the quad behind it',
      );
    });

    test('the shortfall is what the trim took out of the batch', () async {
      // What the scene asked for is measured here, not declared: the same
      // scene is drawn once with room for all of it and once without, and the
      // difference between the two batches is what the shortfall has to be.
      // A literal is what let the charge and the batch drift apart in #252.
      final roomy = await _game(budget: _roomyBudget);
      _mixedScene();
      run.state.advance(_step);
      final whole = _batchColors(roomy).length;
      expect(_renderer.lastRecordsOverBudget, 0);
      expect(_renderer.lastRecordCount, whole);

      final tight = await _game();
      _mixedScene();
      run.state.advance(_step);
      final drawn = _batchColors(tight).length;

      expect(
        _renderer.lastRecordCount,
        drawn,
        reason: 'the charge is the batch, over budget as well as under it',
      );
      expect(
        _renderer.lastRecordsOverBudget,
        whole - drawn,
        reason:
            'the shortfall is exactly the records the trim took out, and '
            'both halves of that subtraction came off a published batch',
      );
    });

    test('the shortfall counts records, not sprites', () async {
      await _game();
      final scene = _scene;
      for (var i = 0; i < 60; i++) {
        scene.add(scene.first);
      }
      // One nine-sliced sprite, behind all sixty: 9 records against the 4
      // the trim has left by the time it reaches that depth.
      final panel = scene.add(scene.panel);
      scene.panel.frame.zIndex[panel] = -10;
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

  // #252. `_isNineSliced` is true when *any* of the four insets is set, and
  // the charge was a flat 9 from there. But the writer skips a collapsed row
  // or column, and a sprite sliced on one axis has them by construction - so
  // a three-sliced capsule button was charged three times what it draws, and
  // a frame of ten of them dropped three panels with 34 records to spare.
  //
  // Every test here asserts the charge against `_batchColors(game).length` -
  // the records actually in the published batch - and not against a literal.
  // A literal is what let the two drift apart in the first place: it pins
  // what someone believed on the day, where the invariant is that the number
  // the budget is spent against is the number the buffer holds.
  group('the nine-slice charge', () {
    test('a sprite sliced on one axis is charged what it draws', () async {
      final game = await _game();
      final scene = _scene;
      scene.add(scene.bar);
      run.state.advance(_step);

      final colors = _batchColors(game);
      expect(
        colors,
        hasLength(3),
        reason:
            'left corner, stretched middle, right corner - the top and '
            'bottom rows are collapsed, so the writer never emitted them',
      );
      expect(
        _renderer.lastRecordCount,
        colors.length,
        reason:
            'the charge is the batch. It read 9 against a batch of 3 before '
            'this fix, which is what made `lastRecordCount` disagree with '
            'its own doc',
      );
      expect(_renderer.lastSpriteCount, 1);
      expect(_renderer.lastRecordsOverBudget, 0);
    });

    test('and the same sliced on the other axis', () async {
      final game = await _game();
      final scene = _scene;
      scene.add(scene.column);
      run.state.advance(_step);

      final colors = _batchColors(game);
      expect(colors, hasLength(3));
      expect(_renderer.lastRecordCount, colors.length);
      expect(
        colors.every((c) => c == _columnColor),
        isTrue,
        reason:
            'three cells of one column. Here so a count that got rows right '
            'and applied the answer to both axes cannot pass',
      );
    });

    test('a full nine-slice is still charged nine', () async {
      final game = await _game();
      final scene = _scene;
      scene.add(scene.panel);
      run.state.advance(_step);

      final colors = _batchColors(game);
      expect(
        colors,
        hasLength(9),
        reason:
            'insets on all four edges of a 40x40 sprite leave every row and '
            'every column live - the behaviour #252 must not move',
      );
      expect(_renderer.lastRecordCount, colors.length);
      expect(_renderer.lastSpriteCount, 1);
    });

    test('ten three-sliced panels fit a budget with room to spare', () async {
      final game = await _game();
      final scene = _scene;
      for (var i = 0; i < 10; i++) {
        scene.add(scene.bar);
      }
      run.state.advance(_step);

      final colors = _batchColors(game);
      expect(
        _renderer.lastSpriteCount,
        10,
        reason:
            'this frame reported 7 sprites and dropped three panels, out of '
            'a 64-record budget it was using 30 of. That is #252 as a player '
            'sees it: panels missing from a UI that fits',
      );
      expect(colors, hasLength(30));
      expect(_renderer.lastRecordCount, colors.length);
      expect(
        _renderer.lastRecordsOverBudget,
        0,
        reason:
            'and it reported a shortfall of 27 against a true shortfall of '
            'zero, so `maxSpritesPerTick += lastRecordsOverBudget` - the '
            'documented fix - raised a knob that was never the problem',
      );
    });

    test('the charge equals the batch across a mixed frame', () async {
      final game = await _game();
      final scene = _scene;
      for (var i = 0; i < 5; i++) {
        scene.add(scene.first);
      }
      scene.add(scene.panel);
      for (var i = 0; i < 3; i++) {
        scene.add(scene.bar);
      }
      for (var i = 0; i < 2; i++) {
        scene.add(scene.column);
      }
      run.state.advance(_step);

      final colors = _batchColors(game);
      expect(
        _renderer.lastRecordCount,
        colors.length,
        reason:
            'the invariant, over four archetypes at once: whatever the fill '
            'pass charged is what the write pass wrote',
      );
      expect(
        colors,
        hasLength(5 + 9 + 3 * 3 + 2 * 3),
        reason:
            'five plain quads, one full nine-slice, three horizontal bars '
            'and two vertical ones',
      );
      expect(_renderer.lastRecordsOverBudget, 0);
      expect(_renderer.lastSpriteCount, 11);
    });

    test('the charge equals the batch when the budget closes', () async {
      final game = await _game();
      final scene = _scene;
      for (var i = 0; i < 62; i++) {
        scene.add(scene.first);
      }
      // Behind all 62, so the trim reaches it with two records left - and a
      // bar wants three, so it is refused whole.
      final bar = scene.add(scene.bar);
      scene.bar.bar.zIndex[bar] = -10;
      run.state.advance(_step);

      final colors = _batchColors(game);
      expect(_renderer.lastRecordCount, colors.length);
      expect(colors, hasLength(62));
      expect(
        _renderer.lastRecordsOverBudget,
        3,
        reason:
            'the shortfall is what the refused sprite would have drawn. '
            'Three, not nine: raising the budget by nine to fit a bar that '
            'needs three is the wrong number even when it happens to work',
      );
      expect(
        _renderer.lastSpriteCount,
        62,
        reason:
            'all-or-nothing still holds - a sliced sprite is admitted only '
            'if every one of its records fits, because admitting it '
            'partially would write past the scratch',
      );
    });

    test('a sprite scaled to nothing is skipped, not charged', () async {
      final game = await _game();
      final scene = _scene;
      final entity = scene.add(scene.panel);
      scene.panel.transformScaleX[entity] = 0;
      scene.panel.transformScaleY[entity] = 0;
      run.state.advance(_step);

      expect(
        _batchColors(game),
        isEmpty,
        reason:
            'every grid line lands on the same point, so all nine cells are '
            'collapsed and the writer emits nothing',
      );
      expect(_renderer.lastRecordCount, 0);
      expect(
        _renderer.lastSpriteCount,
        0,
        reason: 'a sprite that draws no records is not a drawn sprite',
      );
      expect(_renderer.lastRecordsOverBudget, 0);
    });

    test('a zero-record sprite is never queued at all', () async {
      final game = await _game();
      final scene = _scene;
      for (var i = 0; i < 60; i++) {
        scene.add(scene.first);
      }
      // Both behind the sixty. The full-scale one is refused; the collapsed
      // one never reaches the queue.
      final refused = scene.add(scene.panel);
      scene.panel.frame.zIndex[refused] = -10;
      final collapsed = scene.add(scene.panel);
      scene.panel.frame.zIndex[collapsed] = -10;
      scene.panel.transformScaleX[collapsed] = 0;
      scene.panel.transformScaleY[collapsed] = 0;
      run.state.advance(_step);

      expect(
        _renderer.lastSpriteCount,
        60,
        reason:
            'the collapsed panel costs 0 records, so the trim can never be '
            'the thing that stops on it - `admitted + 0 > limit` is false '
            'however little room is left. Queued, it would be admitted from '
            'behind a refused sprite and counted as drawn while drawing '
            'nothing. It is skipped in the fill pass instead',
      );
      expect(_batchColors(game), hasLength(60));
      expect(_renderer.lastRecordCount, 60);
      expect(
        _renderer.lastRecordsOverBudget,
        9,
        reason:
            'nine for the full-scale panel that was refused, and nothing '
            'for the collapsed one - it asked for nothing, so nothing was '
            'turned away',
      );
    });
  });

  // The default itself. 4096 was a figure a first tilemap walked past on its
  // first frame - a full-screen layer of 16 px tiles is 8228 records, and
  // #252 does not touch that, since tiles are not sliced.
  group('the default budget', () {
    test('draws a scene the old default would have clipped', () async {
      final game = await _game(budget: null);
      final scene = _scene;
      for (var i = 0; i < 5000; i++) {
        scene.add(scene.first);
      }
      run.state.advance(_step);

      expect(
        game.maxSpritesPerTick,
        16384,
        reason: '3.56 MiB reserved per view, against 0.89 MiB at 4096',
      );
      expect(
        _renderer.lastRecordsOverBudget,
        0,
        reason:
            '5000 records is past the 4096 this used to default to, so a '
            'scene this size lost 904 of them - and being told nothing is '
            'what #175 was filed about',
      );
      expect(_renderer.lastRecordCount, 5000);
      expect(_batchColors(game), hasLength(5000));
    });
  });
}
