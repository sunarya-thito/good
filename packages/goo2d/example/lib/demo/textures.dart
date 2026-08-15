import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:goo2d/goo2d.dart';

/// Textures generated at run time instead of shipped.
///
/// Real `ui.Image`s decoded through the same `instantiateImageCodec` path a
/// bundled PNG takes, so a sprite here samples an actual texture and the
/// numbers mean what they would with art. Generated rather than shipped purely
/// so the example has no binary asset in the repo; swap in
/// `TextureAsset.bundle('assets/whatever.png')` and nothing else changes.
///
/// `dart:ui` is the one piece of Flutter a `demo/` file is allowed to touch,
/// and only here: producing an image is not widget boilerplate, and hiding it
/// in the harness would separate a texture from the case that samples it.
class _Disc extends GameAssetSource {
  const _Disc(this.size);

  final int size;

  @override
  Future<Uint8List> load() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final extent = size.toDouble();
    // Real alpha and a gradient, so the sampler and the blend both do work -
    // a flat opaque square lets the raster path off lightly and flatters the
    // measurement.
    canvas.drawCircle(
      ui.Offset(extent / 2, extent / 2),
      extent / 2 - 1,
      ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset(extent * 0.35, extent * 0.3),
          extent * 0.75,
          const <ui.Color>[ui.Color(0xFFFFFFFF), ui.Color(0x00FFFFFF)],
        ),
    );
    final image = await recorder.endRecording().toImage(size, size);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  @override
  String get description => 'disc ${size}x$size';
}

/// A soft white disc, tinted per entity through `Sprite.color`.
///
/// **One key, shared by every sprite that wants it** - so a whole field is one
/// texture and the renderer emits a single `drawVertices` run for all of them.
/// Two keys naming the same image would be two addresses, two decodes and two
/// runs, which is the thing to avoid and the reason this is a top-level final.
final discTexture = TextureAsset(const _Disc(64));
