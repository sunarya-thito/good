import 'dart:io';

import 'package:goo_cli/src/command.dart';
import 'package:goo_cli/src/commands/compile.dart';

class WindowsCompileCommand extends CompileSubCommand {
  @override
  void execute() {
    File inputDir = this.inputDir.value;
    File outputDir = this.outputDir.value;
  }
}
