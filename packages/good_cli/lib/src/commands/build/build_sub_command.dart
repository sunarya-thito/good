import 'dart:io';

import 'package:good_cli/src/assets/compact.dart';
import 'package:good_cli/src/assets/ffmpeg.dart';
import 'package:good_cli/src/assets/key_material.dart';
import 'package:good_cli/src/assets/options.dart';
import 'package:good_cli/src/assets/pack.dart';
import 'package:good_cli/src/config.dart';
import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/bundle.dart';
import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/generate/scan.dart';
import 'package:good_cli/src/command.dart';
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
abstract class BuildSubCommand extends Command with Verbose, Resolving {
  late final Arg<Directory> projectDir;
  late final Arg<bool> dryRun;
  late final Arg<bool> noDownload;
  late final Arg<AssetMode> assetMode;
  late final Arg<AssetEncryption> assetEncryption;
  late final Arg<AssetCompressionLevel> assetCompression;

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
    noDownload = descriptor.describeFlag(
      name: 'no-download',
      description:
          'Fail rather than downloading ffmpeg when none is installed.',
    );
    assetMode = descriptor.describeOption<AssetMode>(
      name: 'assets',
      description: 'Loose files, or a packed release bundle.',
      choices: AssetMode.values,
      // Release is the default *for a build*: `flutter run` is the development
      // path and does not come through here at all, so someone typing
      // `good build windows` is making something to ship.
      defaultValue: AssetMode.release,
    );
    assetEncryption = descriptor.describeOption<AssetEncryption>(
      name: 'asset-encryption',
      description: 'Encryption for packed assets.',
      choices: AssetEncryption.values,
      // AES by default, not none. Packing without encrypting leaves every
      // file header legible in a hex editor, which is the thing packing is
      // meant to stop being trivial.
      defaultValue: AssetEncryption.aes,
    );
    assetCompression = descriptor.describeOption<AssetCompressionLevel>(
      name: 'asset-compression',
      description: 'Compression for packed assets.',
      choices: AssetCompressionLevel.values,
      defaultValue: AssetCompressionLevel.normal,
    );
  }

  @override
  Future<void> execute() async {
    final project = projectDir.value;
    final config = GoodConfig.read(project);
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

    if (dryRun.value) {
      info
        ..println('')
        ..println('Would run, in order:')
        ..println('  1. good assets compact')
        ..println('  2. good generate')
        ..printf('  3. good assets pack --mode=%s\n', [assetMode.value.name])
        ..printf('  4. flutter build %s\n', [flutterTarget]);
      return;
    }

    // The order is the whole point of this command existing.
    //
    // Compaction writes the canonical files. Generation reads *those* and
    // emits the enums, so it has to follow. Packing reads the generated
    // manifest's key material and writes the mapping back into the same file,
    // so it follows generation. `flutter build` bundles whatever is on disk by
    // then, so it goes last. Running these by hand in the wrong order produces
    // a build that is subtly stale rather than one that fails, which is
    // exactly the mistake worth removing.

    // Which package the bundle is, and whether it is good's, before step 1
    // rather than inside step 2. Compaction re-encodes every source asset and
    // writes the results into the project, and a build that spends minutes
    // doing that and then refuses has already written to a tree it was about
    // to say it would not touch. The answer is read off the pubspec and the
    // marker, so asking early costs nothing.
    final bundle = resolveBundle(project);

    info.println('');
    info.println('[1/4] compacting assets');
    if (!await _compact(project, config)) throw const CommandFailure();

    info.println('[2/4] generating bindings');
    await runGenerate(
      projectDir: project,
      command: '${session.path.first} generate',
      out: info,
      verbose: debug,
      pubGet: pubGet,
    );

    info.println('[3/4] packing assets');
    if (!await _pack(project, config, bundle)) throw const CommandFailure();

    info.printf('[4/4] flutter build %s\n', [flutterTarget]);
    if (!_flutterBuild(project)) throw const CommandFailure();

    info
      ..println('')
      ..printf('Built %s.\n', [flutterTarget]);
  }

  /// Runs compaction, and says whether the build can go on.
  ///
  /// A project with no source directory has nothing to compact and is not an
  /// error: keeping the art already-canonical in the output directory is a
  /// legitimate setup, and the build carries on to pack what is there.
  Future<bool> _compact(Directory project, GoodConfig config) async {
    final sourceDir = Directory('${project.path}/${config.assetSource}');
    if (!sourceDir.existsSync()) {
      debug.printf('  no %s - nothing to compact\n', [config.assetSource]);
      return true;
    }
    final plan = planCompaction(sourceDir: sourceDir, config: config);
    if (plan.isEmpty) return true;

    final Ffmpeg ffmpeg;
    try {
      ffmpeg = await FfmpegResolver().resolve(
        allowDownload: !noDownload.value,
        out: info,
        verbose: debug,
      );
    } on FfmpegUnavailable catch (error) {
      err.println(error.message);
      return false;
    }
    final result = await runCompaction(
      plan: plan,
      sourceDir: sourceDir,
      outputDir: Directory('${project.path}/${config.assetOutput}'),
      config: config,
      ffmpeg: ffmpeg,
      journal: compactJournal(project),
      out: info,
      verbose: debug,
    );
    if (result.failed.isEmpty) return true;
    // A build stops here. Compaction reporting a failure and carrying on would
    // ship a game missing an asset, and the whole point of the readiness check
    // is that that is not something to discover at run time.
    err.printf('%s asset(s) failed to convert:\n', [result.failed.length]);
    for (final entry in result.failed.entries) {
      err.printf('  %s: %s\n', [entry.key, entry.value]);
    }
    return false;
  }

  Future<bool> _pack(
    Directory project,
    GoodConfig config,
    BundlePackage bundle,
  ) async {
    final scan = scanAssets(project);
    final paths = <String>[
      for (final asset in scan.textures) asset.path,
      for (final asset in scan.audio) asset.path,
    ]..sort();
    // The bundle package's, which is where every generated file lives now.
    // Resolved at the top of the command, before compaction wrote anything.
    final keyFile = bundle.assetKeyFile;

    if (paths.isEmpty) {
      debug.println('  no declared assets - nothing to pack');
      return true;
    }

    List<int> key = const <int>[];
    if (assetMode.value == AssetMode.release &&
        assetEncryption.value == AssetEncryption.aes) {
      try {
        key = readKeyMaterial(keyFile);
      } on ArgumentError catch (error) {
        err.println('${error.message}');
        return false;
      }
    }

    // Checked before anything is written, because the failure it prevents is
    // the quietest one in the pipeline: chunks build, the mapping points at
    // them, and Flutter bundles none of them, so the game fails at its first
    // asset load with every file present on the build machine.
    if (assetMode.value == AssetMode.release &&
        !declaredAssetEntries(project).contains(config.packOutput)) {
      err.printf(
        'pubspec.yaml does not list %s under `flutter: assets:`, so the '
        'chunks would be built and never bundled. Add it - good creates the '
        'directory itself.\n',
        [config.packOutput],
      );
      return false;
    }

    Directory(
      '${project.path}/${config.packOutput}',
    ).createSync(recursive: true);

    final usage = await scanScenes(project, scan);
    final plan = planPack(
      paths,
      assetRoot: config.assetOutput,
      byScene: usage.byScene,
    );
    info.printf('  %s asset(s) in %s chunk(s), %s\n', [
      plan.assetCount,
      plan.chunks.length,
      plan.grouping,
    ]);

    final result = await packAssets(
      plan: plan,
      assetDir: Directory('${project.path}/${config.assetOutput}'),
      outputDir: Directory('${project.path}/${config.packOutput}'),
      mode: assetMode.value,
      encryption: assetEncryption.value,
      compression: assetCompression.value,
      key: key,
      assetRoot: config.assetOutput,

      chunkRoot: config.packOutput,
      out: info,
      verbose: debug,
    );

    if (!writeAssetMapping(keyFile, result.mapping)) {
      err.println(
        'Could not update assetMapping in ${keyFile.path}; without it a '
        'packed build cannot find its chunks.',
      );
      return false;
    }
    return true;
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
