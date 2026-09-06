import 'package:good_cli/src/command.dart';
import 'package:good_cli/src/commands/build.dart';
import 'package:good_cli/src/commands/create.dart';
import 'package:good_cli/src/commands/generate.dart';

/// The root of the `good` command tree.
///
/// Three commands, and that is the whole of it (#238). There was a fourth -
/// `good assets`, holding `compact` and `pack` - and it was two ways to run
/// half of `good generate` out of order. Both folded into it: the pipeline is
/// one thing with one order, so it is one command.
///
/// Declares nothing of its own beyond the subcommands, so running `good` with
/// no arguments falls through to [Command.execute]'s default and prints the
/// command list - which is what someone typing `good` to find out what it does
/// is asking for.
class GoodCommand extends Command {
  late final CreateCommand create;
  late final GenerateCommand generate;
  late final BuildCommand build;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    // Declared in the order a project meets them: make one, generate what it
    // ships, build it. `describeSubCommand` preserves that order in help.
    create = descriptor.describeSubCommand(
      'create',
      'Scaffold a new Flutter project wired up to good.',
      CreateCommand(),
    );
    generate = descriptor.describeSubCommand(
      'generate',
      'Convert the source art, write the generated bundle package, and pack '
          'what the project ships.',
      GenerateCommand(),
    );
    build = descriptor.describeSubCommand(
      'build',
      'Build and package a game for a target platform.',
      BuildCommand(),
    );
  }
}
