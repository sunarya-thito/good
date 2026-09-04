// The declaration table a project carries for the classes its own author
// wrote.
//
// # Why a project needs one at all
//
// `collectDeclarations` reads a class's fields off a generated table, because
// a running program cannot ask an object what fields it has. Every engine
// package ships one for the classes it can instantiate, and those tables hold
// a handful of systems - what they cannot hold is `MainScene`, `Player` and
// `WalkgameGame`, which are classes the person wrote. So a project with no
// table of its own boots as far as the first registration and throws
// `No generated collector for WalkgameGame`, and no table any engine package
// ships can answer for it.
//
// # Why it goes in the project's own lib/
//
// #299 and #300 put `good generate`'s output in the generated package beside
// the project, and #313 carves out the case this is: where the sub package
// cannot express the output, it goes in the project's `lib/`. A collector
// casts to the class it reads and names that class in a `const` table, so a
// table keyed by `Player` has to sit in a library that can name `Player` -
// which is the project and nowhere else. The sub package depends on the
// project the other way round.
//
// # Why it is the same emitter the engine packages use
//
// Because it is one artifact. `good build` runs `good generate` for the reason
// #362 gives - two generation mechanisms can disagree about what is current -
// and two emitters for one file shape is that defect one step further in. See
// `declaration_collectors.dart`.

import 'dart:io';

import 'package:good_cli/src/generate/declaration_collectors.dart';
import 'package:good_cli/src/generate/declaration_emit.dart';
import 'package:good_cli/src/generate/engine_dependency.dart';
import 'package:good_cli/src/generate/engine_package.dart';
import 'package:good_cli/src/generate/imports.dart';
import 'package:good_cli/src/generate/scan.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// A project and the engine packages it resolved, as packages a generator
/// addresses.
@immutable
class ProjectPackages {
  const ProjectPackages({required this.project, required this.engine});

  /// The project itself - the one package written into.
  final EnginePackage project;

  /// Every engine package it resolves, directly or through another.
  ///
  /// Read and never written into, the same split a run over this repository
  /// makes: a project's `good generate` has no business writing a file into a
  /// copy of `goo2d` in a pub cache. They are read because the project's own
  /// classes cannot be understood without them - `WalkgameGame extends Game2D`
  /// is a scanned class only if `Game2D` reaches `Scannable`, and that chain
  /// lies entirely inside those packages.
  final List<EnginePackage> engine;

  /// The project first, then what it is built on.
  List<EnginePackage> get all => <EnginePackage>[project, ...engine];
}

/// [projectDir] and everything it resolves that is built on the engine.
///
/// Read out of `.dart_tool/package_config.json`, so a project that has never
/// been resolved answers with no engine packages at all - which
/// [projectDeclarations] refuses by name rather than generating an empty table
/// from.
ProjectPackages projectPackages(Directory projectDir) {
  final facts = readPubspecFacts(File(p.join(projectDir.path, 'pubspec.yaml')));
  final name = facts?.name;
  if (name == null) {
    throw ArgumentError(
      'No package name in ${p.join(projectDir.path, 'pubspec.yaml')}, so there '
      'is nothing to name the generated declaration table after.',
    );
  }
  final project = EnginePackage(
    name: name,
    root: projectDir,
    dependencies: <String>{...facts!.dependencies, ...facts.devDependencies},
  );

  final resolved = resolvedPackages(projectDir);
  final engine = EngineDependencies(
    roots: <String, Directory>{
      for (final package in resolved.values) package.name: package.root,
    },
  );
  final packages = <EnginePackage>[];
  for (final entry in resolved.values) {
    if (entry.name == name) continue;
    if (!engine.contains(entry.name)) continue;
    if (!Directory(entry.lib).existsSync()) continue;
    final read = readPubspecFacts(File(p.join(entry.root.path, 'pubspec.yaml')));
    packages.add(
      EnginePackage(
        name: entry.name,
        root: entry.root,
        dependencies: <String>{
          ...?read?.dependencies,
          ...?read?.devDependencies,
        },
      ),
    );
  }
  packages.sort((a, b) => a.name.compareTo(b.name));
  return ProjectPackages(project: project, engine: packages);
}

/// What one project's declaration table holds, and what it left out.
@immutable
class ProjectDeclarations {
  const ProjectDeclarations({
    required this.file,
    required this.classes,
    required this.declarations,
    required this.skipped,
  });

