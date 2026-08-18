import 'package:goo_cli/src/commands/build/build_sub_command.dart';

/// `goo build linux`.
class LinuxBuildCommand extends BuildSubCommand {
  @override
  String get flutterTarget => 'linux';
}
