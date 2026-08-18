import 'package:good/src/struct.dart';

// note: we used to support DataPointer<Matrix4>, and etc
// but we removed them because they are object heap
// and during loop, they will cause GC to run frequently, which is not good for performance

// default value is stored to the memory pool during object creation
// NOT accessed through pattern like `hasValue ? value : defaultValue`

abstract class DataBinding<T> {
  T get value;
  set value(T newValue);
}

abstract class DataDescriptor {
  /// A boolean flag - one bit on the row, same storage as [hasUint1].
  ///
  /// This engine stored booleans as `uint1` written `1`/`0` for a long time,
  /// on the reasoning that there was no boolean field *kind*. There still
  /// isn't, and there does not need to be: a `bool` field is a `uint1` with a
  /// type on it, exactly as `Child.parent` is an `optInt64` with `Entity` on
  /// it. The storage, the width and the cost are identical; only the spelling
  /// at the call site changes, from `enable[e] = 1` to `enable[e] = true`.
  ///
  /// Prefer this over `hasUint1` for anything that is genuinely a flag. Keep
  /// `hasUint1` for a one-bit *number* - a two-state enum, a packed counter.
  DataPointer<bool> hasBool([bool defaultValue = false]);

  DataPointer<int> hasUint1([int defaultValue = 0]);
  DataPointer<int> hasInt1([int defaultValue = 0]);
  DataPointer<int> hasUint2([int defaultValue = 0]);
  DataPointer<int> hasInt2([int defaultValue = 0]);
  DataPointer<int> hasUint4([int defaultValue = 0]);
  DataPointer<int> hasInt4([int defaultValue = 0]);
  DataPointer<int> hasUint8([int defaultValue = 0]);
  DataPointer<int> hasInt8([int defaultValue = 0]);
  DataPointer<int> hasUint16([int defaultValue = 0]);
  DataPointer<int> hasInt16([int defaultValue = 0]);
  DataPointer<int> hasUint32([int defaultValue = 0]);
  DataPointer<int> hasInt32([int defaultValue = 0]);
  // 64-bit ints exist specifically so a field can hold a full packed
  // `Entity` handle (archetype id + page index + row offset, see struct.dart)
  // - `data/hierarchy.dart`'s Child.parent/nextSibling/prevSibling and
  // Parent.firstChild/lastChild are the reference use. Prefer `hasInt64`/
  // `optInt64` for that specifically: `Entity.value` is a signed Dart
  // `int` already (packing can push bits into the sign position, see
  // Entity's own doc), so storing it signed avoids any unsigned
  // reinterpretation at the boundary. Uint64 exists for symmetry with
  // every narrower width, not because this engine needs unsigned 64-bit
  // arithmetic anywhere yet.
  DataPointer<int> hasUint64([int defaultValue = 0]);
  DataPointer<int> hasInt64([int defaultValue = 0]);
  DataPointer<double> hasFloat32([double defaultValue = 0.0]);
  DataPointer<double> hasFloat64([double defaultValue = 0.0]);
  DataPointer<int?> optUint1([int? defaultValue]);
  DataPointer<int?> optInt1([int? defaultValue]);
  DataPointer<int?> optUint2([int? defaultValue]);
  DataPointer<int?> optInt2([int? defaultValue]);
  DataPointer<int?> optUint4([int? defaultValue]);
  DataPointer<int?> optInt4([int? defaultValue]);
  DataPointer<int?> optUint8([int? defaultValue]);
  DataPointer<int?> optInt8([int? defaultValue]);
  DataPointer<int?> optUint16([int? defaultValue]);
  DataPointer<int?> optInt16([int? defaultValue]);
  DataPointer<int?> optUint32([int? defaultValue]);
  DataPointer<int?> optInt32([int? defaultValue]);
  DataPointer<int?> optUint64([int? defaultValue]);
  DataPointer<int?> optInt64([int? defaultValue]);
  DataPointer<double?> optFloat32([double? defaultValue]);
  DataPointer<double?> optFloat64([double? defaultValue]);
  DataArrayPointer<int> hasUint1Array(int length, [int defaultValue = 0]);
  DataArrayPointer<int> hasInt1Array(int length, [int defaultValue = 0]);
  DataArrayPointer<int> hasUint2Array(int length, [int defaultValue = 0]);
  DataArrayPointer<int> hasInt2Array(int length, [int defaultValue = 0]);
  DataArrayPointer<int> hasUint4Array(int length, [int defaultValue = 0]);
  DataArrayPointer<int> hasInt4Array(int length, [int defaultValue = 0]);
  DataArrayPointer<int> hasUint8Array(int length, [int defaultValue = 0]);
  DataArrayPointer<int> hasInt8Array(int length, [int defaultValue = 0]);
  DataArrayPointer<int> hasUint16Array(int length, [int defaultValue = 0]);
  DataArrayPointer<int> hasInt16Array(int length, [int defaultValue = 0]);
  DataArrayPointer<int> hasUint32Array(int length, [int defaultValue = 0]);
  DataArrayPointer<int> hasInt32Array(int length, [int defaultValue = 0]);
  DataArrayPointer<double> hasFloat32Array(
    int length, [
    double defaultValue = 0.0,
  ]);
  DataArrayPointer<double> hasFloat64Array(
    int length, [
    double defaultValue = 0.0,
  ]);
  DataArrayPointer<int?> optUint1Array(int length, [int? defaultValue]);
  DataArrayPointer<int?> optInt1Array(int length, [int? defaultValue]);
  DataArrayPointer<int?> optUint2Array(int length, [int? defaultValue]);
  DataArrayPointer<int?> optInt2Array(int length, [int? defaultValue]);
  DataArrayPointer<int?> optUint4Array(int length, [int? defaultValue]);
  DataArrayPointer<int?> optInt4Array(int length, [int? defaultValue]);
  DataArrayPointer<int?> optUint8Array(int length, [int? defaultValue]);
  DataArrayPointer<int?> optInt8Array(int length, [int? defaultValue]);
  DataArrayPointer<int?> optUint16Array(int length, [int? defaultValue]);
  DataArrayPointer<int?> optInt16Array(int length, [int? defaultValue]);
  DataArrayPointer<int?> optUint32Array(int length, [int? defaultValue]);
  DataArrayPointer<int?> optInt32Array(int length, [int? defaultValue]);
  DataArrayPointer<double?> optFloat32Array(int length, [double? defaultValue]);
  DataArrayPointer<double?> optFloat64Array(int length, [double? defaultValue]);

