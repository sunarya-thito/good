import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The package every engine package's dependencies bottom out at (#305).
///
/// The one name written down here, and it is the root of a package graph
/// rather than a key anything is looked up by: `package:good` is what "the
/// engine" *is*, and a package reaches it or it does not. Nothing resolves a
/// declaration through this string, and no author has to spell anything to be
/// found - they already wrote the dependency.
const String engineRootPackage = 'good';

/// The package that declares `Texture` (#312).
///
/// The second name written down here, and the same kind of name as
/// [engineRootPackage]: the root of a package graph, not a key anything is
/// looked up by. `Texture` is declared in `goo2d/lib/src/render/texture.dart`
/// and exported from `package:goo2d/goo2d.dart`, so a package that draws is
/// one that reaches `goo2d` - see [enginePackageDrawsTextures].
const String textureRootPackage = 'goo2d';

/// The parts of a `pubspec.yaml` anything here asks about.
@immutable
class PubspecFacts {
  const PubspecFacts({
    required this.name,
    required this.publishTo,
    required this.dependencies,
    required this.devDependencies,
  });

  /// The package name, or `null` when the pubspec declares none.
  final String? name;

  /// The `publish_to:` value, or `null` when there is none.
  final String? publishTo;

  /// Whether this package is published anywhere - `publish_to: none` is not.
  bool get isPublished => publishTo != 'none';

  /// Every key under `dependencies:`.
  final Set<String> dependencies;

  /// Every key under `dev_dependencies:`.
  final Set<String> devDependencies;
}

/// Reads [pubspec], or `null` when it is absent or not a YAML map.
///
/// Through a YAML parser rather than line by line. A pubspec written by
/// somebody else indents how it likes, quotes keys when it likes and is under
/// no obligation to look like the ones in this repository - and the answer to
/// a pubspec this cannot read has to be "no dependencies", which for the
/// engine test below means "not an engine package". A line scanner that missed
/// a four-space `dependencies:` block would decide that silently.
PubspecFacts? readPubspecFacts(File pubspec) {
  if (!pubspec.existsSync()) return null;
  final Object? doc;
  try {
    doc = loadYaml(pubspec.readAsStringSync());
  } on YamlException {
    return null;
  } on FileSystemException {
    return null;
  }
  if (doc is! YamlMap) return null;
  final name = doc['name'];
  final publishTo = doc['publish_to'];
  return PubspecFacts(
    name: name is String ? name : null,
    publishTo: publishTo is String ? publishTo : null,
    dependencies: _keys(doc['dependencies']),
    devDependencies: _keys(doc['dev_dependencies']),
  );
}

Set<String> _keys(Object? node) => <String>{
  if (node is YamlMap)
    for (final key in node.keys)
      if (key is String) key,
};

/// One package a `package_config.json` resolved.
@immutable
class ResolvedPackage {
  const ResolvedPackage({
    required this.name,
    required this.root,
    required this.lib,
  });

  final String name;

  /// The package's own directory - where its `pubspec.yaml` is.
  final Directory root;

  /// Its `lib/`, or wherever `packageUri` points, normalised and absolute.
  ///
  /// Not checked for existence here. A caller walking it has to check; a
  /// caller reading the pubspec beside it does not, and dropping an entry
  /// whose `lib/` is missing would cut a link out of the dependency graph.
  final String lib;
}

/// Every package `<dir>/.dart_tool/package_config.json` names.
///
/// Empty before a `pub get`, and that is an answer rather than an error: a
/// package config is how a resolved dependency's directory is found at all, so
/// without one nothing outside [dir] can be read and every question about a
/// dependency is answered from what is already on hand.
Map<String, ResolvedPackage> resolvedPackages(Directory dir) {
  final file = File(p.join(dir.path, '.dart_tool', 'package_config.json'));
  if (!file.existsSync()) return const <String, ResolvedPackage>{};
  final Object? doc;
  try {
    doc = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return const <String, ResolvedPackage>{};
  } on FileSystemException {
    return const <String, ResolvedPackage>{};
  }
  if (doc is! Map<String, Object?>) return const <String, ResolvedPackage>{};
  final packages = doc['packages'];
  if (packages is! List<Object?>) return const <String, ResolvedPackage>{};

  final resolved = <String, ResolvedPackage>{};
  for (final entry in packages) {
    if (entry is! Map<String, Object?>) continue;
    final name = entry['name'];
    if (name is! String) continue;
    final rootUri = entry['rootUri'];
    if (rootUri is! String) continue;
    final packageUri = entry['packageUri'];
    final base = rootUri.startsWith('file:')
        ? File.fromUri(Uri.parse(rootUri)).path
        : p.normalize(p.join(file.parent.path, rootUri));
    resolved[name] = ResolvedPackage(
      name: name,
      root: Directory(p.normalize(p.absolute(base))),
      lib: p.normalize(
        p.absolute(p.join(base, packageUri is String ? packageUri : 'lib/')),
      ),
    );
  }
  return resolved;
}

