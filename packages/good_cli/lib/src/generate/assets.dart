import 'dart:io';

import 'package:good_cli/src/config.dart';
import 'package:good_cli/src/generate/bundle.dart';
import 'package:good_cli/src/generate/engine_dependency.dart';
import 'package:good_cli/src/generate/image_size.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

/// One asset the project ships, as codegen sees it.
@immutable
class DiscoveredAsset {
  const DiscoveredAsset({
    required this.identifier,
    required this.path,
    required this.kind,
    this.size,
  });

  /// The Dart identifier this becomes - `planePlayerBlue`.
  final String identifier;

  /// The **bundle path**, exactly as the pubspec declares it and exactly what
  /// `BundleSource` hands to `rootBundle` - `assets/plane_player_blue.png`.
  ///
  /// The full path, extension included. A bare `plane_player_blue` loads
  /// nothing: in a loose development build `BundleSource` goes straight to
  /// `rootBundle`, and the bundle knows the pubspec's path or nothing at all.
  /// A packed build translates this same string through the manifest, so it
  /// stays the *logical* path and never a chunk offset.
  final String path;

  /// Which pipeline this asset goes through - texture, audio, or raw bytes.
  final AssetKind kind;

  /// The image's pixel dimensions, read from its header (#111).
  ///
  /// `null` for anything that is not an image, and for an image whose header
  /// [readImageSize] does not recognise - a format outside the six
  /// [AssetKind.texture] accepts, or a file truncated before its size field.
  /// A caller emitting a number for every texture has to pick something for
  /// those; see `emitTextures`.
  final ImageSize? size;

  @override
  String toString() => '$identifier -> $path (${kind.name})';
}

/// Identifiers the generated `Textures` enum spends on its own members.
///
/// Enum values and instance fields share one namespace, so these are the
/// basenames a project cannot give a texture. The set is fixed and does not
/// grow with what a project ships: `assets/width.png` and `assets/height.png`
/// are the only two files this rejects, whatever directory they sit in.
const Set<String> reservedTextureMembers = <String>{'width', 'height'};

/// What a file's extension says it is, which decides which generated enum it
/// lands in and which `AssetLoader` will decode it.
///
/// # Every file is a kind, and [blob] is what makes that true
///
/// [blob] used to mean "no rule for this", and a file that landed there was
/// reported and dropped: no enum value, no chunk, no encryption. So a level
/// layout, a dialogue file or a save blob shipped loose and legible while the
/// art beside it was sealed (#357). It now means raw bytes - a real kind with
/// a real payload type - and it is the fallback, so there is no longer any
/// such thing as a file the pipeline has no rule for.
///
/// # Why five kinds and not one
///
/// A generated enum mixes in `LocalEnumAssetKey<T>`, and `Asset.of<T>` takes
/// an `AssetKey<T>`. The payload type is the enum's type argument, so one
/// enum has one payload type and one loader. Three payload types is three
/// enums; there is no spelling of `Jsons`, `Texts` and `Blobs` as one.
///
/// # Why the split is by extension
///
/// Nothing else says what a file is. There is no per-file declaration in
/// `good: assets:` - an entry is a path, and that is the shape it has to keep
/// so an entry moves between the two lists unchanged (`AssetEntry`). So the
/// extension decides, exactly as it already did for [texture] and [audio].
///
/// [text] is deliberately short. `TextLoader` decodes strictly, so a file in
/// it that is not UTF-8 throws at load; a file left out of it is a [blob] and
/// the project decodes it itself, which is a worse API and never a failure.
/// Adding an extension here later moves files from `Blobs` to `Texts` and
/// breaks the code naming them, so the list errs towards what is UTF-8 by
/// definition rather than towards what usually is.
enum AssetKind {
  texture(
    <String>['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'],
    'Textures',
  ),

  /// Keyed and packed exactly like a texture, into its own `Audios` enum.
  /// Nothing plays it yet - see `AudioClip` for why the pipeline runs ahead of
  /// the backend - but it ships, and a readiness check catches it missing.
  audio(<String>['.wav', '.mp3', '.ogg', '.flac'], 'Audios'),

  /// Decoded by `JsonLoader` into a `JsonValue`, whose top level is whatever
  /// the document's is.
  json(<String>['.json'], 'Jsons'),

  /// Read by `TextLoader` as one UTF-8 `String`.
  text(
    <String>[
      '.txt',
      '.md',
      '.csv',
      '.tsv',
      '.xml',
      '.yaml',
      '.yml',
      '.ini',
      '.cfg',
      '.glsl',
      '.frag',
      '.vert',
    ],
    'Texts',
  ),

