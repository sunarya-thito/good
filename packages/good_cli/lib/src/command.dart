import 'dart:async';

import 'package:meta/meta.dart';

/// One command, declared the way everything in this engine is declared: a
/// `describe*` pass that hands back typed handles the command keeps in
/// `late final` fields, and never a name to quote again later.
///
/// ```dart
/// class ExportCommand extends Command {
///   late final Arg<Directory> outputDir;
///
///   @override
///   void describeCommand(CommandDescriptor descriptor) {
///     super.describeCommand(descriptor);
///     outputDir = descriptor.describeArg<Directory>(
///       name: 'output-dir',
///       description: 'Where the build lands.',
///       parser: parseDirectory,
///       defaultValue: Directory('./build'),
///     );
///   }
///
///   @override
///   void execute() => print(outputDir.value.path);
/// }
/// ```
///
/// [describeCommand] runs exactly once per instance, before any parsing, for
/// **every** command in the tree - not just the selected one. That is what
/// lets `good build --help` describe a subcommand this run is not going to
/// execute.
abstract class Command {
  /// Bound by [CommandRunner] during its declaration pass. Every member below
  /// that reports on the run reads through it, and each fails by name rather
  /// than null-dereferencing when a command is inspected outside a run.
  CommandBinding? _binding;

  @internal
  void bind(CommandBinding binding) => _binding = binding;

  CommandBinding get _bound {
    final binding = _binding;
    if (binding == null) {
      throw StateError(
        '$runtimeType has not been run. `selected`, `parent`, `session` and '
        '`findAncestor` are all answers about a particular run, and are '
        'assigned when CommandRunner walks the command tree. A command '
        'constructed by hand has no run to report on.',
      );
    }
    return binding;
  }

  /// Whether *this* command is the one the arguments selected.
  ///
  /// Exactly one command in the tree answers `true`. A command that merely
  /// sits on the path to it answers `false`, and so does a sibling nobody
  /// named. The question is total, so a `BuildCommand` asking
  /// `windows.selected` is an ordinary thing to do and never throws.
  bool get selected => _bound.selected;

  /// The command that declared this one as a subcommand.
  ///
  /// Throws for the root, which is not a failure to handle but a question that
  /// has no answer - use [findAncestor] if you mean "walk up if there is
  /// anything to walk up to".
  Command get parent {
    final parent = _bound.parent;
    if (parent == null) {
      throw StateError(
        '$runtimeType is the root command and has no parent. Reaching for one '
        'usually means walking up to find something specific - findAncestor<T> '
        'does that and stops cleanly at the root.',
      );
    }
    return parent.command;
  }

  /// The nearest enclosing command of type [T], this command included.
  ///
  /// How a subcommand reaches a flag its parent declared: `--verbose` on
  /// `my_command compile` is one declaration, and `my_command compile
  /// windows` reads it through here instead of redeclaring its own.
  T findAncestor<T extends Command>() {
    for (CommandBinding? at = _bound; at != null; at = at.parent) {
      final command = at.command;
      if (command is T) return command;
    }
    throw StateError(
      'No $T among $runtimeType and its ancestors. findAncestor searches the '
      'path from this command up to the root, so a $T that is a *sibling* - or '
      'a subcommand of something else - is deliberately not found.',
    );
  }

  /// This run's parsed arguments. Every [Arg] reads through it.
  CommandSession get session => _bound.session;

  /// Declares this command's arguments and subcommands. Runs once, before
  /// parsing.
  @mustCallSuper
  void describeCommand(CommandDescriptor descriptor) {}

  /// What this command does. The base implementation prints help, which is
  /// what a command with subcommands and nothing of its own to do wants -
  /// `super.execute()` from a subclass reaches it.
  FutureOr<void> execute() {
    _bound.printUsage();
  }
}

/// One run's parsed values, keyed by the declaration that produced them.
///
/// Handed to [Arg]s, not baked into them, so a declaration is a
/// description of an argument and not a slot holding one run's answer.
abstract class CommandSession {
  /// The values [arg] was given, already parsed. Empty when it was absent and
  /// had no default.
  List<T> valuesOf<T>(Arg<T> arg);

  /// The command path that was selected, root first - `['good', 'build',
  /// 'windows']`. Diagnostics and help.
  List<String> get path;
}

/// The binding [CommandRunner] injects into a [Command] - the run-specific
/// half of it, kept off the `Command` surface so a subclass author sees only
/// what they are meant to override.
@internal
abstract class CommandBinding {
  Command get command;
  CommandBinding? get parent;
  bool get selected;
  CommandSession get session;
  void printUsage();
}

/*
Arg is for --arg=value or --arg value or simply --arg (value is empty string)
for example: my_command --my-arg=hello or my_command --my-arg hello or my_command --my-arg
SubCommand is for subcommands like my_command compile windows --input-dir=./src
for multi words use quotes like my_command compile --input-dir="./my src"
Consumer is for my_command consumer_value consumer_value2 (where consumer1 is "consumer_value" and consumer2 is "consumer_value2"), Consumer is order-sensitive towards other consumer
Remaining is for my_command remaining_value remaining_value2 (where remaining string is "remaining_value remaining_value2"), Remaining is not sensitive to order
even if it described before any arg or in the middle or at the end, it will always consume remaining arguments, it can only be described once
Consumer can be required (represented as <name> in the help) or optional (represented as [name] in the help), Remaining can be required (need at least one word) or optional (can be empty)
default value is represented as [name=default_value] in the help, if default value is not provided, it will be represented as [name] in the help
optional Arg can be done by using .describeConsumer<MyType?>(...)
*/

