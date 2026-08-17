// Entry point for the `goo` CLI - see the project root plan, Phase 4.
//
// The command *framework* is implemented; the pipelines it drives (codegen,
// asset packing, platform packaging) are not. `goo` and `goo compile --help`
// work and describe what will exist.
import 'dart:io';

import 'package:goo_cli/src/commands/goo.dart';
import 'package:goo_cli/src/runner.dart';

// `args`, not a bare `main()`. `Platform.executableArguments` - what this
// reached for before - is the Dart VM's own arguments, never the script's, so
// every command line was silently parsed as empty.
Future<void> main(List<String> args) async {
  exitCode = await runCommand(GooCommand(), args);
}
