import 'dart:async';
import 'dart:typed_data';

import 'package:goo2d/src/data/object.dart';
import 'package:meta/meta.dart';

typedef DataFactory<T extends EntityData> = T Function();
typedef DataInit<T extends EntityData> = FutureOr<DataFactory<T>>;

// ---------------------------------------------------------------------------
// DataFactoryWithInit — FutureOr trick (mirrors ComponentFactoryWithParams)
// ---------------------------------------------------------------------------

mixin _FakeDataFuture<T extends EntityData> implements Future<DataFactory<T>> {
  DataFactory<T> get _rawFactory;

  @override
  Stream<DataFactory<T>> asStream() => Stream.value(_rawFactory);

  @override
  Future<DataFactory<T>> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => this;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(DataFactory<T> value) onValue, {
    Function? onError,
  }) => Future.value(onValue(_rawFactory));

  @override
  Future<DataFactory<T>> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) => this;

  @override
  Future<DataFactory<T>> whenComplete(FutureOr<dynamic> Function() action) {
    action();
    return this;
  }
}

class DataFactoryWithInit<T extends EntityData>
    with _FakeDataFuture<T>
    implements Future<DataFactory<T>> {
  @override
  final DataFactory<T> _rawFactory;
  final void Function(T singleton, QueryResult cursor)? _init;

  const DataFactoryWithInit(
    this._rawFactory, {
    void Function(T, QueryResult)? init,
  }) : _init = init;

  /// The underlying factory, accessible outside this library.
  DataFactory<T> get dataFactory => _rawFactory;

  void applyInit(EntityData singleton, QueryResult cursor) =>
      _init?.call(singleton as T, cursor);
}

typedef DataFactoryInitializer<T extends EntityData> =
    void Function(T singleton, QueryResult cursor);

extension DataFactoryInitExtension<T extends EntityData> on DataFactory<T> {
  DataFactoryWithInit<T> withInit(
    DataFactoryInitializer<T> init,
  ) => DataFactoryWithInit(this, init: init);
}

// ---------------------------------------------------------------------------
// EntityData, Field
// ---------------------------------------------------------------------------

abstract class EntityData implements Queryable, Type {
  late int _bitmask;
  void describe(DataDescriptor descriptor);
}

@internal
void entityDataAssignBitmask(EntityData data, int bitmask) {
  data._bitmask = bitmask;
}

@internal
int entityDataGetBitmask(EntityData data) => data._bitmask;

abstract class Field<T> {
  T get(QueryResult cursor);
  void set(QueryResult cursor, T value);
  @internal
  T getSlot(int slot);
  @internal
  void setSlot(int slot, T value);
}

// ---------------------------------------------------------------------------
// DataDescriptor — declares fields for an EntityData type
// ---------------------------------------------------------------------------

abstract class DataDescriptor {
  Field<int> newInt8({int initialValue = 0});
  Field<int> newInt16({int initialValue = 0});
  Field<int> newInt32({int initialValue = 0});
  Field<int> newInt64({int initialValue = 0});
  Field<int> newUint8({int initialValue = 0});
  Field<int> newUint16({int initialValue = 0});
  Field<int> newUint32({int initialValue = 0});
  Field<int> newUint64({int initialValue = 0});
  Field<double> newFloat32({double initialValue = 0.0});
  Field<double> newFloat64({double initialValue = 0.0});
  Field<T> newField<T>(FieldParser<T> parser, {required T initialValue});
  Field<T?> newFieldNullable<T>(FieldParser<T> parser, {T? initialValue});

