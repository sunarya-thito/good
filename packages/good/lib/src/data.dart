import 'package:good/src/camera_view.dart';
import 'package:good/src/data_layout.dart';
import 'package:good/src/scannable.dart';
import 'package:good/src/struct.dart';

// note: we used to support DataPointer<Matrix4>, and etc but we removed them
// because they are object heap and during loop, they will cause GC to run
// frequently, which is not good for performance

abstract class DataBinding<T> {
  T get value;
  set value(T newValue);
}

/// # What this offers, and what it does not
///
/// Every width, `bool`, an enum member, an `Entity` handle, a packed value, a
/// heap object, and an inline array of any of the first two kinds - each with
/// a nullable form. `ParamDescriptor` and `StateDescriptor` carry the same
/// vocabulary wherever their own storage supports it, and each says in place
/// what it leaves out.
///
/// **There is no `hasString` and no `hasBytes`, and there cannot be.** A page
/// is an array of rows and a row is *reached* by multiplying a stride, so a
/// variable-length field would break random access outright - the argument
/// `ParamDescriptor` sets out in full, where a record's forward walk makes
/// the weaker requirement that lets one carry a tail. Text that belongs to an
/// entity goes in a fixed-capacity array of code units (`goo2d`'s `Text2D` is
/// the reference use) or through [hasHeapObject], which stores an index and
/// not the characters.
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
  InitialPointer<bool> hasBool([bool initialValue = false]);

  InitialPointer<int> hasUint1([int initialValue = 0]);
  InitialPointer<int> hasInt1([int initialValue = 0]);
  InitialPointer<int> hasUint2([int initialValue = 0]);
  InitialPointer<int> hasInt2([int initialValue = 0]);
  InitialPointer<int> hasUint4([int initialValue = 0]);
  InitialPointer<int> hasInt4([int initialValue = 0]);
  InitialPointer<int> hasUint8([int initialValue = 0]);
  InitialPointer<int> hasInt8([int initialValue = 0]);
  InitialPointer<int> hasUint16([int initialValue = 0]);
  InitialPointer<int> hasInt16([int initialValue = 0]);
  InitialPointer<int> hasUint32([int initialValue = 0]);
  InitialPointer<int> hasInt32([int initialValue = 0]);
  // 64-bit ints exist specifically so a field can hold a full packed
  // `Entity` handle (archetype id + page index + row offset, see
  // struct.dart). A field that holds one should say so - `hasEntity` and
  // `optEntity` are these two widths with the handle type on them, and
  // `data/hierarchy.dart`'s Child.childParent/childNextSibling/
  // childPrevSibling and Parent.parentFirstChild/parentLastChild are the
  // reference use. Both are signed, because `Entity.value` is a signed Dart
  // `int` already (packing can push bits into the sign position, see Entity's
  // own doc), so storing it signed avoids any unsigned reinterpretation at
  // the boundary. Uint64 exists for symmetry with every narrower width, not
  // because this engine needs unsigned 64-bit arithmetic anywhere yet.
  InitialPointer<int> hasUint64([int initialValue = 0]);
  InitialPointer<int> hasInt64([int initialValue = 0]);

  /// A column holding an [Entity] handle - the same signed 64-bit storage
  /// [hasInt64] gives, with the type saying what the column holds.
  ///
  /// `Entity` is an extension type over `int` (see struct.dart), so this is
  /// the int64 read and write path exactly: no conversion, no allocation.
  /// What changes is the declare and call sites - an entity handle and a
  /// score stop being assignable to each other.
  ///
  /// With no [initialValue] a fresh row reads `Entity(0)`, and that is a
  /// real handle and not a "nothing here" marker - it packs archetype 0,
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
  /// on that entity's data, with `entity<T>()` answering for the archetype
  /// as usual.
  ///
  /// A link that outlives the tick it was made in therefore needs something
  /// beside it: a stamp the target also carries, compared against the stored
  /// one before the handle is trusted. `docs/guide/thinking-in-ecs.md` writes
  /// that recipe out in full.
  InitialPointer<Entity> hasEntity([Entity? initialValue]);

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
  /// With no [initialValue] a fresh row reads `values.first` - the member
  /// declared first, since its index is the `0` an unwritten field holds.
  InitialPointer<E> hasEnum<E extends Enum>(List<E> values, [E? initialValue]);

  InitialPointer<double> hasFloat32([double initialValue = 0.0]);
  InitialPointer<double> hasFloat64([double initialValue = 0.0]);
  InitialPointer<int?> optUint1([int? initialValue]);
  InitialPointer<int?> optInt1([int? initialValue]);
  InitialPointer<int?> optUint2([int? initialValue]);
  InitialPointer<int?> optInt2([int? initialValue]);
  InitialPointer<int?> optUint4([int? initialValue]);
  InitialPointer<int?> optInt4([int? initialValue]);
  InitialPointer<int?> optUint8([int? initialValue]);
  InitialPointer<int?> optInt8([int? initialValue]);
  InitialPointer<int?> optUint16([int? initialValue]);
  InitialPointer<int?> optInt16([int? initialValue]);
  InitialPointer<int?> optUint32([int? initialValue]);
  InitialPointer<int?> optInt32([int? initialValue]);
  InitialPointer<int?> optUint64([int? initialValue]);
  InitialPointer<int?> optInt64([int? initialValue]);

  /// A column holding an [Entity] handle or `null` - [hasEntity]'s storage
  /// with a presence flag in front of it, so "no target" is a state of its
  /// own, with no handle reserved as a sentinel.
  ///
  /// This is what a link between entities usually wants. [hasEntity]'s
  /// unwritten value is `Entity(0)`, a real address (archetype 0, page 0,
  /// row 0) and not a "nothing here"; here an unwritten column reads `null`,
  /// and `Entity(0)` stored in it reads back as itself.
  ///
  /// With no [initialValue] a fresh row reads `null`. Pass one and every
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
  InitialPointer<Entity?> optEntity([Entity? initialValue]);

  InitialPointer<double?> optFloat32([double? initialValue]);
  InitialPointer<double?> optFloat64([double? initialValue]);
  /// A fixed-length inline array of [length] [element]s, one run per entity's
  /// row.
  ///
  /// The element is an argument, so one method covers every width and every
  /// [IntRepresentation]:
  ///
  /// ```dart
  /// textCodeUnits = data.hasArray(.uint16, capacity);   // DataArrayPointer<int>
  /// vertices      = data.hasArray(.float64, 8);         // DataArrayPointer<double>
  /// frames        = data.hasArray(const SpriteFrames(), 4, SpriteFrame.full);
  /// ```
  ///
  /// The pointer's `T` follows from the element: [DataElement.uint16] gives a
  /// `DataArrayPointer<int>`, [DataElement.float64] a
  /// `DataArrayPointer<double>`, and a representation of `SpriteFrame` a
  /// `DataArrayPointer<SpriteFrame>`. A field and its element are therefore
  /// type-checked against each other where the column is declared.
  ///
  /// Every element of a fresh row starts at [initialValue]. A native width
  /// takes `0` or `0.0` when it is left out; an [IntRepresentation] element
  /// has no such value to fall back on and one is required, since the bits a
  /// representation has no meaning for would be read back through
  /// [IntRepresentation.unpack] and throw.
  ///
  /// Use [hasArrayOf] when the elements start at *different* values.
  DataArrayPointer<T> hasArray<T>(
    DataElement<T> element,
    int length, [
    T? initialValue,
  ]);

  /// [hasArray] with one initial value per element: element `i` of a fresh
  /// row holds `initialValues[i]`, and any slot past the end of
  /// [initialValues] holds the element's own zero.
  ///
  /// [length] is the storage capacity, as it is for [hasArray], so an array
  /// can reserve slots beyond the values it starts with and have them written
  /// per entity later. More values than the array can hold is an error.
  ///
  /// `goo2d`'s `hasPolygonCollider(points: ...)` is the reference use: a
  /// prefab whose outline is fixed states it where it declares the field,
  /// instead of writing every vertex from `onEntityMounted`.
  ///
  /// An [IntRepresentation] element may be used here, and the slots past
  /// [initialValues] are then the case [hasArray] refuses - so pass one value
  /// per element for a representation, or reach for [optArray] and let the
  /// unwritten slots read `null`.
  DataArrayPointer<T> hasArrayOf<T>(
    DataElement<T> element,
    int length,
    List<T> initialValues,
  );

  /// [hasArray]'s nullable twin: every element is a value or `null`,
  /// independently of its neighbours.
  ///
  /// Nullability stays on the method and off the element. A `DataElement` is
  /// one thing - a width, or a representation - and the two entry points here
  /// each take a plain one, so a nullable counterpart for every element does
  /// not have to exist.
  ///
  /// Each element carries its own presence flag ahead of its value, so this
  /// costs more row than [hasArray] does - see `data_layout.dart`'s
  /// `_OptionalArrayField`. With no [initialValue] every element of a fresh
  /// row reads `null`.
  DataArrayPointer<T?> optArray<T>(
    DataElement<T> element,
    int length, [
    T? initialValue,
  ]);

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
  /// makes a mismatched field/representation a compile error instead of a
  /// read-time `StateError`.
  ///
  /// The field is [IntRepresentation.bitWidth] bits wide, so a representation
  /// that only ever hands out a few hundred values costs a row a byte or two,
  /// not a fixed four.
  PackedPointer<T> hasPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    T initialValue,
  );
  DataPointer<T?> optPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr, [
    T? initialValue,
  ]);

  /// The camera-view column: [optPacked] against the table the registering
  /// scene owns, without the declaration having to name it.
  ///
  /// It exists because that table is the one representation in the engine
  /// that a declaration cannot be handed. Every other packed column names its
  /// [IntRepresentation] at the declare site - `hasPacked(const
  /// SpriteFrames(), ...)` - and that works because the representation is a
  /// value the writer of the line already has. A [CameraViewTable] is not:
  /// there is one per game, it reaches a component through the scene, and a
  /// field initialiser has no scene. `late final DataPointer<CameraView?>
  /// cameraView;` filled in from `describeStruct` was the shape that fell out
  /// of that, and it is a double declaration - the thing this engine's
  /// declaration rules forbid.
  ///
  /// Nothing about the table is a declaration input. It contributes no width
  /// ([CameraViewTable.viewBitWidth] is 8, a constant on the class, not a
  /// property of the instance) and no initial value, and a *write* never
  /// consults it - [CameraView.pack] is its own index. Only a read does. So
  /// the table is the resolution environment and not part of what is being
  /// declared, and naming the column kind is enough: the table comes from
  /// `ArchetypeStorage.scene`, which the registering scene set one call
  /// before the prefab's constructor ran.
  DataPointer<CameraView?> optCameraView([CameraView? initialValue]);

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
  DataPointer<T> hasHeapObject<T>(T Function() initialValue);

  /// Nullable heap-object field. No default parameter: an unset element is
  /// `null`, which is already the only sensible "nothing here yet" for a
  /// reference that is assigned dynamically at runtime.
  DataPointer<T?> optHeapObject<T>();
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
/// prefix dropped and returns exactly what that returns, so `speed[entity]`
/// is the same read it was when the field was a `late final` assigned in
/// `describeStruct`. There is no wrapper object and nothing extra on the read
/// path.
///
/// # Nothing is open around the call
///
/// A `Field.*` static reaches no archetype, no scene and no allocation
/// cursor. It builds the column and hands it back; the row space is reserved
/// afterwards, once the whole set of a class's declarations is known. Two
/// things depend on that being the order: [optCameraView] names a table that
/// belongs to the scene, which a field initialiser cannot reach, and
/// [DataArrayPointer.length] can still move.
///
/// It also leaves the declaration nowhere to be misattributed to. These used
/// to reach an ambient descriptor, so an initialiser that ran late - a `late`
/// field, a `static`, a top-level variable - declared its column onto
/// whichever owner happened to be under construction at that moment. There is
/// no innermost entry to land on now: what a class declares is what its own
/// fields hold.
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
/// [boolean] and not `bool` for a related reason, one level down: a
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
/// declared also uses `describeStruct`, but to move the default, not to
/// declare anything - see [InitialPointer.initialValue]. Declaring the name a
/// second time would not do it.
///
/// # Two mixins declaring the same field name are silent here
///
/// Components are mixins, so `speed` declared by two of them is an override,
/// not an error: the later one in the `with` clause wins. Written as
/// `describeStruct` assignments it is caught by accident - both bodies assign
/// the same `late final`, and the second throws a `LateInitializationError`
/// before the game runs. An eager initialiser assigns nothing, so both columns
/// are allocated, the row grows by both, and one of them is unreachable for the
/// life of the process. Measured: 128 bits of row against 64, `speed[entity]`
/// reading the second mixin's column, no error anywhere.
///
/// Prefix a published component's columns the way `Transform2D` prefixes
/// `transformOffsetX`. Catching it properly is a build-time check over the
/// mixin closure, which is issue #58.
abstract final class Field {
  /// See [DataDescriptor.hasBool].
  static InitialPointer<bool> boolean([bool initialValue = false]) =>
      declaredColumns.hasBool(initialValue);

