import 'dart:io';

import 'package:good_cli/src/command.dart';

/// Runs [command] against [args], returning the process exit code.
///
/// Zero means the command finished. Every way of not finishing has a code of
/// its own, because a non-zero exit is the only part of this a CI step, a shell
/// `&&` or any other script can read: [UsageException] is 64, `ArgumentError`
/// 65, [CommandFailure] 70.
///
/// [args] is what `main` was handed. It is **not** optional in practice:
/// `Platform.executableArguments` - which this used to fall back to - is the
/// Dart VM's own arguments (`--enable-asserts` and friends), never the
/// script's, so the fallback silently parsed the wrong list.
Future<int> runCommand(
  Command command,
  List<String> args, {
  StringSink? out,
}) async {
  final sink = out ?? stdout;
  final runner = CommandRunner(command, out: sink);
  try {
    await runner.run(args);
    return 0;
  } on UsageException catch (error) {
    // stderr, and usage after the message: a user who piped stdout somewhere
    // still sees why nothing happened, and the last line on screen is the
    // thing they need rather than the top of a long help page.
    stderr.writeln(error.message);
    stderr.writeln();
    stderr.writeln(runner.usageFor(error.path));
    return 64; // EX_USAGE
  } on CommandFailure catch (failure) {
    // The work failed. Almost always silent here, because the command has
    // already written why to stderr; what was missing was never the message,
    // it was a non-zero code for anything that is not a person reading a
    // screen. `good build windows && upload` used to upload.
    final message = failure.message;
    if (message != null) stderr.writeln(message);
    return 70; // EX_SOFTWARE
  } on ArgumentError catch (error) {
    // A command refusing to run over something it read - a pubspec that does
    // not bundle its own assets, two files that generate one identifier, key
    // material that is the wrong length. The message is written for the person
    // who has to fix it, and burying it under fifteen stack frames from
    // `main` is throwing that away. No usage block: the command line was
    // fine, so reprinting it answers a question nobody asked.
    stderr.writeln(error.message);
    return 65; // EX_DATAERR
  } finally {
    if (sink is IOSink) sink.flush();
  }
}

/// Parses a command line against a [Command] tree and runs what it selected.
///
/// # Two passes, and the first one is total
///
/// Declaration runs over the **whole** tree up front, not just the branch the
/// arguments happen to select. That is what makes `good compile --help` able to
/// describe `windows`, and it is the same reason the engine's `describeStruct`
/// pass is total: a declaration that only runs when it is used is a
/// declaration you cannot inspect, print, or check for collisions.
class CommandRunner {
  CommandRunner(Command root, {StringSink? out})
    : _out = out ?? stdout,
      _root = _Node.declare(root, 'good', null, out ?? stdout);

  final _Node _root;
  final StringSink _out;

  /// Where help is written. Injectable so a test can read it back instead of
  /// letting it out onto the terminal.
  StringSink get out => _out;

  Future<void> run(List<String> args) async {
    final leaf = _dispatch(_root, args);

    // Help wins, and is checked **before** parsing. Someone typing `--help` is
    // asking what the arguments are; answering "missing required argument
    // <input>" would be refusing the question with the very information they
    // asked for. Checked along the whole path, so `good --help compile` works
    // as well as `good compile --help`.
    for (_Node? at = leaf; at != null; at = at.parent) {
      if (at.pending.contains('--help') || at.pending.contains('-h')) {
        leaf.printUsage();
        return;
      }
    }

    // Every node on the path parses its **own** slice, not just the leaf. That
    // is what makes `good --verbose compile windows` put `--verbose` on the
    // root where it was declared, and it is why a parent's arguments are
    // readable through `findAncestor` while a child executes: they were
    // genuinely parsed, not inherited.
    for (_Node? at = leaf; at != null; at = at.parent) {
      at.parseOwn();
    }
    // The **whole tree** is bound, not just the selected path, so `selected`
    // is a total question: a sibling that was not chosen answers `false`
    // rather than throwing. `good compile` asking `windows.selected` is an
    // ordinary thing to do and must not be an error. Reading a *value* off an
    // unselected command still fails loudly, because there genuinely is none.
    _root.bindTree();
    leaf.markSelected();
    await leaf.command.execute();
  }