  /// Stores per-entity Dart object references in a [List<Object?>].
  ///
  /// Unlike every other field type, heap fields bypass the compact TypedData
  /// byte-buffer layout entirely. Each live entity holds a plain Dart reference;
  /// GC pressure scales with entity count, and cache locality is lost.
  ///
  /// [withInit] works normally — the command buffer captures the value via an
  /// integer index into a transient side-channel list that is cleared after each
  /// flush. For entities created without [withInit], or for recycled slots,
  /// [initialValue] is used instead.
  ///
  /// Prefer [newField] with a [FieldParser] for any type that can be serialised
  /// to bytes. Use [newHeap] only when serialisation is genuinely impossible or
  /// impractical (e.g. closures, streams, native resources).
  Field<T> newHeap<T>({required T initialValue});

  // Sub-byte packed fields — multiple fields share one Uint8 per entity
  Field<int> newBit({int initialValue = 0}); // 0 or 1
  Field<bool> newBool({bool initialValue = false});
  Field<int> newInt2({int initialValue = 0}); // -2..1
  Field<int> newUint2({int initialValue = 0}); // 0..3
  Field<int> newInt4({int initialValue = 0}); // -8..7
  Field<int> newUint4({int initialValue = 0}); // 0..15

  // ---------------------------------------------------------------------------
  // Nullable — Form 1: interleaved double-stride (int only)
  //   list[s*2]=tag (0=null), list[s*2+1]=value; packed types share same byte
  // ---------------------------------------------------------------------------
  Field<int?> newInt8Nullable({int? initialValue});
  Field<int?> newInt16Nullable({int? initialValue});
  Field<int?> newInt32Nullable({int? initialValue});
  Field<int?> newInt64Nullable({int? initialValue});
  Field<int?> newUint8Nullable({int? initialValue});
  Field<int?> newUint16Nullable({int? initialValue});
  Field<int?> newUint32Nullable({int? initialValue});
  Field<int?> newUint64Nullable({int? initialValue});
  // packed int nullable (value bits + tag bits in same packed byte)
  Field<int?> newBitNullable({int? initialValue});
  Field<int?> newInt2Nullable({int? initialValue});
  Field<int?> newUint2Nullable({int? initialValue});
  Field<int?> newInt4Nullable({int? initialValue});
  Field<int?> newUint4Nullable({int? initialValue});
  // bool specialization: 1 value bit + 1 tag bit in packed byte
  Field<bool?> newBoolNullable({bool? initialValue});

  // ---------------------------------------------------------------------------
  // Nullable — Form 2: stolen-bit sentinel (int only, no extra storage)
  //   null encoded as typeMinValue (signed) or typeMaxValue (unsigned)
  // ---------------------------------------------------------------------------
  Field<int?> newInt7Nullable({
    int? initialValue,
  }); // uses Int8List, sentinel=-128
  Field<int?> newInt15Nullable({
    int? initialValue,
  }); // Int16List, sentinel=-32768
  Field<int?> newInt31Nullable({
    int? initialValue,
  }); // Int32List, sentinel=minInt32
  Field<int?> newInt63Nullable({
    int? initialValue,
  }); // Int64List, sentinel=minInt64
  Field<int?> newUint7Nullable({int? initialValue}); // Uint8List, sentinel=255
  Field<int?> newUint15Nullable({
    int? initialValue,
  }); // Uint16List, sentinel=65535
  Field<int?> newUint31Nullable({
    int? initialValue,
  }); // Uint32List, sentinel=maxUint32
  Field<int?> newUint63Nullable({int? initialValue}); // Uint64List, sentinel=-1

  // ---------------------------------------------------------------------------
  // Nullable — Form 3: tagged (all numeric types, separate bit array in pool)
  //   pool: 1 bit per slot in _NullTagStorage; capture: 1 flag byte after value
  // ---------------------------------------------------------------------------
  Field<int?> newInt8Tagged({int? initialValue});
  Field<int?> newInt16Tagged({int? initialValue});
  Field<int?> newInt32Tagged({int? initialValue});
  Field<int?> newInt64Tagged({int? initialValue});
  Field<int?> newUint8Tagged({int? initialValue});
  Field<int?> newUint16Tagged({int? initialValue});
  Field<int?> newUint32Tagged({int? initialValue});
  Field<int?> newUint64Tagged({int? initialValue});
  Field<double?> newFloat32Tagged({double? initialValue});
  Field<double?> newFloat64Tagged({double? initialValue});
  Field<bool?> newBoolTagged({bool? initialValue});
  Field<int?> newBitTagged({int? initialValue});
  Field<int?> newInt2Tagged({int? initialValue});
  Field<int?> newUint2Tagged({int? initialValue});
  Field<int?> newInt4Tagged({int? initialValue});
  Field<int?> newUint4Tagged({int? initialValue});