/// Answers whether a package depends on the engine (#305).
///
/// # Why this replaces a name test
///
/// `good_cli` decided by prefix - `name == 'good' || name.startsWith('goo')` -
/// which reads `google_fonts`, `google_sign_in`, `googleapis`, `goodies` and
/// `gooey` as engine packages and walks their `lib/` on every generate.
/// `google_fonts` is in a large share of Flutter projects. A name is not a
/// capability and is not the author's to coordinate: nobody who called a
/// package `gooey` opted into anything.
///
/// # What "depends on the engine" means
///
/// [engineRootPackage] is in the transitive closure of the package's
/// `dependencies:`, or the package *is* [engineRootPackage].
///
/// **Transitive**, because a physics backend depends on `goo2d` and `goo2d`
/// depends on `good`. `goo2d_physics_box2d` declares no edge to `good` at all,
/// and it is exactly the kind of package this has to recognise.
///
/// **`dependencies:` only, never `dev_dependencies:`.** What is being asked is
/// whether this package's `lib/` can hold engine declarations, and a dev
/// dependency is not on `lib/`'s import path - a package that dev-depends on
/// the engine to test something against it ships no components of its own.
/// `good_net_p2p` has both edges and qualifies through the real one.
///
/// **The engine itself counts.** It declares components and gets a generated
/// table like any other, and a rule with an exception for the author of the
/// rule is the one that rots.
class EngineDependencies {
  EngineDependencies({
    Map<String, PubspecFacts> known = const <String, PubspecFacts>{},
    Map<String, Directory> roots = const <String, Directory>{},
  }) : _facts = <String, PubspecFacts?>{...known},
       _roots = <String, Directory>{...roots};

  /// Where a package not already in [_facts] can be read from, by name.
  final Map<String, Directory> _roots;

  /// What each package's pubspec said, by name. Seeded with whatever the
  /// caller had already read and filled in from [_roots] on demand, with a
  /// `null` entry recording a pubspec that could not be read so it is looked
  /// for once.
  final Map<String, PubspecFacts?> _facts;

  final Map<String, bool> _answers = <String, bool>{};

  /// Whether [name] is the engine or reaches it through `dependencies:`.
  bool contains(String name) =>
      _answers[name] ??= _reaches(name, engineRootPackage);

  /// Whether [name] is [target] or reaches it through `dependencies:`.
  ///
  /// This is [contains] with the destination left open, and it orders two
  /// engine packages against each other: a renderer declares `goo2d`, so
  /// `dependsOn('neon', 'goo2d')` is true and `dependsOn('goo2d', 'neon')` is
  /// not. `dependsOn(x, x)` is true, the same way the engine counts as an
  /// engine package.
  ///
  /// Not memoised. [_answers] holds answers about [engineRootPackage] alone,
  /// and a walk to somewhere else would poison it.
  bool dependsOn(String name, String target) => _reaches(name, target);

  /// A breadth-first walk, whose answer is memoised for [name] alone.
  ///
  /// For [name] alone because a package reached part-way through this walk has
  /// had only as much of its own closure looked at as this walk happened to
  /// visit, so recording an answer for it would be recording a guess. The
  /// graph is a few hundred nodes and each pubspec is read once, so asking
  /// about every package separately costs a few hundred set operations rather
  /// than a few hundred re-reads.
  bool _reaches(String start, String target) {
    final seen = <String>{start};
    final queue = <String>[start];
    while (queue.isNotEmpty) {
      final name = queue.removeLast();
      if (name == target) return true;
      final facts = _factsFor(name);
      if (facts == null) continue;
      for (final dependency in facts.dependencies) {
        if (seen.add(dependency)) queue.add(dependency);
      }
    }
    return false;
  }

