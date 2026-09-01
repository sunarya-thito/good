import 'dart:io';

// ignore: implementation_imports
import 'package:good_cli/src/generate/struct_scan.dart';
import 'package:good_tool/src/component_emit.dart';
import 'package:good_tool/src/component_scan.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:good_tool/src/imports.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '_repo.dart';

// What gets a build-time bit, and what is left to the run-time registry (#18).
//
// The distinction this turns on is not "is it a component". It is "does some
// `describeType` in this repository call `has<T>()` on it" - because those are
// exactly the types `ComponentTypeRegistry.bitFor` is called with, and a table
// over any other set would be a numbering with the same name and different
// contents. A mixin on `Component` that registers nothing has no bit here, and
// a bit for it would be one of sixty-four spent on a type no signature carries.

/// A mixin that registers itself, which is what almost every one does.
String _mixin(String name) =>
    '''
import 'package:good/good.dart';

mixin $name on Component {
  final ${name.toLowerCase()}Value = Field.float64();

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<$name>();
  }
}
''';

/// A repository: the kernel, and one package holding [files].
Directory _repo(Map<String, String> files, {String name = 'goo2d'}) =>
    fakeRepo(<FakePackage>[
      componentKernel(),
      FakePackage(name, dependencies: const <String>['good'], files: files),
    ]);

List<String> _types(ComponentBitScan scan) =>
    <String>[for (final bit in scan.bits) bit.type];

String _emit(Directory repo, String package) {
  final packages = enginePackages(repo);
  final sources = readSources(
    repo,
    rootOverride: <String>[for (final target in packages) target.libDir],
  );
  final scan = scanComponentBits(repo, packages: packages, sources: sources);
  final imports = Imports(
    declaredIn: declaredIn(sources),
    byLibDir: <String, EnginePackage>{
      for (final target in packages) target.libDir: target,
    },
    units: sources.units,
    packages: packages,
  );
  final file = componentBitsFiles(scan, packages, imports).singleWhere(
    (candidate) => candidate.file.path.contains(
      '${p.separator}$package${p.separator}',
    ),
    orElse: () => fail('no table written for $package'),
  );
  return file.contents;
}

