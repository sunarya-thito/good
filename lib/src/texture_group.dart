import 'dart:ui' as ui;

import 'package:goo2d/src/asset.dart';

// Internal record of a single texture's placement in a sub-atlas.
class _PackedEntry {
  final GameTexture texture;
  // Pixel rect of the actual texture data (inner rect, excludes padding strips).
  final ui.Rect innerRect;
  bool isDisposed = false;

  _PackedEntry(this.texture, this.innerRect);
}

// Shelf-packer for one sub-atlas bounded by [maxDim].
class _Packer {
  final int maxDim;
  final int padding;

  int _curX = 0;
  int _curY = 0;
  int _curShelfH = 0;
  int _maxUsedW = 0;

  final List<_PackedEntry> entries = [];

  _Packer(this.maxDim, this.padding);

  /// Tries to place [tex] in this sub-atlas.
  /// Returns false if [tex] doesn't fit — caller should start a new packer.
  bool tryPlace(GameTexture tex) {
    final slotW = tex.width + 2 * padding;
    final slotH = tex.height + 2 * padding;
    if (slotW > maxDim || slotH > maxDim) return false;

    var x = _curX;
    var y = _curY;
    var shelfH = _curShelfH;

    if (x + slotW > maxDim) {
      y += shelfH;
      x = 0;
      shelfH = 0;
    }
    if (y + slotH > maxDim) return false;

    _curX = x + slotW;
    _curY = y;
    if (slotH > shelfH) shelfH = slotH;
    _curShelfH = shelfH;
    if (_curX > _maxUsedW) _maxUsedW = _curX;

    entries.add(_PackedEntry(
      tex,
      ui.Rect.fromLTWH(
        (x + padding).toDouble(),
        (y + padding).toDouble(),
        tex.width.toDouble(),
        tex.height.toDouble(),
      ),
    ));
    return true;
  }

  int get finalW => _maxUsedW;
  int get finalH => _curY + _curShelfH;
}

// ---------------------------------------------------------------------------
// SimpleTextureGroup
// ---------------------------------------------------------------------------

/// A [TextureGroup] backed by a single packed atlas image.
class SimpleTextureGroup extends TextureGroup {
  final ui.Image _packedImage;
  final Map<GameTexture, _PackedEntry> _entries;

  int _disposedCount = 0;
  bool _isDisposed = false;

  // TextureGroup has no explicit constructor — super() is called implicitly,
  // which triggers the id = _nextId++ field initializer.
  SimpleTextureGroup._(this._packedImage, this._entries);

  /// Direct access to the atlas image.
  ui.Image get packedImage => _packedImage;

  @override
  bool get isDisposed => _isDisposed;

  @override
  ui.Image? atlasImageFor(GameTexture tex) {
    if (_isDisposed) return null;
    final e = _entries[tex];
    return (e == null || e.isDisposed) ? null : _packedImage;
  }

  @override
  ui.Rect? atlasRectFor(GameTexture tex) {
    if (_isDisposed) return null;
    final e = _entries[tex];
    return (e == null || e.isDisposed) ? null : e.innerRect;
  }

  @override
  void onTextureUnloaded(GameTexture texture) {
    final e = _entries[texture];
    if (e == null || e.isDisposed) return;
    e.isDisposed = true;
    _disposedCount++;
    if (_disposedCount >= _entries.length) dispose();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _packedImage.dispose();
  }
}

// ---------------------------------------------------------------------------
// SplittedTextureGroup
// ---------------------------------------------------------------------------

/// A [TextureGroup] spanning multiple [SimpleTextureGroup] sub-atlases.
/// Created automatically by [groupTexture] when textures exceed [maxAtlasDim].
class SplittedTextureGroup extends TextureGroup {
  final List<SimpleTextureGroup> _subGroups;
  bool _isDisposed = false;

  SplittedTextureGroup._(this._subGroups);

  List<SimpleTextureGroup> get subGroups => List.unmodifiable(_subGroups);

  @override
  bool get isDisposed => _isDisposed;

  @override
  ui.Image? atlasImageFor(GameTexture tex) {
    if (_isDisposed) return null;
    for (final sub in _subGroups) {
      final img = sub.atlasImageFor(tex);
      if (img != null) return img;
    }
    return null;
  }

  @override
  ui.Rect? atlasRectFor(GameTexture tex) {
    if (_isDisposed) return null;
    for (final sub in _subGroups) {
      final r = sub.atlasRectFor(tex);
      if (r != null) return r;
    }
    return null;
  }

  @override
  void onTextureUnloaded(GameTexture texture) {
    for (final sub in _subGroups) {
      sub.onTextureUnloaded(texture);
    }
    if (_subGroups.every((s) => s.isDisposed)) dispose();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final sub in _subGroups) {
      sub.dispose();
    }
  }
}

// ---------------------------------------------------------------------------
// groupTexture
// ---------------------------------------------------------------------------

