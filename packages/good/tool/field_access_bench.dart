// Where does a component field read actually go?
//
//   dart run packages/good/tool/field_access_bench.dart
//
// Run it with `dart run` (AOT-ish JIT with optimisation), not inside
// `flutter test` - the test binding adds its own overhead and this is measuring
// nanoseconds.
//
// The question this exists to answer: a `DataPointer[entity]` read resolves the
// row and then does `(base + byteOffset).cast<Double>().value`. Every one of
// those steps returns a **`Pointer`**, which is a real object - so unless the
// compiler manages to unbox it across the call boundaries, each field access
// allocates. At 10k entities and ~23 accesses each, that is ~230k allocations
// per tick, which would show up as exactly the symptom observed: enormous
// per-access cost plus jitter from collection pauses.
//
// The alternative is to resolve the row once and read through a cached
// `ByteData` over the same memory with an integer offset - no `Pointer`
// materialised per access at all.
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int _rows = 10000;
const int _stride = 256;
const int _fieldsPerRow = 23; // what WorldTransformSystem touches per entity
const int _reps = 20;

double _blackHole = 0;

/// The shape the engine uses today: pointer arithmetic per field.
double _viaPointer(Pointer<Uint8> base) {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final rowBase = base + row * _stride;
    for (var field = 0; field < _fieldsPerRow; field++) {
      sum += (rowBase + field * 8).cast<Double>().value;
    }
  }
  return sum;
}

/// The alternative: one cached view over the same bytes, integer offsets.
double _viaByteData(ByteData view) {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final rowBase = row * _stride;
    for (var field = 0; field < _fieldsPerRow; field++) {
      sum += view.getFloat64(rowBase + field * 8, Endian.host);
    }
  }
  return sum;
}

/// And a `Float64List` view, which needs no endianness decision and indexes by
/// element rather than by byte.
double _viaFloat64List(Float64List view) {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final rowBase = row * (_stride ~/ 8);
    for (var field = 0; field < _fieldsPerRow; field++) {
      sum += view[rowBase + field];
    }
  }
  return sum;
}

// --- the layers the engine actually goes through -------------------------
//
// Raw pointer arithmetic turned out to be ~1ns, so the 190x gap between that
// and the measured system time is not the memory access. These model the call
// chain around it, one layer at a time, to find which one costs.

/// Stands in for `ArchetypeStorage._pages` - a tombstoned list, so every
/// resolution is an index plus a null check.
late List<Pointer<Uint8>?> _pages;

/// `MemoryPage.resolveRead` returns `Pointer<Uint8>?`, and a **nullable**
/// pointer cannot be unboxed - so this models whether that null-ability is
/// what costs, rather than the arithmetic inside it.
Pointer<Uint8>? _resolveNullable(int page, int offset) {
  final base = _pages[page];
  return base == null ? null : base + offset;
}

Pointer<Uint8> _resolveNonNull(int page, int offset) => _pages[page]! + offset;

double _viaNullableChain() {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final offset = row * _stride;
    for (var field = 0; field < _fieldsPerRow; field++) {
      // `_readRow` is exactly this shape: a nullable resolve with a `??`
      // fallback, per field access.
      final p = _resolveNullable(0, offset) ?? _resolveNonNull(0, offset);
      sum += (p + field * 8).cast<Double>().value;
    }
  }
  return sum;
}

double _viaNonNullChain() {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final offset = row * _stride;
    for (var field = 0; field < _fieldsPerRow; field++) {
      sum += (_resolveNonNull(0, offset) + field * 8).cast<Double>().value;
    }
  }
  return sum;
}

// --- does a *nullable field* cost, the way a nullable return does? -------
//
// `TripleBuffer.readView` reads a `Pointer<Uint8>?` cache field and branches on
// it. If a nullable pointer field is as bad as a nullable return, the fix for
// the return just moved the cost one line down.

Pointer<Uint8>? _nullableField;
late Pointer<Uint8> _plainField;

Pointer<Uint8> get _viaNullableField {
  final cached = _nullableField;
  if (cached != null) return cached;
  return _plainField;
}

double _readThroughNullableField() {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final offset = row * _stride;
    for (var field = 0; field < _fieldsPerRow; field++) {
      sum += (_viaNullableField + offset + field * 8).cast<Double>().value;
    }
  }
  return sum;
}

double _readThroughPlainField() {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final offset = row * _stride;
    for (var field = 0; field < _fieldsPerRow; field++) {
      sum += (_plainField + offset + field * 8).cast<Double>().value;
    }
  }
  return sum;
}

int _time(String label, double Function() body) {
  // Warm up so the JIT has optimised the loop before anything is timed.
  for (var i = 0; i < 3; i++) {
    _blackHole += body();
  }
  final clock = Stopwatch()..start();
  for (var i = 0; i < _reps; i++) {
    _blackHole += body();
  }
  clock.stop();
  final perAccess =
      clock.elapsedMicroseconds * 1000 / (_reps * _rows * _fieldsPerRow);
  final perTick = clock.elapsedMicroseconds / _reps / 1000;
  print('${label.padRight(16)} '
      '${perAccess.toStringAsFixed(2).padLeft(7)} ns/access   '
      '${perTick.toStringAsFixed(2).padLeft(7)} ms per 10k-entity pass');
  return clock.elapsedMicroseconds;
}

void main() {
  final bytes = _rows * _stride;
  final base = calloc<Uint8>(bytes);
  try {
    final list = base.asTypedList(bytes);
    final doubles = base.cast<Double>().asTypedList(bytes ~/ 8);
    // Real values, not a byte pattern - a byte pattern reinterpreted as
    // doubles is mostly NaN, and NaN arithmetic is not what this measures.
    for (var i = 0; i < doubles.length; i++) {
      doubles[i] = i * 0.5;
    }
    final view = ByteData.sublistView(list);

    print('$_rows rows x $_fieldsPerRow fields, $_reps passes\n');
    _pages = <Pointer<Uint8>?>[base];
    _time('Pointer', () => _viaPointer(base));
    _time('chain non-null', _viaNonNullChain);
    _time('chain nullable', _viaNullableChain);
    _plainField = base;
    _nullableField = base;
    _time('field nullable', _readThroughNullableField);
    _time('field plain', _readThroughPlainField);
    _time('ByteData', () => _viaByteData(view));
    _time('Float64List', () => _viaFloat64List(doubles));
    print('\nblackhole $_blackHole');
  } finally {
    calloc.free(base);
  }
}
