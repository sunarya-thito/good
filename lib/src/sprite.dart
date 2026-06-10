import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:goo2d/goo2d.dart';

/// Factory that builds a [SpriteMesh] for a given texture region.
///
/// Used by [SpriteSheet] so each tile can get its own mesh (e.g. a
/// [GridMesh.nineSlice]) without the sheet needing to know the texture up
/// front. The default factory produces [SimpleMesh].
typedef SpriteMeshFactory = SpriteMesh Function(
  GameTexture texture,
  ui.Rect srcRect,
);

/// Default [SpriteMeshFactory]: wraps each tile in a [SimpleMesh].
SpriteMesh _defaultMeshFactory(GameTexture texture, ui.Rect srcRect) =>
    SimpleMesh(texture: texture, srcRect: srcRect);

// ---------------------------------------------------------------------------
// GameSprite
// ---------------------------------------------------------------------------

/// A sprite backed by a [SpriteMesh] that owns its own texture and source rect.
///
/// ```dart
/// final sprite = GameSprite(mesh: SimpleMesh(texture: Textures.player));
/// final nineSliced = GameSprite(mesh: GridMesh.nineSlice(texture: Textures.button));
/// ```
class GameSprite {
  /// The mesh that owns this sprite's texture(s) and rendering geometry.
  final SpriteMesh mesh;

  /// The point within the sprite that acts as its origin for transformations.
  final Point2D pivot;

  /// The number of pixels that correspond to one world unit.
  final double pixelsPerUnit;

  const GameSprite({
    required this.mesh,
    this.pivot = Point2D.center,
    this.pixelsPerUnit = 100.0,
  });

  /// The natural pixel size of the sprite, derived from [mesh].
  ui.Size get size => mesh.size;

  double get aspectRatio => size.width / size.height;

  /// Shortcut for [mesh.texture]. Throws if the mesh uses multiple textures.
  GameTexture get texture => mesh.texture;

  /// Resolved source rect: [mesh.srcRect] if set, otherwise the full mesh size.
  ui.Rect get rect =>
      mesh.srcRect ?? ui.Rect.fromLTWH(0, 0, size.width, size.height);

  /// Pivot offset in pixels from the sprite's top-left corner.
  ui.Offset get pivotOffset => pivot.compute(size);

  /// World-space bounding rectangle, taking [pixelsPerUnit] and [pivotOffset] into account.
  ui.Rect get bounds {
    final p = pivotOffset;
    return ui.Rect.fromLTWH(
      -p.dx / pixelsPerUnit,
      -p.dy / pixelsPerUnit,
      size.width / pixelsPerUnit,
      size.height / pixelsPerUnit,
    );
  }

  GameSprite copyWith({
    SpriteMesh? mesh,
    Point2D? pivot,
    double? pixelsPerUnit,
  }) {
    return GameSprite(
      mesh: mesh ?? this.mesh,
      pivot: pivot ?? this.pivot,
      pixelsPerUnit: pixelsPerUnit ?? this.pixelsPerUnit,
    );
  }
}

// ---------------------------------------------------------------------------
// SpriteRenderer
// ---------------------------------------------------------------------------

/// A component that renders a [GameSprite] onto the canvas.
///
/// Positions are pre-baked into world-space vertex coordinates using the
/// sibling [ObjectTransform], avoiding any per-entity canvas state changes.
/// [GridMesh] sprites delegate to [RenderHandle.renderWithMatrix] instead.
class SpriteRenderer extends Behavior with Renderable, LifecycleListener {
  GameSprite? _sprite;
  RenderHandle? _handle;
  bool _mounted = false;

  // Pre-baked world-space quad data: 4 corners (TL, TR, BL, BR).
  final Float32List _bakedPositions = Float32List(8);
  final Float32List _bakedUVs = Float32List(8);
  final Int32List _bakedColors = Int32List(4);
  ui.Image? _bakedAtlasImage;

  bool _positionsDirty = true;
  bool _uvsDirty = true;
  bool _colorDirty = true;
  int _lastTransformVersion = -1;
  ui.Size? _lastSize;
  bool _lastFlipX = false;
  bool _lastFlipY = false;

