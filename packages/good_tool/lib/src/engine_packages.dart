// Which directories in a checkout generated code may be written into.
//
// The package model itself - what a package's generated files are called and
// where they sit - is `good_cli`'s `EnginePackage`, because `good generate`
// writes into a package too. What is here is the part only a run over a
// checkout asks: which of the directories `--dir` named qualify.

import 'dart:io';

// good_cli's `lib/src` is private by convention and this reaches into it.
// What is shared is the one definition of "depends on the engine" (#305):
// `good_cli` asks it of a project's resolved dependencies and this asks it of
// the directories it was pointed at, and two copies of that test would be two
// answers to drift apart.
// ignore: implementation_imports
import 'package:good_cli/src/generate/engine_dependency.dart';
// ignore: implementation_imports
import 'package:good_cli/src/generate/engine_package.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

// Re-exported so the name of the package the whole test bottoms out at has one
// spelling in this package too, rather than a second literal in the message
// that reports it.
// ignore: implementation_imports
export 'package:good_cli/src/generate/engine_dependency.dart'
    show engineRootPackage;


/// What one pass over the directories `--dir` named found.
@immutable
class PackageScan {
  const PackageScan({
    required this.packages,
    required this.dependencies,
    required this.rejected,
    required this.looked,
  });

  /// Every package to generate into, sorted by name.
  final List<EnginePackage> packages;

  /// The engine packages [packages] depend on that were not themselves named,
  /// sorted by name - read, never written into.
  ///
  /// Nothing in this repository's own run: `--dir packages` names every engine
  /// package there is, so a dependency of one is another one. It is the
  /// standalone case that needs it (#305). A third-party `good_physics_foo`
  /// pointed at with `--dir .` is one package on its own, and `Component`,
  /// `Field` and `Accessor` are all declared in `good` - so with only its own
  /// `lib/` read, its components are not components, its columns are not
  /// columns, and the run generates nothing while reporting success.
  ///
  /// Read but never written into, which is the whole distinction: `goo2d`
  /// generates its own files in its own run, and a run over somebody else's
  /// package has no business writing into a copy of it in a pub cache.
  final List<EnginePackage> dependencies;

  /// Every directory that held a pubspec and was not taken, to why.
  ///
  /// Keyed by the directory's own name. This is what a run that matched nothing
  /// prints: "there was nothing there" and "there were four things and none of
  /// them qualified" are different situations, and somebody staring at a run
  /// that generated nothing needs to be told which one they are in.
  final Map<String, String> rejected;

  /// The directories that were looked in, as they were given.
  final List<String> looked;

  /// Package names that two different directories both claimed, to those
  /// directories.
  ///
  /// An error rather than a merge, and the caller raises it: two packages of
  /// one name would write two component-bit tables under one identifier, and
  /// nothing downstream could tell which numbering a signature came from.
  Map<String, List<String>> get duplicates {
    final byName = <String, List<String>>{};
    for (final package in packages) {
      byName.putIfAbsent(package.name, () => <String>[]).add(package.root.path);
    }
    byName.removeWhere((_, roots) => roots.length < 2);
    return byName;
  }
}

