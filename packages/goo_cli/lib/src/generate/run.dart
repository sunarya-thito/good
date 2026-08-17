import 'dart:io';
import 'dart:math';

import 'package:goo_cli/src/generate/assets.dart';
import 'package:goo_cli/src/generate/templates.dart';
import 'package:goo_cli/src/verbosable.dart';

/// The whole of what `goo generate` does, callable without a command line.
///
/// Extracted so `goo create` can finish a new project by generating into it -
/// see `CreateCommand.execute`. A fresh project whose lib/goo.generated/ does
/// not exist yet is one whose first `flutter run` fails, and telling someone to
/// run a second command is a worse answer than running it.
///
/// Returns how many files were written.
int runGenerate({
  required Directory projectDir,
  required String command,
  required VerboseOutput out,
  required VerboseOutput verbose,
  bool rotateKeys = false,
  bool dryRun = false,
}) {
  final project = projectDir;
  final scan = scanAssets(project);

  verbose.printf('Declared asset entries: %s\n', [
    scan.declaredEntries.isEmpty ? '(none)' : scan.declaredEntries.join(', '),
  ]);

  if (scan.isEmpty) {
    // Not an error: a project can legitimately declare no assets yet, and
    // the enum still has to exist for code importing it to compile. Said out
    // loud, though, because "my texture is missing from the enum" is the
    // likeliest reason someone runs this.
    out.println(
      'No assets declared under `flutter: assets:` in pubspec.yaml. '
      'Generating empty Textures and Audios enums.',
    );
  }
  for (final entry in scan.unsupported.entries) {
    out.printf('Skipped %s - %s\n', [entry.key, entry.value]);
  }

  final outDir = Directory('${project.path}/lib/goo.generated');
  final writes = <String, String>{
    '${outDir.path}/textures.dart': emitTextures(scan, command: command),
    '${outDir.path}/audios.dart': emitAudios(scan, command: command),
    '${outDir.path}/goo.dart': emitReadiness(command: command),
  };

  final keyFile = File('${outDir.path}/asset_key.dart');
  final keysExist = keyFile.existsSync();
  if (!keysExist || rotateKeys) {
    writes[keyFile.path] = emitAssetKeys(
      command: command,
      // Random.secure, not Random(): a predictable seed would make every
      // project built by this tool share its keys, which is worse than
      // having none at all - it would look like protection.
      random: Random.secure(),
    );
    if (keysExist) {
      out.println(
        'Rotating asset keys. Every pack built with the old keys stops '
        'decrypting; run `goo assets pack` again.',
      );
    }
  } else {
    verbose.println(
      'asset_key.dart exists - left alone. Use --rotate-keys to replace it.',
    );
  }

  if (dryRun) {
    for (final path in writes.keys) {
      out.printf('Would write %s\n', [path]);
    }
    return writes.length;
  }

  outDir.createSync(recursive: true);
  for (final entry in writes.entries) {
    File(entry.key).writeAsStringSync(entry.value);
    out.printf('Wrote %s\n', [entry.key]);
  }
  out.printf('%s texture(s), %s audio file(s).\n', [
    scan.textures.length,
    scan.audio.length,
  ]);
  return writes.length;
}
