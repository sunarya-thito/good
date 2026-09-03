import 'dart:ffi';

import 'package:good/src/archetype.dart';
import 'package:good/src/camera_view.dart';
import 'package:good/src/data.dart';
import 'package:good/src/heap_object.dart';
import 'package:good/src/scannable.dart';
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

/// A column a declaration produced, before it has any row space.
///
/// `final speed = Field.float64(3)` runs in a field initialiser, where there
/// is no archetype, no scene and no allocation cursor - so it builds the
/// column object and stops. [realize] is the other half: it runs once the
/// whole set of a class's declarations is known, in the order they were
/// declared, and is where the bits are reserved and the column is bound to
/// the storage that holds them.
///
/// Two things the engine could not do while a declaration reserved its row
/// space on the spot fall out of the split, and both were breakages until it
/// existed. A `DataArrayPointer`'s `length` can move, because nothing has
/// been reserved for it yet - see [DataArrayPointer.length]. And
/// `optCameraView` can name a table that belongs to the scene, because
/// `ArchetypeStorage.scene` is reachable here and is not reachable from a
/// field initialiser - see [_CameraViewField].
///
/// Nothing here is ambient. A declaration reaches no descriptor while it is
/// being made, so there is no stack to push, nothing to pop on the way out,
/// and no way for a value produced in one place to land on whichever owner
/// happened to be under construction somewhere else.
abstract interface class _Declared {
  /// Reserves this column's row space on [storage], binds it, and registers
  /// whatever stamps a fresh row's initial value.
  void realize(ArchetypeStorage storage);
}

