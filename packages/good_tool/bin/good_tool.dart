import 'dart:io';

// good_cli's `lib/src` is private by convention and this reaches into it, for
// the reason `accessor_scan.dart` states beside its own copy of this line. One
// `readSources` here, shared by both scans, because both ask about the same
// trees and neither has any reason to parse the same packages a second time.
// ignore: implementation_imports
import 'package:good_cli/src/generate/struct_scan.dart';
import 'package:good_tool/src/accessor_emit.dart';
import 'package:good_tool/src/accessor_scan.dart';
import 'package:good_tool/src/component_emit.dart';
import 'package:good_tool/src/component_scan.dart';
import 'package:good_tool/src/declaration_scan.dart';
import 'package:good_tool/src/doc_references.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:good_tool/src/imports.dart';
import 'package:path/path.dart' as p;

/// The code generator for a package built on this engine.
///
/// ```console
/// $ cd packages/good_tool
/// $ dart run good_tool --dir ../../packages            # write
/// $ dart run good_tool --dir ../../packages --check    # fail if stale
/// $ dart run good_tool --dir ../../packages --verbose  # say what got nothing
/// $ dart run good_tool --dir ../../packages --doc-references
/// $ dart run good_tool --dir ../../packages --declarations
/// ```
///
/// `--doc-references` generates nothing. It reads the doc comments in the
/// packages it was pointed at and fails on a `[Reference]` whose name is
/// written nowhere in the packages read. [scanDocReferences] states the rule
/// and what it leaves alone.
///
/// `--declarations` generates nothing either. It fails on a declaration held by
/// a variable Dart initialises lazily - a `late` field, a `static` field, a
/// top-level variable - because the declaration then lands on whichever owner
/// is under construction when the variable is first read rather than on the one
/// that wrote it. [scanDeferredDeclarations] states the rule and the four
/// things it does not decide.
///
/// From a package's own directory, because `dart run <package>` resolves
/// packages from the working directory.
///
/// # Why `--dir` has no default (#305)
///
/// Because the only default that could exist is `packages/`, and that is this
/// repository's layout rather than anybody's. A third-party author writing
/// `good_physics_foo` has their `lib/` at their package root, so the default
/// would find nothing for them - and finding nothing while reporting success is
/// the defect #305 opens with. A default fails quietly for every caller it was
/// not written for; a required argument fails the same way for all of them, at
/// the point where it can say what is missing.
///
/// It may be given more than once, and that is not a convenience. The
/// component-bit table is numbered over every package one run sees, so two runs
/// over halves of a monorepo produce two numberings neither of which is the one
/// the engine would assign. A layout with packages in two places has to be one
/// run.
///
/// # Which of those directories' packages are handled
///
/// The ones that depend on the engine - see [enginePackages]. Not the ones
/// whose name starts with `goo`, which is what `good_cli` used to ask and which
/// reads `google_fonts` as an engine package.
///
/// # Why the output is committed
///
/// #300 left this open. It is committed, and the reason is that the generated
/// code **ships**: `entity<Transform2D>().offsetX` has to work for somebody who
/// installed `goo2d` from pub.dev and has never heard of this tool. A published
/// package carries what is in its `lib/`, so a build-time step would have to run
/// during `dart pub publish`, and nothing makes it. That is the same fact that
/// makes this tool worth pointing at somebody else's package: whatever it
/// generates for them has to be inside their `lib/` to be published with it.
///
/// Two things follow, and both are the point rather than a cost. A change to
/// the generator shows its effect in the same diff as the change - the
/// twenty-nine properties this writes today are reviewable, and a rename that
/// moved all of them would be visible. And a fresh clone needs no tool run
/// before it can analyze.
///
/// The thing that goes wrong with a committed generated file is that it goes
/// stale, which is what [_check] is for and what CI runs.
///
/// # What each refusal exits with
///
/// The two codes `good_cli`'s `runner.dart` already uses, meaning what it says
/// there. There is no third: `EX_NOINPUT` would fit an absent `--dir` by the
/// letter of `sysexits.h`, and a vocabulary of three where the rest of the
/// repository speaks two is a distinction nobody downstream would read.
///
/// **64, `EX_USAGE` - the command line is wrong.** An argument this does not
/// know, a `--dir` with nothing after it, no `--dir` at all, or a `--dir`
/// naming a directory that is not there. Nothing has been read in any of them;
/// what is wrong is what was typed, and the fix is to type something else. All
/// four reprint the usage, which is the point of the code.
///
/// **65, `EX_DATAERR` - the command line was fine and the source is not.** No
/// package under those directories qualifies, two of them are called one thing,
/// a column would shadow a member of `Accessor`, `Entity` or `int`, the
/// component-bit table would not fit a query signature, `--check` found a
/// committed file that is not what would be written now, or
/// `--doc-references` found a doc comment naming something that is written
/// nowhere, or `--declarations` found a declaration held by a lazy variable.
/// None of them reprint the usage: the invocation was right, so answering it
/// with the invocation answers a question nobody asked.
///
/// The seam between the two runs through the pair that look alike. A `--dir`
/// that does not exist is 64 and a `--dir` holding no engine package is 65,
/// because the first was never read and the second was read and rejected.
Future<void> main(List<String> arguments) async {
  final check = arguments.contains('--check');
  final docReferences = arguments.contains('--doc-references');
  final declarations = arguments.contains('--declarations');
  final verbose = arguments.contains('--verbose') || arguments.contains('-v');
  final directories = <String>[];
  final unknown = <String>[];
  var wantsDirectory = false;
  for (final argument in arguments) {
    if (wantsDirectory) {
      directories.add(argument);
      wantsDirectory = false;
      continue;
    }
    if (argument == '--dir') {
      wantsDirectory = true;
      continue;
    }
    if (argument.startsWith('--dir=')) {
      directories.add(argument.substring('--dir='.length));
      continue;
    }
    if (argument == '--check' ||
        argument == '--doc-references' ||
        argument == '--declarations' ||
        argument == '--verbose' ||
        argument == '-v') {
      continue;
    }
    unknown.add(argument);
  }
  if (unknown.isNotEmpty || wantsDirectory || directories.isEmpty) {
    if (unknown.isNotEmpty) {
      stderr.writeln('Unknown argument(s): ${unknown.join(', ')}');
    }
    if (wantsDirectory) stderr.writeln('--dir takes a directory.');
    if (directories.isEmpty && !wantsDirectory) {
      stderr.writeln(
        'Nothing to look in. --dir names a directory holding the packages to '
        'generate into, and may be given more than once.',
      );
    }
    _usage();
    exitCode = 64;
    return;
  }

  // Also usage, and not the data error below it. Nothing here has been read:
  // what is wrong is the value of an argument, and the fix is to edit the
  // command line - which is what separates the two codes, and why this one
  // reprints the usage and `--check`'s stale-file report does not.
  final missing = directories.where(
    (directory) => !Directory(directory).existsSync(),
  );
  if (missing.isNotEmpty) {
    stderr.writeln('No such directory: ${missing.join(', ')}');
    _usage();
    exitCode = 64;
    return;
  }

  final scan = enginePackages(<Directory>[
    for (final directory in directories) Directory(directory),
  ]);
  final packages = scan.packages;

  // The failure #305 is named for. A run that generated nothing used to exit 0
  // saying nothing at all, and the report it read as was "my components produce
  // no accessors" with no thread to pull.
  if (packages.isEmpty) {
    stderr.writeln(_nothingMatched(scan));
    exitCode = 65;
    return;
  }
  final duplicates = scan.duplicates;
  if (duplicates.isNotEmpty) {
    duplicates.forEach((name, roots) {
      stderr.writeln('Two packages are called $name: ${roots.join(', ')}');
    });
    stderr.writeln(
      '\nOne generated component-bit table is written per package name, so a '
      'run holding two of a name would write one table over the other and no '
      'reader of a query signature could tell which numbering it came from.',
    );
    exitCode = 65;
    return;
  }

  if (docReferences) {
    _docReferences(packages, scan.dependencies);
    return;
  }

  if (declarations) {
    _declarations(packages, scan.dependencies);
    return;
  }

  // Every package read, which is the packages being written into plus the
  // engine packages they depend on. In this repository those are the same set;
  // a standalone package's engine dependencies come from a pub cache, and
  // without them `Component` and `Field` are undeclared names and the run
  // produces nothing (#305).
  final readable = <EnginePackage>[...packages, ...scan.dependencies];
  final sources = readSources(
    Directory.current,
    rootOverride: <String>[for (final package in readable) package.libDir],
    // A generator must not read its own output. What this writes is an
    // `extension ... on Accessor<Transform2D>` inside `packages/goo2d/lib/`,
    // which on the next run is an ordinary hand-written extension declaring
    // `offsetX` - so the second run reported every one of its own properties
    // as colliding with itself. The guard was right and the input was wrong.
    //
    // Its own output, and only its own: an upstream package's committed
    // `accessors.g.dart` is input like any other hand-written extension, and a
    // property this run would generate under a name that file already declares
    // on the same component is a real collision.
    exclude: <String>{
      for (final package in packages) package.accessorFile.path,
      for (final package in packages) package.componentBitsFile.path,
    },
  );
  final accessors = scanAccessors(packages: readable, sources: sources);
  final bits = scanComponentBits(packages: readable, sources: sources);

  if (verbose) {
    final skipped = accessors.skipped.keys.toList()..sort();
    for (final key in skipped) {
      stdout.writeln('No accessor property: $key - ${accessors.skipped[key]}');
    }
    final unbitted = bits.skipped.keys.toList()..sort();
    for (final key in unbitted) {
      stdout.writeln('No generated bit: $key - ${bits.skipped[key]}');
    }
  }

  // The second thing that refuses, and the reason #18 wanted the assignment
  // moved here at all. A registry that fills up at run time throws naming
  // whichever type happened to arrive last, which is whichever scene was
  // declared last; this names every type competing for the last bit, before
  // anything is built. It counts the packages alone, so a table that exactly
  // fills the word has already taken every slot a game had.
  if (bits.bits.length > maxComponentTypes) {
    stderr.writeln(componentBitCeilingMessage(bits, maxComponentTypes));
    exitCode = 65;
    return;
  }

  // Before anything is written, and it is the only thing here that refuses. A
  // column whose property name is already a member of Accessor, Entity or int
  // generates a property that compiles and is never reached, because an
  // extension member loses to one the receiver's own type has. Every read of it
  // would answer about the entity handle instead of the column, with nothing
  // said anywhere - and this file is committed and shipped, so nothing
  // downstream would ever say it either.
  if (accessors.collisions.isNotEmpty) {
    stderr.writeln(accessorCollisionMessage(accessors));
    exitCode = 65;
    return;
  }

  final imports = Imports(
    declaredIn: declaredIn(sources),
    byLibDir: <String, EnginePackage>{
      for (final package in readable) package.libDir: package,
    },
    units: sources.units,
    packages: readable,
  );
  // Written into [packages] alone, resolved against everything read: an
  // upstream package generates its own files in its own run.
  final files = <GeneratedFile>[
    ...accessorFiles(accessors, packages),
    ...componentBitsFiles(bits, packages, imports, known: readable),
  ];
  final absent = <EnginePackage, String>{
    for (final package in missingExports(
      accessorFiles(accessors, packages),
      packages,
    ))
      package: package.accessorExport,
    for (final package in missingComponentBitsExports(
      componentBitsFiles(bits, packages, imports, known: readable),
      packages,
    ))
      package: package.componentBitsExport,
  };

  if (check) {
    _check(packages, files, absent, directories);
    return;
  }

  for (final file in files) {
    if (file.isCurrent) {
      stdout.writeln('Unchanged ${_display(packages, file.file)}');
      continue;
    }
    file.file.parent.createSync(recursive: true);
    file.file.writeAsStringSync(file.contents);
    stdout.writeln('Wrote ${_display(packages, file.file)}');
  }
  absent.forEach((package, export) {
    stdout.writeln(
      'Add `$export` to ${_display(packages, package.barrel)} - the generated '
      'file is not exported, so nothing outside that package can reach '
      'anything in it.',
    );
  });
  stdout.writeln(
    '${accessors.propertyCount} propert(ies) over '
    '${accessors.extensions.length} component(s), and ${bits.bits.length} '
    'component bit(s), in ${files.length} file(s) across '
    '${packages.length} package(s).',
  );
}