  /// The usage block for the command at [path], or the root's when [path] does
  /// not resolve - an error deep in the tree still prints something useful.
  String usageFor(List<String> path) {
    var node = _root;
    for (var i = 1; i < path.length; i++) {
      final child = node.children[path[i]];
      if (child == null) break;
      node = child;
    }
    return node.usage();
  }

  /// Splits [args] across the command path, returning the selected leaf.
  ///
  /// Each node keeps the tokens that belong to *it* - everything up to the
  /// subcommand name that selected its child - and the child gets everything
  /// after. So options are read by the command that declared them, wherever on
  /// the line they were written.
  ///
  /// **Spec-aware, deliberately.** `good compile --input-dir windows` must pass
  /// `windows` to `--input-dir`, not descend into a `windows` subcommand.
  /// Deciding that needs to know whether the preceding option takes a value,
  /// which is exactly what the declaration pass already established - so
  /// dispatch consults it rather than guessing from the token's shape.
  _Node _dispatch(_Node node, List<String> args) {
    final own = <String>[];
    for (var i = 0; i < args.length; i++) {
      final token = args[i];
      if (token == '--') {
        // Past the escape, nothing is a subcommand name.
        own.addAll(args.sublist(i));
        break;
      }
      if (token.startsWith('--')) {
        own.add(token);
        final body = token.substring(2);
        if (!body.contains('=')) {
          final spec = node.namedSpec(body);
          if (spec != null &&
              spec.kind != _Kind.flag &&
              i + 1 < args.length &&
              !args[i + 1].startsWith('-')) {
            own.add(args[++i]);
          }
        }
        continue;
      }
      if (token.startsWith('-')) {
        own.add(token);
        continue;
      }
      final child = node.children[token];
      if (child == null) {
        // A positional. Everything from here belongs to this command - a
        // subcommand name appearing after one is a value, not a command.
        own.addAll(args.sublist(i));
        break;
      }
      node.pending = own;
      return _dispatch(child, args.sublist(i + 1));
    }
    node.pending = own;
    return node;
  }
}

/// One command in the tree: its declarations, its children, and this run's
/// values.
class _Node implements CommandBinding, CommandSession {
  _Node._(this.command, this.name, this.parent, this.out);

  factory _Node.declare(
    Command command,
    String name,
    _Node? parent,
    StringSink out,
  ) {
    final node = _Node._(command, name, parent, out);
    command.describeCommand(_Descriptor(node));
    return node;
  }

  final StringSink out;

  @override
  final Command command;
  final String name;
  @override
  final _Node? parent;

  final Map<String, _Node> children = <String, _Node>{};
  final Map<String, String> childDescriptions = <String, String>{};

  /// Every declaration, in declaration order - which is also the order
  /// consumers are filled in and the order help lists them.
  final List<_Spec<Object?>> specs = <_Spec<Object?>>[];

  final Map<_Spec<Object?>, List<Object?>> _values =
      <_Spec<Object?>, List<Object?>>{};

  bool _selected = false;

  /// The tokens dispatch assigned to this node - its own slice of the command
  /// line, with subcommand names removed.
  List<String> pending = const <String>[];

  @override
  bool get selected => _selected;

  @override
  CommandSession get session => this;

  @override
  List<String> get path => <String>[if (parent != null) ...parent!.path, name];

  void bindTree() {
    command.bind(this);
    for (final child in children.values) {
      child.bindTree();
    }
  }

  void markSelected() => _selected = true;