  // -----
  // behind the scene, the object is stored in memory pool as address to the actual object
  // the address resolves to its respective object storage,
  // for example, asset resolve its "address" to the loaded asset map as map key in the asset manager
  // we don't store the "asset manager" here, this is just helper to avoid the user to do something like this
  // spriteId.value = MyGameTextures.playerSprite.address;
  // instead, we can do this
  // spriteId.value = MyGameTextures.playerSprite;
  // and the system will resolve the address to the actual object for you
  // the renderer system would have to resolve the address manually
  // int spriteId = gameObject.spriteId.value;
  // Sprite? sprite = assetManager.getLoadedTexture(spriteId);
  /// A packed-value field: the row stores the `int` [repr] packs [T] into,
  /// never a Dart heap reference (RULES.md rule 1), and a read unpacks it
  /// back through that same representation.
  ///
  /// [repr] is named at the *declare* site because that is the one place the
  /// field's type is known - so a fourth kind of packed value costs nothing
  /// but its own representation, and no shared address space has to exist for
  /// the read path to find one. Pairing the two in the signature is also what
  /// makes a mismatched field/representation a compile error rather than a
  /// read-time `StateError`.
  ///
  /// The field is [IntRepresentation.bitWidth] bits wide, so a representation
  /// that only ever hands out a few hundred values costs a row a byte or two
  /// rather than a fixed four.
  PackedPointer<T> hasPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    T defaultValue,
  );
  DataPointer<T?> optPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr, [
    T? defaultValue,
  ]);

  // -----
  // Heap objects are the unconstrained cousin of hasPacked/optPacked: any
  // Dart object at all, including a closure, a `List`, or an instance of a
  // class you don't own - no `IntRepresentable` implementation required.
  //
  // The difference that matters is *when* and *where* the value is
  // meaningful. A packed value is either self-describing (the int *is* the
  // value, see `IntRepresentation`) or was assigned its int at describe/load
  // time by a table both isolates built identically - which is what makes an
  // asset reference survive being read from the render isolate. A heap
  // object's address is assigned the moment you write it, on whichever
  // isolate wrote it, and means nothing anywhere else - the row's 32-bit
  // payload is an index into *that* isolate's `HeapObjectRegistry` and
  // nothing more. So:
  //
  //  * Use `hasPacked`/`optPacked` for anything a second isolate has to
  //    unpack (assets, sprite frames, shared immutable descriptors).
  //  * Use `hasHeapObject`/`optHeapObject` for isolate-local, dynamically
  //    assigned references (a callback, a cached decoder, a native handle
  //    wrapper) that only the isolate that set them will ever read.
  //
  // The default is a *factory* rather than a bare value - see
  // `data_layout.dart`'s `_HeapObjectField` for what that does and, just as
  // importantly, what it does not do (it does not give each entity its own
  // instance).
  DataPointer<T> hasHeapObject<T>(T Function() defaultValue);

  /// Nullable heap-object field. No default parameter: an unset element is
  /// `null`, which is already the only sensible "nothing here yet" for a
  /// reference that is assigned dynamically at runtime.
  DataPointer<T?> optHeapObject<T>();
  DataArrayPointer<T> hasPackedArray<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    int length,
    T defaultValue,
  );
  DataArrayPointer<T?> optPackedArray<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    int length, [
    T? defaultValue,
  ]);
}