/// The invocation, on stderr, under whichever message named the problem.
///
/// Written by every 64 and by nothing else - see [main] for why that is the
/// line, and not a matter of how long the message already is.
void _usage() {
  stderr.writeln(
    'Usage: dart run good_tool --dir <directory> [--dir <directory>] '
    '[--check] [--doc-references] [--declarations] [--verbose]',
  );
  stderr.writeln(
    '  --dir .              the package in this directory\n'
    '  --dir packages       every package directly under packages/',
  );
}

/// What a run that matched no package says instead of exiting quietly (#305).
///
/// It names the directories, and every package it did find and turned down
/// with the reason. "There was nothing there" and "there were four things and
/// none of them qualified" send somebody to two different places, and a run
/// that only said neither is the failure this exists to end.
String _nothingMatched(PackageScan scan) {
  final lines = StringBuffer()
    ..writeln(
      'No package to generate into under '
      '${scan.looked.map((where) => '`$where`').join(', ')}. A package is '
      'handled when it has a lib/, is not publish_to: none, and depends on '
      'package:$engineRootPackage - directly or through anything it depends '
      'on.',
    );
  if (scan.rejected.isEmpty) {
    lines
      ..writeln()
      ..writeln(
        'Nothing there holds a pubspec.yaml. --dir takes the package itself '
        '(`--dir .`) or a directory whose immediate children are packages '
        '(`--dir packages`), and looks no deeper than that.',
      );
    return lines.toString();
  }
  lines
    ..writeln()
    ..writeln('What was there:');
  final names = scan.rejected.keys.toList()..sort();
  for (final name in names) {
    lines.writeln('  $name - ${scan.rejected[name]}');
  }
  return lines.toString();
}

