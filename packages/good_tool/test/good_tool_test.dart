import 'dart:convert';
import 'dart:io';

import 'package:good_tool/src/accessor_emit.dart';
import 'package:good_tool/src/accessor_scan.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '_repo.dart';

// Whether what the tool writes compiles, reads the column it says it does, and
// stays fixed once committed - asked of the VM and of the tool's own `--check`,
// not of a string.
//
// `accessor_scan_test.dart` covers what the generator decides, and every
// assertion there is about text. Text assertions only catch the mistakes
// somebody already thought of: they cannot tell `component.transformOffsetX`
// from a line that compiles into a read of the wrong pointer, and they cannot
// tell a property that is reached from one Dart silently resolves elsewhere.

const String _transform = '''
import 'package:good/good.dart';

mixin Transform2D on Component {
  final transformOffsetX = Field.float64();
  final transformOffsetY = Field.float64();
  final transformScaleX = Field.float64(1);
  final transformVisible = Field.boolean(true);
}
''';

/// A repository whose fixture packages can be compiled and run.
///
/// The package config is written with **absolute** `rootUri`s and the
/// repository root gets no `pubspec.yaml`. Both matter: `dart run` inside a
/// package with no lockfile re-resolves, and re-resolving a pubspec that
/// declares no dependencies rewrites this config with the fixture packages
/// dropped out of it - a package the file plainly named a moment earlier is
/// then unresolved, and the failure reads as though the generated import were
/// wrong. Nothing re-resolves without a pubspec here, and the entry point is
/// run on the VM rather than through `dart run`.
Directory _runnableRepo() {
  final repo = fakeRepo(<FakePackage>[
    kernelPackage(),
    const FakePackage(
      'goo2d',
      dependencies: <String>['good'],
      files: <String, String>{
        'goo2d.dart':
            "export 'package:good/good.dart';\nexport 'src/transform.dart';\n",
        'src/transform.dart': _transform,
      },
    ),
  ]);
  final packages = <String>['good', 'goo2d'];
  File(p.join(repo.path, '.dart_tool', 'package_config.json'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          for (final name in packages)
            <String, Object?>{
              'name': name,
              'rootUri': Directory(
                p.join(repo.path, 'packages', name),
              ).uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.12',
            },
          <String, Object?>{
            'name': 'probe',
            'rootUri': repo.uri.toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.12',
          },
        ],
      }),
    );
  return repo;
}

/// Writes what the tool would write into [repo], and returns the scan.
AccessorScan _generate(Directory repo) {
  final packages = enginePackages(repo);
  final scan = scanAccessors(repo, packages: packages);
  for (final file in accessorFiles(scan, packages)) {
    file.file.parent.createSync(recursive: true);
    file.file.writeAsStringSync(file.contents);
  }
  for (final package in packages) {
    final barrel = package.barrel;
    if (!barrel.existsSync()) continue;
    if (scan.byPackage.containsKey(package.name)) {
      barrel.writeAsStringSync(
        '${barrel.readAsStringSync()}${package.accessorExport}\n',
      );
    }
  }
  return scan;
}

