// The "one ball at the centre of the screen for a single frame" report, run
// against the real `SceneGraphGame` rather than a synthetic stand-in.
//
// **This test reproduces an open defect (#5) and fails when it runs**, which is
// the point of it. `spawn_tick_world_transform_test.dart` in `goo2d` pins the
// composition half of the problem and passes; this one shows the demo is still
// wrong, which is the gap two rounds of "fixed" fell into - a synthetic test
// went green while the thing on screen kept flashing.
//
// It is `skip`ped rather than left red, because this package is in CI now (#83)
// and a suite that is permanently red is a suite nobody reads - which is how it
// came to carry sixteen unrelated failures in the first place. The skip is
// named and prints on every run, so the defect stays in front of anyone
// looking. Take it off to see the failure, and take it off for good when #5
// lands - at which point this inverts from reproducing the bug to asserting
// the fix.
//
// # What is asserted, and why exactly this
//
// An entity whose **published** world position is the origin while its
// **published** local offset is not. That pairing is the bug and nothing else
// is: every critter sits 90-390 units from the hub and every limb 26 from its
// body, so no live sprite is legitimately at (0, 0). The one entity that
// genuinely is - the hub - has a local offset of (0, 0) too, and so excludes
// itself without needing to be named.
//
// The probe is a `Tickable`, not a `FixedTickable`, and that is load-bearing.
// The presentation phase runs after `commitTick`, so it sees the snapshot
// `GameRenderer2D` draws from - precisely what a frame would have shown. A
// `FixedTickable` probe cannot do this job: it would have to declare an order
// against `WorldTransformSystem`, and that system deliberately returns 0 from
// its own `compareTo`, so a one-sided opinion does not reciprocate and the
// probe lands wherever the sort puts it. One was tried here and silently ran
// *before* the transform pass, reporting stale values that meant nothing.
//
// # What is known about the failure, measured rather than assumed
//
// `WorldTransformSystem` receives a spawn callback for every one of these
// entities and composes every one of them (16002 seen, 16002 composed), and
// the value it computes is correct - entity 0 composes to (89.999, 0.375) from
// a local offset of (90, 0) under a hub rotated a fraction of a degree. Reading
// it straight back through `readPending` returns that same value, so the write
// reaches the write slot.
//
// The published snapshot for that same row, that same frame, is still (0, 0).
// So this is not a composition bug and not a "which entities get composed" bug.
// A correct write into the write slot is not surviving into the published one
// for rows allocated during that tick. The per-tick distribution says the same
// thing: {1: 320, 16: 122, 31: 4, 40: 42, 47: 126} - tick 1 is the entire first
// batch (80 critters + 240 limbs), and the rest are partial batches at
// irregular intervals, which is the "random frame during sliding" signature.
// Every one of them corrects itself on the following tick.
//
// The remaining suspects are in `good`'s paging, not in `goo2d`:
// `MemoryPage.allocate` defers rows created while a query walk is open, and
// `MemoryPool.beginTick` both calls `flushPending()` and limits the
// copy-forward to `page.highWaterMark`. A row that is handed out mid-tick and
// only becomes "real" at the next `beginTick` is the shape that fits.
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

import 'package:goo2d_example/demo/scene_graph.dart';

const Duration _step = Duration(microseconds: 16667);

/// Records any entity drawn at the world origin that has no business being
/// there, along with the tick it happened on.
class _OriginProbe extends GameSystem with Tickable {
  late final Query _renderables;

  final List<String> sightings = <String>[];

  /// Sightings per tick. Which ticks they land on is most of the diagnosis, so
  /// it is reported rather than left to be inferred from the first few.
  final Map<int, int> perTick = <int, int>{};

  int _tick = 0;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    _renderables = descriptor
        .query()
        .withAll(WorldTransform2D, Transform2D)
        .build();
  }

  @override
  void onTick(Duration delta) {
    _tick++;
    for (final group in _renderables.groups()) {
      final local = group.get<Transform2D>();
      final world = group.get<WorldTransform2D>();
      for (final entity in group) {
        if (world.worldX[entity] != 0 || world.worldY[entity] != 0) continue;
        final localX = local.transformOffsetX[entity];
        final localY = local.transformOffsetY[entity];
        if (localX == 0 && localY == 0) continue; // the hub, legitimately
        perTick[_tick] = (perTick[_tick] ?? 0) + 1;
        sightings.add(
          'tick $_tick: $entity drawn at the world origin, but its local '
          'offset is ($localX, $localY)',
        );
      }
    }
  }
}

class _ProbedState extends SceneGraphState {
  final _OriginProbe probe = _OriginProbe();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(probe);
  }
}

class _ProbedGame extends SceneGraphGame {
  late final _ProbedState probedState = _ProbedState();

  @override
  SceneGraphState createState() => probedState;
}

void main() {
  // These cases boot inline, so this isolate both simulates and decodes. In an
  // app the loader arrives with the first `DrawCanvas2D`, which is a widget and
  // nothing here builds one - a headless boot has to register it itself.
  setUp(() => AssetLoaders.register<Texture>(const TextureLoader()));

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('no sprite is ever drawn at the world origin while the swarm fills',
      () async {
    // **The reported repro, as a test**: start at zero, ask for the maximum,
    // and watch every frame on the way up. The population has to be *growing*
    // for this to be visible at all - a row that has never held anything reads
    // back the defaults, where a recycled row holds the previous critter's
    // position, which is somewhere plausible in the swarm and invisible. That
    // is why the flash appeared at no repeatable point while dragging the
    // slider, and why a fixture that spawns a handful of entities into a fresh
    // scene cannot reproduce it.
    final game = _ProbedGame();
    await Game.startInline(game);
    addTearDown(() async {
      if (game.isRunning) await game.stop();
    });

    final pending = game.setPopulation(4000);
    game.state.advance(_step);
    await pending;

    // 80 critters per step, so ~50 steps to fill; well past that so the fill
    // crosses page boundaries repeatedly and then settles into churn.
    for (var i = 0; i < 120; i++) {
      game.state.advance(_step);
    }

    final probe = game.probedState.probe;
    expect(
      probe.sightings,
      isEmpty,
      reason:
          'each of these is one frame of a sprite at the centre of the '
          'screen. Per tick: ${probe.perTick}\n'
          '${probe.sightings.take(5).join('\n')}',
    );
  }, skip: 'reproduces open defect #5 (rows allocated mid-tick lose their '
      'writes); see the note at the top of this file');
}
