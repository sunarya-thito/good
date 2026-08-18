// Is the counting sort in `_SpriteDrawQueue.sortByZ` actually faster than the
// merge sort it now defers to, and where is the crossover?
//
//   cd packages/goo2d
//   dart compile exe tool/sort_bench.dart -o build/sort_bench.exe
//   ./build/sort_bench.exe
//
// AOT, because the engine ships AOT and because JIT measurements of this
// renderer have already been wrong twice by an order of magnitude - see
// `write_pass_bench.dart`'s header. Sorting is plain integer array work with
// no megamorphic dispatch and no `ByteData`, so it is the *least* likely of
// the three to be distorted by JIT; running it here anyway is cheap and
// removes the question.
//
// # What is compared
//
// Byte-for-byte copies of the two implementations in `render_2d.dart`, over a
// shared `_zIndices`/`_order`/`_merge` triple laid out exactly as the queue
// lays it out. Copies rather than imports because `goo2d` reaches
// `package:flutter` and so cannot be AOT-compiled to an exe - the same reason
// `good/tool/column_dispatch_bench.dart` models its storage instead of using
// it. **If either copy drifts from the original, this bench stops meaning
// anything**, so both are kept as literal transcriptions with their structure
// intact rather than tidied.
//
// # The key distributions, and how this can fail
//
//   galaxy   the demo's own `4000 - radius`, ~380 distinct values
//   flat     every sprite at zIndex 0 - one bucket, the degenerate best case
//   spread   keys multiplied out past the 65,536-bucket cap
//
// The last one is the important one: it is the distribution the counting sort
// **refuses**, and the bench reports what it would have cost had it not. If
// `counting` were to beat `merge` there as well, the range threshold would be
// too conservative and worth raising; if it loses badly, the fallback earns
// its place. Either answer is a result, which is what makes running it worth
// the time.
import 'dart:math' as math;
import 'dart:typed_data';

const int _reps = 50;
const int _rounds = 5;
const List<int> _counts = <int>[1000, 5000, 20000, 40000];

/// The cap in `_SpriteDrawQueue._maxCountingRange`, restated here so the two
/// can be compared rather than assumed equal.
const int _maxCountingRange = 1 << 16;

int _sink = 0;

/// The three arrays `_SpriteDrawQueue` holds, plus the key range it tracks.
class _Queue {
  _Queue(this.keys)
    : n = keys.length,
      order = Int32List(keys.length),
      merge = Int32List(keys.length),
      counts = Int32List(_maxCountingRange) {
    var lo = keys[0];
    var hi = keys[0];
    for (var i = 0; i < n; i++) {
      if (keys[i] < lo) lo = keys[i];
      if (keys[i] > hi) hi = keys[i];
    }
    zMin = lo;
    range = hi - lo + 1;
  }

  final int n;
  final Int32List keys;
  Int32List order;
  Int32List merge;
  final Int32List counts;
  late final int zMin;
  late final int range;

  /// Back to the identity permutation, as `add` leaves it every tick.
  void reset() {
    for (var i = 0; i < n; i++) {
      order[i] = i;
    }
  }
}

/// Transcribed from `_SpriteDrawQueue._countingSortByZ`.
@pragma('vm:never-inline')
void _counting(_Queue q) {
  final range = q.range;
  final counts = q.counts;
  for (var k = 0; k < range; k++) {
    counts[k] = 0;
  }
  final keys = q.keys;
  final src = q.order;
  final min = q.zMin;
  final n = q.n;
  for (var i = 0; i < n; i++) {
    counts[keys[src[i]] - min]++;
  }
  var running = 0;
  for (var k = 0; k < range; k++) {
    final c = counts[k];
    counts[k] = running;
    running += c;
  }
  final dst = q.merge;
  for (var i = 0; i < n; i++) {
    final slot = src[i];
    dst[counts[keys[slot] - min]++] = slot;
  }
  q.merge = q.order;
  q.order = dst;
}

/// Transcribed from `_SpriteDrawQueue._mergeSortByZ`.
@pragma('vm:never-inline')
void _merge(_Queue q) {
  final n = q.n;
  final keys = q.keys;
  var src = q.order;
  var dst = q.merge;
  for (var width = 1; width < n; width *= 2) {
    for (var lo = 0; lo < n; lo += width * 2) {
      final mid = lo + width < n ? lo + width : n;
      final hi = lo + width * 2 < n ? lo + width * 2 : n;
      var i = lo;
      var j = mid;
      var k = lo;
      while (i < mid && j < hi) {
        dst[k++] = keys[src[i]] <= keys[src[j]] ? src[i++] : src[j++];
      }
      while (i < mid) {
        dst[k++] = src[i++];
      }
      while (j < hi) {
        dst[k++] = src[j++];
      }
    }
    final swap = src;
    src = dst;
    dst = swap;
  }
  if (!identical(src, q.order)) {
    q.merge = q.order;
    q.order = src;
  }
}