  static InitialPointer<int> uint1([int initialValue = 0]) =>
      declaredColumns.hasUint1(initialValue);
  static InitialPointer<int> int1([int initialValue = 0]) =>
      declaredColumns.hasInt1(initialValue);
  static InitialPointer<int> uint2([int initialValue = 0]) =>
      declaredColumns.hasUint2(initialValue);
  static InitialPointer<int> int2([int initialValue = 0]) =>
      declaredColumns.hasInt2(initialValue);
  static InitialPointer<int> uint4([int initialValue = 0]) =>
      declaredColumns.hasUint4(initialValue);
  static InitialPointer<int> int4([int initialValue = 0]) =>
      declaredColumns.hasInt4(initialValue);
  static InitialPointer<int> uint8([int initialValue = 0]) =>
      declaredColumns.hasUint8(initialValue);
  static InitialPointer<int> int8([int initialValue = 0]) =>
      declaredColumns.hasInt8(initialValue);
  static InitialPointer<int> uint16([int initialValue = 0]) =>
      declaredColumns.hasUint16(initialValue);
  static InitialPointer<int> int16([int initialValue = 0]) =>
      declaredColumns.hasInt16(initialValue);
  static InitialPointer<int> uint32([int initialValue = 0]) =>
      declaredColumns.hasUint32(initialValue);
  static InitialPointer<int> int32([int initialValue = 0]) =>
      declaredColumns.hasInt32(initialValue);
  static InitialPointer<int> uint64([int initialValue = 0]) =>
      declaredColumns.hasUint64(initialValue);
  static InitialPointer<int> int64([int initialValue = 0]) =>
      declaredColumns.hasInt64(initialValue);

