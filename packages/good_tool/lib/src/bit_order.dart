// The bit order one game gets, which is the order that goes on the wire.
//
// `component_bits.g.dart` holds one package's order, and `--check` proves each
// of those files is what the generator would write now. What no generated file
// states is what bit 4 means to a running game: a game is numbered from every
// table it names plus every table those name, and the cross-package half of
// that numbering lives in `ComponentTypeRegistry.installGenerated` rather than
// in anything committed. So the per-package files can all be current and a
// game's numbering still move, because it also moves when the game's
// dependencies change.
//
// #381 makes bits per game - a bit for each component the project's prefabs
// use, and nothing else - and deletes the per-package tables. The proof that
// bit order has not moved has to stop being "those files regenerate
// byte-for-byte" before they go, and start being "this project's numbering
// regenerates identically". That is what this computes, from the same scan the
// tables are written from.

import 'dart:io';

// good_cli's `lib/src` is private by convention and this reaches into it, for
// the reason `scan.dart` states beside its own copy of this line.
// The engine test is the one in `engine_dependency.dart` and not a second
// answer to it: which packages a project is numbered from is which engine
// packages it depends on.
// ignore: implementation_imports
import 'package:good_cli/src/generate/engine_dependency.dart';
// ignore: implementation_imports
import 'package:good_cli/src/generate/engine_package.dart';
import 'package:good_tool/src/scan.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// What one project's component bits are, in the order they are numbered.
@immutable
class ProjectBitOrder {
  const ProjectBitOrder({
    required this.project,
    required this.packages,
    required this.bits,
  });

  /// The project's package name, as its pubspec declares it.
  final String project;

  /// The packages it is numbered from, in the order they are numbered - which
  /// is by name, because that is what `installGenerated` sorts by.
  ///
  /// Only the ones that have a table: a package the project depends on that
  /// registers no component contributes no bits and shifts nothing.
  final List<String> packages;

  /// Every component type the project holds a bit for, indexed by that bit.
  final List<ComponentBit> bits;

  /// The order as one line per bit - `0 goo2d:Camera`.
  ///
  /// The bit number is in the line rather than implied by the position,
  /// because that is the number a peer reads. A list of bare type names
  /// compared against another list reports "these two differ"; these lines
  /// report which bit changed meaning.
  List<String> get lines => <String>[
    for (var i = 0; i < bits.length; i++)
      '$i ${bits[i].package}:${bits[i].type}',
  ];
}

/// The bits [projectDir] would be given, numbered from [scan].
///
/// # The rule
///
/// `ComponentTypeRegistry.installGenerated`'s, restated over a scan instead of
/// over a set of loaded tables: the packages are sorted by name and their
/// types numbered contiguously from zero in that order, each package's own
/// order being the one `scanComponentBits` fixed. Its own half of that is
/// pinned by `good`'s `component_bits_test.dart`; what is pinned here is the
/// answer for a whole project, which is a fact about the project's
/// dependencies as much as about any package's table.
///
/// # Which packages the project is numbered from
///
/// The ones it depends on, transitively, through `dependencies:` - the test
/// `EngineDependencies` already answers, asked with the destination left open.
/// A game names its own tables to `Game.componentBits` and each table brings
/// its dependencies' tables with it, so the reachable set is the dependency
/// closure and nothing else. A package with no components has no table and is
/// left out here for the same reason `componentBitsFiles` writes it no file.
///
/// Read from pubspecs, not from `.dart_tool/package_config.json`: this answers
/// about a checkout, and a checkout that has not been resolved is one where
/// every question about a dependency would otherwise be answered `no`.
///
/// [packages] are the engine packages the scan read. [projectDir] does not
/// have to be one of them, and in this repository it is not: a game is
/// `publish_to: none`, so nothing generates into it.
ProjectBitOrder projectBitOrder({
  required Directory projectDir,
  required List<EnginePackage> packages,
  required ComponentBitScan scan,
}) {
  final facts = readPubspecFacts(File(p.join(projectDir.path, 'pubspec.yaml')));
  final name = facts?.name;
  if (facts == null || name == null) {
    throw ArgumentError(
      'No package name in ${p.join(projectDir.path, 'pubspec.yaml')}. A '
      'project is numbered from what it depends on, and a pubspec that names '
      'nothing declares nothing to depend on it.',
    );
  }
  final dependencies = EngineDependencies(
    known: <String, PubspecFacts>{name: facts},
    roots: <String, Directory>{
      for (final package in packages) package.name: package.root,
    },
  );
  final numbered =
      <String>[
        for (final package in packages)
          if (scan.byPackage.containsKey(package.name) &&
              dependencies.dependsOn(name, package.name))
            package.name,
      ]..sort();
  return ProjectBitOrder(
    project: name,
    packages: numbered,
    bits: <ComponentBit>[
      for (final package in numbered) ...scan.byPackage[package]!,
    ],
  );
}
