import 'package:goo2d/goo2d.dart';

class TransformData extends EntityData {
  late final Field<double> x;
  late final Field<double> y;
  late final Field<double> angle;
  late final Field<double> scaleX;
  late final Field<double> scaleY;

  @override
  void describe(DataDescriptor d) {
    x      = d.newFloat32();
    y      = d.newFloat32();
    angle  = d.newFloat32();
    scaleX = d.newFloat32(initialValue: 1.0);
    scaleY = d.newFloat32(initialValue: 1.0);
  }
}

class WorldTransformData extends EntityData {
  late final Field<double> wx;
  late final Field<double> wy;
  late final Field<double> wAngle;
  late final Field<double> wScaleX;
  late final Field<double> wScaleY;

  @override
  void describe(DataDescriptor d) {
    wx      = d.newFloat32();
    wy      = d.newFloat32();
    wAngle  = d.newFloat32();
    wScaleX = d.newFloat32(initialValue: 1.0);
    wScaleY = d.newFloat32(initialValue: 1.0);
  }
}