  /// See [DataDescriptor.hasEntity], including its warning that a stored
  /// handle outlives the entity it names.
  static InitialPointer<Entity> entity([Entity? initialValue]) =>
      declaredColumns.hasEntity(initialValue);

  /// See [DataDescriptor.hasEnum]. Named `enumOf` because `enum` is a
  /// keyword.
  static InitialPointer<E> enumOf<E extends Enum>(
    List<E> values, [
    E? initialValue,
  ]) => declaredColumns.hasEnum<E>(values, initialValue);

  static InitialPointer<double> float32([double initialValue = 0.0]) =>
      declaredColumns.hasFloat32(initialValue);
  static InitialPointer<double> float64([double initialValue = 0.0]) =>
      declaredColumns.hasFloat64(initialValue);

  static InitialPointer<int?> optUint1([int? initialValue]) =>
      declaredColumns.optUint1(initialValue);
  static InitialPointer<int?> optInt1([int? initialValue]) =>
      declaredColumns.optInt1(initialValue);
  static InitialPointer<int?> optUint2([int? initialValue]) =>
      declaredColumns.optUint2(initialValue);
  static InitialPointer<int?> optInt2([int? initialValue]) =>
      declaredColumns.optInt2(initialValue);
  static InitialPointer<int?> optUint4([int? initialValue]) =>
      declaredColumns.optUint4(initialValue);
  static InitialPointer<int?> optInt4([int? initialValue]) =>
      declaredColumns.optInt4(initialValue);
  static InitialPointer<int?> optUint8([int? initialValue]) =>
      declaredColumns.optUint8(initialValue);
  static InitialPointer<int?> optInt8([int? initialValue]) =>
      declaredColumns.optInt8(initialValue);
  static InitialPointer<int?> optUint16([int? initialValue]) =>
      declaredColumns.optUint16(initialValue);
  static InitialPointer<int?> optInt16([int? initialValue]) =>
      declaredColumns.optInt16(initialValue);
  static InitialPointer<int?> optUint32([int? initialValue]) =>
      declaredColumns.optUint32(initialValue);
  static InitialPointer<int?> optInt32([int? initialValue]) =>
      declaredColumns.optInt32(initialValue);
  static InitialPointer<int?> optUint64([int? initialValue]) =>
      declaredColumns.optUint64(initialValue);
  static InitialPointer<int?> optInt64([int? initialValue]) =>
      declaredColumns.optInt64(initialValue);

