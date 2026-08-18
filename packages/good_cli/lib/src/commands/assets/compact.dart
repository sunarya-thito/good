import 'dart:io';

import 'package:good_cli/src/assets/compact.dart' as impl;
import 'package:good_cli/src/assets/ffmpeg.dart';
import 'package:good_cli/src/command.dart';
import 'package:good_cli/src/config.dart';
import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/parsers.dart';
import 'package:good_cli/src/verbosable.dart';

/// `good assets compact` - source art in, canonical assets out.
///
/// # Why this is a step at all
///
/// A real project's art arrives as whatever each tool exported: jpg beside
/// png beside webp, wav beside mp3 beside ogg. Every one of those is a decoder
/// the runtime has to be right about, on every platform, forever. Converting
/// once at build time collapses that to one format per kind, and the choice
/// becomes a build decision instead of something each file carries.
///
/// # Why development uses the output too
///
/// The output directory is what `flutter: assets:` lists, so `flutter run` and
/// a shipped build load byte-identical files. The alternative - development
/// loads the source art, release loads the converted art - means every format
/// bug appears for the first time in a release build, which is the worst place
/// to find one.
class CompactCommand extends Command with Verbose {
  late final Arg<Directory> projectDir;
  late final Arg<bool> dryRun;
  late final Arg<bool> force;
  late final Arg<bool> noDownload;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    projectDir = descriptor.describeArg<Directory>(
      name: 'project-dir',
      description: 'The project whose assets to compact.',
      parser: parseDirectory,
      defaultValue: Directory('.'),
    );
    dryRun = descriptor.describeFlag(
      name: 'dry-run',
      description: 'Report the plan, convert nothing.',
    );
    force = descriptor.describeFlag(
      name: 'force',
      description: 'Reconvert everything, ignoring what is already up to date.',
    );
    noDownload = descriptor.describeFlag(
      name: 'no-download',
      description:
          'Fail rather than downloading ffmpeg when none is installed.',
    );
  }

  @override
  Future<void> execute() async {
    final project = projectDir.value;
    final config = GoodConfig.read(project);
    final sourceDir = Directory('${project.path}/${config.assetSource}');
    final outputDir = Directory('${project.path}/${config.assetOutput}');

    _report(config, sourceDir, outputDir);

    if (!sourceDir.existsSync()) {
      // Not a failure. A project that has not started on art yet is ordinary,
      // and the message is more useful than an empty plan.
      info.printf(
        'No source directory at %s. Put your original art there - whatever '
        'format it is in - and re-run.\n',
        [sourceDir.path],
      );
      return;
    }

    final plan = impl.planCompaction(sourceDir: sourceDir, config: config);
    for (final entry in plan.skipped.entries) {
      info.printf('Skipped %s - %s\n', [entry.key, entry.value]);
    }
    if (plan.isEmpty) {
      info.printf('Nothing to convert in %s.\n', [sourceDir.path]);
      return;
    }

    if (dryRun.value) {
      for (final step in plan.steps) {
        info.printf('  %s\n', [step]);
      }
      info.printf('%s file(s) would be written to %s.\n', [
        plan.steps.length,
        outputDir.path,
      ]);
      return;
    }

    // Resolved *after* the plan and the dry-run exit, so `--dry-run` never
    // downloads anything and a project with no convertible art never needs
    // ffmpeg at all.
    final Ffmpeg ffmpeg;
    try {
      ffmpeg = await FfmpegResolver().resolve(
        allowDownload: !noDownload.value,
        out: info,
        verbose: debug,
      );
    } on FfmpegUnavailable catch (error) {
      err.println(error.message);
      return;
    }

    final result = await impl.runCompaction(
      plan: plan,
      sourceDir: sourceDir,
      outputDir: outputDir,
      config: config,
      ffmpeg: ffmpeg,
      out: info,
      verbose: debug,
      force: force.value,
    );
    _warnAboutUnlistedDirectories(project, config, plan);

    if (result.failed.isEmpty) return;
    err
      ..println('')
      ..printf('%s file(s) could not be converted:\n', [result.failed.length]);
    for (final entry in result.failed.entries) {
      err.printf('  %s: %s\n', [entry.key, entry.value]);
    }
  }

  void _report(GoodConfig config, Directory source, Directory output) {
    debug
      ..printf('source:  %s\n', [source.path])
      ..printf('output:  %s\n', [output.path])
      ..printf('texture: %s q%s\n', [
        config.texture.format.name,
        config.texture.quality,
      ])
      ..printf('audio:   %s q%s\n', [
        config.audio.format.name,
        config.audio.quality,
      ]);
  }

  /// Warns about output subdirectories the pubspec does not bundle.
  ///
  /// Flutter's `assets: - assets/` bundles the files *directly* inside that
  /// directory and nothing deeper, so compaction happily writing
  /// `assets/ui/button.webp` produces a file that ships with nothing and
  /// appears in no generated enum. The symptom is "my texture is missing" with
  /// the file sitting right there on disk, which is exactly the kind of
  /// silence worth breaking.
  void _warnAboutUnlistedDirectories(
    Directory project,
    GoodConfig config,
    impl.CompactPlan plan,
  ) {
    final declared = declaredAssetEntries(project).toSet();
    final needed = <String>{};
    for (final step in plan.steps) {
      final slash = step.output.lastIndexOf('/');
      needed.add(
        slash == -1
            ? config.assetOutput
            : '${config.assetOutput}${step.output.substring(0, slash)}/',
      );
    }
    final missing = needed.where((d) => !declared.contains(d)).toList()..sort();
    if (missing.isEmpty) return;
    info
      ..println('')
      ..println(
        'These directories now hold assets but are not listed under '
        '`flutter: assets:` in pubspec.yaml, so Flutter will not bundle them '
        'and `good generate` will not see them:',
      );
    for (final dir in missing) {
      info.printf('  - %s\n', [dir]);
    }
  }
}
