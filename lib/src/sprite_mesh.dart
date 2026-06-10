import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:goo2d/src/asset.dart';
import 'package:goo2d/src/point.dart';
import 'package:goo2d/src/sprite_fit.dart';

// 2D affine → column-major 4×4 Float64List for canvas.transform / ImageShader.
Float64List _affineToMatrix4(Float32List m) {
  // m = [a, b, c, d, tx, ty] where:
  //   a = cos*sx, b = -sin*sy, c = sin*sx, d = cos*sy
  // Column-major 4×4: indices [col*4+row]
  //   col0 = [a,c,0,0], col1 = [b,d,0,0], col2=[0,0,1,0], col3=[tx,ty,0,1]
  return Float64List.fromList([
    m[0], m[2], 0, 0, // col 0
    m[1], m[3], 0, 0, // col 1
    0, 0, 1, 0, // col 2
    m[4], m[5], 0, 1, // col 3
  ]);
}

// ---------------------------------------------------------------------------
// RenderHandle
// ---------------------------------------------------------------------------

/// A live handle to the GPU resources needed to render a [SpriteMesh].
///
/// Created via [SpriteMesh.createHandle]. The owner (a stateful widget or
/// component) must call [dispose] when it is unmounted to release native
/// resources such as [ui.FragmentShader].
abstract class RenderHandle {
  void render(ui.Canvas canvas, ui.Size size, ui.Paint paint);

  /// Renders the mesh using a pre-baked 2D affine [matrix] = [a, b, c, d, tx, ty].
  ///
  /// No canvas state changes are made outside this call. The canvas must already
  /// be in world space (camera transform applied once upstream). This is the
  /// primary render entry point for the new batching-friendly pipeline.
  void renderWithMatrix(
    ui.Canvas canvas,
    ui.Size size,
    ui.Paint paint,
    Float32List matrix,
  );

  void dispose();
}

// ---------------------------------------------------------------------------
// SpriteMesh
// ---------------------------------------------------------------------------

abstract class SpriteMesh {
  const SpriteMesh();

  /// The natural pixel size of this mesh (used for aspect-ratio and bounds).
  ui.Size get size;

  /// The primary texture of this mesh.
  ///
  /// For [GridMesh], throws a [StateError] if cells use more than one texture.
  GameTexture get texture;

  /// Source rectangle in texture-space coordinates, or `null` for the full texture.
  ///
  /// For [GridMesh] returns `null` — cells each own their own rect.
  ui.Rect? get srcRect;

  /// Returns a copy of this mesh with [tex] substituted as the texture.
  ///
  /// For [GridMesh], all cells are remapped to [tex].
  SpriteMesh withTexture(GameTexture tex);

  /// Returns a copy of this mesh with [r] as the source rectangle.
  ///
  /// For [GridMesh], throws a [StateError] — use cell-level access instead.
  SpriteMesh withSrcRect(ui.Rect? r);

  /// Creates a [RenderHandle] that owns GPU resources for this mesh.
  ///
  /// Call once when the owner mounts; dispose when the owner unmounts.
  RenderHandle createHandle();
}

// ---------------------------------------------------------------------------
// SimpleMesh
// ---------------------------------------------------------------------------

/// A single-region mesh that maps one texture rect to the destination area.
class SimpleMesh extends SpriteMesh {
  @override
  final GameTexture texture;
  @override
  final ui.Rect? srcRect;
  final SpriteFit fit;

  const SimpleMesh({
    required this.texture,
    this.srcRect,
    this.fit = const StretchFit(),
  });

  @override
  ui.Size get size {
    final r = srcRect;
    return r != null
        ? r.size
        : ui.Size(texture.width.toDouble(), texture.height.toDouble());
  }

  @override
  SimpleMesh withTexture(GameTexture tex) =>
      SimpleMesh(texture: tex, srcRect: srcRect, fit: fit);

  @override
  SimpleMesh withSrcRect(ui.Rect? r) =>
      SimpleMesh(texture: texture, srcRect: r, fit: fit);

  @override
  RenderHandle createHandle() => _SimpleMeshHandle(this);
}