  /// See [DataDescriptor.optEntity] - the spelling a link that may be absent
  /// wants.
  static InitialPointer<Entity?> optEntity([Entity? initialValue]) =>
      declaredColumns.optEntity(initialValue);

  static InitialPointer<double?> optFloat32([double? initialValue]) =>
      declaredColumns.optFloat32(initialValue);
  static InitialPointer<double?> optFloat64([double? initialValue]) =>
      declaredColumns.optFloat64(initialValue);

  /// See [DataDescriptor.hasArray] - a fixed-length run of [element], with
  /// the element named as an argument.
  ///
  /// ```dart
  /// final vertices = Field.array(.float64, 8);
  /// final frames = Field.array(const SpriteFrames(), 4, SpriteFrame.full);
  /// ```
  static DataArrayPointer<T> array<T>(
    DataElement<T> element,
    int length, [
    T? initialValue,
  ]) => declaredColumns.hasArray<T>(element, length, initialValue);

  /// See [DataDescriptor.hasArrayOf] - element `i` starts at
  /// `initialValues[i]`.
  static DataArrayPointer<T> arrayOf<T>(
    DataElement<T> element,
    int length,
    List<T> initialValues,
  ) => declaredColumns.hasArrayOf<T>(element, length, initialValues);

  /// See [DataDescriptor.optArray].
  static DataArrayPointer<T?> optArray<T>(
    DataElement<T> element,
    int length, [
    T? initialValue,
  ]) => declaredColumns.optArray<T>(element, length, initialValue);

