import 'package:flutter/services.dart' show StringCodec, SystemChannels;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/scene_handle.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/camera_view.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input/input_axis.dart';
import 'package:good/src/input/input_key.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/system.dart';
import 'package:good/src/widget/game_view.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// The Flutter-facing surface of a Game, which is now one method: buildView.
//
// There used to be a whole second event lane here - WidgetEvent,
// WidgetListener, BuildWidgetEvent - so that several declared systems could
// each wrap the widget tree. It is gone, and this file is what replaced it:
// one object builds the view, systems live wholly on the game isolate, and
// the "which isolate does this run on" question has one answer per type.

class _BareState extends GameState<Game> {
  @override
  void onMounted() {
    loadScene(_BareScene());
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_TickingSystem.new);
  }
}

class _BareScene extends SceneStruct {
  _BareScene();
}

class _TickingSystem extends GameSystem {}

/// The shape a renderer package takes: a `Game` subclass that answers
/// [Game.buildView]. `Game2D` in `goo2d` is exactly this with a `CustomPaint`
/// in it.
class _ViewGame extends Game {
  @override
  int get pageSize => 4096;

  BuildContext? seen;
  bool show = true;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _BareState();

  @override
  Widget? buildView(BuildContext context, CameraView? camera) {
    seen = context;
    return show ? const Text('game', textDirection: TextDirection.ltr) : null;
  }
}

/// A game that draws nothing - headless, or a game whose whole UI is ordinary
/// Flutter widgets around the view.
class _SilentGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  GameState createState() => _BareState();
}

/// Records the visibility hooks and the fixed steps, so a test can tell
/// "the command arrived" apart from "a tick ran and carried it".
class _VisibilitySystem extends GameSystem
    with AppVisibilityListener, FixedTickable {
  int hidden = 0;
  final List<Duration> shown = <Duration>[];
  int steps = 0;

  @override
  void onAppHidden() => hidden++;

  @override
  void onAppShown(Duration gap) => shown.add(gap);

  @override
  void onFixedUpdate() => steps++;
}

/// The system of the live run, bound the same way [run] is and for the same
/// reason: the declaration pass owns the instance, so a test cannot hold one
/// it made itself.
late _VisibilitySystem _visibility;

class _VisibilityState extends GameState<Game> {
  @override
  void onMounted() {
    loadScene(_BareScene());
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    _visibility = descriptor.has(_VisibilitySystem.new);
  }
}

class _VisibilityGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _VisibilityState();
}

/// Drives the platform's own lifecycle channel, which is what the observer
/// under test is registered against.
///
/// Not `WidgetsBinding.handleAppLifecycleStateChanged`: that one is
/// `@protected`, so calling it is an analyzer warning, and it also skips the
/// binding's transition generator - the thing that turns one `hidden` into
/// the `inactive -> hidden` walk a real backgrounding produces. Going in
/// through the channel means these tests exercise the same arrival the OS
/// causes, doubled states and all.
Future<void> _lifecycle(AppLifecycleState state) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          SystemChannels.lifecycle.name,
          const StringCodec().encodeMessage(state.toString()),
          (_) {},
        );

