import 'dart:ui' as ui;
import 'package:flutter/widgets.dart'
    show BoxFit, applyBoxFit, FittedSizes, Alignment;
import 'package:vector_math/vector_math_64.dart';

/// A strategy for mapping a sprite's source rectangle to a destination area.
///
/// [SpriteFit] defines how a [GameSprite] should be scaled and aligned when 
/// its pixel dimensions do not match the target rendering area in the 
/// game world. This is essential for handling UI elements, backgrounds, 
/// and objects that need to adapt to different aspect ratios.
///
/// ```dart
/// void example(ui.Canvas canvas, ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) {
///   final fit = SpriteFit.contain();
///   fit.draw(canvas, image, src, dst, paint);
/// }
/// ```
///
/// See also:
/// * [StretchFit] for simple non-uniform scaling.
/// * [TileFit] for repeating the sprite pattern.
/// * [FixedFit] for rendering at the original size.
/// * [CoverFit] for filling the area while maintaining aspect ratio.
/// * [ContainFit] for fitting inside the area while maintaining aspect ratio.
abstract class SpriteFit {
  /// A fit strategy that stretches the sprite to fill the destination exactly.
  ///
  /// This constant provides a reusable instance of [StretchFit] for 
  /// applications where non-uniform scaling is desired. It is the most 
  /// computationally efficient fit strategy as it maps directly to 
  /// a single [Canvas.drawImageRect] call.
  static const SpriteFit stretch = StretchFit();

  /// A fit strategy that tiles the sprite source across the destination.
  ///
  /// This constant provides a reusable instance of [TileFit]. It is 
  /// particularly useful for large background layers or textured 
  /// surfaces that should repeat a small pattern rather than scaling it.
  static const SpriteFit tile = TileFit();

  /// Creates a fit strategy that renders the sprite at its fixed original size.
  ///
  /// This strategy is ideal for assets that must maintain their exact pixel 
  /// dimensions, such as pixel art or sharp UI icons. It uses the provided 
  /// [alignment] to position the sprite within the target area without 
  /// applying any scaling.
  ///
  /// * [alignment]: How to position the fixed-size sprite within the destination.
  const factory SpriteFit.fixed({Alignment alignment}) = FixedFit;

  /// Creates a fit strategy that scales the sprite to cover the destination.
  ///
  /// [CoverFit] ensures that the entire destination area is filled with the 
  /// sprite, scaling it as needed while preserving aspect ratio. This is 
  /// commonly used for full-screen backgrounds where the exact framing 
  /// is less critical than covering the entire display.
  ///
  /// * [alignment]: How to align the overflow when covering the area.
  const factory SpriteFit.cover({Alignment alignment}) = CoverFit;

  /// Creates a fit strategy that scales the sprite to fit inside the destination.
  ///
  /// [ContainFit] scales the sprite as large as possible without overflowing 
  /// the destination, preserving its aspect ratio. This is the preferred 
  /// choice for character portraits or interactive objects that must 
  /// remain fully visible.
  ///
  /// * [alignment]: How to align the sprite within the remaining space.
  const factory SpriteFit.contain({Alignment alignment}) = ContainFit;

  /// Base constructor for all [SpriteFit] strategies.
  ///
  /// This constructor is kept protected and const to allow for efficient
  /// instantiation of specific fit implementations. It establishes the
  /// interface that all scaling strategies must follow.
  const SpriteFit();

  /// The flex weight this fit contributes to [GridMesh] layout.
  ///
  /// When [GridMesh] computes destination sizes, a column is flexible only if
  /// every cell in that column returns a non-null [flex]. A single null (i.e.,
  /// a [FixedFit] cell) anchors the column at its source pixel width. The same
  /// rule applies to rows.
  ///
  /// Returns null by default, meaning the cell is fixed at its source pixel
  /// size. Override with a positive value (typically `1.0`) in fits that should
  /// expand to fill available space.
  double? get flex => null;

