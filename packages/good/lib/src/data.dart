import 'package:good/src/declare.dart';
import 'package:good/src/struct.dart';

// note: we used to support DataPointer<Matrix4>, and etc but we removed them
// because they are object heap and during loop, they will cause GC to run
// frequently, which is not good for performance

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
  /// type on it, exactly as [hasEntity] is an `int64` with `Entity` on it.
  /// The storage, the width and the cost are identical; only the spelling at
  /// the call site changes, from `enable[e] = 1` to `enable[e] = true`.
  ///
  /// Prefer this over `hasUint1` for anything that is genuinely a flag. Keep
  /// `hasUint1` for a one-bit *number* - a two-state enum, a packed counter.
  DefaultPointer<bool> hasBool([bool defaultValue = false]);

  DefaultPointer<int> hasUint1([int defaultValue = 0]);
  DefaultPointer<int> hasInt1([int defaultValue = 0]);
  DefaultPointer<int> hasUint2([int defaultValue = 0]);
  DefaultPointer<int> hasInt2([int defaultValue = 0]);
  DefaultPointer<int> hasUint4([int defaultValue = 0]);
  DefaultPointer<int> hasInt4([int defaultValue = 0]);
  DefaultPointer<int> hasUint8([int defaultValue = 0]);
  DefaultPointer<int> hasInt8([int defaultValue = 0]);
  DefaultPointer<int> hasUint16([int defaultValue = 0]);
  DefaultPointer<int> hasInt16([int defaultValue = 0]);
  DefaultPointer<int> hasUint32([int defaultValue = 0]);
  DefaultPointer<int> hasInt32([int defaultValue = 0]);
  // 64-bit ints exist specifically so a field can hold a full packed
  // `Entity` handle (archetype id + page index + row offset, see
  // struct.dart). A field that holds one should say so - `hasEntity` and
  // `optEntity` are these two widths with the handle type on them, and
  // `data/hierarchy.dart`'s Child.parent/nextSibling/prevSibling and
  // Parent.firstChild/lastChild are the reference use. Both are signed,
  // because `Entity.value` is a signed Dart `int` already (packing can push
  // bits into the sign position, see Entity's own doc), so storing it signed
  // avoids any unsigned reinterpretation at the boundary. Uint64 exists for
  // symmetry with every narrower width, not because this engine needs
  // unsigned 64-bit arithmetic anywhere yet.
  DefaultPointer<int> hasUint64([int defaultValue = 0]);
  DefaultPointer<int> hasInt64([int defaultValue = 0]);

  /// A column holding an [Entity] handle - the same signed 64-bit storage
  /// [hasInt64] gives, with the type saying what the column holds.
  ///
  /// `Entity` is an extension type over `int` (see struct.dart), so this is
  /// the int64 read and write path exactly: no conversion, no allocation.
  /// What changes is the declare and call sites - an entity handle and a
  /// score stop being assignable to each other.
  ///
  /// With no [defaultValue] a fresh row reads `Entity(0)`, and that is a
  /// real handle rather than a "nothing here" marker - it packs archetype 0,
  /// page 0, row offset 0, which is some scene's first entity. Give a default
  /// only when an entity genuinely is the right starting target; otherwise
  /// write the column before anything reads it. For a link that is allowed to
  /// be absent, [optEntity] carries `null` as its own state.
  ///
  /// # A stored handle outlives the entity it names
  ///
  /// A handle is a row address (archetype id, page index, row offset).
  /// Destroying an entity frees the row, and the next `addEntity` on that
  /// archetype hands the row to a new entity whose handle is numerically
  /// equal to the old one. So a handle kept across the destroy resolves to
  /// whichever entity holds the row now, and reads and writes through it land
  /// on that entity's data, with `get`/`tryGet` answering for the archetype
  /// as usual.
  ///
  /// A link that outlives the tick it was made in therefore needs something
  /// beside it: a stamp the target also carries, compared against the stored
  /// one before the handle is trusted. `docs/guide/thinking-in-ecs.md` writes
  /// that recipe out in full.
  DefaultPointer<Entity> hasEntity([Entity? defaultValue]);

  /// A column holding one member of [E], stored as that member's `index` in
  /// the narrowest unsigned width the enum fits: one bit for up to two
  /// members, two bits for up to four, then 4, 8, 16 and 32. A three-member
  /// enum therefore takes the same two bits it took when callers declared
  /// `hasUint2` and packed the index themselves.
  ///
  /// [values] is a parameter because Dart cannot reach `E.values` from the
  /// type parameter. It has to be the enum's own `values` list: writing
  /// stores `Enum.index`, and reading is `values[index]`, so the two only
  /// agree on the complete list. Reading indexes the const list the enum
  /// declares, which allocates nothing.
  ///
  /// With no [defaultValue] a fresh row reads `values.first` - the member
  /// declared first, since its index is the `0` an unwritten field holds.
  DefaultPointer<E> hasEnum<E extends Enum>(List<E> values, [E? defaultValue]);

  DefaultPointer<double> hasFloat32([double defaultValue = 0.0]);
  DefaultPointer<double> hasFloat64([double defaultValue = 0.0]);
  DefaultPointer<int?> optUint1([int? defaultValue]);
  DefaultPointer<int?> optInt1([int? defaultValue]);
  DefaultPointer<int?> optUint2([int? defaultValue]);
  DefaultPointer<int?> optInt2([int? defaultValue]);
  DefaultPointer<int?> optUint4([int? defaultValue]);
  DefaultPointer<int?> optInt4([int? defaultValue]);
  DefaultPointer<int?> optUint8([int? defaultValue]);
  DefaultPointer<int?> optInt8([int? defaultValue]);
  DefaultPointer<int?> optUint16([int? defaultValue]);
  DefaultPointer<int?> optInt16([int? defaultValue]);
  DefaultPointer<int?> optUint32([int? defaultValue]);
  DefaultPointer<int?> optInt32([int? defaultValue]);
  DefaultPointer<int?> optUint64([int? defaultValue]);
  DefaultPointer<int?> optInt64([int? defaultValue]);

  /// A column holding an [Entity] handle or `null` - [hasEntity]'s storage
  /// with a presence flag in front of it, so "no target" is a state of its
  /// own rather than a handle that has to be reserved as a sentinel.
  ///
  /// This is what a link between entities usually wants. [hasEntity]'s
  /// unwritten value is `Entity(0)`, a real address (archetype 0, page 0,
  /// row 0) rather than a "nothing here"; here an unwritten column reads
  /// `null`, and `Entity(0)` stored in it reads back as itself.
  ///
  /// With no [defaultValue] a fresh row reads `null`. Pass one and every
  /// fresh row starts pointing at it.
  ///
  /// # The presence flag can cost a byte per row
  ///
  /// The flag is a bit declared ahead of the handle, and the handle then
  /// rounds up to its own byte. Declared where the row is byte-aligned -
  /// the usual case - the column takes 72 bits against [hasEntity]'s 64.
  /// Declared after a sub-byte field that left room in the byte (a
  /// `hasBool`, a `hasUint4`), the flag lands in that room and the column
  /// costs the same 64 bits. Worth ordering for on a link every entity in a
  /// scene carries.
  ///
  /// The handle-outlives-the-entity warning on [hasEntity] applies here
  /// unchanged: `null` says the link is absent, never that its target has
  /// been destroyed.
  DefaultPointer<Entity?> optEntity([Entity? defaultValue]);

  DefaultPointer<double?> optFloat32([double? defaultValue]);
  DefaultPointer<double?> optFloat64([double? defaultValue]);
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

  /// A float array whose elements start at *different* values: element `i`
  /// of a fresh row holds `defaultValues[i]`, and any slot past the end of
  /// [defaultValues] holds `0.0`.
  ///
  /// [length] is the storage capacity, as it is for [hasFloat64Array], so an
  /// array can reserve slots beyond the values it starts with and have them
  /// written per entity later. More defaults than the array can hold is an
  /// error.
  ///
  /// `goo2d`'s `hasPolygonCollider(points: ...)` is the reference use: a
  /// prefab whose outline is fixed states it where it declares the field
  /// rather than writing every vertex from `onEntityMounted`.
  DataArrayPointer<double> hasFloat32ArrayOf(
    int length,
    List<double> defaultValues,
  );
  DataArrayPointer<double> hasFloat64ArrayOf(
    int length,
    List<double> defaultValues,
  );
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
  /// never a Dart heap reference (the no-allocation rule), and a read unpacks
  /// it back through that same representation.
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

