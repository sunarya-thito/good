import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/scene_handle.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/camera_view.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
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
    descriptor.has(_TickingSystem());
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
  });
}
