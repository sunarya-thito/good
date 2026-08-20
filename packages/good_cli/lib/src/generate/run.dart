import 'dart:io';
import 'dart:math';

import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/templates.dart';
import 'package:good_cli/src/verbosable.dart';

/// The whole of what `good generate` does, callable without a command line.
///
/// Extracted so `good create` can finish a new project by generating into it -
/// see `CreateCommand.execute`. A fresh project whose lib/good.generated/ does
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

  // Before anything is written. An asset Flutter will not bundle produces no
  // enum value, and today the only sign of it is a note printed by a different
  // command; `good generate` said nothing and exited 0, so the first symptom
  // was a missing texture in a shipped game. Failing here costs a pubspec line
  // and catches it at the build that introduced it.
  final unbundled = unbundledAssets(project);
  if (unbundled.isNotEmpty) {
    throw ArgumentError(unbundledAssetsMessage(unbundled));
  }

  verbose.printf('Declared asset entries: %s\n', [
    scan.declaredEntries.isEmpty ? '(none)' : scan.declaredEntries.join(', '),
  ]);

  if (scan.isEmpty) {
    // Not an error: a project can legitimately declare no assets yet, and
    // the enum still has to exist for code importing it to compile. Said out
    // loud, though, because "my texture is missing from the enum" is the
    // likeliest reason someone runs this.
    //
    // The two cases are separated because the fix differs and the wrong one
    // sends people to edit a pubspec that is already right - a fresh project
    // has the entries and no files yet, which is not a mistake.
    out.println(
      scan.declaredEntries.isEmpty
          ? 'No assets declared under `flutter: assets:` in pubspec.yaml. '
                'Generating empty Textures and Audios enums.'
          : 'No assets found in the declared directories. Generating empty '
                'Textures and Audios enums.',
    );
  }
  for (final entry in scan.unsupported.entries) {
    out.printf('Skipped %s - %s\n', [entry.key, entry.value]);
  }

  final package = enginePackageOf(project);
  verbose.printf('Engine package: %s\n', [package]);

  final outDir = Directory('${project.path}/lib/good.generated');
  final writes = <String, String>{
    '${outDir.path}/textures.dart': emitTextures(
      scan,
      command: command,
      package: package,
    ),
    '${outDir.path}/audios.dart': emitAudios(
      scan,
      command: command,
      package: package,
    ),
    '${outDir.path}/good.dart': emitReadiness(
      command: command,
      package: package,
    ),
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
        'decrypting; run `good assets pack` again.',
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