  /// See [DataDescriptor.hasPacked] - a value stored as the int its
  /// [IntRepresentation] packs it into.
  static PackedPointer<T> packed<T extends IntRepresentable>(
    IntRepresentation<T> repr,
    T initialValue,
  ) => declaredColumns.hasPacked<T>(repr, initialValue);

  /// See [DataDescriptor.optPacked].
  static DataPointer<T?> optPacked<T extends IntRepresentable>(
    IntRepresentation<T> repr, [
    T? initialValue,
  ]) => declaredColumns.optPacked<T>(repr, initialValue);

  /// See [DataDescriptor.optCameraView] - the one packed column whose
  /// representation the declaration does not name, because it belongs to the
  /// scene rather than to the field.
  static DataPointer<CameraView?> optCameraView([CameraView? initialValue]) =>
      declaredColumns.optCameraView(initialValue);

  /// See [DataDescriptor.hasHeapObject], including why the value it stores
  /// means nothing on a second isolate.
  static DataPointer<T> heapObject<T>(T Function() initialValue) =>
      declaredColumns.hasHeapObject<T>(initialValue);

  /// See [DataDescriptor.optHeapObject].
  static DataPointer<T?> optHeapObject<T>() =>
      declaredColumns.optHeapObject<T>();

}

abstract class DataPointer<T> implements ScannableField {
  const DataPointer();

