import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

import 'package:goo2d_example/demo/demo_game.dart';
import 'package:goo2d_example/demo/particles.dart';
import 'package:goo2d_example/demo/scene_graph.dart';

/// A demo case is a program, and a program that does not run demonstrates
/// nothing. This boots each case headless and drives it by hand, so a wiring
/// mistake surfaces here rather than on a device with a profiler attached.
///
/// It deliberately does **not** assert timings - a test machine's frame budget
/// is meaningless. What it asserts is that every number the overlay shows is
/// connected to something, and that each case's entities end up where the case
/// says they do.
///
/// Exactly one fixed step's worth. `Game.fixedTimeStep` defaults to 16667us
/// (60 Hz), and a round 16ms affords **zero** steps - the accumulator spends
/// wall clock in whole multiples and carries the rest. Getting that wrong
/// reads as "nothing ran" with no hint as to why, which is worth the pedantry
/// of naming the real number here.
const Duration _step = Duration(microseconds: 16667);

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  Future<G> boot<G extends DemoGame>(G Function() create) async {
    final game = await Game.startInline(create);
    addTearDown(() async {
      if (game.isRunning) await game.stop();
    });
    return game;
  }

  /// Sets the target population and ticks until the case has converged on it.
  ///
  /// Fire, tick, await: inline, the tick is what runs the command, so awaiting
  /// first deadlocks - the thing that would complete the future is the tick
  /// that never happens. A real app never notices, because it is auto-ticking.
  ///
  /// Then more ticks, because a case fills toward its target a capped batch at
  /// a time rather than in one step. Entities also expire, so this settles at
  /// *about* the target rather than exactly on it.
  Future<void> populate(DemoGame game, int target, {int ticks = 12}) async {
    final pending = game.setPopulation(target);
    game.state.advance(_step);
    await pending;
    for (var i = 0; i < ticks; i++) {
      game.state.advance(_step);
    }
  }

  group('the shared readout', () {
    test('every channel the overlay reads is published', () async {
      final game = await boot(ParticlesGame.new);
      await populate(game, 64);
      game.state.advance(_step);

      // "About", not exactly: the case fills toward the target a capped
      // batch per step and entities expire on their own clock, so the
      // population hovers rather than latching.
      expect(game.spawnedCount.value, closeTo(64, 24));
      expect(game.spritesDrawn.value, greaterThan(0));
      expect(game.stepsPerAdvance.value, 1);
      // Timings are machine-dependent, so the only honest assertion is that
      // something published at all rather than the channel sitting at its
      // default forever.
      expect(game.advanceMicros.value, greaterThan(0));
      expect(game.stepMicros.value, greaterThanOrEqualTo(0));
      expect(game.presentMicros.value, greaterThan(0));
      expect(
        game.renderMicros.value,
        lessThanOrEqualTo(game.presentMicros.value),
        reason:
            'the renderer is one Tickable among several, so its time is a '
            'share of the presentation pass and never more than all of it - '
            'which is also the check that the two probe brackets did not end '
            'up sorted the wrong way round',
      );
    });
  });

  group('Galaxy', () {
    test('the population churns and holds near its target', () async {
      final game = await boot(ParticlesGame.new);
      await populate(game, 200, ticks: 60);
      final settled = game.spawnedCount.value;
      expect(settled, closeTo(200, 60));

      // Long enough that every mote alive at the start has expired - its
      // lifetime tops out under 4.5s and the step is 16.667ms. If nothing
      // despawned, the count would only ever climb; if nothing respawned, it
      // would collapse. Holding is the whole behaviour.
      for (var i = 0; i < 400; i++) {
        game.state.advance(_step);
      }
      expect(game.spawnedCount.value, closeTo(200, 60));

      await populate(game, 0, ticks: 400);
      expect(
        game.spawnedCount.value,
        0,
        reason:
            'with nothing topping it up, every mote expires and the '
            'scene empties - which needs per-entity destroy to be real',
      );
    });

    test('motes are flat - no world transform pass touches them', () async {
      final game = await boot(ParticlesGame.new);
      await populate(game, 16);

      final state = game.state as ParticlesState;
      var seen = 0;
      for (final entity in state.getSystem<SwirlSystem>().motes.run()) {
        // The case's whole claim: an unparented sprite carries no
        // `WorldTransform2D`, so it is not in `WorldTransformSystem`'s query
        // and the renderer reads its local transform directly.
        expect(entity.has<WorldTransform2D>(), isFalse);
        seen++;
      }
      expect(seen, greaterThan(0));
    });

    test('the swirl actually moves them', () async {
      final game = await boot(ParticlesGame.new);
      await populate(game, 4);
      final state = game.state as ParticlesState;
      final mote = state.galaxy.mote;
      final entity = state.getSystem<SwirlSystem>().motes.run().first;

      final before = mote.transformOffsetX[entity];
      for (var i = 0; i < 20; i++) {
        game.state.advance(_step);
      }
      expect(mote.transformOffsetX[entity], isNot(before));
    });
  });

  group('Swarm', () {
    test('a critter keeps every limb spawned in the same tick', () async {
      final game = await boot(SceneGraphGame.new);
      await populate(game, 1);
      game.state.advance(_step);

      final state = game.state as SceneGraphState;
      final critter = state.getSystem<CritterSystem>().critters.run().first;

      // The reason this case exists as a test at all: `Parent.addChild` reads
      // the tail of the child chain to append, and an ordinary read sees the
      // last published snapshot - so three `addChild` calls in one tick used
      // to each believe they were the first, and every limb but one was
      // silently orphaned.
      final walked = <Entity>[];
      Entity? at = critter<Parent>().component.parentFirstChild[critter];
      while (at != null) {
        walked.add(at);
        at = at<Child>().component.childNextSibling[at];
      }
      expect(walked, hasLength(Limb.limbsPerCritter));
    });

    test('a freshly spawned critter does not snap on its second frame', () async {
      final game = await boot(SceneGraphGame.new);
      await populate(game, 1);

      final state = game.state as SceneGraphState;
      final critter = state.swarm.critter;
      final entity = state.getSystem<CritterSystem>().critters.run().first;

      // Sampled once per tick, the way the renderer would see it. A field left
      // at its default for the first frame and written by the first update on
      // the second shows up here as one enormous delta among tiny ones.
      var previous = critter.transformRotation[entity];
      var worst = 0.0;
      for (var i = 0; i < 5; i++) {
        game.state.advance(_step);
        final now = critter.transformRotation[entity];
        final delta = (now - previous).abs();
        if (delta > worst) worst = delta;
        previous = now;
      }

      // One step turns it by spin * dt * 3, well under a tenth of a radian.
      expect(
        worst,
        lessThan(0.2),
        reason:
            'every frame-to-frame rotation delta is one step of the '
            'update, so nothing was left uninitialised at mount',
      );
    });
    test('limbs are composed, never animated', () async {
      final game = await boot(SceneGraphGame.new);
      await populate(game, 1);
      game.state.advance(_step);

      final state = game.state as SceneGraphState;
      final critter = state.getSystem<CritterSystem>().critters.run().first;
      final limb = critter<Parent>().component.parentFirstChild[critter]!;
      final limbStruct = state.swarm.limb;

      final localBefore = limbStruct.transformOffsetX[limb];
      final worldBefore = limbStruct.worldX[limb];
      for (var i = 0; i < 30; i++) {
        game.state.advance(_step);
      }

      expect(
        limbStruct.transformOffsetX[limb],
        localBefore,
        reason: 'nothing writes a limb transform after spawn',
      );
      expect(
        limbStruct.worldX[limb],
        isNot(worldBefore),
        reason:
            'yet it moves on screen - that is WorldTransformSystem '
            'composing a constant against a moving ancestor',
      );
    });

    test('rotating the hub alone moves every limb', () async {
      final game = await boot(SceneGraphGame.new);
      await populate(game, 3);
      game.state.advance(_step);

      final state = game.state as SceneGraphState;
      final limbStruct = state.swarm.limb;
      final critter = state.getSystem<CritterSystem>().critters.run().first;
      final limb = critter<Parent>().component.parentFirstChild[critter]!;
      final before = limbStruct.worldY[limb];

      game.state.pool.beginTick();
      state.swarm.hub.transformOffsetY[state.swarm.hubEntity] = 5000;
      game.state.pool.commitTick();
      game.state.advance(_step);

      expect(
        limbStruct.worldY[limb],
        greaterThan(before + 4000),
        reason: 'two levels of composition: hub -> critter -> limb',
      );
    });
  });
  // Switching cases in the menu is start, stop, start - in one process, with
  // process-global registries in between. Nothing exercised that until the
  // menu existed, and it did not work: the third run re-registered an
  // archetype the first run had left in `ArchetypeRegistry`, got back the
  // *first* run's prefab, and read an asset handle belonging to a `GameAssets`
  // torn down two runs earlier. It surfaced as "declared (address 0) but was
  // never loaded on this isolate", which points at the asset layer and not at
  // the registry that actually held the stale entry.
  group('running several games in one process', () {
    test('inline: galaxy, then swarm, then galaxy again', () async {
      for (final make in <DemoGame Function()>[
        ParticlesGame.new,
        SceneGraphGame.new,
        ParticlesGame.new,
      ]) {
        final game = await Game.startInline(() => make());
        await populate(game, 24);
        // Reading a sprite's texture is what failed: it resolves an address
        // through the asset table of the run that declared it.
        expect(game.spritesDrawn.value, greaterThan(0));
        expect(game.spawnedCount.value, greaterThan(0));
        await game.stop();
      }
    });

    // **Spawned**, which is what the app does - and the reason the inline
    // version above passed while the menu still hung. `Game.start` runs the
    // declaration passes on both isolates and loads assets through a main-side
    // round trip, so it is a different boot path end to end. A test that only
    // covers the inline one says nothing about the one that ships.
    test('spawned: galaxy, then swarm, then galaxy again', () async {
      for (final make in <DemoGame Function()>[
        ParticlesGame.new,
        SceneGraphGame.new,
        ParticlesGame.new,
      ]) {
        // The hang is here: the third `start` never completes.
        final game = await Game.start(() => make());
        expect(game.isRunning, isTrue);
        await game.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
