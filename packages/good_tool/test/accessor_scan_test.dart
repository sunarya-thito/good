import 'dart:io';

import 'package:good_tool/src/accessor_emit.dart';
import 'package:good_tool/src/accessor_scan.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:test/test.dart';

import '_repo.dart';

// What the generator decides, and where it refuses.
//
// Almost everything it declines to generate is safe to decline quietly,
// because the use site then fails to compile with `The getter isn't defined`.
// Exactly one class of thing is not, and it is why there is a refusal in here
// at all: a property whose name is already a member of `Accessor`, `Entity` or
// `int` is shadowed silently and reads the entity handle instead of the
// column. `good_tool_test.dart` runs that case to show it really is silent.
//
// The rest is about where the output goes, which is what #300 moved: into
// `packages/*/lib/`, committed and shipped, so a user gets
// `entity<Transform2D>().offsetX` by importing the engine.

const String _transform = '''
import 'package:good/good.dart';

mixin Transform2D on Component {
  final transformOffsetX = Field.float64();
  final transformOffsetY = Field.float64();
  final transformScaleX = Field.float64(1);
  final transformVisible = Field.boolean(true);
}
''';

AccessorScan _scan(Directory repo) => scanAccessors(repo);

AccessorExtension _only(AccessorScan scan, String component) =>
    scan.extensions.singleWhere(
      (extension) => extension.component == component,
      orElse: () => fail(
        'no extension for $component; got '
        '${scan.extensions.map((e) => e.component).toList()}',
      ),
    );

String _emit(AccessorScan scan, String package) => emitAccessors(
  scan.byPackage[package] ?? const <AccessorExtension>[],
  package: package,
);

/// A two-package repository: the kernel, and one package holding [files].
Directory _repo(Map<String, String> files, {String name = 'goo2d'}) =>
    fakeRepo(<FakePackage>[
      kernelPackage(),
      FakePackage(name, dependencies: const <String>['good'], files: files),
    ]);