  T operator [](Entity instance);
  void operator []=(Entity instance, T newValue);

  /// [operator []], but reading the slot this tick is **writing** instead of
  /// the last published one - so it sees writes made earlier in this same
  /// tick, which an ordinary read cannot.
  ///
  /// # This is for structural mutation, and nothing else
  ///
  /// A *system* reading uncommitted state is the thing the
  /// no-specialised-variant rule exists to forbid, and this does not change
  /// that. What it is for is the narrow case of a mutation that has to read
  /// back the structure **it is itself editing**, within one tick:
  /// `Parent.addChild` reads `parentLastChild` to append to the chain, and two
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
  /// # Which columns answer
  ///
  /// Three, and only these three:
  ///
  /// - `float64`, for composing a just-spawned transform.
  /// - `optInt64`.
  /// - `optEntity`, the optional-entity fields the hierarchy links are made
  ///   of.
  ///
  /// Every other column kind throws [UnsupportedError], including the ones
  /// that look like the three above - `optFloat64` and `optInt32` are
  /// optional columns whose value half cannot answer, and `hasInt64` is an
  /// `int64` without the optional wrapper. Reach for one of those and the
  /// failure names the field class that could not answer.
  ///
  /// Refusing rather than quietly returning the published value is the point:
  /// a silently-published answer here is exactly the bug this exists to fix.
  /// A new structural field that needs this gets an implementation, not a
  /// fallback.
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
  /// Implementers **extend** `DataPointer` instead of implementing it, purely
  /// so this default is inherited and not copied per implementation - one home
  /// for the behaviour (the one-fact-one-place rule).
  DataBinding<T> bind(Entity instance) => _DataBinding(this, instance);
}

/// A column whose initial value a prefab can still change while the
/// archetype is being described.
///
/// A value written where the column is declared - `Field.float64(60)`, or
/// `data.hasFloat64(60)` - is the same for every archetype that mixes the
/// component in. Setting [initialValue] in a prefab's own `describeStruct`
/// changes it for that archetype and no other:
///
/// ```dart
/// class Eye extends EntityStruct with Transform3D, WorldTransform3D, Camera3D {
///   @override
///   void describeStruct(DataDescriptor data) {
///     super.describeStruct(data);
///     near.initialValue = 10;
///     far.initialValue *= 2;
///   }
/// }
/// ```
///
/// [initialValue] reads as well as writes, which is what the second line
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
/// Every column whose initial value is a plain stored value and can be moved
/// afterwards: the integer widths, the floats, `bool`, an enum member, an
/// `Entity` handle, and the nullable form of each. Packed columns,
/// heap-object columns and arrays are left out - see [initialValue].
abstract class InitialPointer<T> extends DataPointer<T> {
  const InitialPointer();

