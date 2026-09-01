import 'dart:io';
import 'dart:math';

import 'package:good_cli/src/command.dart';
import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/bundle.dart';
import 'package:good_cli/src/generate/engine_dependency.dart';
import 'package:good_cli/src/generate/struct_scan.dart';
import 'package:good_cli/src/generate/templates.dart';
import 'package:good_cli/src/verbosable.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The `--no-pub-get` that every command generating the bundle package takes.
///
/// One mixin rather than the same flag declared three times: `create`,
/// `generate` and `build` all reach [runGenerate], so all three resolve, and a
/// CI step that resolves for itself wants to say so once in whichever it runs.
///
/// It is a flag and not a default because the resolve is the step that stops
/// the silent failure: a path dependency that was never resolved does not fail
/// the build, it ships without the package.
mixin Resolving on Command {
  late final Arg<bool> noPubGet;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    noPubGet = descriptor.describeFlag(
      name: 'no-pub-get',
      description:
          'Skip `flutter pub get`. The generated package is written but not '
          'resolved, and a build would then ship without it.',
    );
  }

  /// Whether [runGenerate] should resolve what it wrote.
  bool get pubGet => !noPubGet.value;
}

/// What one run of `good generate` produced.
@immutable
class GenerateResult {
  const GenerateResult({required this.bundle, required this.fileCount});

  /// The generated package everything was written into.
  final BundlePackage bundle;

  /// How many files were written.
  final int fileCount;
}

