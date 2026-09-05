import 'dart:io';

import 'package:good_cli/src/command.dart';

import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/parsers.dart';
import 'package:good_cli/src/verbosable.dart';

/// `good generate` - writes the project's generated sibling package.
///
/// The command is a thin wrapper on purpose. Everything it does lives in
/// [runGenerate] and `bundle.dart`, so what the entry point is *called* is a
/// wiring detail: the CLI's command names are being reconsidered, and a rename
/// should cost this file and nothing else.
///
/// Four files, in `<bundle>/lib/`, and they are regenerated on very different
/// schedules:
///
///  * `textures.dart` - one enum value per shipped image. Rewritten every run;
///    it is a pure function of the pubspec.
///  * `good.dart` - the startup readiness check. Rewritten every run.
///  * `asset_key.dart` - the encryption keys. **Written once**, then left
///    alone, because rewriting the keys orphans every asset pack already built
///    with the old ones. [rotateKeys] is the flag that replaces them. A
///    project migrating off `lib/good.generated/` keeps the file it already
///    had, byte for byte.
///
/// It also writes the package itself - its pubspec and its ownership marker -
/// records its name in the project's `good:` section, adds the path
/// dependency, and resolves it. The last of those is [noPubGet]'s to skip.
///
/// The struct-layout half of codegen the README describes - scanning
/// `Component`/`EntityStruct` with `package:analyzer` to hoist good's runtime
/// `DataDescriptor` layout to build time - is not here. That is a separate and
/// much larger piece of Phase 4, and pretending otherwise by emitting a stub
/// would make it look done.
class GenerateCommand extends Command with Verbose, Resolving {
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
  Future<void> execute() async {
    await runGenerate(
      projectDir: projectDir.value,
      command: _command,
      out: info,
      verbose: debug,
      rotateKeys: rotateKeys.value,
      dryRun: dryRun.value,
      pubGet: pubGet,
    );
  }

  String get _command => session.path.join(" ");
}