  /// The file to write, or null where the project declares no scanned class
  /// and so has no table to name.
  final GeneratedFile? file;

  /// How many of the project's classes got a collector.
  final int classes;

  /// How many declarations those collectors read, over all of them.
  final int declarations;

  /// Every declaration that reached no collector, keyed `Class.field`, to why.
  ///
  /// A private field, or a private class. Reported and not fatal, for
  /// `DeclarationCollectorScan.skipped`'s reason - and it matters more here
  /// than in this repository, because the hole is in a row of the person's own
  /// entity and this message is the only thing that says where.
  final Map<String, String> skipped;
}

/// The declaration table [projectDir] would carry.
///
/// # It refuses rather than writing an empty table
///
/// A project whose engine packages cannot be read is not a project that
/// declares nothing. `WalkgameGame extends Game2D` is a scanned class only
/// because `Game2D` reaches `Scannable`, and with `goo2d` unread the walk sees
/// a class extending a name it has never heard of and moves on. Everything
/// downstream of that is the failure this file exists to remove: a table that
/// is there, is current by every check, and answers for nothing.
///
/// So the precondition is checked outright - `Scannable` has to be among the
/// types the walk read. That is one name and it is the root the whole test
/// bottoms out at, so nothing but the engine's own source satisfies it.
ProjectDeclarations projectDeclarations(
  Directory projectDir, {
  required String command,
}) {
  final packages = projectPackages(projectDir);
  final project = packages.project;
  final sources = readSources(
    projectDir,
    // Its own output, and only its own. A stale table declares the name the
    // new one is about to, and a walk that read it back would resolve that
    // name to the file it is replacing.
    exclude: <String>{project.declarationsFile.path},
  );

  if (!sources.typesByName.containsKey(scannableRoot)) {
    throw ArgumentError(
      'Cannot read the engine from ${projectDir.path}, so nothing can be said '
      'about which of its classes declare anything: $scannableRoot is in none '
      'of the source this read.\n'
      '\n'
      'The engine packages are found through '
      '`.dart_tool/package_config.json`, so this is what an unresolved project '
      'looks like. Run `flutter pub get` and generate again.\n'
      '\n'
      'Refused rather than writing what could be read: a table generated with '
      'the engine out of the read set holds no collectors, is current by every '
      'check there is, and every game built on it throws at its first '
      'registration.',
    );
  }

  final collectors = scanDeclarationCollectors(
    packages: packages.all,
    sources: sources,
  );
  final imports = Imports(
    declaredIn: declaredIn(sources),
    byLibDir: <String, EnginePackage>{
      for (final package in packages.all) package.libDir: package,
    },
    units: sources.units,
    packages: packages.all,
  );
  final files = declarationFiles(
    collectors,
    <EnginePackage>[project],
    imports,
    known: packages.all,
    // What the engine packages' own copies say here is "run it from
    // packages/good_tool, and commit what changes", and neither half is true
    // of a project: this file is rewritten by every build, and whether it is
    // committed is the project's call.
    regenerate: <String>[
      'Regenerate with `$command`. It is rewritten from your',
      'lib/ every time, so an edit here is gone on the next build.',
    ],
  );
  final entries =
      collectors.byPackage[project.name] ?? const <DeclarationCollectorEntry>[];
  var declarations = 0;
  for (final entry in entries) {
    declarations += entry.fields.length;
  }
  return ProjectDeclarations(
    file: files.isEmpty ? null : files.single,
    classes: entries.length,
    declarations: declarations,
    skipped: <String, String>{
      for (final entry in collectors.skipped.entries)
        if (_ownedBy(project, collectors, entry.key)) entry.key: entry.value,
    },
  );
}

/// Whether [key] names something in [project] rather than in a package it
/// reads.
///
/// A skipped entry from an engine package is that package's business and is
/// reported by that package's own generator; repeating it here sends somebody
/// to edit a file in a pub cache.
bool _ownedBy(
  EnginePackage project,
  DeclarationCollectorScan scan,
  String key,
) {
  final type = key.split('.').first;
  for (final entry in scan.entries) {
    if (entry.type != type) continue;
    return entry.package == project.name;
  }
  // A class skipped outright has no entry to read a package off. The walk
  // reaches those only through a file it read, and the ones worth naming to
  // the person are the ones they can edit, so this errs towards saying so.
  return true;
}
