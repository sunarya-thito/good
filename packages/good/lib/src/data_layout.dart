import 'dart:ffi';

import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/declare.dart';
import 'package:good/src/heap_object.dart';
import 'package:good/src/struct.dart';

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

/// Rejects a column indexed with an entity of another archetype.
///
/// Nothing on the access path consults `entity.archetypeId` - [_readRow] and
/// [_writeRow] resolve a row from the page index and the row offset alone -
/// so a foreign entity does not fail where the mistake is made. It addresses
/// whatever row happens to sit at that page and offset in *this* archetype's
/// storage, which is a live entity of the wrong prefab, and the write lands
/// on it silently. `Child.declaredInArchetype` in `data/hierarchy.dart`
/// states the fact this rests on, for the one column kind that was guarded
/// before this existed: a column is a byte offset into one archetype's row
/// and means nothing in another's.
///
/// Shaped as a predicate rather than a two-argument `assert` inside
/// [_readRow] so that [column] never becomes a parameter of the row
/// resolvers. Everything here - the argument, the comparison, the message -
/// sits inside `assert(...)` at the call site and is gone from a release
/// build, which matters because [_readRow] is the hottest function in the
/// engine (see the measurements in its body). It always returns `true`, or
/// throws with the whole diagnosis.
///
/// The message names three things and needs all three: the entity's
/// archetype, the column's archetype, and the column. The symptom otherwise
/// surfaces arbitrarily far from the cause - a wrong value read in one
/// scene, long after a line that ran in another.
bool _ownsRow(ArchetypeStorage storage, Entity entity, Object column) {
  if (entity.archetypeId == storage.archetypeId) return true;
  final theirs = _prefabName(entity.archetypeId);
  final ours = _prefabName(storage.archetypeId);
  throw StateError(
    'Entity ${entity.value} belongs to archetype ${entity.archetypeId} '
    '($theirs), but this ${column.runtimeType} is a column of archetype '
    "${storage.archetypeId} ($ours). A column is a byte offset into one "
    "archetype's row and means nothing in another's, so this access does "
    'not fail where it is made: it reads or writes whatever row sits at '
    'page ${entity.pageIndex}, offset ${entity.rowOffset} of '
    "$ours's storage - very likely a different, live entity - and the "
    'damage surfaces later and somewhere else.\n'
    'Index a column with an entity of the prefab that declared it. Two '
    'scenes each declaring the same prefab type declare two archetypes, and '
    "reaching for the wrong scene's declaration is the usual way to arrive "
    'here.',
  );
}

/// The prefab type behind an archetype id, for a message that is already
/// reporting a broken access - so every step of it has to survive an id that
/// names nothing and a storage that never got its prefab.
String _prefabName(int archetypeId) {
  try {
    return ArchetypeRegistry.byId(archetypeId).prefab.runtimeType.toString();
  } on Object {
    return 'unregistered';
  }
}

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
///
/// Takes no argument it does not need. The foreign-entity check that guards
/// this lives in [_ownsRow], called from an `assert` in the accessors above
/// it, so the field it names never reaches this signature - see the numbers
/// in the body for how little room there is here.
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
/// The tick assertion catches silent data loss: `MemoryPool.beginTick` copies
/// each page's published bytes over the write slot, so a write that lands
/// outside a tick window is erased by the next `beginTick` with no error
/// anywhere. Writing before the *first* publish is fine and common (scene
/// bootstrap) and is not lost at all - a page that never published has nothing
/// to be copied over it - hence the second clause. Debug-only: it compiles out
/// of a release build, so the hot path stays a page lookup and a pointer add.
///
/// **It is no longer the only guard, and it is no longer the one that matters
/// most.** It reports a *lost write* by whoever made it - a `Tickable` writing
/// during presentation, a callback resuming after `commitTick`. The narrower
/// and far more dangerous case, a command handler running on a lane that
/// promised not to write, is refused outright in `ArchetypeStorage.rowWrite`
/// before this line is reached, in every build and on an unpublished page too.
/// See `HandlerWindow` (#245).
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
  /// caller and which explains why the rest throw rather than answer with
  /// the published value.
  T readFrom(int row) => throw UnsupportedError(
    '$runtimeType does not implement readFrom - see DataPointer.readPending.',
  );

  @pragma('vm:prefer-inline')
  int _write(Entity entity) {
    assert(_ownsRow(_storage, entity, this));
    return _writeRow(_storage, entity);
  }

  @pragma('vm:prefer-inline')
  int _read(Entity entity) {
    assert(_ownsRow(_storage, entity, this));
    return _readRow(_storage, entity);
  }
}

/// A field whose stamped default can still be changed - see
/// [InitialPointer.initialValue] for which column kinds get one and why the
/// rest do not.
///
/// Every width already held its default in a `_default` of its own; this
/// hoists them into one mutable field. `writeInitialValue` reads it at `seal`, so
/// a change made before then simply lands in the prototype row and a change
/// made after cannot land anywhere - which is what [_requireUnsealed] is
/// for.
abstract base class _ValueField<T> extends _Field<T>
    implements InitialPointer<T> {
  _ValueField(super.storage, this._default);

  /// What [writeInitialValue] stamps. Held here rather than once per width so the
  /// setter and its guard are written once, and so [_DefaultableOptionalField]
  /// can reach the value half of a nullable column's default.
  T _default;

  @override
  T get initialValue => _default;

  @override
  set initialValue(T newValue) {
    _requireUnsealed(_storage);
    _default = newValue;
  }
}

/// Rejects a default set after [ArchetypeStorage.seal] has already stamped
/// the prototype row.
///
/// The message names both spellings on purpose. `near.initialValue = 10` and
/// `near[entity] = 10` are one keystroke apart and mean entirely different
/// things, and a caller who reaches here has almost certainly typed the
/// first while meaning the second.
void _requireUnsealed(ArchetypeStorage storage) {
  if (!storage.isSealed) return;
  throw StateError(
    'A column default was set after ${storage.prefab.runtimeType}\'s '
    'archetype was sealed, so it can no longer take effect. Defaults are '
    'stamped once: seal() builds a prototype row holding every column\'s '
    'default and copies it into each row allocated after that, and nothing '
    'consults the default again.\n'
    '  near.initialValue = 10;  // declare time - a field initialiser, or a '
    'prefab\'s describeStruct\n'
    '  near[entity] = 10;       // run time - this one entity, right now\n'
    'If you meant to change what new entities of this prefab start with, '
    'set it while the struct is being described. If you meant to change one '
    'entity, subscript the column with it.',
  );
}