/// Declares one column on the struct currently being constructed, from the
/// field that holds it:
///
/// ```dart
/// class Player extends EntityStruct with Transform2D {
///   final speed = Field.float64(3.0);
///   final hp = Field.int32(100);
/// }
/// ```
///
/// That is the whole declaration: no `late final DataPointer<double> speed;`
/// above it, no `speed = data.hasFloat64(3.0);` in a `describeStruct` below
/// it. The name is written once.
///
/// Every method here is the matching [DataDescriptor] `has*`/`opt*` with the
/// prefix dropped, returns exactly what that returns, and reaches the
/// descriptor through [DeclarationContext] - so `speed[entity]` is the same
/// read it was when the field was a `late final` assigned in
/// `describeStruct`. There is no wrapper object and nothing extra on the read
/// path.
///
/// # Statics on a class, not top-level functions
///
/// A top-level `Int32(...)` would be silently shadowed by `dart:ffi`'s
/// `Int32` in any library that imports both, and the error the user sees is
/// "Too many positional arguments" plus an unused-import hint, with no
/// mention of a collision. `dart:ffi` exports `Int8/16/32/64`,
/// `Uint8/16/32/64`, `Bool`, `Double`, `Float` and `Array`, and this repo
/// imports it in dozens of files. Namespacing them here removes the question.
///
/// `Field` and not `Column`, which is what a row's slot is called throughout
/// these docs: `Column` is a Flutter widget, and a name exported by both
/// `package:flutter` and this package is an `ambiguous_import` error in every
/// file that imports the two - which is every file that puts a `GameView`
/// inside a layout. The engine's own code already says field (`declareField`,
/// `registerField`, `_Field<T>`), so this is the term that was free.
///
/// [boolean] rather than `bool` for a related reason, one level down: a
/// member named `bool` hides the *type* `bool` inside this class body, so its
/// own signature stops compiling.
///
/// # When a field still needs `describeStruct`
///
/// A field initialiser cannot read another field, so a column whose default
/// comes from a handle declared in an earlier pass - an asset from
/// `describeAssets`, a sprite built from a texture - keeps its `describeStruct`
/// body. The two forms coexist: constructor-time declarations run first, then
/// the passes `SceneDescriptor.has` drives, in the order they already ran.
///
/// A prefab that wants a *different* default for a column one of its mixins
/// declared also uses `describeStruct`, but to move the default rather than
/// to declare anything - see [DefaultPointer.defaultValue]. Declaring the
/// name a second time would not do it.
///
/// # Two mixins declaring the same field name are silent here
///
/// Components are mixins, so `speed` declared by two of them is an override
/// rather than an error: the later one in the `with` clause wins. Written as
/// `describeStruct` assignments that used to be caught by accident - both
/// bodies assigned the same `late final` and the second throw a
/// `LateInitializationError` before the game ran. An eager initialiser assigns
/// nothing, so both columns are allocated, the row grows by both, and one of
/// them is unreachable for the life of the process. Measured: 128 bits of row
/// against 64, `speed[entity]` reading the second mixin's column, no error
/// anywhere.
///
/// Prefix a published component's columns the way `Transform2D` prefixes
/// `transformOffsetX`. Catching it properly is a build-time check over the
/// mixin closure, which is issue #58.
abstract final class Field {
  /// See [DataDescriptor.hasBool].
  static DefaultPointer<bool> boolean([bool defaultValue = false]) =>
      DeclarationContext.data.hasBool(defaultValue);