  /// Everything else, handed over as bytes by `BytesLoader`.
  ///
  /// Named for the file and not for the payload, the way [texture] and [audio]
  /// are: `Blobs.autosave` is a file a project ships, and what the engine
  /// knows about it is nothing. It is also the fallback, so a file with an
  /// extension nothing recognises - or with no extension at all - is this.
  blob(<String>[], 'Blobs');

  const AssetKind(this.extensions, this.enumName);

  final List<String> extensions;

  /// The generated enum a file of this kind becomes a value of.
  ///
  /// Held here so the scene scan can recognise `Jsons.balance` in a source
  /// file without a second list of the same five names - see `scanScenes`.
  final String enumName;

  static AssetKind of(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return AssetKind.blob;
    final extension = path.substring(dot).toLowerCase();
    for (final kind in values) {
      if (kind.extensions.contains(extension)) return kind;
    }
    return AssetKind.blob;
  }
}

/// Every name a generated asset enum has, for a pass that has to spot one
/// written in somebody's source.
final Set<String> assetEnumNames = <String>{
  for (final kind in AssetKind.values) kind.enumName,
};

/// The result of looking at a project: what it ships, by kind.
///
/// Keyed by [AssetKind] rather than held in one field per kind, so adding a
/// kind is one entry in that enum and not a field here, a getter there and a
/// list somewhere else that quietly stayed at two.
@immutable
class AssetScan {
  const AssetScan({required this.byKind, required this.declaredEntries});

  /// Every asset the project ships, under the kind that decides which enum it
  /// becomes a value of and which loader decodes it.
  ///
  /// A kind with nothing in it is absent rather than empty; read it through
  /// [of], which answers an empty list either way.
  final Map<AssetKind, List<DiscoveredAsset>> byKind;

  /// The paths `good: assets:` declared, verbatim.
  final List<String> declaredEntries;

  List<DiscoveredAsset> of(AssetKind kind) =>
      byKind[kind] ?? const <DiscoveredAsset>[];

  List<DiscoveredAsset> get textures => of(AssetKind.texture);

  /// Audio the project ships. Keyed and packed like a texture; nothing plays
  /// it yet - see `AudioClip`.
  List<DiscoveredAsset> get audio => of(AssetKind.audio);

  List<DiscoveredAsset> get json => of(AssetKind.json);

  List<DiscoveredAsset> get text => of(AssetKind.text);

  List<DiscoveredAsset> get blobs => of(AssetKind.blob);

  /// Every asset, in kind order. What packing chunks, and what the readiness
  /// check walks.
  List<DiscoveredAsset> get all => <DiscoveredAsset>[
    for (final kind in AssetKind.values) ...of(kind),
  ];

  bool get isEmpty => all.isEmpty;
}

