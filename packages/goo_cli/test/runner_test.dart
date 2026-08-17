import 'package:goo_cli/src/command.dart';
import 'package:goo_cli/src/runner.dart';
import 'package:goo_cli/src/verbosable.dart';
import 'package:test/test.dart';

// The command framework: does a command line become the values a command
// declared, does dispatch pick the right command, and does a malformed line
// fail by saying what was wrong rather than by guessing.
//
// Driven through `CommandRunner` directly rather than through `runCommand`,
// which writes to stderr and returns an exit code - the parse result is the
// subject here, not the process plumbing.

String _identity(String value) => value;

int _int(String value) {
  final parsed = int.tryParse(value);
  if (parsed == null) throw ArgumentError('"$value" is not a whole number.');
  return parsed;
}

enum _Colour { red, green, blue }

/// Records that it ran, so "did the right command execute" is observable
/// rather than inferred.
class _Spy extends Command {
  int runs = 0;

  @override
  void execute() => runs++;
}

class _Args extends _Spy {
  late final Arg<String> name;
  late final Arg<String?> nickname;
  late final Arg<bool> loud;
  late final Arg<_Colour> colour;
  late final Arg<int> count;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    name = descriptor.describeArg(
      name: 'name',
      description: 'A name.',
      parser: _identity,
      defaultValue: 'anon',
    );
    nickname = descriptor.describeOptionalArg(
      name: 'nickname',
      description: 'An optional name.',
      parser: _identity,
    );
    loud = descriptor.describeFlag(name: 'loud', description: 'Shout.');
    colour = descriptor.describeOption(
      name: 'colour',
      description: 'A colour.',
      choices: _Colour.values,
      defaultValue: _Colour.red,
    );
    count = descriptor.describeArg(
      name: 'count',
      description: 'How many.',
      parser: _int,
      defaultValue: 1,
    );
  }
}

class _Positionals extends _Spy {
  late final Arg<String> first;
  late final Arg<String?> second;
  late final Arg<String?> rest;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    // `rest` is declared *between* the consumers on purpose: the remainder is
    // order-insensitive, so where it appears in the declaration must not
    // change what it collects.
    first = descriptor.describeConsumer(
      name: 'first',
      description: 'First positional.',
      parser: _identity,
      defaultValue: 'one',
    );
    rest = descriptor.describeOptionalRemaining(
      name: 'rest',
      description: 'Everything else.',
      parser: _identity,
    );
    second = descriptor.describeOptionalConsumer(
      name: 'second',
      description: 'Second positional.',
      parser: _identity,
    );
  }
}

class _Required extends _Spy {
  late final Arg<String?> target;
  late final Arg<String?> mode;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    target = descriptor.describeOptionalConsumer(
      name: 'target',
      description: 'Required-ish.',
      parser: _identity,
    );
    mode = descriptor.describeOptionalArg(
      name: 'mode',
      description: 'Optional.',
      parser: _identity,
    );
  }
}

class _Multi extends _Spy {
  late final MultiArg<String> define;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    define = descriptor.describeOptionalMultiArg(
      name: 'define',
      description: 'Repeatable.',
      parser: _identity,
    );
  }
}

class _Leaf extends _Spy with Verbose {
  late final Arg<String> which;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    super.describeCommand(descriptor);
    which = descriptor.describeArg(
      name: 'which',
      description: 'Which one.',
      parser: _identity,
      defaultValue: 'none',
    );
  }
}

class _Middle extends _Spy {
  late final _Leaf leaf;
  late final Arg<bool> middleFlag;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    middleFlag = descriptor.describeFlag(
      name: 'middle-flag',
      description: 'On the middle command.',
    );
    leaf = descriptor.describeSubCommand('leaf', 'The leaf.', _Leaf());
  }
}

class _Root extends _Spy {
  late final _Middle middle;
  late final _Args args;
  late final _Positionals positionals;
  late final _Required required;
  late final _Multi multi;
  late final Arg<bool> rootFlag;

  @override
  void describeCommand(CommandDescriptor descriptor) {
    rootFlag = descriptor.describeFlag(
      name: 'root-flag',
      description: 'On the root.',
    );
    middle = descriptor.describeSubCommand('middle', 'Middle.', _Middle());
    args = descriptor.describeSubCommand('args', 'Args.', _Args());
    positionals = descriptor.describeSubCommand(
      'positionals',
      'Positionals.',
      _Positionals(),
    );
    required = descriptor.describeSubCommand('req', 'Required.', _Required());
    multi = descriptor.describeSubCommand('multi', 'Multi.', _Multi());
  }
}

