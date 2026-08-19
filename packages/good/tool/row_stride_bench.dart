// What does one byte of row stride cost, per entity, per tick?
//
//   cd packages/good
//   dart compile exe tool/row_stride_bench.dart -o build/row_stride_bench.exe
//   ./build/row_stride_bench.exe
//
// **AOT**, via `dart compile exe`, for the reason `goo2d/tool/write_pass_bench`
// spells out at length: the same question asked under `flutter test` is asked
// of a JIT build, which has priced this engine's memory work wrong by two
// orders of magnitude before.
//
// # The question
//
// A component row is an array of structs. A system reading 20 fields out of it
// still drags every byte of the row through the cache, so shrinking the row
// helps even when the bytes removed were never read. Layout changes therefore
// arrive as "this saves N bytes per row" and get argued about in the abstract.
// This turns N into nanoseconds.
//
// The shape modelled is `WorldTransformSystem`'s flat walk, which is the
// heaviest per-entity loop in the fixed step: rows in address order, and out of
// each one ten float64 reads and ten float64 writes, all within the first ~120
// bytes. Everything past that in the row is never touched and exists only to
// push the stride out - exactly the `Renderable2D` fields that walk ignores.
//
// # Reading the output
//
// The strides bracket the ones that prompted this. A `Child` + `Parent`
// archetype is 41 bytes of hierarchy alone; the demo's flat mote archetype is
// 169 with the presence flags packed and 174 without. The wide ends (120 and
// 256) are there so the bench can be seen to work: if those two do not differ,
// nothing between them means anything either.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Two populations: one whose rows fit a typical L2, one that cannot. The
/// stride only costs anything once the walk is missing, so a bench run at one
/// size only would be answering half the question.
const List<int> _counts = <int>[20000, 200000];

/// The pair under test (169/174), a pair far enough apart to prove the bench
/// responds at all (120/256), and enough between them to read a slope off.
const List<int> _strides = <int>[120, 128, 144, 160, 169, 174, 192, 224, 256];

const int _warmReps = 5;
const int _timedReps = 40;

/// The whole measurement is the memory system's behaviour, so anything else
/// competing for the cache lands in it as a large upward spike. Reporting the
/// best of several trials rather than the mean is what makes the smaller
/// population readable at all - at 20,000 rows a single run varied by 3x.
const int _trials = 7;

/// Byte offsets of what the walk touches, mirroring the field order
/// `Transform2D` then `WorldTransform2D` declares: five local float64s, then
/// five world ones, then five cached ones.
const int _localBase = 0;
const int _worldBase = 40;
const int _cachedBase = 80;

double _blackHole = 0;

/// One pass of the childless resolve: read the local transform and the cached
/// copy of it, compose (trivially - the arithmetic is not what is being timed),
/// then write the world transform and refresh the cache.
void _walk(Pointer<Uint8> base, int rows, int stride) {
  var acc = 0.0;
  for (var row = 0; row < rows; row++) {
    final r = base.address + row * stride;
    for (var f = 0; f < 5; f++) {
      final local = Pointer<Double>.fromAddress(r + _localBase + f * 8).value;
      final cached = Pointer<Double>.fromAddress(r + _cachedBase + f * 8).value;
      acc += local + cached;
      Pointer<Double>.fromAddress(r + _worldBase + f * 8).value = local + 1.0;
      Pointer<Double>.fromAddress(r + _cachedBase + f * 8).value = local;
    }
  }
  _blackHole += acc;
}

void main() {
  print('WorldTransformSystem-shaped walk: 10 float64 reads + 10 writes per');
  print('row, all within the first 120 bytes. Only the stride varies.');
  print('');
  print('  ns per entity per tick');
  print('  stride${_counts.map((c) => '$c'.padLeft(12)).join()}');

  final results = <int, Map<int, double>>{};
  for (final stride in _strides) {
    final row = <int, double>{};
    for (final rows in _counts) {
      final base = calloc<Uint8>(rows * stride);
      try {
        for (var i = 0; i < _warmReps; i++) {
          _walk(base, rows, stride);
        }
        var best = double.infinity;
        for (var trial = 0; trial < _trials; trial++) {
          final sw = Stopwatch()..start();
          for (var i = 0; i < _timedReps; i++) {
            _walk(base, rows, stride);
          }
          sw.stop();
          final ns = sw.elapsedMicroseconds * 1000 / (_timedReps * rows);
          if (ns < best) best = ns;
        }
        row[rows] = best;
      } finally {
        calloc.free(base);
      }
    }
    results[stride] = row;
    print(
      '  ${stride.toString().padLeft(6)}'
      '${_counts.map((c) => row[c]!.toStringAsFixed(2).padLeft(12)).join()}',
    );
  }

  print('');
  print('  cost of one byte of stride, over the range measured:');
  for (final rows in _counts) {
    final lo = results[_strides.first]![rows]!;
    final hi = results[_strides.last]![rows]!;
    final perByte = (hi - lo) / (_strides.last - _strides.first);
    print(
      '    $rows rows: ${perByte.toStringAsFixed(4)} ns/byte'
      ' -> 5 bytes is ${(perByte * 5).toStringAsFixed(3)} ns/entity',
    );
  }
  print('');
  print('  blackhole ${_blackHole.isFinite}');
}
