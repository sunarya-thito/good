import 'dart:ffi';

import 'package:goo/src/archetype.dart';
import 'package:goo/src/data.dart';
import 'package:goo/src/heap_object.dart';
import 'package:goo/src/struct.dart';

/// Concrete `DataDescriptor`/`DataPointer` layer over [ArchetypeStorage].
///
/// One [ArchetypeDataDescriptor] exists per archetype, alive only for the
/// duration of that archetype's single `describeStruct` pass; the
/// `DataPointer`s it hands back outlive it and are what the struct's
/// `late final` fields hold forever after. So there is exactly one pointer
/// object per *field*, not per field per entity - the entity is an argument
/// to `operator []`, never baked into the pointer. That is what keeps
/// `transform.transformOffsetX[instance] += 1` allocation-free across a
/// million entities.
///
/// No *field* caches a row address. A row resolved last tick points at a slot
/// the writer is about to reuse, because the page's backing slot rotates every
/// tick (`MemoryPool.beginTick`/`commitTick`), so every access re-resolves
/// through [ArchetypeStorage.rowRead] - which does keep a (epoch, pageIndex)
/// cache of its own, invalidated precisely when the bases move. Reads go
/// through the latest *published* snapshot, which is what makes a read from the
/// render/UI isolate coherent, and what makes `+= 1` mean "last tick's value
/// plus one" rather than reading a half-written tick.
///
/// Row addresses are plain `int`s throughout this file rather than
/// `Pointer<Uint8>` - see [_readRow] for the measurement that forced it.

/// Resolves a row for reading - the **last published** snapshot, never the
/// tick currently being written.
///
/// That is a deliberate, and sharp, semantic. Within one tick every read
/// sees the state as of `commitTick` of the *previous* tick, so:
///
///  * `x[e] += 1` means "last tick's value plus one" and is therefore
///    order-independent between systems - two systems each doing `+= 1` in
///    the same tick produce +1, not +2.
///  * a value written earlier in the same tick is **not** visible to a
///    later read in that tick. In particular, values assigned in
///    `onEntityMounted` are invisible to systems running in the spawn
///    tick, and a read-modify-write in such a system will overwrite them.
///    Initialize by writing, never by reading-then-writing, on the tick an
///    entity is created.
///
/// The pay-off is that a reader in another isolate (the render pass, a HUD
/// query) sees a coherent, complete snapshot with no locking - see
/// `TripleBuffer`. Freshly allocated rows are stamped into the published
/// slot as well as the write slot (see `ArchetypeStorage.allocateRow`), so
/// declared defaults are readable immediately rather than a tick late.
///
/// Before the first `commitTick` there is no published snapshot at all;
/// reads fall back to the write slot, which at that point holds the only
/// state that exists. No reader isolate can be running yet - the scene is
/// not live - and once anything has been published this branch is never
/// taken again.
@pragma('vm:prefer-inline')
int _readRow(ArchetypeStorage storage, Entity entity) {
  // Returns an **address**, not a `Pointer`, and that is the whole point.
  //
  // Two rounds of the same lesson landed here. First: one non-nullable call
  // rather than `resolveRead(o) ?? resolveWrite(o)`, because a `Pointer<T>?`
  // cannot be unboxed and the nullable spelling allocated a box on every field
  // read - 14.4ns against 1.65ns (`tool/field_access_bench.dart`). Second, and
  // larger: a **non**-nullable `Pointer` is still a heap object, so returning
  // one from here allocated on every read too, and so did each `+ _byte` and
  // `.cast<T>()` the accessor did to it. Handing back an `int` and letting each
  // accessor do `Pointer<T>.fromAddress(row + offset)` compiles to a plain load
  // - the compiler never materialises the pointer at all.
  //
  // `tool/column_dispatch_bench.dart` isolates it against every neighbouring
  // suspect: 14.63ns/access through a `Pointer` field, 2.25ns through an `int`
  // one, with the generic megamorphic `DataPointer` dispatch identical in both.
  // Generics cost ~0 and megamorphic dispatch ~1.3ns; the boxing was ~12.
  // End to end that is `WorldTransformSystem` at 249ns/entity/tick before and
  // 91ns after (`goo2d/tool/world_transform_bench.dart`, 10k entities).
  return storage.rowRead(entity);
}

// `_requirePage` used to live here, walking `pageAt` -> `resolveRow` ->
// `readView` on **every field access**. A DevTools profile of 10k entities put
// that chain at ~54% of all samples, so it moved into `ArchetypeStorage` as a
// cache keyed by (epoch, pageIndex) - see `ArchetypeStorage.rowRead`. Two int
// compares now stand where six calls did, and nothing above this line changed:
// `field[entity]` is still `field[entity]`.

/// Resolves this tick's write slot for [entity]'s row.
///
/// The assertion is the only thing standing between a caller and silent
/// data loss: `MemoryPool.beginTick` copies each page's published bytes
/// over the write slot, so a write that lands outside a tick window is
/// erased by the next `beginTick` with no error anywhere. Writing before
/// the *first* publish is fine and common (scene bootstrap), hence the
/// second clause. Debug-only - it compiles out of a release build, so
/// the hot path stays a page lookup and a pointer add.
///
/// Top-level, mirroring [_readRow], so the array field types can share the
/// one guarded write path instead of restating the assertion - they are not
/// `_Field` subclasses (a `DataArrayPointer` is not a `DataPointer`), so
/// there is no inherited `_write` for them to call.
@pragma('vm:prefer-inline')
int _writeRow(ArchetypeStorage storage, Entity entity) {
  final row = storage.rowWrite(entity);
  assert(
    storage.pool.isTickOpen || !storage.cachedPage.hasPublished,
    'Component data was written outside a tick. MemoryPool.beginTick() '
    'copies the last published snapshot over the write slot, so this '
    'write would be silently discarded when the next tick starts. All '
    'mutation belongs between beginTick() and commitTick().',
  );
  return row;
}

abstract base class _Field<T> extends DataPointer<T> implements ArchetypeField {
  _Field(this._storage);

  final ArchetypeStorage _storage;

  /// This field's value in an already-resolved row.
  ///
  /// Only implemented by the field kinds a structural mutation reads back
  /// inside its own tick; see `DataPointer.readPending`, which is the only
  /// caller and which explains why the rest deliberately throw rather than
  /// answer with the published value.
  T readFrom(int row) => throw UnsupportedError(
    '$runtimeType does not implement readFrom - see DataPointer.readPending.',
  );

  @pragma('vm:prefer-inline')
  int _write(Entity entity) => _writeRow(_storage, entity);

  @pragma('vm:prefer-inline')
  int _read(Entity entity) => _readRow(_storage, entity);
}

// --- sub-byte fields ---------------------------------------------------
//
// 1/2/4-bit fields never span a byte (see ArchetypeStorage.declareField),
// so both directions are a single-byte access: read is load/shift/mask,
// write is a load/mask/or/store read-modify-write. `_byteMask` is the
// field's bits in place; `_valueMask` is them at bit 0.