  // Shared across all SpriteRenderer instances — never mutated after init.
  static final Uint16List _kQuadIndices =
      Uint16List.fromList([0, 1, 2, 1, 3, 2]);
  static final Float64List _kIdentity4x4 = _makeIdentity();
  static Float64List _makeIdentity() {
    final m = Float64List(16);
    m[0] = m[5] = m[10] = m[15] = 1.0;
    return m;
  }

  GameSprite? get sprite => _sprite;

  set sprite(GameSprite? s) {
    _sprite = s;
    _positionsDirty = true;
    _uvsDirty = true;
    if (_mounted) {
      _handle?.dispose();
      _handle = s?.mesh.createHandle();
    }
  }

  /// Color tint (ARGB). Default is opaque white — no tint.
  ui.Color _color = const ui.Color(0xFFFFFFFF);
  ui.Color get color => _color;
  set color(ui.Color value) {
    if (_color == value) return;
    _color = value;
    _colorDirty = true;
  }

  bool flipX = false;
  bool flipY = false;
  ui.FilterQuality filterQuality = ui.FilterQuality.low;

  /// How this sprite blends with the canvas. Default is normal compositing.
  ui.BlendMode blendMode = ui.BlendMode.srcOver;

  /// Explicit render size in pixels. Defaults to [GameSprite.size].
  ui.Size? size;

  /// Swaps the texture on the current sprite's mesh via [SpriteMesh.withTexture].
  ///
  /// If no sprite is set yet, wraps [tex] in a bare [SimpleMesh].
  /// Setting to `null` clears the sprite.
  set texture(GameTexture? tex) {
    if (tex == null) {
      sprite = null;
    } else if (_sprite != null) {
      sprite = _sprite!.copyWith(mesh: _sprite!.mesh.withTexture(tex));
    } else {
      sprite = GameSprite(mesh: SimpleMesh(texture: tex));
    }
  }

  @override
  void onMounted() {
    _mounted = true;
    _handle = _sprite?.mesh.createHandle();
  }

  @override
  void onUnmounted() {
    _mounted = false;
    _handle?.dispose();
    _handle = null;
    _bakedAtlasImage = null;
  }

  void _rebakePositions(ObjectTransform transform, GameSprite sprite) {
    // worldMatrix.storage is Float64List in column-major 4×4 order.
    // col0=[a,c,0,0], col1=[b,d,0,0], col2=[0,0,1,0], col3=[tx,ty,0,1]
    final s = transform.worldMatrix.storage;
    final a = s[0], b = s[4], c = s[1], d = s[5];
    final tx = s[12], ty = s[13];

    final renderSize = size ?? sprite.size;
    final ppu = sprite.pixelsPerUnit;
    final p = sprite.pivot.compute(renderSize);

    // Local corners with pivot and PPU applied. Flip is UV-side only.
    final lx0 = -p.dx / ppu;
    final lx1 = (renderSize.width - p.dx) / ppu;
    final ly0 = -p.dy / ppu;
    final ly1 = (renderSize.height - p.dy) / ppu;

    // TL
    _bakedPositions[0] = a * lx0 + b * ly0 + tx;
    _bakedPositions[1] = c * lx0 + d * ly0 + ty;
    // TR
    _bakedPositions[2] = a * lx1 + b * ly0 + tx;
    _bakedPositions[3] = c * lx1 + d * ly0 + ty;
    // BL
    _bakedPositions[4] = a * lx0 + b * ly1 + tx;
    _bakedPositions[5] = c * lx0 + d * ly1 + ty;
    // BR
    _bakedPositions[6] = a * lx1 + b * ly1 + tx;
    _bakedPositions[7] = c * lx1 + d * ly1 + ty;

    _lastTransformVersion = transform.version;
    _lastSize = size;
  }

