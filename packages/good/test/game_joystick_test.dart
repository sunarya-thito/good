import 'dart:math' as math;

import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/input/input_axis.dart';
import 'package:good/src/input/input_binding.dart';
import 'package:good/src/system.dart';
import 'package:good/src/widget/joystick.dart';

// The on-screen stick (#191): a finger on a widget becoming two virtual axis
// floats, and coming back to rest on every way a finger can stop.
//
// Every reading here has to tell *proportional* from *thresholded*, which is
// what the widget exists to deliver: "dragging left reads left" passes against
// four composed bits, so the load-bearing assertions below are mid-travel
// pushes reading mid-travel.
//
// Most tests read the device mirror through `axisOf`, which is what
// `setVirtualAxis` wrote and is exact. The last group runs a real fixed step
// and reads a `StickBinding`, so the trip across the block is covered once
// once and not repeated fifteen times.

late Game run;

/// Every widget Flutter rebuilt while [_recordingRebuilds] ran.
///
/// Read off `debugPrintRebuildDirtyWidgets`, which is the only vantage point
/// that can see this: a widget the test passes in as a `track` is one instance
/// for the test's whole life, so `Element.updateChild` short-circuits on
/// identity and a counter inside it never moves however often its parent
/// rebuilds. Counting the parent's own rebuilds needs the framework's own
/// report.
final List<String> rebuilt = <String>[];

/// Runs [body] with Flutter reporting every widget it rebuilds into [rebuilt].
Future<void> _recordingRebuilds(Future<void> Function() body) async {
  final DebugPrintCallback original = debugPrint;
  rebuilt.clear();
  debugPrint = (String? message, {int? wrapWidth}) => rebuilt.add(message ?? '');
  debugPrintRebuildDirtyWidgets = true;
  try {
    await body();
  } finally {
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = original;
  }
}

class _StickSystem extends GameSystem with FixedTickable {
  final move = Input.of<Vector2>(
    const StickBinding(x: .virtualLeftStickX, y: .virtualLeftStickY),
  );

  final aim = Input.of<Vector2>(
    const StickBinding(x: .virtualRightStickX, y: .virtualRightStickY),
  );

  @override
  void onFixedUpdate() {}
}

class _StickState extends GameState<_StickGame> {
  final stickSystem = GameSystem.of(_StickSystem.new);
}

class _StickGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _StickState();
}

