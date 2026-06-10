import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'dart:typed_data';

class MockSource implements AssetSource {
  @override
  String get name => 'mock';
  @override
  Future<Uint8List> loadBytes() async => Uint8List(0);
}

class MockTexture extends GameTexture {
  final int _width;
  final int _height;
  final ui.Image _image;

  @override int  get width    => _width;
  @override int  get height   => _height;
  @override bool get isLoaded => true;

  MockTexture(this._width, this._height, this._image) : super(MockSource());

  @override Future<void> load()  async {}
  @override void         unload()      {}
  @override ui.Image     get image => _image;
}

class RecordingCanvas extends Fake implements ui.Canvas {
  int drawImageRectCalls = 0;
  int drawRectCalls      = 0;

  @override void save()   {}
  @override void restore() {}
  @override void translate(double dx, double dy) {}
  @override void scale(double sx, [double? sy]) {}

  @override
  void drawImageRect(ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) =>
      drawImageRectCalls++;

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) => drawRectCalls++;
}

class RecordingFit extends SpriteFit {
  final List<ui.Rect> srcRects = [];
  final List<ui.Rect> dstRects = [];

  @override
  void draw(
    ui.Canvas canvas,
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) {
    srcRects.add(src);
    dstRects.add(dst);
  }
}

Future<ui.Image> createTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFFFF0000), ui.BlendMode.src);
  final picture = recorder.endRecording();
  return await picture.toImage(10, 10);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpriteMesh', () {
    late ui.Image image;
    late MockTexture texture;

    setUpAll(() async {
      image = await createTestImage();
      texture = MockTexture(100, 100, image);
    });

    test('SimpleMesh size matches full texture', () {
      final mesh = SimpleMesh(texture: texture);
      expect(mesh.size, const ui.Size(100, 100));
    });

    test('SimpleMesh with srcRect reports srcRect size', () {
      final mesh = SimpleMesh(
        texture: texture,
        srcRect: const ui.Rect.fromLTWH(10, 10, 50, 40),
      );
      expect(mesh.size, const ui.Size(50, 40));
    });

    test('SimpleMesh render calls fit.draw with correct src/dst', () {
      final recorder = RecordingFit();
      final canvas = RecordingCanvas();
      final mesh = SimpleMesh(texture: texture, fit: recorder);
      final handle = mesh.createHandle();
      handle.render(canvas, const ui.Size(200, 200), ui.Paint());
      handle.dispose();
      expect(recorder.srcRects.single, const ui.Rect.fromLTWH(0, 0, 100, 100));
      expect(recorder.dstRects.single, const ui.Rect.fromLTWH(0, 0, 200, 200));
    });

    test('GridMesh.nineSlice size matches full texture', () {
      final mesh = GridMesh.nineSlice(
        texture: texture,
        left:   Point.px(10),
        top:    Point.px(10),
        right:  Point.px(10),
        bottom: Point.px(10),
      );
      expect(mesh.size, const ui.Size(100, 100));
    });

    test('GridMesh render fallback does not throw', () {
      final canvas = RecordingCanvas();
      final mesh = GridMesh.nineSlice(
        texture: texture,
        left:   Point.px(10),
        top:    Point.px(10),
        right:  Point.px(10),
        bottom: Point.px(10),
      );
      final handle = mesh.createHandle();
      expect(
        () => handle.render(canvas, const ui.Size(300, 300), ui.Paint()),
        returnsNormally,
      );
      handle.dispose();
    });

    test('GridMesh.nineSlice source lines partition the source correctly', () {
      final canvas = RecordingCanvas();
      final mesh = GridMesh.nineSlice(
        texture: texture,
        left:   Point.px(10),
        top:    Point.px(10),
        right:  Point.px(10),
        bottom: Point.px(10),
      );
      expect(
        () => mesh.createHandle()
          ..render(canvas, const ui.Rect.fromLTWH(0, 0, 300, 300).size, ui.Paint())
          ..dispose(),
        returnsNormally,
      );
    });

    test('Point.px resolves correctly', () {
      expect(Point.px(20).resolve(100), 20.0);
      expect(Point.px(20).flipped.resolve(100), 80.0);
    });

    test('Point.frac resolves correctly', () {
      expect(Point.frac(0.25).resolve(100), 25.0);
      expect(Point.frac(0.25).flipped.resolve(100), 75.0);
    });

    test('Point.flipped is its own inverse', () {
      final b = Point.px(15);
      expect(b.flipped.flipped.resolve(200), b.resolve(200));

      final f = Point.frac(0.3);
      expect(f.flipped.flipped.resolve(200), f.resolve(200));
    });
  });
}
