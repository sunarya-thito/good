import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as soloud;
import 'package:http/http.dart' as http;

/// A source from which raw asset data can be retrieved.
///
/// This interface abstracts the underlying storage mechanism, whether it is
/// the local file system, an application bundle, or a remote server. It
/// ensures that the engine can treat all byte streams uniformly during
/// the loading process.
///
/// Implementing this class allows for custom loading strategies, such as
/// encrypted archives or database-backed assets.
///
/// ```dart
/// final source = AssetSource.local('assets/image.png');
/// await source.loadBytes();
/// ```
///
/// See also:
/// * [LocalSource] for loading data from the application bundle.
/// * [NetworkSource] for retrieving data over the network.
abstract interface class AssetSource {
  /// Loads the raw bytes from the specified source.
  ///
  /// This method is called internally by [GameAsset] during its initialization
  /// phase. It returns a [Uint8List] containing the complete file data.
  Future<Uint8List> loadBytes();

  /// The human-readable name or path identifier for this source.
  ///
  /// This is primarily used for debugging and logging purposes to identify
  /// which asset failed to load or is consuming excessive memory.
  String get name;

  /// Creates a source that loads data from the local asset bundle.
  ///
  /// * [path]: The relative path to the asset within the project bundle.
  factory AssetSource.local(String path) = LocalSource;

  /// Creates a source that fetches data from a remote network location.
  ///
  /// * [uri]: The full URL to the asset.
  /// * [headers]: Optional HTTP headers for the request (e.g., authentication).
  factory AssetSource.network(Uri uri, {Map<String, String>? headers}) =
      NetworkSource;
}

/// An [AssetSource] that reads from the application's root bundle.
///
/// This is the standard source for assets packaged with the game, providing
/// fast access to local files through the platform's asset management system.
///
/// ```dart
/// final source = LocalSource('assets/image.png');
/// await source.loadBytes();
/// ```
///
/// See also:
/// * [AssetSource] for the base source interface.
class LocalSource implements AssetSource {
  /// The path to the local asset.
  ///
  /// This string identifies the resource within the application's asset
  /// bundle. It is used by [rootBundle] to locate and read the raw bytes.
  final String path;

  /// Creates a new local source for the given [path].
  ///
  /// * [path]: The relative path to the asset.
  LocalSource(this.path);

  @override
  Future<Uint8List> loadBytes() {
    return rootBundle.load(path).then((data) => data.buffer.asUint8List());
  }

  @override
  String get name => path;
}

/// An [AssetSource] that retrieves data over HTTP.
///
/// This source is used for dynamic content that is not bundled with the
/// application, allowing for OTA updates or cloud-hosted resources.
///
/// ```dart
/// final uri = Uri.parse('https://example.com/asset.png');
/// final source = NetworkSource(uri);
/// await source.loadBytes();
/// ```
///
/// See also:
/// * [AssetSource] for the base source interface.
class NetworkSource implements AssetSource {
  /// The remote URL of the asset.
  ///
  /// This URI specifies the network location from which the asset will be
  /// downloaded. It must be a valid, reachable endpoint.
  final Uri uri;

  /// Optional HTTP headers for the fetch request.
  ///
  /// These can be used for authentication, content-type specification, or
  /// other request metadata required by the server hosting the asset.
  final Map<String, String>? headers;

  /// Creates a new network source for the given [uri].
  ///
  /// * [uri]: The remote URL.
  /// * [headers]: Optional HTTP headers.
  NetworkSource(this.uri, {this.headers});

  @override
  Future<Uint8List> loadBytes() {
    return http
        .get(uri, headers: headers)
        .then((response) => response.bodyBytes);
  }

  @override
  String get name => uri.pathSegments.lastOrNull ?? uri.toString();
}

