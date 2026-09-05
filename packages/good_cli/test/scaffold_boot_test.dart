@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:good_cli/src/generate/scaffold.dart';
import 'package:test/test.dart';

import '_scaffolded.dart';

// Whether a scaffolded project **runs** - asked by running it.
//
// # Why nothing else here could answer this
//
// Every generation gate in this repository walks `packages/*`, and a user's
// project is outside all of them: `good_tool` refuses `publish_to: none` and
// every `flutter create` app declares it, so a project is not a directory that
// tool will look at. The suites over `good create` asserted on template text,
// and `scaffold_analyze_test` resolved the names in it. None of that reaches
// the one question a new project asks first, which is whether it starts.
//
// It did not. A scaffolded project threw
// `Bad state: No generated collector for WalkgameGame` from `Game.start`,
// because nothing wrote the declaration collectors for the classes a project's
// own author writes and nothing named them to `Game.declarations` - and no
// gate anywhere could have said so, because each one measures something else.
//
// # Why it is `flutter test` in a subprocess
//
// `Game.start` spawns the simulation isolate and the engine is built on
// Flutter, so booting one needs a Flutter binding - which `dart test`, the
// runner this suite is under, does not have. So the assertions live in a file
// written into the project and run there, the way its author would run them.
// That also makes the boot go through a real `package:` resolution of the
// generated table rather than through this package's imports.
//
// # What it asserts, and why the tick is a separate claim from the boot
//
// `isRunning` says the boot got through registration, which is what a missing
// collector stops. The tick says the simulation isolate is still alive a
// moment later, which is a different failure: a declaration held by a private
// field reaches no collector, so the query it declared never resolves, and
// `_ArchetypeQuery.matches` fails an assertion on the first fixed tick. The
// boot succeeds in that case. The 3D scaffold shipped exactly it.

/// The `flutter` executable, found the way `asset_entry_test` finds the SDK.
String _flutter() {
  final name = Platform.isWindows ? 'flutter.bat' : 'flutter';
  for (final root in _candidateRoots()) {
    final file = File('$root/bin/$name');
    if (file.existsSync()) return file.path;
  }
  fail(
    'No Flutter SDK found, so a scaffolded project cannot be run. Set '
    'FLUTTER_ROOT, or put `flutter` on PATH.',
  );
}

Iterable<String> _candidateRoots() sync* {
  final declared = Platform.environment['FLUTTER_ROOT'];
  if (declared != null && declared.isNotEmpty) yield declared;

  // A Dart from inside a Flutter SDK sits at <root>/bin/cache/dart-sdk/bin/.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    yield dir.path;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }

  final path = Platform.environment['PATH'] ?? '';
  for (final entry in path.split(Platform.isWindows ? ';' : ':')) {
    if (entry.isEmpty) continue;
    for (final name in const <String>['flutter', 'flutter.bat']) {
      if (File('$entry/$name').existsSync()) {
        yield Directory('$entry/..').absolute.path;
      }
    }
  }
}

/// The test written into the project: start the game, and watch it tick.
///
/// `runAsync` for the reason the scaffold's own widget test gives - `pump`
/// advances fake time and `Game.start` spawns a real isolate, so a pumped
/// clock never waits for one.
String _bootTest(String name, String engine, String gameClass) =>
    '''
import 'package:flutter_test/flutter_test.dart';
import 'package:$engine/$engine.dart';

import 'package:$name/game/${name}_game.dart';

void main() {
  testWidgets('the game boots and the simulation runs', (tester) async {
    late $gameClass game;
    await tester.runAsync(() async {
      game = await Game.start($gameClass.new);
    });
    expect(game.isRunning, isTrue, reason: 'Game.start returned a dead game');

    // The boot can succeed and the simulation still stop on its first fixed
    // tick, so this is a second claim and not a restatement of the first.
    final first = game.tick;
    for (var i = 0; i < 100 && game.tick <= first; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    expect(
      game.tick,
      greaterThan(first),
      reason: 'the game booted and then stopped ticking',
    );

    await tester.runAsync(() => game.stop());
  });
}
''';

void main() {
  for (final engine in GoodEngine.values) {
    test('a scaffolded ${engine.package} project boots and ticks', () async {
      // Nothing here ends in `_game`, so the scaffolded file is
      // `lib/game/<name>_game.dart` and the class is `<Name>Game` - see
      // `_gameFile` and `_gameClass`, which take the other branch for a
      // project already called one.
      final name = '${engine.package}_boot_probe';
      final dir = await scaffoldProject(name: name, engine: engine);

      final gameClass =
          '${name.split('_').map((word) => word[0].toUpperCase() + word.substring(1)).join()}Game';
      File(
        '${dir.path}/test/boot_test.dart',
      ).writeAsStringSync(_bootTest(name, engine.package, gameClass));

      // `--no-pub`, because the project is resolved by the config
      // `scaffoldProject` wrote and a `pub get` would try to fetch an engine
      // version that is not published yet.
      final result = Process.runSync(_flutter(), <String>[
        'test',
        '--no-pub',
        'test/boot_test.dart',
      ], workingDirectory: dir.path, runInShell: true);
      expect(
        result.exitCode,
        0,
        reason:
            'a project `good create` writes has to start before its author has '
            'touched it:\n${result.stdout}${result.stderr}',
      );
    });
  }
}