/// Every package under [directories] that generated code can be written into.
///
/// # Where it looks
///
/// Each directory named, **and each of its immediate children**. Both, because
/// both are real invocations: `--dir packages` from a monorepo root means the
/// packages inside it, and `--dir .` from a package's own root means that
/// package. Neither is a special case of the other, and guessing between them
/// from the directory's name would be the kind of mistake this replaced (#305).
///
/// It does not recurse further. A walk of arbitrary depth would reach a
/// package's `example/`, the copies of other packages under `.dart_tool/`, and
/// any checkout that happened to be sitting in the tree - and the answer to a
/// layout nested deeper is a second `--dir`, which costs a word and says
/// exactly what is meant.
///
/// # What it takes
///
/// A directory qualifies when it has a `pubspec.yaml` naming the package, has a
/// `lib/`, is not `publish_to: none`, and **depends on the engine** -
/// [EngineDependencies], which is `package:good` in the transitive closure of
/// its `dependencies:`.
///
/// Published, because that is exactly the set a user can import. `doc_snippets`
/// and `good_tool` itself declare `publish_to: none` and drop out here - the
/// first would otherwise contribute the components in its generated
/// `lib/pages/`, which are extracted from the docs and git-ignored, and
/// generating engine code from a copy of the documentation is a loop nobody
/// wants to debug.
///
/// Depending on the engine, because a package that is not built on the engine
/// cannot declare a component, and parsing it is a walk that can only ever
/// find nothing. `goo2d_ffi_box2d` is that case in this repository: raw Box2D
/// bindings with no engine dependency and no component, parsed on every run
/// until this.
///
/// A qualifying package with no components generates nothing and costs a walk.
/// That is the right direction for this to fail in: a new engine package is
/// picked up by being one, rather than by being added to a list in this file
/// that nothing would report as missing.
PackageScan enginePackages(List<Directory> directories) {
  final candidates = <String, Directory>{};
  for (final directory in directories) {
    if (!directory.existsSync()) continue;
    _consider(candidates, directory);
    for (final entry in directory.listSync()) {
      if (entry is Directory) _consider(candidates, entry);
    }
  }

  // Every pubspec is read before anything is decided. The engine test asks
  // about a package's dependencies by name, and in a monorepo those names are
  // the other candidates: `goo2d_physics_box2d` reaches `good` through `goo2d`,
  // which is the directory next door rather than anything a config resolves.
  final facts = <String, PubspecFacts>{};
  final roots = <String, Directory>{};
  final found = <(Directory, PubspecFacts)>[];
  for (final candidate in candidates.values) {
    final read = readPubspecFacts(
      File(p.join(candidate.path, 'pubspec.yaml')),
    );
    final name = read?.name;
    if (read == null || name == null) continue;
    found.add((candidate, read));
    facts[name] = read;
    roots[name] = candidate;
  }

  // And where a name is not another candidate, wherever that candidate's own
  // `pub get` resolved it. This is what makes a standalone package work at all:
  // a third-party `good_physics_foo` depends on `goo2d` from pub.dev, so the
  // edge that reaches `good` leaves through the package config rather than
  // through the directory this was pointed at.
  for (final root in roots.values.toList()) {
    for (final entry in resolvedPackages(root).entries) {
      roots.putIfAbsent(entry.key, () => entry.value.root);
    }
  }

  final engine = EngineDependencies(known: facts, roots: roots);
  final packages = <EnginePackage>[];
  final rejected = <String, String>{};
  for (final (root, read) in found) {
    final name = read.name!;
    final label = p.basename(root.path);
    if (!read.isPublished) {
      rejected[label] = '$name declares publish_to: none';
      continue;
    }
    if (!Directory(p.join(root.path, 'lib')).existsSync()) {
      rejected[label] = '$name has no lib/';
      continue;
    }
    if (!engine.contains(name)) {
      rejected[label] =
          '$name does not depend on package:$engineRootPackage, directly or '
          'through anything it depends on';
      continue;
    }
    packages.add(
      EnginePackage(
        name: name,
        root: root,
        dependencies: <String>{...read.dependencies, ...read.devDependencies},
      ),
    );
  }
  packages.sort((a, b) => a.name.compareTo(b.name));

  // The engine packages the targets depend on and that are not targets
  // themselves. Engine packages only, and not every resolved dependency: what
  // this widens is the set of files parsed, and `flutter` alone would be more
  // source than everything else here put together.
  final taken = <String>{for (final package in packages) package.name};
  final dependencies = <String, EnginePackage>{};
  for (final package in packages) {
    for (final entry in resolvedPackages(package.root).entries) {
      if (taken.contains(entry.key)) continue;
      if (dependencies.containsKey(entry.key)) continue;
      if (!engine.contains(entry.key)) continue;
      if (!Directory(entry.value.lib).existsSync()) continue;
      final read =
          facts[entry.key] ??
          readPubspecFacts(File(p.join(entry.value.root.path, 'pubspec.yaml')));
      dependencies[entry.key] = EnginePackage(
        name: entry.key,
        root: entry.value.root,
        dependencies: <String>{
          ...?read?.dependencies,
          ...?read?.devDependencies,
        },
      );
    }
  }
  final read = dependencies.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  return PackageScan(
    packages: packages,
    dependencies: read,
    rejected: rejected,
    looked: <String>[for (final directory in directories) directory.path],
  );
}

/// Records [directory] as a candidate when it holds a pubspec, once.
///
/// Once, keyed on the resolved path, because two `--dir` arguments are allowed
/// to overlap: `--dir . --dir packages` from a monorepo root reaches `packages`
/// both as a child of `.` and as itself.
void _consider(Map<String, Directory> into, Directory directory) {
  final key = p.normalize(p.absolute(directory.path));
  if (!File(p.join(key, 'pubspec.yaml')).existsSync()) return;
  into.putIfAbsent(key, () => Directory(key));
}
