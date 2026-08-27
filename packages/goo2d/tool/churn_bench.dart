// Does a *fixed* population get slower the longer it churns?
//
//   flutter test packages/goo2d/tool/churn_bench.dart
//
// Reported from a device: the perf demo holds 20k entities via a spawn-rate
// slider and drops from 40fps to 4fps within about ten seconds. Population is
// constant the whole time, so per-entity cost cannot explain it - something has
// to be growing with *total spawns*, not with how many are alive.
//
// The cause, found here: `ArchetypeStorage.allocateRow`'s per-slot page cursor
// only ever moved *forward*. Once a page bump-filled, the next allocation made
// a fresh page current and the old one was never allocated from again, so every
// row later freed in it was stranded permanently. Live population stayed flat
// while the walked extent grew without bound - and both `MemoryPool.beginTick`
// (which memcpys `page.highWaterMark` bytes per page) and every query walk
// (which steps `highWaterMark ~/ strideBytes` candidates) are priced off extent
// rather than off live rows. So a tick got steadily more expensive forever, and
// dropping the spawn rate never recovered because pages are never released.
//
// **Two earlier versions of this bench reported "flat" and were both wrong**,
// which is the more useful lesson. The first pre-filled to exactly
// [_population] and then destroyed one and spawned one per tick, pinning the
// high-water mark at the population by construction. The second still used a
// page big enough to hold every entity at once, so recycling was trivially
// perfect and no second page was ever opened. A bench that cannot fail is worse
// than no bench: it produced a confident, wrong "ruled out".
//
// Hence the two things this file is careful about, and that any edit must
// preserve: entities die on **staggered lifetimes** so population oscillates
// and freed offsets scatter, and [_Game.pageSize] matches what a real game
// uses, so the multi-page path is actually exercised.
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

/// The shape a demo particle actually has: a flat sprite that is spawned,
/// moved for a while, and destroyed.
class _Particle extends EntityStruct with Transform2D, WorldTransform2D {}

class _Scene extends SceneStruct {
  @override
  void onSceneMounted(Scene scene) => handle = scene;

  late Scene handle;
  late final _Particle particle;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    particle = descriptor.has(_Particle.new);
  }
}

class _State extends GameState<_Game> {
  @override
  void onMounted() => loadScene(_Scene());

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(WorldTransformSystem.new);
  }
}

class _Game extends Game {
  @override
  int get pageSize => 1 << 20;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 16);

  @override
  GameState createState() => _State();
}

const Duration _step = Duration(milliseconds: 16);

/// Population held constant; only elapsed churn varies.
const int _population = 20000;

/// Spawned and destroyed per tick. At 20k population and 300/tick, an entity
/// lives ~66 ticks - roughly the "entities don't live long" shape the demo's
/// slider produces.
const int _churnPerTick = 300;

const int _ticks = 600;
const int _reportEvery = 100;

final List<String> _rows = <String>[];

/// Candidate rows every walk steps over, and every `beginTick` memcpy covers:
/// the sum of each page's high-water mark in rows, across every archetype.
///
/// This is the number that should track the live population and is suspected of
/// diverging from it. `MemoryPool.beginTick` copies `page.highWaterMark` bytes
/// (pool.dart:209), and `MemoryPage.rowOffsets` steps
/// `highWaterMark ~/ strideBytes` candidates skipping freed ones - so both the
/// per-step copy and the per-walk scan are priced off this, not off how many
/// entities are alive.
({int rows, int pages}) _extent() {
  var rows = 0;
  var pages = 0;
  for (var id = 0; id < ArchetypeRegistry.count; id++) {
    // ignore: invalid_use_of_internal_member
    final storage = ArchetypeRegistry.byId(id);
    for (var p = 0; p < storage.pageCount; p++) {
      // ignore: invalid_use_of_internal_member
      final page = storage.pageAt(p);
      if (page == null) continue;
      pages++;
      final stride = page.strideBytes;
      if (stride == null || stride == 0) continue;
      rows += page.highWaterMark ~/ stride;
    }
  }
  return (rows: rows, pages: pages);
}

void main() {
  tearDownAll(() {
    print(
      '\n$_population entities held constant, '
      '$_churnPerTick spawned+destroyed per tick',
    );
    print('(if this column is flat, churn is not the cause)\n');
    print('   tick     ms/tick        live    walked   pages');
    print('   ------------------------------------------------');
    for (final row in _rows) {
      print(row);
    }
  });

  tearDown(() {
    // ignore: invalid_use_of_visible_for_testing_member
    SceneRegistry.reset();
    // ignore: invalid_use_of_visible_for_testing_member
    ArchetypeRegistry.reset();
    // ignore: invalid_use_of_visible_for_testing_member
    ComponentTypeRegistry.reset();
  });

  test('a constant population does not get slower as it churns', () async {
    final run = await Game.startInline(_Game());
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    final scene = run.state.singleScene<_Scene>();

    // **Lifetimes, not a strict 1-for-1 swap.** The first version of this bench
    // pre-filled to exactly [_population] and then destroyed one and spawned
    // one per tick, which pins the high-water mark at the population by
    // construction - so it could not observe the extent growth it was written
    // to detect, and reported "flat" from a measurement that could not fail.
    // Real entities die on their own schedule, so the number destroyed in a
    // tick varies, population oscillates, and freed offsets are scattered.
    var seed = 12345;
    int rand(int n) {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      return seed % n;
    }

    // Entities bucketed by the tick they die on.
    final dying = <int, List<Entity>>{};
    var live = 0;

    void spawn(int tick, int count) {
      for (var i = 0; i < count; i++) {
        final entity = scene.handle.addEntity(scene.particle);
        final death = tick + 50 + rand(40);
        (dying[death] ??= <Entity>[]).add(entity);
        live++;
      }
    }

    // Ramp in over the mean lifetime rather than all at once, so the steady
    // state is reached the way the demo reaches it.
    for (var tick = -70; tick < 1; tick++) {
      spawn(tick, _churnPerTick);
      run.state.advance(_step);
    }

    final clock = Stopwatch();
    var windowMicros = 0;

    for (var tick = 1; tick <= _ticks; tick++) {
      clock
        ..reset()
        ..start();

      for (final entity in dying.remove(tick) ?? const <Entity>[]) {
        entity.destroy();
        live--;
      }
      spawn(tick, _churnPerTick);
      run.state.advance(_step);

      clock.stop();
      windowMicros += clock.elapsedMicroseconds;

      if (tick % _reportEvery == 0) {
        final perTick = windowMicros / _reportEvery / 1000;
        final extent = _extent();
        _rows.add(
          '${tick.toString().padLeft(7)}  '
          '${perTick.toStringAsFixed(2).padLeft(10)}  '
          '${live.toString().padLeft(10)}  '
          '${extent.rows.toString().padLeft(8)}  '
          '${extent.pages.toString().padLeft(6)}',
        );
        windowMicros = 0;
      }
    }

    // The claim under test: candidate rows should track the live population.
    // If `walked` has drifted far above `live`, every `beginTick` memcpy and
    // every query walk is paying for rows nobody is using.
    final extent = _extent();
    expect(
      extent.rows,
      lessThan((live * 1.25).round()),
      reason:
          'walked extent (${extent.rows}) should track live population '
          '($live); a large gap is the fragmentation this bench exists to '
          'catch',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
