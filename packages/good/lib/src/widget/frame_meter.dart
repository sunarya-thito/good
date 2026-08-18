import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:meta/meta.dart';

/// What the display is actually doing, measured on the Flutter isolate.
///
/// # Why this is not derived from the tick counter
///
/// `Game.tick` counts *simulation* steps, and those are deliberately decoupled
/// from frames: the fixed step runs at `fixedTimeStep` whatever the display is
/// managing, which is the whole point of a fixed timestep. A game whose
/// renderer is drowning still ticks 60 times a second and would report a
/// perfect 60 "fps" from its tick count, right up until it stopped drawing
/// entirely. So frames are counted where frames happen.
///
/// # [fps] is counted, not computed from a delta
///
/// Every frame the engine actually presented increments [frameCount]. [fps] is
/// that count over the wall clock it spanned - nothing here is `1 / delta`.
///
/// That distinction is the usual way an in-game counter lies. [millis] is how
/// long a frame took to build and raster; [fps] is how often frames arrived,
/// and they are not reciprocals. A game comfortably inside its budget spends
/// 4ms of a 16.67ms frame and still presents exactly 60 times a second -
/// `1 / 0.004` would report 250fps for it, which is not a thing that happened.
/// vsync sets the ceiling; the frame time only says how close to it you are.
///
/// # A high [fps] and a janky picture are not a contradiction
///
/// [fps] is a **throughput** number and jank is a **pacing** problem, so they
/// can disagree completely and both be right. Sixty frames delivered as fifty
/// in the first half-second and ten in the next average to 60fps and look
/// terrible. Some platforms make this the normal case: a desktop embedder that
/// does not vsync-throttle will happily report 180fps while the picture
/// visibly stutters.
///
/// [worstIntervalMillis] is the number that catches it - the longest the screen
/// went without a new frame. If [fps] says 180 and that says 90, the screen
/// froze for a tenth of a second inside the window and the average absorbed it.
///
/// So the four answer four different questions: [fps] is "how many arrived",
/// [millis] is "how much headroom is left", [worstMillis] is "was any single
/// frame expensive to make", and [worstIntervalMillis] is "did the picture ever
/// stop moving". Only the last one is jank.
@internal
final class FrameMeter {
  /// Timestamps of the last [_window] frames, in microseconds.
  ///
  /// A fixed-size ring rather than a growing list: this is fed by the engine
  /// once per frame forever, and anything that allocates per frame here would
  /// be measuring its own overhead (the hot-path rules).
  static const int _window = 60;

  final List<int> _at = List<int>.filled(_window, 0);
  final List<int> _span = List<int>.filled(_window, 0);
  int _count = 0;
  int _next = 0;
  int _total = 0;

  bool _armed = false;

  /// Starts listening. Idempotent - two `GameView`s on one game arm once.
  void arm() {
    if (_armed) return;
    _armed = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Stops listening and forgets the window, so a game that comes back on
  /// screen reports what it is doing *now* rather than blending in what it was
  /// doing before it went away.
  void disarm() {
    if (!_armed) return;
    _armed = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _count = 0;
    _next = 0;
  }

  /// Frames the engine has actually presented while this was armed.
  ///
  /// A plain counter, incremented once per real frame - the ground truth [fps]
  /// is derived from. Monotonic across a view going away and coming back;
  /// [disarm] forgets the *window*, not the total.
  int get frameCount => _total;

  /// Feeds timings in directly.
  ///
  /// The widget test binding does **not** drive `addTimingsCallback` -
  /// `tester.pump()` runs the pipeline but the engine's frame *reporting* is
  /// not simulated, so a test that pumps three frames sees zero here. That is
  /// a limitation of the harness, not of the wiring, and it would leave the
  /// counting and rate arithmetic below completely uncovered. So the seam is
  /// here rather than nowhere.
  @visibleForTesting
  void reportTimings(List<FrameTiming> timings) => _onTimings(timings);

  void _onTimings(List<FrameTiming> timings) {
    for (var i = 0; i < timings.length; i++) {
      final timing = timings[i];
      record(
        timing.timestampInMicroseconds(FramePhase.rasterFinish),
        timing.totalSpan.inMicroseconds,
      );
    }
  }

  /// Records one event by hand, for a producer that is not the Flutter frame
  /// pipeline.
  ///
  /// The simulation is the case: it publishes a new picture once per
  /// presentation pass, and *that* rate is what a player perceives as the
  /// frame rate when it is lower than the display's. Same ring, same
  /// arithmetic, different producer - so the two rates are directly
  /// comparable, which is the whole point of measuring both.
  @internal
  void record(int atMicros, [int spanMicros = 0]) {
    _at[_next] = atMicros;
    _span[_next] = spanMicros;
    _next = (_next + 1) % _window;
    if (_count < _window) _count++;
    _total++;
  }

  /// Frames presented per second: how many frames were counted in the window,
  /// divided by the wall clock between the first and the last of them.
  ///
  /// Zero until two frames have been seen - a rate needs an interval, and
  /// guessing one from a single frame would report a number before there is
  /// one. Zero is also what a game nobody is looking at reports, which is the
  /// honest answer rather than a stale last-known value.
  double get fps {
    if (_count < 2) return 0;
    final oldest = _at[_count < _window ? 0 : _next];
    final newest = _at[(_next - 1 + _window) % _window];
    final elapsed = newest - oldest;
    if (elapsed <= 0) return 0;
    return (_count - 1) * 1000000.0 / elapsed;
  }

  /// Mean build-plus-raster time per frame, in milliseconds. The headroom
  /// number: at 60Hz the budget is 16.67.
  double get millis {
    if (_count == 0) return 0;
    var total = 0;
    for (var i = 0; i < _count; i++) {
      total += _span[i];
    }
    return total / _count / 1000.0;
  }

  /// The most expensive single frame in the window, in milliseconds - how long
  /// the slowest one took to build and raster.
  ///
  /// Note this is *work*, not *delay*: a frame can be cheap to produce and
  /// still arrive late. [worstIntervalMillis] is the one that measures the
  /// wait.
  double get worstMillis {
    var worst = 0;
    for (var i = 0; i < _count; i++) {
      if (_span[i] > worst) worst = _span[i];
    }
    return worst / 1000.0;
  }

  /// The longest the picture went without a new frame, in milliseconds.
  ///
  /// **This is the jank number.** [fps] averages the window and therefore hides
  /// exactly the thing a player notices: a stall. At a steady 60Hz this reads
  /// about 16.7; a single dropped frame doubles it, and anything much above
  /// that is a stutter someone saw.
  ///
  /// Measured between consecutive frames' raster-finish timestamps, so it is a
  /// difference within one clock domain and does not care what the epoch is.
  double get worstIntervalMillis {
    if (_count < 2) return 0;
    var worst = 0;
    // Oldest to newest, following the ring rather than the slot order - the
    // gaps only mean anything in the order the frames actually happened.
    final first = _count < _window ? 0 : _next;
    for (var n = 1; n < _count; n++) {
      final previous = _at[(first + n - 1) % _window];
      final current = _at[(first + n) % _window];
      final gap = current - previous;
      if (gap > worst) worst = gap;
    }
    return worst / 1000.0;
  }
}
