import 'dart:io';

import 'package:good_cli/src/assets/compact.dart';
import 'package:good_cli/src/assets/ffmpeg.dart';
import 'package:good_cli/src/assets/key_material.dart';
import 'package:good_cli/src/assets/options.dart';
import 'package:good_cli/src/assets/pack.dart';
import 'package:good_cli/src/assets/strip.dart';
import 'package:good_cli/src/config.dart';
import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/generate/scene_scan.dart';
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
abstract class BuildSubCommand extends Command with Verbose {
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

    info.println('');
    info.println('[1/4] compacting assets');
    final compacted = await _compact(project, config);
    if (compacted == null) throw const CommandFailure();

    info.println('[2/4] generating bindings');
    runGenerate(
      projectDir: project,
      command: '${session.path.first} generate',
      out: info,
      verbose: debug,
    );

    info.println('[3/4] packing assets');
    if (!await _pack(project, config, compacted)) throw const CommandFailure();

    info.printf('[4/4] flutter build %s\n', [flutterTarget]);
    if (!_flutterBuild(project)) throw const CommandFailure();

    info
      ..println('')
      ..printf('Built %s.\n', [flutterTarget]);
  }

  /// Runs compaction and reports what it produced, or null if it failed.
  ///
  /// The plan comes back rather than just a success flag because it is the only
  /// record of *which* files in the output directory good generated - and
  /// therefore which ones a release build may delete once they are inside a
  /// chunk. See [_stripLoose].
  ///
  /// An empty plan when the project has no source directory is deliberate and
  /// not an error: a project that keeps its art already-canonical in the output
  /// directory is a legitimate setup, and it also means nothing there is
  /// regenerable, so nothing gets stripped.
  Future<CompactPlan?> _compact(Directory project, GoodConfig config) async {
    final sourceDir = Directory('${project.path}/${config.assetSource}');
    if (!sourceDir.existsSync()) {
      debug.printf('  no %s - nothing to compact\n', [config.assetSource]);
      return const CompactPlan(steps: <CompactStep>[], skipped: {});
    }
    final plan = planCompaction(sourceDir: sourceDir, config: config);
    if (plan.isEmpty) return plan;

    final Ffmpeg ffmpeg;
    try {
      ffmpeg = await FfmpegResolver().resolve(
        allowDownload: !noDownload.value,
        out: info,
        verbose: debug,
      );
    } on FfmpegUnavailable catch (error) {
      err.println(error.message);
      return null;
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
    if (result.failed.isEmpty) return plan;
    // A build stops here. Compaction reporting a failure and carrying on would
    // ship a game missing an asset, and the whole point of the readiness check
    // is that that is not something to discover at run time.
    err.printf('%s asset(s) failed to convert:\n', [result.failed.length]);
    for (final entry in result.failed.entries) {
      err.printf('  %s: %s\n', [entry.key, entry.value]);
    }
    return null;
  }

  Future<bool> _pack(
    Directory project,
    GoodConfig config,
    CompactPlan compacted,
  ) async {
    final scan = scanAssets(project);
    final paths = <String>[
      for (final asset in scan.textures) asset.path,
      for (final asset in scan.audio) asset.path,
    ]..sort();
    final keyFile = File('${project.path}/lib/good.generated/asset_key.dart');

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
        !scan.declaredEntries.contains(config.packOutput)) {
      err.printf(
        'pubspec.yaml does not list %s under `flutter: assets:`, so the '
        'chunks would be built and never bundled. Add it - good creates the '
        'directory itself.\n',
        [config.packOutput],
      );
      return false;
    }

    // Checked before anything is written, for the same reason as the guard
    // above and a heavier one: what it prevents cannot be undone.
    //
    // Packing takes every declared asset, and stripping then removes the loose
    // copy of everything packed. For a compaction output that costs a re-encode
    // and nothing else. For a file someone put in the asset directory by hand
    // there is no source to build it from, so the strip is the last anyone sees
    // of it. The two mistakes are not the same size, so the safe one is the
    // default and the project says when it wants the other.
    if (assetMode.value == AssetMode.release && !config.stripOriginals) {
      final generated = <String>{
        for (final step in compacted.steps)
          '${config.assetOutput}${step.output}',
      };
      final originals = paths.where((p) => !generated.contains(p)).toList()
        ..sort();
      if (originals.isNotEmpty) {
        err.printf(
          '%s packed asset(s) cannot be rebuilt if the build strips them:\n',
          [originals.length],
        );
        for (final path in originals) {
          err.printf('    %s\n', [path]);
        }
        err.printf(
          'Compaction did not produce these, so deleting the loose copy '
          'destroys the only one. Leaving it in place ships a legible copy '
          'beside the encrypted chunk.\n'
          '\n'
          'Choose one:\n'
          '  - move them into %s so compaction owns them, or\n'
          '  - add `strip-originals: true` under `good: assets:` in '
          'pubspec.yaml to accept the deletion.\n',
          [config.assetSource],
        );
        return false;
      }
    }

    Directory(
      '${project.path}/${config.packOutput}',
    ).createSync(recursive: true);

    final usage = scanScenes(project, scan);
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
    if (result.mapping.isNotEmpty) {
      _stripLoose(project, config, compacted, result.mapping.keys);
    }
    return true;
  }

  /// Removes the loose copies of everything that is now inside a chunk.
  ///
  /// [packed] is what the chunks carry, which is not what compaction produced.
  /// A file placed in the asset directory by hand is packed like any other, and
  /// leaving it loose ships it twice with one of the copies legible. See
  /// [stripLoose].
  ///
  /// [compacted] is still read, for one thing: it says which of the removed
  /// files `good assets compact` can build again. Reaching here with any of the
  /// others in [packed] means the project set `strip-originals: true`, so they
  /// are named as they go - an opt-in is a reason to say what it cost, not a
  /// reason to go quiet.
  void _stripLoose(
    Directory project,
    GoodConfig config,
    CompactPlan compacted,
    Iterable<String> packed,
  ) {
    final stripped = <String>[];
    final removed = stripLoose(
      assetDir: Directory('${project.path}/${config.assetOutput}'),
      packed: packed,
      assetRoot: config.assetOutput,
      onStrip: (path) {
        stripped.add(path);
        debug.printf('  stripped %s%s\n', [config.assetOutput, path]);
      },
    );
    if (removed == 0) return;
    info.printf(
      '  stripped %s loose asset(s) now carried in chunks; '
      '`good assets compact` rebuilds them\n',
      [removed],
    );

    final generated = <String>{for (final step in compacted.steps) step.output};
    final originals = stripped.where((p) => !generated.contains(p)).toList()
      ..sort();
    if (originals.isEmpty) return;
    info.printf(
      '  %s of those were not built from %s, so compaction cannot bring them '
      'back. Keep the originals under %s:\n',
      [originals.length, config.assetSource, config.assetSource],
    );
    for (final path in originals) {
      info.printf('    %s%s\n', [config.assetOutput, path]);
    }
  }

  /// Hands off to Flutter.
  ///
  /// Inherited output rather than captured: `flutter build` prints progress
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