abstract class DataPointer<T> {
  const DataPointer();

  T operator [](Entity instance);
  void operator []=(Entity instance, T newValue);

  /// [operator []], but reading the slot this tick is **writing** instead of
  /// the last published one - so it sees writes made earlier in this same
  /// tick, which an ordinary read deliberately cannot.
  ///
  /// # This is for structural mutation, and nothing else
  ///
  /// A *system* reading uncommitted state is the thing RULES.md rule 8 exists
  /// to forbid, and this does not change that. What it is for is the narrow
  /// case of a mutation that has to read back the structure **it is itself
  /// editing**, within one tick: `Parent.addChild` reads `lastChild` to append
  /// to the chain, and two `addChild` calls in one tick both read the same
  /// published value, both conclude the parent has no children yet, and the
  /// second silently overwrites the first. That is not a race or a subtle
  /// ordering question - it drops entities out of the hierarchy outright, and
  /// every existing test missed it because a page that has never published
  /// falls through to the write slot anyway, making the first tick work by
  /// accident.
  ///
  /// Outside a tick window there is no write slot to speak of - the one the
  /// buffer would hand back holds whatever was there before `beginWrite`
  /// copied - so implementations fall back to the published read, which
  /// outside a tick is the only correct answer anyway.
  ///
  /// Only implemented where a structural mutation actually needs it (the
  /// optional-entity fields the hierarchy links are made of, and `float64`
  /// for composing a just-spawned transform). Anywhere else it throws rather
  /// than quietly returning the published value, because a silently-published
  /// answer here is exactly the bug this exists to fix.
  ///
  /// **Not `@internal`, and that is not an invitation.** It was, until
  /// `WorldTransformSystem` needed it - and that lives in `goo2d`, a
  /// different package, which is the whole scope of that annotation. The same
  /// thing happened to `Collision2DEvent`. Treat this as internal in spirit:
  /// if you are reaching for it from ordinary game code, you want the
  /// published read.
  T readPending(Entity instance) => throw UnsupportedError(
    '$runtimeType does not implement readPending. It is implemented only for '
    'the field kinds a structural mutation reads back within its own tick - '
    'see DataPointer.readPending. If a new structural field needs it, add it '
    'to that field class rather than falling back to a published read.',
  );

  /// Pairs this pointer with one [instance], so the result reads and writes
  /// that entity's value with no further arguments.
  ///
  /// Implementers **extend** `DataPointer` rather than implementing it, purely
  /// so this default is inherited instead of copied per implementation - one
  /// home for the behaviour (RULES.md rule 10).
  DataBinding<T> bind(Entity instance) => _DataBinding(this, instance);
}

/// A [DataPointer] over an [IntRepresentable], which can additionally hand
/// back the raw packed int without unpacking it.
///
/// That escape hatch is what keeps a self-describing representation off the
/// allocator on a hot path. `frame[entity]` has to return a `SpriteFrame`, so
/// it constructs one - fine at a write site, 20k allocations a frame in a
/// renderer's loop, which is exactly what RULES.md rule 1 and the removal of
/// `DataPointer<Matrix4>` (see the note at the top of this file) exist to
/// prevent. A renderer reads [packedAt] and does the shifts itself.
abstract class PackedPointer<T extends IntRepresentable>
    extends DataPointer<T> {
  const PackedPointer();

  /// The stored int, exactly as [IntRepresentable.pack] produced it, with no
  /// unpacking and no allocation. Reads the last *published* snapshot, like
  /// [DataPointer.operator []].
  int packedAt(Entity instance);
}

class _DataBinding<T> implements DataBinding<T> {
  final DataPointer<T> pointer;
  final Entity instance;

