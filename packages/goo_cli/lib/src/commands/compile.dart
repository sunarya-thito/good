import 'dart:io';

import 'package:goo_cli/src/command.dart';
import 'package:goo_cli/src/commands/compile/windows.dart';
import 'package:goo_cli/src/verbosable.dart';
import 'package:goo_cli/src/parsers.dart';

enum AssetEncryption { none, aes, rsa }

enum AssetCompressionLevel { none, fast, normal, best }

enum AssetCompressionMethod { lossless, lossy }

enum TargetPlatform { windows, macos, linux, android, ios, web }

class CompileCommand extends Command {
  late final WindowsCompileCommand windows;
  @override
  void describeCommand(CommandDescriptor descriptor) {
    windows = descriptor.describeSubCommand(
      'windows',
      'Compile for Windows platform.',
      WindowsCompileCommand(),
    );
  }

  @override
  void execute() {
    if (windows.selected) {
      // "windows" subcommand is selected
      windows.execute();
      return;
    }
    super.execute(); // shows help
  }
}

// TODO: subclass for each platform
abstract class CompileSubCommand extends Command with Verbose {
  late final Arg<File> inputDir;
  late final Arg<File> outputDir;
  late final Arg<bool> dryRun;
  late final Arg<AssetEncryption> assetEncryption;
  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    inputDir = descriptor.describeArg<File>(
      name: 'input-dir',
      description: 'The input directory containing the source files.',
      parser: parseFile,
      defaultValue: File('.'),
    );
    outputDir = descriptor.describeArg<File>(
      name: 'output-dir',
      description:
          'The output directory where the compiled files will be saved.',
      parser: parseFile,
      defaultValue: File('./build/Game/'),
    );
    dryRun = descriptor.describeFlag(
      name: 'dry-run',
      description: 'Perform a dry run without actually compiling.',
      defaultValue: false,
    );
    assetEncryption = descriptor.describeOption<AssetEncryption>(
      name: 'asset-encryption',
      description: 'The encryption method for assets.',
      choices: AssetEncryption.values,
      defaultValue: AssetEncryption.none,
    );
  }
}
