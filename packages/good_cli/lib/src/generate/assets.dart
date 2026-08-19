import 'dart:io';

import 'package:good_cli/src/config.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

/// One asset the project ships, as codegen sees it.
@immutable
class DiscoveredAsset {
  const DiscoveredAsset({
    required this.identifier,
    required this.path,
    required this.kind,
  });

  /// The Dart identifier this becomes - `planePlayerBlue`.
  final String identifier;

  /// The **bundle path**, exactly as the pubspec declares it and exactly what
  /// `BundleSource` hands to `rootBundle` - `assets/plane_player_blue.png`.
  ///
  /// The full path including the extension, deliberately. The hand-written
  /// generated file this replaces used a bare `plane_player_blue`, which
  /// nothing could have loaded: in a loose development build `BundleSource`
  /// goes straight to `rootBundle`, and the bundle knows the pubspec's path or
  /// nothing at all. A packed build translates this same string through the
  /// manifest, which is why it stays the *logical* path and never a chunk
  /// offset.
  final String path;

  final AssetKind kind;

  @override
  String toString() => '$identifier -> $path (${kind.name})';
}

/// What a file's extension says it is, which decides which generated enum it
/// lands in and which `AssetLoader` will decode it.
enum AssetKind {
  texture(<String>['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp']),

  /// Keyed and packed exactly like a texture, into its own `Audios` enum.
  /// Nothing plays it yet - see `AudioClip` for why the pipeline runs ahead of
  /// the backend - but it ships, and a readiness check catches it missing.
  audio(<String>['.wav', '.mp3', '.ogg', '.flac']),

  other(<String>[]);

  const AssetKind(this.extensions);

  final List<String> extensions;

  static AssetKind of(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return AssetKind.other;
    final extension = path.substring(dot).toLowerCase();
    for (final kind in values) {
      if (kind.extensions.contains(extension)) return kind;
    }
    return AssetKind.other;
  }
}

/// The result of looking at a project: what it ships, and what codegen cannot
/// do anything with.
@immutable
class AssetScan {
  const AssetScan({
    required this.textures,
    required this.audio,
    required this.unsupported,
    required this.declaredEntries,
  });

  final List<DiscoveredAsset> textures;

  /// Audio the project ships. Keyed and packed like a texture; nothing plays
  /// it yet - see `AudioClip`.
  final List<DiscoveredAsset> audio;

  /// Files that ship but produce no generated code, with why. Reported rather
  /// than dropped: a texture the generator quietly ignored is a missing enum
  /// value someone will hunt for.
  final Map<String, String> unsupported;

  /// The `flutter: assets:` entries the pubspec declared, verbatim.
  final List<String> declaredEntries;

  bool get isEmpty => textures.isEmpty && audio.isEmpty;
}

/// Reads a project's shipped assets from its pubspec.
///
/// **The pubspec, not a directory walk**, and that is the whole point. Flutter
/// bundles what `flutter: assets:` lists and nothing else, so generating a key
/// for a file merely *present* on disk would produce code that compiles and
/// then fails at load with the file sitting right there - the worst possible
/// version of that error. Reading the declaration means the generated set and
/// the shipped set cannot disagree.
///
/// An entry ending in `/` is a directory: Flutter bundles the files directly
/// inside it, not recursively, and this matches that.
AssetScan scanAssets(Directory projectDir) {
  final pubspec = File('${projectDir.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw ArgumentError(
      'No pubspec.yaml in ${projectDir.path} - that is the file that says '
      'which assets ship, so there is nothing to generate from.',
    );
  }

  final doc = loadYaml(pubspec.readAsStringSync());
  final entries = <String>[];
  if (doc is YamlMap) {
    final flutter = doc['flutter'];
    if (flutter is YamlMap) {
      final assets = flutter['assets'];
      if (assets is YamlList) {
        for (final entry in assets) {
          if (entry is String) entries.add(entry);
        }
      }
    }
  }

  // The packed directory ships, but is not made of assets - it is made *from*
  // them. Left in, every chunk would be scanned as an asset on the next run,
  // reported as an unrecognised extension, and then packed into a chunk of its
  // own, which is a build that grows every time it is run.
  final config = GoodConfig.read(projectDir);
  final packed = config.packOutput;

  final files = <String>[];
  for (final entry in entries) {
    if (entry == packed) continue;
    if (entry.endsWith('/')) {
      final dir = Directory('${projectDir.path}/$entry');
      if (!dir.existsSync()) continue;
      for (final child in dir.listSync()) {
        if (child is! File) continue;
        final name = child.uri.pathSegments.last;
        // Sidecars the pipeline writes beside the assets - the compaction
        // journal is the one that exists today. Named by convention rather
        // than listed, since anything good drops next to an asset is its own
        // bookkeeping and never something to key.
        if (name.startsWith('.')) continue;
        files.add('$entry$name');
      }
    } else if (!entry.startsWith(packed)) {
      files.add(entry);
    }
  }
  files.sort(); // Stable output: codegen that reorders itself churns diffs.

  final textures = <DiscoveredAsset>[];
  final audio = <DiscoveredAsset>[];
  final unsupported = <String, String>{};
  // Collisions are checked **per enum**, not across all of them: `Textures`
  // and `Audios` are separate types, so a `click.png` and a `click.ogg` are
  // `Textures.click` and `Audios.click` and do not collide at all.
  final byIdentifier = <AssetKind, Map<String, String>>{
    AssetKind.texture: <String, String>{},
    AssetKind.audio: <String, String>{},
  };

  for (final path in files) {
    final kind = AssetKind.of(path);
    final seen = byIdentifier[kind];
    if (seen == null) {
      unsupported[path] = 'unrecognised extension';
      continue;
    }
    final identifier = identifierFor(path);
    final clash = seen[identifier];
    if (clash != null) {
      // Loudly, at generate time. Two assets collapsing onto one enum value
      // would silently make one of them unreachable.
      throw ArgumentError(
        '"$path" and "$clash" both generate the identifier "$identifier" in '
        'the ${kind.name} enum. Rename one - the identifier comes from the '
        'path with separators removed, so "ui/button.png" and "ui_button.png" '
        'collide.',
      );
    }
    seen[identifier] = path;
    final asset = DiscoveredAsset(
      identifier: identifier,
      path: path,
      kind: kind,
    );
    (kind == AssetKind.texture ? textures : audio).add(asset);
  }

  return AssetScan(
    textures: textures,
    audio: audio,
    unsupported: unsupported,
    declaredEntries: entries,
  );
}

