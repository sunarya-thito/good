import 'dart:ui' as ui;
import 'package:flutter/widgets.dart' show Alignment;
import 'package:vector_math/vector_math_64.dart';

import 'package:goo2d/src/asset.dart';
import 'package:goo2d/src/camera.dart';
import 'package:goo2d/src/component.dart';
import 'package:goo2d/src/game.dart';
import 'package:goo2d/src/render.dart';

/// A component that renders a [GameTexture] as a tiled or aligned background layer.
///
/// [TileRenderer] uses Flutter's [ui.ImageShader] to draw a texture onto the canvas
/// with support for independent horizontal/vertical tiling, UV offset, scale, and
/// alignment. It is the primary building block for parallax backgrounds and
/// repeating environment layers.
///
/// The render area defaults to the full camera viewport and is centered at the
/// game object's world origin. Set [size] to constrain the area to explicit
/// world-unit dimensions.
///
/// ```dart
/// void example(GameObject object, GameTexture skyTexture) {
///   object.addComponent(TileRenderer()
///     ..texture = skyTexture
///     ..repeatX = true
///     ..repeatY = false
///     ..scale = Vector2(1.0, 1.0));
/// }
/// ```
///
/// To create a parallax scrolling effect, update [offset] each frame in proportion
/// to the camera's world movement:
///
/// ```dart
/// tileRenderer.offset.x = -camera.position.x * parallaxFactor;
/// ```
///
/// See also:
/// * [GameTexture] for the source image.
/// * [Camera] for the viewport that determines the default render area.
class TileRenderer extends Behavior with Renderable {
  /// The texture to draw.
  ///
  /// If null or not yet loaded, the renderer draws nothing.
  GameTexture? texture;

  /// Whether to tile the texture horizontally.
  ///
  /// When true, the texture repeats beyond its width. When false, areas outside
  /// the texture boundary are transparent ([ui.TileMode.decal]).
  bool repeatX = true;

  /// Whether to tile the texture vertically.
  ///
  /// When true, the texture repeats beyond its height. When false, areas outside
  /// the texture boundary are transparent ([ui.TileMode.decal]).
  bool repeatY = true;

  /// Scroll offset of the texture pattern in world units.
  ///
  /// Increasing [offset.x] shifts the tiling pattern to the right. Use this to
  /// implement parallax scrolling relative to the camera.
  Vector2 offset = Vector2.zero();

  /// Scale of the texture relative to the render area.
  ///
  /// A value of `(1.0, 1.0)` makes the texture span the render area exactly once.
  /// A value of `(0.5, 0.5)` makes the texture half the render area size, so it
  /// tiles four times total when both repeat flags are enabled.
  Vector2 scale = Vector2(1.0, 1.0);

  /// Alignment of the texture origin within the render area.
  ///
  /// Controls where image pixel `(0, 0)` is anchored before [offset] is applied.
  /// Defaults to [Alignment.center].
  Alignment alignment = Alignment.center;

  /// Explicit render area in world units, centered at the game object's origin.
  ///
  /// When null, the render area defaults to the full camera viewport derived from
  /// [Camera.orthographicSize] and the screen's aspect ratio.
  Vector2? size;

  /// Filter quality used when sampling the texture.
  ///
  /// Defaults to [ui.FilterQuality.low] (bilinear filtering).
  ui.FilterQuality filterQuality = ui.FilterQuality.low;

  @override
  void render(ui.Canvas canvas) {
    final texture = this.texture;
    if (texture == null || !texture.isLoaded) return;

    final image = texture.image;
    final imgW = texture.width.toDouble();
    final imgH = texture.height.toDouble();
    if (imgW == 0 || imgH == 0) return;

    final cameraSystem = game.getSystem<CameraSystem>();
    final camera = cameraSystem?.currentRenderCamera;
    if (camera == null) return;

    // Render area in world coordinates, centered at the game object's origin.
    // Uses explicit [size] when set; otherwise fills the full camera viewport.
    final ui.Rect dst;
    final explicitSize = size;
    if (explicitSize != null) {
      dst = ui.Rect.fromCenter(
        center: ui.Offset.zero,
        width: explicitSize.x,
        height: explicitSize.y,
      );
    } else {
      final screenSize = game.screen.screenSize;
      final aspect = screenSize.width / screenSize.height;
      final halfH = camera.orthographicSize;
      final halfW = halfH * aspect;
      dst = ui.Rect.fromLTRB(-halfW, -halfH, halfW, halfH);
    }

    // Texture size in world units — scale is relative to the render area.
    final texW = dst.width * scale.x;
    final texH = dst.height * scale.y;

    // Alignment maps [-1,1]×[-1,1] to the position of image pixel (0,0) in world
    // space, before applying [offset]. Alignment.center places the texture
    // symmetrically around the center of the render area.
    final originX =
        dst.left + (dst.width - texW) * (1.0 + alignment.x) / 2.0 + offset.x;
    final originY =
        dst.top + (dst.height - texH) * (1.0 + alignment.y) / 2.0 + offset.y;

    // ImageShader matrix: image pixel coordinates → canvas world coordinates.
    // Flutter inverts this internally to compute which pixel to sample for each
    // canvas position. Same construction idiom as TileFit.computeMatrix.
    final matrix = Matrix4.identity()
      ..translateByDouble(originX, originY, 0.0, 1.0)
      ..scaleByDouble(texW / imgW, texH / imgH, 1.0, 1.0);

    final xMode = repeatX ? ui.TileMode.repeated : ui.TileMode.decal;
    final yMode = repeatY ? ui.TileMode.repeated : ui.TileMode.decal;

    final paint = ui.Paint()
      ..shader = ui.ImageShader(image, xMode, yMode, matrix.storage)
      ..filterQuality = filterQuality;

    canvas.drawRect(dst, paint);
  }
}
