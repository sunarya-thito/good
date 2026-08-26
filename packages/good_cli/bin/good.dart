// Entry point for the `good` CLI.
//
// `runCommand` owns the exit codes and the error reporting; what each command
// does lives in `lib/src/commands/`.
import 'dart:io';

import 'package:good_cli/src/commands/good.dart';
import 'package:good_cli/src/runner.dart';

// `args`, not a bare `main()`. `Platform.executableArguments` - what this
// reached for before - is the Dart VM's own arguments, never the script's, so
// every command line was silently parsed as empty.
Future<void> main(List<String> args) async {
  exitCode = await runCommand(GoodCommand(), args);
}
