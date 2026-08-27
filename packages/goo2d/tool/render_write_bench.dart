// Where does `GameRenderer2D`'s write pass actually spend its 415 ns/sprite?
//
//   cd packages/goo2d && flutter test tool/render_write_bench.dart
//
// Deliberately **not** in `test/`: this is a measurement, not an assertion, and
// a bench that fails the suite on a slow machine is worse than no bench. Same
// placement and same reasoning as `world_transform_bench.dart`, which this
// borrows its harness shape from.
//
// # What it exists to answer
//
// A device recording of the Galaxy case at 20,000 entities put `present` at
// 14.26 ms of a 23.66 ms frame, and its `write` phase alone at 8.30 ms - about
// 415 ns per sprite, the single largest item in the frame. The standing
// hypothesis was "too many per-sprite component reads: hoist the
// archetype-constant ones (pivot, border) out of the loop". That hypothesis
// prices ~8 field reads at ~50 ns each, which is 20x what a field read costs
// (2.25 ns - `good/tool/column_dispatch_bench.dart`). So it cannot be the whole
// story and probably is not any of it.
//
// The competing explanation is **access order**. The walk pass iterates rows in
// page order and costs 2.74 ms; the write pass iterates the same rows in
// *z-sorted* order and costs 8.30 ms. In the Galaxy case `zIndex` is
// `4000 - radius`, and radius comes off a low-discrepancy sequence over the
// spawn index - so z order is essentially a random permutation of row order,
// and every sprite's 300-byte row is a fresh cache miss.
//
// # The ablation, and how it can fail
//
// Four loops over the *same live entities*, each timed separately:
//
//   rowOrder    - the write pass's 13 field reads, in page order
//   zOrder      - the identical reads, in z-sorted order
//   zOrder+trig - and the two `math.cos`/`math.sin` calls
//   zOrder+quad - and `DrawSpriteData2D.writeQuad`'s 18 ByteData stores
//
// Each stage adds exactly one thing, so a stage's cost is its delta from the
// previous one. **This bench can report a negative as easily as a positive**:
// if row order and z order come out equal, the ordering hypothesis is dead and
// the cost is in the arithmetic or the stores, which the last two stages then
// price directly. That is the property `bench-must-be-able-to-fail` is about -
// the setup does not decide the answer, because both orders walk the same rows
// the same number of times and differ in nothing but the permutation.
//
// The end-to-end numbers come from the real `GameRenderer2D`'s own counters, so
// the ablation is always checkable against the thing it claims to explain: the
// four stages should add up to roughly the reported `write`.
//
// `flutter test` is JIT with optimisation on, which is close enough for a
// *shape* even though absolute numbers will not match a profile build.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

/// Generous, and it has to be: the **first** cell in the process pays to
/// JIT-compile the renderer's loops, and the fill pass is now a large body
/// (every sprite's geometry is computed there). At 30 warm ticks the 5,000
/// cell reported `walk` at 215 ns/sprite against the 20,000 cell's 137 - the
/// smaller scene looking 1.6x *more* expensive per sprite, which is
/// compilation and not cost. Same trap as the ablation stages below; see
/// [_time].
const int _warmTicks = 150;
const int _timedTicks = 60;

/// Ablation passes per stage. The stages are cheap next to a whole tick, so
/// they get their own repeat count to keep the timer resolution honest.
const int _ablationPasses = 20;

/// Timed rounds per stage; the best one is reported. See [_time].
const int _ablationRounds = 5;

const List<int> _counts = <int>[5000, 20000, 40000];

const Duration _step = Duration(milliseconds: 16);

/// Mirrors the Galaxy demo's `Mote` field-for-field: same mixins in the same
/// order, the same six extra `float64`s, one sprite. The row stride is what
/// makes a random-order walk expensive, so it has to match the thing being
/// explained rather than be a lean stand-in.
///
/// No `WorldTransform2D` and no `Child`, exactly as in the demo - a particle is
/// never parented, so the renderer reads its local `Transform2D` directly.
class _Mote extends EntityStruct
    with Transform2D, Renderable2D, EntityLifecycleListener {
  late final Sprite body;

  final angle = Field.float64();
  final radius = Field.float64();
  final spin = Field.float64();
  final life = Field.float64();
  final lifespan = Field.float64();
  final baseSize = Field.float64();

  int _spawned = 0;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    body = descriptor.has(width: 14, height: 14);
  }

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    final i = _spawned++;
    final t = i * 2.39996322972865332;
    final u = (i * 0.6180339887498949) % 1.0;
    final r = 70 + 380 * math.sqrt(u);
    angle[entity] = t;
    radius[entity] = r;
    transformOffsetX[entity] = math.cos(t) * r;
    transformOffsetY[entity] = math.sin(t) * r;
    transformRotation[entity] = -t * 2;
    body
      ..width[entity] = 8
      ..height[entity] = 8
      // The demo's own key: `4000 - radius`, over a radius drawn from a
      // low-discrepancy sequence on the spawn index. That is what makes z order
      // a near-random permutation of row order, which is the whole point.
      ..zIndex[entity] = 4000 - r.round();
  }
}

