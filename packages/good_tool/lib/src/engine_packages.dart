import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// One package in this repository that generated code can be written into.
@immutable
class EnginePackage {
  const EnginePackage({
    required this.name,
    required this.root,
    required this.dependencies,
  });

  /// The package name, as its pubspec declares it.
  final String name;

  /// Its directory under `packages/`.
  final Directory root;

  /// Every package it declares a dependency on, `dependencies` and
  /// `dev_dependencies` alike.
  ///
  /// Read so a generated file never imports a package the one holding it does
  /// not depend on. `Camera` is a `goo2d` component with a `CameraView?`
  /// column, and `CameraView` is declared in `good` - so that import is only
  /// legal because `goo2d` depends on `good`, and the next such pair might not
  /// be.
  final Set<String> dependencies;

  /// Its `lib/`, normalised and absolute.
  String get libDir => p.normalize(p.absolute(p.join(root.path, 'lib')));

  /// Its entry library - `lib/<name>.dart`.
  File get barrel => File(p.join(libDir, '$name.dart'));

  /// Where generated accessor properties go.
  ///
  /// `lib/src/<something>.g.dart` is the shape this repository already uses for
  /// a checked-in generated file: `goo2d_ffi_box2d/lib/src/box2d.g.dart`,
  /// exported from that package's entry library by a hand-written line.
  File get accessorFile => File(p.join(libDir, 'src', 'accessors.g.dart'));

  /// The `export` line [barrel] has to carry for [accessorFile] to be reachable.
  String get accessorExport => "export 'src/accessors.g.dart';";
}

/// Every package under `packages/` that is published from this repository.
///
/// Published, because that is exactly the set a user can import. `doc_snippets`
/// and `good_tool` itself declare `publish_to: none` and drop out here - the
/// first would otherwise contribute the components in its generated
/// `lib/pages/`, which are extracted from the docs and git-ignored, and
/// generating engine code from a copy of the documentation is a loop nobody
/// wants to debug.
///
/// A published package with no components generates nothing and costs a walk.
/// That is the right direction for this to fail in: a new engine package is
/// picked up by existing here, rather than by being added to a list in this
/// file that nothing would report as missing.
List<EnginePackage> enginePackages(Directory repoRoot) {
  final dir = Directory(p.join(repoRoot.path, 'packages'));
  if (!dir.existsSync()) return const <EnginePackage>[];
  final packages = <EnginePackage>[];
  for (final entry in dir.listSync()) {
    if (entry is! Directory) continue;
    final pubspec = File(p.join(entry.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) continue;
    final lines = pubspec.readAsLinesSync();
    final name = _scalar(lines, 'name');
    if (name == null) continue;
    final publishTo = _scalar(lines, 'publish_to');
    if (publishTo != null && publishTo.replaceAll('"', '') == 'none') continue;
    if (!Directory(p.join(entry.path, 'lib')).existsSync()) continue;
    packages.add(
      EnginePackage(
        name: name,
        root: entry,
        dependencies: _dependencyNames(lines),
      ),
    );
  }
  packages.sort((a, b) => a.name.compareTo(b.name));
  return packages;
}

/// The value of a top-level `key:` in a pubspec, or `null`.
///
/// Read line by line rather than through a YAML parser. What is wanted here is
/// two top-level scalars and the keys of two top-level maps, all of which are
/// at a fixed indentation in every pubspec in this repository, and this package
/// has no reason to take a YAML dependency for it.
String? _scalar(List<String> lines, String key) {
  for (final line in lines) {
    if (!line.startsWith('$key:')) continue;
    return line.substring(key.length + 1).trim();
  }
  return null;
}

/// Every key under `dependencies:` and `dev_dependencies:`.
Set<String> _dependencyNames(List<String> lines) {
  final names = <String>{};
  var inside = false;
  for (final line in lines) {
    if (line.startsWith('dependencies:') ||
        line.startsWith('dev_dependencies:')) {
      inside = true;
      continue;
    }
    if (line.isEmpty || line.startsWith('#')) continue;
    if (!line.startsWith(' ')) {
      inside = false;
      continue;
    }
    if (!inside) continue;
    final match = RegExp(r'^  ([A-Za-z_][A-Za-z0-9_]*):').firstMatch(line);
    if (match != null) names.add(match.group(1)!);
  }
  return names;
}
