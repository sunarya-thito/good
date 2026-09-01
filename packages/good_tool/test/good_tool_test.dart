import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:good_cli/src/generate/struct_scan.dart';
import 'package:good_tool/src/accessor_emit.dart';
import 'package:good_tool/src/accessor_scan.dart';
import 'package:good_tool/src/component_emit.dart';
import 'package:good_tool/src/component_scan.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:good_tool/src/imports.dart';
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
  final packages = repoPackages(repo);
  final scan = scanAccessors(packages: packages);
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
      final first = await _tool(repo, const <String>['--dir', 'packages']);
      expect(first.exitCode, 0, reason: '${first.stdout}${first.stderr}');
      expect(first.stdout, contains('Wrote goo2d/lib/src/accessors.g.dart'));
      expect(
        first.stdout,
        contains("Add `export 'src/accessors.g.dart';`"),
        reason: 'the barrel export is hand-written, so an absent one is said',
      );

      final second = await _tool(repo, const <String>['--dir', 'packages']);
      expect(second.stdout, contains('Unchanged'));
      expect(second.stdout, isNot(contains('Wrote')));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('--check fails on a missing file, then on a stale one, then passes',
        () async {
      final repo = _runnableRepo();

      final missing = await _tool(repo, const <String>['--dir', 'packages', '--check']);
      expect(missing.exitCode, 65);
      expect(missing.stderr, contains('Missing: goo2d/'));

      _generate(repo);
      final current = await _tool(repo, const <String>['--dir', 'packages', '--check']);
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
      final stale = await _tool(repo, const <String>['--dir', 'packages', '--check']);
      expect(stale.exitCode, 65);
      expect(stale.stderr, contains('Stale: goo2d/'));
      expect(stale.stderr, contains('dart run good_tool'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('--check fails when the barrel stops exporting the generated file',
        () async {
      final repo = _runnableRepo();
      _generate(repo);
      expect((await _tool(repo, const <String>['--dir', 'packages', '--check'])).exitCode, 0);

      final barrel = File(p.join(repo.path, 'packages/goo2d/lib/goo2d.dart'));
      barrel.writeAsStringSync(
        barrel.readAsStringSync().replaceAll(
          "export 'src/accessors.g.dart';\n",
          '',
        ),
      );

      final result = await _tool(repo, const <String>['--dir', 'packages', '--check']);
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
      expect((await _tool(repo, const <String>['--dir', 'packages', '--check'])).exitCode, 65);

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

      final result = await _tool(repo, const <String>['--dir', 'packages']);
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

    test('refuses a column that would shadow Entity.has', () async {
      // `has<T>()` is a member of `Entity`, so a column stripping to `has`
      // would generate a property no receiver ever reaches - an extension
      // member loses to one the type already has. The reserved list is read
      // out of the parse rather than transcribed, so this is what says the
      // new member landed in it.
      final repo = _runnableRepo();
      _write(
        repo,
        'packages/goo2d/lib/src/transform.dart',
        "import 'package:good/good.dart';\n\n"
            'mixin Marker on Component {\n'
            '  final markerHas = Field.int32();\n}\n',
      );

      final result = await _tool(repo, const <String>[]);
      expect(result.exitCode, 65);
      expect(result.stderr, contains('Marker.markerHas'));
      expect(result.stderr, contains('Entity already has has'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('rejects an argument it does not know', () async {
      final repo = _runnableRepo();
      final result = await _tool(repo, const <String>[
        '--dir',
        'packages',
        '--wrIte',
      ]);
      expect(result.exitCode, 64);
      expect(result.stderr, contains('Unknown argument'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('refuses to run with no --dir at all', () async {
      // Rather than defaulting to `packages/`, which is this repository's
      // layout and nobody else's. A default would find nothing for a
      // standalone package and report success doing it (#305).
      final repo = _runnableRepo();
      final result = await _tool(repo, const <String>[]);
      expect(result.exitCode, 64);
      expect(result.stderr, contains('--dir'));
      expect(
        result.stdout,
        isEmpty,
        reason: 'it decides nothing before it knows where to look',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('refuses a --dir naming a directory that is not there', () async {
      final repo = _runnableRepo();
      final result = await _tool(repo, const <String>['--dir', 'plugins']);
      expect(result.exitCode, 65);
      expect(result.stderr, contains('plugins'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('refuses a run that matches no package, rather than exiting 0', () async {
      // The failure this issue opens with. `enginePackages` returned an empty
      // list when there was no `packages/`, so the run wrote nothing and exited
      // reporting success - and what the author saw was their components
      // producing no accessors, with nothing to pull on.
      final repo = _runnableRepo();
      Directory(
        p.join(repo.path, 'plugins', 'gooey', 'lib'),
      ).createSync(recursive: true);
      _write(repo, 'plugins/gooey/pubspec.yaml', 'name: gooey\n');

      final result = await _tool(repo, const <String>['--dir', 'plugins']);
      expect(result.exitCode, 65, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, contains('No package to generate into'));
      expect(
        result.stderr,
        contains('gooey'),
        reason:
            'it saw a package and turned it down, which is a different thing '
            'from having seen nothing, and the run has to say which',
      );
      expect(result.stderr, contains('does not depend on package:good'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('generates into a standalone package pointed at with --dir .', () async {
      // The invocation #305 exists for. A published package cannot carry a
      // path dependency, so whatever is generated for it has to be inside its
      // own `lib/` and published with it - which means the author has to be
      // able to run this over their own package, with no `packages/` anywhere
      // and the engine resolved from pub.
      final tree = _standaloneTree();
      final mine = Directory(p.join(tree.path, 'good_physics_foo'));

      final result = await _tool(mine, const <String>['--dir', '.']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(
        result.stdout,
        contains('Wrote good_physics_foo/lib/src/accessors.g.dart'),
      );

      final written = File(p.join(mine.path, 'lib', 'src', 'accessors.g.dart'));
      expect(written.existsSync(), isTrue);
      expect(written.readAsStringSync(), contains('double get mass'));
      expect(
        written.readAsStringSync(),
        contains("import 'package:goo2d/goo2d.dart';"),
        reason:
            'the import names the package this one depends on, which is the '
            'only one a published copy of this file could reach',
      );

      final table = File(
        p.join(mine.path, 'lib', 'src', 'component_bits.g.dart'),
      );
      expect(table.existsSync(), isTrue);
      expect(
        table.readAsStringSync(),
        contains('goo2dComponentBits'),
        reason:
            'the table names the one upstream of it, which this run read and '
            'did not write - a table that named nothing would leave every '
            'goo2d type to be numbered at run time by whoever installed it',
      );

      for (final upstream in const <String>['good', 'goo2d']) {
        expect(
          Directory(p.join(tree.path, upstream, 'lib', 'src'))
              .listSync()
              .map((entry) => p.basename(entry.path)),
          isNot(contains('accessors.g.dart')),
          reason:
              '$upstream was read so its declarations could be resolved, and '
              'it generates its own files in its own run - this one has no '
              'business writing into a copy of it in a pub cache',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('this repository', () {
    // The one test that fails if somebody edits a column and forgets to
    // regenerate, run against the real packages rather than a fixture. CI runs
    // the same check as a step of its own; this puts it in the suite too, so it
    // fails on the machine that made the change.
    test('has the accessor files the generator would write', () async {
      final root = _actualRepoRoot();
      final packages = repoPackages(root);
      final scan = scanAccessors(packages: packages);

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

    // The same test for the other generated file (#18), and it carries one
    // more thing: the order below is what every bit index in the engine is,
    // so it is written out rather than derived. A regeneration that moved
    // anything fails here, in the commit that moved it, instead of arriving
    // as two peers disagreeing about what a signature meant.
    test('has the component-bit table the generator would write', () async {
      final root = _actualRepoRoot();
      final packages = repoPackages(root);
      final sources = readSources(
        root,
        rootOverride: <String>[for (final package in packages) package.libDir],
        exclude: <String>{
          for (final package in packages) package.accessorFile.path,
          for (final package in packages) package.componentBitsFile.path,
        },
      );
      final scan = scanComponentBits(packages: packages, sources: sources);
      final files = componentBitsFiles(
        scan,
        packages,
        Imports(
          declaredIn: declaredIn(sources),
          byLibDir: <String, EnginePackage>{
            for (final package in packages) package.libDir: package,
          },
          units: sources.units,
          packages: packages,
        ),
      );
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
      expect(missingComponentBitsExports(files, packages), isEmpty);

      expect(
        scan.bits.map((bit) => '${bit.package}:${bit.type}').toList(),
        <String>[
          'goo2d:Camera',
          'goo2d:Collider2D',
          'goo2d:ScreenTransform2D',
          'goo2d:Transform2D',
          'goo2d:WorldTransform2D',
          'goo2d:HoverReceiver',
          'goo2d:PointerReceiver',
          'goo2d:Renderable2D',
          'goo2d:Text2D',
          'goo2d_physics_box2d:Effector2D',
          'goo2d_physics_box2d:RigidBody2D',
          'goo3d:Camera3D',
          'goo3d:Transform3D',
          'goo3d:WorldTransform3D',
          'good:Child',
          'good:Parent',
        ],
      );
      // `CollisionListener` is a mixin on `Component` in `goo2d` that never
      // reaches `has<T>()`, so it holds no bit and spends none.
      expect(
        scan.bits.map((bit) => bit.type),
        isNot(contains('CollisionListener')),
      );
      expect(
        scan.bits.length,
        lessThan(maxComponentTypes),
        reason: 'a game needs bits of its own after these',
      );
    });
  });
}

/// A standalone package with the engine resolved beside it, not under it.
///
/// `good_physics_foo` depends on `goo2d` and `goo2d` depends on `good`, so
/// nothing here reaches the engine in one hop and nothing is inside a
/// `packages/` directory. The package config is what a `pub get` would have
/// written, and it is the only route from the package to either engine package
/// - which is the difference between this and every fixture above.
Directory _standaloneTree() {
  final tree = testTempDir('good_tool_standalone');
  void package(
    String name,
    List<String> dependencies,
    Map<String, String> files,
  ) {
    final root = p.join(tree.path, name);
    File(p.join(root, 'pubspec.yaml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        <String>[
          'name: $name',
          '',
          'environment:',
          '  sdk: ^3.12.1',
          '',
          'dependencies:',
          for (final dependency in dependencies) '  $dependency: ^1.0.0',
          '',
        ].join('\n'),
      );
    files.forEach((path, contents) {
      File(p.join(root, 'lib', path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(contents);
    });
  }

  package('good', const <String>[], <String, String>{
    'good.dart':
        "export 'src/struct.dart';\n"
        "export 'src/data.dart';\n"
        "export 'src/archetype.dart';\n",
    'src/struct.dart': kernelStruct,
    'src/data.dart': kernelData,
    'src/archetype.dart': kernelArchetype,
  });
  // Carrying a committed table of its own, the way a published engine package
  // does - which is what `good_physics_foo` names as its own table's
  // dependency, and what makes that name resolvable.
  package('goo2d', const <String>['good'], <String, String>{
    'goo2d.dart':
        "export 'package:good/good.dart';\n"
        "export 'src/transform.dart';\n"
        "export 'src/component_bits.g.dart';\n",
    'src/transform.dart':
        "import 'package:good/good.dart';\n\n"
        'mixin Transform2D on Component {\n'
        '  final transformOffsetX = Field.float64();\n\n'
        '  @override\n'
        '  void describeType(ComponentDescriptor component) {\n'
        '    component.has<Transform2D>();\n'
        '  }\n'
        '}\n',
    'src/component_bits.g.dart':
        "import 'package:good/good.dart';\n\n"
        "import 'transform.dart';\n\n"
        'const GeneratedComponentBits goo2dComponentBits = '
        'GeneratedComponentBits(\n'
        "  package: 'goo2d',\n"
        '  types: <Type>[Transform2D],\n'
        ');\n',
  });
  package('good_physics_foo', const <String>['goo2d'], <String, String>{
    'good_physics_foo.dart': "export 'src/body.dart';\n",
    'src/body.dart':
        "import 'package:goo2d/goo2d.dart';\n\n"
        'mixin Body on Component {\n'
        '  final bodyMass = Field.float64();\n\n'
        '  @override\n'
        '  void describeType(ComponentDescriptor component) {\n'
        '    component.has<Body>();\n'
        '  }\n'
        '}\n',
  });

  File(
      p.join(tree.path, 'good_physics_foo', '.dart_tool',
          'package_config.json'),
    )
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          for (final name in const <String>['good', 'goo2d'])
            <String, Object?>{
              'name': name,
              'rootUri': Directory(p.join(tree.path, name)).uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.12',
            },
        ],
      }),
    );
  return tree;
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
