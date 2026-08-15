// What does going through `DataPointer<T>` actually cost?
//
//   dart compile exe packages/goo/tool/column_dispatch_bench.dart -o bench.exe
//   ./bench.exe
//
// AOT, not `dart run`: JIT and AOT weight devirtualisation differently, and the
// engine ships AOT. Run it JIT too if you like, but the AOT number is the one
// that decides anything.
//
// `field_access_bench.dart` established that the raw read is ~1ns while a real
// system pays ~25ns, and then modelled the *pointer plumbing* around it -
// nullable returns, nullable fields, cached views. Every call site it measures
// is statically resolved. The one layer it never modelled is the one the engine
// actually forces on every field access: an **abstract generic** class with many
// implementations alive at once.
//
// Two separate things could be hiding in there, and they have different fixes:
//
//   * **Dispatch.** Many `DataPointer` subclasses exist (`_Int64Field`,
//     `_OptionalField`, `_HeapObjectField`, `_EntityField`, ...), so
//     `operator []` is a megamorphic call site the compiler cannot inline.
//   * **Boxing.** `operator []` returns `T`. A `double` returned through a
//     generic interface does not reliably stay unboxed - every access would
//     allocate, which at 10k entities x 23 fields is ~230k allocations a tick.
//
// Time alone cannot separate them, so this measures a ladder where each rung
// adds exactly one property:
//
//   raw          inline pointer arithmetic, no call            (floor)
//   mono         final class, non-generic, one impl alive      (+ a call)
//   megamorphic  abstract, non-generic, many impls alive       (+ dispatch)
//   generic      abstract, generic, many impls alive           (+ boxing)
//
// So `mega - mono` is the cost of dispatch, and `generic - mega` is the cost of
// the type parameter. If the second gap is the big one, the fix is to drop the
// generic and keep the abstraction; if the first is, the abstraction itself has
// to go. If both are small, my hypothesis is wrong and the 25ns is somewhere
// else entirely - which is the outcome this is built to be able to report.
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int _rows = 10000;
const int _stride = 256;
const int _columns = 23; // what WorldTransformSystem touches per entity
const int _reps = 20;

/// Mirrors the real handle: `(archetypeId 16, pageIndex 16, rowOffset 32)`.
/// Only the row offset is used here, but it is unpacked rather than passed
/// bare so every rung pays the same masking the engine pays.
extension type const Entity(int value) {
  int get rowOffset => value & 0xFFFFFFFF;
}

// --- rung 1: the floor ---------------------------------------------------

double _raw(Pointer<Uint8> base) {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final entity = Entity(row * _stride);
    for (var column = 0; column < _columns; column++) {
      sum += (base + entity.rowOffset + column * 8).cast<Double>().value;
    }
  }
  return sum;
}

// --- rung 2: monomorphic, non-generic ------------------------------------

/// `final` so the compiler knows there is nothing below it, non-generic so
/// `read` returns an honest unboxed `double`. This is the shape I want to
/// argue the engine should move to.
final class Float64Column {
  const Float64Column(this._base, this._offset);

  final Pointer<Uint8> _base;
  final int _offset;

  @pragma('vm:prefer-inline')
  double read(Entity entity) =>
      (_base + entity.rowOffset + _offset).cast<Double>().value;
}

double _mono(List<Float64Column> columns) {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final entity = Entity(row * _stride);
    for (var column = 0; column < columns.length; column++) {
      sum += columns[column].read(entity);
    }
  }
  return sum;
}

// --- rung 3: megamorphic, still non-generic ------------------------------
//
// Four implementations, all instantiated and all reachable from the same call
// site, so the site genuinely goes megamorphic rather than being speculatively
// devirtualised behind a class check. The bodies are deliberately identical -
// the point is the dispatch, not the work.

abstract class DoubleColumn {
  double read(Entity entity);
}

class _DoubleA extends DoubleColumn {
  _DoubleA(this.base, this.offset);
  final Pointer<Uint8> base;
  final int offset;
  @override
  double read(Entity entity) =>
      (base + entity.rowOffset + offset).cast<Double>().value;
}

