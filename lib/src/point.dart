import 'dart:ui';

/// A position along a single axis, specified as either a pixel value or a
/// fraction of the total dimension, measured from either edge.
sealed class Point {
  const Point();

  /// [pixels] from the leading edge. Use [flipped] to measure from the trailing edge.
  const factory Point.px(double pixels) = _PointPx;

  /// [fraction] × total from the leading edge. Use [flipped] to measure from the trailing edge.
  const factory Point.frac(double fraction) = _PointFrac;

  double resolve(double total);
  Point get flipped;
}

final class _PointPx extends Point {
  final double pixels;
  const _PointPx(this.pixels);
  @override
  double resolve(double total) => pixels;
  @override
  Point get flipped => _PointPxEnd(pixels);
}

final class _PointFrac extends Point {
  final double fraction;
  const _PointFrac(this.fraction);
  @override
  double resolve(double total) => fraction * total;
  @override
  Point get flipped => _PointFracEnd(fraction);
}

final class _PointPxEnd extends Point {
  final double pixels;
  const _PointPxEnd(this.pixels);
  @override
  double resolve(double total) => total - pixels;
  @override
  Point get flipped => _PointPx(pixels);
}

final class _PointFracEnd extends Point {
  final double fraction;
  const _PointFracEnd(this.fraction);
  @override
  double resolve(double total) => total - fraction * total;
  @override
  Point get flipped => _PointFrac(fraction);
}

/// A 2D anchor point defined by independent [Point] values for each axis.
///
/// Replaces the former `SpritePivot` hierarchy. Each axis can independently
/// use pixel or fractional coordinates, e.g.:
///
/// ```dart
/// const pivot = Point2D(Point.frac(0.5), Point.frac(0.5)); // center
/// const corner = Point2D(Point.px(16), Point.frac(1.0));   // mixed
/// ```
class Point2D {
  final Point x;
  final Point y;

  const Point2D(this.x, this.y);

  /// Resolves this anchor to a pixel [Offset] for the given [size].
  Offset compute(Size size) => Offset(x.resolve(size.width), y.resolve(size.height));

  static const center       = Point2D(Point.frac(0.5), Point.frac(0.5));
  static const topLeft      = Point2D(Point.frac(0.0), Point.frac(0.0));
  static const topRight     = Point2D(Point.frac(1.0), Point.frac(0.0));
  static const bottomLeft   = Point2D(Point.frac(0.0), Point.frac(1.0));
  static const bottomRight  = Point2D(Point.frac(1.0), Point.frac(1.0));
  static const topCenter    = Point2D(Point.frac(0.5), Point.frac(0.0));
  static const bottomCenter = Point2D(Point.frac(0.5), Point.frac(1.0));
  static const leftCenter   = Point2D(Point.frac(0.0), Point.frac(0.5));
  static const rightCenter  = Point2D(Point.frac(1.0), Point.frac(0.5));
}