  @override
  List<T> valuesOf<T>(Arg<T> arg) {
    final spec = (arg as _Handle<T>).spec;
    final values = _values[spec];
    if (values == null) {
      throw StateError(
        'The argument "--${spec.name}" was read before this command ran. An '
        'Arg is a declaration; it only has a value once CommandRunner has '
        'parsed a command line into it.',
      );
    }
    return values.cast<T>();
  }

  // --- parsing ------------------------------------------------------------

  void parseOwn() => parse(pending);

  void parse(List<String> args) {
    final raw = <_Spec<Object?>, List<String>>{};
    final positionals = <String>[];
    var literal = false;

    for (var i = 0; i < args.length; i++) {
      final token = args[i];
      if (literal) {
        positionals.add(token);
        continue;
      }
      if (token == '--') {
        // Everything after it is positional, however it is spelled. The escape
        // hatch for a path that starts with a dash.
        literal = true;
        continue;
      }
      if (!token.startsWith('--')) {
        positionals.add(token);
        continue;
      }

      final body = token.substring(2);
      final eq = body.indexOf('=');
      final name = eq == -1 ? body : body.substring(0, eq);
      final inline = eq == -1 ? null : body.substring(eq + 1);
      final spec = _named(name);
      if (spec == null) {
        throw UsageException('Unknown option "--$name".', path);
      }
      if (spec.kind == _Kind.flag) {
        if (inline != null) {
          throw UsageException(
            '"--$name" is a flag and takes no value, but got "=$inline". '
            'Write "--$name" to turn it on and leave it out to turn it off.',
            path,
          );
        }
        raw.putIfAbsent(spec, () => <String>[]).add('true');
        continue;
      }
      String value;
      if (inline != null) {
        value = inline;
      } else if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
        value = args[++i];
      } else {
        // Bare `--arg` hands the parser an empty string rather than erroring:
        // an argument whose parser accepts "" is a legitimate design, and one
        // whose parser does not will say so itself, in its own words.
        value = '';
      }
      final bucket = raw.putIfAbsent(spec, () => <String>[]);
      if (!spec.multi && bucket.isNotEmpty) {
        throw UsageException(
          '"--$name" was given more than once. It takes a single value; '
          'declare it with describeMultiArg if it should repeat.',
          path,
        );
      }
      bucket.add(value);
    }

