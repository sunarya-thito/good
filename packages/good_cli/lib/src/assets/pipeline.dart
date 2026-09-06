import 'dart:io';

import 'package:good_cli/src/assets/compact.dart' as normalize;
import 'package:good_cli/src/assets/ffmpeg.dart';
import 'package:good_cli/src/assets/key_material.dart';
import 'package:good_cli/src/assets/options.dart';
import 'package:good_cli/src/assets/pack.dart' as chunk;
import 'package:good_cli/src/command.dart';
import 'package:good_cli/src/config.dart';
import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/bundle.dart';
import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/generate/scan.dart';
import 'package:good_cli/src/verbosable.dart';
import 'package:meta/meta.dart';

/// The whole of what `good generate` does, in the one order that works.
///
/// ```
/// normalize -> generate -> pack
/// ```
///
/// # The stages are four, and folding the commands must not fold them
///
/// The full order is a project's declared `transformers:` first, then good's
/// own bundling as the implicit last transformer in the chain:
///
/// ```
/// transformers -> normalize -> chunk -> compress -> encrypt
/// ```
///
/// Nothing runs usefully after a chunk (#358, `AssetEntry.transformers`).
/// Running the declared transformers is not implemented yet; when it is, it is
/// a stage in front of `_normalize` here and not a step inside it - which is
/// the distinction this whole issue turns on. Normalisation converts a
/// container; packing chunks, compresses and seals. They are two stages of one
/// pipeline and one command is not one stage.
///
/// # Why it is one command and not three
///
/// Because the order is not optional and nothing said it. Normalisation
/// writes the canonical files; generation reads *those* and emits the enums;
/// packing reads the key material generation wrote and writes its mapping
/// back into the same file. Run by hand in the wrong order they produce a
/// build that succeeds and is quietly stale, and the failure a user actually
/// hit was quieter still: art in `assets_src/`, nothing normalised, and
/// `good generate` reporting `0 texture(s)` and exiting 0 because the only
/// command that would have converted the art was a separate one nothing
/// mentioned.
///
/// # The stages are still individually reachable
///
/// A project with slow art and fast code must not pay for a re-encode on
/// every run. Two things answer that, and neither is a separate command:
///
///  * normalisation is already incremental - `runCompaction` skips any file
///    whose source bytes and settings match the journal and whose output is
///    still on disk, so an unchanged tree costs one hash per source file and
///    starts no encoder;
///  * [normalizeAssets] and [packAssets] turn a stage off outright, which is
///    what `--no-normalize` and `--no-pack` are for.
///
/// Ffmpeg is resolved only once there is a file to convert, so a project
/// whose art is already canonical never downloads it.
Future<PipelineResult> runAssetPipeline({
  required Directory projectDir,
  required String command,
  required VerboseOutput out,
  required VerboseOutput err,
  required VerboseOutput verbose,
  required PipelineSteps steps,
  String? enginePackage,
  AssetMode mode = AssetMode.release,
  AssetEncryption encryption = AssetEncryption.aes,
  AssetCompressionLevel compression = AssetCompressionLevel.normal,
  bool normalizeAssets = true,
  bool packAssets = true,
  bool force = false,
  bool allowDownload = true,
  bool rotateKeys = false,
  bool dryRun = false,
  bool pubGet = true,
}) async {
  final config = GoodConfig.read(projectDir);

  // Which package the bundle is, and whether it is good's, before the first
  // byte. Normalisation re-encodes every source asset into the project, and a
  // run that spends minutes doing that and then refuses has already written to
  // a tree it was about to say it would not touch. The answer is read off the
  // pubspec and the marker, so asking early costs nothing.
  final bundle = resolveBundle(projectDir);

  if (normalizeAssets) {
    out.println(steps.next('normalizing assets'));
    await _normalize(
      projectDir: projectDir,
      config: config,
      out: out,
      err: err,
      verbose: verbose,
      force: force,
      allowDownload: allowDownload,
      dryRun: dryRun,
    );
  } else {
    verbose.println('--no-normalize: source art is not being converted.');
  }

  out.println(steps.next('generating bindings'));
  final generated = await runGenerate(
    projectDir: projectDir,
    command: command,
    out: out,
    verbose: verbose,
    enginePackage: enginePackage,
    rotateKeys: rotateKeys,
    dryRun: dryRun,
    pubGet: pubGet,
  );

  if (packAssets) {
    out.println(steps.next('packing assets'));
    await _pack(
      projectDir: projectDir,
      config: config,
      bundle: bundle,
      mode: mode,
      encryption: encryption,
      compression: compression,
      out: out,
      err: err,
      verbose: verbose,
      dryRun: dryRun,
    );
  } else {
    verbose.println('--no-pack: no chunks are being written.');
  }

  return PipelineResult(bundle: bundle, fileCount: generated.fileCount);
}

