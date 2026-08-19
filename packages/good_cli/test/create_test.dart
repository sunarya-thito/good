import 'dart:io';

import 'package:good_cli/src/commands/create.dart';
import 'package:good_cli/src/runner.dart';
import 'package:test/test.dart';

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

Directory _existingProject() {
  final dir = Directory.systemTemp.createTempSync('good_create_test');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  File('${dir.path}/demo/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
name: demo

dependencies:
  flutter:
    sdk: flutter

flutter:
  uses-material-design: true
''');
  return dir;
}

/// Runs it with its output captured - a passing test should say nothing.
Future<void> _create(Directory parent, List<String> args) =>
    CommandRunner(CreateCommand(), out: StringBuffer()).run(args);

void main() {
  test('a file in a project it did not create is never replaced', () async {
    final parent = _existingProject();
    final main = File('${parent.path}/demo/lib/main.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// mine');

    await _create(parent, <String>[
      'demo',
      '--directory=${parent.path}',
      '--no-flutter-create',
    ]);

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

    await _create(parent, <String>[
      'demo',
      '--directory=${parent.path}',
      '--no-flutter-create',
    ]);

    expect(File('${parent.path}/demo/lib/main.dart').existsSync(), isTrue);
    expect(
      File('${parent.path}/demo/lib/game/demo_game.dart').existsSync(),
      isTrue,
    );
  });
}