/// Runs [script] inside [repo] on the VM running this suite.
///
/// The VM directly, with the config named, and not `dart run` - see
/// [_runnableRepo]. `Platform.resolvedExecutable` so nothing here depends on
/// `dart` being on PATH.
Future<ProcessResult> _dart(Directory repo, String script) => Process.run(
  Platform.resolvedExecutable,
  <String>[
    '--packages=${p.join(repo.path, '.dart_tool', 'package_config.json')}',
    p.join(repo.path, script),
  ],
  workingDirectory: repo.path,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

/// Runs the tool itself, from a working directory inside [repo].
Future<ProcessResult> _tool(Directory repo, List<String> arguments) =>
    Process.run(
      Platform.resolvedExecutable,
      <String>[
        p.join(
          Directory.current.path,
          'bin',
          'good_tool.dart',
        ),
        ...arguments,
      ],
      workingDirectory: repo.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

void _write(Directory repo, String path, String contents) =>
    File(p.join(repo.path, path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(contents);

void main() {
  group('the generated file runs', () {
    test('and each property reads and writes its own column', () async {
      final repo = _runnableRepo();
      _generate(repo);

      // The three lines #99's comment verified, plus a column nothing writes.
      // A generator pointing every property at one pointer passes "offsetX
      // round-trips" and fails here twice over: offsetY would answer 20 for
      // offsetX as well, and scaleX would answer 0 rather than the 1 its own
      // column was declared with.
      _write(repo, 'bin/main.dart', '''
import 'package:goo2d/goo2d.dart';

class Player extends Prefab with Transform2D {}

void main() {
  mounted = Player();
  const e = Entity(7);
  final t = e<Transform2D>();
  t.offsetX = 10.0;
  t.offsetY = t.offsetX + 10;
  print('\${t.offsetX} \${t.offsetY} \${t.scaleX} \${t.visible}');
}
''');

      final result = await _dart(repo, 'bin/main.dart');
      expect(
        result.exitCode,
        0,
        reason:
            'the generated file did not compile:\n'
            '${result.stdout}${result.stderr}',
      );
      expect((result.stdout as String).trim(), '10.0 20.0 1.0 true');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('reached by importing the engine, with nothing else imported',
        () async {
      final repo = _runnableRepo();
      _generate(repo);

      // #300's whole point. One import of the engine package, no generated
      // library named anywhere, no tool run on the user's side.
      _write(repo, 'bin/one_import.dart', '''
import 'package:goo2d/goo2d.dart';

class Player extends Prefab with Transform2D {}

void main() {
  mounted = Player();
  print(Entity(3)<Transform2D>().scaleX);
}
''');

      final result = await _dart(repo, 'bin/one_import.dart');
      expect(
        result.exitCode,
        0,
        reason: '${result.stdout}${result.stderr}',
      );
      expect((result.stdout as String).trim(), '1.0');
    }, timeout: const Timeout(Duration(minutes: 3)));

    // The whole reason a name collision stops the tool instead of being skipped
    // with a note. Three members of one extension, identical but for their
    // names: one Dart takes from `int`, one from `Entity`, and one it has
    // nowhere else to look for. If the extension won either of the first two the
    // guard would be dead weight; if it lost the third as well, no generated
    // property would work at all.
    test('but a property whose name Accessor already has is never reached',
        () async {
      final repo = _runnableRepo();
      _generate(repo);

      _write(repo, 'bin/shadow.dart', '''
import 'package:goo2d/goo2d.dart';

extension Shadowed on Accessor<Transform2D> {
  int get sign => 42;
  int get archetypeId => 42;
  int get spin => 42;
}

void main() {
  const e = Entity(-7);
  final t = e<Transform2D>();
  print('\${t.sign} \${t.archetypeId} \${t.spin}');
}
''');

      final result = await _dart(repo, 'bin/shadow.dart');
      expect(
        result.exitCode,
        0,
        reason:
            'this has to compile - that it compiles is the problem:\n'
            '${result.stdout}${result.stderr}',
      );
      expect(
        (result.stdout as String).trim(),
        '-1 65535 42',
        reason:
            'int.sign answers first, then Entity.archetypeId, and only the '
            'name neither of them has reaches the extension. Nothing warns '
            'about the first two, which is why a column stripping to one of '
            'those names refuses the run instead of being skipped.',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('the tool', () {
    test('writes, then reports the same files unchanged', () async {
      final repo = _runnableRepo();
      final first = await _tool(repo, const <String>[]);
      expect(first.exitCode, 0, reason: '${first.stdout}${first.stderr}');
      expect(first.stdout, contains('Wrote packages/goo2d/lib/src/accessors.g.dart'));
      expect(
        first.stdout,
        contains("Add `export 'src/accessors.g.dart';`"),
        reason: 'the barrel export is hand-written, so an absent one is said',
      );

      final second = await _tool(repo, const <String>[]);
      expect(second.stdout, contains('Unchanged'));
      expect(second.stdout, isNot(contains('Wrote')));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('--check fails on a missing file, then on a stale one, then passes',
        () async {
      final repo = _runnableRepo();

      final missing = await _tool(repo, const <String>['--check']);
      expect(missing.exitCode, 65);
      expect(missing.stderr, contains('Missing: packages/goo2d'));

      _generate(repo);
      final current = await _tool(repo, const <String>['--check']);
      expect(
        current.exitCode,
        0,
        reason: '${current.stdout}${current.stderr}',
      );

      // A column added and the file not regenerated, which is the failure a
      // committed generated file actually has.
      _write(
        repo,
        'packages/goo2d/lib/src/transform.dart',
        '$_transform\nmixin Motion on Component {\n'
            '  final motionSpeed = Field.float64();\n}\n',
      );
      final stale = await _tool(repo, const <String>['--check']);
      expect(stale.exitCode, 65);
      expect(stale.stderr, contains('Stale: packages/goo2d'));
      expect(stale.stderr, contains('dart run good_tool'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('--check fails when the barrel stops exporting the generated file',
        () async {
      final repo = _runnableRepo();
      _generate(repo);
      expect((await _tool(repo, const <String>['--check'])).exitCode, 0);

      final barrel = File(p.join(repo.path, 'packages/goo2d/lib/goo2d.dart'));
      barrel.writeAsStringSync(
        barrel.readAsStringSync().replaceAll(
          "export 'src/accessors.g.dart';\n",
          '',
        ),
      );

      final result = await _tool(repo, const <String>['--check']);
      expect(result.exitCode, 65);
      expect(result.stderr, contains('Not exported'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('--check leaves the tree exactly as it found it', () async {
      final repo = _runnableRepo();
      _generate(repo);
      final file = File(
        p.join(repo.path, 'packages/goo2d/lib/src/accessors.g.dart'),
      );
      final before = file.readAsStringSync();
      final stamp = file.lastModifiedSync();

      _write(
        repo,
        'packages/goo2d/lib/src/transform.dart',
        '$_transform\nmixin Motion on Component {\n'
            '  final motionSpeed = Field.float64();\n}\n',
      );
      expect((await _tool(repo, const <String>['--check'])).exitCode, 65);

      expect(
        file.readAsStringSync(),
        before,
        reason:
            'a --check that wrote the file and then asked git whether anything '
            'moved would leave a modified working copy behind on failure',
      );
      expect(file.lastModifiedSync(), stamp);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('refuses a colliding column before it writes anything', () async {
      final repo = _runnableRepo();
      _write(
        repo,
        'packages/goo2d/lib/src/transform.dart',
        "import 'package:good/good.dart';\n\n"
            'mixin Marker on Component {\n'
            '  final markerSign = Field.int32();\n}\n',
      );

      final result = await _tool(repo, const <String>[]);
      expect(result.exitCode, 65);
      expect(result.stderr, contains('Marker.markerSign'));
      expect(result.stderr, contains('int already has sign'));
      expect(
        File(
          p.join(repo.path, 'packages/goo2d/lib/src/accessors.g.dart'),
        ).existsSync(),
        isFalse,
        reason: 'it stops before the first byte',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('rejects an argument it does not know', () async {
      final repo = _runnableRepo();
      final result = await _tool(repo, const <String>['--wrIte']);
      expect(result.exitCode, 64);
      expect(result.stderr, contains('Unknown argument'));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('this repository', () {
    // The one test that fails if somebody edits a column and forgets to
    // regenerate, run against the real packages rather than a fixture. CI runs
    // the same check as a step of its own; this puts it in the suite too, so it
    // fails on the machine that made the change.
    test('has the accessor files the generator would write', () async {
      final root = _actualRepoRoot();
      final packages = enginePackages(root);
      final scan = scanAccessors(root, packages: packages);

      expect(
        scan.collisions,
        isEmpty,
        reason: accessorCollisionMessage(scan),
      );

      final files = accessorFiles(scan, packages);
      expect(files, isNotEmpty);
      for (final file in files) {
        expect(
          file.isCurrent,
          isTrue,
          reason:
              '${file.file.path} is not what the generator would write. Run '
              '`dart run good_tool` from packages/good_tool and commit it.',
        );
      }
      expect(missingExports(files, packages), isEmpty);

      // Named, not counted. A count moves every time a column is added and says
      // nothing about which columns arrived; these are what #99 and the design
      // rules are written in terms of.
      expect(
        scan.extensions.map((e) => '${e.package}:${e.component}'),
        containsAll(<String>[
          'good:Child',
          'good:Parent',
          'goo2d:Transform2D',
          'goo2d:Camera',
          'goo2d:Text2D',
          'goo3d:Transform3D',
          'goo2d_physics_box2d:RigidBody2D',
        ]),
      );
      final transform = scan.extensions.singleWhere(
        (e) => e.component == 'Transform2D' && e.package == 'goo2d',
      );
      expect(
        transform.properties.map((e) => '${e.name} <- ${e.column}'),
        containsAll(<String>[
          'offsetX <- transformOffsetX',
          'offsetY <- transformOffsetY',
          'rotation <- transformRotation',
        ]),
      );
    });
  });
}

/// The repository this suite is running inside.
Directory _actualRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File(p.join(dir.path, 'mkdocs.yml')).existsSync() &&
        Directory(p.join(dir.path, 'packages')).existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('run this suite from inside the repository');
}
