// create flutter + goo(2d/3d)
// goo create <project_name> --2d or --3d (future)
import 'dart:io';

import 'package:goo_cli/src/command.dart';
import 'package:goo_cli/src/generate/run.dart';
import 'package:goo_cli/src/generate/scaffold.dart';
import 'package:goo_cli/src/parsers.dart';
import 'package:goo_cli/src/verbosable.dart';

/// Which engine package a new project is built against.
enum GooDimension {
  d2('goo2d'),

  /// Declared and refused. `goo3d` does not exist, and an option that silently
  /// accepts a value it cannot honour is worse than one that says no - the
  /// project would scaffold and then fail to resolve its dependencies.
  d3('goo3d');

  const GooDimension(this.package);

  final String package;
}

/// `goo create <name>` - a Flutter app wired up to goo.
///
/// Two halves, deliberately separable: [scaffoldFiles] decides *what files a
/// goo project consists of* and is a pure function, and this command runs
/// `flutter create` and writes them. The split is what lets the interesting
/// half be tested without a Flutter SDK on the machine.
class CreateCommand extends Command with Verbose {
  late final Arg<String> name;
  late final Arg<Directory> parentDir;
  late final Arg<GooDimension> dimension;
  late final Arg<bool> dryRun;
  late final Arg<bool> noFlutterCreate;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    name = descriptor.describeConsumer<String>(
      name: 'project_name',
      description: 'The package (and directory) name for the new project.',
      parser: parsePackageName,
      defaultValue: '',
    );
    parentDir = descriptor.describeArg<Directory>(
      name: 'directory',
      description: 'Where to create the project.',
      parser: parseDirectory,
      defaultValue: Directory('.'),
    );
    dimension = descriptor.describeOption<GooDimension>(
      name: 'dimension',
      description: 'Which engine package to depend on.',
      choices: GooDimension.values,
      defaultValue: GooDimension.d2,
    );
    dryRun = descriptor.describeFlag(
      name: 'dry-run',
      description: 'Report what would be created, and create nothing.',
    );
    noFlutterCreate = descriptor.describeFlag(
      name: 'no-flutter-create',
      description:
          'Write only the goo files, into a Flutter project that already '
          'exists.',
    );
  }

  @override
  void execute() {
    final projectName = name.value;
    if (projectName.isEmpty) {
      // The consumer carries an empty default so that `goo create --help`
      // works; an actual run needs a name.
      err.println('A project name is required: goo create <project_name>');
      return;
    }
    if (dimension.value == GooDimension.d3) {
      err.println(
        'goo3d does not exist yet. Only --dimension=d2 can be created today.',
      );
      return;
    }

    final root = Directory('${parentDir.value.path}/$projectName');
    final files = scaffoldFiles(
      projectName: projectName,
      package: dimension.value.package,
      command: session.path.join(' '),
    );

    if (dryRun.value) {
      if (!noFlutterCreate.value) {
        info.printf('Would run: flutter create %s\n', [root.path]);
      }
      for (final path in files.keys) {
        info.printf('Would write %s/%s\n', [root.path, path]);
      }
      info.printf('Would add to %s/pubspec.yaml:\n%s', [
        root.path,
        pubspecPatch(dimension.value.package),
      ]);
      return;
    }

    if (!noFlutterCreate.value) {
      if (root.existsSync()) {
        // Refused rather than merged. `flutter create` over an existing tree
        // rewrites platform folders, and doing that to a project someone has
        // been working in is not something to do on their behalf.
        err.printf(
          '%s already exists. Use --no-flutter-create to add the goo files to '
          'a project that is already there.\n',
          [root.path],
        );
        return;
      }
      info.printf('Running flutter create %s\n', [root.path]);
      final result = Process.runSync('flutter', <String>[
        'create',
        '--project-name',
        projectName,
        root.path,
      ], runInShell: true);
      if (result.exitCode != 0) {
        err
          ..println('flutter create failed:')
          ..println(result.stderr);
        return;
      }
      debug.println(result.stdout.toString());
    } else if (!root.existsSync()) {
      err.printf(
        '%s does not exist, and --no-flutter-create says not to create it.\n',
        [root.path],
      );
      return;
    }

    for (final entry in files.entries) {
      final file = File('${root.path}/${entry.key}');
      // Never over an existing file. Scaffolding is a starting point, and
      // silently replacing a main.dart someone has written in is the one
      // unrecoverable thing this command could do.
      if (file.existsSync()) {
        info.printf('Kept existing %s\n', [entry.key]);
        continue;
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      info.printf('Wrote %s\n', [entry.key]);
    }

    _patchPubspec(root, dimension.value.package);

    // Generate straight away rather than telling them to. A fresh project's
    // lib/goo.generated/ is otherwise missing, so `main.dart` does not compile
    // until a second command has been run - which makes "it does not build" a
    // new project's first experience.
    //
    // Driven directly rather than by re-entering the runner: `generate` is a
    // command, but it is also just this work, and spawning a second parse of a
    // synthetic command line to reach it would be indirection for its own
    // sake.
    info.println('');
    final generated = runGenerate(
      projectDir: root,
      command: '${session.path.first} generate',
      out: info,
      verbose: debug,
    );
    info
      ..printf('Generated %s file(s) in lib/goo.generated/.\n', [generated])
      ..println('')
      ..printf('Created %s. Next:\n', [projectName])
      ..printf('  cd %s\n', [projectName])
      ..println('  flutter pub get')
      ..println('  flutter run');
  }

  /// Adds the goo dependency and the asset entries to the project's pubspec.
  ///
  /// Applied rather than only printed, because the alternative is what this
  /// command used to do: scaffold a `main.dart` importing a package the
  /// pubspec does not depend on, then print "flutter run" underneath it. A new
  /// project's first experience should not be a compile error.
  ///
  /// A pubspec whose shape the patcher does not recognise - anything but the
  /// one `flutter create` just wrote, which is the `--no-flutter-create` case -
  /// is left alone and the lines are printed instead.
  void _patchPubspec(Directory root, String package) {
    final pubspec = File('${root.path}/pubspec.yaml');
    final patched = pubspec.existsSync()
        ? patchedPubspecLines(pubspec.readAsLinesSync(), package)
        : null;
    if (patched == null) {
      info
        ..println('')
        ..printf('Add this to %s by hand:\n', [pubspec.path])
        ..println(pubspecPatch(package));
      return;
    }
    pubspec.writeAsStringSync('${patched.join('\n')}\n');
    info.println('Patched pubspec.yaml');
  }
}