base class _SubByteUintField extends _Field<int> {
  _SubByteUintField(super.storage, int bitOffset, int bitWidth, this._default)
    : _byte = bitOffset >> 3,
      _shift = bitOffset & 7,
      _valueMask = (1 << bitWidth) - 1,
      _byteMask = ((1 << bitWidth) - 1) << (bitOffset & 7),
      _signBit = 1 << (bitWidth - 1),
      _range = 1 << bitWidth;

  final int _byte;
  final int _shift;
  final int _valueMask;
  final int _byteMask;
  final int _default;

  // Only [_SubByteIntField] reads these; they live here so the signed
  // variant can be a plain super-parameter subclass instead of restating
  // the whole constructor to get at `bitWidth`.
  final int _signBit;
  final int _range;

  @override
  int operator [](Entity entity) =>
      (Pointer<Uint8>.fromAddress(_read(entity) + _byte).value >> _shift) &
      _valueMask;

  @override
  void operator []=(Entity entity, int newValue) =>
      _store(_write(entity), newValue);

  void _store(int row, int newValue) {
    Pointer<Uint8>.fromAddress(row + _byte).value =
        (Pointer<Uint8>.fromAddress(row + _byte).value & ~_byteMask & 0xFF) |
        ((newValue & _valueMask) << _shift);
  }

  @override
  void writeDefault(int row) => _store(row, _default);
}

/// Two's-complement variant. Note `hasInt1` therefore holds -1 or 0, which
/// is what a 1-bit two's-complement integer means - it is not a bool with
/// values 0/1 (`hasUint1` is that).
final class _SubByteIntField extends _SubByteUintField {
  _SubByteIntField(
    super.storage,
    super.bitOffset,
    super.bitWidth,
    super.defaultValue,
  );

  @override
  int operator [](Entity entity) {
    final raw = super[entity];
    return raw >= _signBit ? raw - _range : raw;
  }
}

// --- byte-aligned fields -----------------------------------------------
//
// One aligned-to-a-byte (not necessarily naturally aligned - see
// declareField) load or store through a cast pointer. `row + _byte`
// advances a Pointer<Uint8> by bytes, so the cast lands where it should.

final class _Uint8Field extends _Field<int> {
  _Uint8Field(super.storage, this._byte, this._default);
  final int _byte;
  final int _default;

  @override
  int operator [](Entity entity) =>
      Pointer<Uint8>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Uint8>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeDefault(int row) =>
      Pointer<Uint8>.fromAddress(row + _byte).value = _default;
}

final class _Int8Field extends _Field<int> {
  _Int8Field(super.storage, this._byte, this._default);
  final int _byte;
  final int _default;

  @override
  int operator [](Entity entity) =>
      Pointer<Int8>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Int8>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeDefault(int row) =>
      Pointer<Int8>.fromAddress(row + _byte).value = _default;
}

final class _Uint16Field extends _Field<int> {
  _Uint16Field(super.storage, this._byte, this._default);
  final int _byte;
  final int _default;

  @override
  int operator [](Entity entity) =>
      Pointer<Uint16>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Uint16>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeDefault(int row) =>
      Pointer<Uint16>.fromAddress(row + _byte).value = _default;
}

final class _Int16Field extends _Field<int> {
  _Int16Field(super.storage, this._byte, this._default);
  final int _byte;
  final int _default;

  @override
  int operator [](Entity entity) =>
      Pointer<Int16>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Int16>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeDefault(int row) =>
      Pointer<Int16>.fromAddress(row + _byte).value = _default;
}

final class _Uint32Field extends _Field<int> {
  _Uint32Field(super.storage, this._byte, this._default);
  final int _byte;
  final int _default;

  @override
  int operator [](Entity entity) =>
      Pointer<Uint32>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Uint32>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeDefault(int row) =>
      Pointer<Uint32>.fromAddress(row + _byte).value = _default;
}

final class _Int32Field extends _Field<int> {
  _Int32Field(super.storage, this._byte, this._default);
  final int _byte;
  final int _default;

  @override
  int operator [](Entity entity) =>
      Pointer<Int32>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Int32>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeDefault(int row) =>
      Pointer<Int32>.fromAddress(row + _byte).value = _default;
}

// Uint64/Int64 exist mainly so a field can hold a full packed `Entity`
// handle - see the doc on DataDescriptor.hasUint64/hasInt64 in data.dart.
// dart:ffi's Uint64 getter/setter round-trip the same 64-bit pattern
// Dart's own (signed, twos-complement) `int` already uses, so this is a
// plain aligned load/store exactly like the narrower widths, no different
// handling needed for values that "look negative".
final class _Uint64Field extends _Field<int> {
  _Uint64Field(super.storage, this._byte, this._default);
  final int _byte;
  final int _default;

  @override
  int operator [](Entity entity) =>
      Pointer<Uint64>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Uint64>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeDefault(int row) =>
      Pointer<Uint64>.fromAddress(row + _byte).value = _default;
}

final class _Int64Field extends _Field<int> {
  _Int64Field(super.storage, this._byte, this._default);
  final int _byte;
  final int _default;

  @override
  int operator [](Entity entity) =>
      Pointer<Int64>.fromAddress(_read(entity) + _byte).value;

  /// The value in an already-resolved row. Split out so [_OptionalField] can
  /// read the *pending* row it resolved for the flag without resolving it a
  /// second time - see `DataPointer.readPending`.
  @override
  int readFrom(int row) => Pointer<Int64>.fromAddress(row + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Int64>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeDefault(int row) =>
      Pointer<Int64>.fromAddress(row + _byte).value = _default;
}

// dart:ffi names the IEEE-754 types Float/Double, not Float32/Float64.
final class _Float32Field extends _Field<double> {
  _Float32Field(super.storage, this._byte, this._default);
  final int _byte;
  final double _default;

  @override
  double operator [](Entity entity) =>
      Pointer<Float>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, double newValue) =>
      Pointer<Float>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeDefault(int row) =>
      Pointer<Float>.fromAddress(row + _byte).value = _default;
}

final class _Float64Field extends _Field<double> {
  _Float64Field(super.storage, this._byte, this._default);
  final int _byte;
  final double _default;

  @override
  @pragma('vm:prefer-inline')
  double operator [](Entity entity) =>
      Pointer<Double>.fromAddress(_read(entity) + _byte).value;

  @override
  @pragma('vm:prefer-inline')
  void operator []=(Entity entity, double newValue) =>
      Pointer<Double>.fromAddress(_write(entity) + _byte).value = newValue;

  /// This tick's write slot, for the narrow case of composing state that was
  /// written earlier in the *same* tick - see [DataPointer.readPending].
  ///
  /// Implemented here because a freshly spawned entity's transform is exactly
  /// that: the spawner writes it during the tick, and anything deriving from
  /// it in the same tick would otherwise read the last published snapshot,
  /// which on a recycled row is the previous occupant's value. That produced
  /// one frame of a sprite at the world origin.
  @override
  double readPending(Entity entity) =>
      Pointer<Double>.fromAddress(_write(entity) + _byte).value;

