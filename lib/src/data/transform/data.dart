import 'dart:typed_data';
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

  /// Pre-baked 2D affine matrix written by [TransformSystem] each tick.
  /// Layout: [a, b, c, d, tx, ty] where
  ///   a = cos(wAngle)*wScaleX,  b = -sin(wAngle)*wScaleY,
  ///   c = sin(wAngle)*wScaleX,  d =  cos(wAngle)*wScaleY,
  ///   tx = wx,                  ty = wy.
  /// Zero-copy view into pool memory — do not hold across entity creation.
  late final Field<Float32List> matrix;

  @override
  void describe(DataDescriptor d) {
    wx      = d.newFloat32();
    wy      = d.newFloat32();
    wAngle  = d.newFloat32();
    wScaleX = d.newFloat32(initialValue: 1.0);
    wScaleY = d.newFloat32(initialValue: 1.0);
    matrix  = d.newFloat32ListView(6);
  }
}
