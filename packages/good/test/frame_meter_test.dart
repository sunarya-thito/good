import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:good/src/widget/frame_meter.dart';

/// [FrameMeter]'s arithmetic, driven by synthesized timings.
///
/// The wiring onto `Game` is exercised by `game_widget_test.dart`; what cannot
/// be exercised there is the counting itself, because the widget test binding
/// does not drive `SchedulerBinding.addTimingsCallback` - `tester.pump()` runs
/// the frame pipeline but not the engine's frame *reporting*. So the numbers
/// are tested here, against frames stated by hand.

/// One frame that finished rastering at [rasterFinishMicros] having taken
/// [spanMicros] from vsync to done.
FrameTiming _frame(int rasterFinishMicros, {int spanMicros = 8000}) {
  final start = rasterFinishMicros - spanMicros;
  return FrameTiming(
    vsyncStart: start,
    buildStart: start,
    buildFinish: start + (spanMicros ~/ 2),
    rasterStart: start + (spanMicros ~/ 2),
    rasterFinish: rasterFinishMicros,
    rasterFinishWallTime: rasterFinishMicros,
  );
}

void main() {
  test('nothing reported means no rate, not a guessed one', () {
    final meter = FrameMeter();
    expect(meter.frameCount, 0);
    expect(meter.fps, 0);
    expect(meter.millis, 0);

    meter.reportTimings(<FrameTiming>[_frame(1000000)]);
    expect(meter.frameCount, 1, reason: 'the frame happened and was counted');
    expect(
      meter.fps,
      0,
      reason:
          'but a rate needs an interval, and one frame is not one - '
          'reporting a number here would be inventing it',
    );
  });

  test('fps is frames counted over the wall clock they spanned', () {
    final meter = FrameMeter();
    // Eleven frames, exactly 1/60s apart: ten intervals over 166666us.
    for (var i = 0; i <= 10; i++) {
      meter.reportTimings(<FrameTiming>[_frame(1000000 + i * 16667)]);
    }
    expect(meter.frameCount, 11);
    expect(meter.fps, closeTo(60.0, 0.01));
  });

  test('fps is not one over the frame time', () {
    final meter = FrameMeter();
    // Frames arriving 60 times a second, each taking only 4ms of work. The
    // reciprocal of the span would say 250fps; the truth is 60, because vsync
    // sets the ceiling and the spare 12.67ms is headroom rather than speed.
    for (var i = 0; i <= 10; i++) {
      meter.reportTimings(<FrameTiming>[
        _frame(1000000 + i * 16667, spanMicros: 4000),
      ]);
    }
    expect(meter.fps, closeTo(60.0, 0.01));
    expect(
      meter.millis,
      closeTo(4.0, 0.01),
      reason:
          'and this is the headroom number, which is the one that '
          'actually moved',
    );
  });

  test('the worst frame survives a good mean', () {
    final meter = FrameMeter();
    for (var i = 0; i < 9; i++) {
      meter.reportTimings(<FrameTiming>[
        _frame(1000000 + i * 16667, spanMicros: 4000),
      ]);
    }
    meter.reportTimings(<FrameTiming>[
      _frame(1000000 + 9 * 16667, spanMicros: 40000),
    ]);

    expect(meter.millis, lessThan(9.0), reason: 'the mean stays comfortable');
    expect(
      meter.worstMillis,
      closeTo(40.0, 0.01),
      reason:
          'and only this says a player saw a hitch - which is why a '
          'mean alone is not enough to report',
    );
  });

  test('the window rolls, and the total does not', () {
    final meter = FrameMeter();
    for (var i = 0; i < 200; i++) {
      meter.reportTimings(<FrameTiming>[
        _frame(1000000 + i * 16667, spanMicros: 4000),
      ]);
    }
    expect(
      meter.frameCount,
      200,
      reason: 'a counter of frames actually presented, not a windowed one',
    );
    expect(
      meter.fps,
      closeTo(60.0, 0.01),
      reason:
          'while the rate describes only the recent window - a fixed '
          'ring, so this costs no allocation however long a game runs',
    );
  });

  group('a high fps and a janky picture are not a contradiction', () {
    test('worstIntervalMillis catches a stall the average absorbs', () {
      final meter = FrameMeter();
      // Twenty frames arriving fast - 180fps territory - then one long stall,
      // then twenty more. Exactly the shape a desktop embedder that does not
      // vsync-throttle produces: plenty of throughput, visibly bad pacing.
      var at = 1000000;
      for (var i = 0; i < 20; i++) {
        at += 5555; // ~180Hz
        meter.reportTimings(<FrameTiming>[_frame(at, spanMicros: 3000)]);
      }
      at += 100000; // the screen froze for a tenth of a second
      meter.reportTimings(<FrameTiming>[_frame(at, spanMicros: 3000)]);
      for (var i = 0; i < 20; i++) {
        at += 5555;
        meter.reportTimings(<FrameTiming>[_frame(at, spanMicros: 3000)]);
      }

      expect(
        meter.fps,
        greaterThan(100),
        reason:
            'the throughput really is high - the average is not lying, '
            'it is answering a different question',
      );
      expect(
        meter.worstMillis,
        closeTo(3.0, 0.1),
        reason:
            'and no single frame was expensive to *make*, which is why '
            'frame time alone cannot find this either',
      );
      expect(
        meter.worstIntervalMillis,
        closeTo(100.0, 0.1),
        reason:
            'this is the only number that says the picture stopped '
            'moving for a tenth of a second - i.e. the only one that '
            'describes what a player actually saw',
      );
    });

    test('a steady 60Hz reads about one frame period', () {
      final meter = FrameMeter();
      for (var i = 0; i < 30; i++) {
        meter.reportTimings(<FrameTiming>[_frame(1000000 + i * 16667)]);
      }
      expect(
        meter.worstIntervalMillis,
        closeTo(16.667, 0.01),
        reason: 'no stall, so the worst gap is just the frame period',
      );
    });

    test('the gaps are read in frame order once the ring has wrapped', () {
      final meter = FrameMeter();
      // 200 frames through a 60-slot ring, with the stall late enough that it
      // is still inside the window. Walking the ring by slot index instead of
      // in arrival order would compute a gap across the wrap point and report
      // a huge negative-turned-positive nonsense.
      var at = 1000000;
      for (var i = 0; i < 195; i++) {
        at += 16667;
        meter.reportTimings(<FrameTiming>[_frame(at)]);
      }
      at += 50000;
      meter.reportTimings(<FrameTiming>[_frame(at)]);
      for (var i = 0; i < 4; i++) {
        at += 16667;
        meter.reportTimings(<FrameTiming>[_frame(at)]);
      }
      expect(meter.worstIntervalMillis, closeTo(50.0, 0.1));
    });
  });
}