  @override
  void writeDefault(int row) =>
      Pointer<Double>.fromAddress(row + _byte).value = _default;
}

// --- packed value fields -------------------------------------------------
//
// hasPacked<T extends IntRepresentable> stores a plain integer in the row, so
// a component row never holds a Dart heap reference (RULES.md rule 1). Writes
// call `pack()`; reads `unpack()` it back through the `IntRepresentation` the
// field was declared against.
//
// The representation is held *per field*, not looked up from a shared
// registry. That is what lets two unrelated populations (assets, sprite
// frames) number their values from zero without colliding: an int is only
// ever unpacked by the representation the field named. It also costs nothing
// extra at read time - one field deref, where this used to reach
// `_storage.assets`.
//
// The bits themselves are delegated to an ordinary integer field rather than
// hardcoding `Pointer<Uint32>`, which is what lets a representation pick its
// own width: every rung of the 1..64 ladder, sub-byte included, comes for
// free because `_declareInt` already built them.

final class _PackedField<T extends IntRepresentable> extends _Field<T>
    implements PackedPointer<T> {
  _PackedField(super.storage, this._bits, this._repr);

  /// The integer field holding the packed bits. Declared and owned here, and
  /// deliberately **not** registered with the storage itself - this field's
  /// own [writeDefault] drives it, so registering both would stamp the
  /// default twice.
  final _Field<int> _bits;
  final IntRepresentation<T> _repr;

  @override
  T operator [](Entity entity) => _repr.unpack(_bits[entity]);

  @override
  void operator []=(Entity entity, T newValue) =>
      _bits[entity] = newValue.pack();

  @override
  int packedAt(Entity entity) => _bits[entity];

  @override
  void writeDefault(int row) => _bits.writeDefault(row);
}

/// `hasHeapObject`/`optHeapObject`: the same Uint32-address-in-the-row shape
/// as [_GlobalObjectField], resolving through [HeapObjectRegistry] instead.
/// See `DataDescriptor.hasHeapObject`'s doc for when to reach for which.
///
/// **Every write registers a new slot.** There is no attempt to notice that
/// the same object was written twice and reuse its address - that would need
/// an identity map consulted on the hot path, which is exactly what this
/// engine's row storage exists to avoid. So `field[e] = x` twice leaves the
/// first slot occupied until something unregisters it, and nothing does yet:
/// entity destruction is the natural place to free these and this engine has
/// no despawn API (see the TODO on [HeapObjectRegistry]). Accepted, and
/// documented rather than half-solved: heap-object fields are for references
/// assigned a bounded number of times, not for per-tick churn.
///
/// **The default is a factory, and it is called exactly once.**
/// [writeDefault] runs once, at `ArchetypeStorage.seal`, to build the
/// prototype row; `allocateRow` then *memcpy*s that row into every spawned
/// entity. A memcpy copies the 4-byte address, not the object - so every
/// entity that does not overwrite the field shares one default instance.
/// That is the intended behaviour: it is exactly what
/// `hasObject<T extends GlobalObject>(T defaultValue)` already does, and the
/// alternative (a fresh instance per entity) is not expressible here at all,
/// because there is no per-spawn hook to run a factory in - only the memcpy.
/// The factory exists so the default can be *built* at seal time rather than
/// forced into existence at `describeStruct` time; it does not, and cannot,
/// make the default per-entity.
final class _HeapObjectField<T> extends _Field<T> {
  _HeapObjectField(super.storage, this._byte, this._defaultFactory);
  final int _byte;

  /// `null` for the `optHeapObject` case, whose wrapper never asks for a
  /// default (its has-bit defaults to clear, i.e. `null`).
  final T Function()? _defaultFactory;

  @override
  T operator [](Entity entity) => HeapObjectRegistry.resolve<T>(
    Pointer<Uint32>.fromAddress(_read(entity) + _byte).value,
  );

  @override
  void operator []=(Entity entity, T newValue) =>
      Pointer<Uint32>.fromAddress(_write(entity) + _byte)
          .value = HeapObjectRegistry.register(
        newValue,
      );

  @override
  void writeDefault(int row) {
    final factory = _defaultFactory;
    Pointer<Uint32>.fromAddress(row + _byte).value = factory == null
        ? 0
        : HeapObjectRegistry.register(factory());
  }
}

// --- nullable fields ---------------------------------------------------

/// Wraps a non-nullable field with a one-bit "has value" flag declared
/// immediately before it through the same bit cursor - so nullability
/// costs a bit, not a byte, and several `opt*` flags in a row share one
/// byte the way the sub-byte packing rule intends.
///
/// The value bits are don't-care while the flag is clear: writing `null`
/// only clears the flag and leaves whatever was there, because nothing
/// reads the value without first seeing the flag set. That keeps the
/// `null` write to a single byte read-modify-write instead of also zeroing
/// up to 8 bytes.
final class _OptionalField<T> extends _Field<T?> {
  _OptionalField(
    super.storage,
    int flagBitOffset,
    this._value,
    this._defaultPresent,
  ) : _flagByte = flagBitOffset >> 3,
      _flagMask = 1 << (flagBitOffset & 7);

  final int _flagByte;
  final int _flagMask;
  final _Field<T> _value;
  final bool _defaultPresent;

  @override
  T? operator [](Entity entity) {
    if (Pointer<Uint8>.fromAddress(_read(entity) + _flagByte).value &
            _flagMask ==
        0) {
      return null;
    }
    return _value[entity];
  }

  /// Both halves - the presence flag and the value - read from the same
  /// pending row, because a structural edit made earlier this tick set both,
  /// and taking one from each slot would report a field that is present
  /// according to one snapshot and absent according to the other.
  @override
  T? readPending(Entity entity) {
    // Outside a tick there is no meaningful write slot: the one the buffer
    // would hand back holds whatever sat there before `beginWrite` copied. The
    // published read is the only correct answer there, and is what every
    // caller wants anyway.
    if (!_storage.pool.isTickOpen) return this[entity];
    final row = _storage.rowWrite(entity);
    if (Pointer<Uint8>.fromAddress(row + _flagByte).value & _flagMask == 0) {
      return null;
    }
    return _value.readFrom(row);
  }

  @override
  void operator []=(Entity entity, T? newValue) {
    final row = _write(entity);
    if (newValue == null) {
      Pointer<Uint8>.fromAddress(row + _flagByte).value =
          Pointer<Uint8>.fromAddress(row + _flagByte).value & ~_flagMask & 0xFF;
      return;
    }
    Pointer<Uint8>.fromAddress(row + _flagByte).value =
        Pointer<Uint8>.fromAddress(row + _flagByte).value | _flagMask;
    _value[entity] = newValue;
  }

