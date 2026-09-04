import 'dart:io';

import 'package:good_cli/src/assets/entry.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

/// good's own section of a project's `pubspec.yaml`.
///
/// ```yaml
/// good:
///   bundle: my_game_bundle      # the generated package, recorded not derived
///   asset-source: assets_src/   # originals you edit and commit
///   asset-output: assets/       # canonical files, generated
///   pack-output: assets/packed/ # release chunks, generated
///   assets:                     # what good packs, in Flutter's own shape
///     - assets/
///   flavors:                    # this project's flavors, and what each ships
///     development: raw
///     production: bundled
///   texture:
///     format: webp
///     quality: 90
///   audio:
///     format: ogg
///     quality: 5
/// ```
///
/// [assets] is a list and the three directories are not, which is why they are
/// keys of `good:` rather than of `good: assets:`. It says which files good
/// owns. `flutter: assets:` stays the project's own and says what Flutter
/// bundles by path, and the two are read separately: a file named in one is
/// not thereby named in the other.
///
/// **In the pubspec, not a `good.yaml`.** A project already has one file that
/// says what it is and what it ships; a second one beside it is a second place
/// to look and a second thing to keep in step. It also puts good's asset list
/// next to Flutter's, which is exactly where someone reading either will want
/// the other.
@immutable
class GoodConfig {
  const GoodConfig({
    this.bundle,
    required this.assetSource,
    required this.assetOutput,
    this.packOutput = 'assets/packed/',
    this.assets = const <AssetEntry>[],
    this.flavors = const <String, AssetPipeline>{},
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

  /// The files good packs, in the shape `flutter: assets:` takes.
  ///
  /// A separate list from Flutter's, and that is the point: a file here is
  /// good's to normalize, chunk, compress and encrypt, and a file in
  /// `flutter: assets:` is bundled and read by path and is not good's concern
  /// at all. Read them from one list and there is no way to say which a file
  /// is, which is why a packed asset used to be handed to Flutter's bundler as
  /// well and ship in the clear beside the chunk holding the same bytes.
  ///
  /// The entries take Flutter's own four keys, so one moves between the lists
  /// unchanged - see [AssetEntry].
  final List<AssetEntry> assets;

  /// This project's build flavors, and what each one ships - as written.
  ///
  /// ```yaml
  /// good:
  ///   flavors:
  ///     development: raw
  ///     staging: bundled
  ///     production: bundled
  /// ```
  ///
  /// **good names no flavor and reserves none.** A build takes one
  /// `--flavor`, and that slot is the project's: a game that already ships
  /// `paid` and `free` keeps shipping them and says which of the two goes
  /// through the pipeline. Inventing a `dev`/`prod` axis of good's own would
  /// take the only slot there is.
  ///
  /// Empty for a project that declares none, which is not the same as having
  /// none - see [resolvedFlavors].
  final Map<String, AssetPipeline> flavors;

  /// [flavors], with the degenerate case filled in.
  ///
  /// A project that declares no flavors has nothing to map, and an entry with
  /// no `flavors:` is shipped in every build - so the raw set and the bundled
  /// set would be one set, both shipped, which is the double-ship this split
  /// exists to end. `dev` and `prod` are synthesized there: the same rule
  /// applied to the case where the project named nothing, not a second
  /// mechanism.
  Map<String, AssetPipeline> get resolvedFlavors => flavors.isEmpty
      ? const <String, AssetPipeline>{
          'dev': AssetPipeline.raw,
          'prod': AssetPipeline.bundled,
        }
      : flavors;

  /// The flavors that ship the originals, sorted.
  List<String> get rawFlavors => _flavorsFor(AssetPipeline.raw);

  /// The flavors that ship the chunks, sorted.
  List<String> get bundledFlavors => _flavorsFor(AssetPipeline.bundled);

  List<String> _flavorsFor(AssetPipeline pipeline) => <String>[
    for (final entry in resolvedFlavors.entries)
      if (entry.value == pipeline) entry.key,
  ]..sort();

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

    final texture = good['texture'];
    final audio = good['audio'];

    return GoodConfig(
      bundle: _packageName(good, 'bundle'),
      assetSource: _dir(good, 'asset-source', defaults.assetSource),
      assetOutput: _dir(good, 'asset-output', defaults.assetOutput),
      packOutput: _dir(good, 'pack-output', defaults.packOutput),
      assets: _checkedAssets(_assets(good['assets']), _flavors(good)),
      flavors: _flavors(good),
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

  /// The `good: flavors:` map: each of the project's flavors, and whether it
  /// ships the originals or the chunks.
  ///
  /// A value outside [AssetPipeline] is refused rather than ignored. There
  /// are two pipelines and a flavor goes through one of them; a third word
  /// here means someone expected a behaviour that does not exist, and the
  /// quiet reading of it is a flavor that ships nothing at all.
  static Map<String, AssetPipeline> _flavors(YamlMap good) {
    final yaml = good['flavors'];
    if (yaml == null) return const <String, AssetPipeline>{};
    if (yaml is! YamlMap) {
      throw ArgumentError(
        'pubspec.yaml: `good: flavors:` is a ${yaml.runtimeType}, not a map. '
        'Each line under it names one flavor of this project, and says '
        '${AssetPipeline.values.map((p) => p.name).join(' or ')}.',
      );
    }
    final flavors = <String, AssetPipeline>{};
    for (final key in yaml.keys) {
      // Restricted here rather than passed through, because the name is
      // written into a pubspec asset entry and read back by Flutter's own
      // parser. A name needing quoting would come back out of a generated
      // list as something else.
      if (key is! String || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key)) {
        throw ArgumentError(
          'pubspec.yaml: `good: flavors:` names "$key", which is not a flavor '
          'name. A flavor name is letters, digits, underscores and dashes - '
          'it is what `--flavor` takes and what good writes into the '
          'generated asset entries.',
        );
      }
      final value = yaml[key];
      final pipeline = <String, AssetPipeline>{
        for (final p in AssetPipeline.values) p.name: p,
      }[value];
      if (pipeline == null) {
        throw ArgumentError(
          'pubspec.yaml: `good: flavors: $key: $value` is not a pipeline. A '
          'flavor ships ${AssetPipeline.values.map((p) => p.name).join(' or ')}'
          ' - the originals, or the normalized, chunked, compressed and '
          'encrypted bundle.',
        );
      }
      flavors[key] = pipeline;
    }
    return flavors;
  }

  /// [assets], refused if an entry names a flavor the project does not map.
  ///
  /// Not a warning and not a silent pass. `good generate` gates the raw copy
  /// of an entry on its own flavors intersected with the raw ones, so a name
  /// outside the map intersects to nothing - the originals ship nowhere - and
  /// the chunk still ships, so the asset exists in one build and not the
  /// other for a reason nothing states. A typo'd flavor is exactly that.
  static List<AssetEntry> _checkedAssets(
    List<AssetEntry> assets,
    Map<String, AssetPipeline> flavors,
  ) {
    for (final entry in assets) {
      final unknown =
          entry.flavors.where((f) => !flavors.containsKey(f)).toList()..sort();
      if (unknown.isEmpty) continue;
      throw ArgumentError(
        'pubspec.yaml: `good: assets:` entry "${entry.path}" ships in '
        '${unknown.join(', ')}, which `good: flavors:` does not map. '
        '${flavors.isEmpty ? 'This project declares no flavors at all - add a '
                  '`good: flavors:` map naming them and whether each ships raw '
                  'or bundled.' : 'It maps ${flavors.keys.join(', ')}.'}',
      );
    }
    return assets;
  }

  /// The `good: assets:` list.
  ///
  /// A missing key is an empty list, not an error: a project can legitimately
  /// have no assets of good's yet, and one that has none should still build. A
  /// key that is there and is not a list *is* an error - it is a project that
  /// meant to declare assets and wrote something this cannot read, and the
  /// silent reading of that is a build that ships none of them.
  static List<AssetEntry> _assets(Object? yaml) {
    if (yaml == null) return const <AssetEntry>[];
    if (yaml is! YamlList) {
      throw ArgumentError(
        'pubspec.yaml: `good: assets:` is a ${yaml.runtimeType}, not a list of '
        'assets. Each line under it is a path, or a map with a `path:` in it.',
      );
    }
    return <AssetEntry>[
      for (final entry in yaml)
        AssetEntry.parse(entry, context: 'good: assets'),
    ];
  }
}

/// What a flavor ships: the originals, or what the pipeline made of them.
///
/// The two are the whole of the development/release split, and they are
/// flavors rather than a post-build deletion because Flutter's own bundler
/// already excludes a flavoured entry from a build that did not ask for that
/// flavor. Nothing has to strip anything afterwards, and there is no moment
/// where both copies are in one bundle.
enum AssetPipeline {
  /// The files as they are, loaded loose through the asset bundle. What a
  /// development run wants: edit a file, hot restart, see it.
  raw,

  /// normalize -> chunk -> compress -> encrypt. What ships.
  bundled,
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