  static DefaultPointer<int> uint1([int defaultValue = 0]) =>
      DeclarationContext.data.hasUint1(defaultValue);
  static DefaultPointer<int> int1([int defaultValue = 0]) =>
      DeclarationContext.data.hasInt1(defaultValue);
  static DefaultPointer<int> uint2([int defaultValue = 0]) =>
      DeclarationContext.data.hasUint2(defaultValue);
  static DefaultPointer<int> int2([int defaultValue = 0]) =>
      DeclarationContext.data.hasInt2(defaultValue);
  static DefaultPointer<int> uint4([int defaultValue = 0]) =>
      DeclarationContext.data.hasUint4(defaultValue);
  static DefaultPointer<int> int4([int defaultValue = 0]) =>
      DeclarationContext.data.hasInt4(defaultValue);
  static DefaultPointer<int> uint8([int defaultValue = 0]) =>
      DeclarationContext.data.hasUint8(defaultValue);
  static DefaultPointer<int> int8([int defaultValue = 0]) =>
      DeclarationContext.data.hasInt8(defaultValue);
  static DefaultPointer<int> uint16([int defaultValue = 0]) =>
      DeclarationContext.data.hasUint16(defaultValue);
  static DefaultPointer<int> int16([int defaultValue = 0]) =>
      DeclarationContext.data.hasInt16(defaultValue);
  static DefaultPointer<int> uint32([int defaultValue = 0]) =>
      DeclarationContext.data.hasUint32(defaultValue);
  static DefaultPointer<int> int32([int defaultValue = 0]) =>
      DeclarationContext.data.hasInt32(defaultValue);
  static DefaultPointer<int> uint64([int defaultValue = 0]) =>
      DeclarationContext.data.hasUint64(defaultValue);
  static DefaultPointer<int> int64([int defaultValue = 0]) =>
      DeclarationContext.data.hasInt64(defaultValue);

