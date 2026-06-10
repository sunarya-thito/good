import 'package:goo2d/goo2d.dart';

typedef FieldLengthDescriptor = void Function(FieldDescriptor descriptor);
typedef FieldLengthWriter<T> = void Function(FieldWriter writer, T value);
typedef FieldLengthReader<T> = T Function(FieldReader reader);
typedef FieldLengthDataDescriptor<T> =
    Field<T> Function(DataDescriptor descriptor);

enum IntLength {
  bit(
    min: 0,
    max: 1,
    descriptor: _describeBit,
    writer: _writeBit,
    reader: _readBit,
    dataDescriptor: _dataBit,
  ),
  uint2(
    min: 0,
    max: 3,
    descriptor: _describeUint2,
    writer: _writeUint2,
    reader: _readUint2,
    dataDescriptor: _dataUint2,
  ),
  int2(
    min: -2,
    max: 1,
    descriptor: _describeInt2,
    writer: _writeInt2,
    reader: _readInt2,
    dataDescriptor: _dataInt2,
  ),
  uint4(
    min: 0,
    max: 15,
    descriptor: _describeUint4,
    writer: _writeUint4,
    reader: _readUint4,
    dataDescriptor: _dataUint4,
  ),
  int4(
    min: -8,
    max: 7,
    descriptor: _describeInt4,
    writer: _writeInt4,
    reader: _readInt4,
    dataDescriptor: _dataInt4,
  ),
  uint8(
    min: 0,
    max: 255,
    descriptor: _describeUint8,
    writer: _writeUint8,
    reader: _readUint8,
    dataDescriptor: _dataUint8,
  ),
  int8(
    min: -128,
    max: 127,
    descriptor: _describeInt8,
    writer: _writeInt8,
    reader: _readInt8,
    dataDescriptor: _dataInt8,
  ),
  uint16(
    min: 0,
    max: 65535,
    descriptor: _describeUint16,
    writer: _writeUint16,
    reader: _readUint16,
    dataDescriptor: _dataUint16,
  ),
  int16(
    min: -32768,
    max: 32767,
    descriptor: _describeInt16,
    writer: _writeInt16,
    reader: _readInt16,
    dataDescriptor: _dataInt16,
  ),
  uint32(
    min: 0,
    max: 4294967295,
    descriptor: _describeUint32,
    writer: _writeUint32,
    reader: _readUint32,
    dataDescriptor: _dataUint32,
  ),
  int32(
    min: -2147483648,
    max: 2147483647,
    descriptor: _describeInt32,
    writer: _writeInt32,
    reader: _readInt32,
    dataDescriptor: _dataInt32,
  ),
  uint64(
    min: 0,
    // max: 18446744073709551615,
    // we use signed ints because Dart doesn't have uint64, so max is halved
    max: 9223372036854775807,
    descriptor: _describeUint64,
    writer: _writeUint64,
    reader: _readUint64,
    dataDescriptor: _dataUint64,
  ),
  int64(
    min: -9223372036854775808,
    max: 9223372036854775807,
    descriptor: _describeInt64,
    writer: _writeInt64,
    reader: _readInt64,
    dataDescriptor: _dataInt64,
  );

  final int min;
  final int max;
  final FieldLengthDescriptor descriptor;
  final FieldLengthWriter<int> writer;
  final FieldLengthReader<int> reader;
  final FieldLengthDataDescriptor<int> dataDescriptor;

  const IntLength({
    required this.min,
    required this.max,
    required this.descriptor,
    required this.writer,
    required this.reader,
    required this.dataDescriptor,
  });

  static IntLength forRange(int min, int max) {
    for (final length in IntLength.values) {
      if (length.min <= min && length.max >= max) {
        return length;
      }
    }
    throw ArgumentError('No suitable IntLength for range [$min, $max]');
  }

  static IntLength forLength(int length) {
    for (final l in IntLength.values) {
      if (l.max - l.min + 1 >= length) {
        return l;
      }
    }
    throw ArgumentError('No suitable IntLength for length $length');
  }