/// A mixin for enums that represent a registry of game assets.
///
/// This mixin allows for a declarative way to define assets using enums,
/// which is a common pattern for managing game resources. It handles
/// the registration and caching of the actual [GameAsset] instances.
///
/// By using this mixin, developers can access assets using enum values
/// while maintaining type safety and centralized loading.
///
/// ```dart
/// enum MyImages with TextureAssetEnum {
///   player('assets/player.png'),
///   enemy('assets/enemy.png');
///
///   const MyImages(this.path);
///   final String path;
///
///   @override
///   AssetSource get source => AssetSource.local(path);
/// }
/// ```
mixin AssetEnum on Enum implements GameAsset {
  static final Map<Enum, GameAsset> _registries = {};

  /// Registers the actual [GameAsset] instance associated with this enum value.
  ///
  /// This is called internally when the [asset] getter is first accessed.
  @protected
  GameAsset createAsset();

  /// Retrieves the [GameAsset] instance for this enum value, creating it if necessary.
  ///
  /// This getter ensures that each enum value maps to a unique, cached
  /// asset instance, preventing redundant allocations and double-loading.
  GameAsset get asset => _registries.putIfAbsent(this, createAsset);

  /// Resets the internal asset registry.
  ///
  /// This is intended for use in tests to ensure a clean state between
  /// test runs, avoiding leaks from previous executions.
  @visibleForTesting
  static void reset() {
    _registries.clear();
  }

  @override
  Future<void> load() => asset.load();

  @override
  bool get isLoaded => asset.isLoaded;

  @override
  void unload() => asset.unload();
}

/// A specialized mixin for enums representing textures.
///
/// This extends [AssetEnum] to provide texture-specific properties and
/// methods directly on the enum values, such as [width], [height], and
/// pixel manipulation functions.
mixin TextureAssetEnum on AssetEnum implements GameTexture {
  @override
  GameAsset createAsset() => GameTexture(source);

  GameTexture get _instance => asset as GameTexture;

  @override
  int get width => _instance.width;

  @override
  int get height => _instance.height;

  @override
  ui.Image get image => _instance.image;

  @override
  Future<void> apply() => _instance.apply();

  @override
  ui.Color getPixel(int x, int y) => _instance.getPixel(x, y);

  @override
  ui.Color getPixelBilinear(double u, double v) =>
      _instance.getPixelBilinear(u, v);

  @override
  Uint8List getPixelData() => _instance.getPixelData();

  @override
  List<ui.Color> getPixels() => _instance.getPixels();

  @override
  Uint32List getPixels32() => _instance.getPixels32();

  @override
  void setPixel(int x, int y, ui.Color color) =>
      _instance.setPixel(x, y, color);

  @override
  void setPixelData(Uint8List data) => _instance.setPixelData(data);

  @override
  void setPixels(List<ui.Color> pixels) => _instance.setPixels(pixels);

  @override
  void setPixels32(Uint32List pixels) => _instance.setPixels32(pixels);
}

/// A specialized mixin for enums representing audio assets.
///
/// This extends [AssetEnum] to provide audio-specific properties and
/// methods directly on the enum values, primarily the [audioSource].
mixin AudioAssetEnum on AssetEnum implements GameAudio {
  @override
  GameAsset createAsset() => GameAudio(source);

  GameAudio get _instance => asset as GameAudio;

  @override
  soloud.AudioSource get audioSource => _instance.audioSource;
}

/// Represents the current progress of an asynchronous asset loading operation.
///
/// This class provides metadata about how many assets have been loaded out of
/// the total batch, allowing for the implementation of loading bars and
/// transition screens.
///
/// ```dart
/// enum MyImages with AssetEnum, TextureAssetEnum {
///   hero;
///   @override
///   AssetSource get source => AssetSource.local('hero.png');
/// }
///
/// void main() async {
///   final stream = GameAsset.loadAll(MyImages.values);
///   stream.listen((progress) {
///     if (progress.progress >= 1.0) {
///       // Loading complete
///     }
///   });
/// }
/// ```
///
/// See also:
/// * [GameAsset.loadAll] for batch loading multiple assets.
class GameAssetProgress {
  /// The specific asset that was most recently loaded.
  ///
  /// This property provides access to the [GameAsset] instance that triggered
  /// this progress update, allowing for per-asset initialization if needed.
  final GameAsset loadingAsset;

  /// The total number of assets that have completed loading so far.
  ///
  /// This count includes the current [loadingAsset] and all previously
  /// completed assets in the same batch.
  final int assetLoaded;

  /// The total number of assets in the current loading batch.
  ///
  /// This represents the total size of the collection passed to [GameAsset.loadAll].
  final int assetCount;

  /// Creates a progress snapshot for a loading batch.
  ///
  /// * [loadingAsset]: The asset that just finished loading.
  /// * [assetLoaded]: The count of successfully loaded assets.
  /// * [assetCount]: The total expected asset count.
  GameAssetProgress(this.loadingAsset, this.assetLoaded, this.assetCount);

