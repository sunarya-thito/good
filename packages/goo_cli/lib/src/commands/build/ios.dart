import 'package:goo_cli/src/commands/build/build_sub_command.dart';

/// `goo build ios`.
class IosBuildCommand extends BuildSubCommand {
  @override
  String get flutterTarget => 'ios';
}
