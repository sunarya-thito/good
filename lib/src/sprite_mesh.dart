import 'dart:ui' as ui;
import 'package:goo2d/src/sprite.dart';
import 'package:goo2d/src/sprite_fit.dart';

/// A geometry definition that determines how a sprite is mapped to the screen.
///
/// [SpriteMesh] provides the infrastructure for complex sprite rendering 
/// techniques, such as 9-slice scaling and grid-based deformations. It 
/// decouples the raw sprite data from its visual representation, allowing 
/// for dynamic resizing while preserving specific regions like corners or 
/// borders.
///
/// ```dart
/// class CustomMesh extends SpriteMesh {
///   @override
///   void render(ui.Canvas canvas, GameSprite sprite, ui.Size size, ui.Paint paint) {
///     // Custom rendering logic
///   }
/// }
/// ```
///
/// See also:
/// * [SimpleMesh] for standard, single-region rendering.
/// * [GridMesh] for advanced multi-slice scaling (9-slice, 25-slice).
abstract class SpriteMesh {
  /// Base constructor for all [SpriteMesh] implementations.
  ///
  /// This constructor is kept const to enable efficient sharing of mesh 
  /// definitions across multiple game objects. It establishes the contract 
  /// for custom rendering logic in the Goo2D engine.
  const SpriteMesh();

  /// Renders the [sprite] onto the [canvas] at the specified [destinationSize].
  ///
  /// This method is responsible for dividing the sprite into sub-regions 
  /// and applying the appropriate scaling and alignment logic for each 
  /// part. It uses the provided [paint] to control global properties 
  /// like opacity and color filters.
  ///
  /// * [canvas]: The rendering target.
  /// * [sprite]: The source image and region data.
  /// * [destinationSize]: The total area to fill in world coordinates.
  /// * [paint]: Visual configuration for the draw call.
  void render(
    ui.Canvas canvas,
    GameSprite sprite,
    ui.Size destinationSize,
    ui.Paint paint,
  );
}

/// A basic mesh that maps the entire sprite to the destination area.
///
/// [SimpleMesh] is the default rendering strategy for most sprites. It 
/// uses a single [SpriteFit] to determine how the source rectangle should 
/// be scaled and aligned within the target dimensions, making it suitable 
/// for characters, props, and simple icons.
///
/// ```dart
/// void example(ui.Canvas canvas, GameSprite sprite, ui.Size size, ui.Paint paint) {
///   const mesh = SimpleMesh(fit: SpriteFit.contain());
///   mesh.render(canvas, sprite, size, paint);
/// }
/// ```
///
/// See also:
/// * [SpriteFit] for the scaling strategies used by this mesh.
class SimpleMesh extends SpriteMesh {
  /// The scaling and alignment strategy used by this mesh.
  ///
  /// This property determines how the sprite is fitted into the target 
  /// area. For example, using [SpriteFit.contain] will ensure the sprite 
  /// remains fully visible within the destination bounds.
  final SpriteFit fit;

  /// Creates a [SimpleMesh] with the specified [fit] strategy.
  ///
  /// This constructor defaults to [SpriteFit.fixed], which renders the 
  /// sprite at its original pixel size. Using a const constructor allows 
  /// this mesh to be reused across many sprites efficiently.
  ///
  /// * [fit]: The strategy for scaling the sprite.
  const SimpleMesh({this.fit = const SpriteFit.fixed()});

  @override
  void render(
    ui.Canvas canvas,
    GameSprite sprite,
    ui.Size destinationSize,
    ui.Paint paint,
  ) {
    fit.draw(
      canvas,
      sprite.texture.image,
      sprite.rect,
      ui.Rect.fromLTWH(0, 0, destinationSize.width, destinationSize.height),
      paint,
    );
  }
}

/// A mesh that divides a sprite into a grid for sophisticated scaling.
///
/// [GridMesh] implements flexible multi-slice scaling, supporting both 
/// standard 9-slice (3x3) and complex 25-slice (5x5) configurations. This 
/// allows UI elements like buttons and panels to resize without 
/// distorting their borders or corners.
///
/// ```dart
/// void example(ui.Canvas canvas, GameSprite sprite, ui.Size size, ui.Paint paint) {
///   final mesh = GridMesh.nineSlice(
///     left: 10, top: 10, right: 10, bottom: 10,
///   );
///   mesh.render(canvas, sprite, size, paint);
/// }
/// ```
///
/// See also:
/// * [GridMesh.nineSlice] for the most common usage pattern.
/// * [GridMesh.twentyFiveSlice] for highly detailed scaling needs.
class GridMesh extends SpriteMesh {
  /// The horizontal pixel offsets defining the vertical slicing lines.
  ///
  /// These borders determine which parts of the sprite are treated as 
  /// fixed-width corners/edges and which parts are scalable center regions.
  final List<double> xBorders;