/// Dart words that cannot be an identifier on their own. A `new.png` is a
/// perfectly ordinary filename and must not generate uncompilable code.
const Set<String> _reserved = <String>{
  'assert',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'else',
  'enum',
  'extends',
  'false',
  'final',
  'finally',
  'for',
  'if',
  'in',
  'is',
  'new',
  'null',
  'rethrow',
  'return',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'while',
  'with',
  'index',
  'values',
  'name',
  'hashCode',
  'runtimeType',
  'toString',
  'noSuchMethod',
};

/// The enum value name for a bundle path.
///
/// `assets/plane_player_blue.png` -> `planePlayerBlue`. The leading asset
/// directory is dropped and the rest of the path contributes, so
/// `assets/ui/button.png` is `uiButton` and cannot collide with a `button.png`
/// somewhere else - collisions that remain are reported by [scanAssets].
String identifierFor(String path) {
  var working = path;
  final dot = working.lastIndexOf('.');
  if (dot > working.lastIndexOf('/')) working = working.substring(0, dot);

  final segments = working
      .split(RegExp(r'[/\\]'))
      .where((s) => s.isNotEmpty)
      .toList();
  // Drop the conventional root, but never the whole path: `assets/x.png` is
  // `x`, and a file declared as bare `x.png` is still `x`.
  if (segments.length > 1 && segments.first == 'assets') segments.removeAt(0);

  final words = <String>[];
  for (final segment in segments) {
    words.addAll(segment.split(RegExp(r'[_\-. ]+')).where((w) => w.isNotEmpty));
  }
  if (words.isEmpty) return r'$asset';

  final buffer = StringBuffer(words.first.toLowerCase());
  for (var i = 1; i < words.length; i++) {
    final word = words[i];
    buffer
      ..write(word.substring(0, 1).toUpperCase())
      ..write(word.substring(1).toLowerCase());
  }
  var identifier = buffer.toString();

  // A leading digit is not a legal identifier, and a reserved word is not a
  // legal *enum value*. Both are ordinary filenames.
  if (RegExp(r'^[0-9]').hasMatch(identifier)) {
    identifier = '\$$identifier';
  }
  if (_reserved.contains(identifier)) identifier = '$identifier\$';
  return identifier;
}

/// Which good package the project depends on, and therefore what the generated
/// files import.
///
/// `goo2d` and `goo3d` both re-export the `good` kernel, so a project must
/// import the one it depends on and nothing else: importing `package:good`
/// directly in generated code names a package the pubspec does not depend on,
/// which pub warns about and a stricter analysis setup rejects outright. A
/// `goo3d` project left off this list is exactly that warning, on every
/// generated file, from the first run.
///
/// Falls back to `good` when none is declared. A project with no engine
/// dependency at all has bigger problems than the import line, and guessing
/// the kernel is the answer that is right for all of them.
String enginePackageOf(Directory projectDir) {
  final file = File('${projectDir.path}/pubspec.yaml');
  if (!file.existsSync()) return 'good';
  final doc = loadYaml(file.readAsStringSync());
  final deps = doc is YamlMap ? doc['dependencies'] : null;
  if (deps is! YamlMap) return 'good';
  // Most specific first: a project can depend on a renderer and the kernel
  // both, and the renderer is then the one whose export surface covers
  // everything the generated code names.
  for (final candidate in const <String>['goo2d', 'goo3d', 'good']) {
    if (deps.containsKey(candidate)) return candidate;
  }
  return 'good';
}

/// The `flutter: assets:` entries a project declares, verbatim.
///
/// Exposed on its own because two very different things need it: the scan
/// above turns them into generated code, and `good assets compact` checks that
/// the directories it just wrote into are actually among them.
List<String> declaredAssetEntries(Directory projectDir) {
  final pubspec = File('${projectDir.path}/pubspec.yaml');
  if (!pubspec.existsSync()) return const <String>[];
  final doc = loadYaml(pubspec.readAsStringSync());
  if (doc is! YamlMap) return const <String>[];
  final flutter = doc['flutter'];
  if (flutter is! YamlMap) return const <String>[];
  final assets = flutter['assets'];
  if (assets is! YamlList) return const <String>[];
  return <String>[
    for (final e in assets)
      if (e is String) e,
  ];
}
