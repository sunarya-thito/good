import 'dart:ui';

import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/data/enum.dart';
import 'package:goo2d/src/data/renderer/parsers.dart';

class RenderData extends EntityData {
  late final Field<int?> spriteIndex;
  late final Field<BlendMode> blendMode;
  late final Field<FilterQuality> filterQuality;
  late final Field<Size?> size;
  late final Field<bool> flipX;
  late final Field<bool> flipY;
  late final Field<Color> color;

  @override
  void describe(DataDescriptor descriptor) {
    spriteIndex = descriptor.newUint16Nullable();
    blendMode = descriptor.newField(
      const EnumFieldParser(BlendMode.values),
      initialValue: BlendMode.srcOver,
    );
    filterQuality = descriptor.newField(
      const EnumFieldParser(FilterQuality.values),
      initialValue: FilterQuality.low,
    );
    size = descriptor.newFieldNullable(SizeFieldParser.parser);
    flipX = descriptor.newBool();
    flipY = descriptor.newBool();
    color = descriptor.newField(
      ColorFieldParser.parser,
      initialValue: const Color(0xFFFFFFFF),
    );
  }
}