/// Packs [textures] into one or more atlas images and returns a [TextureGroup].
///
/// Returns [SimpleTextureGroup] when all fit in one atlas ≤ [maxAtlasDim] px,
/// or [SplittedTextureGroup] when multiple atlases are needed.
/// Unloaded textures are skipped silently.
///
/// [padding] px of border replication is drawn around each texture to prevent
/// bleeding at atlas edges (emulates GL_CLAMP_TO_EDGE for non-power-of-2 rects).
Future<TextureGroup> groupTexture(
  Iterable<GameTexture> textures, {
  int padding = 2,
  int maxAtlasDim = 4096,
}) async {
  final loaded = textures.where((t) => t.isLoaded).toList()
    ..sort((a, b) => b.height.compareTo(a.height)); // tallest first

  final normalPackers = <_Packer>[];
  final soloPackers = <_Packer>[];

  var current = _Packer(maxAtlasDim, padding);
  normalPackers.add(current);

  for (final tex in loaded) {
    final slotW = tex.width + 2 * padding;
    final slotH = tex.height + 2 * padding;

    if (slotW > maxAtlasDim || slotH > maxAtlasDim) {
      // Texture exceeds the combined-atlas limit — give it its own atlas.
      final dim = slotW > slotH ? slotW : slotH;
      final solo = _Packer(dim, padding);
      solo.tryPlace(tex);
      soloPackers.add(solo);
      continue;
    }

    if (!current.tryPlace(tex)) {
      current = _Packer(maxAtlasDim, padding);
      normalPackers.add(current);
      current.tryPlace(tex);
    }
  }

  final allPackers = [
    ...normalPackers.where((p) => p.entries.isNotEmpty),
    ...soloPackers,
  ];

  if (allPackers.isEmpty) {
    final rec = ui.PictureRecorder();
    // ignore: unused_local_variable
    final emptyCanvas = ui.Canvas(rec, const ui.Rect.fromLTRB(0, 0, 1, 1));
    final pic = rec.endRecording();
    final img = await pic.toImage(1, 1);
    pic.dispose();
    return SimpleTextureGroup._(img, <GameTexture, _PackedEntry>{});
  }

  final simpleGroups = <SimpleTextureGroup>[];

  for (final packer in allPackers) {
    final atlasW = _nextPow2(packer.finalW).clamp(1, 65536);
    final atlasH = _nextPow2(packer.finalH).clamp(1, 65536);

    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(
      rec,
      ui.Rect.fromLTWH(0, 0, atlasW.toDouble(), atlasH.toDouble()),
    );
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    for (final entry in packer.entries) {
      _drawTexturePadded(canvas, paint, entry.texture, entry.innerRect, padding);
    }

    final pic = rec.endRecording();
    final img = await pic.toImage(atlasW, atlasH);
    pic.dispose();

    simpleGroups.add(SimpleTextureGroup._(
      img,
      {for (final e in packer.entries) e.texture: e},
    ));
  }

  final TextureGroup topGroup = simpleGroups.length == 1
      ? simpleGroups.first
      : SplittedTextureGroup._(simpleGroups);

  for (final packer in allPackers) {
    for (final entry in packer.entries) {
      entry.texture.addTextureGroup(topGroup);
    }
  }

  return topGroup;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void _drawTexturePadded(
  ui.Canvas canvas,
  ui.Paint paint,
  GameTexture tex,
  ui.Rect inner,
  int padding,
) {
  final texW = inner.width;
  final texH = inner.height;
  final p = padding.toDouble();
  final srcFull = ui.Rect.fromLTWH(0, 0, texW, texH);
  final img = tex.image;

  canvas.drawImageRect(img, srcFull, inner, paint);

  if (padding <= 0) return;

  canvas.drawImageRect(img, ui.Rect.fromLTWH(0, 0, 1, texH),
      ui.Rect.fromLTWH(inner.left - p, inner.top, p, texH), paint);
  canvas.drawImageRect(img, ui.Rect.fromLTWH(texW - 1, 0, 1, texH),
      ui.Rect.fromLTWH(inner.right, inner.top, p, texH), paint);
  canvas.drawImageRect(img, ui.Rect.fromLTWH(0, 0, texW, 1),
      ui.Rect.fromLTWH(inner.left, inner.top - p, texW, p), paint);
  canvas.drawImageRect(img, ui.Rect.fromLTWH(0, texH - 1, texW, 1),
      ui.Rect.fromLTWH(inner.left, inner.bottom, texW, p), paint);
  // Corners
  canvas.drawImageRect(img, const ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Rect.fromLTWH(inner.left - p, inner.top - p, p, p), paint);
  canvas.drawImageRect(img, ui.Rect.fromLTWH(texW - 1, 0, 1, 1),
      ui.Rect.fromLTWH(inner.right, inner.top - p, p, p), paint);
  canvas.drawImageRect(img, ui.Rect.fromLTWH(0, texH - 1, 1, 1),
      ui.Rect.fromLTWH(inner.left - p, inner.bottom, p, p), paint);
  canvas.drawImageRect(img, ui.Rect.fromLTWH(texW - 1, texH - 1, 1, 1),
      ui.Rect.fromLTWH(inner.right, inner.bottom, p, p), paint);
}

int _nextPow2(int v) {
  if (v <= 1) return 1;
  v--;
  v |= v >> 1;
  v |= v >> 2;
  v |= v >> 4;
  v |= v >> 8;
  v |= v >> 16;
  return v + 1;
}