void main() {
  group('a property is generated per column', () {
    test('with the column name, its type, and the component prefix gone', () {
      final scan = _scan(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/transform.dart';\n",
          'src/transform.dart': _transform,
        }),
      );

      final transform = _only(scan, 'Transform2D');
      expect(
        transform.properties.map((e) => '${e.type} ${e.name} <- ${e.column}'),
        <String>[
          'double offsetX <- transformOffsetX',
          'double offsetY <- transformOffsetY',
          'double scaleX <- transformScaleX',
          'bool visible <- transformVisible',
        ],
      );
      expect(transform.package, 'goo2d');
    });

    // The one a round-trip cannot catch. A generator emitting the first column
    // for every property passes "offsetX round-trips" - it reads back what it
    // wrote, through the wrong pointer.
    test('each property names its own column, not a shared one', () {
      final scan = _scan(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/transform.dart';\n",
          'src/transform.dart': _transform,
        }),
      );

      final columns = _only(
        scan,
        'Transform2D',
      ).properties.map((e) => e.column).toList();
      expect(columns.toSet(), hasLength(columns.length));

      // And the same of the text, because the model above is only half of it -
      // an emitter taking `properties.first.column` for every line would leave
      // the scan correct and the file wrong.
      final source = _emit(scan, 'goo2d');
      for (final property in _only(scan, 'Transform2D').properties) {
        expect(
          source,
          contains(
            '${property.type} get ${property.name} => '
            'component.${property.column}[entity];',
          ),
        );
      }
      expect(
        RegExp(
          r'component\.transformOffsetX\[entity\]',
        ).allMatches(source).length,
        2,
        reason: 'one getter and one setter reach this column, and nothing else',
      );
    });

    test('one extension per component, and none per prefab', () {
      final scan = _scan(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/transform.dart';\n",
          'src/transform.dart':
              '$_transform\nclass Player extends Prefab with Transform2D {}\n',
        }),
      );

      expect(
        scan.extensions.map((e) => e.component),
        <String>['Transform2D'],
        reason:
            'a prefab needs none of its own - Accessor<Player> is a subtype '
            'of Accessor<Transform2D>, so the component extension applies',
      );
      expect(_only(scan, 'Transform2D').extensionName, r'Accessor$Transform2D');
    });
  });

  group('the property name', () {
    // The rule reads one column and its component's name, and nothing else.
    // Pinned here because a sibling-derived rule renames every property of a
    // component the day an eleventh column joins it - and these names are
    // shipped API now, not regenerated per project.
    test('drops a component prefix only when the column carries one', () {
      expect(accessorPropertyName('Transform2D', 'transformOffsetX'), 'offsetX');
      expect(accessorPropertyName('Child', 'childParent'), 'parent');
      expect(accessorPropertyName('Text2D', 'textZIndex'), 'zIndex');

      // #99's body names this pair: `bodyHandle` on `RigidBody2D` is not
      // `handle`-by-prefix, it only reads that way. Left as declared.
      expect(accessorPropertyName('RigidBody2D', 'bodyType'), 'bodyType');
      expect(accessorPropertyName('WorldTransform2D', 'worldX'), 'worldX');
    });

    test('needs a camel-case boundary, so a word is never cut in half', () {
      expect(accessorPropertyName('Parent', 'parenthood'), 'parenthood');
      expect(accessorPropertyName('Parent', 'parent'), 'parent');
    });

    test("does not depend on the component's other columns", () {
      expect(<String>[
        accessorPropertyName('Motion', 'speed'),
        accessorPropertyName('Motion', 'spin'),
      ], <String>['speed', 'spin']);
    });
  });

  group('a name something already answers to stops the tool', () {
    AccessorScan scanWith(String body, {String extra = ''}) => _scan(
      _repo(<String, String>{
        'goo2d.dart': "export 'src/marker.dart';\n",
        'src/marker.dart':
            "import 'package:good/good.dart';\n\n"
            'mixin Marker on Component {\n$body}\n$extra',
      }),
    );

    test('for a member of int, naming the column and what shadows it', () {
      final scan = scanWith(
        '  final markerSign = Field.int32();\n'
        '  final markerSpin = Field.float64();\n',
      );

      expect(scan.collisions, hasLength(1));
      final hit = scan.collisions.single;
      expect(hit.column, 'markerSign');
      expect(hit.property, 'sign');
      expect(hit.owner, 'int');
      expect(hit.file, 'goo2d/lib/src/marker.dart');

      // The discriminating half. `markerSpin` strips to `spin`, which nothing
      // has, so the check has to let it through - a guard refusing the whole
      // component would pass the assertion above for the wrong reason.
      expect(_only(scan, 'Marker').properties.single.name, 'spin');

      final message = accessorCollisionMessage(scan);
      expect(message, contains('Marker.markerSign'));
      expect(message, contains('int already has sign'));
    });

    test('for a member of Entity, read out of the parse', () {
      final hit = scanWith(
        '  final markerArchetypeId = Field.int32();\n',
      ).collisions.single;
      expect(hit.property, 'archetypeId');
      expect(
        hit.owner,
        'Entity',
        reason:
            'archetypeId is not an int member and is written down nowhere in '
            'this package - it can only have come from parsing Entity',
      );
    });

    test('for a member of Accessor', () {
      final hit = scanWith(
        '  final markerComponent = Field.int32();\n',
      ).collisions.single;
      expect(hit.property, 'component');
      expect(hit.owner, 'Accessor');
    });

    // New with #300. The properties ship now, so a generated name clashing
    // with one of the engine's five hand-written accessor extensions is an
    // ambiguity error in released code, raised nowhere near the column that
    // caused it. It found a real one on the first run against this repository:
    // Parent.parentFirstChild and ParentAccessor.firstChild.
    test('for a member of a hand-written extension on the same accessor', () {
      final hit = scanWith(
        '  final markerDepth = Field.int32();\n',
        extra:
            '\nextension MarkerAccessor on Accessor<Marker> {\n'
            '  int get depth => 0;\n'
            '}\n',
      ).collisions.single;
      expect(hit.property, 'depth');
      expect(hit.owner, 'a hand-written extension on Accessor<Marker>');
    });

    test('when two columns of one component strip to the same name', () {
      final hit = scanWith(
        '  final markerDepth = Field.int32();\n'
        '  final depth = Field.int32();\n',
      ).collisions.single;
      expect(hit.property, 'depth');
      expect(hit.owner, 'Marker.markerDepth');
    });
  });

  group('what is skipped instead, because the use site fails loudly', () {
    test('a component in a package that is never published', () {
      final scan = _scan(
        fakeRepo(<FakePackage>[
          kernelPackage(),
          const FakePackage(
            'doc_snippets',
            published: false,
            dependencies: <String>['good'],
            files: <String, String>{
              'doc_snippets.dart': "export 'src/transform.dart';\n",
              'src/transform.dart': _transform,
            },
          ),
        ]),
      );

      expect(
        scan.extensions,
        isEmpty,
        reason:
            'a package a user cannot install is not one to generate shipped '
            'code into - and doc_snippets holds components extracted from the '
            'documentation itself',
      );
    });

    test('a private column', () {
      final scan = _scan(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/world.dart';\n",
          'src/world.dart':
              "import 'package:good/good.dart';\n\n"
              'mixin WorldTransform2D on Component {\n'
              '  final worldX = Field.float64();\n'
              '  final _cachedX = Field.float64();\n'
              '}\n',
        }),
      );

      expect(
        _only(scan, 'WorldTransform2D').properties.map((e) => e.name),
        <String>['worldX'],
      );
      expect(scan.skipped['WorldTransform2D._cachedX'], contains('private'));
    });

    test('an array column, which has no column[entity] to read', () {
      final scan = _scan(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/text.dart';\n",
          'src/text.dart':
              "import 'package:good/good.dart';\n\n"
              'mixin Text2D on Component {\n'
              '  final textLength = Field.int32();\n'
              '  final textCells = Field.array(0, 4);\n'
              '  late final DataArrayPointer<int> textCodeUnits;\n'
              '}\n',
        }),
      );

      expect(_only(scan, 'Text2D').properties.map((e) => e.name), <String>[
        'length',
      ]);
      expect(scan.skipped['Text2D.textCells'], isNotNull);
      expect(scan.skipped['Text2D.textCodeUnits'], isNotNull);
    });

    test('a column whose type nothing in the repository declares', () {
      final scan = _scan(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/camera.dart';\n",
          'src/camera.dart':
              "import 'package:good/good.dart';\n\n"
              'mixin Camera on Component {\n'
              '  final cameraZoom = Field.float64();\n'
              '  late final DataPointer<CameraView?> cameraView;\n'
              '}\n',
        }),
      );

      expect(_only(scan, 'Camera').properties.map((e) => e.name), <String>[
        'zoom',
      ]);
      expect(scan.skipped['Camera.cameraView'], contains('CameraView'));
    });

    test('a component name two libraries both declare', () {
      final scan = _scan(
        fakeRepo(<FakePackage>[
          kernelPackage(),
          const FakePackage(
            'goo2d',
            dependencies: <String>['good'],
            files: <String, String>{
              'goo2d.dart': "export 'src/transform.dart';\n",
              'src/transform.dart': _transform,
            },
          ),
          const FakePackage(
            'goo3d',
            dependencies: <String>['good'],
            files: <String, String>{
              'goo3d.dart': "export 'src/transform.dart';\n",
              'src/transform.dart': _transform,
            },
          ),
        ]),
      );

      expect(scan.extensions, isEmpty);
      expect(scan.skipped['Transform2D'], contains('more than one library'));
    });
  });

  group('the import a generated file writes', () {
    test('names its own package by file, and another by its entry library', () {
      final scan = _scan(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/camera.dart';\n",
          'src/camera.dart':
              "import 'package:good/good.dart';\n\n"
              'mixin Camera on Component {\n'
              '  final cameraOwner = Field.optEntity();\n'
              '}\n',
        }),
      );

      expect(_only(scan, 'Camera').imports, <String>{
        // Its own package: the file, the way every hand-written file under
        // goo2d/lib/src spells it.
        'package:goo2d/src/camera.dart',
        // Another package: the entry library. Reaching into `good/src` would
        // compile and then trip `implementation_imports`, which CI fails on.
        'package:good/good.dart',
      });
    });

    test('reaches a re-export through a package it does depend on', () {
      // `goo2d_physics_box2d` depends on `goo2d` and not on `good`, and it
      // needs `Accessor`, which `good` declares and `goo2d` re-exports. This is
      // the real shape: rigid_body.dart imports `package:goo2d/goo2d.dart` and
      // so must the file generated beside it.
      final scan = _scan(
        fakeRepo(<FakePackage>[
          kernelPackage(),
          const FakePackage(
            'goo2d',
            dependencies: <String>['good'],
            files: <String, String>{'goo2d.dart': "export 'package:good/good.dart';\n"},
          ),
          const FakePackage(
            'physics',
            dependencies: <String>['goo2d'],
            files: <String, String>{
              'physics.dart': "export 'src/body.dart';\n",
              'src/body.dart':
                  "import 'package:goo2d/goo2d.dart';\n\n"
                  'mixin RigidBody2D on Component {\n'
                  '  final bodyAwake = Field.boolean();\n'
                  '}\n',
            },
          ),
        ]),
      );

      expect(_only(scan, 'RigidBody2D').imports, <String>{
        'package:physics/src/body.dart',
        'package:goo2d/goo2d.dart',
      });
    });

    test('and skips the component when nothing it depends on exports the name',
        () {
      final scan = _scan(
        fakeRepo(<FakePackage>[
          kernelPackage(),
          // Depends on nothing, so `Accessor` is unreachable from it however
          // the source is written.
          const FakePackage(
            'stranded',
            files: <String, String>{
              'stranded.dart': "export 'src/body.dart';\n",
              'src/body.dart':
                  "import 'package:good/good.dart';\n\n"
                  'mixin Stray on Component {\n'
                  '  final strayAwake = Field.boolean();\n'
                  '}\n',
            },
          ),
        ]),
      );

      expect(scan.extensions, isEmpty);
      expect(scan.skipped['Stray'], contains('Accessor'));
    });

    // An `import` is not an `export`. Following one would claim a generated
    // file can name a type its own imports do not reach.
    test('never through a barrel that only imports the name', () {
      final scan = _scan(
        fakeRepo(<FakePackage>[
          kernelPackage(),
          const FakePackage(
            'goo2d',
            dependencies: <String>['good'],
            // Imports the kernel rather than exporting it, so `Accessor` is not
            // in this package's namespace.
            files: <String, String>{
              'goo2d.dart': "import 'package:good/good.dart';\n",
            },
          ),
          const FakePackage(
            'physics',
            dependencies: <String>['goo2d'],
            files: <String, String>{
              'physics.dart': "export 'src/body.dart';\n",
              'src/body.dart':
                  "import 'package:goo2d/goo2d.dart';\n\n"
                  'mixin RigidBody2D on Component {\n'
                  '  final bodyAwake = Field.boolean();\n'
                  '}\n',
            },
          ),
        ]),
      );

      expect(scan.extensions, isEmpty);
      expect(scan.skipped['RigidBody2D'], contains('Accessor'));
    });
  });

  group('the output is stable, because it is read in a diff', () {
    test('ordered by package, then by path, then by name', () {
      final scan = _scan(
        fakeRepo(<FakePackage>[
          kernelPackage(),
          const FakePackage(
            'zeta',
            dependencies: <String>['good'],
            files: <String, String>{
              'zeta.dart': "export 'src/a.dart';\n",
              'src/a.dart':
                  "import 'package:good/good.dart';\n\n"
                  'mixin ZetaOne on Component {\n'
                  '  final zetaOneX = Field.float64();\n'
                  '}\n',
            },
          ),
          const FakePackage(
            'alpha',
            dependencies: <String>['good'],
            files: <String, String>{
              'alpha.dart': "export 'src/z.dart';\nexport 'src/a.dart';\n",
              // Declared second in the barrel and first by path, and holding
              // two components whose order within one file is by name.
              'src/a.dart':
                  "import 'package:good/good.dart';\n\n"
                  'mixin Beta on Component {\n'
                  '  final betaX = Field.float64();\n'
                  '}\n\n'
                  'mixin AlphaOne on Component {\n'
                  '  final alphaOneX = Field.float64();\n'
                  '}\n',
              'src/z.dart':
                  "import 'package:good/good.dart';\n\n"
                  'mixin Omega on Component {\n'
                  '  final omegaX = Field.float64();\n'
                  '}\n',
            },
          ),
        ]),
      );

      expect(
        scan.extensions.map((e) => '${e.package}:${e.sortKey}:${e.component}'),
        <String>[
          'alpha:src/a.dart:AlphaOne',
          'alpha:src/a.dart:Beta',
          'alpha:src/z.dart:Omega',
          'zeta:src/a.dart:ZetaOne',
        ],
        reason:
            'not the order the barrel exports them, not the order they are '
            'declared in a file, and above all not the order listSync '
            'happened to hand them over',
      );
    });

    test('and the imports are sorted', () {
      final scan = _scan(
        _repo(<String, String>{
          'goo2d.dart': "export 'src/z.dart';\nexport 'src/a.dart';\n",
          'src/z.dart':
              "import 'package:good/good.dart';\n\n"
              'mixin Zeta on Component {\n'
              '  final zetaX = Field.float64();\n'
              '}\n',
          'src/a.dart':
              "import 'package:good/good.dart';\n\n"
              'mixin Alpha on Component {\n'
              '  final alphaOwner = Field.optEntity();\n'
              '}\n',
        }),
      );

      final source = _emit(scan, 'goo2d');
      final imports = RegExp(
        r"^import '([^']+)';$",
        multiLine: true,
      ).allMatches(source).map((m) => m.group(1)!).toList();
      expect(imports, <String>[
        'package:goo2d/src/a.dart',
        'package:goo2d/src/z.dart',
        'package:good/good.dart',
      ]);
      expect(imports, orderedEquals(<String>[...imports]..sort()));
    });

    // A generator must not read its own output. What this writes is an
    // `extension ... on Accessor<Transform2D>` inside `packages/goo2d/lib/`,
    // which on the next run looks exactly like a hand-written extension
    // declaring `offsetX`. Measured before the exclusion existed: the second
    // run reported all ten of its own components as colliding with themselves.
    test('and a second run reads none of what the first one wrote', () {
      final repo = _repo(<String, String>{
        'goo2d.dart': "export 'src/transform.dart';\n",
        'src/transform.dart': _transform,
      });

      final first = _scan(repo);
      expect(first.collisions, isEmpty);
      final packages = enginePackages(repo);
      for (final file in accessorFiles(first, packages)) {
        file.file.parent.createSync(recursive: true);
        file.file.writeAsStringSync(file.contents);
      }

      final second = _scan(repo);
      expect(
        second.collisions,
        isEmpty,
        reason: 'the first run wrote the extension the second one is reading',
      );
      expect(
        second.extensions.map((e) => e.component),
        first.extensions.map((e) => e.component),
      );
      expect(_emit(second, 'goo2d'), _emit(first, 'goo2d'));
    });
  });
}