  static void _describeBit(FieldDescriptor descriptor) => descriptor.addBit();
  static void _describeUint2(FieldDescriptor descriptor) =>
      descriptor.addUint2();
  static void _describeInt2(FieldDescriptor descriptor) => descriptor.addInt2();
  static void _describeUint4(FieldDescriptor descriptor) =>
      descriptor.addUint4();
  static void _describeInt4(FieldDescriptor descriptor) => descriptor.addInt4();
  static void _describeUint8(FieldDescriptor descriptor) =>
      descriptor.addUint8();
  static void _describeInt8(FieldDescriptor descriptor) => descriptor.addInt8();
  static void _describeUint16(FieldDescriptor descriptor) =>
      descriptor.addUint16();
  static void _describeInt16(FieldDescriptor descriptor) =>
      descriptor.addInt16();
  static void _describeUint32(FieldDescriptor descriptor) =>
      descriptor.addUint32();
  static void _describeInt32(FieldDescriptor descriptor) =>
      descriptor.addInt32();
  static void _describeUint64(FieldDescriptor descriptor) =>
      descriptor.addUint64();
  static void _describeInt64(FieldDescriptor descriptor) =>
      descriptor.addInt64();

  static void _writeBit(FieldWriter writer, int value) =>
      writer.writeBit(value);
  static void _writeUint2(FieldWriter writer, int value) =>
      writer.writeUint2(value);
  static void _writeInt2(FieldWriter writer, int value) =>
      writer.writeInt2(value);
  static void _writeUint4(FieldWriter writer, int value) =>
      writer.writeUint4(value);
  static void _writeInt4(FieldWriter writer, int value) =>
      writer.writeInt4(value);
  static void _writeUint8(FieldWriter writer, int value) =>
      writer.writeUint8(value);
  static void _writeInt8(FieldWriter writer, int value) =>
      writer.writeInt8(value);
  static void _writeUint16(FieldWriter writer, int value) =>
      writer.writeUint16(value);
  static void _writeInt16(FieldWriter writer, int value) =>
      writer.writeInt16(value);
  static void _writeUint32(FieldWriter writer, int value) =>
      writer.writeUint32(value);
  static void _writeInt32(FieldWriter writer, int value) =>
      writer.writeInt32(value);
  static void _writeUint64(FieldWriter writer, int value) =>
      writer.writeUint64(value);
  static void _writeInt64(FieldWriter writer, int value) =>
      writer.writeInt64(value);

  static int _readBit(FieldReader reader) => reader.readBit();
  static int _readUint2(FieldReader reader) => reader.readUint2();
  static int _readInt2(FieldReader reader) => reader.readInt2();
  static int _readUint4(FieldReader reader) => reader.readUint4();
  static int _readInt4(FieldReader reader) => reader.readInt4();
  static int _readUint8(FieldReader reader) => reader.readUint8();
  static int _readInt8(FieldReader reader) => reader.readInt8();
  static int _readUint16(FieldReader reader) => reader.readUint16();
  static int _readInt16(FieldReader reader) => reader.readInt16();
  static int _readUint32(FieldReader reader) => reader.readUint32();
  static int _readInt32(FieldReader reader) => reader.readInt32();
  static int _readUint64(FieldReader reader) => reader.readUint64();
  static int _readInt64(FieldReader reader) => reader.readInt64();

  static Field<int> _dataBit(DataDescriptor descriptor) => descriptor.newBit();
  static Field<int> _dataUint2(DataDescriptor descriptor) =>
      descriptor.newUint2();
  static Field<int> _dataInt2(DataDescriptor descriptor) =>
      descriptor.newInt2();
  static Field<int> _dataUint4(DataDescriptor descriptor) =>
      descriptor.newUint4();
  static Field<int> _dataInt4(DataDescriptor descriptor) =>
      descriptor.newInt4();
  static Field<int> _dataUint8(DataDescriptor descriptor) =>
      descriptor.newUint8();
  static Field<int> _dataInt8(DataDescriptor descriptor) =>
      descriptor.newInt8();
  static Field<int> _dataUint16(DataDescriptor descriptor) =>
      descriptor.newUint16();
  static Field<int> _dataInt16(DataDescriptor descriptor) =>
      descriptor.newInt16();
  static Field<int> _dataUint32(DataDescriptor descriptor) =>
      descriptor.newUint32();
  static Field<int> _dataInt32(DataDescriptor descriptor) =>
      descriptor.newInt32();
  static Field<int> _dataUint64(DataDescriptor descriptor) =>
      descriptor.newUint64();
  static Field<int> _dataInt64(DataDescriptor descriptor) =>
      descriptor.newInt64();
}

