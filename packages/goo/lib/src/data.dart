import 'package:goo/src/struct.dart';

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
  /// An object-reference field: the row stores [table]'s `Uint32` address,
  /// never a Dart heap reference (RULES.md rule 1), and a read resolves it
  /// back through that same table.
  ///
  /// [table] is named at the *declare* site because that is the one place the
  /// field's type is known - so a fourth kind of global object costs nothing
  /// but its own table, and no shared address space has to exist for the
  /// read path to find one.
  DataPointer<T> hasObject<T extends GlobalObject>(
    ObjectTable table,
    T defaultValue,
  );
  DataPointer<T?> optObject<T extends GlobalObject>(
    ObjectTable table, [
    T? defaultValue,
  ]);

  // -----
  // Heap objects are the unconstrained cousin of hasObject/optObject: any
  // Dart object at all, including a closure, a `List`, or an instance of a
  // class you don't own - no `GlobalObject` implementation required.
  //
  // The difference that matters is *when* and *where* the value is
  // meaningful. A `GlobalObject`'s address is assigned once at describe/load
  // time and is agreed on by every isolate that re-ran the same registration
  // (that's what makes an asset reference survive being read from the render
  // isolate). A heap object's address is assigned the moment you write it,
  // on whichever isolate wrote it, and means nothing anywhere else - the
  // row's 32-bit payload is an index into *that* isolate's
  // `HeapObjectRegistry` and nothing more. So:
  //
  //  * Use `hasObject`/`optObject` for anything a second isolate has to
  //    resolve (assets, shared immutable descriptors).
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
  DataArrayPointer<T> hasObjectArray<T extends GlobalObject>(
    ObjectTable table,
    int length,
    T defaultValue,
  );
  DataArrayPointer<T?> optObjectArray<T extends GlobalObject>(
    ObjectTable table,
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

/// A thing with an integer key, and nothing more.
///
/// The key implies **nothing on its own** - not that it names an asset, not
/// that it names a camera view. It is meaningful only against the
/// [ObjectTable] that issued it, and whoever handles the int decides what it
/// means.
///
/// That is a correction of an earlier design in which every `GlobalObject`
/// shared one process-wide address space (a `GlobalObjectRegistry`, later
/// merged into `GameAssets`). One space forces every unrelated population -
/// assets, camera views, whatever comes next - to be poured into the same
/// table, which makes "address 3" a question you cannot answer without
/// knowing what else has been registered.
abstract interface class GlobalObject {
  int get address;
}

/// Issues and resolves the addresses for **one population** of
/// [GlobalObject]s.
///
/// One table per population, each numbering from zero. `GameAssets` numbers
/// assets; a `Game` numbers its camera views. The two may hand out the same
/// address and it does not matter, because an address is never resolved
/// except against the table that issued it - which is exactly the property a
/// single shared registry destroys.
///
/// Generic in the *method* rather than the class deliberately: a row field is
/// declared as some specific subtype (`Texture`), while a table holds a whole
/// family (`GameAssetInstance`), and Dart's covariance means an
/// `ObjectTable<GameAssetInstance>` is not an `ObjectTable<Texture>`. Putting
/// the type parameter on `resolve` lets one table serve every field that
/// draws from it.
abstract interface class ObjectTable {
  /// The object at [address], or a `StateError` naming what went wrong -
  /// never a neighbouring object, and never null.
  T resolve<T extends GlobalObject>(int address);

  /// [resolve], but null when nothing is registered at [address].
  T? tryResolve<T extends GlobalObject>(int address);
}