  /// Draws the [image] region specified by [src] into the [dst] area on the [canvas].
  ///
  /// This method implements the specific scaling and alignment logic for the 
  /// strategy. It uses the provided [paint] to control visual properties 
  /// like opacity and blending during the drawing process.
  ///
  /// * [canvas]: The rendering target.
  /// * [image]: The source texture containing the sprite.
  /// * [src]: The sub-region of the image to render.
  /// * [dst]: The world-space area where the sprite should be drawn.
  /// * [paint]: The configuration for the draw call.
  void draw(
    ui.Canvas canvas,
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  );
}

/// A fit strategy that scales the sprite non-uniformly to fill the destination.
///
/// [StretchFit] ignores the aspect ratio of the source rectangle and 
/// forces it to match the dimensions of the target area. This is often 
/// used for UI backgrounds or health bars that must exactly match 
/// their container size.
///
/// ```dart
/// void example(ui.Canvas canvas, ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) {
///   const fit = SpriteFit.stretch;
///   fit.draw(canvas, image, src, dst, paint);
/// }
/// ```
///
/// See also:
/// * [SpriteFit.stretch], the constant instance of this class.
class StretchFit extends SpriteFit {
  /// Creates a new [StretchFit] instance.
  ///
  /// This constructor is const to allow for static usage via the 
  /// [SpriteFit.stretch] constant. It requires no configuration as the 
  /// stretching behavior is uniform across all instances.
  const StretchFit();

  @override
  double? get flex => 1.0;

  @override
  void draw(
    ui.Canvas canvas,
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) {
    canvas.drawImageRect(image, src, dst, paint);
  }
}

/// A fit strategy that tiles the sprite source rectangle across the destination.
///
/// [TileFit] repeats the specified source region in both horizontal and 
/// vertical directions to fill the destination area. It uses an [ui.ImageShader] 
/// with a calculated matrix to ensure the tiling pattern aligns correctly 
/// with the source and destination origins.
///
/// ```dart
/// void example(ui.Canvas canvas, ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) {
///   const fit = SpriteFit.tile;
///   fit.draw(canvas, image, src, dst, paint);
/// }
/// ```
///
/// See also:
/// * [SpriteFit.tile], the constant instance of this class.
class TileFit extends SpriteFit {
  /// Creates a new [TileFit] instance.
  ///
  /// This constructor is const to allow for static usage via the 
  /// [SpriteFit.tile] constant. It provides the base for repeating 
  /// texture patterns across arbitrary destination areas.
  const TileFit();

  /// Calculates the transformation matrix required to tile [src] into [dst].
  ///
  /// This matrix handles the translation and scaling needed to align the 
  /// [ui.ImageShader] with the target rendering coordinates. It ensures 
  /// that the top-left of the source rectangle matches the top-left of 
  /// the destination rectangle in world space.
  ///
  /// * [src]: The source region in pixel coordinates.
  /// * [dst]: The destination region in world coordinates.
  static Matrix4 computeMatrix(ui.Rect src, ui.Rect dst) {
    final double sx = dst.width / src.width;
    final double sy = dst.height / src.height;
    final matrix = Matrix4.identity();
    matrix.translateByDouble(
      dst.left - src.left * sx,
      dst.top - src.top * sy,
      0.0,
      1.0,
    );
    matrix.scaleByDouble(sx, sy, 1.0, 1.0);
    return matrix;
  }

  @override
  double? get flex => 1.0;

  @override
  void draw(
    ui.Canvas canvas,
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) {
    final originalShader = paint.shader;

    // ImageShader tiles the entire image.
    // To tile only a sub-rect 'src' into 'dst', we must use the matrix:
    final matrix = computeMatrix(src, dst);

    paint.shader = ui.ImageShader(
      image,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      matrix.storage,
    );

    canvas.drawRect(dst, paint);
    paint.shader = originalShader;
  }
}

