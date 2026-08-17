import 'dart:io';

import 'package:goo_cli/src/assets/key_material.dart';
import 'package:goo_cli/src/assets/options.dart';
import 'package:goo_cli/src/assets/pack.dart' as impl;
import 'package:goo_cli/src/command.dart';
import 'package:goo_cli/src/config.dart';
import 'package:goo_cli/src/generate/assets.dart';
import 'package:goo_cli/src/parsers.dart';
import 'package:goo_cli/src/verbosable.dart';

/// `goo assets pack` - loose canonical assets in, shipped chunks out.
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
/// # Why per chunk and not per asset
///
/// A per-asset scheme needs an index outside the ciphertext saying where each
/// asset begins and how long it is - and that index is a map of the whole pack
/// in plaintext, which is most of what packing was meant to stop being
/// trivial. Sealing whole chunks puts the index inside the ciphertext; what
/// remains outside is a magic number, a version, flags, a nonce and a tag.
class PackCommand extends Command with Verbose {
  late final Arg<Directory> projectDir;
  late final Arg<Directory> outputDir;
  late final Arg<bool> dryRun;
  late final Arg<AssetMode> mode;
  late final Arg<AssetEncryption> encryption;
  late final Arg<AssetCompressionLevel> compression;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    projectDir = descriptor.describeArg<Directory>(
      name: 'project-dir',
      description: 'The project whose assets to pack.',
      parser: parseDirectory,
      defaultValue: Directory('.'),
    );
    outputDir = descriptor.describeArg<Directory>(
      name: 'output-dir',
      description: 'Where the chunks are written.',
      parser: parseOutputDirectory,
      defaultValue: Directory('./build/goo/assets'),
    );
    dryRun = descriptor.describeFlag(
      name: 'dry-run',
      description: 'Report the plan, write nothing.',
    );
    mode = descriptor.describeOption<AssetMode>(
      name: 'mode',
      description: 'Loose files, or a packed release bundle.',
      choices: AssetMode.values,
      defaultValue: AssetMode.release,
    );
    encryption = descriptor.describeOption<AssetEncryption>(
      name: 'encryption',
      description: 'Encryption for packed chunks.',
      choices: AssetEncryption.values,
      defaultValue: AssetEncryption.aes,
    );
    compression = descriptor.describeOption<AssetCompressionLevel>(
      name: 'compression',
      description: 'Compression applied before encryption.',
      choices: AssetCompressionLevel.values,
      defaultValue: AssetCompressionLevel.normal,
    );
  }

  @override
  Future<void> execute() async {
    final project = projectDir.value;
    final config = GooConfig.read(project);
    final scan = scanAssets(project);
    final paths = <String>[
      for (final asset in scan.textures) asset.path,
      for (final asset in scan.audio) asset.path,
    ]..sort();

    if (paths.isEmpty) {
      info.println(
        'No assets declared under `flutter: assets:` - nothing to pack.',
      );
      return;
    }

    final plan = impl.planPack(paths, assetRoot: config.assetOutput);
    info
      ..printf('%s asset(s) in %s chunk(s), %s.\n', [
        plan.assetCount,
        plan.chunks.length,
        plan.grouping,
      ])
      ..printf('  mode: %s, encryption: %s, compression: %s\n', [
        mode.value.name,
        encryption.value.name,
        compression.value.name,
      ]);
    for (final chunk in plan.chunks) {
      debug.printf('  %s <- %s\n', [chunk.name, chunk.members.join(', ')]);
    }

    if (dryRun.value) {
      info.println('Dry run - stopping before any work.');
      return;
    }

    final keyFile = File('${project.path}/lib/goo.generated/asset_key.dart');
    List<int> key = const <int>[];
    if (mode.value == AssetMode.release &&
        encryption.value == AssetEncryption.aes) {
      try {
        key = readKeyMaterial(keyFile);
      } on ArgumentError catch (error) {
        err.println('${error.message}');
        return;
      }
    }

    final result = await impl.packAssets(
      plan: plan,
      assetDir: Directory('${project.path}/${config.assetOutput}'),
      outputDir: outputDir.value,
      mode: mode.value,
      encryption: encryption.value,
      compression: compression.value,
      key: key,
      assetRoot: config.assetOutput,
      out: info,
      verbose: debug,
    );

    // The mapping is rewritten even when it is empty: switching a project back
    // to development mode has to *clear* a stale mapping, or the runtime keeps
    // looking for chunks that are no longer built.
    if (!writeAssetMapping(keyFile, result.mapping)) {
      err.println(
        'Could not update assetMapping in ${keyFile.path}. Run `goo generate` '
        'to recreate it - without the mapping a packed build cannot find its '
        'chunks.',
      );
      return;
    }

    if (result.mapping.isEmpty) {
      info.println('Cleared assetMapping - loose assets are the source now.');
      return;
    }
    info
      ..printf('Wrote %s chunk(s) to %s\n', [
        plan.chunks.length,
        outputDir.value.path,
      ])
      ..printf('  %s bytes of assets -> %s bytes packed (%s per cent)\n', [
        result.sourceBytes,
        result.chunkBytes,
        result.sourceBytes == 0
            ? 0
            : (result.chunkBytes * 100 / result.sourceBytes).round(),
      ]);
  }
}
