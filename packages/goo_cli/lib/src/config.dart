import 'dart:io';

import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

/// goo's own section of a project's `pubspec.yaml`.
///
/// ```yaml
/// goo:
///   assets:
///     source: assets_src/    # originals you edit and commit
///     output: assets/        # canonical files, generated
///     packed: assets/packed/ # release chunks, generated
///   texture:
///     format: webp
///     quality: 90
///   audio:
///     format: ogg
///     quality: 5
/// ```
///
/// Both `output` and `packed` have to appear in `flutter: assets:` - that list
/// is the only thing Flutter bundles from. A release build fills `packed` and
/// then empties `output` of everything it generated, so the two are listed
/// together and only one of them ever ships anything.
///
/// **In the pubspec, not a `goo.yaml`.** A project already has one file that
/// says what it is and what it ships; a second one beside it is a second place
/// to look and a second thing to keep in step. It also puts the asset
/// *source* directory next to the `flutter: assets:` list that names the
/// *output*, which is exactly where someone reading either will want the
/// other.
@immutable
class GooConfig {
  const GooConfig({
    required this.assetSource,
    required this.assetOutput,
    this.packOutput = 'assets/packed/',
    required this.texture,
    required this.audio,
  });

  /// Where the originals live - whatever format they happen to be in.
  ///
  /// Not scanned by `goo generate`: what a project *ships* is the output
  /// directory, and generating keys for source art would name files that never
  /// reach the bundle.
  final String assetSource;

  /// Where canonical assets are written, and what `flutter: assets:` must
  /// list.
  ///
  /// Generated: safe to gitignore, and rebuilt by `goo assets compact`.
  /// Development and release load byte-identical files because both load
  /// *this*, which is the whole reason compaction is not a release-only step -
  /// a format bug that only appears in release is the worst kind.
  final String assetOutput;

  /// Where packed chunks are written, under the project root.
  ///
  /// Separate from [assetOutput] deliberately: chunks have to be bundled by
  /// Flutter, so they must live somewhere `flutter: assets:` lists - but they
  /// are not *assets* in the sense the rest of the pipeline means. Written
  /// into the asset directory itself they get re-scanned on the next run, and
  /// a chunk containing a chunk is not a useful thing to build.
  ///
  /// A subdirectory of [assetOutput] by default, which is fine and is why the
  /// scan skips it by name rather than by extension. Flutter's directory
  /// entries bundle files and not subdirectories, so the two never overlap.
  final String packOutput;

  final TextureConfig texture;
  final AudioConfig audio;

  static const GooConfig defaults = GooConfig(
    assetSource: 'assets_src/',
    assetOutput: 'assets/',
    texture: TextureConfig(),
    audio: AudioConfig(),
  );

  /// Reads the `goo:` section of [projectDir]'s pubspec, falling back to
  /// [defaults] for anything absent.
  ///
  /// A project with no `goo:` section at all is not an error - the defaults
  /// are the conventional layout, and a new project should work before anyone
  /// has configured anything.
  factory GooConfig.read(Directory projectDir) {
    final file = File('${projectDir.path}/pubspec.yaml');
    if (!file.existsSync()) {
      throw ArgumentError(
        'No pubspec.yaml in ${projectDir.path} - goo reads its configuration '
        'from the `goo:` section of it.',
      );
    }
    final doc = loadYaml(file.readAsStringSync());
    final goo = doc is YamlMap ? doc['goo'] : null;
    if (goo is! YamlMap) return defaults;

    final assets = goo['assets'];
    final texture = goo['texture'];
    final audio = goo['audio'];

    return GooConfig(
      assetSource: _dir(assets, 'source', defaults.assetSource),
      assetOutput: _dir(assets, 'output', defaults.assetOutput),
      packOutput: _dir(assets, 'packed', defaults.packOutput),
      texture: TextureConfig(
        format: _enum(
          texture,
          'format',
          TextureFormat.values,
          TextureFormat.webp,
        ),
        quality: _int(texture, 'quality', 90),
      ),
      audio: AudioConfig(
        format: _enum(audio, 'format', AudioFormat.values, AudioFormat.ogg),
        quality: _int(audio, 'quality', 5),
      ),
    );
  }

  /// A directory setting, always ending in `/`.
  ///
  /// Normalised here rather than at each use: `assets` and `assets/` mean the
  /// same thing to a person writing the pubspec, and a missing slash otherwise
  /// turns into a path like `assetsfoo.png` three layers away.
  static String _dir(Object? map, String key, String fallback) {
    final value = map is YamlMap ? map[key] : null;
    if (value is! String || value.isEmpty) return fallback;
    return value.endsWith('/') ? value : '$value/';
  }

  static T _enum<T extends Enum>(
    Object? map,
    String key,
    List<T> choices,
    T fallback,
  ) {
    final value = map is YamlMap ? map[key] : null;
    if (value is! String) return fallback;
    for (final choice in choices) {
      if (choice.name == value) return choice;
    }
    throw ArgumentError(
      'pubspec.yaml: "$value" is not a valid $key - expected one of '
      '${choices.map((c) => c.name).join(', ')}.',
    );
  }

  static int _int(Object? map, String key, int fallback) {
    final value = map is YamlMap ? map[key] : null;
    return value is int ? value : fallback;
  }
}

/// The one format every texture is converted to.
///
/// One format, not "whatever the artist saved", because the runtime's job gets
/// smaller the fewer decoders it has to be right about - and because the
/// choice is a build decision, not something each file should carry.
enum TextureFormat {
  /// The default. Smallest at equal quality for both photographic and
  /// lossless art, decodes on every platform Flutter targets, and keeps
  /// alpha - which rules out plain JPEG for sprite work.
  webp('.webp'),

  /// Lossless, universally understood, and much larger than [webp] on
  /// photographic art. Worth choosing when you want the pack auditable, or
  /// when ffmpeg's WebP encoder is not available.
  png('.png');

  const TextureFormat(this.extension);

  final String extension;
}

/// The one format every audio file is converted to.
enum AudioFormat {
  /// The default: patent-free, well compressed, and decodable by every audio
  /// backend worth using.
  ogg('.ogg'),

  /// Uncompressed. Enormous, and only sensible for very short clips where
  /// decode latency matters more than size.
  wav('.wav');

  const AudioFormat(this.extension);

  final String extension;
}

@immutable
class TextureConfig {
  const TextureConfig({this.format = TextureFormat.webp, this.quality = 90});

  final TextureFormat format;

  /// 0-100. Ignored for a lossless format.
  final int quality;
}

@immutable
class AudioConfig {
  const AudioConfig({this.format = AudioFormat.ogg, this.quality = 5});

  final AudioFormat format;

  /// Vorbis quality, -1 to 10. Ignored for an uncompressed format.
  final int quality;
}