class _DoubleB extends DoubleColumn {
  _DoubleB(this.base, this.offset);
  final Pointer<Uint8> base;
  final int offset;
  @override
  double read(Entity entity) =>
      (base + entity.rowOffset + offset).cast<Double>().value;
}

class _DoubleC extends DoubleColumn {
  _DoubleC(this.base, this.offset);
  final Pointer<Uint8> base;
  final int offset;
  @override
  double read(Entity entity) =>
      (base + entity.rowOffset + offset).cast<Double>().value;
}

class _DoubleD extends DoubleColumn {
  _DoubleD(this.base, this.offset);
  final Pointer<Uint8> base;
  final int offset;
  @override
  double read(Entity entity) =>
      (base + entity.rowOffset + offset).cast<Double>().value;
}

double _mega(List<DoubleColumn> columns) {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final entity = Entity(row * _stride);
    for (var column = 0; column < columns.length; column++) {
      sum += columns[column].read(entity);
    }
  }
  return sum;
}

// --- rung 4: what the engine has today -----------------------------------
//
// Same four implementations, same bodies, one difference: the return type is a
// type parameter and the operator is a subscript. This is `DataPointer<double>`
// with the engine's own field classes standing in.

abstract class GenericColumn<T> {
  T operator [](Entity entity);
}

class _GenericA extends GenericColumn<double> {
  _GenericA(this.base, this.offset);
  final Pointer<Uint8> base;
  final int offset;
  @override
  double operator [](Entity entity) =>
      (base + entity.rowOffset + offset).cast<Double>().value;
}

class _GenericB extends GenericColumn<double> {
  _GenericB(this.base, this.offset);
  final Pointer<Uint8> base;
  final int offset;
  @override
  double operator [](Entity entity) =>
      (base + entity.rowOffset + offset).cast<Double>().value;
}

class _GenericC extends GenericColumn<double> {
  _GenericC(this.base, this.offset);
  final Pointer<Uint8> base;
  final int offset;
  @override
  double operator [](Entity entity) =>
      (base + entity.rowOffset + offset).cast<Double>().value;
}

/// The odd one out on purpose: a nullable payload, like `_OptionalField`. Its
/// presence is what makes `T` genuinely varied across the hierarchy rather than
/// uniformly `double`, which is the situation the real `DataPointer` is in.
class _GenericNullable extends GenericColumn<double?> {
  _GenericNullable(this.base, this.offset);
  final Pointer<Uint8> base;
  final int offset;
  @override
  double? operator [](Entity entity) =>
      (base + entity.rowOffset + offset).cast<Double>().value;
}

double _generic(List<GenericColumn<double>> columns) {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final entity = Entity(row * _stride);
    for (var column = 0; column < columns.length; column++) {
      sum += columns[column][entity];
    }
  }
  return sum;
}

// --- rung 5: same shape, but the base is an `int` ------------------------
//
// Rungs 1-4 put the whole cost at "read a `Pointer` out of a field". `Pointer`
// is a real Dart object, so a field holding one is a boxed reference: each
// access loads it, unboxes it, and then `+ offset` materialises *another*
// `Pointer` just to reach `.value`. Storing the address as a plain `int` and
// rebuilding the pointer per access tests whether `fromAddress` is cheaper than
// carrying the box - it still allocates a `Pointer`, so this is expected to be
// no better, and is here to prove the allocation rather than the field load is
// what costs.

final class AddressColumn {
  const AddressColumn(this._address, this._offset);

  final int _address;
  final int _offset;

  @pragma('vm:prefer-inline')
  double read(Entity entity) =>
      Pointer<Double>.fromAddress(_address + entity.rowOffset + _offset).value;
}

double _address(List<AddressColumn> columns) {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final entity = Entity(row * _stride);
    for (var column = 0; column < columns.length; column++) {
      sum += columns[column].read(entity);
    }
  }
  return sum;
}