  PubspecFacts? _factsFor(String name) {
    if (_facts.containsKey(name)) return _facts[name];
    final root = _roots[name];
    return _facts[name] = root == null
        ? null
        : readPubspecFacts(File(p.join(root.path, 'pubspec.yaml')));
  }
}

/// Whether generated code importing [enginePackage] can name `Texture`.
///
/// The question the texture enum's payload type turns on. `Texture` lives in
/// [textureRootPackage], so a project draws when its entry package is that
/// package or reaches it through `dependencies:`. `goo3d` depends on `good`
/// and never on `goo2d`, so a 3D project answers `false` and its texture keys
/// carry `Object?` - which is what keeps `Texture isn't a type` out of its
/// first `flutter analyze`.
///
/// Answered from the graph and not from [enginePackage]'s name, so a renderer
/// somebody else publishes on top of `goo2d` gets typed keys without being
/// listed anywhere here.
///
/// # What it does not answer
///
/// Which package the generated file imports. That is [generatedImport], and
/// the two are separate: this one asks whether a `Texture` exists in the
/// project at all, and that one asks who declares the name. A package can
/// reach `goo2d` and export nothing of it - `goo2d_physics_box2d` exports its
/// own `src/` and re-exports neither `goo2d` nor the kernel - so the answer
/// here is `true` and the import is still `package:goo2d/goo2d.dart` (#316).
///
/// # An unresolved project
///
/// The graph comes from `.dart_tool/package_config.json`, so a project that
/// has not run `flutter pub get` has no graph and a third-party renderer in it
/// answers `false`. That is `Object?` on keys that could have been typed, and
/// not a name that fails to resolve. Resolving the project and running
/// `good generate` again types them.
bool enginePackageDrawsTextures(Directory projectDir, String enginePackage) =>
    EngineDependencies(
      roots: <String, Directory>{
        for (final entry in resolvedPackages(projectDir).entries)
          entry.key: entry.value.root,
      },
    ).dependsOn(enginePackage, textureRootPackage);

/// The package a generated file imports to name the engine types in it.
///
/// Two packages declare those names, and which one a file needs is decided by
/// the file's contents and nothing else: [engineRootPackage] declares
/// `AssetKey`, `LocalEnumAssetKey`, `AudioClip` and the pack API, and
/// [textureRootPackage] declares `Texture`. [namesTexture] says whether this
/// file spells the renderer type - which is [enginePackageDrawsTextures] for
/// the texture enum, and `false` for everything else generated.
///
/// # Why not the entry package
///
/// The bundle wrote one import for the package #309 resolved out of the
/// dependency graph and named every type through it, which holds only while
/// that package re-exports what it is built on. `goo2d_physics_box2d` does
/// not: its library exports its own `src/` files and nothing else, and a
/// project declaring it and `goo2d` resolves the physics package as the more
/// specific of the two. The generated file then failed at `AssetKey`, so
/// every asset kind broke and not only the textures (#316).
///
/// # One import and not two
///
/// A file naming `Texture` names `AssetKey` as well, and both imports would
/// resolve - two URIs delivering the same declaration are not ambiguous. They
/// are not both *needed*: [textureRootPackage] re-exports [engineRootPackage],
/// so the second import is an `unnecessary_import`, which `flutter analyze`
/// reports and a project's own CI fails on.
String generatedImport({required bool namesTexture}) =>
    namesTexture ? textureRootPackage : engineRootPackage;

/// Every package the generated files import, which is what the bundle's
/// pubspec has to depend on.
///
/// The union over the four generated files. `audios.dart` and `good.dart`
/// name kernel types whatever the project renders with, so
/// [engineRootPackage] is in it always; `textures.dart` adds
/// [textureRootPackage] where the payload is a `Texture`.
///
/// Declared and not merely resolvable. `package:good/good.dart` resolves out
/// of the project's package config whether or not the bundle asks for it, and
/// `depend_on_referenced_packages` - which `flutter_lints` turns on in every
/// project `flutter create` writes - reports the import that is not declared
/// beside it.
Set<String> generatedImports({required bool drawsTextures}) => <String>{
  engineRootPackage,
  if (drawsTextures) textureRootPackage,
};
