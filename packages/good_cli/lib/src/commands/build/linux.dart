import 'package:good_cli/src/commands/build/build_sub_command.dart';

/// `good build linux`.
class LinuxBuildCommand extends BuildSubCommand {
  @override
  String get flutterTarget => 'linux';
}