  @override
  void writeDefault(int row) {
    if (_defaultPresent) {
      Pointer<Uint8>.fromAddress(row + _flagByte).value =
          Pointer<Uint8>.fromAddress(row + _flagByte).value | _flagMask;
      _value.writeDefault(row);
    } else {
      Pointer<Uint8>.fromAddress(row + _flagByte).value =
          Pointer<Uint8>.fromAddress(row + _flagByte).value & ~_flagMask & 0xFF;
    }
  }
}

// --- array fields ------------------------------------------------------
//
// An array field is `length` consecutive scalar fields declared back to
// back, addressed by arithmetic instead of by storing `length` offsets.
// `ArchetypeDataDescriptor._declareElements` reserves them by calling
// `ArchetypeStorage.declareField(bitWidth)` `length` times in a row and
// keeping only the first offset; element `i` then sits at exactly
// `baseBit + i * bitWidth`, with no gaps, in every supported case:
//
//  * Sub-byte widths (1/2/4) all divide 8, so once the array's base is a
//    multiple of the element width, declareField's "jump to the next byte if
//    this one can't fit the field" rule never fires mid-array - a byte
//    boundary always coincides with an element boundary. `_declareElements`
//    pads the cursor up to that multiple first; read its doc for why
//    skipping that step silently corrupts sub-byte arrays that happen to be
//    declared after an odd number of flag bits.
//  * Byte-and-wider widths (8/16/32/64) get rounded to a byte boundary on
//    *every* declareField call, and the width is already a whole number of
//    bytes, so consecutive elements land at `baseByte + i * (bitWidth / 8)`.
//
// `test/data_layout_test.dart`'s 'sub-byte array packing is tight' case
// pins that down against the real cursor rather than on paper.
//
// Note what these classes are *not*: subclasses of `_Field`. A
// `DataArrayPointer<T>` is not a `DataPointer<T>` (its accessors take an
// index), so they share the row-resolution helpers `_readRow`/`_writeRow`
// rather than an inheritance chain.

abstract base class _ArrayField<T>
    implements DataArrayPointer<T>, ArchetypeField {
  _ArrayField(this._storage, this.length);

  final ArchetypeStorage _storage;

  @override
  final int length;

  int _read(Entity entity) => _readRow(_storage, entity);
  int _write(Entity entity) => _writeRow(_storage, entity);

  /// Bounds check. Without it an out-of-range index is not an error but
  /// silent corruption: the arithmetic would happily address a neighbouring
  /// field's bits, or - past the end of the row - the next entity's row
  /// entirely, since rows are packed back to back in a page.
  ///
  /// Allocation-free on the passing path; the `RangeError` is only built
  /// when the call is already failing.
  void _checkIndex(int index) {
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this, 'index', null, length);
    }
  }
}

/// Sub-byte (1/2/4-bit) unsigned element array. Element `i` never straddles
/// a byte - see the packing note above - so each access stays a single-byte
/// load/shift/mask, exactly like [_SubByteUintField].
base class _SubByteUintArrayField extends _ArrayField<int> {
  _SubByteUintArrayField(
    super.storage,
    super.length,
    this._baseBit,
    this._bitWidth,
    this._default,
  ) : _valueMask = (1 << _bitWidth) - 1,
      _signBit = 1 << (_bitWidth - 1),
      _range = 1 << _bitWidth;

  final int _baseBit;
  final int _bitWidth;
  final int _valueMask;
  final int _default;

  // Only [_SubByteIntArrayField] reads these; same arrangement as the
  // scalar pair, so the signed variant stays a super-parameter subclass.
  final int _signBit;
  final int _range;

  @override
  int get(Entity entity, int index) {
    _checkIndex(index);
    final bit = _baseBit + index * _bitWidth;
    return (Pointer<Uint8>.fromAddress(_read(entity) + (bit >> 3)).value >>
            (bit & 7)) &
        _valueMask;
  }

  @override
  void set(Entity entity, int index, int newValue) {
    _checkIndex(index);
    _store(_write(entity), index, newValue);
  }

  void _store(int row, int index, int newValue) {
    final bit = _baseBit + index * _bitWidth;
    final byte = bit >> 3;
    final shift = bit & 7;
    final byteMask = _valueMask << shift;
    Pointer<Uint8>.fromAddress(row + byte).value =
        (Pointer<Uint8>.fromAddress(row + byte).value & ~byteMask & 0xFF) |
        ((newValue & _valueMask) << shift);
  }

  @override
  void writeDefault(int row) {
    for (var i = 0; i < length; i++) {
      _store(row, i, _default);
    }
  }
}

/// Two's-complement variant of [_SubByteUintArrayField] - see
/// [_SubByteIntField] on what a 1-bit signed element means (-1 or 0).
final class _SubByteIntArrayField extends _SubByteUintArrayField {
  _SubByteIntArrayField(
    super.storage,
    super.length,
    super.baseBit,
    super.bitWidth,
    super.defaultValue,
  );

  @override
  int get(Entity entity, int index) {
    final raw = super.get(entity, index);
    return raw >= _signBit ? raw - _range : raw;
  }
}

// Byte-aligned element arrays. `(row + _baseByte).cast<X>()[index]` is one
// load or store: the cast lands on the array's first byte and dart:ffi's
// `[]` scales the index by the element size, which is precisely the
// `baseByte + i * elementBytes` layout declareField produced.

final class _Uint8ArrayField extends _ArrayField<int> {
  _Uint8ArrayField(super.storage, super.length, this._baseByte, this._default);
  final int _baseByte;
  final int _default;

  @override
  int get(Entity entity, int index) {
    _checkIndex(index);
    return Pointer<Uint8>.fromAddress(_read(entity) + _baseByte + index).value;
  }

  @override
  void set(Entity entity, int index, int newValue) {
    _checkIndex(index);
    Pointer<Uint8>.fromAddress(_write(entity) + _baseByte + index).value =
        newValue;
  }

  @override
  void writeDefault(int row) {
    for (var i = 0; i < length; i++) {
      Pointer<Uint8>.fromAddress(row + _baseByte + i).value = _default;
    }
  }
}

final class _Int8ArrayField extends _ArrayField<int> {
  _Int8ArrayField(super.storage, super.length, this._baseByte, this._default);
  final int _baseByte;
  final int _default;

  @override
  int get(Entity entity, int index) {
    _checkIndex(index);
    return Pointer<Int8>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, int newValue) {
    _checkIndex(index);
    Pointer<Int8>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeDefault(int row) {
    final elements = Pointer<Int8>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _default;
    }
  }
}

final class _Uint16ArrayField extends _ArrayField<int> {
  _Uint16ArrayField(super.storage, super.length, this._baseByte, this._default);
  final int _baseByte;
  final int _default;

  @override
  int get(Entity entity, int index) {
    _checkIndex(index);
    return Pointer<Uint16>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, int newValue) {
    _checkIndex(index);
    Pointer<Uint16>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeDefault(int row) {
    final elements = Pointer<Uint16>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _default;
    }
  }
}

