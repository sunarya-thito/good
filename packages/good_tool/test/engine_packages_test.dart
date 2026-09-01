import 'dart:convert';
import 'dart:io';

import 'package:good_tool/src/engine_packages.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '_repo.dart';

// Which directories the tool generates into (#305).
//
// It used to be `<root>/packages/`, hardcoded, so a standalone package's run
// found nothing and exited reporting success; and `good_cli`'s half of the same
// question was `name == 'good' || name.startsWith('goo')`, which reads
// `google_fonts` as an engine package and walks its `lib/` on every generate.
// Both are answered here: where to look is an argument, and what to take is a
// dependency on the engine.
//
// Every fixture is a real directory tree with real pubspecs, because every one
// of these decisions is read off a filesystem.

/// Writes one package under [parent].
Directory _package(
  Directory parent,
  String name, {
  List<String> dependencies = const <String>[],
  List<String> devDependencies = const <String>[],
  bool published = true,
  bool hasLib = true,
}) {
  final root = Directory(p.join(parent.path, name))..createSync(recursive: true);
  final lines = <String>[
    'name: $name',
    if (!published) 'publish_to: none',
    '',
    'environment:',
    '  sdk: ^3.12.1',
    '',
    'dependencies:',
    for (final dependency in dependencies) '  $dependency: ^1.0.0',
    '',
    'dev_dependencies:',
    for (final dependency in devDependencies) '  $dependency: ^1.0.0',
    '',
  ];
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(lines.join('\n'));
  if (hasLib) {
    File(p.join(root.path, 'lib', '$name.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// $name\n');
  }
  return root;
}

/// Points [package]'s package config at [resolves], the way a `pub get` would.
void _resolve(Directory package, List<Directory> resolves) {
  File(p.join(package.path, '.dart_tool', 'package_config.json'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          for (final resolved in resolves)
            <String, Object?>{
              'name': p.basename(resolved.path),
              'rootUri': resolved.uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.12',
            },
        ],
      }),
    );
}

List<String> _names(PackageScan scan) =>
    <String>[for (final package in scan.packages) package.name];

