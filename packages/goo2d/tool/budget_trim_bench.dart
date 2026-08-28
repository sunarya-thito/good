// What does spending the record budget after the sort cost a frame that fits?
//
//   cd packages/goo2d
//   dart compile exe tool/budget_trim_bench.dart -o build/budget_trim_bench.exe
//   ./build/budget_trim_bench.exe
//
// AOT, because the engine ships AOT and because JIT measurements of this
// renderer have already been wrong by two orders of magnitude - see
// `write_pass_bench.dart`'s header.
//
// # The question
//
// `_SpriteDrawQueue.trimToBudget` runs once per view per frame, after
// `sortByZ`. On a frame that fits it must be free, because that is every frame
// a shipped game renders; on a frame that does not, it walks the sorted order
// from the camera backwards admitting records until one does not fit. #175
// moved the budget here from the fill pass, where it was spent in archetype
// registration order.
//
// # What is compared
//
//   fits       the queued total is inside the budget - one comparison
//   over       the queued total is 5x the budget - the back-walk runs
//   worst      every candidate costs 1, so the walk is as long as it can be
//
// The last one is the honest upper bound: the walk stops after admitting
// `budget` records, and one-record candidates make that `budget` iterations,
// which is the most it can ever be. A tilemap is exactly that shape. It is
// within noise of `over` for the same reason - the walk length is set by the
// budget, not by how many candidates were queued behind it, so queuing five
// times as many does not make the trim five times slower.
//
// Byte-for-byte transcriptions of `_SpriteDrawQueue`'s arrays, its counting
// sort and `trimToBudget`, because `goo2d` reaches `package:flutter` and
// cannot be AOT-compiled - the same reason `sort_bench.dart` transcribes
// instead of importing. **If a copy drifts from the original this bench stops
// meaning anything**, so it is kept literal rather than tidied.
import 'dart:typed_data';

const int _reps = 20000;
const int _rounds = 5;
const List<int> _budgets = <int>[4096, 16384];

int _sink = 0;

/// The arrays `_SpriteDrawQueue` holds that the trim touches, plus the two
/// fields `reset` leaves at their fitting values.
class _Queue {
  _Queue(this.keys, this.records)
    : n = keys.length,
      order = Int32List(keys.length),
      merge = Int32List(keys.length),
      counts = Int32List(1 << 16) {
    var lo = keys[0];
    var hi = keys[0];
    var total = 0;
    for (var i = 0; i < n; i++) {
      if (keys[i] < lo) lo = keys[i];
      if (keys[i] > hi) hi = keys[i];
      total += records[i];
    }
    zMin = lo;
    range = hi - lo + 1;
    recordTotal = total;
  }

  final int n;
  final Int32List keys;
  final Int32List records;
  Int32List order;
  Int32List merge;
  final Int32List counts;
  late final int zMin;
  late final int range;
  late final int recordTotal;

  int first = 0;
  int trimmed = 0;

  /// What `reset` leaves behind, plus the identity permutation `add` writes.
  void reset() {
    first = 0;
    trimmed = 0;
    for (var i = 0; i < n; i++) {
      order[i] = i;
    }
  }
}

/// Transcribed from `_SpriteDrawQueue._countingSortByZ`.
@pragma('vm:never-inline')
void _sort(_Queue q) {
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

/// Transcribed from `_SpriteDrawQueue.trimToBudget`.
@pragma('vm:never-inline')
void _trim(_Queue q, int limit) {
  if (q.recordTotal <= limit) return;
  final records = q.records;
  final order = q.order;
  var admitted = 0;
  var i = q.n;
  while (i > 0) {
    final cost = records[order[i - 1]];
    if (admitted + cost > limit) break;
    admitted += cost;
    i--;
  }
  q.first = i;
  q.trimmed = q.recordTotal - admitted;
}

/// Microseconds for one trim, best of [_rounds].
///
/// The sort is *outside* the timed loop: the trim is what is being measured
/// and re-sorting per rep would bury it. The permutation the sort leaves is
/// the one the trim then reads, which is the whole point of running it at
/// all - a trim over the identity permutation walks a different array order.
double _time(_Queue q, int limit) {
  q.reset();
  _sort(q);
  for (var warm = 0; warm < 5; warm++) {
    _trim(q, limit);
  }
  var best = double.infinity;
  for (var round = 0; round < _rounds; round++) {
    final clock = Stopwatch()..start();
    for (var rep = 0; rep < _reps; rep++) {
      _trim(q, limit);
    }
    clock.stop();
    _sink += q.first + q.trimmed;
    final us = clock.elapsedMicroseconds / _reps;
    if (us < best) best = us;
  }
  return best;
}

/// Layered depths, the shape a scene actually has: a few hundred distinct
/// `zIndex` values across the queue.
Int32List _depths(int n) {
  final keys = Int32List(n);
  for (var i = 0; i < n; i++) {
    keys[i] = (i * 7919) % 380;
  }
  return keys;
}

Int32List _flat(int n, int cost) => Int32List(n)..fillRange(0, n, cost);

/// A UI-ish mix: mostly plain quads, one sprite in twelve nine-sliced.
Int32List _mixed(int n) {
  final records = Int32List(n);
  for (var i = 0; i < n; i++) {
    records[i] = i % 12 == 0 ? 9 : 1;
  }
  return records;
}

void main() {
  print('one trim, microseconds, best of $_rounds x $_reps reps');
  print('');
  print('budget      n  candidates  records     case      us');
  for (final budget in _budgets) {
    // A frame that fits, a frame five times over, and the longest walk the
    // trim can be made to do.
    final cases = <(String, int, Int32List)>[
      ('fits', budget ~/ 2, _flat(budget ~/ 2, 1)),
      ('fits-mixed', budget ~/ 4, _mixed(budget ~/ 4)),
      ('over-5x', budget * 5, _flat(budget * 5, 1)),
      ('over-mixed', budget * 5, _mixed(budget * 5)),
      ('worst', budget * 2, _flat(budget * 2, 1)),
    ];
    for (final (name, n, records) in cases) {
      final q = _Queue(_depths(n), records);
      final us = _time(q, budget);
      print(
        '${budget.toString().padLeft(6)}'
        '${n.toString().padLeft(7)}'
        '${q.n.toString().padLeft(12)}'
        '${q.recordTotal.toString().padLeft(9)}'
        '${name.padLeft(13)}'
        '${us.toStringAsFixed(3).padLeft(8)}',
      );
    }
  }
  if (_sink == -1) print('unreachable');
}
