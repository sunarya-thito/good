import 'dart:io';
import 'dart:math';

import 'package:goo_cli/src/command.dart';
import 'package:goo_cli/src/generate/assets.dart';
import 'package:goo_cli/src/generate/templates.dart';
import 'package:goo_cli/src/parsers.dart';
import 'package:goo_cli/src/verbosable.dart';

/// `goo generate` - writes `lib/goo.generated/`.
///
/// Three files, and they are regenerated on very different schedules:
///
///  * `textures.dart` - one enum value per shipped image. Rewritten every run;
///    it is a pure function of the pubspec.
///  * `goo.dart` - the startup readiness check. Rewritten every run.
///  * `asset_key.dart` - the encryption keys. **Written once**, then left
///    alone, because rewriting the keys orphans every asset pack already built
///    with the old ones. [rotateKeys] is the deliberate way to change them.
///
/// The struct-layout half of codegen the README describes - scanning
/// `Component`/`EntityStruct` with `package:analyzer` to hoist goo's runtime
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
    final project = projectDir.value;
    final scan = scanAssets(project);

    debug.printf('Declared asset entries: %s\n', [
      scan.declaredEntries.isEmpty ? '(none)' : scan.declaredEntries.join(', '),
    ]);

    if (scan.isEmpty) {
      // Not an error: a project can legitimately declare no assets yet, and
      // the enum still has to exist for code importing it to compile. Said out
      // loud, though, because "my texture is missing from the enum" is the
      // likeliest reason someone runs this.
      info.println(
        'No image assets declared under `flutter: assets:` in pubspec.yaml. '
        'Generating an empty Textures enum.',
      );
    }
    for (final entry in scan.unsupported.entries) {
      info.printf('Skipped %s - %s\n', [entry.key, entry.value]);
    }

    final outDir = Directory('${project.path}/lib/goo.generated');
    final writes = <String, String>{
      '${outDir.path}/textures.dart': emitTextures(scan, command: _command),
      '${outDir.path}/goo.dart': emitReadiness(command: _command),
    };

    final keyFile = File('${outDir.path}/asset_key.dart');
    final keysExist = keyFile.existsSync();
    if (!keysExist || rotateKeys.value) {
      writes[keyFile.path] = emitAssetKeys(
        command: _command,
        // Random.secure, not Random(): a predictable seed would make every
        // project built by this tool share its keys, which is worse than
        // having none at all - it would look like protection.
        random: Random.secure(),
      );
      if (keysExist) {
        info.println(
          'Rotating asset keys. Every pack built with the old keys stops '
          'decrypting; run `goo assets pack` again.',
        );
      }
    } else {
      debug.println(
        'asset_key.dart exists - left alone. Use --rotate-keys to replace it.',
      );
    }

    if (dryRun.value) {
      for (final path in writes.keys) {
        info.printf('Would write %s\n', [path]);
      }
      return;
    }

    outDir.createSync(recursive: true);
    for (final entry in writes.entries) {
      File(entry.key).writeAsStringSync(entry.value);
      info.printf('Wrote %s\n', [entry.key]);
    }
    info.printf('%s texture(s).\n', [scan.textures.length]);
  }

  String get _command => session.path.join(' ');
}