/// How many stages [runAssetPipeline] will announce.
///
/// Generation always runs: it is the cheap half and the one that decides what
/// the other two are about.
int pipelineStepCount({required bool normalize, required bool pack}) =>
    1 + (normalize ? 1 : 0) + (pack ? 1 : 0);

/// The `[2/4]` counter a run prints in front of each stage.
///
/// Held by the caller rather than by [runAssetPipeline] because `good build`
/// has a stage of its own after the pipeline's, and two counters that each
/// think they are the whole run print `[1/3]` followed by `[1/1]`.
class PipelineSteps {
  PipelineSteps(this.total);

  /// Every stage this run will announce, the caller's own included.
  final int total;

  int _done = 0;

  /// The label for the next stage, numbered.
  String next(String label) => '[${++_done}/$total] $label';
}

/// What one run of the pipeline produced.
@immutable
class PipelineResult {
  const PipelineResult({required this.bundle, required this.fileCount});

  /// The generated package everything was written into.
  final BundlePackage bundle;

  /// How many files generation wrote.
  final int fileCount;
}

/// Source art in, one canonical format per kind out.
///
/// # Why this is a stage at all
///
/// A real project's art arrives as whatever each tool exported: jpg beside
/// png beside webp, wav beside mp3 beside ogg. Every one of those is a decoder
/// the runtime has to be right about, on every platform, forever. Converting
/// once at build time collapses that to one format per kind, and the choice
/// becomes a build decision instead of something each file carries.
///
/// # Why development reads the output too
///
/// The output directory is what both asset lists name, so `flutter run` and a
/// shipped build load byte-identical files. The alternative - development
/// loads the source art, release loads the converted art - means every format
/// bug appears for the first time in a release build, which is the worst place
/// to find one.
Future<void> _normalize({
  required Directory projectDir,
  required GoodConfig config,
  required VerboseOutput out,
  required VerboseOutput err,
  required VerboseOutput verbose,
  required bool force,
  required bool allowDownload,
  required bool dryRun,
}) async {
  final sourceDir = Directory('${projectDir.path}/${config.assetSource}');
  final outputDir = Directory('${projectDir.path}/${config.assetOutput}');
  verbose
    ..printf('source:  %s\n', [sourceDir.path])
    ..printf('output:  %s\n', [outputDir.path])
    ..printf('texture: %s q%s\n', [
      config.texture.format.name,
      config.texture.quality,
    ])
    ..printf('audio:   %s q%s\n', [
      config.audio.format.name,
      config.audio.quality,
    ]);

  if (!sourceDir.existsSync()) {
    // Not a failure. Keeping art that is already canonical in the output
    // directory is a legitimate setup, and generation carries on to bind
    // whatever is there.
    _sayThereIsNothingToConvert(
      projectDir: projectDir,
      config: config,
      sourceDir: sourceDir,
      out: out,
      verbose: verbose,
      reason: 'there is no %s',
    );
    return;
  }

  final plan = normalize.planCompaction(sourceDir: sourceDir, config: config);
  for (final entry in plan.skipped.entries) {
    out.printf('Skipped %s - %s\n', [entry.key, entry.value]);
  }
  if (plan.isEmpty) {
    _sayThereIsNothingToConvert(
      projectDir: projectDir,
      config: config,
      sourceDir: sourceDir,
      out: out,
      verbose: verbose,
      reason: '%s holds nothing this can convert',
    );
    return;
  }

  if (dryRun) {
    for (final step in plan.steps) {
      out.printf('  %s\n', [step]);
    }
    out.printf('%s file(s) would be written to %s.\n', [
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
      allowDownload: allowDownload,
      out: out,
      verbose: verbose,
    );
  } on FfmpegUnavailable catch (error) {
    err.println(error.message);
    throw const CommandFailure();
  }

  final result = await normalize.runCompaction(
    plan: plan,
    sourceDir: sourceDir,
    outputDir: outputDir,
    config: config,
    ffmpeg: ffmpeg,
    journal: normalize.compactJournal(projectDir),
    out: out,
    verbose: verbose,
    force: force,
  );
  if (result.failed.isEmpty) return;

  // A run stops here. Converting most of the art and carrying on would bind
  // and ship a game missing an asset, and the whole point of doing this at
  // build time is that that is not something to discover at run time.
  err.printf('%s file(s) could not be converted:\n', [result.failed.length]);
  for (final entry in result.failed.entries) {
    err.printf('  %s: %s\n', [entry.key, entry.value]);
  }
  throw const CommandFailure();
}

/// Says that normalisation converted nothing, loudly only when that is a
/// surprise.
///
/// A project whose canonical art already sits in the output directory
/// converts nothing on every run and does not want a line about it. A project
/// with no art anywhere does: "I put my art in and got `0 texture(s)`" is the
/// report this whole command exists to answer, and the answer is which
/// directory the art goes in.
void _sayThereIsNothingToConvert({
  required Directory projectDir,
  required GoodConfig config,
  required Directory sourceDir,
  required VerboseOutput out,
  required VerboseOutput verbose,
  required String reason,
}) {
  final because = formatMessage(reason, [config.assetSource]);
  if (!scanAssets(projectDir).isEmpty) {
    verbose.printf('nothing to convert - %s\n', [because]);
    return;
  }
  out.printf(
    'Nothing to convert, and no assets under %s either, because %s. Put your '
    'original art in %s - whatever format it is in - and run this again.\n',
    [config.assetOutput, because, sourceDir.path],
  );
}

/// Canonical assets in, shipped chunks out.
///
/// # Two modes that want opposite things
///
/// Development leaves everything alone: loose files, no compression, no
/// encryption, and an empty mapping, so `BundleSource` resolves a logical path
/// straight through `rootBundle`. The shortest path from a changed file to
/// seeing it is not to touch it.
///
/// Release compresses, then encrypts, then chunks. Compress *first*: encrypted
/// bytes are indistinguishable from random and do not compress at all, so the
/// other order costs size and buys nothing.
///
/// # What this does not do
///
/// It writes the chunks and leaves the loose assets where they are. Nothing
/// deletes them afterwards: which files ship is what the two asset lists say,
/// so a plaintext copy in the bundle is a `flutter: assets:` entry to remove
/// and not a file for a build to go and delete.
///
/// # Why per chunk and not per asset
///
/// A per-asset scheme needs an index outside the ciphertext saying where each
/// asset begins and how long it is - and that index is a map of the whole pack
/// in plaintext, which is most of what packing was meant to stop being
/// trivial. Sealing whole chunks puts the index inside the ciphertext; what
/// remains outside is a magic number, a version, flags, a nonce and a tag.
Future<void> _pack({
  required Directory projectDir,
  required GoodConfig config,
  required BundlePackage bundle,
  required AssetMode mode,
  required AssetEncryption encryption,
  required AssetCompressionLevel compression,
  required VerboseOutput out,
  required VerboseOutput err,
  required VerboseOutput verbose,
  required bool dryRun,
}) async {
  final scan = scanAssets(projectDir);
  final paths = <String>[
    for (final asset in scan.textures) asset.path,
    for (final asset in scan.audio) asset.path,
  ]..sort();
  if (paths.isEmpty) {
    verbose.println('  no declared assets - nothing to pack');
    return;
  }

  // Checked before anything is written, because the failure it prevents is
  // the quietest one in the pipeline: chunks build, the mapping points at
  // them, and Flutter bundles none of them, so the game fails at its first
  // asset load with every file present on the build machine.
  if (mode == AssetMode.release &&
      !declaredAssetEntries(projectDir).contains(config.packOutput)) {
    err.printf(
      'pubspec.yaml does not list %s under `flutter: assets:`, so the chunks '
      'would be built and never bundled. Add it - good creates the directory '
      'itself.\n',
      [config.packOutput],
    );
    throw const CommandFailure();
  }

  // Which scene needs what, so a scene load reads its own chunk and at most
  // the shared one. A project this pass cannot read anything out of falls
  // back to directory grouping rather than failing - see `planPack`.
  final usage = await scanScenes(projectDir, scan);
  for (final entry in usage.unresolved.entries) {
    verbose.printf('unresolved: %s -> %s\n', [entry.key, entry.value]);
  }
  if (usage.unresolved.isNotEmpty) {
    out.printf(
      '%s declaration(s) could not be attributed to a scene statically; their '
      'assets go in the shared chunk. Run with --verbose to see them.\n',
      [usage.unresolved.length],
    );
  }

  final plan = chunk.planPack(
    paths,
    assetRoot: config.assetOutput,
    byScene: usage.byScene,
  );
  out
    ..printf('  %s asset(s) in %s chunk(s), %s\n', [
      plan.assetCount,
      plan.chunks.length,
      plan.grouping,
    ])
    ..printf('  mode: %s, encryption: %s, compression: %s\n', [
      mode.name,
      encryption.name,
      compression.name,
    ]);
  for (final each in plan.chunks) {
    verbose.printf('  %s <- %s\n', [each.name, each.members.join(', ')]);
  }
  if (dryRun) return;

  final keyFile = bundle.assetKeyFile;

  // Created even in development mode, where nothing is written into it.
  // `flutter: assets:` has to list this directory for the chunks to ship, and
  // Flutter refuses to build over a listed directory that does not exist - so
  // a project that has declared it but never packed would fail every
  // `flutter run` until its first release build.
  final chunkDir = Directory('${projectDir.path}/${config.packOutput}')
    ..createSync(recursive: true);

  List<int> key = const <int>[];
  if (mode == AssetMode.release && encryption == AssetEncryption.aes) {
    try {
      key = readKeyMaterial(keyFile);
    } on ArgumentError catch (error) {
      err.println('${error.message}');
      throw const CommandFailure();
    }
  }

  final result = await chunk.packAssets(
    plan: plan,
    assetDir: Directory('${projectDir.path}/${config.assetOutput}'),
    outputDir: chunkDir,
    mode: mode,
    encryption: encryption,
    compression: compression,
    key: key,
    assetRoot: config.assetOutput,
    chunkRoot: config.packOutput,
    out: out,
    verbose: verbose,
  );

  // The mapping is rewritten even when it is empty: switching a project back
  // to development mode has to *clear* a stale mapping, or the runtime keeps
  // looking for chunks that are no longer built.
  if (!writeAssetMapping(keyFile, result.mapping)) {
    err.printf(
      'Could not update assetMapping in %s; without it a packed build cannot '
      'find its chunks.\n',
      [keyFile.path],
    );
    throw const CommandFailure();
  }

  if (result.mapping.isEmpty) {
    out.println('  cleared assetMapping - loose assets are the source now.');
    return;
  }
  out
    ..printf('  wrote %s chunk(s) to %s\n', [plan.chunks.length, chunkDir.path])
    ..printf('  %s bytes of assets -> %s bytes packed (%s per cent)\n', [
      result.sourceBytes,
      result.chunkBytes,
      result.sourceBytes == 0
          ? 0
          : (result.chunkBytes * 100 / result.sourceBytes).round(),
    ]);
}

/// The stage flags shared by `good generate` and `good build`.
///
/// One mixin rather than the same six options declared twice: a build runs the
/// pipeline, so every knob the pipeline has is a knob a build has, and two
/// copies drift. `good build` adds `--no-generate`, which is the only one that
/// is genuinely its own - see `BuildSubCommand`.
mixin Bundling on Command {
  late final Arg<AssetMode> assetMode;
  late final Arg<AssetEncryption> assetEncryption;
  late final Arg<AssetCompressionLevel> assetCompression;
  late final Arg<bool> noNormalize;
  late final Arg<bool> noPack;
  late final Arg<bool> force;
  late final Arg<bool> noDownload;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    assetMode = descriptor.describeOption<AssetMode>(
      name: 'assets',
      description: 'Loose files, or a packed release bundle.',
      choices: AssetMode.values,
      // Release is the default: `flutter run` is the development path and
      // comes through none of this, so someone running these commands by hand
      // is making something to ship.
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
      description: 'Compression applied before encryption.',
      choices: AssetCompressionLevel.values,
      defaultValue: AssetCompressionLevel.normal,
    );
    noNormalize = descriptor.describeFlag(
      name: 'no-normalize',
      description:
          'Skip the conversion of source art. What is already in the asset '
          'directory is bound and packed as it stands.',
    );
    noPack = descriptor.describeFlag(
      name: 'no-pack',
      description:
          'Skip chunking, compression and encryption. The chunks already on '
          'disk are left exactly as they are, which makes them stale.',
    );
    force = descriptor.describeFlag(
      name: 'force',
      description: 'Reconvert every source asset, ignoring the journal.',
    );
    noDownload = descriptor.describeFlag(
      name: 'no-download',
      description: 'Fail rather than downloading ffmpeg when none is '
          'installed.',
    );
  }

  /// Whether source art is converted before anything reads it.
  bool get normalizeAssets => !noNormalize.value;

  /// Whether chunks are written after the bindings are.
  bool get packAssets => !noPack.value;
}