/// A `bool` view over a one-bit field.
///
/// Delegation rather than a new `_Field` subclass: the bit-packing, the
/// default handling and the row resolution are already right in the `uint1`
/// field this wraps, and a parallel implementation would be a second copy of
/// them to keep in step (the one-fact-one-place rule). [_EntityHandleField]
/// and [_OptionalEntityHandleField] wrap the int64 fields the same way for
/// the same reason.
///
/// The wrapper is not free at the call site the way a raw field is - it adds
/// one virtual call and a compare per access - but it is only ever used for
/// flags, which are read once per entity per tick at most, never in the
/// per-field inner loops the `int` accessors were tuned for.
///
/// `readPending` is not delegated - the one-bit field this wraps does not
/// implement it, so forwarding reported the failure under
/// `_SubByteUintField`, a class no declaration names and no caller asks for.
/// [_EntityHandleField] and [_EnumField] leave it alone for the same reason.
class _BoolField extends InitialPointer<bool> {
  const _BoolField(this._raw);

  final InitialPointer<int> _raw;

  @override
  bool operator [](Entity entity) => _raw[entity] != 0;

  @override
  void operator []=(Entity entity, bool newValue) =>
      _raw[entity] = newValue ? 1 : 0;

  /// Delegated for the same reason everything else here is: the seal guard
  /// and the stamped value both live in the field being wrapped.
  @override
  bool get initialValue => _raw.initialValue != 0;

  @override
  set initialValue(bool newValue) => _raw.initialValue = newValue ? 1 : 0;
}

/// An `Entity` view over the `int64` field `hasEntity` declares.
///
/// Delegation for the same reason [_BoolField] delegates: the row
/// resolution, the default stamping and the 64-bit load/store are already
/// right in the `_Int64Field` this wraps (the one-fact-one-place rule).
/// [_OptionalEntityHandleField] is the nullable twin of this, over the
/// `optInt64` path.
///
/// `Entity` is an extension type over `int`, so it erases: the value handed
/// back is the very `int` the field read, and `Entity(...)` compiles to
/// nothing. The wrapper costs one virtual call per access and no allocation.
///
/// `readPending` is not delegated - `_Int64Field` does not implement it, so
/// forwarding would only move the `UnsupportedError` to a message naming the
/// wrong class.
class _EntityHandleField extends InitialPointer<Entity> {
  const _EntityHandleField(this._raw);

  final InitialPointer<int> _raw;

  @override
  Entity operator [](Entity entity) => Entity(_raw[entity]);

  @override
  void operator []=(Entity entity, Entity newValue) =>
      _raw[entity] = newValue.value;

  @override
  Entity get initialValue => Entity(_raw.initialValue);

  @override
  set initialValue(Entity newValue) => _raw.initialValue = newValue.value;
}

/// An `Entity?` view over the nullable `int64` field `optEntity` declares -
/// a presence flag and, when it is set, a packed handle beside it.
///
/// Delegation for the same reason [_EntityHandleField] delegates: the flag,
/// the value and the default stamping are already right in the
/// `_OptionalField` this wraps (the one-fact-one-place rule). `Entity` is an
/// extension type over `int`, so the value handed back is the very `int?`
/// the field read and `Entity(...)` compiles to nothing.
///
/// `readPending` *is* delegated here, unlike [_EntityHandleField]'s.
/// `_OptionalField` implements it - taking the flag and the value from the
/// same pending row - so forwarding reaches a real implementation rather
/// than relabelling an `UnsupportedError`. `data/hierarchy.dart` splices its
/// child lists through it, so this path is load-bearing: two `addChild`
/// calls in one tick need the second to see the link the first wrote.
class _OptionalEntityHandleField extends InitialPointer<Entity?> {
  const _OptionalEntityHandleField(this._raw);

  final InitialPointer<int?> _raw;

  @override
  Entity? get initialValue {
    final value = _raw.initialValue;
    return value == null ? null : Entity(value);
  }

  @override
  set initialValue(Entity? newValue) => _raw.initialValue = newValue?.value;

  @override
  Entity? operator [](Entity entity) {
    final value = _raw[entity];
    return value == null ? null : Entity(value);
  }

  @override
  void operator []=(Entity entity, Entity? newValue) =>
      _raw[entity] = newValue?.value;

  @override
  Entity? readPending(Entity entity) {
    final value = _raw.readPending(entity);
    return value == null ? null : Entity(value);
  }
}

/// An `E` view over the unsigned field `hasEnum` declares, which holds the
/// member's `index`.
///
/// Delegation for the same reason [_EntityHandleField] delegates: the width,
/// the default stamping and the row resolution are already right in the field
/// this wraps (the one-fact-one-place rule).
///
/// [_values] is the enum's own `values` list, so a read is one load out of a
/// const list and allocates nothing.
///
/// `readPending` is not delegated - the narrow int fields this wraps do not
/// implement it, so forwarding would only move the `UnsupportedError` to a
/// message naming the wrong class.
class _EnumField<E extends Enum> extends InitialPointer<E> {
  const _EnumField(this._raw, this._values);

  final InitialPointer<int> _raw;
  final List<E> _values;

  @override
  E operator [](Entity entity) => _values[_raw[entity]];

  @override
  void operator []=(Entity entity, E newValue) => _raw[entity] = newValue.index;

  @override
  E get initialValue => _values[_raw.initialValue];

  @override
  set initialValue(E newValue) => _raw.initialValue = newValue.index;
}

/// The narrowest unsigned width that can index [count] members.
///
/// Widths are in *bits*, so a three-member enum answers 2 - the two bits
/// callers spent on `hasUint2` when they packed the index by hand.
///
/// The ladder stops at 32: Dart evaluates `1 << 64` to 0, so a 64-bit rung
/// could not state its own bound. An enum big enough to need one cannot be
/// written down, so the throw is what an out-of-range [count] hits rather
/// than silently truncating to a width that cannot hold it.
int _enumIndexWidth(int count) {
  for (final width in const [1, 2, 4, 8, 16, 32]) {
    if (count <= 1 << width) return width;
  }
  throw ArgumentError.value(
    count,
    'values.length',
    'more members than a 32-bit index column can address',
  );
}

// --- sub-byte fields ---------------------------------------------------
//
// 1/2/4-bit fields never span a byte (see ArchetypeStorage.declareField),
// so both directions are a single-byte access: read is load/shift/mask,
// write is a load/mask/or/store read-modify-write. `_byteMask` is the
// field's bits in place; `_valueMask` is them at bit 0.

base class _SubByteUintField extends _ValueField<int> {
  _SubByteUintField(
    super.storage,
    int bitOffset,
    int bitWidth,
    super.initialValue,
  ) : _byte = bitOffset >> 3,
      _shift = bitOffset & 7,
      _valueMask = (1 << bitWidth) - 1,
      _byteMask = ((1 << bitWidth) - 1) << (bitOffset & 7),
      _signBit = 1 << (bitWidth - 1),
      _range = 1 << bitWidth;

  final int _byte;
  final int _shift;
  final int _valueMask;
  final int _byteMask;

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
  void writeInitialValue(int row) => _store(row, _default);
}

