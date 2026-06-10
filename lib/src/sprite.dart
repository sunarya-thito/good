import 'dart:ui' as ui;
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/asset.dart';
import 'package:goo2d/src/point.dart';
import 'package:goo2d/src/sprite_mesh.dart';
import 'package:goo2d/src/component.dart';
import 'package:goo2d/src/lifecycle.dart';
import 'package:goo2d/src/render.dart';

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
/// Holds a [RenderHandle] (created when mounted, disposed when unmounted) so
/// that GPU resources such as [ui.FragmentShader] are properly managed.
class SpriteRenderer extends Behavior with Renderable, LifecycleListener {
  GameSprite? _sprite;
  RenderHandle? _handle;
  bool _mounted = false;

  GameSprite? get sprite => _sprite;

  set sprite(GameSprite? s) {
    _sprite = s;
    if (_mounted) {
      _handle?.dispose();
      _handle = s?.mesh.createHandle();
    }
  }

  /// Color tint applied via [blendMode].
  ui.Color color = const ui.Color(0xFFFFFFFF);

  bool flipX = false;
  bool flipY = false;

  ui.FilterQuality filterQuality = ui.FilterQuality.low;
  ui.BlendMode blendMode = ui.BlendMode.modulate;

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
  }

  @override
  void render(ui.Canvas canvas) {
    final sprite = _sprite;
    final handle = _handle;
    if (sprite == null || handle == null) return;

    final paint = ui.Paint()
      ..colorFilter = ui.ColorFilter.mode(color, blendMode)
      ..filterQuality = filterQuality;

    final p = sprite.pivotOffset;
    canvas.save();
    final scale = 1.0 / sprite.pixelsPerUnit;
    canvas.scale(scale, scale);
    canvas.translate(-p.dx, -p.dy);
    if (flipX || flipY) {
      canvas.scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0);
    }
    handle.render(canvas, size ?? sprite.size, paint);
    canvas.restore();
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
