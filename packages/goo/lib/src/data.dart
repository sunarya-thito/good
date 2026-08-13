import 'package:goo/src/struct.dart';

// note: we used to support DataPointer<Matrix4>, and etc
// but we removed them because they are object heap
// and during loop, they will cause GC to run frequently, which is not good for performance

// default value is stored to the memory pool during object creation
// NOT accessed through pattern like `hasValue ? value : defaultValue`

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
  DataPointer<T> hasObject<T extends GlobalObject>(T defaultValue);
  DataPointer<T?> optObject<T extends GlobalObject>([T? defaultValue]);

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
    int length,
    T defaultValue,
  );
  DataArrayPointer<T?> optObjectArray<T extends GlobalObject>(
    int length, [
    T? defaultValue,
  ]);
}

abstract class DataPointer<T> {
  T operator [](Entity instance);
  void operator []=(Entity instance, T newValue);
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

abstract interface class GlobalObject {
  int get address;
}