    _fillPositionals(raw, positionals);
    _resolve(raw);
  }

  /// Consumers first, in declaration order; whatever is left goes to the
  /// remaining declaration if there is one.
  void _fillPositionals(
    Map<_Spec<Object?>, List<String>> raw,
    List<String> positionals,
  ) {
    var next = 0;
    for (final spec in specs) {
      if (spec.kind != _Kind.consumer) continue;
      if (next >= positionals.length) break;
      raw[spec] = <String>[positionals[next++]];
    }
    final leftover = positionals.sublist(next);
    final remaining = specs
        .where((s) => s.kind == _Kind.remaining)
        .cast<_Spec<Object?>?>()
        .firstWhere((_) => true, orElse: () => null);
    if (remaining != null) {
      // Joined with single spaces, per the declared semantics: the remainder
      // is one string, not a list.
      if (leftover.isNotEmpty) raw[remaining] = <String>[leftover.join(' ')];
    } else if (leftover.isNotEmpty) {
      throw UsageException(
        'Unexpected argument "${leftover.first}". This command takes '
        '${specs.where((s) => s.kind == _Kind.consumer).length} positional '
        'argument(s).',
        path,
      );
    }
  }

  void _resolve(Map<_Spec<Object?>, List<String>> raw) {
    for (final spec in specs) {
      final tokens = raw[spec];
      if (tokens == null || tokens.isEmpty) {
        if (!spec.optional && !spec.hasDefault) {
          throw UsageException(
            spec.kind == _Kind.consumer || spec.kind == _Kind.remaining
                ? 'Missing required argument <${spec.name}>.'
                : 'Missing required option "--${spec.name}".',
            path,
          );
        }
        _values[spec] = spec.hasDefault
            ? <Object?>[spec.defaultValue]
            : <Object?>[if (!spec.multi) null];
        continue;
      }
      final parsed = <Object?>[];
      for (final token in tokens) {
        try {
          parsed.add(spec.parse(token));
        } on ArgumentError catch (error) {
          // The parser's own message, which is why `parsers.dart` throws
          // ArgumentError rather than returning null - it is the one place
          // that knows what was wrong with the value.
          throw UsageException(
            'Invalid value for "${spec.display}": ${error.message}',
            path,
          );
        }
      }
      _values[spec] = parsed;
    }
  }

  /// The named declaration called [name], or null. Used by dispatch to tell
  /// `--opt value` from `--flag subcommand`.
  _Spec<Object?>? namedSpec(String name) => _named(name);

  _Spec<Object?>? _named(String name) {
    for (final spec in specs) {
      if (spec.name != name) continue;
      if (spec.kind == _Kind.consumer || spec.kind == _Kind.remaining) continue;
      return spec;
    }
    return null;
  }

  // --- help ---------------------------------------------------------------

  @override
  void printUsage() => out.writeln(usage());

  String usage() {
    final buffer = StringBuffer();
    final line = StringBuffer('Usage: ${path.join(' ')}');
    if (children.isNotEmpty) line.write(' <command>');
    // Unconditional: `--help` is always available, so there are always
    // options, even for a command that declares none of its own.
    line.write(' [options]');
    for (final spec in specs) {
      if (spec.kind == _Kind.consumer || spec.kind == _Kind.remaining) {
        line.write(' ${spec.display}');
      }
    }
    buffer.writeln(line);

    if (children.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Commands:');
      final width = children.keys
          .map((k) => k.length)
          .fold<int>(0, (a, b) => a > b ? a : b);
      for (final entry in children.entries) {
        buffer.writeln(
          '  ${entry.key.padRight(width)}  ${childDescriptions[entry.key]}',
        );
      }
    }

    final options = specs.where((s) => s.kind != _Kind.consumer).toList();
    buffer.writeln();
    buffer.writeln('Options:');
    // `--help` is listed even though no command declares it: it is handled by
    // the runner for every command, and an option that works but is not
    // documented is one nobody finds.
    final rows = <String, String>{
      '--help': 'Show this help and exit.',
      for (final spec in options) spec.optionLabel: spec.description,
    };
    final width = rows.keys
        .map((k) => k.length)
        .fold<int>(0, (a, b) => a > b ? a : b);
    for (final row in rows.entries) {
      buffer.writeln('  ${row.key.padRight(width)}  ${row.value}');
    }

    final consumers = specs.where((s) => s.kind == _Kind.consumer).toList();
    if (consumers.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Arguments:');
      final width = consumers
          .map((s) => s.display.length)
          .fold<int>(0, (a, b) => a > b ? a : b);
      for (final spec in consumers) {
        buffer.writeln(
          '  ${spec.display.padRight(width)}  ${spec.description}',
        );
      }
    }
    return buffer.toString().trimRight();
  }
}

enum _Kind { arg, flag, consumer, remaining }

/// One declared argument: how its token is found, how the token becomes a
/// value, and how it is written in help.
class _Spec<T> {
  _Spec({
    required this.name,
    required this.description,
    required this.kind,
    required this.parse,
    required this.optional,
    required this.multi,
    required this.hasDefault,
    required this.defaultValue,
    this.choices,
  });

  final String name;
  final String description;
  final _Kind kind;
  final T Function(String) parse;
  final bool optional;
  final bool multi;

  /// Distinct from `defaultValue != null`: a nullable argument's default
  /// legitimately *is* null, and "absent, so null" has to be tellable from
  /// "absent, and required".
  final bool hasDefault;
  final T? defaultValue;
  final List<String>? choices;