// ---------------------------------------------------------------------------
// NullableIntLength — mirrors IntLength but for Field<int?> / Field<double?>
// ---------------------------------------------------------------------------

typedef NullableFieldLengthDataDescriptor<T> = Field<T?> Function(DataDescriptor descriptor);

enum NullableIntLength {
  // ---- Form 1: double-stride interleaved (int only) ----
  int8Nullable(
    min: -127,
    max: 127,
    descriptor: _describeInt8Nullable,
    writer: _writeInt8Nullable,
    reader: _readInt8Nullable,
    dataDescriptor: _dataInt8Nullable,
  ),
  int16Nullable(
    min: -32767,
    max: 32767,
    descriptor: _describeInt16Nullable,
    writer: _writeInt16Nullable,
    reader: _readInt16Nullable,
    dataDescriptor: _dataInt16Nullable,
  ),
  int32Nullable(
    min: -2147483647,
    max: 2147483647,
    descriptor: _describeInt32Nullable,
    writer: _writeInt32Nullable,
    reader: _readInt32Nullable,
    dataDescriptor: _dataInt32Nullable,
  ),
  int64Nullable(
    min: -9223372036854775807,
    max: 9223372036854775807,
    descriptor: _describeInt64Nullable,
    writer: _writeInt64Nullable,
    reader: _readInt64Nullable,
    dataDescriptor: _dataInt64Nullable,
  ),
  uint8Nullable(
    min: 0,
    max: 254,
    descriptor: _describeUint8Nullable,
    writer: _writeUint8Nullable,
    reader: _readUint8Nullable,
    dataDescriptor: _dataUint8Nullable,
  ),
  uint16Nullable(
    min: 0,
    max: 65534,
    descriptor: _describeUint16Nullable,
    writer: _writeUint16Nullable,
    reader: _readUint16Nullable,
    dataDescriptor: _dataUint16Nullable,
  ),
  uint32Nullable(
    min: 0,
    max: 4294967294,
    descriptor: _describeUint32Nullable,
    writer: _writeUint32Nullable,
    reader: _readUint32Nullable,
    dataDescriptor: _dataUint32Nullable,
  ),
  // ---- Form 2: stolen-bit sentinel ----
  int7Nullable(
    min: -127,
    max: 127,
    descriptor: _describeInt7Nullable,
    writer: _writeInt7Nullable,
    reader: _readInt7Nullable,
    dataDescriptor: _dataInt7Nullable,
  ),
  int15Nullable(
    min: -32767,
    max: 32767,
    descriptor: _describeInt15Nullable,
    writer: _writeInt15Nullable,
    reader: _readInt15Nullable,
    dataDescriptor: _dataInt15Nullable,
  ),
  int31Nullable(
    min: -2147483647,
    max: 2147483647,
    descriptor: _describeInt31Nullable,
    writer: _writeInt31Nullable,
    reader: _readInt31Nullable,
    dataDescriptor: _dataInt31Nullable,
  ),
  int63Nullable(
    min: -9223372036854775807,
    max: 9223372036854775807,
    descriptor: _describeInt63Nullable,
    writer: _writeInt63Nullable,
    reader: _readInt63Nullable,
    dataDescriptor: _dataInt63Nullable,
  ),
  uint7Nullable(
    min: 0,
    max: 254,
    descriptor: _describeUint7Nullable,
    writer: _writeUint7Nullable,
    reader: _readUint7Nullable,
    dataDescriptor: _dataUint7Nullable,
  ),
  uint15Nullable(
    min: 0,
    max: 65534,
    descriptor: _describeUint15Nullable,
    writer: _writeUint15Nullable,
    reader: _readUint15Nullable,
    dataDescriptor: _dataUint15Nullable,
  ),
  uint31Nullable(
    min: 0,
    max: 4294967294,
    descriptor: _describeUint31Nullable,
    writer: _writeUint31Nullable,
    reader: _readUint31Nullable,
    dataDescriptor: _dataUint31Nullable,
  ),
  // ---- Form 3: tagged (includes float variants via separate accessor) ----
  int8Tagged(
    min: -128,
    max: 127,
    descriptor: _describeInt8Tagged,
    writer: _writeInt8Tagged,
    reader: _readInt8Tagged,
    dataDescriptor: _dataInt8Tagged,
  ),
  int16Tagged(
    min: -32768,
    max: 32767,
    descriptor: _describeInt16Tagged,
    writer: _writeInt16Tagged,
    reader: _readInt16Tagged,
    dataDescriptor: _dataInt16Tagged,
  ),
  int32Tagged(
    min: -2147483648,
    max: 2147483647,
    descriptor: _describeInt32Tagged,
    writer: _writeInt32Tagged,
    reader: _readInt32Tagged,
    dataDescriptor: _dataInt32Tagged,
  ),
  int64Tagged(
    min: -9223372036854775808,
    max: 9223372036854775807,
    descriptor: _describeInt64Tagged,
    writer: _writeInt64Tagged,
    reader: _readInt64Tagged,
    dataDescriptor: _dataInt64Tagged,
  ),
  uint8Tagged(
    min: 0,
    max: 255,
    descriptor: _describeUint8Tagged,
    writer: _writeUint8Tagged,
    reader: _readUint8Tagged,
    dataDescriptor: _dataUint8Tagged,
  ),
  uint16Tagged(
    min: 0,
    max: 65535,
    descriptor: _describeUint16Tagged,
    writer: _writeUint16Tagged,
    reader: _readUint16Tagged,
    dataDescriptor: _dataUint16Tagged,
  ),
  uint32Tagged(
    min: 0,
    max: 4294967295,
    descriptor: _describeUint32Tagged,
    writer: _writeUint32Tagged,
    reader: _readUint32Tagged,
    dataDescriptor: _dataUint32Tagged,
  ),
  uint64Tagged(
    min: 0,
    max: 9223372036854775807,
    descriptor: _describeUint64Tagged,
    writer: _writeUint64Tagged,
    reader: _readUint64Tagged,
    dataDescriptor: _dataUint64Tagged,
  );