/// Two's-complement variant. Note `hasInt1` therefore holds -1 or 0, which
/// is what a 1-bit two's-complement integer means - it is not a bool with
/// values 0/1 (`hasUint1` is that).
final class _SubByteIntField extends _SubByteUintField {
  _SubByteIntField(
    super.storage,
    super.bitOffset,
    super.bitWidth,
    super.initialValue,
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

final class _Uint8Field extends _ValueField<int> {
  _Uint8Field(super.storage, this._byte, super.initialValue);
  final int _byte;

  @override
  int operator [](Entity entity) =>
      Pointer<Uint8>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Uint8>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeInitialValue(int row) =>
      Pointer<Uint8>.fromAddress(row + _byte).value = _default;
}

final class _Int8Field extends _ValueField<int> {
  _Int8Field(super.storage, this._byte, super.initialValue);
  final int _byte;

  @override
  int operator [](Entity entity) =>
      Pointer<Int8>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Int8>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeInitialValue(int row) =>
      Pointer<Int8>.fromAddress(row + _byte).value = _default;
}

final class _Uint16Field extends _ValueField<int> {
  _Uint16Field(super.storage, this._byte, super.initialValue);
  final int _byte;

  @override
  int operator [](Entity entity) =>
      Pointer<Uint16>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Uint16>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeInitialValue(int row) =>
      Pointer<Uint16>.fromAddress(row + _byte).value = _default;
}

final class _Int16Field extends _ValueField<int> {
  _Int16Field(super.storage, this._byte, super.initialValue);
  final int _byte;

  @override
  int operator [](Entity entity) =>
      Pointer<Int16>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Int16>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeInitialValue(int row) =>
      Pointer<Int16>.fromAddress(row + _byte).value = _default;
}

final class _Uint32Field extends _ValueField<int> {
  _Uint32Field(super.storage, this._byte, super.initialValue);
  final int _byte;

  @override
  int operator [](Entity entity) =>
      Pointer<Uint32>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Uint32>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeInitialValue(int row) =>
      Pointer<Uint32>.fromAddress(row + _byte).value = _default;
}

final class _Int32Field extends _ValueField<int> {
  _Int32Field(super.storage, this._byte, super.initialValue);
  final int _byte;

  @override
  int operator [](Entity entity) =>
      Pointer<Int32>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Int32>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeInitialValue(int row) =>
      Pointer<Int32>.fromAddress(row + _byte).value = _default;
}

// Uint64/Int64 exist mainly so a field can hold a full packed `Entity`
// handle - see the doc on DataDescriptor.hasUint64/hasInt64 in data.dart.
// dart:ffi's Uint64 getter/setter round-trip the same 64-bit pattern
// Dart's own (signed, twos-complement) `int` already uses, so this is a
// plain aligned load/store exactly like the narrower widths, no different
// handling needed for values that "look negative".
final class _Uint64Field extends _ValueField<int> {
  _Uint64Field(super.storage, this._byte, super.initialValue);
  final int _byte;

  @override
  int operator [](Entity entity) =>
      Pointer<Uint64>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, int newValue) =>
      Pointer<Uint64>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeInitialValue(int row) =>
      Pointer<Uint64>.fromAddress(row + _byte).value = _default;
}

final class _Int64Field extends _ValueField<int> {
  _Int64Field(super.storage, this._byte, super.initialValue);
  final int _byte;

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
  void writeInitialValue(int row) =>
      Pointer<Int64>.fromAddress(row + _byte).value = _default;
}

// dart:ffi names the IEEE-754 types Float/Double, not Float32/Float64.
final class _Float32Field extends _ValueField<double> {
  _Float32Field(super.storage, this._byte, super.initialValue);
  final int _byte;

  @override
  double operator [](Entity entity) =>
      Pointer<Float>.fromAddress(_read(entity) + _byte).value;

  @override
  void operator []=(Entity entity, double newValue) =>
      Pointer<Float>.fromAddress(_write(entity) + _byte).value = newValue;

  @override
  void writeInitialValue(int row) =>
      Pointer<Float>.fromAddress(row + _byte).value = _default;
}

final class _Float64Field extends _ValueField<double> {
  _Float64Field(super.storage, this._byte, super.initialValue);
  final int _byte;

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
  double readPending(Entity entity) {
    // Outside a tick there is no meaningful write slot: the one the buffer
    // hands back holds whatever sat there before `beginWrite` copied, so the
    // published read is the only correct answer - which is what
    // `DataPointer.readPending` states and what `_OptionalField.readPending`
    // already did. Reaching for `_write` here also tripped the lost-write
    // assertion on a page that has published, reporting a write this call
    // never makes.
    if (!_storage.pool.isTickOpen) return this[entity];
    return Pointer<Double>.fromAddress(_write(entity) + _byte).value;
  }

