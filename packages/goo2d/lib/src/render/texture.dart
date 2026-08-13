import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:goo/goo.dart';

/// A decoded image, ready to draw - the concrete [GameAssetInstance] a
/// `DataPointer<Texture>` component field points at.
///
/// Named `Texture`, not `GameTexture`: the `Game` prefix belongs to the
/// generic base types a user implements against ([GameAsset],
/// [GameAssetInstance], [GameAssetSource]), and concrete instance types drop
/// it.
///
/// # It is normal for this to hold no image
///
/// A `Texture` is *declared* (and therefore addressed - see [GameAssets]) on
/// both isolate copies, but only decoded on the one with Flutter attached.
/// The game isolate's copy holds the address and nothing else, forever, and
/// that is exactly what it needs: it writes the address into component rows
/// and never draws. Reading [image] there throws by name rather than
/// null-dereferencing.
class Texture extends GameAssetInstance {
  /// [sourceWidth]/[sourceHeight] are the *declared* pixel dimensions - see
  /// their doc. Both default to zero, meaning "not declared", which is the
  /// right answer for every texture nothing nine-slices.
  Texture({this.sourceWidth = 0, this.sourceHeight = 0});

  ui.Image? _image;

  /// The image's pixel dimensions **as declared**, readable on every isolate
  /// without decoding anything - `0` when the declaration did not state them.
  ///
  /// # Why this exists alongside [width]/[height]
  ///
  /// [width] and [height] report the *decoded* image's size, so they go
  /// through [image] and therefore through `requireLoaded()`. That makes them
  /// permanently unreadable on the game isolate (see the class doc), and the
  /// game isolate is exactly where `GameRenderer2D` runs.
  ///
  /// Nine-slicing needs a pixel size *there*: the border insets are in source
  /// pixels, so splitting the UV square at them means dividing by the image's
  /// width and height, and that division happens in the producer. There is no
  /// way to satisfy that from a decoded image - the producer has none, and
  /// giving it one would mean decoding on an isolate with no Flutter engine.
  ///
  /// So the size is *declared* instead of discovered. Both isolate copies run
  /// the same `describeAssets` pass over the same [TextureAsset], so both end
  /// up holding the same two integers, from declaration, with no decode and no
  /// cross-isolate message. [TextureAsset.loadInto] then checks the
  /// declaration against the real decode on the isolate that can, so a wrong
  /// number is a loud load-time failure rather than a subtly mis-sliced panel.
  ///
  /// Zero means undeclared, and a nine-sliced sprite whose texture is
  /// undeclared falls back to a single quad - see `GameRenderer2D`.
  final int sourceWidth;
  final int sourceHeight;

  /// Whether both [sourceWidth] and [sourceHeight] were declared, i.e. whether
  /// this texture can be nine-sliced. One named question rather than the same
  /// two comparisons at each call site.
  bool get hasSourceSize => sourceWidth > 0 && sourceHeight > 0;

  /// The decoded image.
  ///
  /// Throws on a copy that never loaded this asset - see the class doc; that
  /// includes the game isolate always, and the main isolate before
  /// `GameState.loadScene` (or an explicit `GameAssets.load`) has finished
  /// with it.
  ui.Image get image {
    requireLoaded();
    return _image!;
  }

  /// Pixel width of [image], with the same loaded requirement.
  int get width => image.width;

  /// Pixel height of [image], with the same loaded requirement.
  int get height => image.height;

  @override
  void onUnloaded() {
    super.onUnloaded();
    // A `ui.Image` holds engine-side memory that the Dart GC does not
    // account for, so dropping the reference is not enough - unloading a
    // texture has to actually give the pixels back.
    _image?.dispose();
    _image = null;
  }
}

/// The [GameAsset] key for a [Texture]: names where the encoded bytes live
/// and knows how to turn them into a `ui.Image`.
///
/// Declare one per texture, once, and share it - a key is identity-compared,
/// so two keys naming one file are two textures, two addresses and two
/// decodes (see [GameAssets]):
///
/// ```dart
/// class Player extends EntityStruct<Player> {
///   static final playerTexture = TextureAsset.bundle('assets/player.png');
///
///   late final Texture texture;
///
///   @override
///   void describeAssets(AssetDescriptor descriptor) {
///     super.describeAssets(descriptor);
///     texture = descriptor.has(playerTexture);
///   }
/// }
/// ```
class TextureAsset extends GameAsset<Texture> {
  TextureAsset(this.source, {this.pixelWidth = 0, this.pixelHeight = 0});