  /// The completion ratio as a value between 0.0 and 1.0.
  ///
  /// This is a convenience getter that divides [assetLoaded] by [assetCount]
  /// to determine the overall progress of the batch.
  double get progress => assetLoaded / assetCount;
}

/// The base class for all managed resources within the engine.
///
/// This class defines the lifecycle of an asset, including loading from a
/// [source], tracking its [isLoaded] state, and unloading it to free memory.
/// It serves as the foundation for specialized assets like [GameTexture]
/// and [GameAudio].
///
/// ```dart
/// class CustomAsset extends GameAsset {
///   @override
///   AssetSource get source => AssetSource.local('data.bin');
///   @override
///   Future<void> load() async {
///     // Implementation of loading logic
///   }
///   @override
///   void unload() {
///     // Implementation of unloading logic
///   }
///   @override
///   bool get isLoaded => true;
/// }
/// ```
///
/// See also:
/// * [AssetSource] for the various origin points of asset data.
abstract class GameAsset {
  /// The source from which this asset retrieves its raw data.
  ///
  /// This getter must be implemented by subclasses to provide the appropriate
  /// [AssetSource] (e.g., [LocalSource] or [NetworkSource]).
  AssetSource get source;

  /// Batch loads multiple assets and reports progress over time.
  ///
  /// This static method returns a stream of [GameAssetProgress] objects,
  /// yielding a new update every time an asset in the provided collection
  /// finishes its [load] operation.
  ///
  /// * [assets]: The collection of enum-based assets to load.
  static Stream<GameAssetProgress> loadAll<T extends AssetEnum>(
    Iterable<AssetEnum> assets,
  ) async* {
    int count = 0;
    for (var asset in assets) {
      await asset.load();
      count++;
      yield GameAssetProgress(asset, count, assets.length);
    }
  }

  /// Whether this asset's data is currently present in memory.
  ///
  /// This returns true if [load] has completed successfully and [unload]
  /// has not yet been called.
  bool get isLoaded;

  /// Asynchronously loads the asset data into memory.
  ///
  /// If the asset is already loaded, this method completes immediately.
  /// Otherwise, it fetches the bytes from the [source] and processes them
  /// into the appropriate internal format (e.g., a GPU texture or audio clip).
  Future<void> load();

  /// Removes the asset data from memory.
  ///
  /// This should be called when an asset is no longer needed to prevent
  /// memory leaks, especially for large textures or long audio samples.
  void unload();
}

/// A managed image resource that can be rendered or manipulated.
///
/// This class handles the loading of image data from an [AssetSource] and
/// its conversion into a [ui.Image] suitable for drawing. It also provides
/// a pixel-level buffer for read and write operations, allowing for dynamic
/// texture generation or modification at runtime.
///
/// Modified textures must call [apply] to synchronize the internal pixel
/// buffer with the underlying graphics object.
///
/// ```dart
/// final texture = GameTexture(AssetSource.local('player.png'));
/// await texture.load();
/// final pixel = texture.getPixel(10, 10);
/// ```
///
/// See also:
/// * [GameAsset] for the base asset lifecycle.
/// * [TextureAssetEnum] for enum-based texture registries.
class GameTexture extends GameAsset {
  @override
  final AssetSource source;

  /// Creates a new texture from the specified [source].
  ///
  /// * [source]: The origin of the texture data.
  GameTexture(this.source);

  ui.Image? _loadedImage;
  Uint32List? _buffer;
  bool _isDirty = false;

  /// The horizontal pixel count of the loaded texture.
  ///
  /// Returns 0 if the texture has not yet been loaded.
  int get width => _loadedImage?.width ?? 0;

  /// The vertical pixel count of the loaded texture.
  ///
  /// Returns 0 if the texture has not yet been loaded.
  int get height => _loadedImage?.height ?? 0;

  @override
  bool get isLoaded => _loadedImage != null;