  /// How a positional is written in help: `<name>` required, `[name]`
  /// optional, `[name=default]` when it has one.
  String get display {
    if (kind == _Kind.arg || kind == _Kind.flag) return '--$name';
    if (!optional && !hasDefault) return '<$name>';
    if (hasDefault) return '[$name=${_show(defaultValue)}]';
    return '[$name]';
  }

  String get optionLabel {
    if (kind == _Kind.flag) return '--$name';
    final choices = this.choices;
    final value = choices == null ? name : choices.join('|');
    if (hasDefault) return '--$name=<$value> [${_show(defaultValue)}]';
    return '--$name=<$value>';
  }

  /// How a default reads in help.
  ///
  /// An enum shows its name rather than `TargetPlatform.windows`, and a path
  /// shows the path rather than `File: '.'` - `toString` on those types is
  /// built for a debugger, and help is read by someone deciding what to type.
  static String _show(Object? value) => switch (value) {
    Enum() => value.name,
    FileSystemEntity() => value.path,
    _ => '$value',
  };
}

/// The `Arg`/`MultiArg` a declaration hands back: a name for a [_Spec] plus
/// the node to read this run's value out of. Holds no value of its own, which
/// is what lets one declaration be re-run.
class _Handle<T> implements Arg<T>, MultiArg<T> {
  _Handle(this.spec, this._node);

  final _Spec<Object?> spec;
  final _Node _node;

  @override
  CommandSession get session => _node;

  @override
  bool get optional => spec.optional;

  @override
  T get value => _node.valuesOf<T>(this).first;

  @override
  T operator [](int index) => _node.valuesOf<T>(this)[index];

  @override
  int get length => _node.valuesOf<T>(this).length;
}

class _Descriptor implements CommandDescriptor {
  _Descriptor(this._node);

  final _Node _node;

  _Handle<T> _add<T>(_Spec<T> spec) {
    if (spec.kind == _Kind.remaining &&
        _node.specs.any((s) => s.kind == _Kind.remaining)) {
      throw StateError(
        '${_node.command.runtimeType} declares a second "remaining" argument '
        '("${spec.name}"). Only one can exist: the first would leave nothing '
        'for the second to collect.',
      );
    }
    if (spec.kind != _Kind.consumer &&
        spec.kind != _Kind.remaining &&
        _node.specs.any(
          (s) =>
              s.name == spec.name &&
              s.kind != _Kind.consumer &&
              s.kind != _Kind.remaining,
        )) {
      throw StateError(
        '${_node.command.runtimeType} declares "--${spec.name}" twice.',
      );
    }
    _node.specs.add(spec as _Spec<Object?>);
    return _Handle<T>(spec as _Spec<Object?>, _node);
  }

  @override
  T describeSubCommand<T extends Command>(
    String name,
    String description,
    T commandHandler,
  ) {
    if (_node.children.containsKey(name)) {
      throw StateError(
        '${_node.command.runtimeType} declares a "$name" subcommand twice.',
      );
    }
    _node.children[name] = _Node.declare(
      commandHandler,
      name,
      _node,
      _node.out,
    );
    _node.childDescriptions[name] = description;
    return commandHandler;
  }