/// Fails when a committed file is not what the generator would write now.
///
/// Reports rather than rewrites. A `--check` that wrote the file and then asked
/// git whether anything moved would leave a modified tree behind on failure,
/// and on a developer's machine that is somebody's working copy.
void _check(
  List<EnginePackage> packages,
  List<GeneratedFile> files,
  Map<EnginePackage, String> absent,
  List<String> directories,
) {
  final stale = files.where((file) => !file.isCurrent).toList();
  if (stale.isEmpty && absent.isEmpty) {
    stdout.writeln('${files.length} generated file(s) are up to date.');
    return;
  }
  for (final file in stale) {
    stderr.writeln(
      file.file.existsSync()
          ? 'Stale: ${_display(packages, file.file)}'
          : 'Missing: ${_display(packages, file.file)}',
    );
  }
  absent.forEach((package, export) {
    stderr.writeln(
      'Not exported: ${_display(packages, package.barrel)} does not carry '
      '`$export`',
    );
  });
  final where = <String>[
    for (final directory in directories) '--dir $directory',
  ].join(' ');
  stderr.writeln('\nRun `dart run good_tool $where` and commit the result.');
  exitCode = 65;
}

/// Fails when a doc comment names something that is written nowhere.
///
/// A separate mode and not a step inside [_check], because the two say
/// different things about the same tree and are fixed by different edits. A
/// stale generated file is fixed by running the tool; a dead doc reference is
/// fixed by editing the comment, and a run that reported both under one exit
/// code would tell whoever reads it to regenerate.
///
/// [dependencies] are read and never reported on. A `goo2d_physics_box2d`
/// comment naming a `good` type is a resolved reference, and a scan holding
/// only the package under it would call that name missing.
void _docReferences(
  List<EnginePackage> packages,
  List<EnginePackage> dependencies,
) {
  final scan = scanDocReferences(
    packages: packages,
    known: <EnginePackage>[...packages, ...dependencies],
  );
  if (scan.dangling.isEmpty) {
    stdout.writeln(
      '${scan.checked} of ${scan.references} doc reference(s) in '
      '${scan.files} file(s) name something the packages write.',
    );
    return;
  }
  for (final reference in scan.dangling) {
    stderr.writeln(danglingReferenceLine(reference));
  }
  stderr.writeln(danglingReferenceSummary(scan));
  exitCode = 65;
}