  /// See [DataDescriptor.hasEntity], including its warning that a stored
  /// handle outlives the entity it names.
  static DefaultPointer<Entity> entity([Entity? defaultValue]) =>
      DeclarationContext.data.hasEntity(defaultValue);

  /// See [DataDescriptor.hasEnum]. Named `enumOf` because `enum` is a
  /// keyword.
  static DefaultPointer<E> enumOf<E extends Enum>(
    List<E> values, [
    E? defaultValue,
  ]) => DeclarationContext.data.hasEnum<E>(values, defaultValue);

  static DefaultPointer<double> float32([double defaultValue = 0.0]) =>
      DeclarationContext.data.hasFloat32(defaultValue);
  static DefaultPointer<double> float64([double defaultValue = 0.0]) =>
      DeclarationContext.data.hasFloat64(defaultValue);

  static DefaultPointer<int?> optUint1([int? defaultValue]) =>
      DeclarationContext.data.optUint1(defaultValue);
  static DefaultPointer<int?> optInt1([int? defaultValue]) =>
      DeclarationContext.data.optInt1(defaultValue);
  static DefaultPointer<int?> optUint2([int? defaultValue]) =>
      DeclarationContext.data.optUint2(defaultValue);
  static DefaultPointer<int?> optInt2([int? defaultValue]) =>
      DeclarationContext.data.optInt2(defaultValue);
  static DefaultPointer<int?> optUint4([int? defaultValue]) =>
      DeclarationContext.data.optUint4(defaultValue);
  static DefaultPointer<int?> optInt4([int? defaultValue]) =>
      DeclarationContext.data.optInt4(defaultValue);
  static DefaultPointer<int?> optUint8([int? defaultValue]) =>
      DeclarationContext.data.optUint8(defaultValue);
  static DefaultPointer<int?> optInt8([int? defaultValue]) =>
      DeclarationContext.data.optInt8(defaultValue);
  static DefaultPointer<int?> optUint16([int? defaultValue]) =>
      DeclarationContext.data.optUint16(defaultValue);
  static DefaultPointer<int?> optInt16([int? defaultValue]) =>
      DeclarationContext.data.optInt16(defaultValue);
  static DefaultPointer<int?> optUint32([int? defaultValue]) =>
      DeclarationContext.data.optUint32(defaultValue);
  static DefaultPointer<int?> optInt32([int? defaultValue]) =>
      DeclarationContext.data.optInt32(defaultValue);
  static DefaultPointer<int?> optUint64([int? defaultValue]) =>
      DeclarationContext.data.optUint64(defaultValue);
  static DefaultPointer<int?> optInt64([int? defaultValue]) =>
      DeclarationContext.data.optInt64(defaultValue);