class _SimpleMeshHandle extends RenderHandle {
  final SimpleMesh _mesh;
  _SimpleMeshHandle(this._mesh);

  @override
  void render(ui.Canvas canvas, ui.Size size, ui.Paint paint) {
    final tex = _mesh.texture;
    if (!tex.isLoaded) return;
    final src =
        _mesh.srcRect ??
        ui.Rect.fromLTWH(0, 0, tex.width.toDouble(), tex.height.toDouble());
    _mesh.fit.draw(canvas, tex.image, src, ui.Offset.zero & size, paint);
  }

  @override
  void renderWithMatrix(
    ui.Canvas canvas,
    ui.Size size,
    ui.Paint paint,
    Float32List matrix,
  ) {
    canvas.save();
    canvas.transform(_affineToMatrix4(matrix));
    render(canvas, size, paint);
    canvas.restore();
  }

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// MeshPart
// ---------------------------------------------------------------------------

/// One cell of a [GridMesh], carrying its own texture source and fit strategy.
///
/// Cells can be copied between grids with `mesh[(col, row)] = other[(col, row)]`,
/// enabling effects like giving specific corners of a rounded button sharp edges.
class MeshPart {
  final SpriteFit fit;
  final GameTexture texture;

  /// Sub-rectangle of [texture] used as the source. Defaults to the full texture.
  final ui.Rect? srcRect;

  const MeshPart({
    required this.fit,
    required this.texture,
    this.srcRect,
  });

  ui.Rect get rect =>
      srcRect ??
      ui.Rect.fromLTWH(
        0,
        0,
        texture.width.toDouble(),
        texture.height.toDouble(),
      );

  ui.Size get size => rect.size;
}

// ---------------------------------------------------------------------------
// TileCoord
// ---------------------------------------------------------------------------

/// Column/row index pair for addressing a cell in a [GridMesh] or tile in a sheet.
typedef TileCoord = (int x, int y);

// ---------------------------------------------------------------------------
// GridMesh constants
// ---------------------------------------------------------------------------

const int _kShaderMaxDim = 5;
const int _kMaxTextures = 4;

// ---------------------------------------------------------------------------
// GridMesh
// ---------------------------------------------------------------------------

/// A mesh that divides a sprite into a grid for sophisticated 9/25-slice scaling.
///
/// Cells (see [MeshPart]) are addressed by [TileCoord] via `[]` / `[]=`.
/// Swapping a cell from another [GridMesh] updates the visual only; the owning
/// [RenderHandle] detects the change via an internal version counter.
class GridMesh extends SpriteMesh {
  static ui.FragmentProgram? _program;

  // 1×1 transparent image used to pad unused sampler slots.
  static ui.Image? _placeholder;

  final List<MeshPart> _cells;
  final int _cols;

  // Incremented by operator[]= so handles can detect staleness.
  int _version = 0;

  int get _rows => _cells.length ~/ _cols;

  GridMesh({required List<MeshPart> cells, required int cols})
    : assert(cols > 0, 'GridMesh requires at least 1 column'),
      assert(
        cells.length % cols == 0,
        'cells.length must be a multiple of cols',
      ),
      _cells = List<MeshPart>.of(cells),
      _cols = cols;

  static Future<void> loadShader() async {
    if (_program == null) {
      try {
        _program = await ui.FragmentProgram.fromAsset(
          'packages/goo2d/shaders/grid_mesh.frag',
        );
      } catch (_) {
        _program = null;
      }
    }
    _placeholder ??= _makePlaceholder();
  }