// --- rung 6: a typed-data view and an integer index ----------------------
//
// No `Pointer` anywhere on the access path. The view is created once over the
// same native memory and stored in the field; a read is a bounds-checked load
// out of a `Float64List` at an integer element index. If the diagnosis above is
// right, this should land near the raw floor - and it is a shape the engine can
// actually adopt, because the memory is unchanged and only the accessor moves.

final class ViewColumn {
  const ViewColumn(this._view, this._element);

  final Float64List _view;
  final int _element;

  @pragma('vm:prefer-inline')
  double read(Entity entity) => _view[(entity.rowOffset >> 3) + _element];
}

double _view(List<ViewColumn> columns) {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final entity = Entity(row * _stride);
    for (var column = 0; column < columns.length; column++) {
      sum += columns[column].read(entity);
    }
  }
  return sum;
}

// --- rung 7: the view, reached megamorphically ---------------------------
//
// Rung 6 with the abstraction back on top, because the engine cannot ship a
// single concrete column type - optional fields, entity fields and object
// fields all have genuinely different bodies. This is the honest shape of the
// proposal: cheap access *plus* the polymorphism the design needs.

abstract class ViewBackedColumn {
  double read(Entity entity);
}

class _ViewA extends ViewBackedColumn {
  _ViewA(this.view, this.element);
  final Float64List view;
  final int element;
  @override
  double read(Entity entity) => view[(entity.rowOffset >> 3) + element];
}

class _ViewB extends ViewBackedColumn {
  _ViewB(this.view, this.element);
  final Float64List view;
  final int element;
  @override
  double read(Entity entity) => view[(entity.rowOffset >> 3) + element];
}

class _ViewC extends ViewBackedColumn {
  _ViewC(this.view, this.element);
  final Float64List view;
  final int element;
  @override
  double read(Entity entity) => view[(entity.rowOffset >> 3) + element];
}

class _ViewD extends ViewBackedColumn {
  _ViewD(this.view, this.element);
  final Float64List view;
  final int element;
  @override
  double read(Entity entity) => view[(entity.rowOffset >> 3) + element];
}

double _viewMega(List<ViewBackedColumn> columns) {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final entity = Entity(row * _stride);
    for (var column = 0; column < columns.length; column++) {
      sum += columns[column].read(entity);
    }
  }
  return sum;
}

// --- rung 8: the actual proposal -----------------------------------------
//
// Everything the engine has today - `DataPointer<T>`'s generic subscript, four
// implementations live, a nullable one among them - with exactly one change:
// the base is an `int` address instead of a `Pointer` field.
//
// This is the rung that decides the work. If it lands near `int address`, the
// public API does not change at all: `DataPointer<T>` survives, every mixin's
// `late final DataPointer<double>` declaration survives, user code survives,
// and the fix is confined to how the field classes hold their base. If instead
// it lands near `generic`, then the abstraction really is the problem and the
// change is a breaking one.

abstract class GenericAddressColumn<T> {
  T operator [](Entity entity);
}

class _AddrA extends GenericAddressColumn<double> {
  _AddrA(this.address, this.offset);
  final int address;
  final int offset;
  @override
  double operator [](Entity entity) =>
      Pointer<Double>.fromAddress(address + entity.rowOffset + offset).value;
}

class _AddrB extends GenericAddressColumn<double> {
  _AddrB(this.address, this.offset);
  final int address;
  final int offset;
  @override
  double operator [](Entity entity) =>
      Pointer<Double>.fromAddress(address + entity.rowOffset + offset).value;
}

class _AddrC extends GenericAddressColumn<double> {
  _AddrC(this.address, this.offset);
  final int address;
  final int offset;
  @override
  double operator [](Entity entity) =>
      Pointer<Double>.fromAddress(address + entity.rowOffset + offset).value;
}

/// The nullable sibling again, so `T` is genuinely varied across the hierarchy.
class _AddrNullable extends GenericAddressColumn<double?> {
  _AddrNullable(this.address, this.offset);
  final int address;
  final int offset;
  @override
  double? operator [](Entity entity) =>
      Pointer<Double>.fromAddress(address + entity.rowOffset + offset).value;
}

