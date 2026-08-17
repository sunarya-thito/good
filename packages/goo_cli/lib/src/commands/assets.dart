import 'package:goo_cli/src/command.dart';
import 'package:goo_cli/src/commands/assets/compact.dart';

/// `goo assets` - everything that happens to art between the artist and the
/// build.
class AssetsCommand extends Command {
  late final CompactCommand compact;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    compact = descriptor.describeSubCommand(
      'compact',
      'Convert source art into the one canonical format per kind.',
      CompactCommand(),
    );
  }
}