  // ---------------------------------------------------------------------------
  // List view fields — zero-copy TypedData views directly into pool memory.
  // WARNING: views are invalidated after any pool growth (entity creation that
  // triggers capacity expansion). Do not hold views across such operations.
  // ---------------------------------------------------------------------------
  Field<Int8List> newInt8ListView(int count, {Int8List? initialValue});
  Field<Int8List?> newInt8ListViewNullable(int count, {Int8List? initialValue});
  Field<Int16List> newInt16ListView(int count, {Int16List? initialValue});
  Field<Int16List?> newInt16ListViewNullable(
    int count, {
    Int16List? initialValue,
  });
  Field<Int32List> newInt32ListView(int count, {Int32List? initialValue});
  Field<Int32List?> newInt32ListViewNullable(
    int count, {
    Int32List? initialValue,
  });
  Field<Int64List> newInt64ListView(int count, {Int64List? initialValue});
  Field<Int64List?> newInt64ListViewNullable(
    int count, {
    Int64List? initialValue,
  });
  Field<Uint8List> newUint8ListView(int count, {Uint8List? initialValue});
  Field<Uint8List?> newUint8ListViewNullable(
    int count, {
    Uint8List? initialValue,
  });
  Field<Uint16List> newUint16ListView(int count, {Uint16List? initialValue});
  Field<Uint16List?> newUint16ListViewNullable(
    int count, {
    Uint16List? initialValue,
  });
  Field<Uint32List> newUint32ListView(int count, {Uint32List? initialValue});
  Field<Uint32List?> newUint32ListViewNullable(
    int count, {
    Uint32List? initialValue,
  });
  Field<Uint64List> newUint64ListView(int count, {Uint64List? initialValue});
  Field<Uint64List?> newUint64ListViewNullable(
    int count, {
    Uint64List? initialValue,
  });
  Field<Float32List> newFloat32ListView(int count, {Float32List? initialValue});
  Field<Float32List?> newFloat32ListViewNullable(
    int count, {
    Float32List? initialValue,
  });
  Field<Float64List> newFloat64ListView(int count, {Float64List? initialValue});
  Field<Float64List?> newFloat64ListViewNullable(
    int count, {
    Float64List? initialValue,
  });

  // ---------------------------------------------------------------------------
  // Copy-list fields — fresh TypedData copy on every read.
  // Mutations to the returned value do NOT affect pool data.
  // ---------------------------------------------------------------------------
  Field<Int8List> newInt8List(int count, {Int8List? initialValue});
  Field<Int8List?> newInt8ListNullable(int count, {Int8List? initialValue});
  Field<Int16List> newInt16List(int count, {Int16List? initialValue});
  Field<Int16List?> newInt16ListNullable(int count, {Int16List? initialValue});
  Field<Int32List> newInt32List(int count, {Int32List? initialValue});
  Field<Int32List?> newInt32ListNullable(int count, {Int32List? initialValue});
  Field<Int64List> newInt64List(int count, {Int64List? initialValue});
  Field<Int64List?> newInt64ListNullable(int count, {Int64List? initialValue});
  Field<Uint8List> newUint8List(int count, {Uint8List? initialValue});
  Field<Uint8List?> newUint8ListNullable(int count, {Uint8List? initialValue});
  Field<Uint16List> newUint16List(int count, {Uint16List? initialValue});
  Field<Uint16List?> newUint16ListNullable(
    int count, {
    Uint16List? initialValue,
  });
  Field<Uint32List> newUint32List(int count, {Uint32List? initialValue});
  Field<Uint32List?> newUint32ListNullable(
    int count, {
    Uint32List? initialValue,
  });
  Field<Uint64List> newUint64List(int count, {Uint64List? initialValue});
  Field<Uint64List?> newUint64ListNullable(
    int count, {
    Uint64List? initialValue,
  });
  Field<Float32List> newFloat32List(int count, {Float32List? initialValue});
  Field<Float32List?> newFloat32ListNullable(
    int count, {
    Float32List? initialValue,
  });
  Field<Float64List> newFloat64List(int count, {Float64List? initialValue});
  Field<Float64List?> newFloat64ListNullable(
    int count, {
    Float64List? initialValue,
  });
}

