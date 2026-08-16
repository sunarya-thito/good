abstract class Command {
  bool get selected => true;
  Command get parent {
    throw UnimplementedError('Command parent is not implemented.');
  } // injected by the command runner

  T findAncestor<T extends Command>() {
    throw UnimplementedError('Command findAncestor is not implemented.');
  }

  CommandSession get session {
    throw UnimplementedError('CommandSession is not implemented.');
  } // injected by the command runner

  void describeCommand(CommandDescriptor descriptor) {}

  void execute() {
    // TODO: show help so that subclass can do super.execute(session) to show help
  }
}

abstract class CommandSession {}

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
  Arg<T?> describeOptionalMultiOption<T extends Enum>({
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

abstract class Arg<T> {
  CommandSession get session {
    throw UnimplementedError('CommandSession is not implemented.');
  } // injected by the command runner

  T get value; // if its single value like my_command --my-arg=hello
  bool get optional;
}

abstract class MultiArg<T> {
  CommandSession get session {
    throw UnimplementedError('CommandSession is not implemented.');
  } // injected by the command runner

  T operator [](int index);
  bool
  get optional; // if false, requires at least one value, if true, can be empty
}

typedef ArgumentParser<T> = T Function(String value);
