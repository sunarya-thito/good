import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:goo2d/goo2d.dart';

/// Textures generated at run time instead of shipped.
///
/// Real `ui.Image`s decoded through the same `instantiateImageCodec` path a
/// bundled PNG takes, so a sprite here samples an actual texture and the
/// numbers mean what they would with art. Generated rather than shipped purely
/// so the example has no binary asset in the repo; swap in
/// `TextureKey(BundleSource('assets/whatever.png'))` and nothing else changes.
///
/// `dart:ui` is the one piece of Flutter a `demo/` file is allowed to touch,
/// and only here: producing an image is not widget boilerplate, and hiding it
/// in the harness would separate a texture from the case that samples it.
class _Disc extends AssetSource {
  const _Disc(this.size);

  final int size;

  @override
  Future<AssetAvailability> check() async => AssetAvailability.present;

  // Value equality, which half of an asset's identity is made of: two `_Disc`s
  // of one size are one texture, one address and one decode.
  @override
  bool operator ==(Object other) => other is _Disc && other.size == size;

  @override
  int get hashCode => Object.hash(_Disc, size);

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
///
/// Sharing the constant is style rather than necessity now: identity is
/// `(payload type, source)`, so a second `TextureKey(_Disc(64))` written
/// somewhere else is the *same* asset - one address, one decode, one run. It
/// used to be a requirement, because keys were identity-compared and two of
/// them naming one image were two of everything.
const discTexture = TextureKey(_Disc(64));
