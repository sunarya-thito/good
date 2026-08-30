import 'dart:io';

import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

/// good's own section of a project's `pubspec.yaml`.
///
/// ```yaml
/// good:
///   bundle: my_game_bundle  # the generated package, recorded not derived
///   assets:
///     source: assets_src/    # originals you edit and commit
///     output: assets/        # canonical files, generated
///     packed: assets/packed/ # release chunks, generated
///     strip-originals: false # may a build delete art it cannot rebuild
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
/// leaves `output` as it found it, so both directories ship and a packed asset
/// is bundled twice. `strip-originals: true` empties `output` of everything the
/// build packed - see [stripOriginals] for what that costs.
///
/// **In the pubspec, not a `good.yaml`.** A project already has one file that
/// says what it is and what it ships; a second one beside it is a second place
/// to look and a second thing to keep in step. It also puts the asset
/// *source* directory next to the `flutter: assets:` list that names the
/// *output*, which is exactly where someone reading either will want the
/// other.
@immutable
class GoodConfig {
  const GoodConfig({
    this.bundle,
    required this.assetSource,
    required this.assetOutput,
    this.packOutput = 'assets/packed/',
    this.stripOriginals = false,
    required this.texture,
    required this.audio,
  });

  /// The generated sibling package that holds everything good writes, or null
  /// when a project has never had one generated.
  ///
  /// **Recorded, never computed.** A name derived from the project's would
  /// change the moment the project was renamed, leaving the old bundle on disk
  /// and still named in `dependencies:` while a second one was generated
  /// beside it - two packages declaring the same generated code, one of them
  /// dead, and nothing in the build saying which answered. Recorded, a rename
  /// is a non-event.
  ///
  /// Derived from the project name once, at `good create`, and written here.
  /// See `defaultBundleName`.
  final String? bundle;

  /// Where the originals live - whatever format they happen to be in.
  ///
  /// Not scanned by `good generate`: what a project *ships* is the output
  /// directory, and generating keys for source art would name files that never
  /// reach the bundle.
  final String assetSource;

  /// Where canonical assets are written, and what `flutter: assets:` must
  /// list.
  ///
  /// Generated: safe to gitignore, and rebuilt by `good assets compact`.
  /// Development and release load byte-identical files because both load
  /// *this*, which is the whole reason compaction is not a release-only step -
  /// a format bug that only appears in release is the worst kind.
  final String assetOutput;

  /// Where packed chunks are written, under the project root.
  ///
  /// Kept apart from [assetOutput]: chunks have to be bundled by
  /// Flutter, so they must live somewhere `flutter: assets:` lists - but they
  /// are not *assets* in the sense the rest of the pipeline means. Written
  /// into the asset directory itself they get re-scanned on the next run, and
  /// a chunk containing a chunk is not a useful thing to build.
  ///
  /// A subdirectory of [assetOutput] by default, which is fine because the
  /// scan skips it by name and not by extension. Flutter's directory
  /// entries bundle files and not subdirectories, so the two never overlap.
  final String packOutput;

  /// Whether a build deletes the loose copy of an asset it packed.
  ///
  /// **Off by default, and nothing else turns it on.** A build that packs
  /// leaves [assetOutput] as it found it, so every packed asset is bundled
  /// twice: once legible in [assetOutput], once inside an encrypted chunk. The
  /// build says nothing about it. `Image.asset` and everything else that reads
  /// the Flutter bundle by path go on resolving those files, which is what
  /// leaving the loose copies in place buys.
  ///
  /// Turned on, the build deletes the loose copy of everything it packed. Those
  /// paths stop resolving through the Flutter bundle, and only good's own asset
  /// API reaches the bytes. A file you put in [assetOutput] by hand is packed
  /// like any other, so it goes too - and `good assets compact` has no source
  /// to build that one from again. The build names each of those as it deletes
  /// it.
  ///
  /// Turn it on when [assetSource] holds everything and [assetOutput] is
  /// genuinely disposable.
  final bool stripOriginals;

  final TextureConfig texture;
  final AudioConfig audio;

  static const GoodConfig defaults = GoodConfig(
    assetSource: 'assets_src/',
    assetOutput: 'assets/',
    texture: TextureConfig(),
    audio: AudioConfig(),
  );

  /// Reads the `good:` section of [projectDir]'s pubspec, falling back to
  /// [defaults] for anything absent.
  ///
  /// A project with no `good:` section at all is not an error - the defaults
  /// are the conventional layout, and a new project should work before anyone
  /// has configured anything.
  factory GoodConfig.read(Directory projectDir) {
    final file = File('${projectDir.path}/pubspec.yaml');
    if (!file.existsSync()) {
      throw ArgumentError(
        'No pubspec.yaml in ${projectDir.path} - good reads its configuration '
        'from the `good:` section of it.',
      );
    }
    final doc = loadYaml(file.readAsStringSync());
    final good = doc is YamlMap ? doc['good'] : null;
    if (good is! YamlMap) return defaults;

    final assets = good['assets'];
    final texture = good['texture'];
    final audio = good['audio'];

    return GoodConfig(
      bundle: _packageName(good, 'bundle'),
      assetSource: _dir(assets, 'source', defaults.assetSource),
      assetOutput: _dir(assets, 'output', defaults.assetOutput),
      packOutput: _dir(assets, 'packed', defaults.packOutput),
      stripOriginals: _bool(assets, 'strip-originals', defaults.stripOriginals),
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
  /// Normalised here, not at each use: `assets` and `assets/` mean the
  /// same thing to a person writing the pubspec, and a missing slash otherwise
  /// turns into a path like `assetsfoo.png` three layers away.
  static String _dir(Object? map, String key, String fallback) {
    final value = map is YamlMap ? map[key] : null;
    if (value is! String || value.isEmpty) return fallback;
    return value.endsWith('/') ? value : '$value/';
  }

  /// A recorded package name, refused rather than passed on when it is not
  /// one.
  ///
  /// Everything downstream builds a directory, a pubspec `name:` and a
  /// `package:` import out of this. A value that is not a legal package name
  /// produces a package pub cannot read, at a distance from the line that
  /// caused it.
  static String? _packageName(Object? map, String key) {
    final value = map is YamlMap ? map[key] : null;
    if (value == null) return null;
    if (value is! String || !RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(value)) {
      throw ArgumentError(
        'pubspec.yaml: `good: $key: $value` is not a package name. It has to '
        'be lower_snake_case - it names a directory, a pubspec and every '
        '`package:` import of the code generated into it.',
      );
    }
    return value;
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

  static bool _bool(Object? map, String key, bool fallback) {
    final value = map is YamlMap ? map[key] : null;
    return value is bool ? value : fallback;
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

  /// 0-100, where 100 encodes losslessly. Ignored for a lossless format.
  final int quality;
}

@immutable
class AudioConfig {
  const AudioConfig({this.format = AudioFormat.ogg, this.quality = 5});

  final AudioFormat format;

  /// Vorbis quality, -1 to 10. Ignored for an uncompressed format.
  final int quality;
}
