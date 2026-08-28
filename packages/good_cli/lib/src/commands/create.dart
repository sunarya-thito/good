// good create <project_name> [--2d | --3d]
import 'dart:io';

import 'package:good_cli/src/command.dart';
import 'package:good_cli/src/generate/bundle.dart';
import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/generate/scaffold.dart';
import 'package:good_cli/src/parsers.dart';
import 'package:good_cli/src/verbosable.dart';

/// `good create <name>` - a Flutter app wired up to good.
///
/// Two separable halves: [scaffoldFiles] decides *what files a good project
/// consists of* and is a pure function, and this command runs `flutter
/// create` and writes them. The split is what lets the interesting half be
/// tested without a Flutter SDK on the machine.
class CreateCommand extends Command with Verbose, Resolving {
  late final Arg<String> name;
  late final Arg<Directory> parentDir;
  late final Arg<bool> twoD;
  late final Arg<bool> threeD;
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
    twoD = descriptor.describeFlag(
      name: '2d',
      description: 'Build the project against goo2d. The default.',
    );
    threeD = descriptor.describeFlag(
      name: '3d',
      description:
          'Build the project against goo3d - transforms, hierarchy and the '
          'camera. There is no 3D renderer yet, so the project simulates and '
          'draws nothing; see issue #43.',
    );
    dryRun = descriptor.describeFlag(
      name: 'dry-run',
      description: 'Report what would be created, and create nothing.',
    );
    noFlutterCreate = descriptor.describeFlag(
      name: 'no-flutter-create',
      description:
          'Write only the good files, into a Flutter project that already '
          'exists.',
    );
  }

  @override
  void execute() {
    final projectName = name.value;
    if (projectName.isEmpty) {
      // The consumer carries an empty default so that `good create --help`
      // works; an actual run needs a name.
      err.println('A project name is required: good create <project_name>');
      throw const CommandFailure();
    }
    if (twoD.value && threeD.value) {
      err.println('Pass --2d or --3d, not both.');
      throw const CommandFailure();
    }
    final engine = threeD.value ? GoodEngine.threeD : GoodEngine.twoD;

    final root = Directory('${parentDir.value.path}/$projectName');
    final files = scaffoldFiles(
      projectName: projectName,
      engine: engine,
      command: session.path.join(' '),
    );

    if (dryRun.value) {
      if (!noFlutterCreate.value) {
        info.printf('Would run: flutter create %s\n', [root.path]);
      }
      for (final path in files.keys) {
        info.printf('Would write %s/%s\n', [root.path, path]);
      }
      // Both halves of the pubspec edit, because generating is part of what
      // this command does and a dry run that shows half of it is a dry run
      // somebody has to run twice.
      info.printf('Would add to %s/pubspec.yaml:\n%s\n%s', [
        root.path,
        pubspecPatch(engine.package),
        bundlePubspecPatch(defaultBundleName(projectName)),
      ]);
      info.printf('Would generate %s/ beside it.\n', [
        defaultBundleName(projectName),
      ]);
      return;
    }

    if (!noFlutterCreate.value) {
      if (root.existsSync()) {
        // Refused rather than merged. `flutter create` over an existing tree
        // rewrites platform folders, and doing that to a project someone has
        // been working in is not something to do on their behalf.
        err.printf(
          '%s already exists. Use --no-flutter-create to add the good files to '
          'a project that is already there.\n',
          [root.path],
        );
        throw const CommandFailure();
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
        throw const CommandFailure();
      }
      debug.println(result.stdout.toString());
    } else if (!root.existsSync()) {
      err.printf(
        '%s does not exist, and --no-flutter-create says not to create it.\n',
        [root.path],
      );
      throw const CommandFailure();
    }

    // Whether the tree below is one this command just made.
    //
    // It decides who owns the files already in it. `flutter create` ran
    // seconds ago into a directory this command refused to touch if it
    // existed, so everything there is its output and the scaffold is entitled
    // to replace it - which is the whole of #27: `flutter create` writes a
    // counter app to lib/main.dart, the loop below skipped it as "existing",
    // and the good main.dart was never written. A project reached through
    // --no-flutter-create is somebody's, and nothing there is replaced.
    final ours = !noFlutterCreate.value;

    for (final entry in files.entries) {
      final file = File('${root.path}/${entry.key}');
      final existed = file.existsSync();
      // Never over a file this command did not put there. Scaffolding is a
      // starting point, and silently replacing a main.dart someone has written
      // in is the one unrecoverable thing this command could do.
      if (existed && !ours) {
        info.printf('Kept existing %s\n', [entry.key]);
        continue;
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      info.printf(existed ? 'Replaced %s\n' : 'Wrote %s\n', [entry.key]);
    }

    _patchPubspec(root, engine.package);

    // Generate straight away rather than telling them to. A fresh project's
    // bundle package is otherwise missing, so the pubspec's path dependency
    // points at nothing and `flutter pub get` fails outright - which makes "it
    // does not build" a new project's first experience.
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
      pubGet: pubGet,
    );
    info
      ..printf('Generated %s file(s) in %s/.\n', [
        generated.fileCount,
        generated.bundle.name,
      ])
      ..printf(
        "%s/ is good's, and lib/ is yours. The bindings import as "
        '`package:%s/textures.dart`.\n',
        [generated.bundle.name, generated.bundle.name],
      )
      ..println('');
    if (engine == GoodEngine.threeD) {
      // Said here as well as in the scaffolded code's own comments, because
      // "I ran it and the window is empty" is the first thing that happens
      // and the terminal is where the person is still looking.
      info
        ..println(
          'goo3d has no renderer yet (issue #43), so this project simulates '
          'and draws nothing.',
        )
        ..println(
          'What it does have is real: transforms, the hierarchy, and a camera '
          'entity occupying a declared view.',
        )
        ..println('');
    }
    info
      ..printf('Created %s. Next:\n', [projectName])
      // No `flutter pub get` here any more. Generating the bundle package
      // resolves the project itself, because a path dependency that has never
      // been resolved is the one failure Flutter reports by shipping nothing
      // rather than by stopping.
      ..printf('  cd %s\n', [projectName])
      ..println('  flutter run');
  }

  /// Adds the good dependency and the asset entries to the project's pubspec.
  ///
  /// Applied, and not merely printed. Printing alone leaves a `main.dart`
  /// importing a package the pubspec does not depend on, under a "flutter
  /// run" the user is about to type. A new project's first experience should
  /// not be a compile error.
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