/// Declares one command's arguments and subcommands.
///
/// Four kinds of argument, and the difference between them is only ever *how
/// the token is found*, never what happens to it afterwards - every one ends
/// up in an [ArgumentParser] that turns a `String` into a `T`.
///
///  * **Arg** - named. `--arg=value`, `--arg value`, or bare `--arg`, which
///    hands the parser an empty string.
///  * **Consumer** - positional, and order-sensitive against other consumers:
///    the first bare token fills the first declared consumer.
///  * **Remaining** - whatever positional tokens the consumers did not take,
///    joined with single spaces and parsed as one string. Order-*in*sensitive:
///    it can be declared before, between or after anything else and still
///    collects the leftovers. At most one per command.
///  * **Flag/Option** - an [Arg] with its parsing supplied: a `bool` from
///    presence, or one of an enum's values by name.
///
/// Quoting is the shell's job, not this parser's. By the time a process sees
/// its arguments `--input-dir="./my src"` has already become the single token
/// `--input-dir=./my src`.
abstract class CommandDescriptor {
  T describeSubCommand<T extends Command>(
    String name,
    String description,
    T commandHandler,
  );
  Arg<T> describeArg<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
    required T defaultValue,
  });
  Arg<T?> describeOptionalArg<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
  });
  MultiArg<T> describeMultiArg<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
    required T defaultValue,
  });
  MultiArg<T> describeOptionalMultiArg<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
  });
  Arg<bool> describeFlag({
    required String name,
    required String description,
    bool defaultValue = false,
  });
  Arg<T> describeOption<T extends Enum>({
    required String name,
    required String description,
    required List<T> choices,
    required T defaultValue,
  });
  Arg<T?> describeOptionalOption<T extends Enum>({
    required String name,
    required String description,
    required List<T> choices,
  });
  MultiArg<T> describeMultiOption<T extends Enum>({
    required String name,
    required String description,
    required List<T> choices,
    required T defaultValue,
  });

  /// The optional multi-value option.
  ///
  /// Returns a [MultiArg], not the `Arg<T?>` the original sketch had - that
  /// was a slip: every other `describeMulti*` hands back a `MultiArg`, and an
  /// `Arg` has no way to report a second value.
  MultiArg<T> describeOptionalMultiOption<T extends Enum>({
    required String name,
    required String description,
    required List<T> choices,
  });
  Arg<T> describeConsumer<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
    required T defaultValue,
  });
  Arg<T?> describeOptionalConsumer<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
  });
  Arg<T> describeRemaining<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
    required T defaultValue,
  });
  Arg<T?> describeOptionalRemaining<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
  });
}

/// A single-valued declared argument. Read [value] inside `execute`.
abstract class Arg<T> {
  /// The run this argument was parsed in.
  CommandSession get session;

  /// The parsed value, or the declared default when the argument was absent.
  /// `null` for an absent optional one.
  T get value;

  /// Whether the argument may be left out.
  bool get optional;
}

/// A repeatable declared argument - `--define=a --define=b`.
abstract class MultiArg<T> {
  CommandSession get session;

  T operator [](int index);

  /// How many values were supplied.
  ///
  /// Not in the original sketch, and indexing is unusable without it: there
  /// would be no way to know when to stop short of catching a [RangeError].
  int get length;

  /// Whether an empty list is allowed. `false` requires at least one value.
  bool get optional;
}

typedef ArgumentParser<T> = T Function(String value);

/// A malformed command line, as opposed to a command that ran and failed.
///
/// Carries the command it happened in, so [CommandRunner] can print that
/// command's usage and not the root's - `good build windows --nope`
/// should show the windows usage.
/// A command that ran, understood its input, and could not finish.
///
/// Distinct from [UsageException], which means the command *line* was wrong,
/// and from `ArgumentError`, which means something the command read was. This
/// one is the work failing: no ffmpeg, `flutter build` returning non-zero, a
/// key file that cannot be written.
///
/// # Why an exception and not an `int` returned from `execute`
///
/// A returned code has to be passed back through every command signature and
/// every helper between the failure and the runner, and forgetting to pass it
/// is silent - which is the bug this type exists to remove, moved one layer
/// along. Throwing is not something you can leave out by accident.
///
/// # Why [message] is usually absent
///
/// Nearly every site that throws this has already written the detail to its own
/// `err` sink: the failing command's own output, the path that could not be
/// written, the list of assets that would not convert. A summary printed under
/// that by the runner would say it a second time. Pass a message only where
/// nothing has been printed yet.
class CommandFailure implements Exception {
  const CommandFailure([this.message]);

  /// A line for the runner to print, when the thrower has not printed one.
  final String? message;

  @override
  String toString() => message ?? 'the command failed';
}

class UsageException implements Exception {
  UsageException(this.message, [this.path = const <String>[]]);

  final String message;

  /// The command path the error happened in, root first.
  final List<String> path;

  @override
  String toString() => message;
}