  final int min;
  final int max;
  final FieldLengthDescriptor descriptor;
  final FieldLengthWriter<int?> writer;
  final FieldLengthReader<int?> reader;
  final NullableFieldLengthDataDescriptor<int> dataDescriptor;

  const NullableIntLength({
    required this.min,
    required this.max,
    required this.descriptor,
    required this.writer,
    required this.reader,
    required this.dataDescriptor,
  });

  /// Picks the smallest nullable type whose non-null range fully covers [min, max].
  /// Prefers stolen-bit variants (no extra storage) when they fit.
  static NullableIntLength forRange(int min, int max) {
    // Try stolen-bit first (compact)
    for (final l in [int7Nullable, int15Nullable, int31Nullable, int63Nullable,
                     uint7Nullable, uint15Nullable, uint31Nullable]) {
      if (l.min <= min && l.max >= max) return l;
    }
    // Fall back to double-stride interleaved
    for (final l in [int8Nullable, int16Nullable, int32Nullable, int64Nullable,
                     uint8Nullable, uint16Nullable, uint32Nullable]) {
      if (l.min <= min && l.max >= max) return l;
    }
    // Fall back to tagged (full int64 range)
    return int64Tagged;
  }

  // ---- double-stride descriptors ----
  static void _describeInt8Nullable(FieldDescriptor d)  => d.addInt8Nullable();
  static void _describeInt16Nullable(FieldDescriptor d) => d.addInt16Nullable();
  static void _describeInt32Nullable(FieldDescriptor d) => d.addInt32Nullable();
  static void _describeInt64Nullable(FieldDescriptor d) => d.addInt64Nullable();
  static void _describeUint8Nullable(FieldDescriptor d)  => d.addUint8Nullable();
  static void _describeUint16Nullable(FieldDescriptor d) => d.addUint16Nullable();
  static void _describeUint32Nullable(FieldDescriptor d) => d.addUint32Nullable();

  // ---- double-stride writers ----
  static void _writeInt8Nullable(FieldWriter w, int? v)   => w.writeInt8Nullable(v);
  static void _writeInt16Nullable(FieldWriter w, int? v)  => w.writeInt16Nullable(v);
  static void _writeInt32Nullable(FieldWriter w, int? v)  => w.writeInt32Nullable(v);
  static void _writeInt64Nullable(FieldWriter w, int? v)  => w.writeInt64Nullable(v);
  static void _writeUint8Nullable(FieldWriter w, int? v)  => w.writeUint8Nullable(v);
  static void _writeUint16Nullable(FieldWriter w, int? v) => w.writeUint16Nullable(v);
  static void _writeUint32Nullable(FieldWriter w, int? v) => w.writeUint32Nullable(v);