Future<T> _start<T extends Game>(T game) async {
  run = await Game.startInline(game);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('buildView', () {
    testWidgets('what the game returns is what the view shows', (tester) async {
      await _start(_ViewGame());
      await tester.pumpWidget(GameView.headless(game: run));
      expect(find.text('game'), findsOneWidget);
    });

    testWidgets('a game that draws nothing is not an error', (tester) async {
      await _start(_SilentGame());
      await tester.pumpWidget(GameView.headless(game: run));
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the default buildView returns null, and a game with no '
            'renderer is a real configuration - a HUD-only app, a headless '
            'game someone attached a view to - not a misconfiguration to '
            'crash on',
      );
    });

    testWidgets('null and a widget are both honoured on rebuild', (
      tester,
    ) async {
      final game = await _start(_ViewGame());
      await tester.pumpWidget(GameView.headless(game: run));
      expect(find.text('game'), findsOneWidget);

      game.show = false;
      await tester.pumpWidget(
        GameView.headless(game: run, key: const Key('again')),
      );
      expect(
        find.text('game'),
        findsNothing,
        reason:
            'returning null mid-life is how a renderer says "there is '
            'no scene to draw yet" - Game2D does exactly this between '
            'loadScene calls',
      );
    });

    testWidgets('the context is the real one from the element tree', (
      tester,
    ) async {
      final game = await _start(_ViewGame());
      await tester.pumpWidget(GameView.headless(game: run));
      expect(game.seen, isNotNull);
      expect(
        game.seen!.mounted,
        isTrue,
        reason:
            'a live context, so buildView can read an InheritedWidget - '
            'a theme, a MediaQuery - like any other build method',
      );
    });
  });

  group('frame counting', () {
    // NOT COVERED HERE: that pumping frames advances `frameCount`. The widget
    // test binding runs the frame *pipeline* but does not drive the engine's
    // frame **reporting** - `SchedulerBinding.addTimingsCallback` never fires
    // under `tester.pump()`, so this reads zero however many frames are
    // pumped. The wiring is not at fault, the harness simply cannot feed it.
    // `frame_meter_test.dart` drives `FrameMeter` with stated timings instead,
    // which is where all the arithmetic actually is.
    //
    // What is worth asserting here is the half that *is* observable: the
    // meter is armed and disarmed by the view refcount, and reports nothing
    // when nothing is showing the game.

    testWidgets('a game nobody is looking at reports no frames', (
      tester,
    ) async {
      await _start(_ViewGame());
      expect(run.frameCount, 0);
      expect(
        run.fps,
        0,
        reason:
            'and a rate needs an interval - reporting one before two '
            'frames have happened would be inventing it',
      );
    });

    testWidgets('attaching and detaching a view arms and disarms cleanly', (
      tester,
    ) async {
      await _start(_ViewGame());
      await tester.pumpWidget(GameView.headless(game: run));
      await tester.pump();

      // The view goes; the game runs on. What is being checked is that the
      // timings callback is removed rather than left on the binding - a
      // leaked one would keep firing against a game nobody is showing, and
      // the widget binding fails a test outright for a leftover callback.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(run.fps, 0);
      expect(tester.takeException(), isNull);
    });
  });
  group('simulation frame rate', () {
    testWidgets('published pictures are counted, and are not display frames', (
      tester,
    ) async {
      await _start(_ViewGame());
      expect(run.simulationFrameCount, 0);

      // Each `advance` that gets a presentation pass publishes one picture.
      // No widget is involved: this is the *simulation's* output rate, and it
      // is what a player perceives as the frame rate whenever it is the lower
      // of the two - the renderer samples the newest published frame per
      // Flutter frame, so a display at 160 showing a simulation at 25 shows
      // 25 distinct positions.
      for (var i = 0; i < 5; i++) {
        run.advance(const Duration(milliseconds: 10));
      }

      expect(
        run.simulationFrameCount,
        5,
        reason: 'five presentation passes, five published pictures',
      );
      expect(
        run.frameCount,
        0,
        reason:
            'and no *display* frames, because nothing is showing it - '
            'which is exactly why these are two numbers and not one',
      );
    });

    // A plain `test`, not `testWidgets`: the meter reads a real monotonic
    // clock, and inside a widget test `Future.delayed` elapses fake time
    // while that clock does not move at all.
    test('a paused simulation publishes nothing, and says so', () async {
      await _start(_ViewGame());

      // Frames spread over real time, because a rate is over an interval and
      // five advances back to back do not span one.
      final burst = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        run.advance(const Duration(milliseconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      burst.stop();

      expect(run.simulationFrameCount, 5);
      final running = run.simulationFps;
      expect(
        running,
        greaterThan(0.0),
        reason:
            'the meter has to be fed for the paused half below to mean '
            'anything - asserting only the zero would pass against a meter '
            'nothing ever recorded',
      );

      run.state.paused = true;
      // The frame loop keeps running while paused, which is the whole
      // defect: `presentFrame` fires on every one of these and each used to
      // be counted as a published picture.
      for (var i = 0; i < 5; i++) {
        run.advance(const Duration(milliseconds: 10));
      }
      expect(
        run.simulationFrameCount,
        5,
        reason: 'five more frames and no new picture - the tick did not move',
      );

      // Silence for longer than the window the meter averages. Measured on
      // this machine rather than guessed: the staleness threshold scales
      // with what the producer was doing, so the wait has to as well.
      await Future<void>.delayed(burst.elapsed * 2);
      expect(
        run.simulationFps,
        0,
        reason:
            'a simulation running zero steps is not running at $running '
            'frames a second',
      );
    });
  });

  // #160. The two seams that call `InputDevice.releaseAll` - what the app
  // being hidden does, and what the last view going away does. The block
  // arithmetic itself is pinned in game_input_test.dart; these are about
  // whether anything ever pulls the lever.
  //
  // Each one asserts the key is held *first*. Checking only that it reads up
  // afterwards would pass on a game nobody had pressed anything on, which is
  // the exact test that would have let this bug ship.
  group('releasing input', () {
    testWidgets('backgrounding the app lets go of a held key', (tester) async {
      await _start(_ViewGame());
      await tester.pumpWidget(GameView.headless(game: run));
      final device = run.inputDevice!;

      // Resumed first, and it costs nothing when the binding is already
      // there: the transition generator emits nothing for a state that has
      // not changed, so this only fixes a starting point.
      await _lifecycle(AppLifecycleState.resumed);
      device.press(InputKey.w);
      expect(
        device.isDown(InputKey.w),
        isTrue,
        reason: 'the control - the character has to be walking first',
      );

      await _lifecycle(AppLifecycleState.hidden);

      expect(
        device.isDown(InputKey.w),
        isFalse,
        reason:
            'the OS sent no key-up on the way out and never will, so if '
            'the hide does not clear this nothing else ever does',
      );
    });

    testWidgets('coming back does not put the key down again', (tester) async {
      await _start(_ViewGame());
      await tester.pumpWidget(GameView.headless(game: run));
      final device = run.inputDevice!;

      await _lifecycle(AppLifecycleState.resumed);
      device.press(InputKey.w);
      await _lifecycle(AppLifecycleState.hidden);
      await _lifecycle(AppLifecycleState.resumed);

      expect(
        device.isDown(InputKey.w),
        isFalse,
        reason:
            'the decided behaviour, and the reason it is written down on '
            'releaseAll rather than left to be discovered: a key still '
            'physically held sends no fresh down, so it reads up until the '
            'player lifts it and presses again. A false "not held" fixes '
            'itself on the next press; a false "held" never does',
      );

      device.press(InputKey.w);
      expect(
        device.isDown(InputKey.w),
        isTrue,
        reason:
            'and that next press works normally - the hide cleared the '
            'block, it did not wedge it',
      );
    });

    testWidgets('a mouse button held into the background lets go', (
      tester,
    ) async {
      await _start(_ViewGame());
      await tester.pumpWidget(GameView.headless(game: run));
      final device = run.inputDevice!;

      await _lifecycle(AppLifecycleState.resumed);
      device.press(InputKey.leftMouseButton);
      expect(device.isDown(InputKey.leftMouseButton), isTrue);

      await _lifecycle(AppLifecycleState.hidden);

      expect(device.isDown(InputKey.leftMouseButton), isFalse);
    });

    testWidgets('the last view going away lets go', (tester) async {
      await _start(_ViewGame());
      await tester.pumpWidget(GameView.headless(game: run));
      final device = run.inputDevice!;

      device.press(InputKey.w);
      expect(device.isDown(InputKey.w), isTrue);

      // The widget goes; the game runs on. Nothing is forwarding key events
      // any more, so the up that would have cleared this can no longer
      // arrive from anywhere.
      await tester.pumpWidget(const SizedBox.shrink());

      expect(device.isDown(InputKey.w), isFalse);
    });

    // #161. The case #160 left alone: `inactive`, where the window is still
    // on screen. Every other test in this group drives `hidden`, and the
    // binding's transition generator walks `resumed -> inactive -> hidden`
    // to get there - so a test that only asserts the released state after a
    // hide cannot tell which of the two states released it, and would pass
    // unchanged against the old behaviour.
    //
    // These stop at `inactive` and assert both halves: released, *and* still
    // visible. The visible half is what makes it #161 and not #160, and it
    // is checked against a run that goes on to `hidden` afterwards, so the
    // `isTrue` cannot be a flag nobody ever moved.
    testWidgets('losing focus lets go of a held key, and keeps drawing', (
      tester,
    ) async {
      await _start(_VisibilityGame());
      await tester.pumpWidget(GameView.headless(game: run));
      final device = run.inputDevice!;

      await _lifecycle(AppLifecycleState.resumed);
      device.press(InputKey.w);
      expect(
        device.isDown(InputKey.w),
        isTrue,
        reason: 'the control - the character has to be walking first',
      );

      await _lifecycle(AppLifecycleState.inactive);

      expect(
        device.isDown(InputKey.w),
        isFalse,
        reason:
            'an unfocused window receives no key events at all, measured on '
            'Windows - not the up for this key, not anything else - so if '
            'the focus loss does not clear it nothing ever will',
      );
      expect(
        run.state.isVisible,
        isTrue,
        reason:
            'and the window is still on screen, which is the whole '
            'difference from #160: alt-tabbing must not pause the game',
      );
      expect(
        _visibility.hidden,
        0,
        reason: 'nothing told the game it had gone away, because it has not',
      );

      await _lifecycle(AppLifecycleState.hidden);

      expect(
        run.state.isVisible,
        isFalse,
        reason:
            'the control for the visible assertion above - the flag does '
            'move, so reading true at `inactive` was an observation and not '
            'a default nobody had touched',
      );
      expect(_visibility.hidden, 1);
    });

    testWidgets('losing focus returns a pushed stick to rest', (tester) async {
      await _start(_VisibilityGame());
      await tester.pumpWidget(GameView.headless(game: run));
      final device = run.inputDevice!;

      await _lifecycle(AppLifecycleState.resumed);
      device.setGamepadAxis(1, GamepadAnalog.leftStickY, -1);
      expect(
        device.axisOf(InputAxis.padLeftStickY(1)),
        -1.0,
        reason: 'the control - the stick has to be pushed first',
      );

      await _lifecycle(AppLifecycleState.inactive);

      expect(
        device.axisOf(InputAxis.padLeftStickY(1)),
        0.0,
        reason:
            'the hold half of the block goes back to rest with the bits, '
            'and an axis left pushed strands whatever it was driving the '
            'same way a key left down does',
      );
      expect(run.state.isVisible, isTrue);
    });

    testWidgets('the view that stays up keeps its keys', (tester) async {
      await _start(_ViewGame());
      await tester.pumpWidget(
        Column(
          children: <Widget>[
            SizedBox(
              width: 100,
              height: 100,
              child: GameView.headless(game: run, key: const Key('a')),
            ),
            SizedBox(
              width: 100,
              height: 100,
              child: GameView.headless(game: run, key: const Key('b')),
            ),
          ],
        ),
      );
      final device = run.inputDevice!;

      device.press(InputKey.w);
      expect(device.isDown(InputKey.w), isTrue);

      // One of the two goes. The game is still on screen and still being
      // played, which is why the release sits behind `detachView`'s refcount
      // rather than in `_GameViewState.dispose`: doing it per widget would
      // drop a key out from under whoever is still looking at it.
      await tester.pumpWidget(
        Column(
          children: <Widget>[
            SizedBox(
              width: 100,
              height: 100,
              child: GameView.headless(game: run, key: const Key('a')),
            ),
          ],
        ),
      );

      expect(device.isDown(InputKey.w), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        device.isDown(InputKey.w),
        isFalse,
        reason: 'and the second one going is what actually releases it',
      );
    });
  });

  // #162. The carrier, not the semantics. `game_test.dart` drives
  // `GameState.setVisible` directly, so its twelve visibility tests pin what
  // hiding and showing *do* and never touch how the message got there. This
  // one goes in through the platform's lifecycle channel and out through the
  // command, which is the only path a real app uses.
  //
  // The show half is the one that matters. `_setVisibleCommand` is
  // receipt-delivered because it can stop the fixed tick - `pauseWhenHidden`
  // cancels the timer on the way down - so a tick-delivered "visible again"
  // would be queued for a tick that hiding just took away. That is a game
  // which can be hidden and never shown, and no assertion about what
  // `setVisible` does can see it.
  group('visibility over the control carrier', () {
    testWidgets('showing arrives with no tick to carry it', (tester) async {
      await _start(_VisibilityGame());
      await tester.pumpWidget(GameView.headless(game: run));
      await _lifecycle(AppLifecycleState.resumed);

      await _lifecycle(AppLifecycleState.hidden);

      // One step here on purpose, and it is what makes this test about the
      // show half rather than the hide. A tick-delivered command would be
      // pumped by this step, so the hide lands whichever carrier it took -
      // which leaves everything after it answerable only by how the *second*
      // message travelled.
      //
      // It doubles as the control: a game that cannot step at all would
      // satisfy "no step ran" below for reasons that have nothing to do with
      // the carrier.
      run.advance(const Duration(milliseconds: 10));
      expect(
        _visibility.steps,
        greaterThan(0),
        reason: 'the fixed tick has to work here for its absence later to '
            'mean anything',
      );
      expect(_visibility.hidden, 1);
      expect(run.state.isVisible, isFalse);

      // Nothing drives `advance` from here to the end of the test, which is
      // the state `pauseWhenHidden` leaves a real game in: it cancels the
      // timer, so there is no tick window left for a tick-delivered command
      // to be pumped from.
      final stepsWhileHidden = _visibility.steps;

      await _lifecycle(AppLifecycleState.resumed);

      expect(
        run.state.isVisible,
        isTrue,
        reason: 'the whole point - the game came back with no tick running, '
            'because the command is carried over the control port and run '
            'from the port callback',
      );
      expect(
        _visibility.shown,
        hasLength(1),
        reason: 'and it reached the game, not just the flag: onAppShown is '
            'what restarts whatever a game stopped on the way out',
      );
      expect(
        _visibility.steps,
        stepsWhileHidden,
        reason: 'and not one fixed step ran between the send and the '
            'arrival. If this ever moves, a tick carried the message and '
            'the two assertions above are passing for the wrong reason',
      );
    });

    testWidgets('a backgrounding round trip is one hide and one show', (
      tester,
    ) async {
      await _start(_VisibilityGame());
      await tester.pumpWidget(GameView.headless(game: run));

      // Straight down the platform's own walk: the binding's transition
      // generator turns each of these into the doubled states a real
      // backgrounding produces, so this sends far more than two messages.
      await _lifecycle(AppLifecycleState.resumed);
      await _lifecycle(AppLifecycleState.paused);
      await _lifecycle(AppLifecycleState.resumed);

      expect(_visibility.hidden, 1);
      expect(_visibility.shown, hasLength(1));
      expect(
        run.state.isVisible,
        isTrue,
        reason: 'and it ends up back where it started, which is what the '
            'idempotence in setVisible is for',
      );
    });
  });
}