  static ui.Image _makePlaceholder() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint()..color = const ui.Color(0x00000000),
    );
    return recorder.endRecording().toImageSync(1, 1);
  }

  @override
  ui.Size get size {
    double w = 0;
    for (int c = 0; c < _cols; c++) w += _cells[c].size.width;
    double h = 0;
    final rows = _rows;
    for (int r = 0; r < rows; r++) h += _cells[r * _cols].size.height;
    return ui.Size(w, h);
  }

  /// The shared texture of all cells.
  ///
  /// Throws [StateError] if cells use more than one distinct texture.
  @override
  GameTexture get texture {
    final first = _cells.first.texture;
    for (final cell in _cells) {
      if (!identical(cell.texture, first)) {
        throw StateError(
          'GridMesh has more than one texture; access cells individually.',
        );
      }
    }
    return first;
  }

  /// Returns a new [GridMesh] with every cell remapped to [tex].
  @override
  GridMesh withTexture(GameTexture tex) {
    return GridMesh(
      cells: _cells
          .map((c) => MeshPart(fit: c.fit, texture: tex, srcRect: c.srcRect))
          .toList(),
      cols: _cols,
    );
  }

  /// Always `null` — a [GridMesh] has no single source rectangle.
  @override
  ui.Rect? get srcRect => null;

  /// Not supported on [GridMesh] — cells each own their own source rect.
  @override
  GridMesh withSrcRect(ui.Rect? r) => throw StateError(
    'GridMesh has no single srcRect; use cell-level access.',
  );

  /// Returns the [MeshPart] at [coord] = `(col, row)`.
  MeshPart operator [](TileCoord coord) {
    final (col, row) = coord;
    assert(
      col >= 0 && col < _cols && row >= 0 && row < _rows,
      'MeshPart ($col, $row) out of bounds for ${_cols}×${_rows} grid',
    );
    return _cells[row * _cols + col];
  }

  /// Replaces the cell at [coord] with [part] and invalidates live handles.
  void operator []=(TileCoord coord, MeshPart part) {
    final (col, row) = coord;
    assert(
      col >= 0 && col < _cols && row >= 0 && row < _rows,
      'MeshPart ($col, $row) out of bounds for ${_cols}×${_rows} grid',
    );
    _cells[row * _cols + col] = part;
    _version++;
  }

  @override
  RenderHandle createHandle() => _GridMeshHandle(this);

  // -------------------------------------------------------------------------
  // Factories
  // -------------------------------------------------------------------------

  /// Standard 3×3 nine-slice mesh.
  ///
  /// [left]/[right]/[top]/[bottom] are measured from their respective edges.
  factory GridMesh.nineSlice({
    required GameTexture texture,
    ui.Rect? spriteRect,
    Point left = const Point.frac(1 / 3),
    Point top = const Point.frac(1 / 3),
    Point right = const Point.frac(1 / 3),
    Point bottom = const Point.frac(1 / 3),
    SpriteFit cornerFit = const FixedFit(),
    SpriteFit edgeFit = const StretchFit(),
    SpriteFit centerFit = const StretchFit(),
  }) {
    final r =
        spriteRect ??
        ui.Rect.fromLTWH(
          0,
          0,
          texture.width.toDouble(),
          texture.height.toDouble(),
        );
    final xs = [
      r.left,
      r.left + left.resolve(r.width),
      r.right - right.resolve(r.width),
      r.right,
    ];
    final ys = [
      r.top,
      r.top + top.resolve(r.height),
      r.bottom - bottom.resolve(r.height),
      r.bottom,
    ];
    final cells = <MeshPart>[];
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final isRowEdge = row == 0 || row == 2;
        final isColEdge = col == 0 || col == 2;
        cells.add(
          MeshPart(
            fit: (isRowEdge && isColEdge)
                ? cornerFit
                : (isRowEdge || isColEdge)
                ? edgeFit
                : centerFit,
            texture: texture,
            srcRect: ui.Rect.fromLTRB(
              xs[col],
              ys[row],
              xs[col + 1],
              ys[row + 1],
            ),
          ),
        );
      }
    }
    return GridMesh(cells: cells, cols: 3);
  }

  /// 5×5 twenty-five-slice mesh with double borders.
  factory GridMesh.twentyFiveSlice({
    required GameTexture texture,
    ui.Rect? spriteRect,
    Point leftOuter = const Point.frac(1 / 5),
    Point leftInner = const Point.frac(1 / 5),
    Point topOuter = const Point.frac(1 / 5),
    Point topInner = const Point.frac(1 / 5),
    Point rightOuter = const Point.frac(1 / 5),
    Point rightInner = const Point.frac(1 / 5),
    Point bottomOuter = const Point.frac(1 / 5),
    Point bottomInner = const Point.frac(1 / 5),
    SpriteFit centerFit = const StretchFit(),
    SpriteFit edgeCenterFit = const StretchFit(),
    SpriteFit edgeFit = const StretchFit(),
    SpriteFit cornerFit = const FixedFit(),
  }) {
    final r =
        spriteRect ??
        ui.Rect.fromLTWH(
          0,
          0,
          texture.width.toDouble(),
          texture.height.toDouble(),
        );
    final xs = [
      r.left,
      r.left + leftOuter.resolve(r.width),
      r.left + leftOuter.resolve(r.width) + leftInner.resolve(r.width),
      r.right - rightOuter.resolve(r.width) - rightInner.resolve(r.width),
      r.right - rightOuter.resolve(r.width),
      r.right,
    ];
    final ys = [
      r.top,
      r.top + topOuter.resolve(r.height),
      r.top + topOuter.resolve(r.height) + topInner.resolve(r.height),
      r.bottom - bottomOuter.resolve(r.height) - bottomInner.resolve(r.height),
      r.bottom - bottomOuter.resolve(r.height),
      r.bottom,
    ];
    final cells = <MeshPart>[];
    for (int row = 0; row < 5; row++) {
      for (int col = 0; col < 5; col++) {
        final SpriteFit fit;
        if (row != 2 && col != 2) {
          fit = cornerFit;
        } else {
          final distRow = (row - 2).abs();
          final distCol = (col - 2).abs();
          final maxDist = distRow > distCol ? distRow : distCol;
          fit = maxDist == 0
              ? centerFit
              : maxDist == 1
              ? edgeCenterFit
              : edgeFit;
        }
        cells.add(
          MeshPart(
            fit: fit,
            texture: texture,
            srcRect: ui.Rect.fromLTRB(
              xs[col],
              ys[row],
              xs[col + 1],
              ys[row + 1],
            ),
          ),
        );
      }
    }
    return GridMesh(cells: cells, cols: 5);
  }

  /// Horizontal 3×1 bar mesh (left cap | stretch | right cap).
  factory GridMesh.horizontalSliceBar({
    required GameTexture texture,
    ui.Rect? spriteRect,
    Point left = const Point.frac(1 / 3),
    Point right = const Point.frac(1 / 3),
    SpriteFit centerFit = const StretchFit(),
    SpriteFit edgeFit = const FixedFit(),
  }) {
    final r =
        spriteRect ??
        ui.Rect.fromLTWH(
          0,
          0,
          texture.width.toDouble(),
          texture.height.toDouble(),
        );
    final x0 = r.left;
    final x1 = r.left + left.resolve(r.width);
    final x2 = r.right - right.resolve(r.width);
    final x3 = r.right;
    return GridMesh(
      cells: [
        MeshPart(
          fit: edgeFit,
          texture: texture,
          srcRect: ui.Rect.fromLTRB(x0, r.top, x1, r.bottom),
        ),
        MeshPart(
          fit: centerFit,
          texture: texture,
          srcRect: ui.Rect.fromLTRB(x1, r.top, x2, r.bottom),
        ),
        MeshPart(
          fit: edgeFit,
          texture: texture,
          srcRect: ui.Rect.fromLTRB(x2, r.top, x3, r.bottom),
        ),
      ],
      cols: 3,
    );
  }

  /// Vertical 1×3 bar mesh (top cap | stretch | bottom cap).
  factory GridMesh.verticalSliceBar({
    required GameTexture texture,
    ui.Rect? spriteRect,
    Point top = const Point.frac(1 / 3),
    Point bottom = const Point.frac(1 / 3),
    SpriteFit centerFit = const StretchFit(),
    SpriteFit edgeFit = const FixedFit(),
  }) {
    final r =
        spriteRect ??
        ui.Rect.fromLTWH(
          0,
          0,
          texture.width.toDouble(),
          texture.height.toDouble(),
        );
    final y0 = r.top;
    final y1 = r.top + top.resolve(r.height);
    final y2 = r.bottom - bottom.resolve(r.height);
    final y3 = r.bottom;
    return GridMesh(
      cells: [
        MeshPart(
          fit: edgeFit,
          texture: texture,
          srcRect: ui.Rect.fromLTRB(r.left, y0, r.right, y1),
        ),
        MeshPart(
          fit: centerFit,
          texture: texture,
          srcRect: ui.Rect.fromLTRB(r.left, y1, r.right, y2),
        ),
        MeshPart(
          fit: edgeFit,
          texture: texture,
          srcRect: ui.Rect.fromLTRB(r.left, y2, r.right, y3),
        ),
      ],
      cols: 1,
    );
  }
}

