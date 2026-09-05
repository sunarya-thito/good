import 'dart:io';

// ignore: implementation_imports
import 'package:good_cli/src/generate/engine_package.dart';
import 'package:good_tool/src/doc_references.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '_repo.dart';

// What `--doc-references` reports and what it leaves alone (#330).
//
// The check is the thing under test, and a check with false positives gets
// switched off, so most of what is here is a shape that must pass: a name the
// package declares and the file naming it does not import, a private member, a
// constructor, an operator, a named parameter, a library prefix, a type from
// another package, and a member of a type declared outside the run. Four
// fixtures fail, and each one fails on a different part of the rule.
//
// The last group is #348: a file the parser cannot finish is named and the run
// fails, where it used to be walked for whatever recovery left behind and
// counted as read.
//
// Every fixture is a real package tree, because the scan reads pubspecs and
// walks lib/.

/// A `good` for a fixture to depend on, with [contents] as its whole `lib/`.
///
/// The names in it are the run's word list, so it carries nothing a test did
/// not put there. `kernelPackage` writes a working `Entity` and `Field`, which
/// would answer a lookup no fixture here asked about.
FakePackage _kernel([String contents = '// good\n']) =>
    FakePackage('good', files: <String, String>{'good.dart': contents});

/// A package that qualifies for the run, holding [files] under its `lib/`.
FakePackage _demo(Map<String, String> files, {String name = 'demo'}) =>
    FakePackage(name, files: files, dependencies: <String>['good']);

/// Runs the check over [packages], reporting on the ones [only] names.
///
/// [only] left out means every package in the tree is reported on, which is
/// what this repository's own invocation does.
DocReferenceScan _scan(List<FakePackage> packages, {List<String>? only}) {
  final repo = fakeRepo(packages);
  final found = enginePackages(<Directory>[
    Directory(p.join(repo.path, 'packages')),
  ]).packages;
  return scanDocReferences(
    packages: only == null
        ? found
        : <EnginePackage>[
            for (final package in found)
              if (only.contains(package.name)) package,
          ],
    known: found,
  );
}

