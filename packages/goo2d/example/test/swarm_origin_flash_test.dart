// The "one ball at the centre of the screen for a single frame" report, run
// against the real `SceneGraphGame` rather than a synthetic stand-in.
//
// This pins #5. It ran red for as long as that defect was open and is the case
// that finally located it, after three fixes aimed at the wrong layer.
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
// # What it turned out to be
//
// Not paging, which is where the first three attempts looked. Dumping all
// three of the page's triple-buffer slots for a flashing row showed the
// composed world position in **none** of them - so nothing had written it yet,
// and there was no lost write to find. The write came a tick later.
//
// `CritterSystem` returns -1 against `WorldTransformSystem` precisely so the
// spawner runs before the pass that composes what it wrote. It did not:
// `GameState.sortSystems` ran that constraint through `List.sort`, and the
// profiling markers this demo declares (`_FixedPhaseStart` and
// `_PresentPhaseStart` each return -1 unconditionally, so both claim to be
// first) made the comparator inconsistent. `List.sort` given one of those does
// not just mis-order the offending pair - it permutes the list, and
// `CritterSystem`'s unrelated and perfectly consistent constraint went with it.
// The sorted order came out with `WorldTransformSystem` ahead of
// `CritterSystem`, so every entity a tick spawned was composed on the *next*
// tick and published its defaults - (0, 0) - in between.
//
// `sortSystems` builds a constraint graph and topologically sorts it now, so a
// stated constraint cannot be outvoted by anybody else's. The per-tick
// distribution this used to report - {1: 320, 15: 140, 29: 40, 38: 53,
// 44: 180}, tick 1 being the whole first batch of 80 critters and 240 limbs -
// is empty.
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
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test(
    'no sprite is ever drawn at the world origin while the swarm fills',
    () async {
      // **The reported repro, as a test**: start at zero, ask for the maximum,
      // and watch every frame on the way up. Both halves matter. The fill is
      // where a spawn lands on a row that has never held anything, so a late
      // composition publishes the defaults and the sprite is visibly at the
      // centre of the screen; the churn after it is where a spawn lands on a
      // *recycled* row, which is the case a fixture spawning into a fresh scene
      // cannot produce at all. A recycled row holds the previous critter's
      // position - somewhere plausible in the swarm, and invisible - so the
      // sighting count alone under-reports it, but it is the same one-tick lag
      // and it is covered by running well past the fill.
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
    },
  );
}