/// Reads the assets good owns from a project's pubspec.
///
/// **`good: assets:`, not `flutter: assets:`**, and the two lists are the
/// whole distinction. Flutter's is bundled and read by path; good's goes
/// through the pipeline. Read from one list there was no way to say which a
/// file was, so every packed asset was handed to Flutter's bundler too and
/// shipped in the clear beside the chunk holding the same bytes (#270).
///
/// **The pubspec, not a directory walk.** Generating a key for a file merely
/// *present* on disk would produce code that compiles and then fails at load
/// with the file sitting right there - the worst possible version of that
/// error. Reading the declaration means the generated set and the declared set
/// cannot disagree.
///
/// An entry ending in `/` is a directory: the files directly inside it, not
/// recursively, which is the rule Flutter's own entries follow.
AssetScan scanAssets(Directory projectDir) {
  final pubspec = File('${projectDir.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw ArgumentError(
      'No pubspec.yaml in ${projectDir.path} - that is the file that says '
      'which assets ship, so there is nothing to generate from.',
    );
  }

  final config = GoodConfig.read(projectDir);
  final entries = <String>[for (final entry in config.assets) entry.path];

  // The packed directory ships, but is not made of assets - it is made *from*
  // them. Left in, every chunk would be scanned as an asset on the next run,
  // reported as an unrecognised extension, and then packed into a chunk of its
  // own, which is a build that grows every time it is run.
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
        // Dotfiles are not assets. good writes none of its own here any more
        // - the compaction journal moved to .dart_tool/good/ - but a project
        // that last compacted under an older version still has one until its
        // next run, and .gitkeep is ordinary.
        if (name.startsWith('.')) continue;
        files.add('$entry$name');
      }
    } else if (!entry.startsWith(packed)) {
      files.add(entry);
    }
  }
  files.sort(); // Stable output: codegen that reorders itself churns diffs.

  final byKind = <AssetKind, List<DiscoveredAsset>>{};
  // Collisions are checked **per enum**, not across all of them: `Textures`
  // and `Audios` are separate types, so a `click.png` and a `click.ogg` are
  // `Textures.click` and `Audios.click` and do not collide at all.
  final byIdentifier = <AssetKind, Map<String, String>>{
    for (final kind in AssetKind.values) kind: <String, String>{},
  };

  for (final path in files) {
    final kind = AssetKind.of(path);
    final seen = byIdentifier[kind]!;
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
    if (kind == AssetKind.texture &&
        reservedTextureMembers.contains(identifier)) {
      // The generated enum carries `width` and `height` as instance fields, so
      // a texture whose identifier is one of those names is a duplicate
      // definition in a generated file. Refused here, where the message can
      // name the file that caused it - `duplicate_definition` points at two
      // lines of generated code and mentions no asset at all.
      throw ArgumentError(
        '"$path" generates the identifier "$identifier", which the Textures '
        'enum already uses for the pixel size every texture carries. Rename '
        'it - the identifier comes from the path with separators removed, so '
        'a file named "$identifier" anywhere under assets/ lands on it.',
      );
    }
    seen[identifier] = path;
    byKind.putIfAbsent(kind, () => <DiscoveredAsset>[]).add(
      DiscoveredAsset(
        identifier: identifier,
        path: path,
        kind: kind,
        size: kind == AssetKind.texture
            ? readImageSize(File('${projectDir.path}/$path'))
            : null,
      ),
    );
  }

  return AssetScan(byKind: byKind, declaredEntries: entries);
}

/// Assets on disk that `good: assets:` does not declare, keyed by the pubspec
/// line that would declare them.
///
/// Directory entries are **not recursive**, here as in Flutter's own list:
/// `- assets/` takes the files directly inside `assets/` and nothing deeper.
/// So compaction writing `assets/ui/button.webp` produces a file that reaches
/// no chunk, appears in no generated enum, and sits on disk the whole time
/// looking correct. Every new subdirectory needs its own line, and nothing
/// about the layout says so.
///
/// Keyed by that line - `assets/ui/` - because the line is the entire fix, and
/// an error that makes the reader work out its shape is most of the problem
/// again.
///
/// Every file counts except the two that are not assets: a chunk, which is
/// made *from* assets, and a dotfile. A font, a save blob and a level layout
/// are all `Blobs` values now, so a file left out of the list is a key the
/// project cannot name whatever its extension is - which is the whole of what
/// this check is for.
Map<String, List<String>> unbundledAssets(Directory projectDir) {
  final config = GoodConfig.read(projectDir);
  final output = Directory('${projectDir.path}/${config.assetOutput}');
  if (!output.existsSync()) return const <String, List<String>>{};

  final declared = <String>{for (final entry in config.assets) entry.path};
  final root = config.assetOutput.endsWith('/')
      ? config.assetOutput
      : '${config.assetOutput}/';
  // Trailing separators stripped before anything is measured against this, so
  // a `GoodConfig` directory that ends in `/` does not eat the first character
  // of every relative path. Windows also hands back a mix of separators.
  final base = output.path.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '');

  final missing = <String, List<String>>{};
  for (final file in output.listSync(recursive: true).whereType<File>()) {
    final relative = file.path.replaceAll(r'\', '/').substring(base.length + 1);
    if (relative.split('/').any((segment) => segment.startsWith('.'))) continue;
    final bundlePath = '$root$relative';
    if (bundlePath.startsWith(config.packOutput)) continue;
    if (declared.contains(bundlePath)) continue;
    final slash = bundlePath.lastIndexOf('/');
    final entry = bundlePath.substring(0, slash + 1);
    if (declared.contains(entry)) continue;
    missing.putIfAbsent(entry, () => <String>[]).add(bundlePath);
  }
  for (final paths in missing.values) {
    paths.sort();
  }
  return missing;
}