void main() {
  group('reports', () {
    test('a reference to a name nothing writes', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
/// Hands the result to [nothingAtAll].
class Thing {}
''',
        }),
      ]);

      expect(scan.dangling, hasLength(1));
      expect(scan.dangling.single.name, 'nothingAtAll');
      expect(scan.dangling.single.reference, 'nothingAtAll');
      expect(scan.dangling.single.where, 'demo/lib/demo.dart:1');
    });

    test('a member of a type this run declares that nothing writes', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
class Thing {
  int keep = 0;
}

/// Set by [Thing.gone].
int use = 0;
''',
        }),
      ]);

      expect(scan.dangling, hasLength(1));
      expect(scan.dangling.single.name, 'gone');
      expect(scan.dangling.single.reference, 'Thing.gone');
    });

    test('a reference in the body of a primary-constructor class', () {
      // #348. Under an analyzer that does not implement the syntax the parser
      // recovers, and the doc comments hanging off the members of a class
      // whose header it could not read do not come back - so this reference
      // was never checked, and the run printed a count saying it was. That is
      // why the assertion is on a member's comment and not on the class's:
      // the class's survives recovery and would pass either way.
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
/// A ball.
class Ball({
  required final int radius,
}) {
  /// Answers against [nothingAtAll].
  int get area => radius * radius;
}
''',
        }),
      ]);

      expect(scan.unparsed, isEmpty);
      expect(scan.dangling, hasLength(1));
      expect(scan.dangling.single.name, 'nothingAtAll');
      expect(scan.dangling.single.where, 'demo/lib/demo.dart:5');
    });

    test('nothing about a package it was not pointed at', () {
      final scan = _scan(
        <FakePackage>[
          _kernel('''
/// Hands the result to [nothingAtAll].
class Kernel {}
'''),
          _demo(<String, String>{'demo.dart': 'class Thing {}\n'}),
        ],
        only: <String>['demo'],
      );

      expect(scan.dangling, isEmpty);
    });
  });

  group('passes', () {
    test('a name the package declares in a file that does not import it', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': "export 'src/elsewhere.dart';\n",
          'src/elsewhere.dart': 'class Elsewhere {}\n',
          'src/here.dart': '''
/// Built out of an [Elsewhere].
class Here {}
''',
        }),
      ]);

      expect(scan.dangling, isEmpty);
    });

    test('a private member', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
class Thing {
  int _hidden = 0;

  /// Reads [_hidden].
  int get value => _hidden;
}
''',
        }),
      ]);

      expect(scan.dangling, isEmpty);
    });

    test('a constructor', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
class Thing {
  Thing.named();

  /// Made by [Thing.named].
  int value = 0;
}
''',
        }),
      ]);

      expect(scan.dangling, isEmpty);
    });

    test('an operator, which is not an identifier at all', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
/// Neither [operator ~/] nor [Thing.operator ~/] is declared anywhere.
class Thing {}
''',
        }),
      ]);

      expect(scan.dangling, isEmpty);
      // Left alone, and not looked up and found: `~/` is written in no
      // fixture here, so a rule that read it as a name would report both.
      expect(scan.references - scan.checked, 2);
    });

    test('a named parameter', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
class Thing {
  /// Repeats itself [count] times.
  Thing({int count = 0});
}
''',
        }),
      ]);

      expect(scan.dangling, isEmpty);
    });

    test('a type from another package that the code names', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
/// Hands back a [Stopwatch].
Stopwatch make() => Stopwatch();
''',
        }),
      ]);

      expect(scan.dangling, isEmpty);
    });

    test('a member reached through a library prefix', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
import 'dart:math' as math;

/// The other one is [math.pow].
int biggest(int a, int b) => math.max(a, b);
''',
        }),
      ]);

      expect(scan.dangling, isEmpty);
    });

    test('a member of a type declared outside the packages read', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
/// Counted in [Stopwatch.elapsedTicks].
Stopwatch made = Stopwatch();
''',
        }),
      ]);

      expect(scan.dangling, isEmpty);
    });

    test('a name only another package in the run writes', () {
      final packages = <FakePackage>[
        _kernel('class Kernel {}\n'),
        _demo(<String, String>{
          'demo.dart': '''
/// Built on a [Kernel].
class Thing {}
''',
        }),
      ];

      expect(_scan(packages, only: <String>['demo']).dangling, isEmpty);

      // The same reference against the one package alone, which is what makes
      // the pass above the dependency being read and not the name being
      // skipped.
      final repo = fakeRepo(packages);
      final found = enginePackages(<Directory>[
        Directory(p.join(repo.path, 'packages')),
      ]).packages;
      final alone = <EnginePackage>[
        for (final package in found)
          if (package.name == 'demo') package,
      ];
      expect(
        scanDocReferences(packages: alone, known: alone).dangling,
        hasLength(1),
      );
    });

    test('a markdown link and a fenced block, which are not references', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
/// See [the guide](https://example.com/guide):
///
/// ```dart
/// final held = [NotAReference];
/// ```
class Thing {}
''',
        }),
      ]);

      expect(scan.dangling, isEmpty);
      expect(scan.references, 0);
    });
  });

  group('a file it cannot parse', () {
    // #348. This pass used to walk whatever the parser recovered and count the
    // references it found as the references there were. Named instead, and the
    // caller fails on it: a run that read a fraction of a file cannot say the
    // tree is clean.
    test('is named, and contributes neither references nor names', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
/// Hands the result to [Ball].
class Thing {}
''',
          'broken.dart': '''
/// A ball, in a file the parser cannot finish.
class Ball {
  int radius = 0
''',
        }),
      ], only: <String>['demo']);

      expect(scan.unparsed, <String>['demo/lib/broken.dart']);
      expect(scan.files, 1);
      // The one file that did parse is still read, and `Ball` now dangles -
      // which is what "contributes no names" means, and what separates this
      // from a skip that quietly left the word list intact.
      expect(scan.dangling.map((e) => e.name), <String>['Ball']);
    });

    test('a tree that parses names nothing', () {
      final scan = _scan(<FakePackage>[
        _kernel(),
        _demo(<String, String>{
          'demo.dart': '''
/// Hands the result to [Ball].
class Ball {}
''',
        }),
      ]);

      expect(scan.unparsed, isEmpty);
      expect(scan.dangling, isEmpty);
    });
  });
}