final class _Int16ArrayField extends _ArrayField<int> {
  _Int16ArrayField(super.storage, super.length, this._baseByte, this._default);
  final int _baseByte;
  final int _default;

  @override
  int get(Entity entity, int index) {
    _checkIndex(index);
    return Pointer<Int16>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, int newValue) {
    _checkIndex(index);
    Pointer<Int16>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeDefault(int row) {
    final elements = Pointer<Int16>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _default;
    }
  }
}

final class _Uint32ArrayField extends _ArrayField<int> {
  _Uint32ArrayField(super.storage, super.length, this._baseByte, this._default);
  final int _baseByte;
  final int _default;

  @override
  int get(Entity entity, int index) {
    _checkIndex(index);
    return Pointer<Uint32>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, int newValue) {
    _checkIndex(index);
    Pointer<Uint32>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeDefault(int row) {
    final elements = Pointer<Uint32>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _default;
    }
  }
}

final class _Int32ArrayField extends _ArrayField<int> {
  _Int32ArrayField(super.storage, super.length, this._baseByte, this._default);
  final int _baseByte;
  final int _default;

  @override
  int get(Entity entity, int index) {
    _checkIndex(index);
    return Pointer<Int32>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, int newValue) {
    _checkIndex(index);
    Pointer<Int32>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeDefault(int row) {
    final elements = Pointer<Int32>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _default;
    }
  }
}

final class _Float32ArrayField extends _ArrayField<double> {
  _Float32ArrayField(
    super.storage,
    super.length,
    this._baseByte,
    this._default,
  );
  final int _baseByte;
  final double _default;

  @override
  double get(Entity entity, int index) {
    _checkIndex(index);
    return Pointer<Float>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, double newValue) {
    _checkIndex(index);
    Pointer<Float>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeDefault(int row) {
    final elements = Pointer<Float>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _default;
    }
  }
}

final class _Float64ArrayField extends _ArrayField<double> {
  _Float64ArrayField(
    super.storage,
    super.length,
    this._baseByte,
    this._default,
  );
  final int _baseByte;
  final double _default;

  @override
  double get(Entity entity, int index) {
    _checkIndex(index);
    return Pointer<Double>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, double newValue) {
    _checkIndex(index);
    Pointer<Double>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeDefault(int row) {
    final elements = Pointer<Double>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _default;
    }
  }
}

/// `hasPackedArray` - the per-element repeat of [_PackedField], holding one
/// integer element field and packing/unpacking around it.
///
/// Delegating to an integer *array* field rather than to `Pointer<Uint32>`
/// arithmetic is what carries the variable width through: element stride,
/// sub-byte packing and bounds checking are all already solved there, and a
/// representation narrower than 32 bits pays for itself `length` times over
/// here.
final class _PackedArrayField<T extends IntRepresentable>
    extends _ArrayField<T> {
  _PackedArrayField(super.storage, super.length, this._bits, this._repr);

  final _ArrayField<int> _bits;
  final IntRepresentation<T> _repr;

  @override
  T get(Entity entity, int index) {
    _checkIndex(index);
    return _repr.unpack(_bits.get(entity, index));
  }

  @override
  void set(Entity entity, int index, T newValue) {
    _checkIndex(index);
    _bits.set(entity, index, newValue.pack());
  }

  @override
  void writeDefault(int row) => _bits.writeDefault(row);
}

/// Nullable element array: [_OptionalField]'s one-bit has-flag repeated per
/// element, each flag declared immediately before its own element's value.
///
/// Held as a list of per-element scalar fields rather than as base-offset
/// arithmetic, because the interleaved `flag, value, flag, value, ...`
/// declaration order does *not* produce a uniform stride once a flag pushes
/// a sub-byte value across a byte boundary (e.g. 1+4 bits per element: the
/// first element occupies bits 0..4, every later one costs a whole 8). The
/// lists are built once at declare time and only indexed afterwards, so
/// nothing here allocates per access - the density loss versus the
/// non-nullable case is deliberate, matching what the scalar `_opt` already
/// does, one element at a time.
///
/// Value bits are don't-care while the flag is clear, exactly as for the
/// scalar case: writing `null` clears one bit and leaves the payload alone.
final class _OptionalArrayField<T> extends _ArrayField<T?> {
  _OptionalArrayField(
    super.storage,
    super.length,
    this._flagBits,
    this._values,
    this._defaultPresent,
  );

  /// Bit offset of element `i`'s has-flag.
  final List<int> _flagBits;

  /// Element `i`'s value accessor. Registered with the storage only through
  /// this wrapper - never on their own - so the flag decides whether an
  /// element's value default gets stamped at all.
  final List<_Field<T>> _values;

  final bool _defaultPresent;

  @override
  T? get(Entity entity, int index) {
    _checkIndex(index);
    final flagBit = _flagBits[index];
    if (Pointer<Uint8>.fromAddress(_read(entity) + (flagBit >> 3)).value &
            (1 << (flagBit & 7)) ==
        0) {
      return null;
    }
    return _values[index][entity];
  }

  @override
  void set(Entity entity, int index, T? newValue) {
    _checkIndex(index);
    final flagBit = _flagBits[index];
    final byte = flagBit >> 3;
    final mask = 1 << (flagBit & 7);
    final row = _write(entity);
    if (newValue == null) {
      Pointer<Uint8>.fromAddress(row + byte).value =
          Pointer<Uint8>.fromAddress(row + byte).value & ~mask & 0xFF;
      return;
    }
    Pointer<Uint8>.fromAddress(row + byte).value =
        Pointer<Uint8>.fromAddress(row + byte).value | mask;
    _values[index][entity] = newValue;
  }

  @override
  void writeDefault(int row) {
    for (var i = 0; i < length; i++) {
      final flagBit = _flagBits[i];
      final byte = flagBit >> 3;
      final mask = 1 << (flagBit & 7);
      if (_defaultPresent) {
        Pointer<Uint8>.fromAddress(row + byte).value =
            Pointer<Uint8>.fromAddress(row + byte).value | mask;
        _values[i].writeDefault(row);
      } else {
        Pointer<Uint8>.fromAddress(row + byte).value =
            Pointer<Uint8>.fromAddress(row + byte).value & ~mask & 0xFF;
      }
    }
  }
}

/// Builds one archetype's field layout. Created and discarded by
/// `SceneDescriptor.has`; see the library doc at the top of this file.
final class ArchetypeDataDescriptor implements DataDescriptor {
  ArchetypeDataDescriptor(this._storage);

  final ArchetypeStorage _storage;

