import 'dart:ui';

import 'package:goo2d/goo2d.dart';

class SizeFieldParser implements FieldParser<Size> {
  static const parser = SizeFieldParser();
  const SizeFieldParser();
  @override
  void describe(FieldDescriptor descriptor) {
    descriptor.addFloat64();
    descriptor.addFloat64();
  }

  @override
  Size read(FieldReader reader) {
    final width = reader.readFloat64();
    final height = reader.readFloat64();
    return Size(width, height);
  }

  @override
  void write(Size value, FieldWriter writer) {
    writer.writeFloat64(value.width);
    writer.writeFloat64(value.height);
  }
}

class ColorFieldParser implements FieldParser<Color> {
  static const parser = ColorFieldParser();
  const ColorFieldParser();
  @override
  void describe(FieldDescriptor descriptor) {
    descriptor.addUint32();
  }

  @override
  Color read(FieldReader reader) {
    final value = reader.readUint32();
    return Color(value);
  }

  @override
  void write(Color value, FieldWriter writer) {
    writer.writeUint32(value.toARGB32());
  }
}