// ---------------------------------------------------------------------------
// FieldParser, FieldDescriptor, FieldReader, FieldWriter
// ---------------------------------------------------------------------------

abstract class FieldParser<T> {
  void describe(FieldDescriptor descriptor);
  T read(FieldReader reader);
  void write(T value, FieldWriter writer);
}

/// Mixin marking that [read] returns a TypedData view into the reader's
/// backing buffer. [_ByteDataWriter.writeField] skips copying when the
/// returned value is detected to be the same buffer region (identity check).
mixin MutableFieldParser<T> on FieldParser<T> {}

abstract class FieldDescriptor {
  void addInt8();
  void addInt16();
  void addInt32();
  void addInt64();
  void addUint8();
  void addUint16();
  void addUint32();
  void addUint64();
  void addFloat32();
  void addFloat64();
  void addField<T>(FieldParser<T> parser);
  void addNullableField<T>(FieldParser<T> parser);
  // Sub-byte
  void addBit();
  void addBool();
  void addInt2();
  void addUint2();
  void addInt4();
  void addUint4();

  // Nullable word types (double-stride: tag N bytes + value N bytes)
  void addInt8Nullable();
  void addInt16Nullable();
  void addInt32Nullable();
  void addInt64Nullable();
  void addUint8Nullable();
  void addUint16Nullable();
  void addUint32Nullable();
  void addUint64Nullable();

  // Stolen-bit nullable (same size as underlying type, sentinel encodes null)
  void addInt7Nullable();
  void addInt15Nullable();
  void addInt31Nullable();
  void addInt63Nullable();
  void addUint7Nullable();
  void addUint15Nullable();
  void addUint31Nullable();
  void addUint63Nullable();

  // Tagged nullable (value N bytes + 1 flag byte)
  void addInt8Tagged();
  void addInt16Tagged();
  void addInt32Tagged();
  void addInt64Tagged();
  void addUint8Tagged();
  void addUint16Tagged();
  void addUint32Tagged();
  void addUint64Tagged();
  void addFloat32Tagged();
  void addFloat64Tagged();

  // Packed nullable (double-bit in same packed byte)
  void addBoolNullable();
  void addBitNullable();
  void addInt2Nullable();
  void addUint2Nullable();
  void addInt4Nullable();
  void addUint4Nullable();

  // Fixed-count typed-array fields (same wire layout for view and copy)
  void addInt8ListView(int count);
  void addInt8ListViewNullable(int count);
  void addInt16ListView(int count);
  void addInt16ListViewNullable(int count);
  void addInt32ListView(int count);
  void addInt32ListViewNullable(int count);
  void addInt64ListView(int count);
  void addInt64ListViewNullable(int count);
  void addUint8ListView(int count);
  void addUint8ListViewNullable(int count);
  void addUint16ListView(int count);
  void addUint16ListViewNullable(int count);
  void addUint32ListView(int count);
  void addUint32ListViewNullable(int count);
  void addUint64ListView(int count);
  void addUint64ListViewNullable(int count);
  void addFloat32ListView(int count);
  void addFloat32ListViewNullable(int count);
  void addFloat64ListView(int count);
  void addFloat64ListViewNullable(int count);
}

