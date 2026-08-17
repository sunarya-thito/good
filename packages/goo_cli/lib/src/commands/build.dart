import 'dart:io';

import 'package:goo_cli/src/command.dart';
import 'package:goo_cli/src/commands/build/platform.dart';
import 'package:goo_cli/src/parsers.dart';
import 'package:goo_cli/src/verbosable.dart';

/// How assets are prepared for a build.
///
/// The two modes exist because they want opposite things. Development wants
/// the shortest path from a changed file to seeing it: no packing, no
/// compression, no decryption, and a file you can replace on disk and reload.
/// Release wants the pack: fewer files, smaller, and not trivially
/// extractable.
enum AssetMode {
  /// Loose files, exactly as `goo assets compact` wrote them. What a
  /// `flutter run` uses.
  development,

  /// Compressed, encrypted, chunked - see `goo assets pack`.
  release,
}

enum AssetEncryption { none, aes }

enum AssetCompressionLevel { none, fast, normal, best }

/// `goo build <platform>`.
///
/// Renamed from `goo compile`: what this does is produce a build, and every
/// other tool in the ecosystem a user is coming from spells that `build`.
class BuildCommand extends Command {
  late final WindowsBuildCommand windows;
  late final LinuxBuildCommand linux;
  late final AndroidBuildCommand android;
  late final IosBuildCommand ios;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    windows = descriptor.describeSubCommand(
      'windows',
      'Build for Windows.',
      WindowsBuildCommand(),
    );
    linux = descriptor.describeSubCommand(
      'linux',
      'Build for Linux.',
      LinuxBuildCommand(),
    );
    android = descriptor.describeSubCommand(
      'android',
      'Build for Android.',
      AndroidBuildCommand(),
    );
    ios = descriptor.describeSubCommand(
      'ios',
      'Build for iOS.',
      IosBuildCommand(),
    );
  }
}

/// What every platform build shares.
///
/// The per-platform subclasses differ only in which `flutter build` target
/// they invoke and where the artifact lands, so everything else - asset mode,
/// encryption, the output directory - is declared once here. A platform that
/// needs an extra option adds it in its own `describeCommand` and calls
/// `super`.
abstract class BuildSubCommand extends Command with Verbose {
  late final Arg<Directory> projectDir;
  late final Arg<Directory> outputDir;
  late final Arg<bool> dryRun;
  late final Arg<AssetMode> assetMode;
  late final Arg<AssetEncryption> assetEncryption;
  late final Arg<AssetCompressionLevel> assetCompression;

  /// The `flutter build <target>` this platform runs.
  String get flutterTarget;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    projectDir = descriptor.describeArg<Directory>(
      name: 'project-dir',
      description: 'The project to build.',
      parser: parseDirectory,
      defaultValue: Directory('.'),
    );
    outputDir = descriptor.describeArg<Directory>(
      name: 'output-dir',
      description: 'Where the packaged build is written.',
      parser: parseOutputDirectory,
      defaultValue: Directory('./build/goo'),
    );
    dryRun = descriptor.describeFlag(
      name: 'dry-run',
      description: 'Report the plan, and do nothing.',
    );
    assetMode = descriptor.describeOption<AssetMode>(
      name: 'assets',
      description: 'Loose files, or a packed release bundle.',
      choices: AssetMode.values,
      // Release is the default *for a build*: `flutter run` is the development
      // path and does not come through here at all, so someone typing
      // `goo build windows` is making something to ship.
      defaultValue: AssetMode.release,
    );
    assetEncryption = descriptor.describeOption<AssetEncryption>(
      name: 'asset-encryption',
      description: 'Encryption for packed assets.',
      choices: AssetEncryption.values,
      // AES by default, not none. Packing without encrypting leaves every
      // file header legible in a hex editor, which is the thing packing is
      // meant to stop being trivial - see goo_cli's README on what this does
      // and does not claim.
      defaultValue: AssetEncryption.aes,
    );
    assetCompression = descriptor.describeOption<AssetCompressionLevel>(
      name: 'asset-compression',
      description: 'Compression for packed assets.',
      choices: AssetCompressionLevel.values,
      defaultValue: AssetCompressionLevel.normal,
    );
  }

  @override
  void execute() {
    info
      ..printf('goo build %s\n', [flutterTarget])
      ..printf('  project:     %s\n', [projectDir.value.path])
      ..printf('  output:      %s\n', [outputDir.value.path])
      ..printf('  assets:      %s\n', [assetMode.value.name])
      ..printf('  encryption:  %s\n', [assetEncryption.value.name])
      ..printf('  compression: %s\n', [assetCompression.value.name]);

    if (assetMode.value == AssetMode.development &&
        assetEncryption.value != AssetEncryption.none) {
      // Said rather than silently resolved: a development build loads loose
      // files, so an encryption setting has nothing to act on and expecting it
      // to would be a real misunderstanding to leave in place.
      info.println(
        '  note: --assets=development loads loose files, so '
        '--asset-encryption has no effect.',
      );
    }

    if (dryRun.value) {
      info.println('Dry run - stopping before any work.');
      return;
    }

    err.println(
      'The build pipeline is not implemented yet. `goo assets compact` and '
      '`goo assets pack` are the pieces it will drive; run those directly for '
      'now, then `flutter build $flutterTarget` yourself.',
    );
  }
}