  _Field<int> _declareInt(int bitWidth, bool signed, int defaultValue) {
    final bitOffset = _storage.declareField(bitWidth);
    if (bitWidth < 8) {
      return signed
          ? _SubByteIntField(_storage, bitOffset, bitWidth, defaultValue)
          : _SubByteUintField(_storage, bitOffset, bitWidth, defaultValue);
    }
    final byte = bitOffset >> 3;
    return switch ((bitWidth, signed)) {
      (8, false) => _Uint8Field(_storage, byte, defaultValue),
      (8, true) => _Int8Field(_storage, byte, defaultValue),
      (16, false) => _Uint16Field(_storage, byte, defaultValue),
      (16, true) => _Int16Field(_storage, byte, defaultValue),
      (32, false) => _Uint32Field(_storage, byte, defaultValue),
      (32, true) => _Int32Field(_storage, byte, defaultValue),
      (64, false) => _Uint64Field(_storage, byte, defaultValue),
      (64, true) => _Int64Field(_storage, byte, defaultValue),
      _ => throw ArgumentError('unsupported integer bit width $bitWidth'),
    };
  }

  _Field<double> _declareFloat(int bitWidth, double defaultValue) {
    final byte = _storage.declareField(bitWidth) >> 3;
    return bitWidth == 32
        ? _Float32Field(_storage, byte, defaultValue)
        : _Float64Field(_storage, byte, defaultValue);
  }

  DataPointer<int> _has(int bitWidth, bool signed, int defaultValue) {
    final field = _declareInt(bitWidth, signed, defaultValue);
    _storage.registerField(field);
    return field;
  }

  DataPointer<double> _hasFloat(int bitWidth, double defaultValue) {
    final field = _declareFloat(bitWidth, defaultValue);
    _storage.registerField(field);
    return field;
  }

  DataPointer<int?> _opt(int bitWidth, bool signed, int? defaultValue) {
    // Flag first, then the value - the value's own alignment rule then
    // applies to whatever byte the flag left the cursor in.
    final flagBit = _storage.declareField(1);
    final value = _declareInt(bitWidth, signed, defaultValue ?? 0);
    final field = _OptionalField<int>(
      _storage,
      flagBit,
      value,
      defaultValue != null,
    );
    _storage.registerField(field);
    return field;
  }

  DataPointer<double?> _optFloat(int bitWidth, double? defaultValue) {
    final flagBit = _storage.declareField(1);
    final value = _declareFloat(bitWidth, defaultValue ?? 0.0);
    final field = _OptionalField<double>(
      _storage,
      flagBit,
      value,
      defaultValue != null,
    );
    _storage.registerField(field);
    return field;
  }

  @override
  DataPointer<int> hasUint1([int defaultValue = 0]) =>
      _has(1, false, defaultValue);
  @override
  DataPointer<int> hasInt1([int defaultValue = 0]) =>
      _has(1, true, defaultValue);
  @override
  DataPointer<int> hasUint2([int defaultValue = 0]) =>
      _has(2, false, defaultValue);
  @override
  DataPointer<int> hasInt2([int defaultValue = 0]) =>
      _has(2, true, defaultValue);
  @override
  DataPointer<int> hasUint4([int defaultValue = 0]) =>
      _has(4, false, defaultValue);
  @override
  DataPointer<int> hasInt4([int defaultValue = 0]) =>
      _has(4, true, defaultValue);
  @override
  DataPointer<int> hasUint8([int defaultValue = 0]) =>
      _has(8, false, defaultValue);
  @override
  DataPointer<int> hasInt8([int defaultValue = 0]) =>
      _has(8, true, defaultValue);
  @override
  DataPointer<int> hasUint16([int defaultValue = 0]) =>
      _has(16, false, defaultValue);
  @override
  DataPointer<int> hasInt16([int defaultValue = 0]) =>
      _has(16, true, defaultValue);
  @override
  DataPointer<int> hasUint32([int defaultValue = 0]) =>
      _has(32, false, defaultValue);
  @override
  DataPointer<int> hasInt32([int defaultValue = 0]) =>
      _has(32, true, defaultValue);
  @override
  DataPointer<int> hasUint64([int defaultValue = 0]) =>
      _has(64, false, defaultValue);
  @override
  DataPointer<int> hasInt64([int defaultValue = 0]) =>
      _has(64, true, defaultValue);
  @override
  DataPointer<double> hasFloat32([double defaultValue = 0.0]) =>
      _hasFloat(32, defaultValue);
  @override
  DataPointer<double> hasFloat64([double defaultValue = 0.0]) =>
      _hasFloat(64, defaultValue);

  @override
  DataPointer<int?> optUint1([int? defaultValue]) =>
      _opt(1, false, defaultValue);
  @override
  DataPointer<int?> optInt1([int? defaultValue]) => _opt(1, true, defaultValue);
  @override
  DataPointer<int?> optUint2([int? defaultValue]) =>
      _opt(2, false, defaultValue);
  @override
  DataPointer<int?> optInt2([int? defaultValue]) => _opt(2, true, defaultValue);
  @override
  DataPointer<int?> optUint4([int? defaultValue]) =>
      _opt(4, false, defaultValue);
  @override
  DataPointer<int?> optInt4([int? defaultValue]) => _opt(4, true, defaultValue);
  @override
  DataPointer<int?> optUint8([int? defaultValue]) =>
      _opt(8, false, defaultValue);
  @override
  DataPointer<int?> optInt8([int? defaultValue]) => _opt(8, true, defaultValue);
  @override
  DataPointer<int?> optUint16([int? defaultValue]) =>
      _opt(16, false, defaultValue);
  @override
  DataPointer<int?> optInt16([int? defaultValue]) =>
      _opt(16, true, defaultValue);
  @override
  DataPointer<int?> optUint32([int? defaultValue]) =>
      _opt(32, false, defaultValue);
  @override
  DataPointer<int?> optInt32([int? defaultValue]) =>
      _opt(32, true, defaultValue);
  @override
  DataPointer<int?> optUint64([int? defaultValue]) =>
      _opt(64, false, defaultValue);
  @override
  DataPointer<int?> optInt64([int? defaultValue]) =>
      _opt(64, true, defaultValue);
  @override
  DataPointer<double?> optFloat32([double? defaultValue]) =>
      _optFloat(32, defaultValue);
  @override
  DataPointer<double?> optFloat64([double? defaultValue]) =>
      _optFloat(64, defaultValue);

  // --- array declaration helpers ---------------------------------------

  /// A zero- or negative-length array is rejected rather than quietly
  /// accepted: every index into it would be out of range, so it can only be
  /// a caller mistake, and catching it here (at describe time, once) beats
  /// a `RangeError` from every access at runtime.
  void _checkArrayLength(int length) {
    if (length < 1) {
      throw ArgumentError.value(length, 'length', 'must be at least 1');
    }
  }