double _genericAddress(List<GenericAddressColumn<double>> columns) {
  var sum = 0.0;
  for (var row = 0; row < _rows; row++) {
    final entity = Entity(row * _stride);
    for (var column = 0; column < columns.length; column++) {
      sum += columns[column][entity];
    }
  }
  return sum;
}

// -------------------------------------------------------------------------

double _blackHole = 0;

void _time(String label, double Function() body) {
  for (var i = 0; i < 3; i++) {
    _blackHole += body();
  }
  final clock = Stopwatch()..start();
  for (var i = 0; i < _reps; i++) {
    _blackHole += body();
  }
  clock.stop();
  final perAccess =
      clock.elapsedMicroseconds * 1000 / (_reps * _rows * _columns);
  final perTick = clock.elapsedMicroseconds / _reps / 1000;
  print('${label.padRight(14)} '
      '${perAccess.toStringAsFixed(2).padLeft(7)} ns/access   '
      '${perTick.toStringAsFixed(2).padLeft(7)} ms per ${_rows ~/ 1000}k-entity pass');
}

void main() {
  final bytes = _rows * _stride;
  final base = calloc<Uint8>(bytes);
  try {
    final doubles = base.cast<Double>().asTypedList(bytes ~/ 8);
    // Real values: a byte pattern reinterpreted as doubles is mostly NaN, and
    // NaN arithmetic is not what this measures.
    for (var i = 0; i < doubles.length; i++) {
      doubles[i] = i * 0.5;
    }

    final mono = <Float64Column>[
      for (var i = 0; i < _columns; i++) Float64Column(base, i * 8),
    ];
    // Round-robin across the four impls so no single one dominates the site.
    final mega = <DoubleColumn>[
      for (var i = 0; i < _columns; i++)
        switch (i % 4) {
          0 => _DoubleA(base, i * 8),
          1 => _DoubleB(base, i * 8),
          2 => _DoubleC(base, i * 8),
          _ => _DoubleD(base, i * 8),
        },
    ];
    final generic = <GenericColumn<double>>[
      for (var i = 0; i < _columns; i++)
        switch (i % 3) {
          0 => _GenericA(base, i * 8),
          1 => _GenericB(base, i * 8),
          _ => _GenericC(base, i * 8),
        },
    ];
    // Instantiated and called so the nullable implementation is real to the
    // compiler, not dead code it can prune before deciding the call site's
    // shape.
    final nullable = _GenericNullable(base, 0);
    _blackHole += nullable[const Entity(0)] ?? 0;

    final addresses = <AddressColumn>[
      for (var i = 0; i < _columns; i++) AddressColumn(base.address, i * 8),
    ];
    final views = <ViewColumn>[
      for (var i = 0; i < _columns; i++) ViewColumn(doubles, i),
    ];
    final viewsMega = <ViewBackedColumn>[
      for (var i = 0; i < _columns; i++)
        switch (i % 4) {
          0 => _ViewA(doubles, i),
          1 => _ViewB(doubles, i),
          2 => _ViewC(doubles, i),
          _ => _ViewD(doubles, i),
        },
    ];

    print('$_rows rows x $_columns columns, $_reps passes\n');
    _time('raw', () => _raw(base));
    _time('mono', () => _mono(mono));
    _time('megamorphic', () => _mega(mega));
    _time('generic', () => _generic(generic));
    _time('int address', () => _address(addresses));
    _time('view', () => _view(views));
    _time('view mega', () => _viewMega(viewsMega));

    final genericAddresses = <GenericAddressColumn<double>>[
      for (var i = 0; i < _columns; i++)
        switch (i % 3) {
          0 => _AddrA(base.address, i * 8),
          1 => _AddrB(base.address, i * 8),
          _ => _AddrC(base.address, i * 8),
        },
    ];
    final addrNullable = _AddrNullable(base.address, 0);
    _blackHole += addrNullable[const Entity(0)] ?? 0;
    _time('generic+addr', () => _genericAddress(genericAddresses));
    print('\nblackhole $_blackHole');
  } finally {
    calloc.free(base);
  }
}
