// The two things every generator in this repository addresses: a package it
// would write into, and a file it would write there.
//
// Both live here rather than in `good_tool` because `good generate` writes a
// declaration table into a user's own project (#313), and a project is a
// package built on the engine like any other - the same `lib/src/*.g.dart`
// paths, the same table name derived from the package name. Two models of
// "a package generated code goes into" would be two answers about where a
// file belongs, which is the split this repository already paid for once
// between the five scanners `scan.dart` replaced.
//
// What is *not* here is which directories qualify as one. That is
// `good_tool`'s `enginePackages`, and it is a question about a repository
// checkout rather than about a package.

import 'dart:io';

import 'package:good_cli/src/generate/scan.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// One package generated code can be written into.
@immutable
class EnginePackage {
  const EnginePackage({
    required this.name,
    required this.root,
    required this.dependencies,
  });

  /// The package name, as its pubspec declares it.
  final String name;

  /// Its directory.
  final Directory root;

  /// Every package it declares a dependency on, `dependencies` and
  /// `dev_dependencies` alike.
  ///
  /// Read so a generated file never imports a package the one holding it does
  /// not depend on. `Camera` is a `goo2d` component with a `CameraView?`
  /// column, and `CameraView` is declared in `good` - so that import is only
  /// legal because `goo2d` depends on `good`, and the next such pair might not
  /// be.
  ///
  /// Both kinds, unlike the test for whether a package is built on the engine
  /// at all, because this is a different question: this one asks what an
  /// import anywhere in the package may name, and a test may name a dev
  /// dependency.
  final Set<String> dependencies;

  /// Its `lib/`, normalised and absolute.
  String get libDir => p.normalize(p.absolute(p.join(root.path, 'lib')));

  /// One of its files named as `goo2d/lib/src/data/collider.dart`.
  ///
  /// Relative to the package root and in posix form, so a message reads the
  /// same on every machine and from whichever directory `--dir` was resolved
  /// against.
  String describe(File file) =>
      '$name/${p.split(p.relative(file.path, from: root.path)).join('/')}';

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

  /// Where this package's generated component-bit table goes (#18).
  ///
  /// Beside [accessorFile] and written the same way, for the same reason: it
  /// ships inside the package, so it is committed and read in a diff.
  File get componentBitsFile =>
      File(p.join(libDir, 'src', 'component_bits.g.dart'));

  /// The `export` line [barrel] has to carry for [componentBitsFile] to be
  /// reachable.
  ///
  /// It has to be reachable from *outside* the package as well as inside it:
  /// a game names its table to `Game.componentBits`, and a downstream engine
  /// package's table names this one as a dependency.
  String get componentBitsExport => "export 'src/component_bits.g.dart';";

  /// Where this package's generated declaration collectors go (#353).
  ///
  /// Beside [componentBitsFile] and written the same way. It holds one
  /// function per class the package can instantiate that declares anything,
  /// reading that class's declarations off an instance in the order its field
  /// initialisers would have run - see `collectDeclarations` in `good`.
  File get declarationsFile =>
      File(p.join(libDir, 'src', 'declarations.g.dart'));

  /// The `export` line [barrel] has to carry for [declarationsFile] to be
  /// reachable.
  ///
  /// From outside the package, like the component-bit table and for the same
  /// reason: a game names this table to `Game.declarations`, and a downstream
  /// package's table names it as a dependency.
  String get declarationsExport => "export 'src/declarations.g.dart';";

  /// The directories holding classes this package declares outside its
  /// `lib/` - `test/` and `example/`, whichever exist.
  ///
  /// Read by `--tests` and by nothing else. A fixture is a class like any
  /// other and needs a collector like any other, but the file holding that
  /// collector must not ship: `lib/` is what a published package carries,
  /// and test scaffolding inside it would be part of the API.
  List<Directory> get fixtureRoots => <Directory>[
    for (final name in const <String>['test', 'example'])
      if (Directory(p.join(root.path, name)).existsSync())
        Directory(p.normalize(p.absolute(p.join(root.path, name)))),
  ];

  /// What this package's generated collector table is called -
  /// `goo2dDeclarations`.
  String get declarationsName => declarationsTableName(name);

  /// What this package's generated table is called - `goo2dComponentBits`.
  ///
  /// Derived from the package name, so it is unique across one run by
  /// construction and needs no list to keep in step.
  String get componentBitsName => '${packageIdentifier(name)}ComponentBits';
}

/// What [package]'s generated collector table is called.
///
/// A function as well as [EnginePackage.declarationsName] because two things
/// have to agree on it and only one of them has a package to ask: the
/// generator writes the table, and `good create` writes the
/// `Game.declarations` override that names it. A project whose scaffold named
/// it any other way would not compile, and the compile error would be about a
/// generated file the person did not write.
String declarationsTableName(String package) =>
    '${packageIdentifier(package)}Declarations';

/// A package name as one lower-camel word - `goo2dPhysicsBox2d`.
///
/// Derived from the package name, so every table named off it is unique across
/// one run by construction and needs no list to keep in step.
String packageIdentifier(String package) {
  final words = package.split('_');
  return <String>[
    words.first,
    for (final word in words.skip(1))
      if (word.isNotEmpty) word[0].toUpperCase() + word.substring(1),
  ].join();
}

/// One file the tool would write, and what it would hold.
@immutable
class GeneratedFile {
  const GeneratedFile({required this.file, required this.contents});

  final File file;
  final String contents;

  /// Whether what is on disk already matches [contents].
  ///
  /// Read as bytes and compared as text, so a checkout that normalised line
  /// endings does not read as a stale file. Git is configured to write CRLF in
  /// this repository's working copies, and `--check` comparing raw bytes would
  /// then fail on every file on Windows and pass on Linux.
  bool get isCurrent =>
      file.existsSync() &&
      _normalise(file.readAsStringSync()) == _normalise(contents);

  static String _normalise(String text) => text.replaceAll('\r\n', '\n');
}

/// One walk over the `lib/` of each of [packages].
///
/// Every generator that writes into a set of packages reads them once, here,
/// and answers its own question off the result.
///
/// Every package read, and its own generated output left out of it - a
/// generator that read `accessors.g.dart` back reported each property it would
/// write as colliding with the copy of itself already on disk. Its own output
/// and only its own: an upstream package's committed file is an ordinary
/// hand-written extension, and a name it already declares on the same component
/// is a real collision.
///
/// `Directory.current` is passed only so [readSources] has somewhere to look
/// for a package config it will not use - the roots are named outright.
Future<ScanSources> readPackageSources(List<EnginePackage> packages) =>
    readSources(
  Directory.current,
  rootOverride: <String>[for (final package in packages) package.libDir],
  exclude: <String>{
    for (final package in packages) package.accessorFile.path,
    for (final package in packages) package.componentBitsFile.path,
    for (final package in packages) package.declarationsFile.path,
  },
);