abstract base class _Field<T> extends DataPointer<T>
    implements ArchetypeField, _Declared {
  /// The storage this column was given at [realize].
  ///
  /// `late final` rather than a plain field, and it is the only sentinel on
  /// the access path. Two things come out of it and neither has a cheaper
  /// spelling: realizing a column twice throws on the reassignment instead of
  /// silently re-pointing it at a second archetype, and an access to a column
  /// nothing ever realized throws naming the field instead of reading
  /// whatever sits at byte offset 0.
  ///
  /// Every accessor resolves its row through [_read] or [_write] before it
  /// adds an offset, so this one check covers the offsets too - which is why
  /// each field's `_byte`, `_flagByte` and the rest stay plain mutable ints
  /// and cost the read path nothing of their own.
  late final ArchetypeStorage _storage;

  /// Whether [realize] has run.
  ///
  /// The guards ask this rather than reading [_storage], which does not exist
  /// before then: a default moved from a `describeStruct` body is set while
  /// every column is still unrealized, and `_storage.isSealed` would throw
  /// there instead of answering.
  bool _realized = false;

  @override
  void realize(ArchetypeStorage storage) {
    attach(storage);
    storage.registerField(this);
  }

  /// [realize] without the registration - what a wrapper calls on the column
  /// it owns, so the wrapper's own [writeInitialValue] stays the only thing
  /// that stamps the row.
  void attach(ArchetypeStorage storage) {
    _storage = storage;
    _realized = true;
    _reserve(storage);
  }

  /// Reserves this column's bits. [attach] has already set [_storage], so an
  /// implementation only has to record where its bits landed.
  void _reserve(ArchetypeStorage storage);

  /// Rejects a default set after [ArchetypeStorage.seal] has already stamped
  /// the prototype row.
  ///
  /// The message names both spellings on purpose. `near.initialValue = 10`
  /// and `near[entity] = 10` are one keystroke apart and mean entirely
  /// different things, and a caller who reaches here has almost certainly
  /// typed the first while meaning the second.
  ///
  /// An unrealized column always passes: nothing has been reserved for it and
  /// nothing has been stamped from it, which is exactly the window a prefab's
  /// `describeStruct` body moves a default in.
  void _requireUnsealed() {
    if (!_realized || !_storage.isSealed) return;
    throw StateError(
      'A column default was set after ${_storage.prefab.runtimeType}\'s '
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
  _ValueField(this._default);

  /// What [writeInitialValue] stamps. Held here rather than once per width so the
  /// setter and its guard are written once, and so [_DefaultableOptionalField]
  /// can reach the value half of a nullable column's default.
  T _default;

  @override
  T get initialValue => _default;

  @override
  set initialValue(T newValue) {
    _requireUnsealed();
    _default = newValue;
  }
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
class _BoolField extends InitialPointer<bool> implements _Declared {
  const _BoolField(this._raw);

  final _ValueField<int> _raw;

  /// The wrapped column is the one with bits and the one that stamps the
  /// row, so realizing this realizes that and adds nothing of its own -
  /// exactly as every other member here delegates.
  @override
  void realize(ArchetypeStorage storage) => _raw.realize(storage);

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
class _EntityHandleField extends InitialPointer<Entity>
    implements _Declared {
  const _EntityHandleField(this._raw);

  final _ValueField<int> _raw;

  @override
  void realize(ArchetypeStorage storage) => _raw.realize(storage);

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
class _OptionalEntityHandleField extends InitialPointer<Entity?>
    implements _Declared {
  const _OptionalEntityHandleField(this._raw);

  final _DefaultableOptionalField<int> _raw;

  @override
  void realize(ArchetypeStorage storage) => _raw.realize(storage);

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
class _EnumField<E extends Enum> extends InitialPointer<E>
    implements _Declared {
  const _EnumField(this._raw, this._values);

  final _ValueField<int> _raw;
  final List<E> _values;

  @override
  void realize(ArchetypeStorage storage) => _raw.realize(storage);

  @override
  E operator [](Entity entity) => _values[_raw[entity]];

  @override
  void operator []=(Entity entity, E newValue) => _raw[entity] = newValue.index;

  @override
  E get initialValue => _values[_raw.initialValue];

  @override
  set initialValue(E newValue) => _raw.initialValue = newValue.index;
}

// --- sub-byte fields ---------------------------------------------------
//
// 1/2/4-bit fields never span a byte (see ArchetypeStorage.declareField),
// so both directions are a single-byte access: read is load/shift/mask,
// write is a load/mask/or/store read-modify-write. `_byteMask` is the
// field's bits in place; `_valueMask` is them at bit 0.

base class _SubByteUintField extends _ValueField<int> {
  _SubByteUintField(int bitWidth, super.initialValue)
    : _bitWidth = bitWidth,
      _valueMask = (1 << bitWidth) - 1,
      _signBit = 1 << (bitWidth - 1),
      _range = 1 << bitWidth;

  /// A constructor argument here and a constant of the class everywhere
  /// else, because this is the one family whose width is not fixed by the
  /// class: 1, 2 and 4 bits share every line of the access path.
  final int _bitWidth;

  final int _valueMask;

  int _byte = 0;
  int _shift = 0;
  int _byteMask = 0;

  // Only [_SubByteIntField] reads these; they live here so the signed
  // variant can be a plain super-parameter subclass instead of restating
  // the whole constructor to get at `_bitWidth`.
  final int _signBit;
  final int _range;

  @override
  void _reserve(ArchetypeStorage storage) {
    final bitOffset = storage.declareField(_bitWidth);
    _byte = bitOffset >> 3;
    _shift = bitOffset & 7;
    _byteMask = _valueMask << _shift;
  }

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
  _SubByteIntField(super.bitWidth, super.initialValue);

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

/// A column that occupies one whole run of bytes, reserved at [realize] and
/// addressed from the byte it starts at.
///
/// The width is a constant of the class and not a constructor argument:
/// [_Uint16Field] is sixteen bits and could never be anything else, so
/// holding it as a getter is what lets every width below share one
/// [_reserve] instead of repeating the same two lines ten times. The
/// sub-byte family is the exception and says why on its own `_bitWidth`.
abstract base class _ByteAlignedField<T> extends _ValueField<T> {
  _ByteAlignedField(super.initialValue);

  /// Byte offset of this column in the row. A plain field and not `late`:
  /// see [_Field._storage] for the one sentinel that covers it.
  int _byte = 0;

  int get _bitWidth;

  @override
  void _reserve(ArchetypeStorage storage) {
    _byte = storage.declareField(_bitWidth) >> 3;
  }
}

final class _Uint8Field extends _ByteAlignedField<int> {
  _Uint8Field(super.initialValue);

  @override
  int get _bitWidth => 8;

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

final class _Int8Field extends _ByteAlignedField<int> {
  _Int8Field(super.initialValue);

  @override
  int get _bitWidth => 8;

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

final class _Uint16Field extends _ByteAlignedField<int> {
  _Uint16Field(super.initialValue);

  @override
  int get _bitWidth => 16;

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

final class _Int16Field extends _ByteAlignedField<int> {
  _Int16Field(super.initialValue);

  @override
  int get _bitWidth => 16;

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

final class _Uint32Field extends _ByteAlignedField<int> {
  _Uint32Field(super.initialValue);

  @override
  int get _bitWidth => 32;

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

final class _Int32Field extends _ByteAlignedField<int> {
  _Int32Field(super.initialValue);

  @override
  int get _bitWidth => 32;

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
final class _Uint64Field extends _ByteAlignedField<int> {
  _Uint64Field(super.initialValue);

  @override
  int get _bitWidth => 64;

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

final class _Int64Field extends _ByteAlignedField<int> {
  _Int64Field(super.initialValue);

  @override
  int get _bitWidth => 64;

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
final class _Float32Field extends _ByteAlignedField<double> {
  _Float32Field(super.initialValue);

  @override
  int get _bitWidth => 32;

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

final class _Float64Field extends _ByteAlignedField<double> {
  _Float64Field(super.initialValue);

  @override
  int get _bitWidth => 64;

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
// free because `_intColumn` already built them.

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
abstract base class _PackedField<T> extends _Field<T> {
  _PackedField(this._bits);

  /// The integer field holding the packed bits. Declared and owned here, and
  /// deliberately **not** registered with the storage itself - this field's
  /// own [writeInitialValue] drives it, so registering both would stamp the
  /// initial value twice. Which is also why [_reserve] binds it rather than
  /// realizing it.
  final _Field<int> _bits;

  /// The representation the stored ints mean something against.
  ///
  /// A getter and not a stored value, because one column in the engine does
  /// not have one at the declare site. `optCameraView` is packed against a
  /// table the scene owns, and a field initialiser cannot reach a scene -
  /// see [_CameraViewField]. Every other packed column names its
  /// representation where the field is written, which is what
  /// [_DeclaredPackedField] holds.
  IntRepresentation<IntRepresentable> get _repr;

  @override
  void _reserve(ArchetypeStorage storage) => _bits.attach(storage);

  @override
  T operator [](Entity entity) => _repr.unpack(_bits[entity]) as T;

  @override
  void operator []=(Entity entity, T newValue) =>
      _bits[entity] = (newValue as IntRepresentable).pack();

  @override
  void writeInitialValue(int row) => _bits.writeInitialValue(row);
}

/// [_PackedField] against the representation the declaration named - which
/// is every packed column except the camera view.
base class _DeclaredPackedField<T> extends _PackedField<T> {
  _DeclaredPackedField(super.bits, this._declaredRepr);

  final IntRepresentation<IntRepresentable> _declaredRepr;

  @override
  IntRepresentation<IntRepresentable> get _repr => _declaredRepr;
}

/// `optCameraView`'s value half: a packed column whose representation is the
/// table the registering scene owns.
///
/// It reads the table off the storage instead of holding one, and that is the
/// whole of why the column can be declared from a field initialiser. A
/// `CameraViewTable` is the one representation in this engine a declaration
/// cannot be handed - there is one per game, it is reached through the scene,
/// and a field initialiser has no scene. `ArchetypeStorage.scene` does have
/// one, and [_Field.realize] runs where that is reachable.
///
/// Nothing about the table sizes the column: the width is
/// `CameraViewTable.viewBitWidth`, a constant, so the bits are reserved from
/// the declaration exactly as every other packed column's are. Only a *read*
/// consults the table, which is why resolving it later costs nothing.
final class _CameraViewField extends _PackedField<CameraView> {
  _CameraViewField(super.bits);

  @override
  IntRepresentation<IntRepresentable> get _repr => _storage.scene.cameraViews;
}

/// [_PackedField] with the bound back on, which is what lets it be the
/// [PackedPointer] `hasPacked` hands out. `packedAt` lives here and not on
/// the base because only the scalar declaration exposes it - an array
/// element is read through `DataArrayPointer`, which has no such escape
/// hatch.
final class _PackedPointerField<T extends IntRepresentable>
    extends _DeclaredPackedField<T>
    implements PackedPointer<T> {
  _PackedPointerField(super.bits, super.repr);

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
  _HeapObjectField(this._initialFactory);

  int _byte = 0;

  @override
  void _reserve(ArchetypeStorage storage) {
    _byte = storage.declareField(32) >> 3;
  }

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
  _OptionalField(this._value, this._initialPresent);

  int _flagByte = 0;
  int _flagMask = 0;
  final _Field<T> _value;

  @override
  void _reserve(ArchetypeStorage storage) {
    // Flag first, then the value - but the flag takes a bit an earlier
    // field's byte-rounding stranded when there is one, so it usually costs
    // the row nothing (see `ArchetypeStorage.declareFlagBit`). The value
    // still comes from the cursor, so its own alignment rule is unchanged.
    final flagBit = storage.declareFlagBit();
    _flagByte = flagBit >> 3;
    _flagMask = 1 << (flagBit & 7);
    // Bound and not realized: this wrapper's has-bit decides whether the
    // value's default is stamped at all, so the value must not be registered
    // as a field of its own.
    _value.attach(storage);
  }

  /// Registers the value half for teardown when it owns something outside
  /// the row.
  ///
  /// `optHeapObject` is the only case, and it needs both halves declared
  /// through two calls: what stamps the row is this wrapper, and what holds
  /// the registry slot is the heap field inside it. See
  /// `ArchetypeStorage.registerHeapField`.
  @override
  void realize(ArchetypeStorage storage) {
    super.realize(storage);
    final value = _value;
    if (value is HeapArchetypeField) {
      storage.registerHeapField(value as HeapArchetypeField);
    }
  }

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
    this._defaultableValue,
    // ignore: avoid_positional_boolean_parameters
    bool defaultPresent,
  ) : super(_defaultableValue, defaultPresent);

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
    _requireUnsealed();
    _initialPresent = newValue != null;
    if (newValue != null) _defaultableValue._default = newValue;
  }
}

// --- array fields ------------------------------------------------------
//
// An array field is `length` consecutive scalar fields declared back to
// back, addressed by arithmetic instead of by storing `length` offsets.
// `_ArrayField._reserveElements` reserves them by calling
// `ArchetypeStorage.declareField(bitWidth)` `length` times in a row and
// keeping only the first offset; element `i` then sits at exactly
// `baseBit + i * bitWidth`, with no gaps, in every supported case:
//
//  * Sub-byte widths (1/2/4) all divide 8, so once the array's base is a
//    multiple of the element width, declareField's "jump to the next byte if
//    this one can't fit the field" rule never fires mid-array - a byte
//    boundary always coincides with an element boundary. `_reserveElements`
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
    implements DataArrayPointer<T>, ArchetypeField, _Declared {
  _ArrayField(this._length);

  /// See [_Field._storage]: the same late-bound storage, for the same two
  /// reasons, on a root that is deliberately not a `_Field`.
  late final ArchetypeStorage _storage;

  /// Whether [realize] has run, which is what the [length] setter asks.
  bool _realized = false;

  int _length;

  @override
  int get length => _length;

  /// Settable until this column is realized.
  ///
  /// A length sizes the column, and while a declaration reserved its row
  /// space on the spot there was nothing left to move: the elements were
  /// already taken from the cursor and the next column sat immediately behind
  /// them. Reserving after the whole set of declarations is collected is what
  /// makes this implementable at all - nothing has been reserved when a
  /// prefab writes `textCodeUnits.length = 8`, so shortening the array simply
  /// reserves eight slots instead of thirty-two.
  ///
  /// After [realize] it throws, and says which window the caller missed.
  /// Answering with a silent no-op is the failure this engine keeps paying
  /// for elsewhere: the array would be the length the component chose and
  /// every read would agree with itself.
  @override
  set length(int newLength) {
    if (_realized) {
      throw StateError(
        'An array column\'s length was set after its row space had been '
        'reserved, so it can no longer take effect. A length decides how '
        'many elements the row holds, and the elements are reserved once - '
        'after the declaring class\'s whole set of declarations is known, and '
        'before the archetype is sealed.\n'
        '  textCodeUnits.length = 8;   // declare time - a prefab\'s '
        'describeStruct\n'
        'Anything later is resizing a row that has already been laid out.',
      );
    }
    _checkArrayLength(newLength);
    _length = newLength;
  }

  @override
  void realize(ArchetypeStorage storage) {
    attach(storage);
    storage.registerField(this);
  }

  /// [realize] without the registration - see [_Field.attach].
  void attach(ArchetypeStorage storage) {
    _storage = storage;
    _realized = true;
    _reserve(storage);
  }

  void _reserve(ArchetypeStorage storage);

  /// Reserves [length] consecutive [bitWidth]-bit elements and returns the
  /// *first* one's bit offset - the whole array's base. The rest is
  /// arithmetic; see the packing note above for why no gaps can appear
  /// between the elements.
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
  int _reserveElements(ArchetypeStorage storage, int bitWidth) {
    if (bitWidth < 8) {
      while (storage.bitLength % bitWidth != 0) {
        storage.declareField(1);
      }
    }
    final baseBit = storage.declareField(bitWidth);
    for (var i = 1; i < length; i++) {
      storage.declareField(bitWidth);
    }
    return baseBit;
  }

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

/// An array of a native width, holding whatever the declaration said every
/// element starts at.
///
/// The two spellings are kept apart until [_reserve] rather than expanded at
/// the declaration, and that is what a movable [length] costs: `hasArray`
/// broadcasts one value to however many elements the array turns out to have,
/// so expanding it while the count can still change fills the wrong number of
/// slots.
abstract base class _NativeArrayField<T> extends _ArrayField<T> {
  _NativeArrayField(super.length, this._broadcast, this._perElement);

  /// The one value every element starts at, from `hasArray`. `null` asks for
  /// [_zero].
  final T? _broadcast;

  /// One value per element, from `hasArrayOf`, covering the first elements
  /// and no more than [length] of them.
  final List<T>? _perElement;

  /// One entry per element, built at [_reserve] and read once at seal.
  List<T> _defaults = <T>[];

  /// The element's own unwritten value - `0` or `0.0`.
  T get _zero;

  /// Records where this array's bits landed. Called after [_defaults] is
  /// built.
  void _reserveBits(ArchetypeStorage storage);

  @override
  void _reserve(ArchetypeStorage storage) {
    final perElement = _perElement;
    if (perElement == null) {
      _defaults = List<T>.filled(length, _broadcast ?? _zero);
    } else {
      // More values than the array holds can only be a caller mistake, and
      // each extra one names a slot that was never reserved. Checked here
      // and not at the declaration because a prefab may have shortened the
      // array since, and this is the first moment the count is final.
      if (perElement.length > length) {
        throw ArgumentError.value(
          perElement.length,
          'initialValues',
          'is more values than the array holds ($length)',
        );
      }
      _defaults = List<T>.filled(length, _zero)
        ..setRange(0, perElement.length, perElement);
    }
    _reserveBits(storage);
  }
}

/// An array whose elements are a whole number of bytes each, addressed from
/// the byte the array starts at - [_ByteAlignedField]'s shape, one element
/// stride out.
abstract base class _ByteAlignedArrayField<T> extends _NativeArrayField<T> {
  _ByteAlignedArrayField(super.length, super.broadcast, super.perElement);

  int _baseByte = 0;

  int get _bitWidth;

  @override
  void _reserveBits(ArchetypeStorage storage) {
    _baseByte = _reserveElements(storage, _bitWidth) >> 3;
  }
}

/// Sub-byte (1/2/4-bit) unsigned element array. Element `i` never straddles
/// a byte - see the packing note above - so each access stays a single-byte
/// load/shift/mask, exactly like [_SubByteUintField].
base class _SubByteUintArrayField extends _NativeArrayField<int> {
  _SubByteUintArrayField(
    int bitWidth,
    super.length,
    super.broadcast,
    super.perElement,
  ) : _bitWidth = bitWidth,
      _valueMask = (1 << bitWidth) - 1,
      _signBit = 1 << (bitWidth - 1),
      _range = 1 << bitWidth;

  final int _bitWidth;
  final int _valueMask;

  int _baseBit = 0;

  @override
  int get _zero => 0;

  @override
  void _reserveBits(ArchetypeStorage storage) {
    _baseBit = _reserveElements(storage, _bitWidth);
  }

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
    super.bitWidth,
    super.length,
    super.broadcast,
    super.perElement,
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

final class _Uint8ArrayField extends _ByteAlignedArrayField<int> {
  _Uint8ArrayField(super.length, super.broadcast, super.perElement);

  @override
  int get _zero => 0;

  @override
  int get _bitWidth => 8;

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

final class _Int8ArrayField extends _ByteAlignedArrayField<int> {
  _Int8ArrayField(super.length, super.broadcast, super.perElement);

  @override
  int get _zero => 0;

  @override
  int get _bitWidth => 8;

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

final class _Uint16ArrayField extends _ByteAlignedArrayField<int> {
  _Uint16ArrayField(super.length, super.broadcast, super.perElement);

  @override
  int get _zero => 0;

  @override
  int get _bitWidth => 16;

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

final class _Int16ArrayField extends _ByteAlignedArrayField<int> {
  _Int16ArrayField(super.length, super.broadcast, super.perElement);

  @override
  int get _zero => 0;

  @override
  int get _bitWidth => 16;

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

final class _Uint32ArrayField extends _ByteAlignedArrayField<int> {
  _Uint32ArrayField(super.length, super.broadcast, super.perElement);

  @override
  int get _zero => 0;

  @override
  int get _bitWidth => 32;

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

final class _Int32ArrayField extends _ByteAlignedArrayField<int> {
  _Int32ArrayField(super.length, super.broadcast, super.perElement);

  @override
  int get _zero => 0;

  @override
  int get _bitWidth => 32;

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

final class _Float32ArrayField extends _ByteAlignedArrayField<double> {
  _Float32ArrayField(super.length, super.broadcast, super.perElement);

  @override
  double get _zero => 0.0;

  @override
  int get _bitWidth => 32;

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

final class _Float64ArrayField extends _ByteAlignedArrayField<double> {
  _Float64ArrayField(super.length, super.broadcast, super.perElement);

  @override
  double get _zero => 0.0;

  @override
  int get _bitWidth => 64;

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
  _PackedArrayField(_ArrayField<int> bits, this._repr)
    : _bits = bits,
      super(bits.length);

  final _ArrayField<int> _bits;
  final IntRepresentation<IntRepresentable> _repr;

  /// Both halves delegated, so the two can never disagree about how many
  /// elements there are: the integer array underneath is what reserves them,
  /// and a length moved on this one has to reach it.
  @override
  int get length => _bits.length;

  @override
  set length(int newLength) => _bits.length = newLength;

  @override
  void _reserve(ArchetypeStorage storage) => _bits.attach(storage);

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
  _OptionalArrayField(super.length, this._element, this._initialValue);

  /// What one element holds. Kept rather than expanded at the declaration,
  /// because the per-element fields below cannot be built before the count
  /// is final - see [DataArrayPointer.length].
  final DataElement<T> _element;

  final T? _initialValue;

  /// Bit offset of element `i`'s has-flag, built at [_reserve].
  List<int> _flagBits = const <int>[];

  /// Element `i`'s value accessor. Attached through this wrapper and never
  /// registered on their own, so the flag decides whether an element's value
  /// default gets stamped at all.
  List<_Field<T>> _values = <_Field<T>>[];

  bool get _initialPresent => _initialValue != null;

  /// The nullable case reserves per element - flag, then value - which is why
  /// it cannot share [_reserveElements]: the two widths interleave, so the
  /// elements are not evenly spaced.
  @override
  void _reserve(ArchetypeStorage storage) {
    _flagBits = List<int>.filled(length, 0);
    _values = <_Field<T>>[];
    for (var i = 0; i < length; i++) {
      _flagBits[i] = storage.declareFlagBit();
      final value = _elementColumn<T>(_element, _initialValue);
      value.attach(storage);
      _values.add(value);
    }
  }

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

// ---------------------------------------------------------------------------
// Declaring a column
// ---------------------------------------------------------------------------
//
// Everything from here to `_ColumnDescriptor` builds a column and reserves
// nothing. A declaration runs in a field initialiser, where there is no
// archetype and no allocation cursor to take bits from, so the row space is
// taken afterwards - see [_Declared].

/// A zero- or negative-length array is rejected rather than quietly accepted:
/// every index into it would be out of range, so it can only be a caller
/// mistake, and catching it where the length is written beats a `RangeError`
/// out of every access at runtime.
void _checkArrayLength(int length) {
  if (length < 1) {
    throw ArgumentError.value(length, 'length', 'must be at least 1');
  }
}

/// Rejects a width the row cannot hold, before it becomes silent truncation.
///
/// A representation's width is a declare-time constant, so this fires once per
/// field at bring-up and never on a hot path.
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

/// The integer column of [bitWidth] bits, unreserved.
///
/// One `switch` and no second table of widths: `_ByteAlignedField` carries
/// each width as a constant of its own class, so adding a rung is a class and
/// a case, not a third place to keep in step.
_ValueField<int> _intColumn(int bitWidth, bool signed, int initialValue) {
  if (bitWidth < 8) {
    return signed
        ? _SubByteIntField(bitWidth, initialValue)
        : _SubByteUintField(bitWidth, initialValue);
  }
  return switch ((bitWidth, signed)) {
    (8, false) => _Uint8Field(initialValue),
    (8, true) => _Int8Field(initialValue),
    (16, false) => _Uint16Field(initialValue),
    (16, true) => _Int16Field(initialValue),
    (32, false) => _Uint32Field(initialValue),
    (32, true) => _Int32Field(initialValue),
    (64, false) => _Uint64Field(initialValue),
    (64, true) => _Int64Field(initialValue),
    _ => throw ArgumentError('unsupported integer bit width $bitWidth'),
  };
}

_ValueField<double> _floatColumn(int bitWidth, double initialValue) =>
    bitWidth == 32
    ? _Float32Field(initialValue)
    : _Float64Field(initialValue);

/// [_intColumn] behind a presence flag, so "no value" is a state of its own.
_DefaultableOptionalField<int> _optIntColumn(
  int bitWidth,
  bool signed,
  int? initialValue,
) => _DefaultableOptionalField<int>(
  _intColumn(bitWidth, signed, initialValue ?? 0),
  initialValue != null,
);

_DefaultableOptionalField<double> _optFloatColumn(
  int bitWidth,
  double? initialValue,
) => _DefaultableOptionalField<double>(
  _floatColumn(bitWidth, initialValue ?? 0.0),
  initialValue != null,
);

_NativeArrayField<int> _intArrayColumn(
  int length,
  int bitWidth,
  bool signed,
  int? broadcast,
  List<int>? perElement,
) {
  if (bitWidth < 8) {
    return signed
        ? _SubByteIntArrayField(bitWidth, length, broadcast, perElement)
        : _SubByteUintArrayField(bitWidth, length, broadcast, perElement);
  }
  return switch ((bitWidth, signed)) {
    (8, false) => _Uint8ArrayField(length, broadcast, perElement),
    (8, true) => _Int8ArrayField(length, broadcast, perElement),
    (16, false) => _Uint16ArrayField(length, broadcast, perElement),
    (16, true) => _Int16ArrayField(length, broadcast, perElement),
    (32, false) => _Uint32ArrayField(length, broadcast, perElement),
    (32, true) => _Int32ArrayField(length, broadcast, perElement),
    _ => throw ArgumentError('unsupported integer bit width $bitWidth'),
  };
}

_NativeArrayField<double> _floatArrayColumn(
  int length,
  int bitWidth,
  double? broadcast,
  List<double>? perElement,
) => bitWidth == 32
    ? _Float32ArrayField(length, broadcast, perElement)
    : _Float64ArrayField(length, broadcast, perElement);

/// The single place `hasArray`, `hasArrayOf` and `optArray`'s element decide
/// what an element *is*.
///
/// An exhaustive `switch` and not an `is` chain: [DataElement] is sealed, so a
/// fourth element kind is a compile error here instead of a case that falls
/// through. The representation case is spelled
/// `IntRepresentation<IntRepresentable>()`, because a bare
/// `IntRepresentation()` does not satisfy exhaustiveness against an unbounded
/// `DataElement<T>`.
///
/// [broadcast] is one value for every element and [perElement] is one each;
/// both `null` asks for the element's own zero - which a native width has and
/// a representation does not, so the representation branch refuses it by name.
_ArrayField<T> _arrayColumn<T>(
  DataElement<T> element,
  int length,
  T? broadcast,
  List<T>? perElement,
) {
  _checkArrayLength(length);
  switch (element) {
    case IntElement(:final bitWidth, :final signed):
      return _intArrayColumn(
            length,
            bitWidth,
            signed,
            broadcast as int?,
            perElement as List<int>?,
          )
          as _ArrayField<T>;
    case FloatElement(:final bitWidth):
      return _floatArrayColumn(
            length,
            bitWidth,
            broadcast as double?,
            perElement as List<double>?,
          )
          as _ArrayField<T>;
    case IntRepresentation<IntRepresentable>():
      final repr = element as IntRepresentation<IntRepresentable>;
      if (broadcast == null && perElement == null) {
        throw ArgumentError.value(
          null,
          'initialValue',
          'a ${repr.runtimeType} array needs one. The bits an unwritten '
              'element holds are 0, which a representation is under no '
              'obligation to have a value for, so the first read would throw '
              'out of unpack. Pass the value every element starts at, or '
              'declare the column with optArray and let unwritten elements '
              'read null.',
        );
      }
      return _PackedArrayField<T>(
        _intArrayColumn(
          length,
          _checkBitWidth(repr),
          false,
          (broadcast as IntRepresentable?)?.pack(),
          perElement == null
              ? null
              : <int>[
                  for (final value in perElement)
                    (value as IntRepresentable).pack(),
                ],
        ),
        repr,
      );
  }
}

/// One element of an `optArray`, as a scalar column.
///
/// The value bits are don't-care while the element's flag is clear, so an
/// absent [initialValue] is the element's zero here and a representation needs
/// no value of its own - which is why this switch has no counterpart to the
/// refusal in [_arrayColumn].
_Field<T> _elementColumn<T>(DataElement<T> element, T? initialValue) {
  switch (element) {
    case IntElement(:final bitWidth, :final signed):
      return _intColumn(bitWidth, signed, (initialValue as int?) ?? 0)
          as _Field<T>;
    case FloatElement(:final bitWidth):
      return _floatColumn(bitWidth, (initialValue as double?) ?? 0.0)
          as _Field<T>;
    case IntRepresentation<IntRepresentable>():
      final repr = element as IntRepresentation<IntRepresentable>;
      return _DeclaredPackedField<T>(
        _intColumn(
          _checkBitWidth(repr),
          false,
          (initialValue as IntRepresentable?)?.pack() ?? 0,
        ),
        repr,
      );
  }
}

/// The narrowest unsigned width that can index [count] enum members.
///
/// Widths are in *bits*, so a three-member enum answers 2 - the two bits
/// callers spent on `hasUint2` when they packed the index by hand.
///
/// The ladder stops at 32: Dart evaluates `1 << 64` to 0, so a 64-bit rung
/// could not state its own bound. An enum big enough to need one cannot be
/// written down, so the throw is what an out-of-range [count] hits rather than
/// silently truncating to a width that cannot hold it.
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

/// Every `DataDescriptor` method, answered by building the column and handing
/// it to [_declared].
///
/// The two descriptors below differ by exactly that one step - a `Field.*`
/// static keeps nothing, and a describe pass records what it declared so the
/// archetype can realize it with everything else - so the vocabulary is
/// written once here and each of them says only what [_declared] does with a
/// column.
abstract base class _ColumnDescriptor implements DataDescriptor {
  const _ColumnDescriptor();

  /// Called with each column as it is built, and returns it - which is what
  /// keeps every method below one expression.
  D _declared<D extends ScannableField>(D column);

  @override
  InitialPointer<bool> hasBool([bool initialValue = false]) =>
      _declared(_BoolField(_intColumn(1, false, initialValue ? 1 : 0)));

  @override
  InitialPointer<int> hasUint1([int initialValue = 0]) =>
      _declared(_intColumn(1, false, initialValue));
  @override
  InitialPointer<int> hasInt1([int initialValue = 0]) =>
      _declared(_intColumn(1, true, initialValue));
  @override
  InitialPointer<int> hasUint2([int initialValue = 0]) =>
      _declared(_intColumn(2, false, initialValue));
  @override
  InitialPointer<int> hasInt2([int initialValue = 0]) =>
      _declared(_intColumn(2, true, initialValue));
  @override
  InitialPointer<int> hasUint4([int initialValue = 0]) =>
      _declared(_intColumn(4, false, initialValue));
  @override
  InitialPointer<int> hasInt4([int initialValue = 0]) =>
      _declared(_intColumn(4, true, initialValue));
  @override
  InitialPointer<int> hasUint8([int initialValue = 0]) =>
      _declared(_intColumn(8, false, initialValue));
  @override
  InitialPointer<int> hasInt8([int initialValue = 0]) =>
      _declared(_intColumn(8, true, initialValue));
  @override
  InitialPointer<int> hasUint16([int initialValue = 0]) =>
      _declared(_intColumn(16, false, initialValue));
  @override
  InitialPointer<int> hasInt16([int initialValue = 0]) =>
      _declared(_intColumn(16, true, initialValue));
  @override
  InitialPointer<int> hasUint32([int initialValue = 0]) =>
      _declared(_intColumn(32, false, initialValue));
  @override
  InitialPointer<int> hasInt32([int initialValue = 0]) =>
      _declared(_intColumn(32, true, initialValue));
  @override
  InitialPointer<int> hasUint64([int initialValue = 0]) =>
      _declared(_intColumn(64, false, initialValue));
  @override
  InitialPointer<int> hasInt64([int initialValue = 0]) =>
      _declared(_intColumn(64, true, initialValue));

  /// Signed 64-bit, like [hasInt64] and for its reason: `Entity.pack` shifts
  /// the archetype id up into the sign position, so only a signed slot
  /// round-trips every handle unchanged.
  @override
  InitialPointer<Entity> hasEntity([Entity? initialValue]) => _declared(
    _EntityHandleField(_intColumn(64, true, initialValue?.value ?? 0)),
  );

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

    return _declared(
      _EnumField<E>(
        _intColumn(
          _enumIndexWidth(values.length),
          false,
          initialValue?.index ?? 0,
        ),
        values,
      ),
    );
  }

  @override
  InitialPointer<double> hasFloat32([double initialValue = 0.0]) =>
      _declared(_floatColumn(32, initialValue));
  @override
  InitialPointer<double> hasFloat64([double initialValue = 0.0]) =>
      _declared(_floatColumn(64, initialValue));

  @override
  InitialPointer<int?> optUint1([int? initialValue]) =>
      _declared(_optIntColumn(1, false, initialValue));
  @override
  InitialPointer<int?> optInt1([int? initialValue]) =>
      _declared(_optIntColumn(1, true, initialValue));
  @override
  InitialPointer<int?> optUint2([int? initialValue]) =>
      _declared(_optIntColumn(2, false, initialValue));
  @override
  InitialPointer<int?> optInt2([int? initialValue]) =>
      _declared(_optIntColumn(2, true, initialValue));
  @override
  InitialPointer<int?> optUint4([int? initialValue]) =>
      _declared(_optIntColumn(4, false, initialValue));
  @override
  InitialPointer<int?> optInt4([int? initialValue]) =>
      _declared(_optIntColumn(4, true, initialValue));
  @override
  InitialPointer<int?> optUint8([int? initialValue]) =>
      _declared(_optIntColumn(8, false, initialValue));
  @override
  InitialPointer<int?> optInt8([int? initialValue]) =>
      _declared(_optIntColumn(8, true, initialValue));
  @override
  InitialPointer<int?> optUint16([int? initialValue]) =>
      _declared(_optIntColumn(16, false, initialValue));
  @override
  InitialPointer<int?> optInt16([int? initialValue]) =>
      _declared(_optIntColumn(16, true, initialValue));
  @override
  InitialPointer<int?> optUint32([int? initialValue]) =>
      _declared(_optIntColumn(32, false, initialValue));
  @override
  InitialPointer<int?> optInt32([int? initialValue]) =>
      _declared(_optIntColumn(32, true, initialValue));
  @override
  InitialPointer<int?> optUint64([int? initialValue]) =>
      _declared(_optIntColumn(64, false, initialValue));
  @override
  InitialPointer<int?> optInt64([int? initialValue]) =>
      _declared(_optIntColumn(64, true, initialValue));

  /// Signed 64-bit beside a presence flag, the signedness for [hasEntity]'s
  /// reason.
  @override
  InitialPointer<Entity?> optEntity([Entity? initialValue]) => _declared(
    _OptionalEntityHandleField(_optIntColumn(64, true, initialValue?.value)),
  );

  @override
  InitialPointer<double?> optFloat32([double? initialValue]) =>
      _declared(_optFloatColumn(32, initialValue));
  @override
  InitialPointer<double?> optFloat64([double? initialValue]) =>
      _declared(_optFloatColumn(64, initialValue));

  @override
  DataArrayPointer<T> hasArray<T>(
    DataElement<T> element,
    int length, [
    T? initialValue,
  ]) => _declared(_arrayColumn<T>(element, length, initialValue, null));

  @override
  DataArrayPointer<T> hasArrayOf<T>(
    DataElement<T> element,
    int length,
    List<T> initialValues,
  ) => _declared(_arrayColumn<T>(element, length, null, initialValues));

  @override
  DataArrayPointer<T?> optArray<T>(
    DataElement<T> element,
    int length, [
    T? initialValue,
  ]) {
    _checkArrayLength(length);
    return _declared(_OptionalArrayField<T>(length, element, initialValue));
  }

  @override
  PackedPointer<T> hasPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    T initialValue,
  ) => _declared(
    _PackedPointerField<T>(
      _intColumn(_checkBitWidth(repr), false, initialValue.pack()),
      repr,
    ),
  );

  @override
  DataPointer<T?> optPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr, [
    T? initialValue,
  ]) => _declared(
    _OptionalField<T>(
      _DeclaredPackedField<T>(
        _intColumn(_checkBitWidth(repr), false, initialValue?.pack() ?? 0),
        repr,
      ),
      initialValue != null,
    ),
  );

  /// The width is a constant and the table is not, which is the whole shape
  /// of this column: `CameraViewTable.viewBitWidth` reserves the bits from
  /// the declaration, and [_CameraViewField] reads the scene's table at
  /// realize, where a scene is reachable.
  @override
  DataPointer<CameraView?> optCameraView([CameraView? initialValue]) =>
      _declared(
        _OptionalField<CameraView>(
          _CameraViewField(
            _intColumn(
              CameraViewTable.viewBitWidth,
              false,
              initialValue?.pack() ?? 0,
            ),
          ),
          initialValue != null,
        ),
      );

  @override
  DataPointer<T> hasHeapObject<T>(T Function() initialValue) =>
      _declared(_HeapObjectField<T>(initialValue));

  @override
  DataPointer<T?> optHeapObject<T>() =>
      // No default factory: the wrapper's has-bit defaults to clear, so
      // `_OptionalField.writeInitialValue` never asks the value field for one
      // and a fresh entity reads `null`.
      _declared(_OptionalField<T>(_HeapObjectField<T>(null), false));
}

/// The descriptor a `Field.*` static declares against.
///
/// It is `const`, holds nothing and reaches nothing: `Field.float64(3)` builds
/// a column and hands it straight back, so a field initialiser needs no
/// archetype, no scene and no pass open around it. That is the whole
/// difference between this and the ambient window it replaced - there is no
/// stack, so there is no innermost entry for a declaration to be attributed
/// to, and a lazily-initialised one cannot land on whichever owner happens to
/// be under construction when it finally runs.
///
/// What it costs is that nothing here knows the column exists. A class's
/// declarations reach its archetype by being read off the constructed
/// instance and handed to [ArchetypeDataDescriptor.declare].
const DataDescriptor declaredColumns = _DeclaredColumns();

final class _DeclaredColumns extends _ColumnDescriptor {
  const _DeclaredColumns();

  @override
  D _declared<D extends ScannableField>(D column) => column;
}

/// Builds one archetype's field layout. Created and discarded by
/// `SceneDescriptor.has`; see the library doc at the top of this file.
///
/// It answers the same vocabulary [declaredColumns] does and additionally
/// **records** what it handed out, because a `describeStruct` body's
/// declarations are not held by any field a collector could read them off.
/// [realize] then gives every column - the collected ones and these - its row
/// space, in one pass and in declaration order.
final class ArchetypeDataDescriptor extends _ColumnDescriptor {
  ArchetypeDataDescriptor(this._storage);

  final ArchetypeStorage _storage;

  /// Every column this archetype declares, in the order it declared them,
  /// which is the order of the row.
  final List<_Declared> _columns = <_Declared>[];

  @override
  D _declared<D extends ScannableField>(D column) {
    _columns.add(column as _Declared);
    return column;
  }

  /// Records the columns a constructed instance's field initialisers
  /// produced, ahead of anything a describe pass goes on to add.
  ///
  /// A declaration that is not a column is skipped rather than refused: a
  /// `Query` is a declaration too, and what it resolves against is the
  /// component-bit registry rather than a row layout. This descriptor lays
  /// out rows, and says so by taking only what it can lay out.
  void declare(Iterable<ScannableField> declarations) {
    for (final declaration in declarations) {
      // Cast rather than promote, the shape `ArchetypeStorage.registerField`
      // spells out: `_Declared` is not a subtype of `ScannableField`, so `is`
      // leaves the static type alone and the cast is the only spelling.
      if (declaration is! _Declared) continue;
      _columns.add(declaration as _Declared);
    }
  }

  /// Gives every column its row space and registers it, so `seal` stamps its
  /// default.
  ///
  /// One pass at the end rather than one reservation per declaration, and
  /// that is what leaves an array's length movable and a camera view's table
  /// resolvable right up to this line. Called once, after the describe
  /// passes and before `ArchetypeStorage.seal`.
  void realize() {
    for (final column in _columns) {
      column.realize(_storage);
    }
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
