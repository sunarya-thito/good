// The joints case, headless.
//
// Requires the native library:
//   cd packages/goo2d_ffi_box2d && powershell -File tool/build_native.ps1
//
// **Positive y is DOWN**, so a chain hangs towards a larger y and its anchor
// sits at a negative one.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

import 'package:goo2d_example/demo/joints.dart';

const Duration _step = Duration(microseconds: 16667);

/// Every body the case should ever hold: three chain anchors plus the wheel
/// hub, the wheel itself, three chains of nine links, and one weight.
const int _expectedBodies = 4 + 1 + 9 * 3 + 1;

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  Future<(Game, JointState, JointGame)> boot() async {
    final demo = JointsDemo();
    final game = demo.create() as JointGame;
    final run = await Game.startInline(game);
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });
    return (run, run.state as JointState, game);
  }

  test('a chain hangs from its anchor instead of falling', () async {
    // The mechanism, not the wiring. If no joint were made - which is what
    // happens if the case builds them on the spawn tick, before any body
    // exists - every link would be in free fall and the whole chain would be
    // metres below where it started after two seconds.
    final (run, state, _) = await boot();

    final scene = state.sandbox;
    // The unloaded left-hand chain, so the breaking logic cannot influence it.
    final chain = scene.chains.first;
    final bottom = chain.last;
    final startY = scene.link.transformOffsetY[bottom];

    for (var i = 0; i < 120; i++) {
      run.state.advance(_step);
    }

    final endY = scene.link.transformOffsetY[bottom];
    expect(
      endY - startY,
      lessThan(1.0),
      reason: 'a hanging chain should stay put; two seconds of free fall '
          'would put the bottom link about 20 m lower',
    );
    // And it is genuinely suspended, not resting on anything - there is no
    // ground in this case at all.
    expect(
      endY,
      lessThan(scene.link.transformOffsetY[chain.first] + 12),
      reason: 'the chain should not have stretched into a line of dots',
    );
  });

  test('the loaded chain breaks and the unloaded ones do not', () async {
    // Box2D has no breaking; the case reads each joint's constraint force and
    // destroys it past a threshold. This asserts the whole path - force is
    // reported, compared, and acted on.
    final (run, state, game) = await boot();

    for (var i = 0; i < 240; i++) {
      run.state.advance(_step);
    }

    expect(
      state.broken,
      greaterThan(0),
      reason: 'the weighted chain should tear under its own load',
    );
    expect(
      game.peakJointForce.value,
      greaterThan(0),
      reason: 'a loaded joint must report a non-zero constraint force, or the '
          'threshold is being compared against nothing. This is the '
          'all-time peak on purpose: the live reading is 0 once the last '
          'joint has let go, which is exactly when this is sampled',
    );

    // The other two chains carry no weight and must survive - a "breaking"
    // that destroys everything is not breaking, it is a bug.
    final quiet = state.sandbox.chains.first;
    final bottom = quiet.last;
    expect(
      state.sandbox.link.transformOffsetY[bottom],
      lessThan(0),
      reason: 'the unloaded chain should still be hanging near its anchor',
    );
  });

  test('the unloaded chains swing rather than hanging dead still', () async {
    // A chain built hanging straight down is already in equilibrium, so it
    // stands there - correct physics, and indistinguishable on screen from a
    // chain that is not simulating at all. The case shoves the bottom link
    // sideways once; the joints carry it up the chain, which is the thing
    // worth looking at.
    final (run, state, _) = await boot();
    final scene = state.sandbox;
    final bottom = scene.chains.first.last;

    var extremeX = 0.0;
    for (var i = 0; i < 90; i++) {
      run.state.advance(_step);
      final x = scene.link.transformOffsetX[bottom] - JointScene.chainX(0);
      if (x.abs() > extremeX) extremeX = x.abs();
    }

    expect(
      extremeX,
      greaterThan(0.5),
      reason: 'the bottom link should visibly leave the vertical',
    );
  });

  test('the weighted chain is rehung after it tears', () async {
    // Otherwise the case is a one-shot: the chain breaks in the first few
    // seconds, its pieces fall out of view - there is no ground here - and
    // anyone who looks after that sees two chains and a wheel.
    final (run, state, _) = await boot();

    // Long enough to break, wait out the delay, respawn and break again.
    for (var i = 0; i < 900; i++) {
      run.state.advance(_step);
    }

    expect(
      state.rehangs,
      greaterThan(0),
      reason: 'the chain should have been torn down and hung again',
    );
    expect(
      state.broken,
      greaterThan(0),
      reason: 'and it got there by breaking, not by some other path',
    );
    // **And rehanging does not leak.** Eight rebuilds of a ten-entity chain
    // is eighty entities if the old one is not destroyed, and the symptom of
    // getting that wrong is a scene that gets heavier forever while looking
    // completely normal - which is exactly the shape of the bug that made
    // this whole physics integration slow in the first place.
    //
    // Asserted against Box2D's own body count rather than anything Dart
    // tracks, for the same reason: the Dart side was right last time too.
    final physics = state.getSystem<Box2DPhysicsSystem>();
    final counters = physics.counters(Int32List(5));
    expect(
      counters[0],
      _expectedBodies,
      reason: 'one anchor per chain plus the wheel hub, the wheel, three '
          'chains of nine links and one weight - and nothing accumulated '
          'across ${state.rehangs} rehangs',
    );

    // Deliberately no assertion on where the rehung chain *is*: it is torn
    // down and rebuilt on a cycle, so a sample at an arbitrary tick can
    // legitimately catch it mid-fall. An earlier version asserted it hangs at
    // its anchor and failed against perfectly good code.
    expect(state.sandbox.chains.last.length, 10);
  });

  test('the motorised wheel actually turns', () async {
    // A revolute joint with a motor. `maxMotorTorque` is what makes it real -
    // a motor with none of it cannot move anything and looks exactly like the
    // joint not working, so the assertion is on rotation rather than on the
    // joint handle being non-zero.
    final (run, state, _) = await boot();

    final scene = state.sandbox;
    final wheel = scene.wheelEntity;
    final startAngle = scene.wheel.transformRotation[wheel];

    for (var i = 0; i < 60; i++) {
      run.state.advance(_step);
    }

    expect(
      (scene.wheel.transformRotation[wheel] - startAngle).abs(),
      greaterThan(0.5),
      reason: 'one second at 2.5 rad/s should be a visible fraction of a turn',
    );
  });
}