  @override
  void writeInitialValue(int row) =>
      Pointer<Double>.fromAddress(row + _byte).value = _default;
}

// --- packed value fields -------------------------------------------------
//
// hasPacked<T extends IntRepresentable> stores a plain integer in the row, so a
// component row never holds a Dart heap reference (the no-allocation rule).
// Writes call `pack()`; reads `unpack()` it back through the
// `IntRepresentation` the field was declared against.
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

/// The bits, the packing and the unpacking, with **no bound on [T]**.
///
/// `hasArray` reaches a representation through `DataElement<T>`, whose `T` is
/// unbounded, and Dart cannot recover `T extends IntRepresentable` from a
/// `switch` that matched an `IntRepresentation`. So the bound lives where it
/// is actually needed - on the public signatures, and on
/// [_PackedPointerField] below - and this class holds the representation
/// covariantly as `IntRepresentation<IntRepresentable>`, which every
/// `IntRepresentation<X>` is. Nothing constructs one except the two declare
/// paths that already checked the element is a representation, so the two
/// casts here cannot fail.
base class _PackedField<T> extends _Field<T> {
  _PackedField(super.storage, this._bits, this._repr);

  /// The integer field holding the packed bits. Declared and owned here, and
  /// deliberately **not** registered with the storage itself - this field's
  /// own [writeInitialValue] drives it, so registering both would stamp the
  /// initial value twice.
  final _Field<int> _bits;
  final IntRepresentation<IntRepresentable> _repr;

  @override
  T operator [](Entity entity) => _repr.unpack(_bits[entity]) as T;

  @override
  void operator []=(Entity entity, T newValue) =>
      _bits[entity] = (newValue as IntRepresentable).pack();

  @override
  void writeInitialValue(int row) => _bits.writeInitialValue(row);
}

/// [_PackedField] with the bound back on, which is what lets it be the
/// [PackedPointer] `hasPacked` hands out. `packedAt` lives here and not on
/// the base because only the scalar declaration exposes it - an array
/// element is read through `DataArrayPointer`, which has no such escape
/// hatch.
final class _PackedPointerField<T extends IntRepresentable>
    extends _PackedField<T>
    implements PackedPointer<T> {
  _PackedPointerField(super.storage, super.bits, super.repr);

  @override
  int packedAt(Entity entity) => _bits[entity];
}

/// `hasHeapObject`/`optHeapObject`: a Uint32 address in the row, resolved
/// through [HeapObjectRegistry] instead of through the [IntRepresentation] a
/// [_PackedPointerField] carries.
/// See `DataDescriptor.hasHeapObject`'s doc for when to reach for which.
///
/// **Every write registers a new slot.** There is no attempt to notice that
/// the same object was written twice and reuse its address - that would need
/// an identity map consulted on the hot path, which is exactly what this
/// engine's row storage exists to avoid. So `field[e] = x` twice leaves the
/// first slot occupied until the entity is destroyed, which is when
/// [releaseRow] frees whatever address the row holds by then. Accepted, and
/// documented rather than half-solved: heap-object fields are for references
/// assigned a bounded number of times, not for per-tick churn.
///
/// Destruction itself no longer leaks. It did, for as long as the note here
/// said entity destruction was the natural place to free a slot and this
/// engine had no despawn API - `destroy()` had existed for some time by then
/// (#49). See [HeapObjectRegistry] for the hook and for how a row that never
/// wrote the field is told apart from one that did.
///
/// **The default is a factory, and it is called exactly once.**
/// [writeInitialValue] runs once, at `ArchetypeStorage.seal`, to build the
/// prototype row; `allocateRow` then *memcpy*s that row into every spawned
/// entity. A memcpy copies the 4-byte address, not the object - so every
/// entity that does not overwrite the field shares one default instance.
/// That is the intended behaviour: it is exactly what
/// [DataDescriptor.hasPacked] already does with its `initialValue`, and the
/// alternative (a fresh instance per entity) is not expressible here at all,
/// because there is no per-spawn hook to run a factory in - only the memcpy.
/// The factory exists so the default can be *built* at seal time rather than
/// forced into existence at `describeStruct` time; it does not, and cannot,
/// make the default per-entity.
final class _HeapObjectField<T> extends _Field<T>
    implements HeapArchetypeField {
  _HeapObjectField(super.storage, this._byte, this._initialFactory);
  final int _byte;

  /// `null` for the `optHeapObject` case, whose wrapper never asks for a
  /// default (its has-bit defaults to clear, i.e. `null`).
  final T Function()? _initialFactory;

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
  void writeInitialValue(int row) {
    final factory = _initialFactory;
    Pointer<Uint32>.fromAddress(row + _byte).value = factory == null
        ? 0
        : HeapObjectRegistry.register(factory());
  }

  /// Frees this row's slot unless the row still carries the prototype's.
  ///
  /// The equality test is doing real work in both directions - see
  /// `ArchetypeStorage.releaseHeapSlots` for why the shared default must
  /// survive, and why `optHeapObject`'s 0 cannot simply be special-cased.
  @override
  void releaseRow(int row, int prototype) {
    final address = Pointer<Uint32>.fromAddress(row + _byte).value;
    if (address == Pointer<Uint32>.fromAddress(prototype + _byte).value) return;
    HeapObjectRegistry.unregister(address);
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
base class _OptionalField<T> extends _Field<T?> {
  _OptionalField(
    super.storage,
    int flagBitOffset,
    this._value,
    this._initialPresent,
  ) : _flagByte = flagBitOffset >> 3,
      _flagMask = 1 << (flagBitOffset & 7);

  final int _flagByte;
  final int _flagMask;
  final _Field<T> _value;

  /// Whether a fresh row starts with the flag set. Not `final` because
  /// [_DefaultableOptionalField] moves it - a nullable column's default has
  /// two halves, and `null` is the one that is only the flag.
  bool _initialPresent;

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
    final row = _write(entity);
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
  void writeInitialValue(int row) {
    if (_initialPresent) {
      Pointer<Uint8>.fromAddress(row + _flagByte).value =
          Pointer<Uint8>.fromAddress(row + _flagByte).value | _flagMask;
      _value.writeInitialValue(row);
    } else {
      Pointer<Uint8>.fromAddress(row + _flagByte).value =
          Pointer<Uint8>.fromAddress(row + _flagByte).value & ~_flagMask & 0xFF;
    }
  }
}

/// The nullable columns that carry a settable default: `optInt32`,
/// `optFloat64`, `optEntity` and the rest of the scalar `opt*` family.
///
/// A separate class because [_OptionalField] also wraps a packed field
/// (`optPacked`) and a heap-object one (`optHeapObject`), neither of which
/// has a default to offer - see [InitialPointer.initialValue].
///
/// Setting `null` clears the presence flag and leaves the value half alone,
/// exactly as writing `null` to an entity does, because nothing reads the
/// value without first seeing the flag.
final class _DefaultableOptionalField<T> extends _OptionalField<T>
    implements InitialPointer<T?> {
  _DefaultableOptionalField(
    ArchetypeStorage storage,
    int flagBitOffset,
    this._defaultableValue,
    // ignore: avoid_positional_boolean_parameters
    bool defaultPresent,
  ) : super(storage, flagBitOffset, _defaultableValue, defaultPresent);

  /// The same object `_OptionalField._value` holds, typed so its own default
  /// is reachable.
  final _ValueField<T> _defaultableValue;

  /// `null` when the flag starts clear, whatever the value half happens to
  /// hold - the value bits are don't-care while the flag is down, exactly as
  /// they are for a row.
  @override
  T? get initialValue => _initialPresent ? _defaultableValue._default : null;

  @override
  set initialValue(T? newValue) {
    _requireUnsealed(_storage);
    _initialPresent = newValue != null;
    if (newValue != null) _defaultableValue._default = newValue;
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

  int _read(Entity entity) {
    assert(_ownsRow(_storage, entity, this));
    return _readRow(_storage, entity);
  }

  int _write(Entity entity) {
    assert(_ownsRow(_storage, entity, this));
    return _writeRow(_storage, entity);
  }

  /// Bounds check. Without it an out-of-range index is not an error but
  /// silent corruption: the arithmetic would happily address a neighbouring
  /// field's bits, or - past the end of the row - the next entity's row
  /// entirely, since rows are packed back to back in a page.
  ///
  /// Every caller spells it `assert(_checkIndex(index))`, so it returns
  /// `true` rather than nothing and throws rather than answering `false`.
  /// That shape is what keeps it out of a release build: this is the most
  /// called guard in the engine - 22 call sites, one on every element get
  /// and every element set - and a compare and a branch on each of those is
  /// a cost every shipped game pays to catch a mistake that only a developer
  /// can make. Debug is where the indexing is wrong; release trusts it.
  bool _checkIndex(int index) {
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this, 'index', null, length);
    }
    return true;
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
    this._defaults,
  ) : _valueMask = (1 << _bitWidth) - 1,
      _signBit = 1 << (_bitWidth - 1),
      _range = 1 << _bitWidth;

  final int _baseBit;
  final int _bitWidth;
  final int _valueMask;

  /// One entry per element, exactly as in [_Float64ArrayField].
  final List<int> _defaults;

  // Only [_SubByteIntArrayField] reads these; same arrangement as the
  // scalar pair, so the signed variant stays a super-parameter subclass.
  final int _signBit;
  final int _range;

  @override
  int get(Entity entity, int index) {
    assert(_checkIndex(index));
    final bit = _baseBit + index * _bitWidth;
    return (Pointer<Uint8>.fromAddress(_read(entity) + (bit >> 3)).value >>
            (bit & 7)) &
        _valueMask;
  }

  @override
  void set(Entity entity, int index, int newValue) {
    assert(_checkIndex(index));
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
  void writeInitialValue(int row) {
    for (var i = 0; i < length; i++) {
      _store(row, i, _defaults[i]);
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
    super.defaults,
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
  _Uint8ArrayField(super.storage, super.length, this._baseByte, this._defaults);
  final int _baseByte;

  /// One entry per element, exactly as in [_Float64ArrayField].
  final List<int> _defaults;

  @override
  int get(Entity entity, int index) {
    assert(_checkIndex(index));
    return Pointer<Uint8>.fromAddress(_read(entity) + _baseByte + index).value;
  }

  @override
  void set(Entity entity, int index, int newValue) {
    assert(_checkIndex(index));
    Pointer<Uint8>.fromAddress(_write(entity) + _baseByte + index).value =
        newValue;
  }

  @override
  void writeInitialValue(int row) {
    for (var i = 0; i < length; i++) {
      Pointer<Uint8>.fromAddress(row + _baseByte + i).value = _defaults[i];
    }
  }
}

final class _Int8ArrayField extends _ArrayField<int> {
  _Int8ArrayField(super.storage, super.length, this._baseByte, this._defaults);
  final int _baseByte;

  /// One entry per element, exactly as in [_Float64ArrayField].
  final List<int> _defaults;

  @override
  int get(Entity entity, int index) {
    assert(_checkIndex(index));
    return Pointer<Int8>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, int newValue) {
    assert(_checkIndex(index));
    Pointer<Int8>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeInitialValue(int row) {
    final elements = Pointer<Int8>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _defaults[i];
    }
  }
}

final class _Uint16ArrayField extends _ArrayField<int> {
  _Uint16ArrayField(super.storage, super.length, this._baseByte, this._defaults);
  final int _baseByte;

  /// One entry per element, exactly as in [_Float64ArrayField].
  final List<int> _defaults;

  @override
  int get(Entity entity, int index) {
    assert(_checkIndex(index));
    return Pointer<Uint16>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, int newValue) {
    assert(_checkIndex(index));
    Pointer<Uint16>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeInitialValue(int row) {
    final elements = Pointer<Uint16>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _defaults[i];
    }
  }
}

final class _Int16ArrayField extends _ArrayField<int> {
  _Int16ArrayField(super.storage, super.length, this._baseByte, this._defaults);
  final int _baseByte;

  /// One entry per element, exactly as in [_Float64ArrayField].
  final List<int> _defaults;

  @override
  int get(Entity entity, int index) {
    assert(_checkIndex(index));
    return Pointer<Int16>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, int newValue) {
    assert(_checkIndex(index));
    Pointer<Int16>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeInitialValue(int row) {
    final elements = Pointer<Int16>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _defaults[i];
    }
  }
}

final class _Uint32ArrayField extends _ArrayField<int> {
  _Uint32ArrayField(super.storage, super.length, this._baseByte, this._defaults);
  final int _baseByte;

  /// One entry per element, exactly as in [_Float64ArrayField].
  final List<int> _defaults;

  @override
  int get(Entity entity, int index) {
    assert(_checkIndex(index));
    return Pointer<Uint32>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, int newValue) {
    assert(_checkIndex(index));
    Pointer<Uint32>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeInitialValue(int row) {
    final elements = Pointer<Uint32>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _defaults[i];
    }
  }
}

final class _Int32ArrayField extends _ArrayField<int> {
  _Int32ArrayField(super.storage, super.length, this._baseByte, this._defaults);
  final int _baseByte;

  /// One entry per element, exactly as in [_Float64ArrayField].
  final List<int> _defaults;

  @override
  int get(Entity entity, int index) {
    assert(_checkIndex(index));
    return Pointer<Int32>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, int newValue) {
    assert(_checkIndex(index));
    Pointer<Int32>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeInitialValue(int row) {
    final elements = Pointer<Int32>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _defaults[i];
    }
  }
}

final class _Float32ArrayField extends _ArrayField<double> {
  _Float32ArrayField(
    super.storage,
    super.length,
    this._baseByte,
    this._defaults,
  );
  final int _baseByte;

  /// One entry per element, so [DataDescriptor.hasArrayOf] can start each
  /// element at its own value; the broadcast form fills this with `length`
  /// copies of the one default. Built once at declare time and read once at seal.
  final List<double> _defaults;

  @override
  double get(Entity entity, int index) {
    assert(_checkIndex(index));
    return Pointer<Float>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, double newValue) {
    assert(_checkIndex(index));
    Pointer<Float>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeInitialValue(int row) {
    final elements = Pointer<Float>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _defaults[i];
    }
  }
}

final class _Float64ArrayField extends _ArrayField<double> {
  _Float64ArrayField(
    super.storage,
    super.length,
    this._baseByte,
    this._defaults,
  );
  final int _baseByte;

  /// Per element, exactly as in [_Float32ArrayField].
  final List<double> _defaults;

  @override
  double get(Entity entity, int index) {
    assert(_checkIndex(index));
    return Pointer<Double>.fromAddress(_read(entity) + _baseByte)[index];
  }

  @override
  void set(Entity entity, int index, double newValue) {
    assert(_checkIndex(index));
    Pointer<Double>.fromAddress(_write(entity) + _baseByte)[index] = newValue;
  }

  @override
  void writeInitialValue(int row) {
    final elements = Pointer<Double>.fromAddress(row + _baseByte);
    for (var i = 0; i < length; i++) {
      elements[i] = _defaults[i];
    }
  }
}

/// A representation element of [DataDescriptor.hasArray] - the per-element
/// repeat of [_PackedField], holding one
/// integer element field and packing/unpacking around it.
///
/// Delegating to an integer *array* field rather than to `Pointer<Uint32>`
/// arithmetic is what carries the variable width through: element stride,
/// sub-byte packing and bounds checking are all already solved there, and a
/// representation narrower than 32 bits pays for itself `length` times over
/// here.
/// [T] is unbounded here for [_PackedField]'s reason, and the two casts
/// cannot fail for the same one.
final class _PackedArrayField<T> extends _ArrayField<T> {
  _PackedArrayField(super.storage, super.length, this._bits, this._repr);

  final _ArrayField<int> _bits;
  final IntRepresentation<IntRepresentable> _repr;

  @override
  T get(Entity entity, int index) {
    assert(_checkIndex(index));
    return _repr.unpack(_bits.get(entity, index)) as T;
  }

  @override
  void set(Entity entity, int index, T newValue) {
    assert(_checkIndex(index));
    _bits.set(entity, index, (newValue as IntRepresentable).pack());
  }

  @override
  void writeInitialValue(int row) => _bits.writeInitialValue(row);
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
    this._initialPresent,
  );

  /// Bit offset of element `i`'s has-flag.
  final List<int> _flagBits;

  /// Element `i`'s value accessor. Registered with the storage only through
  /// this wrapper - never on their own - so the flag decides whether an
  /// element's value default gets stamped at all.
  final List<_Field<T>> _values;

  final bool _initialPresent;

  @override
  T? get(Entity entity, int index) {
    assert(_checkIndex(index));
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
    assert(_checkIndex(index));
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
  void writeInitialValue(int row) {
    for (var i = 0; i < length; i++) {
      final flagBit = _flagBits[i];
      final byte = flagBit >> 3;
      final mask = 1 << (flagBit & 7);
      if (_initialPresent) {
        Pointer<Uint8>.fromAddress(row + byte).value =
            Pointer<Uint8>.fromAddress(row + byte).value | mask;
        _values[i].writeInitialValue(row);
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

  _ValueField<int> _declareInt(int bitWidth, bool signed, int initialValue) {
    final bitOffset = _storage.declareField(bitWidth);
    if (bitWidth < 8) {
      return signed
          ? _SubByteIntField(_storage, bitOffset, bitWidth, initialValue)
          : _SubByteUintField(_storage, bitOffset, bitWidth, initialValue);
    }
    final byte = bitOffset >> 3;
    return switch ((bitWidth, signed)) {
      (8, false) => _Uint8Field(_storage, byte, initialValue),
      (8, true) => _Int8Field(_storage, byte, initialValue),
      (16, false) => _Uint16Field(_storage, byte, initialValue),
      (16, true) => _Int16Field(_storage, byte, initialValue),
      (32, false) => _Uint32Field(_storage, byte, initialValue),
      (32, true) => _Int32Field(_storage, byte, initialValue),
      (64, false) => _Uint64Field(_storage, byte, initialValue),
      (64, true) => _Int64Field(_storage, byte, initialValue),
      _ => throw ArgumentError('unsupported integer bit width $bitWidth'),
    };
  }

  _ValueField<double> _declareFloat(int bitWidth, double initialValue) {
    final byte = _storage.declareField(bitWidth) >> 3;
    return bitWidth == 32
        ? _Float32Field(_storage, byte, initialValue)
        : _Float64Field(_storage, byte, initialValue);
  }

  InitialPointer<int> _has(int bitWidth, bool signed, int initialValue) {
    final field = _declareInt(bitWidth, signed, initialValue);
    _storage.registerField(field);
    return field;
  }

  InitialPointer<double> _hasFloat(int bitWidth, double initialValue) {
    final field = _declareFloat(bitWidth, initialValue);
    _storage.registerField(field);
    return field;
  }

  InitialPointer<int?> _opt(int bitWidth, bool signed, int? initialValue) {
    // Flag first, then the value - but the flag takes a bit an earlier
    // field's byte-rounding stranded when there is one, so it usually costs
    // the row nothing (see `ArchetypeStorage.declareFlagBit`). The value
    // still comes from the cursor, so its own alignment rule is unchanged.
    final flagBit = _storage.declareFlagBit();
    final value = _declareInt(bitWidth, signed, initialValue ?? 0);
    final field = _DefaultableOptionalField<int>(
      _storage,
      flagBit,
      value,
      initialValue != null,
    );
    _storage.registerField(field);
    return field;
  }

  InitialPointer<double?> _optFloat(int bitWidth, double? initialValue) {
    final flagBit = _storage.declareFlagBit();
    final value = _declareFloat(bitWidth, initialValue ?? 0.0);
    final field = _DefaultableOptionalField<double>(
      _storage,
      flagBit,
      value,
      initialValue != null,
    );
    _storage.registerField(field);
    return field;
  }

  @override
  InitialPointer<bool> hasBool([bool initialValue = false]) =>
      _BoolField(_has(1, false, initialValue ? 1 : 0));

  @override
  InitialPointer<int> hasUint1([int initialValue = 0]) =>
      _has(1, false, initialValue);
  @override
  InitialPointer<int> hasInt1([int initialValue = 0]) =>
      _has(1, true, initialValue);
  @override
  InitialPointer<int> hasUint2([int initialValue = 0]) =>
      _has(2, false, initialValue);
  @override
  InitialPointer<int> hasInt2([int initialValue = 0]) =>
      _has(2, true, initialValue);
  @override
  InitialPointer<int> hasUint4([int initialValue = 0]) =>
      _has(4, false, initialValue);
  @override
  InitialPointer<int> hasInt4([int initialValue = 0]) =>
      _has(4, true, initialValue);
  @override
  InitialPointer<int> hasUint8([int initialValue = 0]) =>
      _has(8, false, initialValue);
  @override
  InitialPointer<int> hasInt8([int initialValue = 0]) =>
      _has(8, true, initialValue);
  @override
  InitialPointer<int> hasUint16([int initialValue = 0]) =>
      _has(16, false, initialValue);
  @override
  InitialPointer<int> hasInt16([int initialValue = 0]) =>
      _has(16, true, initialValue);
  @override
  InitialPointer<int> hasUint32([int initialValue = 0]) =>
      _has(32, false, initialValue);
  @override
  InitialPointer<int> hasInt32([int initialValue = 0]) =>
      _has(32, true, initialValue);
  @override
  InitialPointer<int> hasUint64([int initialValue = 0]) =>
      _has(64, false, initialValue);
  @override
  InitialPointer<int> hasInt64([int initialValue = 0]) =>
      _has(64, true, initialValue);

  /// Signed 64-bit, like [hasInt64] and for its reason: `Entity.pack` shifts
  /// the archetype id up into the sign position, so only a signed slot
  /// round-trips every handle unchanged.
  @override
  InitialPointer<Entity> hasEntity([Entity? initialValue]) =>
      _EntityHandleField(_has(64, true, initialValue?.value ?? 0));

  /// Unsigned, and as narrow as the member count allows - see
  /// [_enumIndexWidth].
  @override
  InitialPointer<E> hasEnum<E extends Enum>(List<E> values, [E? initialValue]) {
    // The write stores `Enum.index` and the read is `values[index]`, so the
    // two address the same member only when `values` is the enum's whole
    // list in declaration order. Checked here, at declare time, because a
    // partial list is silent otherwise: it reads back the wrong member.
    assert(
      values.isNotEmpty &&
          values.every(
            (value) =>
                value.index < values.length &&
                identical(values[value.index], value),
          ),
      'hasEnum indexes `values` by Enum.index, so it must be the whole '
      'values list the enum declares.',
    );

    return _EnumField<E>(
      _has(_enumIndexWidth(values.length), false, initialValue?.index ?? 0),
      values,
    );
  }

  @override
  InitialPointer<double> hasFloat32([double initialValue = 0.0]) =>
      _hasFloat(32, initialValue);
  @override
  InitialPointer<double> hasFloat64([double initialValue = 0.0]) =>
      _hasFloat(64, initialValue);

  @override
  InitialPointer<int?> optUint1([int? initialValue]) =>
      _opt(1, false, initialValue);
  @override
  InitialPointer<int?> optInt1([int? initialValue]) =>
      _opt(1, true, initialValue);
  @override
  InitialPointer<int?> optUint2([int? initialValue]) =>
      _opt(2, false, initialValue);
  @override
  InitialPointer<int?> optInt2([int? initialValue]) =>
      _opt(2, true, initialValue);
  @override
  InitialPointer<int?> optUint4([int? initialValue]) =>
      _opt(4, false, initialValue);
  @override
  InitialPointer<int?> optInt4([int? initialValue]) =>
      _opt(4, true, initialValue);
  @override
  InitialPointer<int?> optUint8([int? initialValue]) =>
      _opt(8, false, initialValue);
  @override
  InitialPointer<int?> optInt8([int? initialValue]) =>
      _opt(8, true, initialValue);
  @override
  InitialPointer<int?> optUint16([int? initialValue]) =>
      _opt(16, false, initialValue);
  @override
  InitialPointer<int?> optInt16([int? initialValue]) =>
      _opt(16, true, initialValue);
  @override
  InitialPointer<int?> optUint32([int? initialValue]) =>
      _opt(32, false, initialValue);
  @override
  InitialPointer<int?> optInt32([int? initialValue]) =>
      _opt(32, true, initialValue);
  @override
  InitialPointer<int?> optUint64([int? initialValue]) =>
      _opt(64, false, initialValue);
  @override
  InitialPointer<int?> optInt64([int? initialValue]) =>
      _opt(64, true, initialValue);

  /// Signed 64-bit beside a presence flag, the signedness for [hasEntity]'s
  /// reason.
  @override
  InitialPointer<Entity?> optEntity([Entity? initialValue]) =>
      _OptionalEntityHandleField(_opt(64, true, initialValue?.value));

  @override
  InitialPointer<double?> optFloat32([double? initialValue]) =>
      _optFloat(32, initialValue);
  @override
  InitialPointer<double?> optFloat64([double? initialValue]) =>
      _optFloat(64, initialValue);

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
  /// `hasArray(.uint4, 4)` leaves the cursor at bit 1, so element 0 lands at
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
    List<int> defaults,
  ) {
    final baseBit = _declareElements(length, bitWidth);
    if (bitWidth < 8) {
      return signed
          ? _SubByteIntArrayField(_storage, length, baseBit, bitWidth, defaults)
          : _SubByteUintArrayField(
              _storage,
              length,
              baseBit,
              bitWidth,
              defaults,
            );
    }
    final byte = baseBit >> 3;
    return switch ((bitWidth, signed)) {
      (8, false) => _Uint8ArrayField(_storage, length, byte, defaults),
      (8, true) => _Int8ArrayField(_storage, length, byte, defaults),
      (16, false) => _Uint16ArrayField(_storage, length, byte, defaults),
      (16, true) => _Int16ArrayField(_storage, length, byte, defaults),
      (32, false) => _Uint32ArrayField(_storage, length, byte, defaults),
      (32, true) => _Int32ArrayField(_storage, length, byte, defaults),
      _ => throw ArgumentError('unsupported integer bit width $bitWidth'),
    };
  }

  /// Reserves the elements and registers the field. [defaults] holds one
  /// entry per element already, so both spellings of the initial value meet
  /// here.
  DataArrayPointer<double> _declareFloatArray(
    int length,
    int bitWidth,
    List<double> defaults,
  ) {
    final byte = _declareElements(length, bitWidth) >> 3;
    final field = bitWidth == 32
        ? _Float32ArrayField(_storage, length, byte, defaults)
        : _Float64ArrayField(_storage, length, byte, defaults);
    _storage.registerField(field);
    return field;
  }

  /// One entry per element, from whichever of the two spellings the caller
  /// used: [initialValues] covers the first elements and the rest fall back
  /// to [zero], the element's own unwritten value.
  ///
  /// More values than the array holds is an error, for [_checkArrayLength]'s
  /// reason: it can only be a caller mistake, and each extra one names a slot
  /// that was never reserved.
  List<V> _elementDefaults<V>(int length, List<V> initialValues, V zero) {
    if (initialValues.length > length) {
      throw ArgumentError.value(
        initialValues.length,
        'initialValues',
        'is more values than the array holds ($length)',
      );
    }
    final defaults = List<V>.filled(length, zero);
    defaults.setRange(0, initialValues.length, initialValues);
    return defaults;
  }

  /// The single place [hasArray] and [hasArrayOf] decide what an element
  /// *is*.
  ///
  /// An exhaustive `switch` and not an `is` chain: [DataElement] is sealed,
  /// so a fourth element kind is a compile error here instead of a case that
  /// falls through. The representation case is spelled
  /// `IntRepresentation<IntRepresentable>()`, because a bare
  /// `IntRepresentation()` does not satisfy exhaustiveness against an
  /// unbounded `DataElement<T>`.
  ///
  /// [initials] holds one value per element already. `null` reaches here only
  /// from [hasArray] with no initial value given, and asks for the element's
  /// own zero - which a native width has and a representation does not, so
  /// the representation branch refuses it by name.
  DataArrayPointer<T> _declareArray<T>(
    DataElement<T> element,
    int length,
    List<T>? initials,
  ) {
    switch (element) {
      case IntElement(:final bitWidth, :final signed):
        final defaults = _elementDefaults<int>(
          length,
          (initials as List<int>?) ?? const <int>[],
          0,
        );
        final field = _declareIntArray(length, bitWidth, signed, defaults);
        _storage.registerField(field);
        return field as DataArrayPointer<T>;
      case FloatElement(:final bitWidth):
        final defaults = _elementDefaults<double>(
          length,
          (initials as List<double>?) ?? const <double>[],
          0.0,
        );
        return _declareFloatArray(length, bitWidth, defaults)
            as DataArrayPointer<T>;
      case IntRepresentation<IntRepresentable>():
        final repr = element as IntRepresentation<IntRepresentable>;
        if (initials == null) {
          throw ArgumentError.value(
            null,
            'initialValue',
            'a ${repr.runtimeType} array needs one. The bits an unwritten '
                'element holds are 0, which a representation is under no '
                'obligation to have a value for, so the first read would '
                'throw out of unpack. Pass the value every element starts '
                'at, or declare the column with optArray and let unwritten '
                'elements read null.',
          );
        }
        final bits = _declareIntArray(
          length,
          _checkBitWidth(repr),
          false,
          _elementDefaults<int>(
            length,
            <int>[for (final v in initials) (v as IntRepresentable).pack()],
            0,
          ),
        );
        final field = _PackedArrayField<T>(_storage, length, bits, repr);
        _storage.registerField(field);
        return field;
    }
  }

  @override
  DataArrayPointer<T> hasArray<T>(
    DataElement<T> element,
    int length, [
    T? initialValue,
  ]) {
    _checkArrayLength(length);
    return _declareArray<T>(
      element,
      length,
      initialValue == null ? null : List<T>.filled(length, initialValue),
    );
  }

  @override
  DataArrayPointer<T> hasArrayOf<T>(
    DataElement<T> element,
    int length,
    List<T> initialValues,
  ) {
    _checkArrayLength(length);
    return _declareArray<T>(element, length, initialValues);
  }

  /// The nullable case declares per element - flag, then value - which is
  /// why it cannot share [_declareElements]: the two widths interleave, so
  /// the elements are not evenly spaced. See [_OptionalArrayField].
  @override
  DataArrayPointer<T?> optArray<T>(
    DataElement<T> element,
    int length, [
    T? initialValue,
  ]) {
    _checkArrayLength(length);
    final flagBits = List<int>.filled(length, 0);
    final values = <_Field<T>>[];
    for (var i = 0; i < length; i++) {
      flagBits[i] = _storage.declareFlagBit();
      values.add(_declareElement<T>(element, initialValue));
    }
    final field = _OptionalArrayField<T>(
      _storage,
      length,
      flagBits,
      values,
      initialValue != null,
    );
    _storage.registerField(field);
    return field;
  }

  /// One element of an [optArray], as a scalar field.
  ///
  /// The value bits are don't-care while the element's flag is clear, so an
  /// absent [initialValue] is the element's zero here and a representation
  /// needs no value of its own - which is why this switch has no counterpart
  /// to the refusal in [_declareArray].
  _Field<T> _declareElement<T>(DataElement<T> element, T? initialValue) {
    switch (element) {
      case IntElement(:final bitWidth, :final signed):
        return _declareInt(bitWidth, signed, (initialValue as int?) ?? 0)
            as _Field<T>;
      case FloatElement(:final bitWidth):
        return _declareFloat(bitWidth, (initialValue as double?) ?? 0.0)
            as _Field<T>;
      case IntRepresentation<IntRepresentable>():
        final repr = element as IntRepresentation<IntRepresentable>;
        return _PackedField<T>(
          _storage,
          _declareInt(
            _checkBitWidth(repr),
            false,
            (initialValue as IntRepresentable?)?.pack() ?? 0,
          ),
          repr,
        );
    }
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
    T initialValue,
  ) {
    final bits = _declareInt(_checkBitWidth(repr), false, initialValue.pack());
    final field = _PackedPointerField<T>(_storage, bits, repr);
    _storage.registerField(field);
    return field;
  }

  DataPointer<T?> _optPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    T? initialValue,
  ) {
    // Flag first, then the value - but the flag takes a bit an earlier
    // field's byte-rounding stranded when there is one, so it usually costs
    // the row nothing (see `ArchetypeStorage.declareFlagBit`). The value
    // still comes from the cursor, so its own alignment rule is unchanged.
    final flagBit = _storage.declareFlagBit();
    final bits = _declareInt(
      _checkBitWidth(repr),
      false,
      initialValue?.pack() ?? 0,
    );
    final value = _PackedField<T>(_storage, bits, repr);
    final field = _OptionalField<T>(
      _storage,
      flagBit,
      value,
      initialValue != null,
    );
    _storage.registerField(field);
    return field;
  }

  @override
  PackedPointer<T> hasPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    T initialValue,
  ) => _hasPacked(repr, initialValue);
  @override
  DataPointer<T?> optPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr, [
    T? initialValue,
  ]) => _optPacked(repr, initialValue);
  @override
  DataPointer<T> hasHeapObject<T>(T Function() initialValue) {
    final byte = _storage.declareField(32) >> 3;
    final field = _HeapObjectField<T>(_storage, byte, initialValue);
    _storage.registerField(field);
    return field;
  }

  @override
  DataPointer<T?> optHeapObject<T>() {
    final flagBit = _storage.declareFlagBit();
    final byte = _storage.declareField(32) >> 3;
    // No default factory: the wrapper's has-bit defaults to clear, so
    // `_OptionalField.writeInitialValue` never asks the value field for one and
    // a fresh entity reads `null`.
    final value = _HeapObjectField<T>(_storage, byte, null);
    final field = _OptionalField<T>(_storage, flagBit, value, false);
    _storage.registerField(field);
    // The wrapper carries the default; the value field carries the registry
    // slot. Teardown has to reach the latter - see `registerHeapField`.
    _storage.registerHeapField(value);
    return field;
  }
}

/// Collects the query-signature bits for one archetype while its prefab is
/// being constructed, and refuses a pair of components that declared they
/// cannot share one.
///
/// Open for the length of the constructor call, which is what puts every
/// `Component.type` field initialiser inside it. [declareSelf] and
/// [checkConflicts] run after, from `SceneDescriptor.has`, and are the two
/// things that need the built object.
final class ArchetypeComponentDescriptor implements ComponentRegistrar {
  ArchetypeComponentDescriptor(this._storage);

  final ArchetypeStorage _storage;

  /// Each declared conflict, as the component that declared it and the
  /// sentence it gave. Keyed by the type refused, so [checkConflicts] can
  /// name both halves.
  final Map<Type, (Type, String)> _refused = <Type, (Type, String)>{};

  @override
  int declareComponent(Type type, Map<Type, String> conflictsWith) {
    final bit = ComponentTypeRegistry.bitFor(type);
    _storage.componentSignature |= bit;
    for (final MapEntry(key: other, value: reason) in conflictsWith.entries) {
      _refused[other] = (type, reason);
    }
    return bit;
  }

  /// ORs in the prefab's own type.
  ///
  /// The framework's line, not the user's: a prefab's type is `runtimeType`,
  /// which a field initialiser cannot reach and which only the running
  /// program knows. It is the one bit in a signature that stays a run-time
  /// assignment however much of the rest is generated.
  void declareSelf(Type prefabType) {
    _storage.componentSignature |= ComponentTypeRegistry.bitFor(prefabType);
  }

  /// Fails the registration if the finished signature carries both halves of
  /// a declared conflict.
  ///
  /// After construction rather than inside [declareComponent], because mixin
  /// field initialisers run in reverse `with` order: at the moment
  /// `ScreenTransform2D` declares that it refuses `WorldTransform2D`, that
  /// bit may not be in the signature yet. Every declaration first, one check
  /// afterwards.
  ///
  /// An `assert`, so it costs nothing in release, and it guards a
  /// combination that is refused rather than corrected - a game reaching
  /// release with one has been drawing the wrong picture the whole way.
  void checkConflicts(Type prefabType) {
    assert(() {
      for (final MapEntry(key: other, value: (declarer, reason))
          in _refused.entries) {
        final otherBit = ComponentTypeRegistry.declaredBitFor(other);
        if (_storage.componentSignature & otherBit == 0) {
          continue;
        }
        throw StateError(
          '$prefabType mixes in both $declarer and $other. $reason',
        );
      }
      return true;
    }());
  }
}
