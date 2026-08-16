import 'dart:io';

import 'package:goo_cli/src/command.dart';

mixin Verbose on Command {
  late final Arg<bool> verbose;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    // enable debug output for this command
    verbose = descriptor.describeFlag(
      name: 'verbose',
      description: 'Enable verbose output.',
      defaultValue: false,
    );
  }

  VerboseOutput get debug {
    throw UnimplementedError('VerboseOutput is not implemented.');
  }

  VerboseOutput get info {
    throw UnimplementedError('VerboseOutput is not implemented.');
  }

  VerboseOutput get err {
    throw UnimplementedError('VerboseOutput is not implemented.');
  }
}

abstract class VerboseOutput {
  void println(Object? object);
  void print(Object? object);
  void printf(String format, List<Object?> args);
}