  @override
  Future<void> load() async {
    if (isLoaded) return;
    final bytes = await source.loadBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frameInfo = await codec.getNextFrame();
      _loadedImage = frameInfo.image;
      final byteData = await _loadedImage!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      _buffer = Uint32List.fromList(byteData!.buffer.asUint32List());
    } finally {
      codec.dispose();
    }
  }

  @override
  void unload() {
    _loadedImage = null;
    _buffer = null;
    _isDirty = false;
  }

  /// Retrieves the underlying Flutter [ui.Image] for rendering.
  ///
  /// This getter will throw an assertion error if the texture has not
  /// been loaded. Ensure [isLoaded] is true before access.
  ui.Image get image {
    assert(_loadedImage != null, 'Texture not yet loaded');
    return _loadedImage!;
  }

  /// Synchronizes pixel buffer changes to the GPU.
  ///
  /// This method should be called after any pixel manipulation (via [setPixel],
  /// [setPixels], etc.) to update the [image] property with the latest
  /// buffer state. It is an asynchronous operation as it involves
  /// re-encoding the image data.
  Future<void> apply() async {
    if (!_isDirty || _buffer == null) return;
    final completer = ui.ImmutableBuffer.fromUint8List(
      _buffer!.buffer.asUint8List(),
    );
    final buffer = await completer;
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    _loadedImage = frame.image;
    _isDirty = false;
    codec.dispose();
    buffer.dispose();
  }

  /// Retrieves the color of a specific pixel using integer coordinates.
  ///
  /// * [x]: The x-coordinate (column) of the pixel.
  /// * [y]: The y-coordinate (row) of the pixel.
  ui.Color getPixel(int x, int y) {
    if (_buffer == null) return const ui.Color(0x00000000);
    final pixel = _buffer![y * width + x];
    // RGBA8888 in Uint32List (LE) is 0xAABBGGRR? No, usually it's 0xRRGGBBAA or similar depending on endianness.
    // Flutter's rawRgba is [R, G, B, A] bytes.
    // In a Uint32List on LE: byte 0 is R, 1 is G, 2 is B, 3 is A.
    // So value is 0xAABBGGRR.
    return ui.Color.fromARGB(
      (pixel >> 24) & 0xFF, // A
      pixel & 0xFF, // R
      (pixel >> 8) & 0xFF, // G
      (pixel >> 16) & 0xFF, // B
    );
  }

  /// Retrieves a color using bilinear interpolation at normalized coordinates.
  ///
  /// This is useful for sampling textures at non-integer positions or when
  /// performing smooth scaling and transformations.
  ///
  /// * [u]: The normalized horizontal position (0.0 to 1.0).
  /// * [v]: The normalized vertical position (0.0 to 1.0).
  ui.Color getPixelBilinear(double u, double v) {
    if (_buffer == null) return const ui.Color(0x00000000);
    final x = u * (width - 1);
    final y = v * (height - 1);
    final x1 = x.floor();
    final y1 = y.floor();
    final x2 = (x1 + 1).clamp(0, width - 1);
    final y2 = (y1 + 1).clamp(0, height - 1);

    final f11 = getPixel(x1, y1);
    final f21 = getPixel(x2, y1);
    final f12 = getPixel(x1, y2);
    final f22 = getPixel(x2, y2);

    final tx = x - x1;
    final ty = y - y1;

    final r1 = _lerpChannel(f11.r * 255, f21.r * 255, tx);
    final r2 = _lerpChannel(f12.r * 255, f22.r * 255, tx);
    final r = _lerpChannel(r1, r2, ty);

    final g1 = _lerpChannel(f11.g * 255, f21.g * 255, tx);
    final g2 = _lerpChannel(f12.g * 255, f22.g * 255, tx);
    final g = _lerpChannel(g1, g2, ty);

    final b1 = _lerpChannel(f11.b * 255, f21.b * 255, tx);
    final b2 = _lerpChannel(f12.b * 255, f22.b * 255, tx);
    final b = _lerpChannel(b1, b2, ty);

    final a1 = _lerpChannel(f11.a * 255, f21.a * 255, tx);
    final a2 = _lerpChannel(f12.a * 255, f22.a * 255, tx);
    final a = _lerpChannel(a1, a2, ty);

    return ui.Color.fromARGB(
      a.round().clamp(0, 255),
      r.round().clamp(0, 255),
      g.round().clamp(0, 255),
      b.round().clamp(0, 255),
    );
  }

  double _lerpChannel(double a, double b, double t) => a + (b - a) * t;

  /// Exports the entire texture as a raw RGBA8888 byte array.
  ///
  /// This provides direct access to the underlying memory of the texture,
  /// which is useful for custom shaders, low-level image processing, or
  /// saving the texture to a file.
  Uint8List getPixelData() => _buffer!.buffer.asUint8List();

  /// Converts the current texture buffer into a list of [ui.Color] objects.
  ///
  /// This is a relatively expensive operation as it iterates over every
  /// pixel in the texture. Use sparingly for large images.
  List<ui.Color> getPixels() {
    if (_buffer == null) return [];
    return List.generate(width * height, (i) {
      final pixel = _buffer![i];
      return ui.Color.fromARGB(
        (pixel >> 24) & 0xFF,
        pixel & 0xFF,
        (pixel >> 8) & 0xFF,
        (pixel >> 16) & 0xFF,
      );
    });
  }

  /// Returns a copy of the internal 32-bit pixel buffer.
  ///
  /// This is useful when you need a snapshot of the texture state that won't
  /// be affected by subsequent modifications to the original texture.
  Uint32List getPixels32() => Uint32List.fromList(_buffer!);

  /// Updates the color of a single pixel.
  ///
  /// Note that [apply] must be called to propagate this change to the
  /// rendered [image].
  ///
  /// * [x]: The horizontal coordinate.
  /// * [y]: The vertical coordinate.
  /// * [color]: The new color value.
  void setPixel(int x, int y, ui.Color color) {
    if (_buffer == null) return;
    final pixel =
        ((color.a * 255).round().clamp(0, 255) << 24) |
        ((color.b * 255).round().clamp(0, 255) << 16) |
        ((color.g * 255).round().clamp(0, 255) << 8) |
        (color.r * 255).round().clamp(0, 255);
    _buffer![y * width + x] = pixel;
    _isDirty = true;
  }

  /// Overwrites the internal buffer with new raw RGBA8888 data.
  ///
  /// * [data]: The new pixel data as a [Uint8List].
  void setPixelData(Uint8List data) {
    _buffer = Uint32List.fromList(data.buffer.asUint32List());
    _isDirty = true;
  }

  /// Overwrites the internal buffer with a list of colors.
  ///
  /// * [pixels]: The list of colors corresponding to each pixel in row-major order.
  void setPixels(List<ui.Color> pixels) {
    if (_buffer == null) return;
    for (var i = 0; i < pixels.length; i++) {
      final color = pixels[i];
      _buffer![i] =
          ((color.a * 255).round().clamp(0, 255) << 24) |
          ((color.b * 255).round().clamp(0, 255) << 16) |
          ((color.g * 255).round().clamp(0, 255) << 8) |
          (color.r * 255).round().clamp(0, 255);
    }
    _isDirty = true;
  }

  /// Overwrites the internal buffer with 32-bit integer color data.
  ///
  /// * [pixels]: The new buffer as a [Uint32List].
  void setPixels32(Uint32List pixels) {
    _buffer = Uint32List.fromList(pixels);
    _isDirty = true;
  }
}