/// Builds a fresh tree per test - a `Command` holds one run's binding, so
/// sharing one across tests would let an earlier run answer a later one.
({_Root root, CommandRunner runner, StringBuffer help}) _tree() {
  final root = _Root();
  // Help goes to a buffer, not the terminal: a test that asserts on usage
  // should read it, and one that merely triggers it should not print it.
  final help = StringBuffer();
  return (root: root, runner: CommandRunner(root, out: help), help: help);
}

void main() {
  group('named arguments', () {
    test('--arg=value, --arg value and bare --arg are all accepted', () async {
      final a = _tree();
      await a.runner.run(['args', '--name=inline']);
      expect(a.root.args.name.value, 'inline');

      final b = _tree();
      await b.runner.run(['args', '--name', 'separate']);
      expect(b.root.args.name.value, 'separate');

      final c = _tree();
      await c.runner.run(['args', '--name']);
      expect(
        c.root.args.name.value,
        '',
        reason:
            'a bare --arg hands the parser an empty string rather than '
            'erroring - a parser that rejects "" will say so in its own words, '
            'and one that accepts it is a legitimate design',
      );
    });

    test('an absent argument falls back to its declared default', () async {
      final t = _tree();
      await t.runner.run(['args']);
      expect(t.root.args.name.value, 'anon');
      expect(t.root.args.count.value, 1);
      expect(t.root.args.colour.value, _Colour.red);
    });

    test('an absent optional argument is null, not a default', () async {
      final t = _tree();
      await t.runner.run(['args']);
      expect(t.root.args.nickname.value, isNull);
      expect(t.root.args.nickname.optional, isTrue);
    });

    test('a flag is false when absent and true when present', () async {
      final absent = _tree();
      await absent.runner.run(['args']);
      expect(absent.root.args.loud.value, isFalse);

      final present = _tree();
      await present.runner.run(['args', '--loud']);
      expect(present.root.args.loud.value, isTrue);
    });

    test('a flag refuses a value rather than silently taking one', () async {
      final t = _tree();
      await expectLater(
        () => t.runner.run(['args', '--loud=yes']),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('takes no value'),
          ),
        ),
      );
    });

    test('a flag does not swallow the token after it', () async {
      // The trap: `--loud red` must leave `red` to the positional machinery,
      // not consume it as the flag's value.
      final t = _tree();
      await expectLater(
        () => t.runner.run(['args', '--loud', 'red']),
        throwsA(isA<UsageException>()),
        reason: '_Args declares no consumers, so `red` is genuinely unexpected',
      );
    });

    test(
      'an option accepts a choice by name and rejects anything else',
      () async {
        final good = _tree();
        await good.runner.run(['args', '--colour=green']);
        expect(good.root.args.colour.value, _Colour.green);

        final bad = _tree();
        await expectLater(
          () => bad.runner.run(['args', '--colour=puce']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              allOf(contains('puce'), contains('red, green, blue')),
            ),
          ),
          reason: 'naming the valid choices is the whole value of the message',
        );
      },
    );

    test(
      "a parser's own ArgumentError becomes the user-facing message",
      () async {
        final t = _tree();
        await expectLater(
          () => t.runner.run(['args', '--count=lots']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('not a whole number'),
            ),
          ),
          reason:
              'the parser is the only thing that knows what was wrong with the '
              'value, which is why parsers throw ArgumentError rather than '
              'returning null',
        );
      },
    );

    test('an unknown option is refused by name', () async {
      final t = _tree();
      await expectLater(
        () => t.runner.run(['args', '--nope']),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('--nope'),
          ),
        ),
      );
    });

    test('a single-valued argument given twice is refused', () async {
      final t = _tree();
      await expectLater(
        () => t.runner.run(['args', '--name=a', '--name=b']),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('more than once'),
          ),
        ),
        reason:
            'silently keeping the first or the last would make one of two '
            'plausible readings wrong with no way to tell',
      );
    });
  });

  group('repeatable arguments', () {
    test('collects every occurrence, in order', () async {
      final t = _tree();
      await t.runner.run([
        'multi',
        '--define=a',
        '--define',
        'b',
        '--define=c',
      ]);
      final define = t.root.multi.define;
      expect(define.length, 3);
      expect([define[0], define[1], define[2]], ['a', 'b', 'c']);
    });

    test('an absent optional multi is empty rather than a default', () async {
      final t = _tree();
      await t.runner.run(['multi']);
      expect(t.root.multi.define.length, 0);
    });
  });

  group('positionals', () {
    test('consumers fill in declaration order', () async {
      final t = _tree();
      await t.runner.run(['positionals', 'alpha', 'beta']);
      expect(t.root.positionals.first.value, 'alpha');
      expect(t.root.positionals.second.value, 'beta');
    });

    test('the remainder collects what the consumers did not take', () async {
      final t = _tree();
      await t.runner.run(['positionals', 'alpha', 'beta', 'gamma', 'delta']);
      expect(
        t.root.positionals.rest.value,
        'gamma delta',
        reason:
            'the remainder is one string joined with single spaces, not a '
            'list - that is the declared semantic',
      );
    });

    test(
      'where the remainder is declared does not change what it takes',
      () async {
        // `rest` is declared *between* the two consumers in `_Positionals`. If
        // declaration order mattered it would have eaten `beta`.
        final t = _tree();
        await t.runner.run(['positionals', 'alpha', 'beta', 'gamma']);
        expect(t.root.positionals.first.value, 'alpha');
        expect(t.root.positionals.second.value, 'beta');
        expect(t.root.positionals.rest.value, 'gamma');
      },
    );

    test('an absent optional consumer is null', () async {
      final t = _tree();
      await t.runner.run(['positionals', 'alpha']);
      expect(t.root.positionals.second.value, isNull);
      expect(t.root.positionals.rest.value, isNull);
    });

    test(
      'a consumer with a default uses it when nothing is supplied',
      () async {
        final t = _tree();
        await t.runner.run(['positionals']);
        expect(t.root.positionals.first.value, 'one');
      },
    );

    test(
      'an unexpected positional is refused when nothing can take it',
      () async {
        final t = _tree();
        await expectLater(
          () => t.runner.run(['req', 'a', 'b']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('Unexpected argument "b"'),
            ),
          ),
          reason:
              '_Required declares one consumer and no remainder, so the second '
              'token has nowhere to go - dropping it would lose a user\'s input',
        );
      },
    );

    test('-- ends option parsing, so a dashed value survives', () async {
      final t = _tree();
      await t.runner.run(['positionals', '--', '--not-an-option']);
      expect(t.root.positionals.first.value, '--not-an-option');
    });
  });

  group('dispatch', () {
    test('the selected command is the one that executes', () async {
      final t = _tree();
      await t.runner.run(['middle', 'leaf']);
      expect(t.root.middle.leaf.runs, 1);
      expect(t.root.middle.runs, 0);
      expect(t.root.runs, 0);
    });

    test('a command with no subcommand named executes itself', () async {
      final t = _tree();
      await t.runner.run(['middle']);
      expect(t.root.middle.runs, 1);
      expect(t.root.middle.leaf.runs, 0);
    });

    test('selected is a total question, false for a sibling', () async {
      final t = _tree();
      await t.runner.run(['middle', 'leaf']);
      expect(t.root.middle.leaf.selected, isTrue);
      expect(
        t.root.middle.selected,
        isFalse,
        reason:
            'a command on the path to the selected one has not itself been '
            'selected - and asking must not throw, because `goo compile` '
            'checking `windows.selected` is an ordinary thing to do',
      );
      expect(t.root.args.selected, isFalse, reason: 'an untouched sibling');
    });

    test(
      'each command parses the options it declared, wherever they sit',
      () async {
        final t = _tree();
        await t.runner.run([
          '--root-flag',
          'middle',
          '--middle-flag',
          'leaf',
          '--verbose',
        ]);
        expect(t.root.rootFlag.value, isTrue);
        expect(t.root.middle.middleFlag.value, isTrue);
        expect(t.root.middle.leaf.verbose.value, isTrue);
        expect(t.root.middle.leaf.runs, 1);
      },
    );

    test('an option value is not mistaken for a subcommand name', () async {
      // The sharp case: `leaf` is a real subcommand of `middle`, and here it
      // is also the value of `--which`. Telling those apart needs the
      // declaration, not the token's shape.
      final t = _tree();
      await t.runner.run(['middle', 'leaf', '--which', 'leaf']);
      expect(t.root.middle.leaf.which.value, 'leaf');
      expect(t.root.middle.leaf.runs, 1);
    });

    test(
      'findAncestor reaches a parent command, and stops at the root',
      () async {
        final t = _tree();
        await t.runner.run(['middle', 'leaf']);
        expect(t.root.middle.leaf.findAncestor<_Middle>(), same(t.root.middle));
        expect(t.root.middle.leaf.findAncestor<_Root>(), same(t.root));
        expect(
          () => t.root.middle.leaf.findAncestor<_Args>(),
          throwsStateError,
          reason: '_Args is a sibling branch, deliberately not reachable',
        );
      },
    );

    test('parent is the declaring command, and the root has none', () async {
      final t = _tree();
      await t.runner.run(['middle', 'leaf']);
      expect(t.root.middle.leaf.parent, same(t.root.middle));
      expect(() => t.root.parent, throwsStateError);
    });
  });

  group('help', () {
    test('--help prints usage instead of executing', () async {
      final t = _tree();
      await t.runner.run(['middle', 'leaf', '--help']);
      expect(
        t.root.middle.leaf.runs,
        0,
        reason: 'asking what a command does must not do it',
      );
    });

    test('--help answers even when a required argument is missing', () async {
      final t = _tree();
      await expectLater(
        () => t.runner.run(['req', '--help']),
        returnsNormally,
        reason:
            'answering "missing required argument" to someone asking what the '
            'arguments are refuses the question with the answer to it',
      );
    });

    test('--help prints the *selected* command usage, not the root', () async {
      final t = _tree();
      await t.runner.run(['middle', 'leaf', '--help']);
      expect(t.help.toString(), contains('goo middle leaf'));
      expect(
        t.help.toString(),
        contains('--which'),
        reason: "the leaf's own options, not its parent's",
      );
      expect(t.help.toString(), isNot(contains('--root-flag')));
    });

    test(
      '--help before the subcommand still describes the subcommand',
      () async {
        final t = _tree();
        await t.runner.run(['--help', 'middle', 'leaf']);
        expect(
          t.help.toString(),
          contains('goo middle leaf'),
          reason:
              'the whole path is checked, so where --help sits on the line does '
              'not change which command it is asking about',
        );
      },
    );

    test(
      'usage spells required, optional and defaulted positionals apart',
      () async {
        final t = _tree();
        final usage = t.runner.usageFor(['goo', 'positionals']);
        expect(usage, contains('[first=one]'), reason: 'defaulted');
        expect(usage, contains('[second]'), reason: 'optional, no default');
      },
    );

    test('usage lists subcommands and options, --help included', () async {
      final t = _tree();
      final usage = t.runner.usageFor(['goo']);
      expect(usage, contains('middle'));
      expect(usage, contains('Middle.'));
      expect(
        usage,
        contains('--help'),
        reason:
            'the runner handles it for every command, and an option that '
            'works but is undocumented is one nobody finds',
      );
    });

    test('an option shows its choices and its default', () async {
      final t = _tree();
      final usage = t.runner.usageFor(['goo', 'args']);
      expect(usage, contains('--colour=<red|green|blue>'));
      expect(usage, contains('[red]'));
    });
  });

  group('declaration errors', () {
    test('a duplicate option name is refused at declare time', () async {
      expect(
        () => CommandRunner(_DuplicateOption()),
        throwsStateError,
        reason:
            'two declarations of one name make every use of it ambiguous, and '
            'declare time is when the author is looking',
      );
    });

    test('a second remainder is refused at declare time', () async {
      expect(
        () => CommandRunner(_TwoRemainders()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('nothing for the second to collect'),
          ),
        ),
      );
    });

    test('a duplicate subcommand name is refused at declare time', () async {
      expect(() => CommandRunner(_DuplicateSub()), throwsStateError);
    });
  });

  group('reading outside a run', () {
    test(
      'a value read before running says so, rather than defaulting',
      () async {
        final root = _Root();
        CommandRunner(root); // declared, never run
        expect(
          () => root.rootFlag.value,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('before this command ran'),
            ),
          ),
        );
      },
    );
  });

  group('printf', () {
    test('substitutes %s in order', () async {
      expect(formatMessage('%s -> %s', ['a', 'b']), 'a -> b');
    });

    test(
      'leaves a %s with no argument visible rather than dropping it',
      () async {
        expect(
          formatMessage('%s and %s', ['only']),
          'only and %s',
          reason: 'a silently dropped placeholder hides the bug that caused it',
        );
      },
    );

    test('a format with no placeholders is passed through', () async {
      expect(formatMessage('plain', ['unused']), 'plain');
    });
  });
}

class _DuplicateOption extends Command {
  @override
  void describeCommand(CommandDescriptor descriptor) {
    descriptor.describeFlag(name: 'same', description: 'One.');
    descriptor.describeFlag(name: 'same', description: 'Two.');
  }
}

class _TwoRemainders extends Command {
  @override
  void describeCommand(CommandDescriptor descriptor) {
    descriptor.describeOptionalRemaining(
      name: 'a',
      description: 'One.',
      parser: _identity,
    );
    descriptor.describeOptionalRemaining(
      name: 'b',
      description: 'Two.',
      parser: _identity,
    );
  }
}

class _DuplicateSub extends Command {
  @override
  void describeCommand(CommandDescriptor descriptor) {
    descriptor.describeSubCommand('x', 'One.', _Spy());
    descriptor.describeSubCommand('x', 'Two.', _Spy());
  }
}
