import 'package:goo_cli/src/commands/build/build_sub_command.dart';

/// `goo build android`.
class AndroidBuildCommand extends BuildSubCommand {
  @override
  String get flutterTarget => 'apk';
}