// ---------------------------------------------------------------------------
// _GridMeshHandle
// ---------------------------------------------------------------------------

class _GridMeshHandle extends RenderHandle {
  final GridMesh _mesh;
  ui.FragmentShader? _shader;

  // Pre-built per-cell static arrays (25 slots for up to 5×5).
  final _modes = Float32List(25);
  final _alignX = Float32List(25);
  final _alignY = Float32List(25);
  final _srcX = Float32List(25); // cell.srcRect.left
  final _srcY = Float32List(25); // cell.srcRect.top
  final _texIdx = Float32List(25); // index into _uniqueTextures

  List<GameTexture> _uniqueTextures = const [];
  int _seenVersion = -1;

  _GridMeshHandle(this._mesh);

  // Rebuild static arrays when the mesh cells have changed.
  void _ensureStatic() {
    if (_seenVersion == _mesh._version) return;
    _seenVersion = _mesh._version;

    _shader?.dispose();
    _shader = null;

    final cells = _mesh._cells;
    final cols = _mesh._cols;
    final rows = _mesh._rows;

    // Collect unique textures (insertion order, max 4).
    final unique = <GameTexture>[];
    for (final cell in cells) {
      if (!unique.contains(cell.texture)) {
        unique.add(cell.texture);
        if (unique.length == _kMaxTextures) break;
      }
    }
    _uniqueTextures = unique;

    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 5; c++) {
        final i = r * 5 + c;
        if (r < rows && c < cols) {
          final cell = cells[r * cols + c];
          _modes[i] = cell.fit.meshMode.toDouble();
          _alignX[i] = cell.fit.alignment.x;
          _alignY[i] = cell.fit.alignment.y;
          final cr = cell.rect;
          _srcX[i] = cr.left;
          _srcY[i] = cr.top;
          _texIdx[i] = unique.indexOf(cell.texture).toDouble();
        } else {
          _modes[i] = _alignX[i] = _alignY[i] = 0;
          _srcX[i] = _srcY[i] = _texIdx[i] = 0;
        }
      }
    }
  }

  @override
  void render(ui.Canvas canvas, ui.Size size, ui.Paint paint) {
    _ensureStatic();

    final cells = _mesh._cells;
    final cols = _mesh._cols;
    final rows = _mesh._rows;

    // Cumulative source widths / heights.
    final xSrc = <double>[0.0];
    for (int c = 0; c < cols; c++) xSrc.add(xSrc.last + cells[c].size.width);
    final ySrc = <double>[0.0];
    for (int r = 0; r < rows; r++)
      ySrc.add(ySrc.last + cells[r * cols].size.height);

    // Flex weights for destination layout.
    final colFlex = List<double?>.generate(cols, (c) {
      for (int r = 0; r < rows; r++) {
        if ((cells[r * cols + c].fit.flex ?? 0) <= 0) return null;
      }
      return 1.0;
    });
    final rowFlex = List<double?>.generate(rows, (r) {
      for (int c = 0; c < cols; c++) {
        if ((cells[r * cols + c].fit.flex ?? 0) <= 0) return null;
      }
      return 1.0;
    });

    final xDst = _computeDestLines(xSrc, size.width, colFlex);
    final yDst = _computeDestLines(ySrc, size.height, rowFlex);

    final dst = ui.Offset.zero & size;
    final prog = GridMesh._program;

    if (prog != null && cols <= _kShaderMaxDim && rows <= _kShaderMaxDim) {
      _renderWithShader(canvas, dst, paint, prog, xSrc, ySrc, xDst, yDst);
    } else {
      _renderFallback(canvas, dst, paint, xDst, yDst);
    }
  }

  void _renderWithShader(
    ui.Canvas canvas,
    ui.Rect destination,
    ui.Paint paint,
    ui.FragmentProgram program,
    List<double> xSrc,
    List<double> ySrc,
    List<double> xDst,
    List<double> yDst,
  ) {
    for (final tex in _uniqueTextures) {
      if (!tex.isLoaded) return;
    }
    if (_uniqueTextures.isEmpty) return;

    _shader ??= program.fragmentShader();
    final shader = _shader!;

    // Dynamic uniforms — layout documented in grid_mesh.frag.
    shader.setFloat(0, destination.left);
    shader.setFloat(1, destination.top);
    for (int t = 0; t < 4; t++) {
      final tex = t < _uniqueTextures.length ? _uniqueTextures[t] : null;
      shader.setFloat(2 + t * 2, tex != null ? tex.width.toDouble() : 1.0);
      shader.setFloat(3 + t * 2, tex != null ? tex.height.toDouble() : 1.0);
    }
    for (int i = 0; i < 6; i++) {
      shader.setFloat(10 + i, i < xDst.length ? xDst[i] : xDst.last);
    }
    for (int i = 0; i < 6; i++) {
      shader.setFloat(16 + i, i < yDst.length ? yDst[i] : yDst.last);
    }
    for (int i = 0; i < 6; i++) {
      shader.setFloat(22 + i, i < xSrc.length ? xSrc[i] : xSrc.last);
    }
    for (int i = 0; i < 6; i++) {
      shader.setFloat(28 + i, i < ySrc.length ? ySrc[i] : ySrc.last);
    }
    shader.setFloat(34, _mesh._cols.toDouble());
    shader.setFloat(35, _mesh._rows.toDouble());

    // Static uniforms — pre-built by _ensureStatic.
    for (int i = 0; i < 25; i++) shader.setFloat(36 + i, _modes[i]);
    for (int i = 0; i < 25; i++) shader.setFloat(61 + i, _alignX[i]);
    for (int i = 0; i < 25; i++) shader.setFloat(86 + i, _alignY[i]);
    for (int i = 0; i < 25; i++) shader.setFloat(111 + i, _srcX[i]);
    for (int i = 0; i < 25; i++) shader.setFloat(136 + i, _srcY[i]);
    for (int i = 0; i < 25; i++) shader.setFloat(161 + i, _texIdx[i]);

    final placeholder = GridMesh._placeholder!;
    for (int t = 0; t < 4; t++) {
      final tex = t < _uniqueTextures.length ? _uniqueTextures[t] : null;
      shader.setImageSampler(t, tex?.image ?? placeholder);
    }

    final sp = ui.Paint()
      ..shader = shader
      ..blendMode = paint.blendMode
      ..isAntiAlias = paint.isAntiAlias;
    if (paint.colorFilter != null) sp.colorFilter = paint.colorFilter;

    canvas.drawRect(destination, sp);
  }

  void _renderFallback(
    ui.Canvas canvas,
    ui.Rect destination,
    ui.Paint paint,
    List<double> xDst,
    List<double> yDst,
  ) {
    final cells = _mesh._cells;
    final cols = _mesh._cols;
    final rows = _mesh._rows;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final cell = cells[r * cols + c];
        if (!cell.texture.isLoaded) continue;
        final dstRect = ui.Rect.fromLTRB(
          destination.left + xDst[c],
          destination.top + yDst[r],
          destination.left + xDst[c + 1],
          destination.top + yDst[r + 1],
        );
        if (dstRect.width <= 0 || dstRect.height <= 0) continue;
        cell.fit.draw(canvas, cell.texture.image, cell.rect, dstRect, paint);
      }
    }
  }

  static List<double> _computeDestLines(
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
          : totalFlex > 0
          ? (f / totalFlex) * available
          : 0.0;
      dst[i + 1] = dst[i] + segSize;
    }
    return dst;
  }

  @override
  void renderWithMatrix(
    ui.Canvas canvas,
    ui.Size size,
    ui.Paint paint,
    Float32List matrix,
  ) {
    // Temporary: apply world matrix via canvas transform, draw in local space.
    // Step 14 will replace this with a direct world-space drawVertices call.
    canvas.save();
    canvas.transform(_affineToMatrix4(matrix));
    render(canvas, size, paint);
    canvas.restore();
  }

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
  }
}
