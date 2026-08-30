@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:good_cli/src/commands/create.dart';
import 'package:good_cli/src/generate/bundle.dart';
import 'package:good_cli/src/generate/scaffold.dart';
import 'package:good_cli/src/runner.dart';
import 'package:test/test.dart';

import '_cli.dart';
import '_temp.dart';

// Who owns the files `good create` writes over.
//
// The command has two modes and they disagree on purpose. It ran `flutter
// create` itself into a directory it refused to touch if it already existed,
// so everything there is `flutter create`'s output and replacing it is
// correct - that is #27, where the counter app at lib/main.dart was skipped as
// "existing" and the good main.dart was never written at all. A project
// reached through --no-flutter-create belongs to somebody, and nothing in it
// is replaced.
//
// The `flutter create` half needs a Flutter SDK and is covered by generating a
// real project; what is here is the half that can do damage.

Directory _existingProject({String extraDependencies = ''}) {
  final dir = testTempDir('good_create_test');
  File('${dir.path}/demo/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
name: demo

dependencies:
$extraDependencies  flutter:
    sdk: flutter

flutter:
  uses-material-design: true
''');
  return dir;
}

/// The arguments every `--no-flutter-create` run here takes.
///
/// `--no-pub-get` throughout: these projects are a pubspec in a temp
/// directory, not something `flutter pub get` could resolve.
List<String> _args(Directory parent) => <String>[
  'demo',
  '--directory=${parent.path}',
  '--no-flutter-create',
  '--no-pub-get',
];

/// Runs it with its output captured - a passing test should say nothing.
Future<void> _create(Directory parent, List<String> args) =>
    CommandRunner(CreateCommand(), out: StringBuffer()).run(args);

void main() {
  test('a file in a project it did not create is never replaced', () async {
    final parent = _existingProject();
    final main = File('${parent.path}/demo/lib/main.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// mine');

    await _create(parent, _args(parent));

    expect(
      main.readAsStringSync(),
      '// mine',
      reason:
          'silently replacing a main.dart someone has written in is the one '
          'unrecoverable thing this command could do',
    );
  });

  test('it still writes the files that are not there', () async {
    final parent = _existingProject();

    await _create(parent, _args(parent));

    expect(File('${parent.path}/demo/lib/main.dart').existsSync(), isTrue);
    expect(
      File('${parent.path}/demo/lib/game/demo_game.dart').existsSync(),
      isTrue,
    );
  });

  // What the bundle package's name already being taken looks like, and when
  // it is found out.
  //
  // Both of these refuse on the tree today as well - `runGenerate` reaches the
  // same check at the end of the command - so the exception alone says
  // nothing. What is being read here is that the project is untouched when it
  // does: a scaffolded lib/game/ and a patched pubspec are what the answer
  // costs if the question is asked last.
  group('an existing project whose bundle name is taken', () {
    test('a directory of that name good did not write stops it', () async {
      final parent = _existingProject();
      File('${parent.path}/demo/demo_bundle/pubspec.yaml')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('name: demo_bundle\n');
      final pubspec = File('${parent.path}/demo/pubspec.yaml');
      final before = pubspec.readAsStringSync();

      await expectLater(
        _create(parent, _args(parent)),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '${error.message}',
            'message',
            contains(bundleMarkerName),
          ),
        ),
      );

      expect(
        File('${parent.path}/demo/lib/game/demo_game.dart').existsSync(),
        isFalse,
        reason:
            'the scaffold is what a refusal has to come before - a project '
            'told good will not touch it, holding files good wrote',
      );
      expect(pubspec.readAsStringSync(), before);
      expect(
        File('${parent.path}/demo/demo_bundle/pubspec.yaml').readAsStringSync(),
        'name: demo_bundle\n',
      );
    });

    test('a dependency of that name pointing elsewhere stops it', () async {
      final parent = _existingProject(
        extraDependencies: '  demo_bundle: ^1.0.0\n',
      );
      final pubspec = File('${parent.path}/demo/pubspec.yaml');
      final before = pubspec.readAsStringSync();

      await expectLater(
        _create(parent, _args(parent)),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '${error.message}',
            'message',
            contains('demo_bundle'),
          ),
        ),
      );

      expect(
        File('${parent.path}/demo/lib/game/demo_game.dart').existsSync(),
        isFalse,
      );
      expect(
        pubspec.readAsStringSync(),
        before,
        reason:
            'repointing a dependency somebody else declared is what the check '
            'exists to stop, and patching the pubspec first is half of doing '
            'it',
      );
    });
  });

  test('a dry run names the bundle the project records', () {
    // Run out of process because what is being read is what the command
    // printed, and `info` writes to stdout rather than to anything the
    // in-process runner can be handed.
    final parent = _existingProject();
    final pubspec = File('${parent.path}/demo/pubspec.yaml');
    pubspec.writeAsStringSync(
      '${pubspec.readAsStringSync()}\ngood:\n  bundle: game_assets\n',
    );

    final result = GoodCli.instance.run(<String>[
      'create',
      'demo',
      '--directory=${parent.path}',
      '--no-flutter-create',
      '--dry-run',
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('game_assets'));
    expect(
      '${result.stdout}',
      isNot(contains('demo_bundle')),
      reason:
          'the name built from the argument is the one a real run would not '
          'use, so reporting it describes a different command',
    );
  });

  test('the scaffold owns the test flutter create writes', () {
    // #30. `flutter create`'s widget_test.dart builds `MyApp`, which stops
    // existing the moment main.dart is the good one, so a fresh project came
    // with a test that did not compile.
    for (final engine in GoodEngine.values) {
      final files = scaffoldFiles(
        projectName: 'demo',
        engine: engine,
        command: 'good create',
      );
      final test = files['test/widget_test.dart'];
      expect(test, isNotNull, reason: '${engine.package} has no widget test');
      expect(test, isNot(contains('MyApp')));
      expect(test, contains('const DemoApp()'));
      expect(
        test,
        contains('find.byType(GameView)'),
        reason:
            'what a new project is most likely to get wrong is building a '
            'GameView from a game that has not been started',
      );
    }
  });
}