  /// The common case: an image packed into the Flutter asset bundle, named
  /// by the same path the pubspec declares it under.
  TextureAsset.bundle(
    String path, {
    AssetBundle? bundle,
    this.pixelWidth = 0,
    this.pixelHeight = 0,
  }) : source = AssetBundleSource(path, bundle: bundle);

  @override
  final GameAssetSource source;

  /// The image's pixel dimensions, stated here at declare time so the game
  /// isolate can know them without decoding - see [Texture.sourceWidth] for
  /// why that is the only arrangement that works.
  ///
  /// Optional, and only nine-slicing needs it: a sprite that draws the whole
  /// texture addresses it with normalised `0..1` UVs and never cares how many
  /// pixels that is. Leave both at zero unless a sprite slices this texture.
  ///
  /// Stating them wrong is caught, not tolerated - [loadInto] asserts the
  /// declaration against the decoded image.
  final int pixelWidth;
  final int pixelHeight;

  /// Synchronous and empty of I/O - this runs on both isolate copies during
  /// `describeAssets`, so it must not touch `dart:ui`. All it does is give
  /// [GameAssets] something to assign an address to, and hand that instance
  /// the declared pixel size, which is plain integer data and safe on any
  /// isolate.
  @override
  Texture createInstance() =>
      Texture(sourceWidth: pixelWidth, sourceHeight: pixelHeight);

  /// Reads the bytes and decodes the image's first frame.
  ///
  /// Main isolate only, and called only by `GameAssets.load` - a codec is
  /// engine-side state that does not exist on the game isolate.
  ///
  /// Only the first frame: a `Texture` is one image. An animated GIF or APNG
  /// decoded through here yields its first frame and nothing else, which is
  /// honest rather than silently half-supported - animation is sprite-sheet
  /// work in this engine, not a codec feature.
  @override
  Future<void> loadInto(Texture instance) async {
    final bytes = await source.load();
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      instance._image = frame.image;
      // The declared size is what the *game* isolate slices against, and it is
      // never checked there because there is nothing there to check it with.
      // This is the one isolate that holds both numbers, so it is the only
      // place the declaration can be caught being wrong - and a wrong one
      // silently mis-slices every panel drawn from this texture, which is a
      // bug that reads as "the art is off by a pixel" rather than as a typo.
      assert(
        pixelWidth == 0 && pixelHeight == 0 ||
            pixelWidth == frame.image.width && pixelHeight == frame.image.height,
        'TextureAsset declared ${pixelWidth}x$pixelHeight for '
        '${source.description}, but it decoded to '
        '${frame.image.width}x${frame.image.height}. The declared size is what '
        'the game isolate splits nine-slice UVs with, so it has to be the '
        'truth about the image.',
      );
    } finally {
      // The codec is scaffolding; the decoded `ui.Image` it produced is what
      // the instance keeps and what `Texture.onUnloaded` later disposes.
      codec.dispose();
    }
  }

  @override
  String get debugLabel => 'Texture(${source.description})';
}

/// Bytes from the Flutter asset bundle - the ordinary way a shipped game
/// names its content.
///
/// [bundle] is injectable purely so a test (or a game that ships a second
/// bundle) can supply its own; it defaults to `rootBundle`, which is what a
/// normal app wants and which only exists on the main isolate - the same
/// reason `GameAsset.loadInto` runs only there.
class AssetBundleSource extends GameAssetSource {
  const AssetBundleSource(this.path, {this.bundle});

  /// The pubspec-declared asset path, e.g. `assets/player.png`.
  final String path;

  /// The bundle to read from, or `null` for `rootBundle`.
  final AssetBundle? bundle;

  @override
  Future<Uint8List> load() async {
    final data = await (bundle ?? rootBundle).load(path);
    // A view, not a copy: `ByteData.buffer` may be larger than the asset when
    // the bundle packs several together, so the offset and length matter.
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  String get description => path;
}

/// Bytes already in memory - a procedurally generated image, a texture that
/// arrived over the network, a fixture in a test. Carries no I/O of its own.
class MemoryImageSource extends GameAssetSource {
  const MemoryImageSource(this.bytes, {this.name = 'in-memory'});

  final Uint8List bytes;

  /// What diagnostics call this source, since there is no path to name it by.
  final String name;

  @override
  Future<Uint8List> load() async => bytes;

  @override
  String get description => name;
}