void main() {
  group('a package is taken because it depends on the engine', () {
    test('directly', () {
      final dir = testTempDir('good_tool_dir');
      _package(dir, 'good');
      _package(dir, 'goo2d', dependencies: <String>['good']);

      expect(_names(enginePackages(<Directory>[dir])), <String>[
        'goo2d',
        'good',
      ]);
    });

    test('or through anything it depends on', () {
      // The case a one-hop test gets wrong, and it is not hypothetical:
      // `goo2d_physics_box2d` declares `goo2d` and `goo2d_ffi_box2d` and never
      // names `good` at all.
      final dir = testTempDir('good_tool_dir');
      _package(dir, 'good');
      _package(dir, 'goo2d', dependencies: <String>['good']);
      _package(dir, 'physics', dependencies: <String>['goo2d', 'ffi']);

      expect(_names(enginePackages(<Directory>[dir])), <String>[
        'goo2d',
        'good',
        'physics',
      ]);
    });

    test('and the engine itself counts', () {
      final dir = testTempDir('good_tool_dir');
      _package(dir, 'good');

      expect(_names(enginePackages(<Directory>[dir])), <String>['good']);
    });

    test('and a dev dependency on it is not that dependency', () {
      // A package that dev-depends on the engine to test something against it
      // ships no components: a dev dependency is not on `lib/`'s import path,
      // so nothing in `lib/` can declare one.
      final dir = testTempDir('good_tool_dir');
      _package(dir, 'good');
      _package(dir, 'tester', devDependencies: <String>['good']);

      final scan = enginePackages(<Directory>[dir]);
      expect(_names(scan), <String>['good']);
      expect(scan.rejected['tester'], contains('does not depend on'));
    });
  });

  group('a package is not taken for its name', () {
    test('google_fonts is not an engine package', () {
      // The false positive the prefix produced, and the worse half of #305:
      // `google_fonts` is in a large share of Flutter projects, and
      // `name.startsWith('goo')` had its whole `lib/` walked on every run. It
      // is here by name because it is the package this actually happened to.
      final dir = testTempDir('good_tool_dir');
      _package(dir, 'good');
      _package(dir, 'google_fonts', dependencies: <String>['http', 'crypto']);
      _package(dir, 'google_sign_in');
      _package(dir, 'googleapis');
      _package(dir, 'goodies');
      _package(dir, 'gooey');

      final scan = enginePackages(<Directory>[dir]);
      expect(
        _names(scan),
        <String>['good'],
        reason: 'five of these match the prefix that used to decide this',
      );
      expect(
        scan.rejected['google_fonts'],
        contains('does not depend on package:good'),
      );
      expect(scan.rejected, contains('gooey'));
    });

    test('and a package called something else entirely is', () {
      // The false negative, which is the smaller half but is what makes the
      // tool usable by anyone: a third-party component package follows no
      // naming convention and is not the author of this one's to coordinate.
      final dir = testTempDir('good_tool_dir');
      _package(dir, 'good');
      _package(dir, 'myco_physics', dependencies: <String>['good']);

      expect(_names(enginePackages(<Directory>[dir])), <String>[
        'good',
        'myco_physics',
      ]);
    });
  });

  group('where it looks', () {
    test('is the directory itself when that directory is the package', () {
      // `--dir .` from a third-party author's package root, which is the
      // invocation #305 exists for: their `lib/` is at the root and there is no
      // `packages/` anywhere.
      final dir = testTempDir('good_tool_dir');
      final engine = _package(dir, 'good');
      final standalone = _package(
        dir,
        'good_physics_foo',
        dependencies: <String>['goo2d'],
      );
      final renderer = _package(dir, 'goo2d', dependencies: <String>['good']);
      // Resolved from pub rather than sitting beside it, which is the whole
      // difference from a monorepo: the edge that reaches the engine leaves
      // through the package config.
      _resolve(standalone, <Directory>[renderer, engine]);

      final scan = enginePackages(<Directory>[standalone]);
      expect(_names(scan), <String>['good_physics_foo']);
    });

    test('and its immediate children, and no deeper', () {
      final dir = testTempDir('good_tool_dir');
      final packages = Directory(p.join(dir.path, 'packages'))..createSync();
      _package(packages, 'good');
      final renderer = _package(
        packages,
        'goo2d',
        dependencies: <String>['good'],
      );
      _package(renderer, 'example', dependencies: <String>['goo2d']);

      expect(
        _names(enginePackages(<Directory>[packages])),
        <String>['goo2d', 'good'],
        reason:
            'an example beneath a package is not one of the packages, and a '
            'walk that recursed would also reach every .dart_tool copy',
      );
    });

    test('is every directory given, each package once', () {
      // More than one because the component-bit table is numbered over every
      // package one run sees. Two runs over halves of a tree produce two
      // numberings, neither of which is the one the engine assigns.
      final dir = testTempDir('good_tool_dir');
      final packages = Directory(p.join(dir.path, 'packages'))..createSync();
      final plugins = Directory(p.join(dir.path, 'plugins'))..createSync();
      _package(packages, 'good');
      _package(plugins, 'goo2d', dependencies: <String>['good']);

      expect(
        _names(enginePackages(<Directory>[packages, plugins])),
        <String>['goo2d', 'good'],
      );

      // `.` reaches `packages` as a child and `packages` names it again, so
      // overlapping arguments have to collapse rather than double.
      expect(
        _names(enginePackages(<Directory>[dir, packages, plugins])),
        <String>['goo2d', 'good'],
      );
    });

    test('and a directory that is not there is not silently empty', () {
      final dir = testTempDir('good_tool_dir');
      _package(dir, 'good');

      final scan = enginePackages(<Directory>[
        dir,
        Directory(p.join(dir.path, 'nowhere')),
      ]);
      expect(_names(scan), <String>['good']);
      expect(scan.looked, hasLength(2));
    });
  });

  group('what is turned down is said', () {
    test('with the reason, per package', () {
      final dir = testTempDir('good_tool_dir');
      _package(dir, 'good');
      _package(dir, 'doc_snippets', dependencies: <String>['good'],
          published: false);
      _package(dir, 'headless', dependencies: <String>['good'], hasLib: false);
      _package(dir, 'gooey');

      final scan = enginePackages(<Directory>[dir]);
      expect(_names(scan), <String>['good']);
      expect(scan.rejected['doc_snippets'], contains('publish_to: none'));
      expect(scan.rejected['headless'], contains('has no lib/'));
      expect(scan.rejected['gooey'], contains('does not depend on'));
    });

    test('and a run that matched nothing knows what it saw', () {
      final dir = testTempDir('good_tool_dir');
      _package(dir, 'google_fonts');

      final scan = enginePackages(<Directory>[dir]);
      expect(scan.packages, isEmpty);
      expect(
        scan.rejected,
        hasLength(1),
        reason:
            'an empty run over a directory holding a package and an empty run '
            'over an empty directory are different situations',
      );
    });
  });

  test('two packages of one name are reported rather than merged', () {
    // One generated table per package name, so a run holding two of a name
    // would write one over the other and nothing downstream could tell which
    // numbering a query signature came from.
    final dir = testTempDir('good_tool_dir');
    final left = Directory(p.join(dir.path, 'left'))..createSync();
    final right = Directory(p.join(dir.path, 'right'))..createSync();
    _package(left, 'good');
    _package(left, 'goo2d', dependencies: <String>['good']);
    _package(right, 'goo2d', dependencies: <String>['good']);

    final scan = enginePackages(<Directory>[left, right]);
    expect(scan.duplicates.keys, <String>['goo2d']);
    expect(scan.duplicates['goo2d'], hasLength(2));
  });

  test('a pubspec is read as YAML, not as lines at a fixed indent', () {
    // A pubspec written by somebody else indents how it likes. A line scanner
    // that missed this block would read the package as depending on nothing,
    // which under the test above means "not an engine package" - decided
    // silently, in the direction of generating nothing.
    final dir = testTempDir('good_tool_dir');
    _package(dir, 'good');
    final odd = Directory(p.join(dir.path, 'odd'))..createSync();
    File(p.join(odd.path, 'pubspec.yaml')).writeAsStringSync(
      'name: odd\n'
      'dependencies:\n'
      '    good: ^1.0.0\n',
    );
    File(p.join(odd.path, 'lib', 'odd.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// odd\n');

    expect(_names(enginePackages(<Directory>[dir])), <String>['good', 'odd']);
  });
}
