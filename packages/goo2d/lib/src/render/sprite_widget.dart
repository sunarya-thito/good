// `Texture` is a Flutter widget as well as goo2d's payload type, and the
// signatures here are all about the payload one. Nothing below spells it -
// that is the point, see [SpriteWidget] - but the hide keeps a later edit from
// silently binding the wrong `Texture`.
import 'package:flutter/widgets.dart' hide Texture;

import 'package:goo2d/src/render/render_2d.dart';
import 'package:goo2d/src/render/texture.dart';

/// Draws a texture, or one frame of a sprite sheet, as an ordinary Flutter
/// widget.
///
/// A game's menus, HUD and inventory are widgets, and they want the art the
/// game already loaded. This draws the `ui.Image` the engine decoded, so the
/// pixels in a menu icon and the pixels on the entity it stands for are the
/// same bytes.
///
/// ```dart
/// // whole texture
/// SpriteWidget(myPrefab.playerTexture)
///
/// // one cell of an 8x4 sheet
/// SpriteWidget(
///   myPrefab.characters,
///   frame: const SpriteFrame.grid(columns: 8, rows: 4, index: 12),
/// )
/// ```
///
/// # It takes the handle, not a key and not a path
///
/// [texture] is the [TextureAsset] a `describeAssets` pass returned and the
/// declarer kept in a field - the same handle a [Sprite] points at. There is
/// nothing to look up and no name to spell twice.
///
/// The alternative is `Image.asset` with a hand-written path, which decodes a
/// **second** copy into Flutter's `imageCache` and leaves the engine's copy
/// held: measured, a 256x256 image through both paths is 512 KiB, not 256.
/// This widget adds nothing to `imageCache` at all.
///
/// # Loading is the caller's, and an unloaded handle draws nothing
///
/// This is synchronous. It holds no future, never rebuilds itself when a load
/// completes and shows no placeholder: the texture is either decoded on this
/// isolate by the time the widget builds, or it is not.
///
/// When it is not, the widget occupies no space and paints nothing. It does
/// **not** throw. That is the call `DrawCanvas2D` already made for the
/// renderer, for the reason written there: a texture that is declared but
/// still decoding is the ordinary state of the first frames of a run, and
/// throwing on it took the whole app down. A hole in a menu is recoverable and
/// a crash is not.
///
/// # The type is never named `Texture`
///
/// `Texture` is also a widget in `package:flutter/widgets.dart`, so a file
/// importing both `material.dart` and `goo2d.dart` stops compiling the moment
/// it spells that name. Every type in this widget's signature - [TextureAsset],
/// [SpriteFrame], [TextureFilter] - is clear of the collision, which is what
/// makes it usable from ordinary widget code with no `hide` clause.
class SpriteWidget extends StatelessWidget {
  const SpriteWidget(
    this.texture, {
    super.key,
    this.frame = SpriteFrame.full,
    this.filter = TextureFilter.mipmap,
  });

  /// The decoded image to draw, as the handle a `describeAssets` pass
  /// returned.
  final TextureAsset texture;

  /// Which part of [texture] to draw. Defaults to all of it.
  ///
  /// The fractions are used as the constructor computed them, not through
  /// [SpriteFrame.pack] - a widget holds the object, and only a component row
  /// has to quantise it into u16 lanes.
  final SpriteFrame frame;

  /// How the image is sampled when the widget's box is not the frame's own
  /// pixel size. Same default as `Sprite`, for the same reason: a minified
  /// sprite sampled nearest shimmers.
  final TextureFilter filter;

  /// The frame's size in source pixels, or [Size.zero] when nothing is loaded
  /// to ask.
  ///
  /// Preferred, not imposed. `CustomPaint` constrains it, so the widget fills
  /// a tight box the way `SizedBox` or `Expanded` asks it to, and falls back
  /// to its natural pixel size when it is given a free choice - which is what
  /// stops `SpriteWidget` inside a `Column` from laying out at zero and
  /// looking like it failed to load.
  Size get _preferredSize {
    if (!texture.isLoaded) return Size.zero;
    final source = texture.value;
    return Size(frame.width * source.width, frame.height * source.height);
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: _preferredSize,
    painter: _SpritePainter(texture, frame, filter),
  );
}

/// One `drawImageRect` from the frame's pixel rectangle onto the widget's box.
class _SpritePainter extends CustomPainter {
  const _SpritePainter(this.texture, this.frame, this.filter);

  final TextureAsset texture;
  final SpriteFrame frame;
  final TextureFilter filter;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw nothing instead of throwing - see [SpriteWidget]. `Asset.value` is
    // what would throw, so this guard has to come before it.
    if (!texture.isLoaded) return;
    final source = texture.value;
    canvas.drawImageRect(
      source.image,
      // The fractions become pixels here, on main, where the decoded image is
      // the one thing that knows its own size. The game isolate cannot do this
      // conversion at all, so `SpriteFrame` stores fractions.
      Rect.fromLTWH(
        frame.u * source.width,
        frame.v * source.height,
        frame.width * source.width,
        frame.height * source.height,
      ),
      Offset.zero & size,
      Paint()..filterQuality = filter.quality,
    );
  }

  /// [texture] compared by identity: a [TextureAsset] is one handle per
  /// address, so two equal handles are the same object.
  ///
  /// `isLoaded` is part of it because a handle mutates when its load lands -
  /// same object, different pixels - and without it the first rebuild after a
  /// decode would keep painting nothing.
  @override
  bool shouldRepaint(_SpritePainter old) =>
      !identical(old.texture, texture) ||
      old.texture.isLoaded != texture.isLoaded ||
      old.frame.u != frame.u ||
      old.frame.v != frame.v ||
      old.frame.width != frame.width ||
      old.frame.height != frame.height ||
      old.filter != filter;
}
