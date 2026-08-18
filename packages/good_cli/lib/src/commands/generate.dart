import 'dart:io';

import 'package:good_cli/src/command.dart';

import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/parsers.dart';
import 'package:good_cli/src/verbosable.dart';

/// `good generate` - writes `lib/good.generated/`.
///
/// Three files, and they are regenerated on very different schedules:
///
///  * `textures.dart` - one enum value per shipped image. Rewritten every run;
///    it is a pure function of the pubspec.
///  * `good.dart` - the startup readiness check. Rewritten every run.
///  * `asset_key.dart` - the encryption keys. **Written once**, then left
///    alone, because rewriting the keys orphans every asset pack already built
///    with the old ones. [rotateKeys] is the deliberate way to change them.
///
/// The struct-layout half of codegen the README describes - scanning
/// `Component`/`EntityStruct` with `package:analyzer` to hoist good's runtime
/// `DataDescriptor` layout to build time - is not here. That is a separate and
/// much larger piece of Phase 4, and pretending otherwise by emitting a stub
/// would make it look done.
class GenerateCommand extends Command with Verbose {
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
          'decrypting - repack after using this.',
    );
  }

  @override
  void execute() {
    runGenerate(
      projectDir: projectDir.value,
      command: _command,
      out: info,
      verbose: debug,
      rotateKeys: rotateKeys.value,
      dryRun: dryRun.value,
    );
  }

  String get _command => session.path.join(" ");
}
