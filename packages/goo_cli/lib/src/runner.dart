import 'dart:io';

import 'package:goo_cli/src/command.dart';

void runCommand(Command command, [List<String>? args]) {
  final runner = CommandRunner(command);
  runner.run(args ?? Platform.executableArguments);
}

class CommandRunner {}