  void _rebakeUVs(GameSprite sprite) {
    final tex = sprite.texture;
    if (!tex.isLoaded) {
      _bakedAtlasImage = null;
      return;
    }
    final group = UsedTextures.resolveGroup(gameObject, tex);
    _bakedAtlasImage = group?.atlasImageFor(tex) ?? tex.image;

    final src = sprite.mesh.srcRect ??
        ui.Rect.fromLTWH(0, 0, tex.width.toDouble(), tex.height.toDouble());
    final r = group?.atlasRectFor(tex) ?? src;

    // Flip is applied by swapping UV extents rather than touching vertex positions.
    final uMin = flipX ? r.right : r.left;
    final uMax = flipX ? r.left : r.right;
    final vMin = flipY ? r.bottom : r.top;
    final vMax = flipY ? r.top : r.bottom;

    _bakedUVs[0] = uMin; _bakedUVs[1] = vMin; // TL
    _bakedUVs[2] = uMax; _bakedUVs[3] = vMin; // TR
    _bakedUVs[4] = uMin; _bakedUVs[5] = vMax; // BL
    _bakedUVs[6] = uMax; _bakedUVs[7] = vMax; // BR

    _lastFlipX = flipX;
    _lastFlipY = flipY;
  }

  @override
  void render(ui.Canvas canvas) {
    final sprite = _sprite;
    if (sprite == null) return;

    final transform = gameObject.tryGetComponent<ObjectTransform>();

    // GridMesh sprites: world matrix is applied by the handle (step 14 will
    // replace this with a direct world-space drawVertices call).
    if (sprite.mesh is GridMesh) {
      final handle = _handle;
      if (handle == null || transform == null) return;
      final ws = transform.worldMatrix.storage;
      final m = Float32List(6);
      m[0] = ws[0]; m[1] = ws[4]; // a, b
      m[2] = ws[1]; m[3] = ws[5]; // c, d
      m[4] = ws[12]; m[5] = ws[13]; // tx, ty
      final paint = ui.Paint()
        ..filterQuality = filterQuality
        ..blendMode = blendMode
        ..color = _color;
      handle.renderWithMatrix(canvas, size ?? sprite.size, paint, m);
      return;
    }

    // SimpleMesh: lazy-rebake geometry then emit a single drawVertices call.
    final tex = sprite.texture;
    if (!tex.isLoaded) return;

    if (_positionsDirty) {
      if (transform == null) return; // no transform, nothing to draw
      _rebakePositions(transform, sprite);
      _positionsDirty = false;
    } else if (transform != null &&
        (transform.version != _lastTransformVersion || size != _lastSize)) {
      _rebakePositions(transform, sprite);
    }

    if (_uvsDirty || flipX != _lastFlipX || flipY != _lastFlipY) {
      _rebakeUVs(sprite);
      _uvsDirty = false;
    }

    if (_colorDirty) {
      final v = _color.toARGB32();
      _bakedColors[0] = v;
      _bakedColors[1] = v;
      _bakedColors[2] = v;
      _bakedColors[3] = v;
      _colorDirty = false;
    }

    final atlasImage = _bakedAtlasImage;
    if (atlasImage == null) return;

    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        _bakedPositions,
        textureCoordinates: _bakedUVs,
        colors: _bakedColors,
        indices: _kQuadIndices,
      ),
      ui.BlendMode.modulate,
      ui.Paint()
        ..shader = ui.ImageShader(
          atlasImage,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          _kIdentity4x4,
        )
        ..filterQuality = filterQuality
        ..blendMode = blendMode,
    );
  }
}

// ---------------------------------------------------------------------------
// SheetEntry / SpriteSheet
// ---------------------------------------------------------------------------

/// A key-rect pair used by [TaggedSpriteSheet].
class SheetEntry<K> {
  final K key;
  final ui.Rect rect;
  const SheetEntry({required this.key, required this.rect});
}

abstract class SpriteSheet<K> {
  final GameTexture texture;
  const SpriteSheet({required this.texture});

  GameSprite getTileAt(K key);
  GameSprite operator [](K key) => getTileAt(key);

  const factory SpriteSheet.tagged({
    required GameTexture texture,
    required List<SheetEntry<K>> entries,
    Point2D pivot,
    double pixelsPerUnit,
    SpriteMeshFactory? meshFactory,
  }) = TaggedSpriteSheet<K>;