void main() {
  group('a bit is generated', () {
    test('for every type a describeType names, ordered so a diff is stable', () {
      final scan = scanComponentBits(
        _repo(<String, String>{
          'goo2d.dart':
              "export 'src/transform.dart';\nexport 'src/render.dart';\n",
          // Two files, and the second sorts first, so an order taken from the
          // filesystem would come out the other way round on somebody's
          // machine.
          'src/transform.dart': _mixin('Transform2D'),
          'src/render.dart': _mixin('Renderable2D'),
        }),
      );
      expect(_types(scan), <String>['Renderable2D', 'Transform2D']);
      expect(scan.bits.first.package, 'goo2d');
      expect(scan.bits.first.sortKey, 'src/render.dart');
      expect(scan.bits.first.import, 'package:goo2d/src/render.dart');
    });

    test('for two types one file declares, by name', () {
      final scan = scanComponentBits(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/data.dart';\n",
          'src/data.dart':
              '''
import 'package:good/good.dart';

mixin Zeta on Component {
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Zeta>();
  }
}

mixin Alpha on Component {
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Alpha>();
  }
}
''',
        }),
      );
      expect(_types(scan), <String>['Alpha', 'Zeta']);
    });

    test('and not for a component mixin that registers nothing', () {
      // `CollisionListener`'s shape: a mixin on `Component`, subject to every
      // other rule about component mixins, that never reaches `has<T>()`. A
      // table built from "is a component mixin" would hold it, and the bit
      // would be spent on a type no archetype signature ever carries.
      final scan = scanComponentBits(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/data.dart';\n",
          'src/data.dart':
              '''
import 'package:good/good.dart';

mixin Transform2D on Component {
  final transformOffsetX = Field.float64();

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Transform2D>();
  }
}

mixin CollisionListener on Component {
  void onCollision() {}
}
''',
        }),
      );
      expect(_types(scan), <String>['Transform2D']);
    });

    test('and not for has(type: runtimeType), which only a run knows', () {
      final scan = scanComponentBits(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/data.dart';\n",
          'src/data.dart':
              '''
import 'package:good/good.dart';

class Prefab implements Component {
  void describeType(ComponentDescriptor component) {
    component.has(type: runtimeType);
  }
}
''',
        }),
      );
      expect(_types(scan), isEmpty);
      expect(scan.skipped, isEmpty);
    });
  });

  group('no bit, and the run-time registry keeps the type', () {
    test('when two libraries both declare the name', () {
      final scan = scanComponentBits(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/one.dart';\n",
          'src/one.dart': _mixin('Velocity'),
          'src/two.dart': _mixin('Velocity'),
        }),
      );
      expect(_types(scan), isEmpty);
      expect(
        scan.skipped['Velocity'],
        contains('declared in more than one library'),
      );
    });

    test('when nothing this pass reads declares it at all', () {
      final scan = scanComponentBits(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/data.dart';\n",
          'src/data.dart':
              '''
import 'package:good/good.dart';

mixin Transform2D on Component {
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Transform2D>();
    component.has<FromSomewhereElse>();
  }
}
''',
        }),
      );
      expect(_types(scan), <String>['Transform2D']);
      expect(
        scan.skipped['FromSomewhereElse'],
        contains('not declared in any package this pass reads'),
      );
    });

    test('when it is declared in a package that is never published', () {
      final repo = fakeRepo(<FakePackage>[
        componentKernel(),
        const FakePackage(
          'internal',
          published: false,
          dependencies: <String>['good'],
          files: <String, String>{'internal.dart': _hiddenMixin},
        ),
        FakePackage(
          'goo2d',
          dependencies: const <String>['good', 'internal'],
          files: <String, String>{
            'goo2d.dart': "export 'src/data.dart';\n",
            'src/data.dart':
                '''
import 'package:good/good.dart';
import 'package:internal/internal.dart';

mixin Transform2D on Component {
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Transform2D>();
    component.has<Hidden>();
  }
}
''',
          },
        ),
      ]);
      // Read with the unpublished package's `lib/` in the roots, which is what
      // separates this from the case above: `Hidden` *is* declared in
      // something this pass read, and is still nowhere the tool writes. The
      // tool's own run never widens the roots that far, and the guard is here
      // because `scanComponentBits` takes a `ScanSources` from its caller.
      final scan = scanComponentBits(
        repo,
        sources: readSources(
          repo,
          rootOverride: <String>[
            for (final entry
                in Directory(p.join(repo.path, 'packages')).listSync())
              p.join(entry.path, 'lib'),
          ],
        ),
      );
      expect(_types(scan), <String>['Transform2D']);
      expect(
        scan.skipped['Hidden'],
        contains('declared outside every published package'),
      );
    });
  });

  group('the emitted table', () {
    test('names the table of each package it depends on that has one', () {
      // Three packages: the kernel, which registers nothing and so has no
      // table; `base`, which does; and `goo2d`, which depends on both. Only
      // `base` is named, because a dependency with no table has nothing to
      // seed.
      final source = _emit(
        fakeRepo(<FakePackage>[
          componentKernel(),
          FakePackage(
            'base',
            dependencies: const <String>['good'],
            files: <String, String>{
              'base.dart': "export 'src/hierarchy.dart';\n",
              'src/hierarchy.dart': _mixin('Child'),
            },
          ),
          FakePackage(
            'goo2d',
            dependencies: const <String>['good', 'base'],
            files: <String, String>{
              'goo2d.dart': "export 'src/data.dart';\n",
              'src/data.dart': _mixin('Transform2D'),
            },
          ),
        ]),
        'goo2d',
      );
      expect(source, contains("import 'package:base/base.dart';"));
      expect(
        source,
        contains(
          'dependencies: <GeneratedComponentBits>[\n    baseComponentBits,\n  ],',
        ),
      );
      expect(source, isNot(contains('goodComponentBits')));
    });

    test('names no dependency when there is nothing to depend on', () {
      // The kernel's own table. Nothing under it, so the field is left out
      // rather than written empty.
      final source = _emit(
        fakeRepo(<FakePackage>[
          FakePackage(
            'good',
            files: <String, String>{
              'good.dart':
                  "export 'src/struct.dart';\n"
                  "export 'src/data.dart';\n"
                  "export 'src/archetype.dart';\n"
                  "export 'src/hierarchy.dart';\n",
              'src/struct.dart': kernelStruct,
              'src/data.dart': kernelData,
              'src/archetype.dart': kernelArchetype,
              'src/hierarchy.dart':
                  '''
import 'struct.dart';
import 'archetype.dart';

mixin Child on Component {
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Child>();
  }
}
''',
            },
          ),
        ]),
        'good',
      );
      expect(source, contains('package: \'good\','));
      expect(source, contains('types: <Type>[\n    Child,\n  ],'));
      expect(source, isNot(contains('dependencies:')));
      // Its own package by file, never through its own entry library.
      expect(source, contains("import 'package:good/src/hierarchy.dart';"));
    });
  });

  group('the ceiling', () {
    test('is the one archetype.dart declares', () {
      // Written down in `component_scan.dart` because this tool cannot import
      // a Flutter package. Read back out of the engine's source here, so
      // widening the signature cannot leave the tool behind - which would let
      // it write a table the registry then refuses.
      final source = File(
        p.join('..', 'good', 'lib', 'src', 'archetype.dart'),
      ).readAsStringSync();
      final match = RegExp(
        r'static const int maxComponentTypes = (\d+);',
      ).firstMatch(source);
      expect(match, isNotNull, reason: 'maxComponentTypes moved or was renamed');
      expect(int.parse(match!.group(1)!), maxComponentTypes);
    });

    test('names every type competing for the last bit', () {
      final scan = ComponentBitScan(
        bits: <ComponentBit>[
          for (var i = 0; i < 3; i++)
            ComponentBit(
              type: 'Component$i',
              package: 'goo2d',
              sortKey: 'src/c$i.dart',
              import: 'package:goo2d/src/c$i.dart',
            ),
        ],
        skipped: const <String, String>{},
      );
      final message = componentBitCeilingMessage(scan, 2);
      expect(message, contains('has 3 entries and a query signature holds 2'));
      for (var i = 0; i < 3; i++) {
        expect(message, contains('$i  Component$i - goo2d/lib/src/c$i.dart'));
      }
    });
  });
}

const String _hiddenMixin = '''
import 'package:good/good.dart';

mixin Hidden on Component {
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Hidden>();
  }
}
''';
