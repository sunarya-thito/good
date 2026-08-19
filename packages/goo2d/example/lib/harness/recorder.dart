import 'package:goo2d_example/demo/demo_game.dart';

/// Collects a run of samples and reports mean/min/max, so a measurement can be
/// pasted somewhere instead of read off a moving overlay.
///
/// **Min matters as much as mean.** These are wall-clock timings and the game
/// isolate shares a machine with Flutter's UI and raster threads; preemption
/// only ever adds. The minimum is the closest a stopwatch gets to "how much
/// work is this", and the gap between min and mean is how contended the
/// machine was while measuring.
///
/// No widgets here on purpose - this is the numbers, and the harness's widgets
/// only display what it produces.
class DemoRecorder {
  /// Series that are plain counts, not microsecond timings.
  static const Set<String> _counts = <String>{'sim fps', 'fps', 'steps'};

  final Map<String, List<int>> _series = <String, List<int>>{};
  final Stopwatch _clock = Stopwatch();
  int _samples = 0;

  bool get isRecording => _clock.isRunning;
  int get sampleCount => _samples;

  void start() {
    _series.clear();
    _samples = 0;
    _clock
      ..reset()
      ..start();
  }

  void stop() => _clock.stop();

  void _add(String name, int value) => (_series[name] ??= <int>[]).add(value);

  /// Takes one sample of everything the overlay shows.
  ///
  /// Driven by a channel notification rather than a timer, so this is exactly
  /// one sample per published frame - no double counting a tick and no missing
  /// one.
  void sample(DemoGame game) {
    if (!isRecording) return;
    _samples++;
    // Never zero in practice - an advance that afforded no step publishes
    // nothing, so the notification this rides does not fire - but dividing by
    // a published value is worth one guard.
    final steps = game.stepsPerAdvance.value < 1
        ? 1
        : game.stepsPerAdvance.value;
    _add('sim fps', game.simulationFps.round());
    _add('fps', game.fps.round());
    _add('steps', game.stepsPerAdvance.value);
    _add('case', game.caseMicros.value);
    _add('present', game.presentMicros.value);
    _add('  render', game.renderMicros.value);
    _add('systems', game.systemMicros.value);
    _add('step', game.stepMicros.value);
    // The two that are comparable across entity counts: per *step*, which is
    // the unit `case` and `present` are already in. See
    // `DemoGame.stepsPerAdvance` for what reading the raw pair once cost.
    _add('systems/st', game.systemMicros.value ~/ steps);
    _add('step/st', game.stepMicros.value ~/ steps);
    _add('advance', game.advanceMicros.value);
    _add('interval', game.intervalMicros.value);
  }

  /// A block of plain text, deliberately - it is meant to be selected and
  /// pasted somewhere, which a table of widgets is not.
  String report(String caseName, int entities) {
    final buffer = StringBuffer()
      ..writeln('case: $caseName   entities: $entities')
      ..writeln(
        'samples: $_samples over '
        '${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
      )
      ..writeln('');
    for (final entry in _series.entries) {
      final values = entry.value;
      if (values.isEmpty) continue;
      var total = 0;
      var min = values.first;
      var max = values.first;
      for (final value in values) {
        total += value;
        if (value < min) min = value;
        if (value > max) max = value;
      }
      final mean = total / values.length;
      final isCount = _counts.contains(entry.key.trim());
      final scale = isCount ? 1.0 : 1000.0;
      final unit = isCount ? '' : ' ms';
      String fmt(num v) => (v / scale).toStringAsFixed(2);
      buffer.writeln(
        '${entry.key.padRight(12)} '
        'mean ${fmt(mean).padLeft(8)}$unit   '
        'min ${fmt(min).padLeft(8)}$unit   '
        'max ${fmt(max).padLeft(8)}$unit',
      );
    }
    return buffer.toString();
  }
}
