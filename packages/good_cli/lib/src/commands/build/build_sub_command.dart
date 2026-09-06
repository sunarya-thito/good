import 'dart:io';

import 'package:good_cli/src/assets/options.dart';
import 'package:good_cli/src/assets/pipeline.dart';
import 'package:good_cli/src/command.dart';
import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/parsers.dart';
import 'package:good_cli/src/verbosable.dart';

/// What every platform build shares.
///
/// The per-platform commands differ only in which `flutter build` target they
/// invoke, so everything else - asset mode, encryption, output - is declared
/// once here. A platform that needs an extra option adds it in its own
/// `describeCommand` and calls `super`.
///
/// Not a command itself: it declares no subcommand name and is never selected.
abstract class BuildSubCommand extends Command
    with Verbose, Resolving, Bundling {
  late final Arg<Directory> projectDir;
  late final Arg<bool> dryRun;
  late final Arg<bool> noGenerate;

  /// The `flutter build <target>` this platform runs.
  String get flutterTarget;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    projectDir = descriptor.describeArg<Directory>(
      name: 'project-dir',
      description: 'The project to build.',
      parser: parseDirectory,
      defaultValue: Directory('.'),
    );
    dryRun = descriptor.describeFlag(
      name: 'dry-run',
      description: 'Report the plan, and do nothing.',
    );
    noGenerate = descriptor.describeFlag(
      name: 'no-generate',
      description:
          'Build what is on disk. `good generate` is not run first, so the '
          'bindings and the chunks are whatever the last run left.',
    );
  }

  @override
  Future<void> execute() async {
    final project = projectDir.value;
    info
      ..printf('good build %s\n', [flutterTarget])
      ..printf('  project:     %s\n', [project.path])
      ..printf('  assets:      %s\n', [assetMode.value.name])
      ..printf('  encryption:  %s\n', [assetEncryption.value.name])
      ..printf('  compression: %s\n', [assetCompression.value.name]);

    if (assetMode.value == AssetMode.development &&
        assetEncryption.value != AssetEncryption.none) {
      // Said rather than silently resolved: a development build loads loose
      // files, so an encryption setting has nothing to act on and expecting it
      // to would be a real misunderstanding to leave in place.
      info.println(
        '  note: --assets=development loads loose files, so '
        '--asset-encryption has no effect.',
      );
    }

    // `flutter build` bundles whatever is on disk by the time it runs, so it
    // goes after everything that writes. The stages before it are
    // `good generate`'s, in `good generate`'s order, run through the same
    // function it runs - the way `flutter build` runs `flutter pub get`
    // (#238). `--no-generate` is for a tree something else has already
    // generated, which is what a CI job that ran the step itself has.
    final generating = !noGenerate.value;
    final steps = PipelineSteps(
      1 +
          (generating
              ? pipelineStepCount(normalize: normalizeAssets, pack: packAssets)
              : 0),
    );

    if (dryRun.value) {
      info
        ..println('')
        ..println('Would run, in order:');
      if (generating) {
        if (normalizeAssets) {
          info.printf('  %s\n', [steps.next('normalize the source art')]);
        }
        info.printf('  %s\n', [steps.next('generate the bindings')]);
        if (packAssets) {
          info.printf('  %s\n', [
            steps.next('pack --assets=${assetMode.value.name}'),
          ]);
        }
      }
      info.printf('  %s\n', [steps.next('flutter build $flutterTarget')]);
      return;
    }

    info.println('');
    if (generating) {
      await runAssetPipeline(
        projectDir: project,
        command: '${session.path.first} generate',
        out: info,
        err: err,
        verbose: debug,
        steps: steps,
        mode: assetMode.value,
        encryption: assetEncryption.value,
        compression: assetCompression.value,
        normalizeAssets: normalizeAssets,
        packAssets: packAssets,
        force: force.value,
        allowDownload: !noDownload.value,
        pubGet: pubGet,
      );
    } else {
      info.println(
        '--no-generate: building the bindings and chunks already on disk.',
      );
    }

    info.println(steps.next('flutter build $flutterTarget'));
    if (!_flutterBuild(project)) throw const CommandFailure();

    info
      ..println('')
      ..printf('Built %s.\n', [flutterTarget]);
  }

  /// Hands off to Flutter.
  ///
  /// Output is inherited, not captured: `flutter build` prints progress
  /// over minutes, and swallowing it to re-print at the end would make the
  /// slowest step of the build look like a hang.
  bool _flutterBuild(Directory project) {
    final result = Process.runSync(
      'flutter',
      <String>['build', flutterTarget],
      workingDirectory: project.path,
      runInShell: true,
    );
    if (result.exitCode == 0) {
      debug.println(result.stdout.toString());
      return true;
    }
    err
      ..println('flutter build $flutterTarget failed:')
      ..println(result.stdout)
      ..println(result.stderr);
    return false;
  }
}
