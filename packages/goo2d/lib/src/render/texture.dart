import 'dart:ui' as ui;

import 'package:goo/goo.dart';

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

  /// Pixel dimensions of the decoded image.
  ///
  /// These used to be *declared* on the key (`TextureAsset.pixelWidth`) and
  /// checked against the decode with an `assert`, because the game isolate
  /// nine-slices with them and could not decode to find out. They are
  /// discovered here now and published to that isolate via [TextureInfo], so
  /// there is no declaration left to be wrong.
  int get width => _image.width;
  int get height => _image.height;

  /// The decoded image. Only reachable through `Asset.value`, which already
  /// refused on a copy that never loaded - so there is no per-payload
  /// `requireLoaded` guard to write any more.
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
/// property of the sprite. Both used to be on this key, and a build pipeline
/// that repacked or recompressed an asset would have been rewriting its
/// identity.
///
/// ```dart
/// static const playerTexture = TextureKey(BundleSource('player.png'));
/// ```
typedef TextureKey = AssetKey<Texture>;

/// How a sprite samples the texture it draws.
///
/// **A property of the sprite, not of the texture.** It used to be declared on
/// the texture key, which made it part of an asset's identity - so a build
/// pipeline that repacked an image would have been rewriting it, and one
/// texture could not be drawn crisply in one place and smoothly in another.
/// Per sprite is strictly wider: a game can still give every sprite sharing an
/// image the same filter, and can now also mix them.
///
/// goo2d's own enum rather than `dart:ui`'s `FilterQuality`, so the engine's
/// signatures and its component rows stay clear of third-party types - the row
/// stores this index, and only `DrawCanvas2D` ever translates it.
enum TextureFilter {
  /// Pick one texel. What deliberate pixel art wants, and what it *needs* -
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
/// One of these for the payload type, registered once, rather than one per
/// asset - which is what leaves [TextureKey] as pure identity and lets a key
/// be written inline with no subclass.
///
/// Runs only on the isolate that can decode; a codec is engine-side state that
/// does not exist on the game isolate.
class TextureLoader extends AssetLoader<Texture> {
  const TextureLoader();

  /// Decodes the first frame only. A `Texture` is one image; an animated GIF
  /// or APNG through here yields its first frame and nothing else, which is
  /// honest rather than silently half-supported - animation is sprite-sheet
  /// work in this engine (see `SpriteFrame`), not a codec feature.
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
