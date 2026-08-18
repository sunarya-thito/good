import 'package:good_cli/src/commands/build/build_sub_command.dart';

/// `good build android`.
class AndroidBuildCommand extends BuildSubCommand {
  @override
  String get flutterTarget => 'apk';
}