class _Galaxy extends SceneStruct {
  late final _Mote mote;
  late Scene handle;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    mote = descriptor.has(_Mote.new);
  }

  @override
  void onSceneMounted(Scene scene) => handle = scene;
}

/// Exists only to own a query the ablation borrows. Declares no tick phase,
/// so it costs the timed ticks nothing.
class _Probe extends GameSystem {
  final renderables = Query.all(Renderable2D, Transform2D);
}

class _BenchState extends GameState2D<_Bench> {
  final _Galaxy galaxy = _Galaxy();

  @override
  void onMounted() => loadScene(galaxy);

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_Probe.new);
  }
}

class _Bench extends Game2D {
  @override
  int get pageSize => 1 << 20;

  @override
  int get maxSpritesPerTick => 48000;

  @override
  Duration get fixedTimeStep => _step;

  @override
  _BenchState createState() => _BenchState();
}

/// One `(count)` cell: the renderer's own phase costs plus the ablation.
class _Cell {
  _Cell({
    required this.rowOrder,
    required this.zOrder,
    required this.zTrig,
    required this.zQuad,
  });

  /// ns per sprite, from the ablation loops.
  final double rowOrder;
  final double zOrder;
  final double zTrig;
  final double zQuad;
}

/// Sink for the ablation stages, so nothing they compute is dead code the
/// compiler can delete - which would make every stage report zero and read
/// exactly like "the reads are free".
double _sink = 0;

/// The write pass's field reads for one sprite, and nothing else.
///
/// Deliberately the same 13 reads in the same order as `_renderView`'s loop:
/// width, height, rotation, x, y, four pivot fields, two scales, texture,
/// colour. Summed into [_sink] so the loop cannot be optimised away.
@pragma('vm:never-inline')
double _readFields(
  Sprite sprite,
  Transform2D transform,
  List<Entity> entities,
  Int32List order,
  int count,
) {
  var acc = 0.0;
  for (var i = 0; i < count; i++) {
    final entity = entities[order[i]];
    final width = sprite.width[entity];
    final height = sprite.height[entity];
    acc += width + height;
    acc += transform.transformRotation[entity];
    acc += transform.transformOffsetX[entity];
    acc += transform.transformOffsetY[entity];
    acc += sprite.pivotFractionX[entity] * width + sprite.pivotOffsetX[entity];
    acc += sprite.pivotFractionY[entity] * height + sprite.pivotOffsetY[entity];
    acc += transform.transformScaleX[entity];
    acc += transform.transformScaleY[entity];
    acc += sprite.texture[entity] == null ? 0 : 1;
    acc += sprite.color[entity];
  }
  return acc;
}

/// [_readFields] plus the two trig calls the write pass makes per sprite.
@pragma('vm:never-inline')
double _readFieldsAndTrig(
  Sprite sprite,
  Transform2D transform,
  List<Entity> entities,
  Int32List order,
  int count,
) {
  var acc = 0.0;
  for (var i = 0; i < count; i++) {
    final entity = entities[order[i]];
    final width = sprite.width[entity];
    final height = sprite.height[entity];
    acc += width + height;
    final rotation = transform.transformRotation[entity];
    acc += math.cos(rotation) + math.sin(rotation);
    acc += transform.transformOffsetX[entity];
    acc += transform.transformOffsetY[entity];
    acc += sprite.pivotFractionX[entity] * width + sprite.pivotOffsetX[entity];
    acc += sprite.pivotFractionY[entity] * height + sprite.pivotOffsetY[entity];
    acc += transform.transformScaleX[entity];
    acc += transform.transformScaleY[entity];
    acc += sprite.texture[entity] == null ? 0 : 1;
    acc += sprite.color[entity];
  }
  return acc;
}

