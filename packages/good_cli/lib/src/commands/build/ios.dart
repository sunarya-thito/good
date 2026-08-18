import 'package:good_cli/src/commands/build/build_sub_command.dart';

/// `good build ios`.
class IosBuildCommand extends BuildSubCommand {
  @override
  String get flutterTarget => 'ios';
}