  /// See [DataDescriptor.optEntity] - the spelling a link that may be absent
  /// wants.
  static DefaultPointer<Entity?> optEntity([Entity? defaultValue]) =>
      DeclarationContext.data.optEntity(defaultValue);

  static DefaultPointer<double?> optFloat32([double? defaultValue]) =>
      DeclarationContext.data.optFloat32(defaultValue);
  static DefaultPointer<double?> optFloat64([double? defaultValue]) =>
      DeclarationContext.data.optFloat64(defaultValue);

  static DataArrayPointer<int> uint1Array(int length, [int defaultValue = 0]) =>
      DeclarationContext.data.hasUint1Array(length, defaultValue);
  static DataArrayPointer<int> int1Array(int length, [int defaultValue = 0]) =>
      DeclarationContext.data.hasInt1Array(length, defaultValue);
  static DataArrayPointer<int> uint2Array(int length, [int defaultValue = 0]) =>
      DeclarationContext.data.hasUint2Array(length, defaultValue);
  static DataArrayPointer<int> int2Array(int length, [int defaultValue = 0]) =>
      DeclarationContext.data.hasInt2Array(length, defaultValue);
  static DataArrayPointer<int> uint4Array(int length, [int defaultValue = 0]) =>
      DeclarationContext.data.hasUint4Array(length, defaultValue);
  static DataArrayPointer<int> int4Array(int length, [int defaultValue = 0]) =>
      DeclarationContext.data.hasInt4Array(length, defaultValue);
  static DataArrayPointer<int> uint8Array(int length, [int defaultValue = 0]) =>
      DeclarationContext.data.hasUint8Array(length, defaultValue);
  static DataArrayPointer<int> int8Array(int length, [int defaultValue = 0]) =>
      DeclarationContext.data.hasInt8Array(length, defaultValue);
  static DataArrayPointer<int> uint16Array(
    int length, [
    int defaultValue = 0,
  ]) => DeclarationContext.data.hasUint16Array(length, defaultValue);
  static DataArrayPointer<int> int16Array(int length, [int defaultValue = 0]) =>
      DeclarationContext.data.hasInt16Array(length, defaultValue);
  static DataArrayPointer<int> uint32Array(
    int length, [
    int defaultValue = 0,
  ]) => DeclarationContext.data.hasUint32Array(length, defaultValue);
  static DataArrayPointer<int> int32Array(int length, [int defaultValue = 0]) =>
      DeclarationContext.data.hasInt32Array(length, defaultValue);
  static DataArrayPointer<double> float32Array(
    int length, [
    double defaultValue = 0.0,
  ]) => DeclarationContext.data.hasFloat32Array(length, defaultValue);
  static DataArrayPointer<double> float64Array(
    int length, [
    double defaultValue = 0.0,
  ]) => DeclarationContext.data.hasFloat64Array(length, defaultValue);

  /// See [DataDescriptor.hasFloat32ArrayOf] - element `i` starts at
  /// `defaultValues[i]`.
  static DataArrayPointer<double> float32ArrayOf(
    int length,
    List<double> defaultValues,
  ) => DeclarationContext.data.hasFloat32ArrayOf(length, defaultValues);

  /// See [DataDescriptor.hasFloat64ArrayOf].
  static DataArrayPointer<double> float64ArrayOf(
    int length,
    List<double> defaultValues,
  ) => DeclarationContext.data.hasFloat64ArrayOf(length, defaultValues);