/// A fit strategy that renders the sprite at its original pixel size.
///
/// [FixedFit] preserves the scale of the source rectangle and aligns it 
/// within the destination area using the provided [alignment]. If the 
/// destination is smaller than the source, the sprite will extend 
/// beyond the destination bounds.
///
/// ```dart
/// void example(ui.Canvas canvas, ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) {
///   final fit = SpriteFit.fixed(alignment: Alignment.bottomRight);
///   fit.draw(canvas, image, src, dst, paint);
/// }
/// ```
///
/// See also:
/// * [SpriteFit.fixed] for the factory constructor.
class FixedFit extends SpriteFit {
  /// The alignment of the sprite within the destination area.
  ///
  /// This determines how the fixed-size source rectangle is anchored 
  /// when placed into a larger destination rectangle. For example, 
  /// [Alignment.bottomRight] will pin the sprite to the bottom-right 
  /// corner of the target area.
  final Alignment alignment;

  /// Creates a [FixedFit] with the specified [alignment].
  ///
  /// * [alignment]: The anchor point for the sprite.
  const FixedFit({this.alignment = Alignment.center});

  @override
  void draw(
    ui.Canvas canvas,
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) {
    // Draws at src size, aligned in dst
    final rect = alignment.inscribe(src.size, dst);
    canvas.drawImageRect(image, src, rect, paint);
  }
}

/// A fit strategy that scales the sprite to completely cover the destination.
///
/// [CoverFit] maintaining the aspect ratio of the source while scaling 
/// it up until the entire destination area is filled. This often results 
/// in parts of the source rectangle being cropped, depending on the 
/// relative aspect ratios and the chosen [alignment].
///
/// ```dart
/// void example(ui.Canvas canvas, ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) {
///   final fit = SpriteFit.cover(alignment: Alignment.center);
///   fit.draw(canvas, image, src, dst, paint);
/// }
/// ```
///
/// See also:
/// * [SpriteFit.cover] for the factory constructor.
class CoverFit extends SpriteFit {
  /// The alignment used to center or offset the scaled sprite.
  ///
  /// Because [CoverFit] often results in cropping, this property 
  /// determines which part of the source rectangle remains visible. 
  /// A center alignment will crop equally from all sides, while a top 
  /// alignment will preserve the top portion of the image.
  final Alignment alignment;

  /// Creates a [CoverFit] with the specified [alignment].
  ///
  /// * [alignment]: The focus point for the scaled sprite.
  const CoverFit({this.alignment = Alignment.center});

  @override
  double? get flex => 1.0;

  @override
  void draw(
    ui.Canvas canvas,
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) {
    final FittedSizes sizes = applyBoxFit(BoxFit.cover, src.size, dst.size);
    final ui.Rect destinationRect = alignment.inscribe(sizes.destination, dst);
    final ui.Rect sourceRect = alignment.inscribe(sizes.source, src);
    canvas.drawImageRect(image, sourceRect, destinationRect, paint);
  }
}

/// A fit strategy that scales the sprite to fit entirely within the destination.
///
/// [ContainFit] maintains the aspect ratio of the source while scaling it 
/// as large as possible without exceeding the destination's bounds. This 
/// often leaves empty space (letterboxing) within the destination area, 
/// which is distributed according to the provided [alignment].
///
/// ```dart
/// void example(ui.Canvas canvas, ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) {
///   final fit = SpriteFit.contain(alignment: Alignment.topCenter);
///   fit.draw(canvas, image, src, dst, paint);
/// }
/// ```
///
/// See also:
/// * [SpriteFit.contain] for the factory constructor.
class ContainFit extends SpriteFit {
  /// The alignment used to position the fitted sprite.
  ///
  /// When the aspect ratios of the source and destination do not match, 
  /// [ContainFit] leaves empty space. This property determines how that 
  /// space is distributed around the centered sprite.
  final Alignment alignment;

  /// Creates a [ContainFit] with the specified [alignment].
  ///
  /// * [alignment]: The position of the sprite within the letterbox area.
  const ContainFit({this.alignment = Alignment.center});

  @override
  double? get flex => 1.0;

  @override
  void draw(
    ui.Canvas canvas,
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) {
    final FittedSizes sizes = applyBoxFit(BoxFit.contain, src.size, dst.size);
    final ui.Rect destinationRect = alignment.inscribe(sizes.destination, dst);
    canvas.drawImageRect(image, src, destinationRect, paint);
  }
}