/// [_readFieldsAndTrig] plus the real `writeQuad` - i.e. the whole write pass,
/// reimplemented here so the stage deltas are attributable. If this stage does
/// not land near the renderer's own reported `write`, the ablation has drifted
/// from the thing it claims to model and none of the deltas mean anything.
@pragma('vm:never-inline')
double _fullWrite(
  Sprite sprite,
  Transform2D transform,
  List<Entity> entities,
  Int32List order,
  int count,
  ByteData view,
) {
  var offset = DrawData2D.batchHeaderBytes;
  for (var i = 0; i < count; i++) {
    final entity = entities[order[i]];
    final width = sprite.width[entity];
    final height = sprite.height[entity];
    final rotation = transform.transformRotation[entity];
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    final tx = transform.transformOffsetX[entity];
    final ty = transform.transformOffsetY[entity];
    final pivotX =
        sprite.pivotFractionX[entity] * width + sprite.pivotOffsetX[entity];
    final pivotY =
        sprite.pivotFractionY[entity] * height + sprite.pivotOffsetY[entity];
    final scaleX = transform.transformScaleX[entity];
    final scaleY = transform.transformScaleY[entity];
    final lx0 = -pivotX * scaleX;
    final lx1 = (width - pivotX) * scaleX;
    final ly0 = -pivotY * scaleY;
    final ly1 = (height - pivotY) * scaleY;
    final ax0 = lx0 * cos;
    final ax1 = lx1 * cos;
    final ay0 = lx0 * sin;
    final ay1 = lx1 * sin;
    final bx0 = ly0 * sin;
    final bx1 = ly1 * sin;
    final by0 = ly0 * cos;
    final by1 = ly1 * cos;
    final texture = sprite.texture[entity];
    final color = sprite.color[entity];
    final address = texture == null
        ? DrawSpriteData2D.noTexture
        : texture.pack();
    offset = DrawSpriteData2D.writeQuad(
      view,
      offset,
      tx + ax0 - bx0,
      ty + ay0 + by0,
      tx + ax1 - bx0,
      ty + ay1 + by0,
      tx + ax1 - bx1,
      ty + ay1 + by1,
      tx + ax0 - bx1,
      ty + ay0 + by1,
      color,
      textureAddress: address,
    );
  }
  return offset.toDouble();
}

/// Times [body] over [_ablationPasses] repeats, in ns per sprite.
///
/// **Every stage must be warmed before any stage is timed**, which is why
/// warming is [_warmAll]'s job and not this function's. Warming each stage
/// immediately before timing it is not enough: the first stage then pays for
/// JIT-compiling the shared `DataPointer` accessors that all four go through,
/// and reports it as its own cost. That is exactly what the first draft of this
/// bench did, and at 5,000 sprites it reported row order at 339 ns and z order
/// at 65 ns - the ordering hypothesis backwards, purely from compilation
/// landing in the first measurement.
/// Reports the **best** of [_ablationRounds] rounds, not the mean. A round can
/// only be inflated by something that is not the code under test - a GC, the
/// scheduler, another core stealing the cache - never deflated, so the minimum
/// is the closest estimate of the real cost and is far steadier round to round.
/// With the mean, the two-trig-call stage priced itself at +18 ns at 5,000
/// sprites and +124 ns at 20,000, which is noise wearing a result's clothes.
double _time(int count, double Function() body) {
  var best = double.infinity;
  for (var round = 0; round < _ablationRounds; round++) {
    final clock = Stopwatch()..start();
    for (var pass = 0; pass < _ablationPasses; pass++) {
      _sink += body();
    }
    clock.stop();
    final ns = clock.elapsedMicroseconds * 1000.0 / (_ablationPasses * count);
    if (ns < best) best = ns;
  }
  return best;
}

/// Runs every stage several times untimed, so the JIT has optimised all of
/// them - and the shared accessor code beneath them - before the clock starts
/// on any. See [_time].
void _warmAll(List<double Function()> stages) {
  for (var pass = 0; pass < 3; pass++) {
    for (final stage in stages) {
      _sink += stage();
    }
  }
}

