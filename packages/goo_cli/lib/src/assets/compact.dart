import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:goo_cli/src/assets/ffmpeg.dart';
import 'package:goo_cli/src/config.dart';
import 'package:goo_cli/src/generate/assets.dart';
import 'package:goo_cli/src/verbosable.dart';
import 'package:meta/meta.dart';

/// One source file and the canonical file it becomes.
@immutable
class CompactStep {
  const CompactStep({
    required this.source,
    required this.output,
    required this.kind,
    required this.copyOnly,
  });

  /// Path relative to the source directory - `ui/button.jpg`.
  final String source;

  /// Path relative to the output directory - `ui/button.webp`.
  final String output;

  final AssetKind kind;

  /// True when the source is already in the canonical format, so this is a
  /// copy rather than a transcode.
  ///
  /// Worth distinguishing: re-encoding a WebP to WebP is lossy generation
  /// loss, and running ffmpeg over a file that is already right is time spent
  /// making the asset slightly worse.
  final bool copyOnly;

  @override
  String toString() => '$source -> $output${copyOnly ? ' (copy)' : ''}';
}

/// What compaction would do to a project.
@immutable
class CompactPlan {
  const CompactPlan({required this.steps, required this.skipped});

  final List<CompactStep> steps;

  /// Files in the source directory that compaction has no rule for, and why.
  final Map<String, String> skipped;

  bool get isEmpty => steps.isEmpty;
}

/// Works out which source files become which canonical files.
///
/// Pure: it reads a directory listing and returns a plan, and runs no ffmpeg.
/// That is what lets "does a .jpg become a .webp" be a test rather than a
/// claim, on a machine with no ffmpeg at all.
///
/// The source tree's shape is preserved - `ui/button.jpg` becomes
/// `ui/button.webp`, not `button.webp` - because the output path is what
/// `goo generate` turns into an identifier, and flattening would create
/// collisions that the source tree deliberately avoided.
CompactPlan planCompaction({
  required Directory sourceDir,
  required GooConfig config,
}) {
  final steps = <CompactStep>[];
  final skipped = <String, String>{};
  if (!sourceDir.existsSync()) {
    return const CompactPlan(
      steps: <CompactStep>[],
      skipped: <String, String>{},
    );
  }

  // Normalised, and the trailing separator stripped, before anything is
  // measured against it. `GooConfig` guarantees its directories end in `/`, so
  // a naive `path.length + 1` eats the first character of every relative path -
  // `dot.png` becomes `ot.png`, silently, and the failure surfaces much later
  // as a missing file. Windows also hands back a mix of separators.
  final base = _slashes(sourceDir.path).replaceAll(RegExp(r'/+$'), '');
  final entries = sourceDir.listSync(recursive: true).whereType<File>().toList()
    // Sorted so a plan is stable, and so a report of it reads the same twice.
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in entries) {
    final relative = _slashes(file.path).substring(base.length + 1);
    final kind = AssetKind.of(relative);
    final String extension;
    switch (kind) {
      case AssetKind.texture:
        extension = config.texture.format.extension;
      case AssetKind.audio:
        extension = config.audio.format.extension;
      case AssetKind.other:
        skipped[relative] =
            'not a recognised texture or audio extension - copy it into '
            '${config.assetOutput} yourself if it ships';
        continue;
    }
    final dot = relative.lastIndexOf('.');
    final stem = dot > relative.lastIndexOf('/')
        ? relative.substring(0, dot)
        : relative;
    steps.add(
      CompactStep(
        source: relative,
        output: '$stem$extension',
        kind: kind,
        copyOnly: relative.toLowerCase().endsWith(extension),
      ),
    );
  }
  return CompactPlan(steps: steps, skipped: skipped);
}

/// What a previous compaction produced, so an unchanged file is not
/// re-encoded.
///
/// Keyed by source path, holding a hash of the *source bytes* plus the
/// settings that produced the output. A hash rather than a timestamp because
/// checking out a branch rewrites mtimes wholesale, and re-encoding an
/// untouched library because git touched it is exactly the cost this avoids.
class CompactManifest {
  CompactManifest(this.entries);

  CompactManifest.empty() : entries = <String, String>{};

  final Map<String, String> entries;

  static const String fileName = '.goo_compact.json';

  factory CompactManifest.read(File file) {
    if (!file.existsSync()) return CompactManifest.empty();
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return CompactManifest.empty();
      return CompactManifest(<String, String>{
        for (final entry in decoded.entries) '${entry.key}': '${entry.value}',
      });
    } on FormatException {
      // A corrupt manifest means "recompact everything", not a failure: the
      // outputs can always be rebuilt from the sources, so the safe reading of
      // a file we cannot understand is that nothing is up to date.
      return CompactManifest.empty();
    }
  }

  void write(File file) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(entries));
  }

  /// The fingerprint of a source file under a given set of settings.
  ///
  /// The settings are in it deliberately: changing the WebP quality has to
  /// invalidate every texture even though not one source byte moved.
  static String fingerprint(File source, String settings) {
    final digest = sha256.convert(source.readAsBytesSync());
    return '$digest:$settings';
  }
}

/// The result of running compaction.
@immutable
class CompactResult {
  const CompactResult({
    required this.written,
    required this.upToDate,
    required this.failed,
  });