abstract class FieldReader {
  int readInt8();
  int readInt16();
  int readInt32();
  int readInt64();
  int readUint8();
  int readUint16();
  int readUint32();
  int readUint64();
  double readFloat32();
  double readFloat64();
  T readField<T>(FieldParser<T> parser);
  T? readNullableField<T>(FieldParser<T> parser);
  // Sub-byte
  int readBit();
  bool readBool();
  int readInt2();
  int readUint2();
  int readInt4();
  int readUint4();

  // Nullable word types
  int? readInt8Nullable();
  int? readInt16Nullable();
  int? readInt32Nullable();
  int? readInt64Nullable();
  int? readUint8Nullable();
  int? readUint16Nullable();
  int? readUint32Nullable();
  int? readUint64Nullable();

  // Stolen-bit nullable
  int? readInt7Nullable();
  int? readInt15Nullable();
  int? readInt31Nullable();
  int? readInt63Nullable();
  int? readUint7Nullable();
  int? readUint15Nullable();
  int? readUint31Nullable();
  int? readUint63Nullable();

  // Tagged nullable (value + 1 flag byte)
  int? readInt8Tagged();
  int? readInt16Tagged();
  int? readInt32Tagged();
  int? readInt64Tagged();
  int? readUint8Tagged();
  int? readUint16Tagged();
  int? readUint32Tagged();
  int? readUint64Tagged();
  double? readFloat32Tagged();
  double? readFloat64Tagged();

  // Fixed-count typed-array: view (zero-copy) and copy variants
  Int8List readInt8ListView(int count);
  Int8List? readInt8ListViewNullable(int count);
  Int8List readInt8List(int count);
  Int8List? readInt8ListNullable(int count);
  Int16List readInt16ListView(int count);
  Int16List? readInt16ListViewNullable(int count);
  Int16List readInt16List(int count);
  Int16List? readInt16ListNullable(int count);
  Int32List readInt32ListView(int count);
  Int32List? readInt32ListViewNullable(int count);
  Int32List readInt32List(int count);
  Int32List? readInt32ListNullable(int count);
  Int64List readInt64ListView(int count);
  Int64List? readInt64ListViewNullable(int count);
  Int64List readInt64List(int count);
  Int64List? readInt64ListNullable(int count);
  Uint8List readUint8ListView(int count);
  Uint8List? readUint8ListViewNullable(int count);
  Uint8List readUint8List(int count);
  Uint8List? readUint8ListNullable(int count);
  Uint16List readUint16ListView(int count);
  Uint16List? readUint16ListViewNullable(int count);
  Uint16List readUint16List(int count);
  Uint16List? readUint16ListNullable(int count);
  Uint32List readUint32ListView(int count);
  Uint32List? readUint32ListViewNullable(int count);
  Uint32List readUint32List(int count);
  Uint32List? readUint32ListNullable(int count);
  Uint64List readUint64ListView(int count);
  Uint64List? readUint64ListViewNullable(int count);
  Uint64List readUint64List(int count);
  Uint64List? readUint64ListNullable(int count);
  Float32List readFloat32ListView(int count);
  Float32List? readFloat32ListViewNullable(int count);
  Float32List readFloat32List(int count);
  Float32List? readFloat32ListNullable(int count);
  Float64List readFloat64ListView(int count);
  Float64List? readFloat64ListViewNullable(int count);
  Float64List readFloat64List(int count);
  Float64List? readFloat64ListNullable(int count);
}

abstract class FieldWriter {
  void writeInt8(int value);
  void writeInt16(int value);
  void writeInt32(int value);
  void writeInt64(int value);
  void writeUint8(int value);
  void writeUint16(int value);
  void writeUint32(int value);
  void writeUint64(int value);
  void writeFloat32(double value);
  void writeFloat64(double value);
  void writeField<T>(T value, FieldParser<T> parser);
  void writeNullableField<T>(T? value, FieldParser<T> parser);
  // Sub-byte
  void writeBit(int value);
  void writeBool(bool value);
  void writeInt2(int value);
  void writeUint2(int value);
  void writeInt4(int value);
  void writeUint4(int value);