Future<_StickGame> _boot() async {
  final game = await Game.startInline(_StickGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

_StickSystem get _system => run.state.getSystem<_StickSystem>();

double _x([VirtualAxis axis = InputAxis.virtualLeftStickX]) =>
    run.inputDevice!.axisOf(axis);

double _y([VirtualAxis axis = InputAxis.virtualLeftStickY]) =>
    run.inputDevice!.axisOf(axis);

/// A stick under a `Center`, so the box under test is the size asked for.
///
/// `pumpWidget` hands its root tight 800x600 constraints, so a bare `SizedBox`
/// there is stretched to the surface and every coordinate below would be
/// measuring the window.
Widget _boxed(Widget child, {double width = 400, double height = 400}) =>
    Center(child: SizedBox(width: width, height: height, child: child));

/// The centre of an 800x600 test surface, which is where every `_boxed` box is
/// centred.
const Offset _middle = Offset(400, 300);

void main() {
  group('a drag is proportional', () {
    testWidgets('half the travel reads half', (tester) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickArea(game: game, radius: 100)),
      );

      final finger = await tester.startGesture(
        _middle,
        kind: PointerDeviceKind.touch,
      );
      await finger.moveTo(_middle + const Offset(50, 0));

      expect(
        _x(),
        closeTo(0.5, 1e-6),
        reason:
            'half the radius is half the deflection - a stick that read 1 '
            'here would be four thresholded bits drawn as a circle, which is '
            'the whole thing #191 exists to avoid',
      );
      expect(_y(), closeTo(0, 1e-6));
      await finger.up();
    });

    testWidgets('the far edge reads one and no further', (tester) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickArea(game: game, radius: 100)),
      );

      final finger = await tester.startGesture(
        _middle,
        kind: PointerDeviceKind.touch,
      );
      await finger.moveTo(_middle + const Offset(180, 0));

      expect(_x(), closeTo(1, 1e-6));
      await finger.up();
    });

    testWidgets('a diagonal past the corner reads a magnitude of one', (
      tester,
    ) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickArea(game: game, radius: 100)),
      );

      final finger = await tester.startGesture(
        _middle,
        kind: PointerDeviceKind.touch,
      );
      await finger.moveTo(_middle + const Offset(150, -150));

      final magnitude = math.sqrt(_x() * _x() + _y() * _y());
      expect(
        magnitude,
        closeTo(1, 1e-6),
        reason:
            'clamped to the circle, not per axis - a per-axis clamp reads '
            '(1, 1) here and moves a game 1.41 times as fast on a diagonal',
      );
      expect(_x(), closeTo(math.sqrt1_2, 1e-6));
      expect(_y(), closeTo(math.sqrt1_2, 1e-6));
      await finger.up();
    });
  });

  group('which way is up', () {
    testWidgets('dragging up reads +1 on the y axis', (tester) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickArea(game: game, radius: 100)),
      );

      final finger = await tester.startGesture(
        _middle,
        kind: PointerDeviceKind.touch,
      );
      // Up the screen is a *smaller* Flutter y, and an axis reads +1 up.
      await finger.moveTo(_middle + const Offset(0, -100));

      expect(
        _y(),
        closeTo(1, 1e-6),
        reason:
            'InputAxis is +1 up, matching the world, so a game adding the '
            'value to a transform offset moves the way the thumb was pushed',
      );
      await finger.up();
    });
  });

  group('letting go', () {
    testWidgets('lifting the finger returns the stick to rest', (tester) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickArea(game: game, radius: 100)),
      );

      final finger = await tester.startGesture(
        _middle,
        kind: PointerDeviceKind.touch,
      );
      await finger.moveTo(_middle + const Offset(100, 0));
      expect(_x(), closeTo(1, 1e-6));

      await finger.up();
      expect(_x(), 0);
      expect(_y(), 0);
    });

    testWidgets('a cancelled pointer returns the stick to rest', (
      tester,
    ) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickArea(game: game, radius: 100)),
      );

      final finger = await tester.startGesture(
        _middle,
        kind: PointerDeviceKind.touch,
      );
      await finger.moveTo(_middle + const Offset(100, 0));
      expect(_x(), closeTo(1, 1e-6));

      // A notification, an incoming call or an ancestor taking the gesture
      // ends the pointer with no up event behind it. The widget is still
      // mounted and the app still focused, so nothing downstream - not
      // dispose, not releaseAll - is in a position to clean this up.
      await finger.cancel();

      expect(
        _x(),
        0,
        reason:
            'a stick that waited for a lift would hold this direction until '
            'the app was restarted, which is the failure PointerPhase.'
            'cancelled was added for',
      );
      expect(_y(), 0);
    });

    testWidgets('the widget going away while a finger is down returns the '
        'stick to rest', (tester) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickArea(game: game, radius: 100)),
      );

      final finger = await tester.startGesture(
        _middle,
        kind: PointerDeviceKind.touch,
      );
      await finger.moveTo(_middle + const Offset(0, -100));
      expect(_y(), closeTo(1, 1e-6));

      await tester.pumpWidget(const SizedBox.shrink());

      expect(
        _y(),
        0,
        reason:
            'the events that would have said the finger lifted left with the '
            'widget routing them',
      );

      // The gesture outlived the widget; ending it keeps the test binding
      // from complaining about a live pointer.
      await finger.up();
    });
  });

  group('one finger owns the stick', () {
    testWidgets('a second finger in the same area is ignored', (tester) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickArea(game: game, radius: 100)),
      );

      final first = await tester.startGesture(
        _middle,
        pointer: 1,
        kind: PointerDeviceKind.touch,
      );
      await first.moveTo(_middle + const Offset(-100, 0));
      expect(_x(), closeTo(-1, 1e-6));

      final second = await tester.startGesture(
        _middle + const Offset(0, 100),
        pointer: 2,
        kind: PointerDeviceKind.touch,
      );

      expect(
        _x(),
        closeTo(-1, 1e-6),
        reason:
            'the second finger would otherwise recentre the stick under '
            'itself and drop the first finger\'s push to rest',
      );

      await second.moveTo(_middle + const Offset(80, 100));
      expect(
        _x(),
        closeTo(-1, 1e-6),
        reason: 'and it does not steer either',
      );

      await first.up();
      await second.up();
    });

    testWidgets('two areas on two axis pairs are two sticks', (tester) async {
      final game = await _boot();
      await tester.pumpWidget(
        Row(
          textDirection: TextDirection.ltr,
          children: <Widget>[
            SizedBox(
              width: 400,
              height: 600,
              child: JoystickArea(game: game, radius: 100),
            ),
            SizedBox(
              width: 400,
              height: 600,
              child: JoystickArea(
                game: game,
                x: InputAxis.virtualRightStickX,
                y: InputAxis.virtualRightStickY,
                radius: 100,
              ),
            ),
          ],
        ),
      );

      final left = await tester.startGesture(
        const Offset(200, 300),
        pointer: 1,
        kind: PointerDeviceKind.touch,
      );
      final right = await tester.startGesture(
        const Offset(600, 300),
        pointer: 2,
        kind: PointerDeviceKind.touch,
      );
      await left.moveTo(const Offset(150, 300));
      await right.moveTo(const Offset(600, 225));

      expect(_x(), closeTo(-0.5, 1e-6));
      expect(_y(), closeTo(0, 1e-6));
      expect(_x(InputAxis.virtualRightStickX), closeTo(0, 1e-6));
      expect(_y(InputAxis.virtualRightStickY), closeTo(0.75, 1e-6));

      await left.up();
      await right.up();
    });
  });

  group('JoystickControl', () {
    testWidgets('the stick centres on its own box', (tester) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickControl(game: game), width: 200, height: 200),
      );

      final finger = await tester.startGesture(
        _middle,
        kind: PointerDeviceKind.touch,
      );
      expect(
        _x(),
        0,
        reason: 'a control reads from its centre, not from where the finger '
            'landed',
      );

      // Half of the 100-pixel radius the 200-pixel box gives it.
      await finger.moveTo(_middle + const Offset(50, 0));
      expect(_x(), closeTo(0.5, 1e-6));
      await finger.up();
    });

    testWidgets('a drag that leaves the box holds full deflection', (
      tester,
    ) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickControl(game: game), width: 200, height: 200),
      );

      final finger = await tester.startGesture(
        _middle,
        kind: PointerDeviceKind.touch,
      );
      await finger.moveTo(_middle + const Offset(300, 0));

      expect(
        _x(),
        closeTo(1, 1e-6),
        reason:
            'Flutter routes a pointer to what it landed on for the pointer\'s '
            'whole life, so sliding a thumb off the control holds the push '
            'instead of dropping it',
      );
      await finger.up();
    });
  });

  group('what is drawn', () {
    testWidgets('an area with no track and no thumb draws nothing', (
      tester,
    ) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickArea(game: game, radius: 100)),
      );

      expect(find.byType(CustomPaint), findsNothing);

      final finger = await tester.startGesture(
        _middle,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(
        find.byType(CustomPaint),
        findsNothing,
        reason: 'the touchpad case shows the game through it, drawing nothing '
            'even while dragged',
      );
      await finger.up();
    });

    testWidgets('an area given a thumb shows it at the finger, and takes it '
        'away on lift', (tester) async {
      final game = await _boot();
      const key = ValueKey<String>('thumb');
      await tester.pumpWidget(
        _boxed(
          JoystickArea(
            game: game,
            radius: 100,
            thumb: const SizedBox.square(key: key, dimension: 20),
          ),
        ),
      );

      expect(find.byKey(key), findsNothing);

      final landed = _middle + const Offset(-60, 40);
      final finger = await tester.startGesture(
        landed,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();

      expect(find.byKey(key), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(key)),
        within(distance: 0.01, from: landed),
        reason: 'the stick centres where the finger landed, which is what '
            'makes the area a touchpad and not a fixed control',
      );

      await finger.moveTo(landed + const Offset(50, 0));
      await tester.pump();
      expect(
        tester.getCenter(find.byKey(key)),
        within(distance: 0.01, from: landed + const Offset(50, 0)),
        reason: 'the thumb follows the finger, half way across a 100 radius',
      );

      await finger.up();
      await tester.pump();
      expect(find.byKey(key), findsNothing);
    });

    testWidgets('the thumb moves without rebuilding the tree', (tester) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickControl(game: game), width: 200, height: 200),
      );

      final finger = await tester.startGesture(
        _middle,
        kind: PointerDeviceKind.touch,
      );
      await _recordingRebuilds(() async {
        for (var i = 1; i <= 20; i++) {
          await finger.moveTo(_middle + Offset(i * 4, 0));
          // Pumped between moves, so a rebuild scheduled by one event is
          // flushed before the next arrives. Twenty moves and one pump at the
          // end would coalesce twenty rebuilds into one and read almost the
          // same as none.
          await tester.pump();
        }
      });

      expect(_x(), closeTo(0.8, 1e-6), reason: 'the drag did happen');
      expect(
        rebuilt,
        isEmpty,
        reason:
            'the offset drives a repaint through a Listenable, so a drag '
            'rebuilds no widgets - a builder taking the offset, or a '
            'setState, rebuilds the stick once per pointer event',
      );
      await finger.up();
    });

    testWidgets('Joystick draws its thumb where the offset says', (
      tester,
    ) async {
      const key = ValueKey<String>('thumb');
      await tester.pumpWidget(
        _boxed(
          const Joystick(
            thumbOffset: Offset(0.5, 1),
            thumb: SizedBox.square(key: key, dimension: 20),
          ),
          width: 200,
          height: 200,
        ),
      );

      expect(
        tester.getCenter(find.byKey(key)),
        // 100 of travel: half of it right, all of it up, and up is a smaller
        // Flutter y.
        within(distance: 0.01, from: _middle + const Offset(50, -100)),
      );
    });
  });

  group('reaching the game', () {
    testWidgets('a finger on the widget reaches a StickBinding', (
      tester,
    ) async {
      final game = await _boot();
      await tester.pumpWidget(
        _boxed(JoystickArea(game: game, radius: 100)),
      );

      final finger = await tester.startGesture(
        _middle,
        kind: PointerDeviceKind.touch,
      );
      await finger.moveTo(_middle + const Offset(40, -60));
      run.state.runFixedStep();

      expect(
        _system.move.value.x,
        closeTo(0.4, 1e-6),
        reason:
            'the widget writes two floats in the shared block and the binding '
            'reads them - no command, no port and no channel of its own',
      );
      expect(_system.move.value.y, closeTo(0.6, 1e-6));
      expect(
        _system.aim.value,
        Vector2.zero(),
        reason: 'the other virtual pair is its own two floats',
      );

      await finger.up();
      run.state.runFixedStep();
      expect(_system.move.value, Vector2.zero());
    });
  });
}
