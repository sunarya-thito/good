import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

import 'package:goo2d_example/demo/demo.dart';
import 'package:goo2d_example/demo/demo_game.dart';
import 'package:goo2d_example/demo/particles.dart';
import 'package:goo2d_example/demo/physics.dart';
import 'package:goo2d_example/demo/scene_graph.dart';
import 'package:goo2d_example/harness/demo_app.dart';

/// The harness's *widget* half.
///
/// `demo_test.dart` boots each case headless and checks the numbers are wired;
/// nothing there mounts a `GameView`, which is how switching cases stayed
/// broken through two rounds of "fixed": the failure needs a view **attached
/// and replaying frames** on main, and a headless start/stop/start cycle never
/// touches that path at all.
void main() {
  // A `GameView` builds the `DrawCanvas2D` that registers the texture loader in
  // an app, but only once a case is up, and a case decodes its scene while it
  // is starting. So the loader has to be in place before the first start.
  setUp(() => AssetLoaders.register<Texture>(const TextureLoader()));

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  /// `Game.start` spawns a real isolate, and `pumpAndSettle` advances *fake*
  /// time - it never waits for one. `runAsync` steps outside the fake clock so
  /// the spawn can actually complete, then a pump rebuilds with the game set.
  Future<void> settle(WidgetTester tester, {int attempts = 40}) async {
    for (var i = 0; i < attempts; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  testWidgets('a case that fails to start does not wedge the menu',
      (tester) async {
    // **The "sometimes stuck on loading" bug, made deterministic.**
    //
    // `_select` set `_switching = true` at the top and cleared it only on the
    // success path, with no try/finally. So any throw in between - `stop`,
    // `create`, `Game.start` - left the flag true forever: `_demo` stayed
    // null so the view showed a spinner, and every later click hit the
    // `if (_switching) return` guard and did nothing. A permanent spinner and
    // a dead menu from one unseen exception.
    //
    // It was intermittent only because the throw was. This makes the throw
    // certain, so the wedge is testable.
    await tester.pumpWidget(
      DemoApp(demos: <Demo Function()>[ParticlesDemo.new, _BrokenDemo.new]),
    );
    await settle(tester);
    expect(find.byType(GameView), findsOneWidget, reason: 'first case is up');

    await tester.tap(find.text('Broken'));
    await settle(tester);

    expect(
      find.textContaining('failed to start'),
      findsOneWidget,
      reason: 'the failure should be reported, not shown as a spinner that '
          'never resolves',
    );

    // The part that actually matters: the menu still works.
    await tester.tap(find.text('Galaxy'));
    await settle(tester);
    expect(
      find.byType(GameView),
      findsOneWidget,
      reason: 'a failed switch must not leave _switching true - if it does, '
          'this tap is ignored and the app is dead until restarted',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching cases and back keeps the view alive', (tester) async {
    await tester.pumpWidget(
      DemoApp(
        demos: <Demo Function()>[
          ParticlesDemo.new,
          SceneGraphDemo.new,
          PhysicsDemo.new,
        ],
      ),
    );
    await settle(tester);
    expect(
      find.byType(GameView),
      findsOneWidget,
      reason: 'the first case is up',
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Swarm'));
    await settle(tester);
    expect(
      find.byType(GameView),
      findsOneWidget,
      reason: 'the second case is up',
    );
    expect(tester.takeException(), isNull);

    // Several round trips, not one: the first version of this test switched
    // back once, passed, and the menu still hung on the *fifth* run - so
    // whatever survives a run accumulates rather than colliding immediately.
    // Five is what it took by hand; this does six.
    for (var i = 0; i < 4; i++) {
      final next = i.isEven ? 'Galaxy' : 'Swarm';
      await tester.tap(find.text(next));
      await settle(tester);
      expect(
        find.byType(GameView),
        findsOneWidget,
        reason: 'run ${i + 3} ($next) must start, not hang on loading',
      );
      expect(tester.takeException(), isNull, reason: 'run ${i + 3} ($next)');
    }
  });
}

/// A case that cannot start, so the harness's failure path can be tested at
/// all. Throwing from `create` stands in for every intermittent way a real
/// start fails - the harness must not care which.
class _BrokenDemo extends Demo {
  @override
  String get name => 'Broken';

  @override
  String get blurb => 'fails to start, on purpose';

  @override
  DemoGame create() => throw StateError('this case cannot start');

  @override
  DemoGame get game => throw StateError('never started');
}