  /// The vertical pixel offsets defining the horizontal slicing lines.
  ///
  /// These borders determine which parts of the sprite are treated as 
  /// fixed-height corners/edges and which parts are scalable center regions.
  final List<double> yBorders;

  /// A function that provides the [SpriteFit] for a specific grid cell.
  ///
  /// This allows for granular control over how each slice is rendered.
  /// Typically, corners use [FixedFit] while edges and the center use
  /// [StretchFit] or [TileFit].
  final SpriteFit Function(int row, int col) fitProvider;

  late final int _rows;
  late final int _cols;

  /// Flat row-major cache of all cell fits.
  late final List<SpriteFit> _fits;

  /// Per-column flex values derived from [_fits].
  late final List<double?> _colFlex;

  /// Per-row flex values derived from [_fits].
  late final List<double?> _rowFlex;

  /// Creates a [GridMesh] with explicit borders and a fit provider.
  ///
  /// This low-level constructor allows for non-standard grid configurations.
  /// For most UI needs, the [GridMesh.nineSlice] or [GridMesh.twentyFiveSlice]
  /// factories are more convenient and readable.
  ///
  /// * [xBorders]: Horizontal slice offsets.
  /// * [yBorders]: Vertical slice offsets.
  /// * [fitProvider]: Logic for cell-specific scaling.
  GridMesh({
    required this.xBorders,
    required this.yBorders,
    required this.fitProvider,
  }) {
    _rows = yBorders.length + 1;
    _cols = xBorders.length + 1;
    _fits = List<SpriteFit>.generate(
      _rows * _cols,
      (i) => fitProvider(i ~/ _cols, i % _cols),
    );
    _colFlex = List<double?>.generate(_cols, (col) {
      for (int row = 0; row < _rows; row++) {
        if ((_fits[row * _cols + col].flex ?? 0) <= 0) return null;
      }
      return 1.0;
    });
    _rowFlex = List<double?>.generate(_rows, (row) {
      for (int col = 0; col < _cols; col++) {
        if ((_fits[row * _cols + col].flex ?? 0) <= 0) return null;
      }
      return 1.0;
    });
  }

  /// Creates a standard 9-slice mesh for adaptive UI elements.
  ///
  /// [GridMesh.nineSlice] divides the sprite into a 3x3 grid where the 
  /// corners remain at a fixed size, the edges scale in one dimension, 
  /// and the center scales in both. This prevents distortion of decorative 
  /// frame elements during resizing.
  ///
  /// * [left]: Pixel width of the left columns.
  /// * [top]: Pixel height of the top rows.
  /// * [right]: Pixel width of the right columns.
  /// * [bottom]: Pixel height of the bottom rows.
  /// * [centerFit]: How to fit the 1x1 center area.
  /// * [edgeFit]: How to fit the 1x3 and 3x1 edge areas.
  /// * [cornerFit]: How to fit the 1x1 corner areas.
  factory GridMesh.nineSlice({
    required double left,
    required double top,
    required double right,
    required double bottom,
    SpriteFit centerFit = const StretchFit(),
    SpriteFit edgeFit = const StretchFit(),
    SpriteFit cornerFit = const FixedFit(),
  }) {
    return GridMesh(
      xBorders: [left, right],
      yBorders: [top, bottom],
      fitProvider: (row, col) {
        final isRowEdge = row == 0 || row == 2;
        final isColEdge = col == 0 || col == 2;
        if (isRowEdge && isColEdge) return cornerFit;
        if (isRowEdge || isColEdge) return edgeFit;
        return centerFit;
      },
    );
  }