  @override
  Arg<T> describeArg<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
    required T defaultValue,
  }) => _add(
    _Spec<T>(
      name: name,
      description: description,
      kind: _Kind.arg,
      parse: parser,
      optional: false,
      multi: false,
      hasDefault: true,
      defaultValue: defaultValue,
    ),
  );

  @override
  Arg<T?> describeOptionalArg<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
  }) => _add(
    _Spec<T?>(
      name: name,
      description: description,
      kind: _Kind.arg,
      parse: parser,
      optional: true,
      multi: false,
      hasDefault: false,
      defaultValue: null,
    ),
  );

  @override
  MultiArg<T> describeMultiArg<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
    required T defaultValue,
  }) => _add(
    _Spec<T>(
      name: name,
      description: description,
      kind: _Kind.arg,
      parse: parser,
      optional: false,
      multi: true,
      hasDefault: true,
      defaultValue: defaultValue,
    ),
  );

  @override
  MultiArg<T> describeOptionalMultiArg<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
  }) => _add(
    _Spec<T>(
      name: name,
      description: description,
      kind: _Kind.arg,
      parse: parser,
      optional: true,
      multi: true,
      hasDefault: false,
      defaultValue: null,
    ),
  );

  @override
  Arg<bool> describeFlag({
    required String name,
    required String description,
    bool defaultValue = false,
  }) => _add(
    _Spec<bool>(
      name: name,
      description: description,
      kind: _Kind.flag,
      parse: (_) => true,
      optional: false,
      multi: false,
      hasDefault: true,
      defaultValue: defaultValue,
    ),
  );

  _Spec<T> _option<T extends Enum>(
    String name,
    String description,
    List<T> choices,
    bool optional,
    bool multi,
    bool hasDefault,
    T? defaultValue,
  ) => _Spec<T>(
    name: name,
    description: description,
    kind: _Kind.arg,
    parse: (value) {
      for (final choice in choices) {
        if (choice.name == value) return choice;
      }
      throw ArgumentError(
        '"$value" is not one of ${choices.map((c) => c.name).join(', ')}.',
      );
    },
    optional: optional,
    multi: multi,
    hasDefault: hasDefault,
    defaultValue: defaultValue,
    choices: <String>[for (final choice in choices) choice.name],
  );

  @override
  Arg<T> describeOption<T extends Enum>({
    required String name,
    required String description,
    required List<T> choices,
    required T defaultValue,
  }) => _add(
    _option(name, description, choices, false, false, true, defaultValue),
  );

  @override
  Arg<T?> describeOptionalOption<T extends Enum>({
    required String name,
    required String description,
    required List<T> choices,
  }) => _add(
    _option<T>(name, description, choices, true, false, false, null)
        as _Spec<T?>,
  );

  @override
  MultiArg<T> describeMultiOption<T extends Enum>({
    required String name,
    required String description,
    required List<T> choices,
    required T defaultValue,
  }) => _add(
    _option(name, description, choices, false, true, true, defaultValue),
  );

  @override
  MultiArg<T> describeOptionalMultiOption<T extends Enum>({
    required String name,
    required String description,
    required List<T> choices,
  }) => _add(_option<T>(name, description, choices, true, true, false, null));

  @override
  Arg<T> describeConsumer<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
    required T defaultValue,
  }) => _add(
    _Spec<T>(
      name: name,
      description: description,
      kind: _Kind.consumer,
      parse: parser,
      optional: false,
      multi: false,
      hasDefault: true,
      defaultValue: defaultValue,
    ),
  );

  @override
  Arg<T?> describeOptionalConsumer<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
  }) => _add(
    _Spec<T?>(
      name: name,
      description: description,
      kind: _Kind.consumer,
      parse: parser,
      optional: true,
      multi: false,
      hasDefault: false,
      defaultValue: null,
    ),
  );

  @override
  Arg<T> describeRemaining<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
    required T defaultValue,
  }) => _add(
    _Spec<T>(
      name: name,
      description: description,
      kind: _Kind.remaining,
      parse: parser,
      optional: false,
      multi: false,
      hasDefault: true,
      defaultValue: defaultValue,
    ),
  );

  @override
  Arg<T?> describeOptionalRemaining<T>({
    required String name,
    required String description,
    required ArgumentParser<T> parser,
  }) => _add(
    _Spec<T?>(
      name: name,
      description: description,
      kind: _Kind.remaining,
      parse: parser,
      optional: true,
      multi: false,
      hasDefault: false,
      defaultValue: null,
    ),
  );
}