  // Nullable word types
  void writeInt8Nullable(int? value);
  void writeInt16Nullable(int? value);
  void writeInt32Nullable(int? value);
  void writeInt64Nullable(int? value);
  void writeUint8Nullable(int? value);
  void writeUint16Nullable(int? value);
  void writeUint32Nullable(int? value);
  void writeUint64Nullable(int? value);

  // Stolen-bit nullable
  void writeInt7Nullable(int? value);
  void writeInt15Nullable(int? value);
  void writeInt31Nullable(int? value);
  void writeInt63Nullable(int? value);
  void writeUint7Nullable(int? value);
  void writeUint15Nullable(int? value);
  void writeUint31Nullable(int? value);
  void writeUint63Nullable(int? value);

  // Tagged nullable (value + 1 flag byte)
  void writeInt8Tagged(int? value);
  void writeInt16Tagged(int? value);
  void writeInt32Tagged(int? value);
  void writeInt64Tagged(int? value);
  void writeUint8Tagged(int? value);
  void writeUint16Tagged(int? value);
  void writeUint32Tagged(int? value);
  void writeUint64Tagged(int? value);
  void writeFloat32Tagged(double? value);
  void writeFloat64Tagged(double? value);

  // Fixed-count typed-array: view and copy variants (same wire format)
  void writeInt8ListView(Int8List value, int count);
  void writeInt8ListViewNullable(Int8List? value, int count);
  void writeInt8List(Int8List value, int count);
  void writeInt8ListNullable(Int8List? value, int count);
  void writeInt16ListView(Int16List value, int count);
  void writeInt16ListViewNullable(Int16List? value, int count);
  void writeInt16List(Int16List value, int count);
  void writeInt16ListNullable(Int16List? value, int count);
  void writeInt32ListView(Int32List value, int count);
  void writeInt32ListViewNullable(Int32List? value, int count);
  void writeInt32List(Int32List value, int count);
  void writeInt32ListNullable(Int32List? value, int count);
  void writeInt64ListView(Int64List value, int count);
  void writeInt64ListViewNullable(Int64List? value, int count);
  void writeInt64List(Int64List value, int count);
  void writeInt64ListNullable(Int64List? value, int count);
  void writeUint8ListView(Uint8List value, int count);
  void writeUint8ListViewNullable(Uint8List? value, int count);
  void writeUint8List(Uint8List value, int count);
  void writeUint8ListNullable(Uint8List? value, int count);
  void writeUint16ListView(Uint16List value, int count);
  void writeUint16ListViewNullable(Uint16List? value, int count);
  void writeUint16List(Uint16List value, int count);
  void writeUint16ListNullable(Uint16List? value, int count);
  void writeUint32ListView(Uint32List value, int count);
  void writeUint32ListViewNullable(Uint32List? value, int count);
  void writeUint32List(Uint32List value, int count);
  void writeUint32ListNullable(Uint32List? value, int count);
  void writeUint64ListView(Uint64List value, int count);
  void writeUint64ListViewNullable(Uint64List? value, int count);
  void writeUint64List(Uint64List value, int count);
  void writeUint64ListNullable(Uint64List? value, int count);
  void writeFloat32ListView(Float32List value, int count);
  void writeFloat32ListViewNullable(Float32List? value, int count);
  void writeFloat32List(Float32List value, int count);
  void writeFloat32ListNullable(Float32List? value, int count);
  void writeFloat64ListView(Float64List value, int count);
  void writeFloat64ListViewNullable(Float64List? value, int count);
  void writeFloat64List(Float64List value, int count);
  void writeFloat64ListNullable(Float64List? value, int count);
}