  // ---- double-stride readers ----
  static int? _readInt8Nullable(FieldReader r)   => r.readInt8Nullable();
  static int? _readInt16Nullable(FieldReader r)  => r.readInt16Nullable();
  static int? _readInt32Nullable(FieldReader r)  => r.readInt32Nullable();
  static int? _readInt64Nullable(FieldReader r)  => r.readInt64Nullable();
  static int? _readUint8Nullable(FieldReader r)  => r.readUint8Nullable();
  static int? _readUint16Nullable(FieldReader r) => r.readUint16Nullable();
  static int? _readUint32Nullable(FieldReader r) => r.readUint32Nullable();

  // ---- double-stride DataDescriptor factories ----
  static Field<int?> _dataInt8Nullable(DataDescriptor d)   => d.newInt8Nullable();
  static Field<int?> _dataInt16Nullable(DataDescriptor d)  => d.newInt16Nullable();
  static Field<int?> _dataInt32Nullable(DataDescriptor d)  => d.newInt32Nullable();
  static Field<int?> _dataInt64Nullable(DataDescriptor d)  => d.newInt64Nullable();
  static Field<int?> _dataUint8Nullable(DataDescriptor d)  => d.newUint8Nullable();
  static Field<int?> _dataUint16Nullable(DataDescriptor d) => d.newUint16Nullable();
  static Field<int?> _dataUint32Nullable(DataDescriptor d) => d.newUint32Nullable();

  // ---- stolen-bit descriptors ----
  static void _describeInt7Nullable(FieldDescriptor d)   => d.addInt7Nullable();
  static void _describeInt15Nullable(FieldDescriptor d)  => d.addInt15Nullable();
  static void _describeInt31Nullable(FieldDescriptor d)  => d.addInt31Nullable();
  static void _describeInt63Nullable(FieldDescriptor d)  => d.addInt63Nullable();
  static void _describeUint7Nullable(FieldDescriptor d)  => d.addUint7Nullable();
  static void _describeUint15Nullable(FieldDescriptor d) => d.addUint15Nullable();
  static void _describeUint31Nullable(FieldDescriptor d) => d.addUint31Nullable();

  // ---- stolen-bit writers ----
  static void _writeInt7Nullable(FieldWriter w, int? v)   => w.writeInt7Nullable(v);
  static void _writeInt15Nullable(FieldWriter w, int? v)  => w.writeInt15Nullable(v);
  static void _writeInt31Nullable(FieldWriter w, int? v)  => w.writeInt31Nullable(v);
  static void _writeInt63Nullable(FieldWriter w, int? v)  => w.writeInt63Nullable(v);
  static void _writeUint7Nullable(FieldWriter w, int? v)  => w.writeUint7Nullable(v);
  static void _writeUint15Nullable(FieldWriter w, int? v) => w.writeUint15Nullable(v);
  static void _writeUint31Nullable(FieldWriter w, int? v) => w.writeUint31Nullable(v);

  // ---- stolen-bit readers ----
  static int? _readInt7Nullable(FieldReader r)   => r.readInt7Nullable();
  static int? _readInt15Nullable(FieldReader r)  => r.readInt15Nullable();
  static int? _readInt31Nullable(FieldReader r)  => r.readInt31Nullable();
  static int? _readInt63Nullable(FieldReader r)  => r.readInt63Nullable();
  static int? _readUint7Nullable(FieldReader r)  => r.readUint7Nullable();
  static int? _readUint15Nullable(FieldReader r) => r.readUint15Nullable();
  static int? _readUint31Nullable(FieldReader r) => r.readUint31Nullable();

  // ---- stolen-bit DataDescriptor factories ----
  static Field<int?> _dataInt7Nullable(DataDescriptor d)   => d.newInt7Nullable();
  static Field<int?> _dataInt15Nullable(DataDescriptor d)  => d.newInt15Nullable();
  static Field<int?> _dataInt31Nullable(DataDescriptor d)  => d.newInt31Nullable();
  static Field<int?> _dataInt63Nullable(DataDescriptor d)  => d.newInt63Nullable();
  static Field<int?> _dataUint7Nullable(DataDescriptor d)  => d.newUint7Nullable();
  static Field<int?> _dataUint15Nullable(DataDescriptor d) => d.newUint15Nullable();
  static Field<int?> _dataUint31Nullable(DataDescriptor d) => d.newUint31Nullable();