/// A separate mode and not a step inside [_docReferences], for the reason that
/// one is separate from [_check]: the two read different things and are fixed
/// by different edits, and one exit code over both would name the wrong fix.
///
/// [dependencies] are read and never reported on, and here they carry more than
/// they do for doc references. The entry points a call site is matched against
/// are derived from the packages read, and `Field`, `Event` and `Component`
/// live in `good` - a scan holding only the package under it would find no
/// entry points and report a clean run over code full of them.
void _declarations(
  List<EnginePackage> packages,
  List<EnginePackage> dependencies,
) {
  final scan = scanDeferredDeclarations(
    packages: packages,
    known: <EnginePackage>[...packages, ...dependencies],
  );
  _unparsed(scan);
  if (scan.deferred.isEmpty) {
    stdout.writeln(
      '${scan.calls} declaration(s) in ${scan.files} file(s) are eager, '
      'against ${scan.entryPoints} declaring member(s).',
    );
    return;
  }
  for (final deferred in scan.deferred) {
    stderr.writeln(deferredDeclarationLine(deferred));
  }
  stderr.writeln(deferredDeclarationSummary(scan));
  exitCode = 65;
}

/// Names the files the parser could not read, and does not fail on them.
///
/// Not an exit code, because there is nothing the author of the file can do: it
/// is the `analyzer` version this package resolves, not the source. Not silence
/// either - a run that skipped a file and then reported a clean tree would be
/// answering a question it did not ask. See `DeclarationScan.unparsed` for
/// which three files this is today and why.
void _unparsed(DeclarationScan scan) {
  if (scan.unparsed.isEmpty) return;
  for (final file in scan.unparsed) {
    stderr.writeln('$file: not parsed, and so not checked');
  }
  stderr.writeln(
    '${scan.unparsed.length} file(s) were not read. Primary constructors are '
    'the known cause: flutter analyze accepts them and the analyzer this '
    'package resolves does not implement them, so no enable-experiment '
    'spelling parses those files.',
  );
  stderr.writeln();
}

/// A generated file named as `<package>/lib/src/<file>`.
///
/// Relative to the package rather than to the working directory, because the
/// working directory is now whichever one `--dir` was resolved from and a path
/// through `../` says nothing a reader wants. This form is the same on every
/// machine and in every invocation, which is what the printed name is for.
String _display(List<EnginePackage> packages, File file) {
  final full = p.normalize(p.absolute(file.path));
  for (final package in packages) {
    final root = p.normalize(p.absolute(package.root.path));
    if (p.isWithin(root, full)) {
      return p.split(
        p.join(package.name, p.relative(full, from: root)),
      ).join('/');
    }
  }
  return full;
}