/// Both sorts must produce the identical permutation, or the faster one is
/// merely the one doing something else. Checked on every distribution the
/// counting sort accepts, because stability on ties is exactly what a
/// hand-rolled sort gets wrong.
///
/// Skipped, not forced, when the range exceeds the bucket cap: running the
/// counting sort there is an out-of-bounds write, which is precisely why the
/// real queue refuses that case. (Found by running it - the first draft
/// compared unconditionally and threw a `RangeError` on the `spread` set.)
bool _agree(Int32List keys) {
  final a = _Queue(keys);
  if (a.range > _maxCountingRange) return true;
  final b = _Queue(keys)..reset();
  a.reset();
  _counting(a);
  _merge(b);
  for (var i = 0; i < a.n; i++) {
    if (a.order[i] != b.order[i]) return false;
  }
  return true;
}

double _time(_Queue q, void Function(_Queue) sort) {
  for (var warm = 0; warm < 3; warm++) {
    q.reset();
    sort(q);
  }
  var best = double.infinity;
  for (var round = 0; round < _rounds; round++) {
    final clock = Stopwatch()..start();
    for (var rep = 0; rep < _reps; rep++) {
      q.reset();
      sort(q);
    }
    clock.stop();
    _sink += q.order[0];
    final ns = clock.elapsedMicroseconds * 1000.0 / (_reps * q.n);
    if (ns < best) best = ns;
  }
  return best;
}

/// The demo's own key: radius off a low-discrepancy sequence on the spawn
/// index, `zIndex = 4000 - radius`. About 380 distinct values.
Int32List _galaxy(int n) {
  final keys = Int32List(n);
  for (var i = 0; i < n; i++) {
    final u = (i * 0.6180339887498949) % 1.0;
    keys[i] = 4000 - (70 + 380 * math.sqrt(u)).round();
  }
  return keys;
}

Int32List _flat(int n) => Int32List(n);

/// Past the bucketing cap - the distribution the counting sort declines.
Int32List _spread(int n) {
  final keys = _galaxy(n);
  for (var i = 0; i < n; i++) {
    keys[i] *= 1000;
  }
  return keys;
}

void main() {
  final report = StringBuffer()
    ..writeln(
      '\nns per sprite sorted (best of $_rounds x $_reps reps)\n',
    )
    ..writeln('   distribution   sprites    range   counting      merge'
        '   speedup')
    ..writeln('   ${'-' * 66}');

  final distributions = <String, Int32List Function(int)>{
    'galaxy': _galaxy,
    'flat': _flat,
    'spread': _spread,
  };

  var allAgree = true;
  for (final entry in distributions.entries) {
    for (final n in _counts) {
      final keys = entry.value(n);
      allAgree = allAgree && _agree(keys);
      final probe = _Queue(keys);
      // The `spread` case is deliberately run through the counting sort even
      // though the real queue would refuse it, to price the fallback decision.
      final counting = probe.range <= _maxCountingRange
          ? _time(_Queue(keys)..reset(), _counting)
          : double.nan;
      final merge = _time(_Queue(keys)..reset(), _merge);
      String f(double v) =>
          (v.isNaN ? 'declined' : v.toStringAsFixed(1)).padLeft(11);
      final speedup = counting.isNaN
          ? '-'
          : '${(merge / counting).toStringAsFixed(1)}x';
      report.writeln(
        '   ${entry.key.padRight(13)}${n.toString().padLeft(7)}'
        '${probe.range.toString().padLeft(9)}${f(counting)}${f(merge)}'
        '${speedup.padLeft(10)}',
      );
    }
  }

  report
    ..writeln('\n   both sorts produce identical permutations: $allAgree')
    // Printed so the sink is genuinely *read*. One that is only ever assigned
    // is dead by definition - to the analyzer, which says so, and potentially
    // to the optimiser, which is the reason it exists at all.
    ..writeln('   sink: $_sink');
  // ignore: avoid_print
  print(report);
}
