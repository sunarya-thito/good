import 'package:good_cli/src/commands/build/build_sub_command.dart';

/// `good build windows`.
class WindowsBuildCommand extends BuildSubCommand {
  @override
  String get flutterTarget => 'windows';
}