  static GridSpriteSheet grid({
    required GameTexture texture,
    required int rows,
    required int columns,
    ui.Offset offset = ui.Offset.zero,
    ui.Offset spacing = ui.Offset.zero,
    ui.Size? spriteSize,
    Point2D pivot = Point2D.center,
    double ppu = 100.0,
    SpriteMeshFactory? meshFactory,
  }) {
    return GridSpriteSheet(
      texture: texture,
      rows: rows,
      columns: columns,
      offset: offset,
      spacing: spacing,
      spriteSize: spriteSize,
      pivot: pivot,
      pixelsPerUnit: ppu,
      meshFactory: meshFactory,
    );
  }

  static List<GameSprite> split(
    GameTexture texture, {
    required int rows,
    required int columns,
    ui.Offset offset = ui.Offset.zero,
    ui.Size? spriteSize,
    Point2D pivot = Point2D.center,
    double ppu = 100.0,
    SpriteMeshFactory? meshFactory,
  }) {
    final factory = meshFactory ?? _defaultMeshFactory;
    final double width =
        spriteSize?.width ?? (texture.width - offset.dx) / columns;
    final double height =
        spriteSize?.height ?? (texture.height - offset.dy) / rows;

    final sprites = <GameSprite>[];
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < columns; x++) {
        final rect = ui.Rect.fromLTWH(
          offset.dx + x * width,
          offset.dy + y * height,
          width,
          height,
        );
        sprites.add(GameSprite(
          mesh: factory(texture, rect),
          pivot: pivot,
          pixelsPerUnit: ppu,
        ));
      }
    }
    return sprites;
  }
}

// ---------------------------------------------------------------------------
// TaggedSpriteSheet
// ---------------------------------------------------------------------------

class TaggedSpriteSheet<T> extends SpriteSheet<T> {
  final List<SheetEntry<T>> entries;
  final Point2D pivot;
  final double pixelsPerUnit;
  final SpriteMeshFactory? meshFactory;

  const TaggedSpriteSheet({
    required super.texture,
    required this.entries,
    this.pivot = Point2D.center,
    this.pixelsPerUnit = 100.0,
    this.meshFactory,
  });

  @override
  GameSprite getTileAt(T key) {
    final factory = meshFactory ?? _defaultMeshFactory;
    for (final entry in entries) {
      if (entry.key == key) {
        return GameSprite(
          mesh: factory(texture, entry.rect),
          pivot: pivot,
          pixelsPerUnit: pixelsPerUnit,
        );
      }
    }
    throw ArgumentError('Sprite with tag "$key" not found in sheet');
  }
}

// ---------------------------------------------------------------------------
// GridSpriteSheet
// ---------------------------------------------------------------------------

class GridSpriteSheet extends SpriteSheet<TileCoord> {
  final int rows;
  final int columns;
  final ui.Offset offset;
  final ui.Offset spacing;
  final ui.Size? spriteSize;
  final Point2D pivot;
  final double pixelsPerUnit;
  final SpriteMeshFactory? meshFactory;

  const GridSpriteSheet({
    required super.texture,
    required this.rows,
    required this.columns,
    this.offset = ui.Offset.zero,
    this.spacing = ui.Offset.zero,
    this.spriteSize,
    this.pivot = Point2D.center,
    this.pixelsPerUnit = 100.0,
    this.meshFactory,
  });

  @override
  GameSprite getTileAt(TileCoord key) {
    final (int keyX, int keyY) = key;
    if (keyX < 0 || keyX >= columns || keyY < 0 || keyY >= rows) {
      throw ArgumentError(
        'Coordinate $keyX, $keyY is out of bounds for sheet $columns x $rows',
      );
    }

    final double width = spriteSize?.width ??
        (texture.width - offset.dx - (columns - 1) * spacing.dx) / columns;
    final double height = spriteSize?.height ??
        (texture.height - offset.dy - (rows - 1) * spacing.dy) / rows;

    final rect = ui.Rect.fromLTWH(
      offset.dx + keyX * (width + spacing.dx),
      offset.dy + keyY * (height + spacing.dy),
      width,
      height,
    );

    final factory = meshFactory ?? _defaultMeshFactory;
    return GameSprite(
      mesh: factory(texture, rect),
      pivot: pivot,
      pixelsPerUnit: pixelsPerUnit,
    );
  }
}
