import 'dart:io';

import 'package:good_cli/src/assets/pipeline.dart';
import 'package:good_cli/src/command.dart';

import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/parsers.dart';
import 'package:good_cli/src/verbosable.dart';

/// `good generate` - the whole pipeline between the art and a project that
/// builds.
///
/// Three stages, in the one order that works, all of them here:
///
/// ```
/// normalize -> chunk -> compress -> encrypt
/// ```
///
/// with the bindings emitted between the first and the second, because they
/// are a function of the normalised files and packing writes its mapping back
/// into a file generation produced. [runAssetPipeline] holds the order and the
/// reasons; this file is the command line for it.
///
/// # Why it is not three commands
///
/// It was: `good assets compact`, `good generate`, `good assets pack`, with
/// nothing saying they had to be run in that order or at all. What that
/// produced was art in `assets_src/`, a `good generate` that read only the
/// output directory, and this:
///
/// ```
/// No assets found in the declared directories.
/// 0 texture(s), 0 audio file(s).
/// ```
///
/// exiting 0, with the command that would have converted the art sitting in a
/// separate group nothing mentioned. Folding them removes the ordering
/// mistake by removing the ordering. (#238)
///
/// # What generation itself writes
///
/// Four files, in `<bundle>/lib/`, and they are regenerated on very different
/// schedules:
///
///  * `textures.dart` - one enum value per shipped image. Rewritten every run;
///    it is a pure function of the pubspec and the normalised files.
///  * `audios.dart` - the same for audio.
///  * `good.dart` - the startup readiness check. Rewritten every run.
///  * `asset_key.dart` - the encryption keys. **Written once**, then left
///    alone, because rewriting the keys orphans every asset pack already built
///    with the old ones. [rotateKeys] is the flag that replaces them.
///
/// It also writes the package itself - its pubspec and its ownership marker -
/// records its name in the project's `good:` section, adds the path
/// dependency, and resolves it. The last of those is `--no-pub-get`'s to skip.
class GenerateCommand extends Command with Verbose, Resolving, Bundling {
  late final Arg<Directory> projectDir;
  late final Arg<bool> dryRun;
  late final Arg<bool> rotateKeys;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    projectDir = descriptor.describeArg<Directory>(
      name: 'project-dir',
      description: 'The project to generate into.',
      parser: parseDirectory,
      defaultValue: Directory('.'),
    );
    dryRun = descriptor.describeFlag(
      name: 'dry-run',
      description: 'Report what would be written, and write nothing.',
    );
    rotateKeys = descriptor.describeFlag(
      name: 'rotate-keys',
      description:
          'Regenerate asset_key.dart. Every existing asset pack stops '
          'decrypting - generate again after using this.',
    );
  }

  @override
  Future<void> execute() async {
    await runAssetPipeline(
      projectDir: projectDir.value,
      command: _command,
      out: info,
      err: err,
      verbose: debug,
      steps: PipelineSteps(
        pipelineStepCount(normalize: normalizeAssets, pack: packAssets),
      ),
      mode: assetMode.value,
      encryption: assetEncryption.value,
      compression: assetCompression.value,
      normalizeAssets: normalizeAssets,
      packAssets: packAssets,
      force: force.value,
      allowDownload: !noDownload.value,
      rotateKeys: rotateKeys.value,
      dryRun: dryRun.value,
      pubGet: pubGet,
    );
  }

  String get _command => session.path.join(" ");
}