  _DataBinding(this.pointer, this.instance);

  @override
  T get value => pointer[instance];

  @override
  set value(T newValue) => pointer[instance] = newValue;
}

/// A fixed-length array of [length] values stored inline in every entity's
/// row - `data.hasFloat32Array(4)` reserves four floats per entity, not a
/// pointer to a shared list.
///
/// **Why two-argument `get`/`set` instead of `pointer[entity][index]`.**
/// The chained form needs an intermediate handle that knows *both* the row
/// and the array's layout (base offset, element width, length). This engine
/// forbids allocating one per access (RULES.md rule 1: zero heap allocation
/// on the per-entity-per-tick hot path), and the obvious allocation-free
/// carrier - an extension type - can hold exactly one representation value.
/// An extension type over `Entity` alone therefore cannot know which array
/// field produced it, and widening it to a record `(Entity, field)` bets the
/// hot path on records being reliably unboxed in this AOT/VM combination,
/// which this project is not willing to assume.
///
/// Plain parameters have no such question mark: `get(entity, index)` passes
/// two integers to a method on the one long-lived pointer object that
/// already holds the layout. So the two-step subscript is dropped
/// deliberately - this is not an unfinished API.
abstract class DataArrayPointer<T> {
  /// Number of elements per entity, fixed when the field is declared.
  int get length;

  /// Element [index] of [instance]'s array. Throws [RangeError] if [index]
  /// is outside `0 ..< length`.
  ///
  /// Reads the last *published* snapshot, exactly like [DataPointer] - a
  /// value written earlier in the same tick is not visible here.
  T get(Entity instance, int index);

  /// Writes element [index] of [instance]'s array. Throws [RangeError] if
  /// [index] is outside `0 ..< length`. Elements are independent: writing
  /// one never disturbs its neighbours, including for sub-byte element
  /// widths that share a byte.
  void set(Entity instance, int index, T newValue);
}

/// A thing that can be reduced to the integer a component row stores, and
/// nothing more.
///
/// The int implies **nothing on its own** - not that it names an asset, not
/// that it names a camera view, not that it names anything at all. It is
/// meaningful only against the [IntRepresentation] that produced the pairing,
/// and that representation decides what it means.
///
/// This was called `GlobalObject` with an `address` getter, and both halves of
/// that name were wrong. Not *global*: an int is scoped to one
/// representation, which was itself a correction of an earlier design where
/// every such object shared one process-wide address space and "address 3"
/// was unanswerable without knowing everything else registered. And not an
/// *address*: a [SpriteFrame]-style value is packed into its int outright,
/// with nothing stored anywhere and nothing to look up - which is exactly why
/// the other half of the pair says `unpack` rather than `resolve`.
abstract interface class IntRepresentable {
  /// This value as the [IntRepresentation.bitWidth]-bit integer a row holds.
  int pack();
}

/// The other direction: turns the int in a row back into a [T].
///
/// May **look the value up** - `Assets` keeps a list and the int is an index
/// into it - or may simply **decode it**, when the int carries the whole value
/// and there is no storage at all. A field neither knows nor cares which, and
/// that is the point of not calling this a table: an implementation is free to
/// be `const` and stateless.
///
/// One representation per population. Two of them may hand out the same int
/// and it does not matter, because an int is never unpacked except by the
/// representation the field was declared against.
///
/// Generic in the *class* rather than the method, so that a field and its
/// representation are type-checked against each other at the declare site
/// rather than blowing up at read time. A representation whose population is
/// heterogeneous (an asset table holding `Asset<Texture>` and
/// `Asset<AudioClip>`) vends a typed view per payload type instead of being
/// one representation for all of them - see `Assets.of`.
abstract interface class IntRepresentation<T extends IntRepresentable> {
  /// How many bits a column of [T] needs, `1..64`.
  ///
  /// A declare-time constant of the representation, never of an individual
  /// value: the layout is computed once and every entity in the archetype
  /// shares it, so a per-instance width could not be honoured.
  ///
  /// **Keep this a literal** in a `const`-constructible class. `good_cli`'s
  /// codegen hoists layout to build time by reading these through
  /// `package:analyzer`, which can evaluate a constant and cannot evaluate a
  /// computation.
  int get bitWidth;

  /// The value [bits] stands for, or a `StateError` naming what went wrong -
  /// never a neighbouring value, and never null.
  T unpack(int bits);

  /// [unpack], but null when [bits] stands for nothing.
  T? tryUnpack(int bits);
}
