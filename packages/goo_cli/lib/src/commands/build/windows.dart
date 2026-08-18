import 'package:goo_cli/src/commands/build/build_sub_command.dart';

/// `goo build windows`.
class WindowsBuildCommand extends BuildSubCommand {
  @override
  String get flutterTarget => 'windows';
}