  static DataArrayPointer<int?> optUint1Array(
    int length, [
    int? defaultValue,
  ]) => DeclarationContext.data.optUint1Array(length, defaultValue);
  static DataArrayPointer<int?> optInt1Array(int length, [int? defaultValue]) =>
      DeclarationContext.data.optInt1Array(length, defaultValue);
  static DataArrayPointer<int?> optUint2Array(
    int length, [
    int? defaultValue,
  ]) => DeclarationContext.data.optUint2Array(length, defaultValue);
  static DataArrayPointer<int?> optInt2Array(int length, [int? defaultValue]) =>
      DeclarationContext.data.optInt2Array(length, defaultValue);
  static DataArrayPointer<int?> optUint4Array(
    int length, [
    int? defaultValue,
  ]) => DeclarationContext.data.optUint4Array(length, defaultValue);
  static DataArrayPointer<int?> optInt4Array(int length, [int? defaultValue]) =>
      DeclarationContext.data.optInt4Array(length, defaultValue);
  static DataArrayPointer<int?> optUint8Array(
    int length, [
    int? defaultValue,
  ]) => DeclarationContext.data.optUint8Array(length, defaultValue);
  static DataArrayPointer<int?> optInt8Array(int length, [int? defaultValue]) =>
      DeclarationContext.data.optInt8Array(length, defaultValue);
  static DataArrayPointer<int?> optUint16Array(
    int length, [
    int? defaultValue,
  ]) => DeclarationContext.data.optUint16Array(length, defaultValue);
  static DataArrayPointer<int?> optInt16Array(
    int length, [
    int? defaultValue,
  ]) => DeclarationContext.data.optInt16Array(length, defaultValue);
  static DataArrayPointer<int?> optUint32Array(
    int length, [
    int? defaultValue,
  ]) => DeclarationContext.data.optUint32Array(length, defaultValue);
  static DataArrayPointer<int?> optInt32Array(
    int length, [
    int? defaultValue,
  ]) => DeclarationContext.data.optInt32Array(length, defaultValue);
  static DataArrayPointer<double?> optFloat32Array(
    int length, [
    double? defaultValue,
  ]) => DeclarationContext.data.optFloat32Array(length, defaultValue);
  static DataArrayPointer<double?> optFloat64Array(
    int length, [
    double? defaultValue,
  ]) => DeclarationContext.data.optFloat64Array(length, defaultValue);

  /// See [DataDescriptor.hasPacked] - a value stored as the int its
  /// [IntRepresentation] packs it into.
  static PackedPointer<T> packed<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    T defaultValue,
  ) => DeclarationContext.data.hasPacked<T>(repr, defaultValue);

  /// See [DataDescriptor.optPacked].
  static DataPointer<T?> optPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr, [
    T? defaultValue,
  ]) => DeclarationContext.data.optPacked<T>(repr, defaultValue);

  /// See [DataDescriptor.hasHeapObject], including why the value it stores
  /// means nothing on a second isolate.
  static DataPointer<T> heapObject<T>(T Function() defaultValue) =>
      DeclarationContext.data.hasHeapObject<T>(defaultValue);

  /// See [DataDescriptor.optHeapObject].
  static DataPointer<T?> optHeapObject<T>() =>
      DeclarationContext.data.optHeapObject<T>();

  /// See [DataDescriptor.hasPackedArray].
  static DataArrayPointer<T> packedArray<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    int length,
    T defaultValue,
  ) => DeclarationContext.data.hasPackedArray<T>(repr, length, defaultValue);

  /// See [DataDescriptor.optPackedArray].
  static DataArrayPointer<T?> optPackedArray<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    int length, [
    T? defaultValue,
  ]) => DeclarationContext.data.optPackedArray<T>(repr, length, defaultValue);
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
  /// A *system* reading uncommitted state is the thing the
  /// no-specialised-variant rule exists to forbid, and this does not change
  /// that. What it is for is the narrow case of a mutation that has to read
  /// back the structure **it is itself editing**, within one tick:
  /// `Parent.addChild` reads `lastChild` to append to the chain, and two
  /// `addChild` calls in one tick both read the same published value, both
  /// conclude the parent has no children yet, and the second silently
  /// overwrites the first. That is not a race or a subtle ordering question -
  /// it drops entities out of the hierarchy outright, and every existing test
  /// missed it because a page that has never published falls through to the
  /// write slot anyway, making the first tick work by accident.
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
  /// home for the behaviour (the one-fact-one-place rule).
  DataBinding<T> bind(Entity instance) => _DataBinding(this, instance);
}

