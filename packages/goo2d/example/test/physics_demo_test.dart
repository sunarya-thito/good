// The physics demo case, headless.
//
// Requires the native library:
//   cd packages/goo2d_ffi_box2d && powershell -File tool/build_native.ps1

// Tagged `box2d` because these cases need the native library. CI builds it
// and runs them; the tag names them for `--exclude-tags box2d` in a checkout
// where it has not been built.
@Tags(['box2d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

import 'package:goo2d_example/demo/physics.dart';

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('the sandbox fills to its target and the bodies settle', () async {
    final demo = PhysicsDemo();
    final run = await Game.startInline(demo.create());
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    final state = run.state as PhysicsState;
    state.targetPopulation = 40;

    void advance(int steps) {
      for (var i = 0; i < steps; i++) {
        run.state.advance(const Duration(microseconds: 16667));
      }
    }

    // Long enough to spawn the batch (capped per tick) and for it to land.
    advance(240);
    expect(
      state.spawnedCount,
      40,
      reason: 'the case should converge on its target population',
    );

    // The real claim: the population is STABLE. The case recycles anything
    // that falls below the floor, so bodies tunnelling through the ground
    // would show up as a population that keeps churning rather than one that
    // holds - which is why this asserts across a second window rather than
    // sampling once.
    advance(240);
    expect(
      state.spawnedCount,
      40,
      reason:
          'bodies fell through the ground and were recycled - the '
          'population should hold once everything has landed',
    );
  });

  test('a body is born at its drop height, not at the origin', () async {
    // The test that was missing, and its absence let a real bug ship: the
    // first version wrote each body's position AFTER `addEntity`, by which
    // time Box2D had already created the body at (0, 0) and the physics
    // write-back had overwritten the transform on the same tick. Every body
    // was born in a heap at the origin.
    //
    // Two earlier attempts at this test could not fail, and why is worth
    // recording. Asserting on where bodies END UP does not work - a heap at
    // the origin still falls, still lands, and still spreads sideways past
    // any threshold. Asserting on the MAXIMUM height seen does not work
    // either - forty overlapping bodies are flung upward hard enough to
    // clear any bar you set.
    //
    // What does work: a small batch, only two ticks, and the extreme value.
    // Correct code creates every body at y = +6..+10 (positive is UP, see
    // the demo's own note on the axis), so after two ticks of gravity the
    // *lowest* on screen is still above +1. The bug creates them all at zero,
    // and two ticks is not long enough for the solver to throw any of them
    // clear - so that extreme stays near zero.
    final demo = PhysicsDemo();
    final run = await Game.startInline(demo.create());
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    final state = run.state as PhysicsState;
    // One tick's worth of spawns (the case caps at 8 per tick).
    state.targetPopulation = 8;

    run.state.advance(const Duration(microseconds: 16667));
    run.state.advance(const Duration(microseconds: 16667));

    final bodies = state.getSystem<SandboxSystem>().bodies;
    // The smallest y is the one nearest the floor, since +y is up.
    var nearestFloor = 1e9;
    var seen = 0;
    for (final group in bodies.groups()) {
      final prefab = group.tryGet<Crate>() ?? group.tryGet<Ball>();
      if (prefab == null) continue;
      for (final entity in group) {
        final y = (prefab as Transform2D).transformOffsetY[entity];
        if (y < nearestFloor) nearestFloor = y;
        seen++;
      }
    }

    expect(seen, greaterThan(0), reason: 'nothing spawned to check');
    expect(
      nearestFloor,
      greaterThan(1),
      reason:
          'every body should be created around y=+6..+10 (above the floor) '
          'and still be up there two ticks later; a value near zero means '
          'they were created at the origin and the spawn position was '
          'clobbered',
    );
  });

  test('lowering the target sheds bodies', () async {
    // The slider only ever went *up*. `SandboxSystem` spawned to make up a
    // shortfall and did nothing at all with a surplus, so dragging from
    // 20 000 back down to a few hundred left 20 000 bodies simulating - which
    // presents as the engine being unable to recover from a spike rather than
    // as the case ignoring the control.
    final demo = PhysicsDemo();
    final run = await Game.startInline(demo.create());
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    final state = run.state as PhysicsState;

    void advance(int steps) {
      for (var i = 0; i < steps; i++) {
        run.state.advance(const Duration(microseconds: 16667));
      }
    }

    state.targetPopulation = 120;
    advance(120);
    expect(state.spawnedCount, 120, reason: 'the fill should have converged');

    state.targetPopulation = 10;
    advance(30);
    expect(
      state.spawnedCount,
      10,
      reason: 'the population should follow the target down, not only up',
    );
  });

  test('the arena grows to hold the target population', () async {
    // A fixed 32 m x 13 m box holds roughly 200 bodies. Behind a slider that
    // goes to 20 000 that is not a pile, it is a crush - bodies overlapping,
    // the solver pushing them apart every step, nothing ever sleeping - and
    // it cost 36 ms a step at 4000 bodies against 0.94 ms at 1000. The box
    // has to grow with what it is asked to hold.
    final demo = PhysicsDemo();
    final run = await Game.startInline(demo.create());
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    final state = run.state as PhysicsState;
    final scene = state.sandbox;
    final small = scene.arena.halfWidth;

    state.targetPopulation = 4000;
    for (var i = 0; i < 4; i++) {
      run.state.advance(const Duration(microseconds: 16667));
    }

    expect(
      scene.arena.halfWidth,
      greaterThan(small * 4),
      reason: 'the arena should scale with the population it must hold',
    );

    // And the *collider* followed.
    //
    // **This used to assert `scene.ground.box.halfWidth[floor]`, and that
    // test could not fail.** The component field was always right; what was
    // wrong was the Box2D shape built from it, because body creation ran in
    // the same tick as the mount-time write and `_readRow` serves the last
    // *published* snapshot - so a recycled row handed back the previous
    // arena's width. The field said 69, the collider was 17, and bodies
    // poured through the gap. Ask Box2D where the floor is, not the ECS.
    final physics = state.getSystem<Box2DPhysicsSystem>();
    final arena = scene.arena;
    // From below, casting up: +y is down, so this can only hit the floor's
    // underside and never the pile resting on top of it.
    final hit = physics.raycast(
      scene.handle,
      arena.halfWidth * 0.9,
      arena.floorY + 6,
      0,
      -8,
    );
    expect(
      hit && identical(physics.hitCollider, scene.ground.box),
      isTrue,
      reason:
          'there should be floor near the edge of the resized arena - if '
          'there is not, the collider kept the old size while the sprite grew',
    );
  });

  test('a mid-run resize does not drop bodies through the floor', () async {
    // The user-visible symptom, and the one the raycast above explains:
    // "when i slide the demo slider, it zooms out, but the collision on the
    // boxes didn't update, all the balls just falls to the void".
    //
    // Driven through the *command*, like the slider, and with bodies already
    // resting when the resize happens - the path a fresh-start test misses,
    // because a never-published page reads back its own same-tick writes and
    // the bug only bites on recycled rows.
    final demo = PhysicsDemo();
    final game = demo.create() as PhysicsGame;
    final run = await Game.startInline(game);
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    final state = run.state as PhysicsState;
    final sandbox = state.getSystem<SandboxSystem>();

    void advance(int steps) {
      for (var i = 0; i < steps; i++) {
        run.state.advance(const Duration(microseconds: 16667));
      }
    }

    Future<void> settleAt(int target) async {
      final pending = game.setPopulation(target);
      run.state.advance(const Duration(microseconds: 16667));
      await pending;
      advance(900);
    }

    await settleAt(250);
    expect(sandbox.escapes, 0, reason: 'the initial arena should hold them');

    // The resize. Big enough to rebuild (the hysteresis band is 15%).
    await settleAt(1000);

    expect(
      sandbox.escapes,
      0,
      reason: 'nothing should fall out of the box after it is resized',
    );
    expect(
      state.spawnedCount,
      1000,
      reason:
          'and the population should reach its target rather than '
          'plateauing where escapes cancel out spawns',
    );
  });

  test('Box2D holds exactly as many bodies as the case does', () async {
    // The demo-level guard on the leak that made this case unusable: Box2D
    // reported 57 882 awake bodies for a scene of 4000, because
    // `Entity.destroy` never told the physics system. The case churns bodies
    // constantly - recycling escapees, shedding a lowered target - so it is
    // the natural place to notice the two counts drifting apart.
    //
    // Driven through a fill *and* a shed, because the leak only shows on the
    // way down.
    final demo = PhysicsDemo();
    final game = demo.create() as PhysicsGame;
    final run = await Game.startInline(game);
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    final state = run.state as PhysicsState;

    void advance(int steps) {
      for (var i = 0; i < steps; i++) {
        run.state.advance(const Duration(microseconds: 16667));
      }
    }

    // The three static arena pieces - one floor, two walls - are bodies too,
    // and are not part of the population.
    const arenaBodies = 3;

    state.targetPopulation = 120;
    advance(120);
    expect(state.spawnedCount, 120);
    expect(
      game.physicsBodies.value,
      120 + arenaBodies,
      reason: 'every entity should own exactly one Box2D body',
    );

    state.targetPopulation = 10;
    advance(60);
    expect(state.spawnedCount, 10);
    expect(
      game.physicsBodies.value,
      10 + arenaBodies,
      reason:
          'a shed entity must take its Box2D body with it - if this is '
          'high, destroy() is not reaching the physics system and every '
          'recycled body is leaking',
    );
  });

  test('dragging the slider leaves no ghost arenas behind', () async {
    // Reported from the running demo: "i was playing with physics, sliding
    // the slider up and down, and then this happened, im at 4-5k, the
    // container getting bigger, but there is an invisible small container in
    // the middle of the scene".
    //
    // The arena rebuild destroys its walls and spawns new ones. A wall
    // destroyed in the **same tick** its body was created read `bodyHandle`
    // through the published snapshot, got 0, and its body was never
    // destroyed - so every fast rebuild left a complete invisible arena in
    // the world. Sprites gone, colliders still there.
    //
    // A slow drag never shows it; the rebuilds have to land close enough
    // together to catch a body on its creation tick, which is what changing
    // the target every single tick does.
    final demo = PhysicsDemo();
    final game = demo.create() as PhysicsGame;
    final run = await Game.startInline(game);
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    final state = run.state as PhysicsState;

    // Sweep up and down across the whole range, changing on every tick so
    // rebuilds land back to back.
    for (var sweep = 0; sweep < 6; sweep++) {
      for (var i = 0; i < 40; i++) {
        state.targetPopulation = sweep.isEven ? 200 + i * 120 : 5000 - i * 120;
        run.state.advance(const Duration(microseconds: 16667));
      }
    }

    // Settle on one size and let the population converge.
    state.targetPopulation = 200;
    for (var i = 0; i < 400; i++) {
      run.state.advance(const Duration(microseconds: 16667));
    }

    expect(
      game.physicsBodies.value,
      state.spawnedCount + 3,
      reason:
          'Box2D should hold exactly the live bodies plus one floor and '
          'two walls. Anything more is a ghost arena - walls whose entities '
          'were destroyed on the same tick their bodies were created',
    );
  });

  test('a case with a zero target simulates cleanly', () async {
    // The empty world still steps; it must not divide by a population of
    // nothing or skip the step entirely.
    final demo = PhysicsDemo();
    final run = await Game.startInline(demo.create());
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    final state = run.state as PhysicsState;
    state.targetPopulation = 0;
    for (var i = 0; i < 60; i++) {
      run.state.advance(const Duration(microseconds: 16667));
    }
    expect(state.spawnedCount, 0);
  });

  test('the physics figure is the step, not the gap after it', () async {
    // #187. `_PhysicsPhaseStart` stamps the clock, `_PhysicsPhaseEnd` reads
    // it, and the difference is what the overlay shows as `physics` and what
    // `bench_physics.dart` puts in its `physics` column. That difference is
    // the physics step only if the start probe really does sort ahead of
    // `Box2DPhysicsSystem` - and for a long time it did not.
    // `Box2DPhysicsSystem.compareTo` answers -1 for everything that is not
    // itself, `sortSystems` asks the earlier-declared system of a pair first
    // and takes the first non-zero answer, and physics was declared first.
    // The probe's own "before physics" was never read, the stamp landed
    // *after* the step, and the number on screen was the gap between two
    // adjacent no-op systems.
    //
    // **This asserts the number, not the sorted list.** Asserting the order
    // restates the fix and passes just as happily against a probe pair that
    // brackets nothing - which is exactly what the broken version did. The
    // claim made here is that the figure is a real share of the fixed step
    // it sits inside, expressed as a ratio rather than a microsecond
    // threshold so it means the same thing on a fast machine and a slow one.
    // Correct, that ratio is around 0.6; with the declaration order put back
    // it is around 0.01.
    final demo = PhysicsDemo();
    final run = await Game.startInline(demo.create());
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    final state = run.state as PhysicsState;

    void advance(int steps) {
      for (var i = 0; i < steps; i++) {
        run.state.advance(const Duration(microseconds: 16667));
      }
    }

    const target = 200;
    state.targetPopulation = target;
    advance(400);
    // The measurement is only worth reading if there was something to
    // measure. An empty world would report a small physics cost honestly,
    // and this test would then be passing or failing on nothing.
    expect(
      state.spawnedCount,
      target,
      reason: 'nothing was simulating, so the timing below means nothing',
    );

    // Per-frame ratios rather than a ratio of aggregates, so the numerator
    // and the denominator always come from the same step. The median rejects
    // the frames where the machine preempted the isolate - wall clock only
    // ever runs long, never short.
    final ratios = <double>[];
    for (var i = 0; i < 60; i++) {
      run.state.advance(const Duration(microseconds: 16667));
      // `_FixedPhaseStart` and `_FixedPhaseEnd` bracket the whole fixed
      // dispatch, so this span is every system the step ran, physics
      // included.
      final step = state.profile.stepEndedAt - state.profile.stepStartedAt;
      if (step <= 0) continue;
      ratios.add(state.physicsMicros / step);
    }
    expect(ratios.length, greaterThan(30), reason: 'too few steps sampled');
    ratios.sort();
    final median = ratios[ratios.length ~/ 2];

    expect(
      median,
      greaterThan(0.25),
      reason:
          'physics should be most of a fixed step that is simulating $target '
          'bodies. A figure near zero means the probe pair is bracketing '
          'something other than the physics system - check that '
          '_PhysicsPhaseStart is still declared ahead of Box2DPhysicsSystem, '
          'because its "before physics" constraint is discarded if it is not',
    );
  });
}