/// A managed audio resource that can be played by the engine.
///
/// This class handles the loading of audio data from an [AssetSource] and
/// its registration with the underlying audio engine (SoLoud). It provides
/// access to a [soloud.AudioSource] which can then be played, looped, or
/// modified.
///
/// ```dart
/// final audio = GameAudio(AssetSource.local('music.mp3'));
/// await audio.load();
/// // Playing via the underlying engine
/// final handle = soloud.SoLoud.instance.play(audio.audioSource);
/// ```
///
/// See also:
/// * [GameAsset] for the base asset lifecycle.
/// * [AudioAssetEnum] for enum-based audio registries.
class GameAudio extends GameAsset {
  @override
  final AssetSource source;

  /// Creates a new audio asset from the specified [source].
  ///
  /// * [source]: The origin of the audio data.
  GameAudio(this.source);

  soloud.AudioSource? _loadedAudioSource;

  @override
  Future<void> load() async {
    if (isLoaded) return;
    final bytes = await source.loadBytes();
    _loadedAudioSource = await soloud.SoLoud.instance.loadMem(
      '$hashCode',
      bytes,
    );
  }

  @override
  bool get isLoaded => _loadedAudioSource != null;

  /// Retrieves the underlying SoLoud [soloud.AudioSource].
  ///
  /// This getter will throw an assertion error if the audio has not
  /// been loaded. Ensure [isLoaded] is true before access.
  soloud.AudioSource get audioSource {
    assert(_loadedAudioSource != null, 'Audio not yet loaded');
    return _loadedAudioSource!;
  }

  @override
  void unload() {
    soloud.SoLoud.instance.disposeSource(audioSource);
  }
}