/// A column whose declared default a prefab can still change while the
/// archetype is being described.
///
/// A default written where the column is declared - `Field.float64(60)`, or
/// `data.hasFloat64(60)` - is the same for every archetype that mixes the
/// component in. Setting [defaultValue] in a prefab's own `describeStruct`
/// changes it for that archetype and no other:
///
/// ```dart
/// class Eye extends EntityStruct with Transform3D, WorldTransform3D, Camera3D {
///   @override
///   void describeStruct(DataDescriptor data) {
///     super.describeStruct(data);
///     near.defaultValue = 10;
///     far.defaultValue *= 2;
///   }
/// }
/// ```
///
/// [defaultValue] reads as well as writes, which is what the second line
/// needs: the prefab doubles whatever `Camera3D` chose instead of copying
/// the number down and having to keep the copy in step.
///
/// Re-declaring `near` in the prefab would not do this. A field declared
/// twice is an override of the name and not of the column, so both columns
/// get allocated and one of them is unreachable - see `Field`'s note on two
/// mixins declaring the same name.
///
/// # Which columns have one
///
/// Every column whose default is a plain stored value: the integer widths,
/// the floats, `bool`, an enum member, an `Entity` handle, and the nullable
/// form of each. Packed columns, heap-object columns and arrays are
/// deliberately left out - see [defaultValue].
abstract class DefaultPointer<T> extends DataPointer<T> {
  const DefaultPointer();

  /// The value a freshly allocated row starts with - what the column was
  /// declared with, or whatever a prefab has since moved it to.
  ///
  /// Reading it never throws. Writing it does once the archetype is sealed,
  /// which happens as soon as `describeStruct` has returned, and the pair is
  /// deliberately asymmetric: a default is *stamped*, not consulted.
  /// `ArchetypeStorage.seal` builds one prototype row holding every column's
  /// default and memcpy's it into each row allocated afterwards, and there
  /// is no `hasValue ? value : defaultValue` anywhere on the read path. So
  /// after `seal` the stored value is still exactly what every new row will
  /// hold - true, and worth being able to ask about - while a *write* to it
  /// could no longer reach the prototype and would be a lie.
  ///
  /// Having both halves is what lets a prefab adjust an inherited default
  /// rather than restate it:
  ///
  /// ```dart
  /// far.defaultValue *= 2;      // twice whatever Camera3D chose
  /// hp.defaultValue += 50;      // the component's number, plus fifty
  /// ```
  ///
  /// Neither is a write to any entity. `near.defaultValue = 10` changes what
  /// the *next* row starts with; `near[entity] = 10` changes one entity now.
  ///
  /// # Why packed, heap-object and array columns have neither half
  ///
  /// A packed column's value means something only against the
  /// `IntRepresentation` it was declared with, and the two in this engine -
  /// a `CameraView` and an `Asset` - are things an entity is pointed at
  /// individually, not things a whole archetype starts out holding. A
  /// heap-object default is a factory whose one result every row of the
  /// archetype then shares, on whichever isolate ran it. Neither has a
  /// per-archetype default anybody has wanted, and leaving them off beats
  /// inventing a meaning for one. The getter goes with the setter rather
  /// than being offered alone, because `defaultValue` on a column that
  /// cannot have one moved is a reading nobody can act on. Arrays are
  /// excluded by construction: a `DataArrayPointer` is not a [DataPointer]
  /// at all.
  T get defaultValue;
  set defaultValue(T newValue);
}

/// A [DataPointer] over an [IntRepresentable], which can additionally hand
/// back the raw packed int without unpacking it.
///
/// That escape hatch is what keeps a self-describing representation off the
/// allocator on a hot path. `frame[entity]` has to return a `SpriteFrame`, so
/// it constructs one - fine at a write site, 20k allocations a frame in a
/// renderer's loop, which is exactly what the no-allocation rule and the
/// removal of `DataPointer<Matrix4>` (see the note at the top of this file)
/// exist to prevent. A renderer reads [packedAt] and does the shifts itself.
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
/// forbids allocating one per access (the no-allocation rule: zero heap allocation
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
