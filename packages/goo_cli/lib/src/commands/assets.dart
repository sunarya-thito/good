import 'package:goo_cli/src/command.dart';
import 'package:goo_cli/src/commands/assets/compact.dart';
import 'package:goo_cli/src/commands/assets/pack.dart';

/// `goo assets` - everything that happens to art between the artist and the
/// build.
class AssetsCommand extends Command {
  late final CompactCommand compact;
  late final PackCommand pack;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    compact = descriptor.describeSubCommand(
      'compact',
      'Convert source art into the one canonical format per kind.',
      CompactCommand(),
    );
    pack = descriptor.describeSubCommand(
      'pack',
      'Chunk, compress and encrypt the assets a build ships.',
      PackCommand(),
    );
  }
}
