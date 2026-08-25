import 'dart:io';

import 'package:good_cli/src/command.dart';

/// A command that takes `--verbose`, and the three output channels that go
/// with it.
///
/// The point of the split is that a build tool has three different audiences
/// in one stream, and only one of them is optional:
///
///  * [debug] - what the tool did and why. Silent unless `--verbose`.
///  * [info] - what the user asked to know. Always on, stdout, so it pipes.
///  * [err] - what went wrong. Always on, stderr, so it survives a pipe.
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

  VerboseOutput? _debug;
  VerboseOutput? _info;
  VerboseOutput? _err;

  /// Built on first use, not in [describeCommand]: whether it writes anything
  /// depends on `--verbose`, which has no value until the command line has
  /// been parsed - and describe runs before that, for every command in the
  /// tree.
  VerboseOutput get debug =>
      _debug ??= verbose.value ? _SinkOutput(stdout) : const _SilentOutput();

  VerboseOutput get info => _info ??= _SinkOutput(stdout);

  VerboseOutput get err => _err ??= _SinkOutput(stderr);
}

abstract class VerboseOutput {
  void println(Object? object);
  void print(Object? object);

  /// [format] with each `%s` replaced by the next of [args], in order.
  ///
  /// That one substitution is all there is: a build tool's messages are
  /// assembled from paths and counts, and a fuller `printf` would be a
  /// formatting language to specify, implement and test for no reader's
  /// benefit. A leftover `%s` with no argument is left as written, never
  /// silently dropped, so the bug is visible in the output.
  void printf(String format, List<Object?> args);
}

class _SinkOutput implements VerboseOutput {
  _SinkOutput(this._sink);

  final IOSink _sink;

  @override
  void println(Object? object) => _sink.writeln(object);

  @override
  void print(Object? object) => _sink.write(object);

  @override
  void printf(String format, List<Object?> args) =>
      _sink.write(formatMessage(format, args));
}

/// What [Verbose.debug] is without `--verbose`: every call is a no-op.
///
/// A null object, not an `if` at each call site, so a debug line costs
/// its argument evaluation and one virtual call, and reads the same whether it
/// is switched on or not.
class _SilentOutput implements VerboseOutput {
  const _SilentOutput();

  @override
  void println(Object? object) {}

  @override
  void print(Object? object) {}

  @override
  void printf(String format, List<Object?> args) {}
}

/// [VerboseOutput.printf]'s substitution, exposed so it can be tested without
/// capturing a real stdout.
String formatMessage(String format, List<Object?> args) {
  final buffer = StringBuffer();
  var next = 0;
  var i = 0;
  while (i < format.length) {
    final at = format.indexOf('%s', i);
    if (at == -1 || next >= args.length) {
      buffer.write(format.substring(i));
      break;
    }
    buffer
      ..write(format.substring(i, at))
      ..write(args[next++]);
    i = at + 2;
  }
  return buffer.toString();
}