/// What to tell someone whose assets are not bundled.
///
/// Names the files, then the exact lines to add. Both halves matter: the files
/// are how you recognise the problem as yours, and the lines are how it stops.
String unbundledAssetsMessage(Map<String, List<String>> unbundled) {
  final all = <String>[for (final paths in unbundled.values) ...paths]..sort();
  final shown = all.length > 5 ? all.sublist(0, 5) : all;
  final listed = shown.join(', ');
  final rest = all.length - shown.length;
  final buffer = StringBuffer()
    ..write('${all.length} asset(s) under the output directory are not ')
    ..write('bundled: $listed')
    ..write(rest > 0 ? ', and $rest more.' : '.')
    ..write(
      ' The entries under `good: assets:` are not recursive, so a '
      'subdirectory needs a line of its own. Add to pubspec.yaml:\n',
    );
  for (final entry in unbundled.keys.toList()..sort()) {
    buffer.write('    - $entry\n');
  }
  return buffer.toString();
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

/// Which good package the project entered the engine through - the entry
/// package.
///
/// It is the version the bundle's pubspec asks for, and it is what
/// `enginePackageDrawsTextures` walks to decide whether the project has a
/// renderer at all. It is **not** what the generated files import: a package
/// can depend on the engine and re-export none of it, so the imports are the
/// packages that declare the names, by `generatedImport` (#316).
///
/// # How the package is chosen
///
/// The project's direct `dependencies:`, narrowed twice.
///
/// First to the engine packages among them, by [EngineDependencies] - the
/// same test `good generate` uses to decide whose `lib/` holds declarations
/// (#305). A dependency is an engine package when it reaches `package:good`
/// through its own `dependencies:`, so `google_fonts` is not one and a
/// renderer nobody here has heard of is.
///
/// Then to the most specific of those. One candidate depending on another
/// means the second is what the first is built on: a project declaring a
/// renderer and the kernel answers the renderer, and a project declaring a
/// renderer built on `goo2d` answers that renderer and not `goo2d`. No list of
/// package names takes part (#309).
///
/// Two candidates neither of which depends on the other - a project declaring
/// two renderers side by side - are ordered by name, so the answer does not
/// change between runs.
///
/// # Generated packages are not candidates
///
/// A dependency whose directory carries `bundleMarkerName` is dropped before
/// either narrowing (#320). `good generate` adds the bundle to the project's
/// `dependencies:`, so from the second run on it is a resolved direct
/// dependency that reaches the engine and that nothing else depends on - the
/// most specific candidate by both tests above. Naming it here put the bundle
/// in its own `dependencies:`, and `pub get` answered "A package may not list
/// itself as a dependency" for the whole project.
///
/// The marker and not the recorded name, on the same argument as #305 and
/// #309: it asks what the directory is. That also covers a bundle the project
/// did not generate - one belonging to a second project, reached through a
/// `path:` dependency - which holds nothing but generated code either way.
///
/// # What it reads, and what it answers without
///
/// Each candidate's own pubspec, found through
/// `.dart_tool/package_config.json`. A project resolved before this runs has
/// a graph to walk; one whose dependency was added since its last
/// `flutter pub get` has that dependency in no graph at all, and it drops out
/// with everything else that cannot be read.
///
/// Falls back to [engineRootPackage] when no direct dependency reaches the
/// engine. The bundle's pubspec is written from this answer - see
/// `engineDependencyFor` - so a project that names no engine still gets a
/// bundle that resolves.
/// `good create` does not come through here: it scaffolded the project and
/// passes the engine it wrote to [runGenerate] directly.
String enginePackageOf(Directory projectDir) {
  final facts = readPubspecFacts(File('${projectDir.path}/pubspec.yaml'));
  if (facts == null) return engineRootPackage;
  final resolved = resolvedPackages(projectDir);
  final engine = EngineDependencies(
    roots: <String, Directory>{
      for (final entry in resolved.entries) entry.key: entry.value.root,
    },
  );
  final candidates =
      facts.dependencies
          .where((name) => !isGeneratedBundle(resolved[name]?.root))
          .where(engine.contains)
          .toList()
        ..sort();
  if (candidates.isEmpty) return engineRootPackage;
  for (final candidate in candidates) {
    final builtOn = candidates.any(
      (other) => other != candidate && engine.dependsOn(other, candidate),
    );
    if (!builtOn) return candidate;
  }
  // Every candidate is depended on by another one, which takes a cycle among
  // them. There is no most specific package to name, and the first by name is
  // an answer two runs agree on.
  return candidates.first;
}

/// The `flutter: assets:` entries a project declares, verbatim.
///
/// Flutter's list, not good's - the one thing that reads it is the build's
/// check that the chunk directory is in it, since a chunk Flutter does not
/// bundle is a game that fails at its first asset load with every file present
/// on the build machine. What good packs is [GoodConfig.assets].
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