  /// Reserves [length] consecutive [bitWidth]-bit elements and returns the
  /// *first* one's bit offset - the whole array's base. The rest is
  /// arithmetic; see the packing note above [_ArrayField] for why no gaps
  /// can appear between the elements.
  ///
  /// **The leading `while` is load-bearing, not defensive.** "Sub-byte
  /// widths divide 8, so `declareField`'s byte-rounding never fires
  /// mid-array" is only true once the array's *base* is a multiple of the
  /// element width. It is not true in general: `hasUint1()` followed by
  /// `hasUint4Array(4)` leaves the cursor at bit 1, so element 0 lands at
  /// bit 1 (1 + 4 <= 8, no rounding) but element 1 would need bits 5..8,
  /// straddles the byte, and gets pushed to bit 8 - a 3-bit gap that
  /// `baseBit + i * bitWidth` does not know about. Every later element would
  /// then be read and written at the wrong offset, aliasing its neighbours
  /// and, for the last one, corrupting whatever follows the array.
  ///
  /// Padding the cursor up to a multiple of [bitWidth] first removes the
  /// possibility: every element offset is then a multiple of [bitWidth],
  /// [bitWidth] divides 8, so `(offset & 7) + bitWidth <= 8` holds for all
  /// of them and the rounding branch never fires inside the array. The cost
  /// is at most 3 wasted bits, once, and only when the array does not
  /// already start aligned. `declareField(1)` is the padding tool because it
  /// is the only width that never itself rounds - it always advances the
  /// cursor by exactly one bit, so the loop terminates.
  int _declareElements(int length, int bitWidth) {
    if (bitWidth < 8) {
      while (_storage.bitLength % bitWidth != 0) {
        _storage.declareField(1);
      }
    }
    final baseBit = _storage.declareField(bitWidth);
    for (var i = 1; i < length; i++) {
      _storage.declareField(bitWidth);
    }
    return baseBit;
  }

  _ArrayField<int> _declareIntArray(
    int length,
    int bitWidth,
    bool signed,
    int defaultValue,
  ) {
    final baseBit = _declareElements(length, bitWidth);
    if (bitWidth < 8) {
      return signed
          ? _SubByteIntArrayField(
              _storage,
              length,
              baseBit,
              bitWidth,
              defaultValue,
            )
          : _SubByteUintArrayField(
              _storage,
              length,
              baseBit,
              bitWidth,
              defaultValue,
            );
    }
    final byte = baseBit >> 3;
    return switch ((bitWidth, signed)) {
      (8, false) => _Uint8ArrayField(_storage, length, byte, defaultValue),
      (8, true) => _Int8ArrayField(_storage, length, byte, defaultValue),
      (16, false) => _Uint16ArrayField(_storage, length, byte, defaultValue),
      (16, true) => _Int16ArrayField(_storage, length, byte, defaultValue),
      (32, false) => _Uint32ArrayField(_storage, length, byte, defaultValue),
      (32, true) => _Int32ArrayField(_storage, length, byte, defaultValue),
      _ => throw ArgumentError('unsupported integer bit width $bitWidth'),
    };
  }

  DataArrayPointer<int> _hasIntArray(
    int length,
    int bitWidth,
    bool signed,
    int defaultValue,
  ) {
    _checkArrayLength(length);
    final field = _declareIntArray(length, bitWidth, signed, defaultValue);
    _storage.registerField(field);
    return field;
  }

  DataArrayPointer<double> _hasFloatArray(
    int length,
    int bitWidth,
    double defaultValue,
  ) {
    _checkArrayLength(length);
    final byte = _declareElements(length, bitWidth) >> 3;
    final field = bitWidth == 32
        ? _Float32ArrayField(_storage, length, byte, defaultValue)
        : _Float64ArrayField(_storage, length, byte, defaultValue);
    _storage.registerField(field);
    return field;
  }

  /// The nullable case declares per element - flag, then value - which is
  /// why it cannot share [_declareElements]: the two widths interleave, so
  /// the elements are not evenly spaced. See [_OptionalArrayField].
  DataArrayPointer<int?> _optIntArray(
    int length,
    int bitWidth,
    bool signed,
    int? defaultValue,
  ) {
    _checkArrayLength(length);
    final flagBits = List<int>.filled(length, 0);
    final values = <_Field<int>>[];
    for (var i = 0; i < length; i++) {
      flagBits[i] = _storage.declareField(1);
      values.add(_declareInt(bitWidth, signed, defaultValue ?? 0));
    }
    final field = _OptionalArrayField<int>(
      _storage,
      length,
      flagBits,
      values,
      defaultValue != null,
    );
    _storage.registerField(field);
    return field;
  }

  DataArrayPointer<double?> _optFloatArray(
    int length,
    int bitWidth,
    double? defaultValue,
  ) {
    _checkArrayLength(length);
    final flagBits = List<int>.filled(length, 0);
    final values = <_Field<double>>[];
    for (var i = 0; i < length; i++) {
      flagBits[i] = _storage.declareField(1);
      values.add(_declareFloat(bitWidth, defaultValue ?? 0.0));
    }
    final field = _OptionalArrayField<double>(
      _storage,
      length,
      flagBits,
      values,
      defaultValue != null,
    );
    _storage.registerField(field);
    return field;
  }

  /// Rejects a width the row cannot hold, before it becomes silent
  /// truncation. A representation's width is a declare-time constant, so this
  /// fires once per field at bring-up and never on a hot path.
  int _checkBitWidth(IntRepresentation<Object?> repr) {
    final bitWidth = repr.bitWidth;
    if (bitWidth < 1 || bitWidth > 64) {
      throw ArgumentError.value(
        bitWidth,
        'bitWidth',
        '${repr.runtimeType} declares a width outside 1..64. A packed field is '
            'one integer in the row, so anything wider has no representation '
            'there - use separate fields instead.',
      );
    }
    return bitWidth;
  }

