import 'package:flutter/widgets.dart';
import 'package:goo2d/goo2d.dart';

class RectClipper extends CustomClipper<Rect> {
  final Point top;
  final Point right;
  final Point bottom;
  final Point left;

  const RectClipper({
    this.top = const Point.frac(0),
    this.right = const Point.frac(1),
    this.bottom = const Point.frac(1),
    this.left = const Point.frac(0),
  });

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      left.resolve(size.width),
      top.resolve(size.height),
      right.resolve(size.width),
      bottom.resolve(size.height),
    );
  }

  @override
  bool shouldReclip(covariant RectClipper oldClipper) {
    return top != oldClipper.top ||
        right != oldClipper.right ||
        bottom != oldClipper.bottom ||
        left != oldClipper.left;
  }
}