/// The whole of what `good generate` does, callable without a command line.
///
/// Extracted so `good create` can finish a new project by generating into it -
/// see `CreateCommand.execute`. A fresh project whose bundle package does not
/// exist yet is one whose first `flutter run` fails, and telling someone to run
/// a second command is a worse answer than running it.
///
/// # Everything it writes goes in one package beside the project
///
/// Not `lib/good.generated/` any more. The generated Dart and the generated
/// chunks are one artifact from one input, and splitting them by file type -
/// code inside the project, bytes beside it - would leave "may good overwrite
/// this" with two answers. Split by **author** instead: `lib/` is the person's,
/// entirely, and the package next to it is good's, entirely. See
/// `bundle.dart` for the marker that makes the second half provable.
///
/// # Rewritten in place, never cleared and refilled
///
/// The generated code is imported as `package:<bundle>/textures.dart`, so an
/// empty bundle package is not a package waiting to be refilled - it is every
/// asset-referencing file in the project failing to resolve. Two more reasons
/// the same way: `asset_key.dart` is written once and must survive every later
/// run, and a clear that succeeded followed by a write that failed would leave
/// a package that exists, is depended on, and has no `lib/`. The set of
/// generated files is fixed at four, so there is nothing a rewrite can leave
/// stale.
///
/// [pubGet] is the resolve step. It is on by default and only tests and CI
/// turn it off - see the comment at the call below for why leaving it to the
/// next build is not safe.
///
/// [enginePackage] names the package the generated files import. Left out, it
/// is read from the project dependencies by [enginePackageOf]. `good create`
/// passes it: it has just written the pubspec line declaring the engine, and
/// the project has not been resolved since, so the dependency is in no package
/// config for [enginePackageOf] to find.
GenerateResult runGenerate({
  required Directory projectDir,
  required String command,
  required VerboseOutput out,
  required VerboseOutput verbose,
  String? enginePackage,
  bool rotateKeys = false,
  bool dryRun = false,
  bool pubGet = true,
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

  // Also before anything is written, and not gated on the project having
  // assets: two components declaring one field name is a defect in the same
  // class as an asset Flutter will not bundle - it costs a column in every row
  // and silently sends reads and writes to the wrong one, and no run of the
  // game will ever mention it. `good generate` is where a project-level defect
  // gets refused (#107), and it is the command a build runs whether or not
  // there is an asset to chunk, which is why this is here and not in the scene
  // scan that only asset packing calls.
  final shadow = scanStructRules(project);
  for (final entry in shadow.unresolved.entries) {
    verbose.println('Not compared: ${entry.key} - ${entry.value}');
  }
  if (shadow.shadowed.isNotEmpty) {
    throw ArgumentError(shadowedFieldsMessage(shadow));
  }
  if (shadow.missingSuper.isNotEmpty) {
    throw ArgumentError(missingSuperMessage(shadow));
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

  final package = enginePackage ?? enginePackageOf(project);
  verbose.printf('Engine package: %s\n', [package]);

  // Whether a texture key can be typed `Texture`, asked of the dependency
  // graph and not of the package's name (#312).
  final draws = enginePackageDrawsTextures(project, package);
  verbose.printf('Texture payload: %s\n', [
    draws ? 'Texture' : 'Object? - $package does not reach goo2d',
  ]);

  // Said out loud because the generated size is `0` for a file whose
  // header did not state one, and a zero divisor draws nothing rather
  // than failing.
  for (final texture in scan.textures) {
    if (texture.size != null) continue;
    out.printf(
      'Could not read the pixel size of %s - its width and height '
      'generate as 0. Re-export it as PNG, WebP, GIF, BMP or JPEG.\n',
      [texture.path],
    );
  }

  // Which package is the bundle, and whether it is good's to write to. Before
  // the first byte: everything below either creates that directory or writes
  // over what is in it, and a directory this cannot prove it created is one
  // it must not touch at all.
  final bundle = resolveBundle(project);
  verbose.printf('Bundle package: %s\n', [bundle.directory.path]);

  final projectName = projectNameOf(project);
  final writes = <String, String>{
    bundle.pubspec.path: emitBundlePubspec(
      bundleName: bundle.name,
      projectName: projectName,
      enginePackage: package,
      engineDependency: engineDependencyFor(project, package),
      sdkConstraint: sdkConstraintOf(project),
      command: command,
    ),
    p.join(bundle.libDir.path, 'textures.dart'): emitTextures(
      scan,
      command: command,
      package: package,
      drawsTextures: draws,
    ),
    p.join(bundle.libDir.path, 'audios.dart'): emitAudios(
      scan,
      command: command,
      package: package,
    ),
    p.join(bundle.libDir.path, 'good.dart'): emitReadiness(
      command: command,
      package: package,
    ),
  };

  // The keys, which are the one generated file that is not a function of the
  // project's current state. Three ways in, and the order matters:
  //
  //  * the bundle already has them - left exactly as they are, unless
  //    --rotate-keys says otherwise;
  //  * a project still on `lib/good.generated/` has them - **carried over
  //    byte for byte**. Minting new ones during a migration would rotate a
  //    shipped game's asset keys as a side effect of an upgrade nobody asked
  //    to change anything, and orphan every pack already built;
  //  * neither - minted.
  final legacyKeys = legacyAssetKeyFile(project);
  final keysExist = bundle.assetKeyFile.existsSync();
  if (rotateKeys || !keysExist) {
    if (!rotateKeys && legacyKeys != null) {
      writes[bundle.assetKeyFile.path] = legacyKeys.readAsStringSync();
      out.printf('Carrying %s over unchanged - the keys it holds decrypt '
          'every pack already built.\n', [
        '$legacyGeneratedDir/asset_key.dart',
      ]);
    } else {
      writes[bundle.assetKeyFile.path] = emitAssetKeys(
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
    }
  } else {
    verbose.println(
      'asset_key.dart exists - left alone. Use --rotate-keys to replace it.',
    );
  }

  if (dryRun) {
    out.printf('Would write %s\n', [bundle.marker.path]);
    for (final path in writes.keys) {
      out.printf('Would write %s\n', [path]);
    }
    if (Directory(p.join(project.path, legacyGeneratedDir)).existsSync()) {
      out.printf('Would move %s into %s and repoint its imports\n', [
        legacyGeneratedDir,
        bundle.libDir.path,
      ]);
    }
    return GenerateResult(bundle: bundle, fileCount: writes.length);
  }

  // The directory, then the marker, then everything else. The order is the
  // guarantee: a marker written after the first file does not cover that
  // file, and a run that dies in between - a full disk, a closed terminal -
  // leaves a directory good made and can no longer prove it made. Every later
  // command refuses that directory by name, so the way out of it is deleting
  // a package by hand. `lib/` is part of what a later run writes into, so it
  // comes after the claim and not with it.
  bundle.directory.createSync(recursive: true);
  bundle.marker.writeAsStringSync(
    bundleMarkerContents(
      bundleName: bundle.name,
      projectName: projectName,
      command: command,
    ),
  );
  bundle.libDir.createSync(recursive: true);
  for (final entry in writes.entries) {
    File(entry.key).writeAsStringSync(entry.value);
    out.printf('Wrote %s\n', [entry.key]);
  }

  _migrate(project, bundle, out);
  _recordBundle(project, bundle, out);
  _resolve(project, bundle, out, verbose, pubGet: pubGet);

  final problems = bundleProblems(
    projectDir: project,
    bundle: bundle,
    enginePackage: package,
    writtenFiles: writes.keys,
    checkResolution: pubGet,
  );
  if (problems.isNotEmpty) {
    throw ArgumentError(
      'The generated package is not what it should be after writing it:\n'
      '${problems.map((problem) => '  - $problem').join('\n')}\n'
      'Nothing downstream would say so: an empty generated package, an absent '
      'one and an unresolved one all build green and ship nothing.',
    );
  }

  out.printf('%s texture(s), %s audio file(s).\n', [
    scan.textures.length,
    scan.audio.length,
  ]);
  return GenerateResult(bundle: bundle, fileCount: writes.length);
}

/// Moves a project off `lib/good.generated/`.
///
/// Migrating rather than warning, and rather than refusing. Leaving the old
/// directory in place would leave two copies of `Textures` in one project,
/// both compiling, differing the moment an asset is added - and the keys in the
/// stale copy are the ones every shipped pack was built with, so "leave it and
/// warn" is a warning that a project's assets have quietly stopped decrypting.
/// Refusing outright puts the work on the person for no gain: this knows which
/// four files it wrote, and it can tell a file it wrote from one it did not.
void _migrate(Directory project, BundlePackage bundle, VerboseOutput out) {
  final migration = migrateLegacyGenerated(
    projectDir: project,
    bundle: bundle,
  );
  if (migration.isEmpty) return;
  if (migration.moved.isNotEmpty) {
    out.printf('Moved %s out of %s/ - lib/ is yours now.\n', [
      migration.moved.join(', '),
      legacyGeneratedDir,
    ]);
  }
  for (final path in migration.rewritten) {
    out.printf('Repointed the generated imports in %s\n', [path]);
  }
  for (final path in migration.leftBehind) {
    out.printf(
      'Left %s where it is - good did not write it, so it is not good\'s to '
      'delete.\n',
      [path],
    );
  }
}

/// Records the bundle in the project's pubspec: the dependency, and the name.
///
/// Both are needed and they answer different questions. The dependency is what
/// makes the generated code reachable at all; the recorded name is what says
/// which package is the bundle on every later run, so a project rename does not
/// orphan one and build a second beside it.
void _recordBundle(
  Directory project,
  BundlePackage bundle,
  VerboseOutput out,
) {
  final pubspec = File(p.join(project.path, 'pubspec.yaml'));
  final patched = pubspec.existsSync()
      ? patchedBundlePubspecLines(pubspec.readAsLinesSync(), bundle.name)
      : null;
  if (patched == null) {
    // Printed, not guessed at - the same rule `patchedPubspecLines` follows.
    // The run still fails, in the assertion below: what it was asked to do was
    // make the generated package reachable, and it is not.
    out
      ..println('')
      ..printf('Add this to %s by hand:\n', [pubspec.path])
      ..println(bundlePubspecPatch(bundle.name));
    return;
  }
  pubspec.writeAsStringSync('${patched.join('\n')}\n');
}

/// Makes the path dependency real, or proves it already is.
///
/// The happy path resolves itself: the pubspec changed, so the next build
/// re-resolves. Every other path is silent. Flutter's staleness gate is pure
/// mtime and never compares content, and `pub get` legitimately leaves
/// `package_config.json` newer than `pubspec.yaml` - so a bundle directory
/// deleted after a successful resolve produces an exit-0 build that ships
/// nothing from it. A gitignored generated package and a cache-restoring CI
/// both reach that state without anybody doing anything unusual.
///
/// Asked as a question about the resolved config rather than run
/// unconditionally: a `good generate` in a loop, and `good build` which runs
/// one every time, should not pay two seconds to re-establish something that
/// is already established. When the answer is no, this runs; when it is yes,
/// there is nothing to do and the assertion afterwards says the same thing.
void _resolve(
  Directory project,
  BundlePackage bundle,
  VerboseOutput out,
  VerboseOutput verbose, {
  required bool pubGet,
}) {
  if (!pubGet) {
    verbose.println('--no-pub-get: leaving the resolve to whoever runs next.');
    return;
  }
  if (bundleIsResolved(project, bundle)) {
    verbose.printf('%s already resolves to %s - not running pub get.\n', [
      bundle.name,
      bundle.directory.path,
    ]);
    return;
  }
  out.printf('Resolving %s - flutter pub get\n', [bundle.name]);
  final failure = runFlutterPubGet(project);
  if (failure != null) throw ArgumentError(failure);
}