  PackedPointer<T> _hasPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    T defaultValue,
  ) {
    final bits = _declareInt(_checkBitWidth(repr), false, defaultValue.pack());
    final field = _PackedField<T>(_storage, bits, repr);
    _storage.registerField(field);
    return field;
  }

  DataPointer<T?> _optPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    T? defaultValue,
  ) {
    // Flag first, then the value - the value's own alignment rule then
    // applies to whatever byte the flag left the cursor in.
    final flagBit = _storage.declareField(1);
    final bits = _declareInt(
      _checkBitWidth(repr),
      false,
      defaultValue?.pack() ?? 0,
    );
    final value = _PackedField<T>(_storage, bits, repr);
    final field = _OptionalField<T>(
      _storage,
      flagBit,
      value,
      defaultValue != null,
    );
    _storage.registerField(field);
    return field;
  }

  DataArrayPointer<T> _hasPackedArray<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    int length,
    T defaultValue,
  ) {
    _checkArrayLength(length);
    final bits = _declareIntArray(
      length,
      _checkBitWidth(repr),
      false,
      defaultValue.pack(),
    );
    final field = _PackedArrayField<T>(_storage, length, bits, repr);
    _storage.registerField(field);
    return field;
  }

  DataArrayPointer<T?> _optPackedArray<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    int length,
    T? defaultValue,
  ) {
    _checkArrayLength(length);
    final bitWidth = _checkBitWidth(repr);
    final defaultBits = defaultValue?.pack() ?? 0;
    final flagBits = List<int>.filled(length, 0);
    final values = <_Field<T>>[];
    for (var i = 0; i < length; i++) {
      flagBits[i] = _storage.declareField(1);
      values.add(
        _PackedField<T>(
          _storage,
          _declareInt(bitWidth, false, defaultBits),
          repr,
        ),
      );
    }
    final field = _OptionalArrayField<T>(
      _storage,
      length,
      flagBits,
      values,
      defaultValue != null,
    );
    _storage.registerField(field);
    return field;
  }

  @override
  DataArrayPointer<int> hasUint1Array(int length, [int defaultValue = 0]) =>
      _hasIntArray(length, 1, false, defaultValue);
  @override
  DataArrayPointer<int> hasInt1Array(int length, [int defaultValue = 0]) =>
      _hasIntArray(length, 1, true, defaultValue);
  @override
  DataArrayPointer<int> hasUint2Array(int length, [int defaultValue = 0]) =>
      _hasIntArray(length, 2, false, defaultValue);
  @override
  DataArrayPointer<int> hasInt2Array(int length, [int defaultValue = 0]) =>
      _hasIntArray(length, 2, true, defaultValue);
  @override
  DataArrayPointer<int> hasUint4Array(int length, [int defaultValue = 0]) =>
      _hasIntArray(length, 4, false, defaultValue);
  @override
  DataArrayPointer<int> hasInt4Array(int length, [int defaultValue = 0]) =>
      _hasIntArray(length, 4, true, defaultValue);
  @override
  DataArrayPointer<int> hasUint8Array(int length, [int defaultValue = 0]) =>
      _hasIntArray(length, 8, false, defaultValue);
  @override
  DataArrayPointer<int> hasInt8Array(int length, [int defaultValue = 0]) =>
      _hasIntArray(length, 8, true, defaultValue);
  @override
  DataArrayPointer<int> hasUint16Array(int length, [int defaultValue = 0]) =>
      _hasIntArray(length, 16, false, defaultValue);
  @override
  DataArrayPointer<int> hasInt16Array(int length, [int defaultValue = 0]) =>
      _hasIntArray(length, 16, true, defaultValue);
  @override
  DataArrayPointer<int> hasUint32Array(int length, [int defaultValue = 0]) =>
      _hasIntArray(length, 32, false, defaultValue);
  @override
  DataArrayPointer<int> hasInt32Array(int length, [int defaultValue = 0]) =>
      _hasIntArray(length, 32, true, defaultValue);
  @override
  DataArrayPointer<double> hasFloat32Array(
    int length, [
    double defaultValue = 0.0,
  ]) => _hasFloatArray(length, 32, defaultValue);
  @override
  DataArrayPointer<double> hasFloat64Array(
    int length, [
    double defaultValue = 0.0,
  ]) => _hasFloatArray(length, 64, defaultValue);
  @override
  DataArrayPointer<int?> optUint1Array(int length, [int? defaultValue]) =>
      _optIntArray(length, 1, false, defaultValue);
  @override
  DataArrayPointer<int?> optInt1Array(int length, [int? defaultValue]) =>
      _optIntArray(length, 1, true, defaultValue);
  @override
  DataArrayPointer<int?> optUint2Array(int length, [int? defaultValue]) =>
      _optIntArray(length, 2, false, defaultValue);
  @override
  DataArrayPointer<int?> optInt2Array(int length, [int? defaultValue]) =>
      _optIntArray(length, 2, true, defaultValue);
  @override
  DataArrayPointer<int?> optUint4Array(int length, [int? defaultValue]) =>
      _optIntArray(length, 4, false, defaultValue);
  @override
  DataArrayPointer<int?> optInt4Array(int length, [int? defaultValue]) =>
      _optIntArray(length, 4, true, defaultValue);
  @override
  DataArrayPointer<int?> optUint8Array(int length, [int? defaultValue]) =>
      _optIntArray(length, 8, false, defaultValue);
  @override
  DataArrayPointer<int?> optInt8Array(int length, [int? defaultValue]) =>
      _optIntArray(length, 8, true, defaultValue);
  @override
  DataArrayPointer<int?> optUint16Array(int length, [int? defaultValue]) =>
      _optIntArray(length, 16, false, defaultValue);
  @override
  DataArrayPointer<int?> optInt16Array(int length, [int? defaultValue]) =>
      _optIntArray(length, 16, true, defaultValue);
  @override
  DataArrayPointer<int?> optUint32Array(int length, [int? defaultValue]) =>
      _optIntArray(length, 32, false, defaultValue);
  @override
  DataArrayPointer<int?> optInt32Array(int length, [int? defaultValue]) =>
      _optIntArray(length, 32, true, defaultValue);
  @override
  DataArrayPointer<double?> optFloat32Array(
    int length, [
    double? defaultValue,
  ]) => _optFloatArray(length, 32, defaultValue);
  @override
  DataArrayPointer<double?> optFloat64Array(
    int length, [
    double? defaultValue,
  ]) => _optFloatArray(length, 64, defaultValue);

  @override
  PackedPointer<T> hasPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    T defaultValue,
  ) => _hasPacked(repr, defaultValue);
  @override
  DataPointer<T?> optPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr, [
    T? defaultValue,
  ]) => _optPacked(repr, defaultValue);
  @override
  DataArrayPointer<T> hasPackedArray<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    int length,
    T defaultValue,
  ) => _hasPackedArray(repr, length, defaultValue);
  @override
  DataArrayPointer<T?> optPackedArray<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    int length, [
    T? defaultValue,
  ]) => _optPackedArray(repr, length, defaultValue);

  @override
  DataPointer<T> hasHeapObject<T>(T Function() defaultValue) {
    final byte = _storage.declareField(32) >> 3;
    final field = _HeapObjectField<T>(_storage, byte, defaultValue);
    _storage.registerField(field);
    return field;
  }

  @override
  DataPointer<T?> optHeapObject<T>() {
    final flagBit = _storage.declareField(1);
    final byte = _storage.declareField(32) >> 3;
    // No default factory: the wrapper's has-bit defaults to clear, so
    // `_OptionalField.writeDefault` never asks the value field for one and
    // a fresh entity reads `null`.
    final value = _HeapObjectField<T>(_storage, byte, null);
    final field = _OptionalField<T>(_storage, flagBit, value, false);
    _storage.registerField(field);
    return field;
  }
}

/// Collects the query-signature bits for one archetype during its
/// `describeType` pass.
final class ArchetypeComponentDescriptor implements ComponentDescriptor {
  ArchetypeComponentDescriptor(this._storage);

  final ArchetypeStorage _storage;

  @override
  void has<T extends Component>({Type? type}) {
    // Two spellings, one bit. A component *mixin* knows its own type
    // statically and says `has<Renderable2D>()`; an `EntityStruct` cannot,
    // because it no longer carries a type parameter naming itself, so it says
    // `has(type: runtimeType)`. `type` wins when both are available - passing
    // it is the deliberate act, while `T` merely falls back to its bound.
    _storage.componentSignature |= ComponentTypeRegistry.bitFor(type ?? T);
  }
}