  /// Creates a complex 25-slice mesh for high-fidelity adaptive visuals.
  ///
  /// [GridMesh.twentyFiveSlice] divides the sprite into a 5x5 grid, 
  /// offering more control over complex borders and transitions. This is 
  /// useful for windows with double-borders or specific interior patterns 
  /// that must be preserved during scaling.
  ///
  /// * [leftOuter]: Outer left border width.
  /// * [leftInner]: Inner left border width.
  /// * [topOuter]: Outer top border height.
  /// * [topInner]: Inner top border height.
  /// * [rightOuter]: Outer right border width.
  /// * [rightInner]: Inner right border width.
  /// * [bottomOuter]: Outer bottom border height.
  /// * [bottomInner]: Inner bottom border height.
  /// * [centerFit]: How to fit the central core.
  /// * [edgeCenterFit]: How to fit the inner edges.
  /// * [edgeFit]: How to fit the outer edges.
  /// * [cornerFit]: How to fit the outer corners.
  factory GridMesh.twentyFiveSlice({
    required double leftOuter,
    required double leftInner,
    required double topOuter,
    required double topInner,
    required double rightOuter,
    required double rightInner,
    required double bottomOuter,
    required double bottomInner,
    SpriteFit centerFit = const StretchFit(),
    SpriteFit edgeCenterFit = const StretchFit(),
    SpriteFit edgeFit = const StretchFit(),
    SpriteFit cornerFit = const FixedFit(),
  }) {
    return GridMesh(
      xBorders: [leftOuter, leftInner, rightInner, rightOuter],
      yBorders: [topOuter, topInner, bottomInner, bottomOuter],
      fitProvider: (row, col) {
        // Cells at the intersection of a border row and border column are fixed
        // in both dimensions. Returning cornerFit (FixedFit by default) ensures
        // GridMesh anchors those columns and rows at their source pixel size.
        // Visual output is identical to the previous edgeFit/edgeCenterFit since
        // cellDst.size == cellSrc.size for all such cells.
        if (row != 2 && col != 2) return cornerFit;

        final distRow = (row - 2).abs();
        final distCol = (col - 2).abs();
        final maxDist = distRow > distCol ? distRow : distCol;

        if (maxDist == 0) return centerFit;
        if (maxDist == 1) return edgeCenterFit;
        return edgeFit;
      },
    );
  }

  @override
  void render(
    ui.Canvas canvas,
    GameSprite sprite,
    ui.Size destinationSize,
    ui.Paint paint,
  ) {
    final src = sprite.rect;

    final List<double> xSrc = _computeSourceLines(xBorders, src.width);
    final List<double> ySrc = _computeSourceLines(yBorders, src.height);

    final List<double> xDst = _computeDestLines(xSrc, destinationSize.width, _colFlex);
    final List<double> yDst = _computeDestLines(ySrc, destinationSize.height, _rowFlex);

    for (int row = 0; row < _rows; row++) {
      for (int col = 0; col < _cols; col++) {
        final cellSrc = ui.Rect.fromLTWH(
          src.left + xSrc[col],
          src.top + ySrc[row],
          xSrc[col + 1] - xSrc[col],
          ySrc[row + 1] - ySrc[row],
        );
        final cellDst = ui.Rect.fromLTWH(
          xDst[col],
          yDst[row],
          xDst[col + 1] - xDst[col],
          yDst[row + 1] - yDst[row],
        );

        if (cellSrc.width <= 0 ||
            cellSrc.height <= 0 ||
            cellDst.width <= 0 ||
            cellDst.height <= 0) {
          continue;
        }

        _fits[row * _cols + col].draw(canvas, sprite.texture.image, cellSrc, cellDst, paint);
      }
    }
  }

  List<double> _computeSourceLines(List<double> borders, double total) {
    final int half = borders.length ~/ 2;
    final List<double> lines = [0.0];

    double current = 0.0;
    for (int i = 0; i < half; i++) {
      current += borders[i];
      lines.add(current);
    }

    final List<double> rightLines = [];
    current = total;
    for (int i = borders.length - 1; i >= half; i--) {
      current -= borders[i];
      rightLines.add(current);
    }

    lines.addAll(rightLines.reversed);
    lines.add(total);
    return lines;
  }

  List<double> _computeDestLines(
    List<double> srcLines,
    double destTotal,
    List<double?> flex,
  ) {
    final count = srcLines.length;

    double fixedSum = 0.0;
    double totalFlex = 0.0;
    for (int i = 0; i < count - 1; i++) {
      final f = flex[i];
      if (f == null || f <= 0) {
        fixedSum += srcLines[i + 1] - srcLines[i];
      } else {
        totalFlex += f;
      }
    }

    final available = (destTotal - fixedSum).clamp(0.0, double.infinity);
    final dst = List<double>.filled(count, 0.0);
    for (int i = 0; i < count - 1; i++) {
      final f = flex[i];
      final segSize = (f == null || f <= 0)
          ? srcLines[i + 1] - srcLines[i]
          : totalFlex > 0 ? (f / totalFlex) * available : 0.0;
      dst[i + 1] = dst[i] + segSize;
    }

    return dst;
  }
}