  final int written;
  final int upToDate;
  final Map<String, String> failed;
}

/// Runs [plan], transcoding through [ffmpeg].
///
/// Skips any step whose source fingerprint matches the manifest *and* whose
/// output still exists - both, because deleting the output directory has to be
/// enough to force a rebuild.
Future<CompactResult> runCompaction({
  required CompactPlan plan,
  required Directory sourceDir,
  required Directory outputDir,
  required GooConfig config,
  required Ffmpeg ffmpeg,
  required VerboseOutput out,
  required VerboseOutput verbose,
  bool force = false,
}) async {
  final manifestFile = File('${outputDir.path}/${CompactManifest.fileName}');
  final manifest = force
      ? CompactManifest.empty()
      : CompactManifest.read(manifestFile);
  final next = CompactManifest.empty();

  var written = 0;
  var upToDate = 0;
  final failed = <String, String>{};

  for (final step in plan.steps) {
    final source = File('${sourceDir.path}/${step.source}');
    final output = File('${outputDir.path}/${step.output}');
    final settings = _settingsFor(step, config);
    final fingerprint = CompactManifest.fingerprint(source, settings);

    if (!force &&
        manifest.entries[step.source] == fingerprint &&
        output.existsSync()) {
      next.entries[step.source] = fingerprint;
      upToDate++;
      verbose.printf('up to date: %s\n', [step.output]);
      continue;
    }

    output.parent.createSync(recursive: true);
    if (step.copyOnly) {
      // A straight copy, never a re-encode. Running a lossy encoder over a
      // file already in the target format loses quality for nothing.
      source.copySync(output.path);
      verbose.printf('copied: %s\n', [step.output]);
    } else {
      final arguments = ffmpegArguments(
        step: step,
        config: config,
        input: source.path,
        output: output.path,
      );
      final result = Process.runSync(ffmpeg.executable, arguments);
      if (result.exitCode != 0) {
        // Recorded and carried, not thrown: one unconvertible file should not
        // abandon the other two hundred, and the report at the end is more
        // use than a stack trace at the first failure.
        failed[step.source] = _lastLines(result.stderr.toString());
        continue;
      }
      verbose.printf('encoded: %s\n', [step.output]);
    }
    next.entries[step.source] = fingerprint;
    written++;
  }

  next.write(manifestFile);
  out.printf('%s written, %s up to date, %s failed.\n', [
    written,
    upToDate,
    failed.length,
  ]);
  return CompactResult(written: written, upToDate: upToDate, failed: failed);
}

/// The settings string a fingerprint carries, so a settings change
/// invalidates.
String _settingsFor(CompactStep step, GooConfig config) => switch (step.kind) {
  AssetKind.texture =>
    'webp:${config.texture.format.name}:${config.texture.quality}',
  AssetKind.audio =>
    'audio:${config.audio.format.name}:${config.audio.quality}',
  AssetKind.other => 'copy',
};

/// The ffmpeg command line for one step.
///
/// Separated out and public so the arguments can be asserted without running
/// anything - a wrong flag here is silent quality loss, which is the least
/// visible kind of bug this tool can have.
List<String> ffmpegArguments({
  required CompactStep step,
  required GooConfig config,
  required String input,
  required String output,
}) {
  final arguments = <String>[
    // Overwrite without asking: the output directory is generated, and a
    // prompt in a build tool is a hang in CI.
    '-y',
    // Errors only. ffmpeg's banner and progress are noise in a build log, and
    // a genuine failure is carried back in `failed` anyway.
    '-loglevel', 'error',
    '-i', input,
  ];

  switch (step.kind) {
    case AssetKind.texture:
      if (config.texture.format == TextureFormat.webp) {
        arguments.addAll(<String>[
          '-c:v', 'libwebp',
          // Alpha survives. The default would discard it for some inputs,
          // which silently ruins every sprite that has any.
          '-pix_fmt', 'yuva420p',
          '-quality', '${config.texture.quality}',
        ]);
        if (config.texture.quality >= 100) {
          arguments.addAll(<String>['-lossless', '1']);
        }
      }
      // A still image, not a one-frame video.
      arguments.addAll(<String>['-frames:v', '1']);
    case AssetKind.audio:
      if (config.audio.format == AudioFormat.ogg) {
        arguments.addAll(<String>[
          '-c:a',
          'libvorbis',
          '-q:a',
          '${config.audio.quality}',
        ]);
      } else {
        arguments.addAll(<String>['-c:a', 'pcm_s16le']);
      }
      // Drop any cover art: an album-art frame in a sound effect turns the
      // stream copy into a video encode and can fail outright.
      arguments.addAll(<String>['-vn']);
    case AssetKind.other:
      break;
  }

  arguments.add(output);
  return arguments;
}

String _lastLines(String stderr, [int lines = 3]) {
  final all = stderr.trim().split('\n');
  return all.length <= lines
      ? all.join(' | ')
      : all.sublist(all.length - lines).join(' | ');
}

/// Windows hands back a mix of `\` and `/` from `Directory.listSync`. Every
/// path this file compares, joins or stores is normalised through here, so a
/// relative path is the same string whichever separator produced it - and so a
/// manifest written on one platform is readable on another.
String _slashes(String path) => path.replaceAll(r'\', '/');