Future<_Cell> _measure(int count) async {
  final game = await Game.startInline(_Bench());
  final state = game.state;
  final scene = state.singleScene<_Galaxy>();
  for (var i = 0; i < count; i++) {
    scene.handle.addEntity(scene.mote);
  }

  for (var i = 0; i < _warmTicks; i++) {
    state.advance(_step);
  }

  // The renderer no longer reports its own phase timings - the engine does not
  // carry a profiler. The ablation below measures the same three stages by
  // rebuilding them here, which is what this bench was always really doing;
  // the engine counters were a second, less controllable copy of it.
  final renderer = state.getSystem<GameRenderer2D>();
  var sprites = 0;
  for (var i = 0; i < _timedTicks; i++) {
    state.advance(_step);
    sprites += renderer.lastSpriteCount;
  }
  // A frame that drew nothing contributes no work and would deflate every
  // average, so the sweep is only meaningful if every tick drew every sprite.
  // This is also the guard that stops the bench quietly measuring an empty
  // scene and reporting it as "fast".
  expect(
    sprites,
    _timedTicks * count,
    reason: 'every timed tick must draw every sprite',
  );

  // --- the ablation ------------------------------------------------------
  //
  // Collect the live entities in page order, then build the z-sorted
  // permutation of them with the renderer's own key. Both orders index the
  // same `entities` list, so the two stages differ in the permutation and in
  // nothing else.
  final query = state.getSystem<_Probe>().renderables;
  final entities = <Entity>[];
  late Sprite sprite;
  late Transform2D transform;
  for (final group in query.groups()) {
    sprite = group.get<Renderable2D>().sprites[0];
    transform = group.get<Transform2D>();
    for (final entity in group) {
      entities.add(entity);
    }
  }
  expect(entities.length, count, reason: 'ablation must walk every entity');

  final rowOrder = Int32List(count);
  for (var i = 0; i < count; i++) {
    rowOrder[i] = i;
  }
  final zOrder = Int32List.fromList(rowOrder)
    ..sort((a, b) => sprite.zIndex[entities[a]] - sprite.zIndex[entities[b]]);

  final scratch = ByteData(DrawData2D.batchHeaderBytes + count * 72);

  double stageRow() =>
      _readFields(sprite, transform, entities, rowOrder, count);
  double stageZ() => _readFields(sprite, transform, entities, zOrder, count);
  double stageTrig() =>
      _readFieldsAndTrig(sprite, transform, entities, zOrder, count);
  double stageQuad() =>
      _fullWrite(sprite, transform, entities, zOrder, count, scratch);

  _warmAll(<double Function()>[stageRow, stageZ, stageTrig, stageQuad]);

  final cell = _Cell(
    rowOrder: _time(count, stageRow),
    zOrder: _time(count, stageZ),
    zTrig: _time(count, stageTrig),
    zQuad: _time(count, stageQuad),
  );

  await game.stop();
  return cell;
}

/// Each cell runs its own game in the same process, so the process-global
/// registries have to go back to empty between them.
void _resetRegistries() {
  // ignore: invalid_use_of_visible_for_testing_member
  SceneRegistry.reset();
  // ignore: invalid_use_of_visible_for_testing_member
  ArchetypeRegistry.reset();
  // ignore: invalid_use_of_visible_for_testing_member
  ComponentTypeRegistry.reset();
}

void main() {
  final results = <int, _Cell>{};

  for (final count in _counts) {
    test('$count sprites', () async {
      results[count] = await _measure(count);
      _resetRegistries();
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  tearDownAll(() {
    final report = StringBuffer()
      ..writeln(
        '\nns per sprite ($_timedTicks ticks, $_ablationPasses '
        'ablation passes)\n',
      )
      ..writeln('                    ablation stages')
      ..writeln('   sprites     row     z    +trig  +quad')
      ..writeln('   ${'-' * 44}');
    for (final count in _counts) {
      final cell = results[count];
      if (cell == null) continue;
      String n(double v) => v.toStringAsFixed(0).padLeft(6);
      report.writeln(
        '   ${count.toString().padLeft(7)}'
        '${n(cell.rowOrder)}${n(cell.zOrder)}${n(cell.zTrig)}'
        '${n(cell.zQuad)}',
      );
    }
    // Printed so the sink is genuinely *read*. One that is only ever assigned
    // is dead by definition - to the analyzer, which says so, and potentially
    // to the optimiser, which is the reason it exists at all.
    report.writeln('\n   sink: $_sink');
    // ignore: avoid_print
    print(report);
  });
}
