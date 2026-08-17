import 'package:goo_cli/src/command.dart';
import 'package:goo_cli/src/commands/assets.dart';
import 'package:goo_cli/src/commands/build.dart';
import 'package:goo_cli/src/commands/create.dart';
import 'package:goo_cli/src/commands/generate.dart';

/// The root of the `goo` command tree.
///
/// Declares nothing of its own beyond the subcommands, so running `goo` with
/// no arguments falls through to [Command.execute]'s default and prints the
/// command list - which is what someone typing `goo` to find out what it does
/// is asking for.
class GooCommand extends Command {
  late final CreateCommand create;
  late final GenerateCommand generate;
  late final AssetsCommand assets;
  late final BuildCommand build;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    // Declared in the order a project meets them: make one, generate its
    // bindings, build it. `describeSubCommand` preserves that order in help.
    create = descriptor.describeSubCommand(
      'create',
      'Scaffold a new Flutter project wired up to goo.',
      CreateCommand(),
    );
    generate = descriptor.describeSubCommand(
      'generate',
      'Write lib/goo.generated/ from the assets the pubspec declares.',
      GenerateCommand(),
    );
    assets = descriptor.describeSubCommand(
      'assets',
      'Convert and pack the assets a project ships.',
      AssetsCommand(),
    );
    build = descriptor.describeSubCommand(
      'build',
      'Build and package a game for a target platform.',
      BuildCommand(),
    );
  }
}
