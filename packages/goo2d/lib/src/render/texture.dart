import 'dart:ui' as ui;

import 'package:good/good.dart';

/// A decoded image, ready to draw.
///
/// **A payload, not a handle.** This is the `T` in `Asset<T>`, so it carries no
/// address, no loaded flag and no base class - `Asset` carries all of that,
/// once, for every payload type there will ever be. What is left here is the
/// thing the old class could never quite be: a plain wrapper whose only job is
/// keeping `dart:ui` out of the engine's signatures.
///
/// Named `Texture`, not `GameTexture`: concrete payload types drop the prefix.
/// Name the *handle* in a field - see [TextureAsset].
class Texture {
  Texture(this._image);

  final ui.Image _image;

  /// The decoded image's width in pixels.
  ///
  /// Discovered by the decode, never declared. The game isolate nine-slices
  /// with these and cannot decode to find out, so it reads them from
  /// [TextureInfo] instead - which leaves no declaration anywhere that a
  /// repack could make wrong.
  int get width => _image.width;

  /// The decoded image's height in pixels. See [width].
  int get height => _image.height;

  /// The decoded image. Reachable only through `Asset.value`, which throws on
  /// a copy that never loaded, so there is no per-payload guard here.
  ui.Image get image => _image;

  /// Releases the engine-side pixels. Called by [TextureLoader.unload]; a
  /// `ui.Image` holds memory the Dart GC does not account for, so dropping the
  /// reference is not enough.
  void dispose() => _image.dispose();
}

/// The handle a component field points at. `Asset<Texture>`, spelled so that
/// `DataPointer<TextureAsset>` reads as intended.
typedef TextureAsset = Asset<Texture>;

/// A texture's identity: where its bytes come from, and nothing else.
///
/// Nothing about the image's shape or how a sprite samples it lives here -
/// the pixel size is discovered at load ([TextureInfo]) and the filter is a
/// property of the sprite. Neither belongs here: a build pipeline that
/// repacks or recompresses an asset would be rewriting the asset's identity.
///
/// ```dart
/// static const playerTexture = TextureKey(BundleSource('player.png'));
/// ```
typedef TextureKey = AssetKey<Texture>;

/// How a sprite samples the texture it draws.
///
/// **A property of the sprite, not of the texture.** On the key it would be
/// part of the asset's identity, so a build pipeline that repacked an image
/// would be rewriting it, and one texture could not be drawn crisply in one
/// place and smoothly in another. Per sprite you can still give every sprite
/// sharing an image the same filter, and you can also mix them.
///
/// This is goo2d's own enum and not `dart:ui`'s `FilterQuality`, so the
/// engine's signatures and its component rows stay clear of third-party types:
/// the row stores this index, and only `DrawCanvas2D` ever translates it.
enum TextureFilter {
  /// Pick one texel. What pixel art wants, and what it *needs* -
  /// pair it with an integer sprite size or it shimmers as the sprite moves.
  nearest,

  /// Blend the neighbouring texels. Fine when the sprite is drawn at roughly
  /// its source size.
  linear,

  /// Mipmapped, and the default. Minifying a 64px image into a 12px sprite
  /// averages the texels it is skipping instead of picking one; nearest
  /// sampling there does not look retro, it shimmers, because the chosen
  /// texels change as the sprite moves.
  mipmap;

  /// The `dart:ui` value this maps to. Called once per draw run, never per
  /// quad.
  ui.FilterQuality get quality => switch (this) {
    TextureFilter.nearest => ui.FilterQuality.none,
    TextureFilter.linear => ui.FilterQuality.low,
    TextureFilter.mipmap => ui.FilterQuality.medium,
  };
}

/// What decoding a texture discovered, replicated to every isolate copy -
/// including the ones that can never hold the `ui.Image` itself.
///
/// This is how the game isolate learns an image's pixel size without decoding
/// anything. Plain data, so it survives the port hop.
class TextureInfo extends AssetInfo {
  const TextureInfo(this.width, this.height);

  final int width;
  final int height;
}

/// Turns a texture's bytes into a [Texture].
///
/// One of these for the payload type, registered once - never one per asset.
/// That is what leaves [TextureKey] as pure identity and lets a key be written
/// inline with no subclass.
///
/// Runs only on the isolate that can decode; a codec is engine-side state that
/// does not exist on the game isolate.
class TextureLoader extends AssetLoader<Texture> {
  const TextureLoader();

  /// Decodes the first frame only. A `Texture` is one image, so an animated
  /// GIF or APNG through here yields its first frame and nothing else.
  /// Animation is sprite-sheet work in this engine (see `SpriteFrame`), not a
  /// codec feature.
  @override
  Future<Texture> load(AssetKey<Texture> key) async {
    final bytes = await key.source.load();
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return Texture((await codec.getNextFrame()).image);
    } finally {
      // The codec is scaffolding; the decoded `ui.Image` it produced is what
      // the payload keeps and what [unload] later disposes.
      codec.dispose();
    }
  }

  @override
  void unload(Texture value) => value.dispose();

  @override
  AssetInfo describe(Texture value) => TextureInfo(value.width, value.height);
}