  /// The value a freshly allocated row starts with - what the column was
  /// declared with, or whatever a prefab has since moved it to.
  ///
  /// Reading it never throws. Writing it does once the archetype is sealed,
  /// which happens as soon as `describeStruct` has returned.
  /// `ArchetypeStorage.seal` builds one prototype row holding every column's
  /// initial value and memcpy's it into each row allocated afterwards, so
  /// after `seal` the stored value is still exactly what every new row will
  /// hold - true, and worth being able to ask about - while a *write* to it
  /// could no longer reach the prototype and would be a lie.
  ///
  /// Having both halves is what lets a prefab adjust an inherited value
  /// instead of restating it:
  ///
  /// ```dart
  /// cameraFar.initialValue *= 2;   // twice whatever Camera3D chose
  /// hp.initialValue += 50;         // the component's number, plus fifty
  /// ```
  ///
  /// Neither is a write to any entity. `cameraNear.initialValue = 10` changes
  /// what the *next* row starts with; `cameraNear[entity] = 10` changes one
  /// entity now.
  ///
  /// # Why packed, heap-object and array columns have neither half
  ///
  /// Every column kind takes an initial value at declaration, and every one
  /// of them is stamped into the prototype row at `seal`; what these three
  /// lack is a way to read that value back and move it afterwards, each for
  /// its own reason. A heap-object column's is a `T Function()` - a factory
  /// whose one result every row of the archetype then shares, on whichever
  /// isolate ran it - so a uniform `T initialValue` cannot describe it: the
  /// getter would have to hand back either the factory or its result, and
  /// those are different things. A packed column's is a plain `T`, the same
  /// shape as every scalar here, and nothing but demand keeps it off this
  /// type. Arrays are excluded by construction: a `DataArrayPointer` is not
  /// a [DataPointer] at all.
  T get initialValue;
  set initialValue(T newValue);
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
/// two integers to a method on the one long-lived pointer object that already
/// holds the layout. There is no two-step subscript here, and no plan for
/// one.
abstract class DataArrayPointer<T> implements ScannableField {
  /// Number of elements per entity.
  ///
  /// Settable in the same window [InitialPointer.initialValue] is settable
  /// in: reading it never throws, and writing it throws once the column has
  /// been given its row space, which happens after the describe passes have
  /// run and before the archetype is sealed. Until then nothing has been
  /// reserved, so a component can declare a length its prefabs adjust:
  ///
  /// ```dart
  /// final textCodeUnits = Field.array(.uint16, 32);   // in the component
  /// textCodeUnits.length = 8;                         // in a prefab
  /// ```
  ///
  /// A length sizes the column, so this is only implementable because a
  /// declaration reserves nothing where it is written - see `Field`. While
  /// `Field.array` took its elements from the row cursor on the spot, there
  /// was nothing left to move: the slots were already spoken for and the next
  /// column sat immediately behind them.
  ///
  /// That is also what a length has instead of an override point. A `int get
  /// textCapacity => 8` a component read back while declaring would be
  /// configuration that sizes a column, and a value that sizes a column is a
  /// declaration - it belongs on the declaration, where a reader finds it
  /// next to the storage it costs, and where a field initialiser (which
  /// cannot reach `this`) does not have to.
  int get length;
  set length(int newLength);

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

/// What one slot of an inline array holds - a native width, or an
/// [IntRepresentation] - as a value a declaration passes to
/// [DataDescriptor.hasArray] instead of a name burned into a method.
///
/// ```dart
/// data.hasArray(.uint16, capacity);
/// data.hasArray(.float64, 8);
/// data.hasArray(const SpriteFrames(), 4, SpriteFrame.full);
/// ```
///
/// The type argument is what a declaration reads back: `.uint16` is a
/// `DataElement<int>` and gives a `DataArrayPointer<int>`, `.float64` a
/// `DataElement<double>` and a `DataArrayPointer<double>`. An enum cannot
/// carry that - an enum case has no type argument of its own - so the widths
/// are static constants on a generic class, which is also what makes the dot
/// shorthand above resolve.
///
/// # Sealed, and still open to a representation
///
/// Sealing restricts *direct* subtyping, which is what makes the declare-time
/// dispatch in `data_layout.dart` an exhaustive `switch` and not an `is`
/// chain. It does not close the type off: [IntRepresentation] implements this
/// interface, and a representation declared in any library is a
/// `DataElement` through it, with nothing wrapping it.
///
/// # Adding a width
///
/// One constant here. There is no second declaration in `data_layout.dart`
/// and no third on [Field] - both reach every width through [bitWidth] and
/// the two element kinds below.
sealed class DataElement<T> {
  const DataElement();

