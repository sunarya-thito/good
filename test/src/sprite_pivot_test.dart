import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

void main() {
  group('Point2D', () {
    test('center should compute (width/2, height/2)', () {
      const pivot = Point2D.center;
      const size = ui.Size(100, 200);
      expect(pivot.compute(size), const ui.Offset(50, 100));
    });

    test('topLeft should compute (0, 0)', () {
      const pivot = Point2D.topLeft;
      const size = ui.Size(100, 200);
      expect(pivot.compute(size), ui.Offset.zero);
    });

    test('bottomRight should compute (width, height)', () {
      const pivot = Point2D.bottomRight;
      const size = ui.Size(100, 200);
      expect(pivot.compute(size), const ui.Offset(100, 200));
    });

    test('custom fractional values should work', () {
      const pivot = Point2D(Point.frac(0.25), Point.frac(0.75));
      const size = ui.Size(100, 100);
      expect(pivot.compute(size), const ui.Offset(25, 75));
    });

    test('pixel values should return absolute offsets regardless of size', () {
      const pivot = Point2D(Point.px(10), Point.px(20));
      expect(pivot.compute(const ui.Size(100, 100)), const ui.Offset(10, 20));
      expect(pivot.compute(const ui.Size(500, 500)), const ui.Offset(10, 20));
    });

    test('mixed px and frac axes should work independently', () {
      const pivot = Point2D(Point.px(16), Point.frac(1.0));
      const size = ui.Size(200, 100);
      expect(pivot.compute(size), const ui.Offset(16, 100));
    });
  });
}