  // ---- tagged descriptors ----
  static void _describeInt8Tagged(FieldDescriptor d)   => d.addInt8Tagged();
  static void _describeInt16Tagged(FieldDescriptor d)  => d.addInt16Tagged();
  static void _describeInt32Tagged(FieldDescriptor d)  => d.addInt32Tagged();
  static void _describeInt64Tagged(FieldDescriptor d)  => d.addInt64Tagged();
  static void _describeUint8Tagged(FieldDescriptor d)  => d.addUint8Tagged();
  static void _describeUint16Tagged(FieldDescriptor d) => d.addUint16Tagged();
  static void _describeUint32Tagged(FieldDescriptor d) => d.addUint32Tagged();
  static void _describeUint64Tagged(FieldDescriptor d) => d.addUint64Tagged();

  // ---- tagged writers ----
  static void _writeInt8Tagged(FieldWriter w, int? v)   => w.writeInt8Tagged(v);
  static void _writeInt16Tagged(FieldWriter w, int? v)  => w.writeInt16Tagged(v);
  static void _writeInt32Tagged(FieldWriter w, int? v)  => w.writeInt32Tagged(v);
  static void _writeInt64Tagged(FieldWriter w, int? v)  => w.writeInt64Tagged(v);
  static void _writeUint8Tagged(FieldWriter w, int? v)  => w.writeUint8Tagged(v);
  static void _writeUint16Tagged(FieldWriter w, int? v) => w.writeUint16Tagged(v);
  static void _writeUint32Tagged(FieldWriter w, int? v) => w.writeUint32Tagged(v);
  static void _writeUint64Tagged(FieldWriter w, int? v) => w.writeUint64Tagged(v);

  // ---- tagged readers ----
  static int? _readInt8Tagged(FieldReader r)   => r.readInt8Tagged();
  static int? _readInt16Tagged(FieldReader r)  => r.readInt16Tagged();
  static int? _readInt32Tagged(FieldReader r)  => r.readInt32Tagged();
  static int? _readInt64Tagged(FieldReader r)  => r.readInt64Tagged();
  static int? _readUint8Tagged(FieldReader r)  => r.readUint8Tagged();
  static int? _readUint16Tagged(FieldReader r) => r.readUint16Tagged();
  static int? _readUint32Tagged(FieldReader r) => r.readUint32Tagged();
  static int? _readUint64Tagged(FieldReader r) => r.readUint64Tagged();

  // ---- tagged DataDescriptor factories ----
  static Field<int?> _dataInt8Tagged(DataDescriptor d)   => d.newInt8Tagged();
  static Field<int?> _dataInt16Tagged(DataDescriptor d)  => d.newInt16Tagged();
  static Field<int?> _dataInt32Tagged(DataDescriptor d)  => d.newInt32Tagged();
  static Field<int?> _dataInt64Tagged(DataDescriptor d)  => d.newInt64Tagged();
  static Field<int?> _dataUint8Tagged(DataDescriptor d)  => d.newUint8Tagged();
  static Field<int?> _dataUint16Tagged(DataDescriptor d) => d.newUint16Tagged();
  static Field<int?> _dataUint32Tagged(DataDescriptor d) => d.newUint32Tagged();
  static Field<int?> _dataUint64Tagged(DataDescriptor d) => d.newUint64Tagged();
}

class EnumFieldParser<T extends Enum> implements FieldParser<T> {
  final List<T> values;

  const EnumFieldParser(this.values);

  @override
  void describe(FieldDescriptor descriptor) {
    final length = values.length;
    final intLength = IntLength.forLength(length);
    intLength.descriptor(descriptor);
  }

  @override
  T read(FieldReader reader) {
    final length = values.length;
    final intLength = IntLength.forLength(length);
    final index = intLength.reader(reader);
    if (index < 0 || index >= length) {
      throw ArgumentError(
        'Invalid enum index $index for enum with ${values.length} values',
      );
    }
    return values[index];
  }

  @override
  void write(T value, FieldWriter writer) {
    final length = values.length;
    final intLength = IntLength.forLength(length);
    final index = values.indexOf(value);
    if (index < 0) {
      throw ArgumentError(
        'Invalid enum value $value for enum with ${values.length} values',
      );
    }
    intLength.writer(writer, index);
  }
}
