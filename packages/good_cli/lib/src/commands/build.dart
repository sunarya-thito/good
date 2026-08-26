import 'package:good_cli/src/command.dart';
import 'package:good_cli/src/commands/build/android.dart';
import 'package:good_cli/src/commands/build/ios.dart';
import 'package:good_cli/src/commands/build/linux.dart';
import 'package:good_cli/src/commands/build/windows.dart';

/// `good build <platform>`.
///
/// One command per platform, not one command with a `--platform`
/// option, because they are genuinely different: each will grow its own
/// signing, bundling and packaging options, and an option that applies to one
/// target is one every other target's help has to explain away.
class BuildCommand extends Command {
  late final WindowsBuildCommand windows;
  late final LinuxBuildCommand linux;
  late final AndroidBuildCommand android;
  late final IosBuildCommand ios;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
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