  /// How many bits one element takes, `1..64`.
  int get bitWidth;

  static const DataElement<int> uint1 = IntElement._(1, signed: false);
  static const DataElement<int> int1 = IntElement._(1, signed: true);
  static const DataElement<int> uint2 = IntElement._(2, signed: false);
  static const DataElement<int> int2 = IntElement._(2, signed: true);
  static const DataElement<int> uint4 = IntElement._(4, signed: false);
  static const DataElement<int> int4 = IntElement._(4, signed: true);
  static const DataElement<int> uint8 = IntElement._(8, signed: false);
  static const DataElement<int> int8 = IntElement._(8, signed: true);
  static const DataElement<int> uint16 = IntElement._(16, signed: false);
  static const DataElement<int> int16 = IntElement._(16, signed: true);
  static const DataElement<int> uint32 = IntElement._(32, signed: false);
  static const DataElement<int> int32 = IntElement._(32, signed: true);
  static const DataElement<double> float32 = FloatElement._(32);
  static const DataElement<double> float64 = FloatElement._(64);
}

/// A native integer element - one of [DataElement]'s `uintN`/`intN`
/// constants, and nothing a caller constructs.
///
/// [signed] is what separates `.int8` from `.uint8` at the same [bitWidth],
/// and it is read once, where the array is declared.
final class IntElement extends DataElement<int> {
  const IntElement._(this.bitWidth, {required this.signed});

  @override
  final int bitWidth;

  /// Whether the stored bits are read back as two's complement.
  final bool signed;
}

/// A native floating-point element - [DataElement.float32] or
/// [DataElement.float64], and nothing a caller constructs.
final class FloatElement extends DataElement<double> {
  const FloatElement._(this.bitWidth);

  @override
  final int bitWidth;
}

/// A thing that can be reduced to the integer a component row stores, and
/// nothing more.
///
/// The int implies **nothing on its own** - not that it names an asset, not
/// that it names a camera view, not that it names anything at all. It is
/// meaningful only against the [IntRepresentation] that produced the pairing,
/// and that representation decides what it means.
///
/// The int is scoped to that one representation, never to a process-wide
/// address space where "address 3" would be unanswerable without knowing
/// everything else registered. Nor is it always an address: a
/// [SpriteFrame]-style value packs into its int outright, with nothing stored
/// anywhere and nothing to look up. That is why the other half of the pair
/// says `unpack` and not `resolve`.
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
/// Generic in the *class* and not the method, so a field and its
/// representation are type-checked against each other at the declare site
/// instead of blowing up at read time. A representation whose population is
/// heterogeneous (an asset table holding `Asset<Texture>` and
/// `Asset<AudioClip>`) vends a typed view per payload type instead of being
/// one representation for all of them - see `Assets.of`.
abstract interface class IntRepresentation<T extends IntRepresentable>
    implements DataElement<T> {
  /// How many bits a column of [T] needs, `1..64`.
  ///
  /// A declare-time constant of the representation, never of an individual
  /// value: the layout is computed once and every entity in the archetype
  /// shares it, so a per-instance width could not be honoured.
  ///
  /// Nothing constrains how it is written. `good_cli` has no pass that reads
  /// a width at build time: both of its scans parse and never resolve, and
  /// `struct_scan.dart` records the measurement that settled that - dropping
  /// resolution took the scan from 826ms to 272ms. A pass that hoisted layout
  /// would need constant evaluation, which needs resolution, so whoever
  /// writes one decides what it can read; this is not a constraint on a
  /// representation today.
  @override
  int get bitWidth;

  /// The value [bits] stands for, or a `StateError` naming what went wrong -
  /// never a neighbouring value, and never null.
  T unpack(int bits);

  /// [unpack], but null when [bits] stands for nothing.
  T? tryUnpack(int bits);
}
