import 'dart:io';

import 'package:good_tool/src/accessor_emit.dart';
import 'package:good_tool/src/accessor_scan.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:path/path.dart' as p;

/// This repository's own code generator.
///
/// ```console
/// $ cd packages/good_tool
/// $ dart run good_tool            # write
/// $ dart run good_tool --check    # fail if what is committed is stale
/// $ dart run good_tool --verbose  # say what got no property, and why
/// ```
///
/// From this package's own directory, because `dart run <package>` resolves
/// packages from the working directory and the repository root has no pubspec.
/// The root itself is then found by walking up, so the paths it prints and the
/// files it writes do not depend on where it was started.
///
/// # Why the output is committed
///
/// #300 left this open. It is committed, and the reason is that the generated
/// code **ships**: `entity<Transform2D>().offsetX` has to work for somebody who
/// installed `goo2d` from pub.dev and has never heard of this tool. A published
/// package carries what is in its `lib/`, so a build-time step would have to run
/// during `dart pub publish`, and nothing makes it.
///
/// Two things follow, and both are the point rather than a cost. A change to
/// the generator shows its effect in the same diff as the change - the
/// twenty-nine properties this writes today are reviewable, and a rename that
/// moved all of them would be visible. And a fresh clone needs no tool run
/// before it can analyze.
///
/// The thing that goes wrong with a committed generated file is that it goes
/// stale, which is what [_check] is for and what CI runs.
Future<void> main(List<String> arguments) async {
  final check = arguments.contains('--check');
  final verbose = arguments.contains('--verbose') || arguments.contains('-v');
  final unknown = arguments.where(
    (argument) =>
        argument != '--check' && argument != '--verbose' && argument != '-v',
  );
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown argument(s): ${unknown.join(', ')}');
    stderr.writeln('Usage: dart run good_tool [--check] [--verbose]');
    exitCode = 64;
    return;
  }

  final root = _repoRoot();
  if (root == null) {
    stderr.writeln(
      'Run this from inside the repository - it looks for mkdocs.yml beside a '
      'packages/ directory. `cd packages/good_tool && dart run good_tool`.',
    );
    exitCode = 65;
    return;
  }

  final packages = enginePackages(root);
  final scan = scanAccessors(root, packages: packages);

  if (verbose) {
    final skipped = scan.skipped.keys.toList()..sort();
    for (final key in skipped) {
      stdout.writeln('No accessor property: $key - ${scan.skipped[key]}');
    }
  }

  // Before anything is written, and it is the only thing here that refuses. A
  // column whose property name is already a member of Accessor, Entity or int
  // generates a property that compiles and is never reached, because an
  // extension member loses to one the receiver's own type has. Every read of it
  // would answer about the entity handle instead of the column, with nothing
  // said anywhere - and this file is committed and shipped, so nothing
  // downstream would ever say it either.
  if (scan.collisions.isNotEmpty) {
    stderr.writeln(accessorCollisionMessage(scan));
    exitCode = 65;
    return;
  }

  final files = accessorFiles(scan, packages);
  final absent = missingExports(files, packages);

  if (check) {
    _check(root, files, absent);
    return;
  }

  for (final file in files) {
    if (file.isCurrent) {
      stdout.writeln('Unchanged ${_display(root, file.file)}');
      continue;
    }
    file.file.parent.createSync(recursive: true);
    file.file.writeAsStringSync(file.contents);
    stdout.writeln('Wrote ${_display(root, file.file)}');
  }
  for (final package in absent) {
    stdout.writeln(
      'Add `${package.accessorExport}` to '
      '${_display(root, package.barrel)} - the generated file is not exported, '
      'so nothing outside that package can reach a single property in it.',
    );
  }
  stdout.writeln(
    '${scan.propertyCount} propert(ies) over ${scan.extensions.length} '
    'component(s), in ${files.length} file(s).',
  );
}

/// Fails when a committed file is not what the generator would write now.
///
/// Reports rather than rewrites. A `--check` that wrote the file and then asked
/// git whether anything moved would leave a modified tree behind on failure,
/// and on a developer's machine that is somebody's working copy.
void _check(
  Directory root,
  List<GeneratedFile> files,
  List<EnginePackage> absent,
) {
  final stale = files.where((file) => !file.isCurrent).toList();
  if (stale.isEmpty && absent.isEmpty) {
    stdout.writeln('${files.length} generated file(s) are up to date.');
    return;
  }
  for (final file in stale) {
    stderr.writeln(
      file.file.existsSync()
          ? 'Stale: ${_display(root, file.file)}'
          : 'Missing: ${_display(root, file.file)}',
    );
  }
  for (final package in absent) {
    stderr.writeln(
      'Not exported: ${_display(root, package.barrel)} does not carry '
      '`${package.accessorExport}`',
    );
  }
  stderr.writeln(
    '\nRun `dart run good_tool` from the repository root and commit the '
    'result.',
  );
  exitCode = 65;
}

String _display(Directory root, File file) =>
    p.split(p.relative(file.path, from: root.path)).join('/');

/// The repository root, found by walking up from the working directory.
Directory? _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File(p.join(dir.path, 'mkdocs.yml')).existsSync() &&
        Directory(p.join(dir.path, 'packages')).existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
