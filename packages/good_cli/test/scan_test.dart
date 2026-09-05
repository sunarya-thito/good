import 'dart:io';

import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/scan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '_temp.dart';

// What the one scan decides, asked of text.
//
// The generated files are the other half of this and the stronger half: eight
// committed `.g.dart` files that `good_tool --check` has to reproduce byte for
// byte, over the real packages, which is a harder thing to satisfy by accident
// than anything written here. What that oracle cannot cover is what it never
// meets - a file the parser gives up on, a project with no engine resolved
// beside it, an enum column written a way this repository does not write one -
// and that is what these are for.

/// A project directory holding [files] under `lib/`, and a pubspec.
///
/// The pubspec names an SDK constraint because the walk resolves, and a
/// library's language version is what decides whether an experiment applies
/// to it: `scanFeatureSet` is pinned at 3.13, so a fixture whose package says
/// nothing gets the analyzer's own version instead and the primary-constructor
/// fixture stops parsing.
Directory _project(
  Map<String, String> files, {
  String pubspec = 'name: demo\nenvironment:\n  sdk: ^3.13.0\n',
}) {
  final dir = testTempDir('good_cli_scan');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
  final name = RegExp(r'^name:\s*(\S+)', multiLine: true)
      .firstMatch(pubspec)!
      .group(1)!;
  // The package config `pub get` would have written, and it is
  // load-bearing rather than scenery. A library in no package takes the
  // analyzer's own language version - 3.12 under this analyzer
  // constraint - and an experiment with no experimental release version
  // applies only at the version `scanFeatureSet` names. Without this the
  // primary-constructor fixture stops parsing and nothing else notices.
  File(p.join(dir.path, '.dart_tool', 'package_config.json'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      '{\n'
      '  "configVersion": 2,\n'
      '  "packages": [\n'
      '    { "name": "$name", "rootUri": "../", '
      '"packageUri": "lib/", "languageVersion": "3.13" }\n'
      '  ]\n'
      '}\n',
    );
  files.forEach((path, contents) {
    File(p.join(dir.path, 'lib', path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(contents);
  });
  return dir;
}

Future<ScanSources> _scan(Directory project) => readSources(project);

/// The engine declarations the derivations read out of the walk.
///
/// Transcribed rather than imported, and that is the point of the design being
/// tested: a fixture that spells `Field.float64` differently gets a different
/// answer, with nothing about the engine hard-coded anywhere.
///
/// Every fixture written against this **imports** it. The walk resolves, so a
/// `game.dart` naming `Field` without saying where it comes from is a file
/// whose every field is `InvalidType` - which is a fact about the fixture and
/// not about the code under test.
const String _kernel = '''
abstract interface class Scannable {}
abstract interface class ScannableField {}
abstract interface class ScannableAnnotation {}

abstract interface class Component implements Scannable {}
abstract interface class MultiComponent implements Component {}
abstract class EntityStruct implements MultiComponent, ScannableField {}
abstract class SceneStruct implements Scannable {}
abstract class GameSystem implements Scannable {}

class DataPointer<T> implements ScannableField {}
class InitialPointer<T> extends DataPointer<T> {}
class DataArrayPointer<T> implements ScannableField {}
class Query implements ScannableField {
  static Query all(Type a) => throw UnimplementedError();
  static QueryBuilder where() => throw UnimplementedError();
}

abstract class QueryBuilder {
  QueryBuilder withAll(Type a);
  QueryBuilder withOptional(Type a);
  Query build();
}

class LoadBefore implements ScannableAnnotation {
  const LoadBefore(this.other);
  final Type other;
}

class Sub implements ScannableAnnotation {
  const Sub._();
}

const Sub sub = Sub._();

abstract final class Field {
  static InitialPointer<double> float64([double initialValue = 0.0]) =>
      throw UnimplementedError();
  static InitialPointer<E> enumOf<E extends Enum>(
    List<E> values, [
    E? initialValue,
  ]) => throw UnimplementedError();
  static DataArrayPointer<T> array<T>(Object element, int length) =>
      throw UnimplementedError();
}
''';

/// A declaration scan over one `game.dart` written against [_kernel].
Future<DeclarationScan> _declarations(String source) async => scanDeclarations(
  await _scan(
    _project(<String, String>{
      'kernel.dart': _kernel,
      'game.dart': "import 'kernel.dart';\n\n$source",
    }),
  ),
);

/// The refusals as `Owner.field`, so a test names what it expects rather than
/// matching a sentence that is free to be rewritten.
List<String> _refused(DeclarationScan scan) => <String>[
  for (final refusal in scan.refusals) '${refusal.owner}.${refusal.field}',
];

void main() {
  group('the walk', () {
    test('parses a file that uses primary constructors', () async {
      // #348, reached through the analyzer rather than through
      // `parseString`. A context reads `analysis_options.yaml`, but an
      // experiment with no experimental release version applies only to a
      // library whose language version is the analyzer's own - so
      // `scanFeatureSet` still names both, and without it this file parses to
      // a shorter tree with no error anywhere.
      final project = _project(<String, String>{
        'shape.dart': 'class Sprite({final int width, final int height});\n',
      });
      final sources = await _scan(project);

      expect(sources.unparsed, isEmpty);
      expect(sources.typesByName.keys, contains('Sprite'));
    });

    test('reports a file it could not parse instead of half-reading it', () async {
      final project = _project(<String, String>{
        'broken.dart': 'class Player {\n  int speed = 0\n',
        'fine.dart': 'class Enemy {}\n',
      });
      final sources = await _scan(project);

      expect(sources.unparsed, hasLength(1));
      expect(sources.unparsed.single, endsWith('broken.dart'));
      expect(
        sources.typesByName.keys,
        isNot(contains('Player')),
        reason: 'a recovered tree is not an answer, and the file that holds it '
            'contributes nothing rather than contributing a fraction',
      );
      expect(sources.typesByName.keys, contains('Enemy'));
    });

    test('leaves out a file named in exclude', () async {
      final project = _project(<String, String>{
        'a.dart': 'class A {}\n',
        'b.dart': 'class B {}\n',
      });
      final sources = await readSources(
        project,
        rootOverride: <String>[p.join(project.path, 'lib')],
        exclude: <String>{p.join(project.path, 'lib', 'b.dart')},
      );

      expect(sources.typesByName.keys, contains('A'));
      expect(sources.typesByName.keys, isNot(contains('B')));
    });
  });

  group('what a column is', () {
    Future<ScannedType> typeOf(Directory project, String name) async =>
        (await _scan(project)).typesByName[name]!;

    test('a factory call takes its value type from the factory', () async {
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': "import 'good.dart';\n\n"
            'mixin Velocity on Component {\n'
            '  final velocitySpeed = Field.float64();\n}\n',
      });
      final field = (await typeOf(project, 'Velocity')).fields.single;

      expect(
        columnValueType(field)?.valueType,
        'double',
      );
    });

    test('a declared type takes its value type from the annotation', () async {
      // `Camera.cameraView` is this shape in the tree: the column is assigned
      // in `describeStruct` because the table it is declared against comes
      // from `getScene`, so there is no initialiser to read a type off.
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': "import 'good.dart';\n\n"
            'class CameraView {}\n\n'
            'mixin Camera on Component {\n'
            '  late final DataPointer<CameraView?> cameraView;\n}\n',
      });
      final field = (await typeOf(project, 'Camera')).fields.single;

      expect(
        columnValueType(field)?.valueType,
        'CameraView?',
        reason: 'the nullability is written and has to survive - it is the '
            'thing a runtime Type cannot carry',
      );
    });

    test('an array column is reported, not passed over', () async {
      // `DataArrayPointer` is a separate root and not a `DataPointer` at all,
      // so a test written as `is DataPointer` drops every array column and
      // says nothing. This is what says it did not.
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': "import 'good.dart';\n\n"
            'mixin Text2D on Component {\n'
            '  late final DataArrayPointer<int> textCodeUnits;\n}\n',
      });
      final field = (await typeOf(project, 'Text2D')).fields.single;
      final column = columnValueType(field);

      expect(column, isNotNull);
      expect(column!.valueType, isNull);
      expect(column.problem, contains('DataArrayPointer'));
    });

    test('an enum column takes its type from the values it was given', () async {
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': "import 'good.dart';\n\n"
            'enum BodyType2D { staticBody, dynamicBody }\n\n'
            'mixin RigidBody2D on Component {\n'
            '  final bodyType = Field.enumOf(BodyType2D.values);\n}\n',
      });
      final field = (await typeOf(project, 'RigidBody2D')).fields.single;

      expect(
        columnValueType(field)?.valueType,
        'BodyType2D',
      );
    });

    test('a value type the two hand-written ways could not reach is '
        'answered', () async {
      // This used to be refused. `Field.enumOf(...)` declares an `E`, and the
      // two ways the walk filled one in were an explicit type argument and a
      // `SomeEnum.values` argument - so an argument that is a *call* reached
      // neither and the column was reported as one whose value type could not
      // be worked out. The analyzer works it out.
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': "import 'good.dart';\n\n"
            'enum Suit { clubs, hearts }\n\n'
            'mixin Odd on Component {\n'
            '  final oddThing = Field.enumOf(somethingElse());\n}\n'
            'List<Suit> somethingElse() => const <Suit>[];\n',
      });
      final field = (await typeOf(project, 'Odd')).fields.single;

      expect(columnValueType(field)?.valueType, 'Suit');
    });

    test('an ordinary field is not a column', () async {
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': "import 'good.dart';\n\n"
            'mixin Velocity on Component {\n'
            '  final List<int> history = <int>[];\n'
            '  int plain = 0;\n}\n',
      });
      for (final field in (await typeOf(project, 'Velocity')).fields) {
        expect(columnValueType(field), isNull, reason: field.name);
      }
    });
  });

  group('the property name', () {
    test('drops the component name the column is prefixed with', () {
      expect(propertyNameFor('Child', 'childParent'), 'parent');
      expect(propertyNameFor('Camera', 'cameraZoom'), 'zoom');
    });

    test('drops the dimension suffix before comparing', () {
      // `Transform2D` prefixes its columns `transform`, not `transform2D`, and
      // so does every other component in the tree that carries a dimension.
      expect(propertyNameFor('Transform2D', 'transformOffsetX'), 'offsetX');
      expect(propertyNameFor('Camera3D', 'cameraFieldOfView'), 'fieldOfView');
      expect(propertyNameFor('Text2D', 'textLength'), 'length');
    });

    test('leaves a column that is not prefixed with the whole name alone', () {
      // The two in the tree. `WorldTransform2D.worldX` starts with `world` and
      // not with `worldTransform`, so a rule that stripped the first camel
      // word would generate `x` - and `RigidBody2D.bodyHandle` would become
      // `handle`. Neither is what is committed.
      expect(propertyNameFor('WorldTransform2D', 'worldX'), 'worldX');
      expect(
        propertyNameFor('WorldTransform2D', 'worldScaleX'),
        'worldScaleX',
      );
      expect(propertyNameFor('RigidBody2D', 'bodyHandle'), 'bodyHandle');
    });

    test('leaves a column that is exactly the prefix alone', () {
      expect(propertyNameFor('Camera', 'camera'), 'camera');
    });
  });

  group('the supertype walk', () {
    test('follows on, extends, with and implements by name', () async {
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': "import 'good.dart';\n\n"
            'mixin Collider2D on MultiComponent {}\n'
            'class Player extends EntityStruct with Collider2D {}\n',
      });
      final names = (await _scan(project)).typesByName;

      expect(isSubtypeOf('Collider2D', 'Component', names), isTrue);
      expect(isSubtypeOf('Player', 'Component', names), isTrue);
      expect(isSubtypeOf('SceneStruct', 'Component', names), isFalse);
    });

    test('stops at a name it never read, rather than looping', () async {
      final project = _project(<String, String>{
        'game.dart': 'class A extends B {}\nclass B extends A {}\n',
      });
      final names = (await _scan(project)).typesByName;

      expect(isSubtypeOf('A', 'Component', names), isFalse);
    });

    test('a mixin on Component is one even with no engine read', () async {
      // A project whose engine is not in the read set: `Component` is a name
      // and nothing else. The supertype walk is by name and answers anyway,
      // which is what keeps `scanStructRules` working on a fixture with no
      // engine beside it - resolution decides what a field *holds*, and this
      // decides what a type *is*.
      final project = _project(<String, String>{
        'game.dart': 'mixin Velocity on Component {}\n',
      });

      expect(
        isSubtypeOf('Velocity', 'Component', (await _scan(project)).typesByName),
        isTrue,
      );
    });
  });

  group('scanStructRules', () {
    test('reports one mixin hiding another mixin\'s field', () async {
      final project = _project(<String, String>{
        'game.dart': 'mixin Velocity on Component {\n'
            '  final speed = Field.float64();\n}\n'
            'mixin Momentum on Component {\n'
            '  final speed = Field.float64();\n}\n'
            'class Player extends EntityStruct with Velocity, Momentum {}\n',
      });
      final scan = await scanStructRules(project);

      expect(scan.shadowed, hasLength(1));
      expect(scan.shadowed.single.later, 'Momentum');
      expect(scan.shadowed.single.earlier, 'Velocity');
      expect(
        shadowedFieldsMessage(scan),
        contains('Momentum.speed shadows Velocity.speed'),
      );
    });

    test('does not report a private field declared in another file', () async {
      // A private field is library-scoped, so `_cached` on two mixins in two
      // files is two names and hides nothing.
      final project = _project(<String, String>{
        'a.dart': 'mixin A on Component {\n  final _cached = 0;\n}\n',
        'b.dart': 'mixin B on Component {\n  final _cached = 0;\n}\n',
        'game.dart': 'class Player extends EntityStruct with A, B {}\n',
      });

      expect((await scanStructRules(project)).shadowed, isEmpty);
    });

    test('reports a component describe override that drops the chain', () async {
      final project = _project(<String, String>{
        'game.dart': 'mixin Velocity on Component {\n'
            '  @override\n'
            '  void describeType(ComponentDescriptor component) {\n'
            '    component.has<Velocity>();\n'
            '  }\n}\n',
      });
      final scan = await scanStructRules(project);

      expect(scan.missingSuper, hasLength(1));
      expect(
        missingSuperMessage(scan),
        contains('Velocity.describeType does not call super.describeType()'),
      );
    });

    test('leaves an override of an abstract hook alone', () async {
      // `TimelineStruct.describeTrack` is abstract, so an override of it has
      // nothing above it to call and `super.describeTrack()` would not
      // compile. A rule keyed on the method name alone reports it - `goo2d`'s
      // own example has two.
      final project = _project(<String, String>{
        'game.dart': 'abstract class TimelineStruct {\n'
            '  void describeTrack(Object descriptor);\n}\n'
            'class Breath extends TimelineStruct {\n'
            '  @override\n'
            '  void describeTrack(Object descriptor) {\n'
            '    print(descriptor);\n'
            '  }\n}\n',
      });

      expect((await scanStructRules(project)).missingSuper, isEmpty);
    });

    test('leaves an empty base declaration alone', () async {
      final project = _project(<String, String>{
        'game.dart': 'mixin Velocity on Component {\n'
            '  @override\n'
            '  void describeAssets(Object descriptor) {}\n}\n',
      });

      expect((await scanStructRules(project)).missingSuper, isEmpty);
    });

    test('names a mixin it could not read rather than passing over it', () async {
      final project = _project(<String, String>{
        'game.dart':
            'class Player extends EntityStruct with SomethingElsewhere {}\n',
      });

      expect(
        (await scanStructRules(project)).unresolved.keys,
        contains('SomethingElsewhere'),
      );
    });
  });

  // The check the deleted declaration window used to carry, rebuilt on
  // `ScannableField` instead. A declaration is one because its value type says
  // so, which is a fact about the source; the old one asked whether a lazily
  // initialised declaration would land on the wrong owner, which was a fact
  // about the window.
  group('scanDeclarations', () {
    test('an eager field is a declaration, named and typed', () async {
      final scan = await _declarations('''
class Player extends EntityStruct {
  final speed = Field.float64(220);
}
''');

      expect(scan.refusals, isEmpty);
      expect(scan.declarers.single.type, 'Player');
      final declaration = scan.declarers.single.declarations.single;
      expect(declaration.name, 'speed');
      // The field name and the written type, which is the half of the answer
      // a collected *value* cannot carry: a DataPointer has no name member.
      expect(declaration.valueType, 'InitialPointer<double>');
    });

    test('a late field with no initialiser is refused', () async {
      // The Camera.cameraView shape: the field declared here, the value
      // assigned from a describe pass. One declaration written twice, and the
      // half that runs does so where the declaration does not say.
      final scan = await _declarations('''
class Player extends EntityStruct {
  late final DataPointer<double> filled;
}
''');

      expect(_refused(scan), <String>['Player.filled']);
      expect(scan.declarers, isEmpty);
      expect(scan.refusals.single.reason, contains('freshly constructed'));
    });

    test('a late field with an initialiser is a declaration', () async {
      // A `late` initialiser runs on first touch, after construction, so it
      // is the one shape that can read `this` - which is how an effector names
      // the region beside it and how an asset key arrives as a constructor
      // argument. The collector's read *is* that first touch, and Dart
      // memoises the result, so collect and gameplay see one object.
      //
      // The pair with the test above is what holds the rule in place. What is
      // refused is a declaration with no initialiser, so a walk rewritten to
      // key on the word `late` passes that one and fails this one.
      final scan = await _declarations('''
class Player extends EntityStruct {
  late final deferred = Field.float64();
}
''');

      expect(_refused(scan), isEmpty);
      expect(scan.unresolved, isEmpty);
      final declaration = scan.declarers.single.declarations.single;
      expect(declaration.name, 'deferred');
      expect(declaration.valueType, 'InitialPointer<double>');
    });

    test('a late ring is refused, and the ring named', () async {
      // `late final a = b; late final b = a;` compiles. The first touch of
      // either throws LateInitializationError naming one field and nothing
      // about the ring, from a stack with no engine frame on it - and a
      // collector's read is that first touch, so this is a boot that dies
      // with nothing to go on.
      final scan = await _declarations('''
class Player extends EntityStruct {
  late final DataPointer<double> a = b;
  late final DataPointer<double> b = a;
}
''');

      expect(
        <String>[for (final ring in scan.cycles) '${ring.owner}.${ring.field}'],
        hasLength(1),
      );
      expect(scan.cycles.single.owner, 'Player');
      expect(scan.cycles.single.reason, contains('closes a ring'));
    });

    test('two late fields that read each other and declare nothing are left '
        'alone', () async {
      // The ring check is a declaration rule and not a lint. Two `late` fields
      // holding ordinary objects are somebody's bug and nothing here collects
      // them, so refusing would be this tool deciding what a class may hold.
      final scan = await _declarations('''
class Player extends EntityStruct {
  late final int a = b;
  late final int b = a;
  final speed = Field.float64();
}
''');

      expect(scan.cycles, isEmpty);
      expect(scan.declarers.single.declarations.single.name, 'speed');
    });

    test('a declaration with no initialiser at all is refused', () async {
      final scan = await _declarations('''
class Player extends EntityStruct {
  DataPointer<double> filled;
}
''');

      expect(_refused(scan), <String>['Player.filled']);
      expect(scan.refusals.single.reason, contains('no initialiser'));
    });

    test('a static declaration is refused', () async {
      final scan = await _declarations('''
class Player extends EntityStruct {
  static final speed = Field.float64(220);
}
''');

      expect(_refused(scan), <String>['Player.speed']);
      expect(scan.refusals.single.reason, contains('lazily'));
    });

    test('a top-level declaration is refused, named by its file', () async {
      final scan = await _declarations('''
final speed = Field.float64(220);
''');

      expect(_refused(scan), <String>['game.dart.speed']);
      expect(scan.refusals.single.reason, contains('top-level'));
    });

    test('a nullable handle is a binding, not a declaration', () async {
      // `Child._declaredIn` in `good/lib/src/data/hierarchy.dart`: a column on
      // somebody *else's* archetype, handed over at registration and null
      // until then. A column cannot be declared conditionally, so a nullable
      // handle is never a declaration - which is what keeps this off the
      // refusal list rather than on it with no way to satisfy it.
      final scan = await _declarations('''
class Player extends EntityStruct {
  DataPointer<double>? bound;
}
''');

      expect(scan.refusals, isEmpty);
      expect(scan.declarers, isEmpty);
    });

    // The three answers a field holding a ScannableField is allowed to end
    // in. Every one of them is checked, because the pair that matters is the
    // last two: a gate that collected the unmarked field as well would still
    // pass the first two, and this repository has shipped tests that could
    // not fail.
    test('a dotted static is collected with no marker on it', () async {
      // The shape half of "shape tells, or annotation tells". Nothing is
      // written on any of these and all three are declarations, because
      // `Field.float64(`, `Query.all(` and the rest say so where they are
      // written.
      final scan = await _declarations('''
class Player extends EntityStruct {
  final speed = Field.float64(220);
}

class Movement extends GameSystem {
  final movers = Query.all(Player);
  final roots = Query.where().withAll(Player).build();
}
''');

      expect(scan.unmarked, isEmpty);
      expect(scan.declarationCount, 3);
      expect(
        <String>[
          for (final declarer in scan.declarers)
            for (final declaration in declarer.declarations) declaration.name,
        ],
        <String>['speed', 'movers', 'roots'],
      );
    });

    test('a marked bare constructor is collected', () async {
      final scan = await _declarations('''
class Turret extends EntityStruct {
  @sub
  final barrel = Barrel();
}

class Barrel extends EntityStruct {}
''');

      expect(scan.unmarked, isEmpty);
      expect(scan.refusals, isEmpty);
      final declaration = scan.declarers.single.declarations.single;
      expect(declaration.name, 'barrel');
      expect(declaration.isCollected, isTrue);
      // The marker is a const variable and not a class, so a walk that only
      // looked types up in `typesByName` finds nothing under `sub` and
      // carries no annotation at all.
      expect(declaration.annotations, <String>['sub']);
    });

    test('an unmarked bare constructor is reported and stays legal', () async {
      // `final spare = Barrel();` holding a prototype is ordinary code, and
      // keeping it legal is half the reason the marker exists. So it is named
      // rather than refused, and it is not collected: it declares nothing, it
      // reserves no column, and the row is not missing one.
      final scan = await _declarations('''
class Turret extends EntityStruct {
  @sub
  final barrel = Barrel();
  final spare = Barrel();
}

class Barrel extends EntityStruct {}
''');

      expect(scan.refusals, isEmpty);
      expect(scan.unresolved, isEmpty);
      expect(scan.unmarked.keys, <String>['Turret.spare']);
      expect(
        <String>[
          for (final declaration in scan.declarers.single.declarations)
            declaration.name,
        ],
        <String>['barrel'],
      );
    });

    test('a cascade over a constructor still needs the marker', () async {
      // Resolution does not make `@sub` optional and never could. It proves
      // `Barrel()` is an `EntityStruct`; it cannot prove the field is a child
      // rather than a spare, because those are the same type by construction.
      // There is no such pair for the other roots - holding a `DataPointer`
      // *is* declaring a column - which is why they need no marker and this
      // does.
      //
      // The cascade is where a stronger scan could have taken the marker away
      // by accident. A walk reading the initialiser as a chain of calls saw
      // nothing at all here, so `final spare = Barrel()..tune();` was neither
      // collected nor listed; a walk that resolved the *type* and kept the
      // old test for "is this a constructor call" would have found a
      // declaration, found no constructor call, and collected it with no
      // marker on it. Both halves are asserted, because the second is the
      // defect.
      final scan = await _declarations('''
class Turret extends EntityStruct {
  @sub
  final barrel = Barrel()..tune();
  final spare = Barrel()..tune();
}

class Barrel extends EntityStruct {
  void tune() {}
}
''');

      expect(scan.refusals, isEmpty);
      expect(scan.unresolved, isEmpty);
      expect(scan.unmarked.keys, <String>['Turret.spare']);
      expect(
        <String>[
          for (final declaration in scan.declarers.single.declarations)
            declaration.name,
        ],
        <String>['barrel'],
      );
    });

    test('a named constructor tells by its own shape', () async {
      // `Entity.pack(...)` is dotted, and a dotted head says what it is where
      // it is written - which is the whole of the shape half of the rule. So
      // the marker is asked for on an *unnamed* constructor call and on
      // nothing else.
      final scan = await _declarations('''
class Turret extends EntityStruct {
  final barrel = Barrel.tuned();
}

class Barrel extends EntityStruct {
  Barrel.tuned();
}
''');

      expect(scan.unmarked, isEmpty);
      expect(scan.declarers.single.declarations.single.name, 'barrel');
    });

    test('an unmarked bare constructor still closes a ring', () async {
      // The marker decides what a collector reads. It decides nothing about
      // whether Dart builds the object, and it is the building that does not
      // terminate - so a walk that filtered the cycle graph on it would go
      // quiet on the one failure a run cannot report from at all.
      final scan = await _declarations('''
class Turret extends EntityStruct {
  final loop = Turret();
}
''');

      expect(scan.unmarked.keys, <String>['Turret.loop']);
      expect(scan.cycles, hasLength(1));
      expect(scan.cycles.single.reason, contains('Turret -> Turret'));
    });

    test('every ScannableField root counts, not just DataPointer', () async {
      // The array root is separate - a DataArrayPointer is not a DataPointer -
      // so a pass testing one root drops every array column with nothing said.
      final scan = await _declarations('''
class Player extends EntityStruct {
  final letters = Field.array(1, 32);
}

class Movement extends GameSystem {
  final movers = Query.all(Player);
}
''');

      expect(scan.refusals, isEmpty);
      expect(
        <String>[for (final declarer in scan.declarers) declarer.type],
        <String>['Player', 'Movement'],
      );
      expect(scan.declarationCount, 2);
    });

    test('a class that is not Scannable declares nothing', () async {
      final scan = await _declarations('''
class Helper {
  final speed = Field.float64(220);
}
''');

      expect(scan.refusals, isEmpty);
      expect(scan.declarers, isEmpty);
    });

    test('a private declaration is accepted and listed as uncollectable', () async {
      // Not refused. A collector cannot read it, and saying so is the whole
      // point; whether the engine's 28 private cache columns become public is
      // a separate call, and refusing here would be making it.
      final scan = await _declarations('''
class Player extends EntityStruct {
  final _cached = Field.float64();
}
''');

      expect(scan.refusals, isEmpty);
      expect(scan.declarers.single.declarations.single.isPrivate, isTrue);
      expect(scan.uncollectable.keys, <String>['Player._cached']);
    });

    test('only a marked annotation is carried', () async {
      final scan = await _declarations('''
class Player extends EntityStruct {
  @override
  @Deprecated('no')
  @LoadBefore(Player)
  final speed = Field.float64(220);
}
''');

      // Whole source, arguments included: a name alone cannot say what
      // LoadBefore(Player) meant, and the table has to write it back out.
      expect(scan.declarers.single.declarations.single.annotations, <String>[
        'LoadBefore(Player)',
      ]);
    });

    // The three states a field holding a declaration is allowed to end in.
    // Nothing else is: a field that lands in none of them is missing from the
    // collector, from the row it would have sat in, and from every list a
    // reader could check, which is the one outcome this design exists to stop.
    test('a builder chain is followed to what it builds', () async {
      // `Query.where().withAll(...).build()` is what `Query.where`'s own doc
      // teaches, and nothing about the first call says the field holds a
      // Query. A walk reading only the outermost call asks about `build` on a
      // receiver it never named; one reading a flattened dotted string looks
      // up a class called `Query.where().withAll(Player)`.
      final scan = await _declarations('''
class Movement extends GameSystem {
  final roots = Query.where().withAll(Player).withOptional(Player).build();
}

class Player extends EntityStruct {}
''');

      expect(_refused(scan), isEmpty);
      expect(scan.unresolved, isEmpty);
      final declaration = scan.declarers.single.declarations.single;
      expect(declaration.name, 'roots');
      expect(declaration.valueType, 'Query');
    });

    test('a private builder chain is listed, not dropped', () async {
      // The six `Query.where()` fields in the engine. They were neither
      // collected nor listed while the walk stopped at the first call, so the
      // count of what a row is missing was six short and read as exact.
      final scan = await _declarations('''
class Movement extends GameSystem {
  final _roots = Query.where().withAll(Player).build();
}

class Player extends EntityStruct {}
''');

      expect(scan.uncollectable.keys, <String>['Movement._roots']);
    });

    test('a field the analyzer cannot type is said, in its own words', () async {
      // The silence this design exists to prevent, and the half of it the
      // walk can still get wrong. `withEverything` is not on `QueryBuilder`,
      // so the field has no type - and a field with no type is neither
      // collected nor listed as uncollectable unless something says so here.
      //
      // The reason is the analyzer's own sentence. This used to be a message
      // written in the walk, which could say "the chain stopped" and nothing
      // about where; the diagnostic names the member.
      final scan = await _declarations('''
class Movement extends GameSystem {
  final roots = Query.where().withEverything(Player).build();
}

class Player extends EntityStruct {}
''');

      expect(
        <String>[
          for (final refusal in scan.unresolved)
            '${refusal.owner}.${refusal.field}',
        ],
        <String>['Movement.roots'],
      );
      expect(scan.unresolved.single.reason, contains('withEverything'));
      expect(scan.declarers, isEmpty);
    });

    test('an ordinary field stays quiet', () async {
      // The other side of the same rule, and the reason the one above is not
      // simply "report every field on a scanned class". Most of them hold
      // ordinary values, and a pass that named each of them would be read as
      // noise and then ignored - which is how a real one gets missed.
      //
      // What changed with resolution is which fields are which. "Built by
      // code outside the read set" used to mean "unknown", because the walk
      // read text; the analyzer types `Stopwatch()` and `toString().trim()`
      // like anything else, so the quiet set is now exactly the fields that
      // compile and are not declarations.
      final scan = await _declarations('''
class Movement extends GameSystem {
  final clock = Stopwatch();
  final label = 'idle'.trim();
  final ticks = <int>[];
}
''');

      expect(scan.unresolved, isEmpty);
      expect(scan.refusals, isEmpty);
      expect(scan.declarers, isEmpty);
    });

    // What the registration stack used to answer. A declared child is a field
    // holding a constructor call, so the recursion is Dart's own and a run
    // reaches no engine code to report from - it gets a StackOverflowError
    // naming nothing. The ring is written down in the source, so this is the
    // only place left that can name it.
    test('a struct that declares itself is refused, and the ring named', () async {
      final scan = await _declarations('''
class Turret extends EntityStruct {
  final loop = Turret();
}
''');

      expect(scan.cycles, hasLength(1));
      expect(scan.cycles.single.owner, 'Turret');
      expect(scan.cycles.single.field, 'loop');
      expect(scan.cycles.single.reason, contains('Turret -> Turret'));
    });

    test('a ring through three structs is one refusal, not three', () async {
      final scan = await _declarations('''
class Turret extends EntityStruct {
  @sub
  final barrel = Barrel();
}

class Barrel extends EntityStruct {
  @sub
  final tip = Tip();
}

class Tip extends EntityStruct {
  @sub
  final turret = Turret();
}
''');

      expect(
        <String>[for (final cycle in scan.cycles) '${cycle.owner}.${cycle.field}'],
        <String>['Tip.turret'],
      );
      expect(
        scan.cycles.single.reason,
        contains('Turret -> Barrel -> Tip -> Turret'),
      );
    });

    test('a struct declared twice by different owners is not a ring', () async {
      // Two turrets holding a barrel each is the ordinary shape, and a walk
      // that treated "seen already" as "cycle" would refuse it.
      final scan = await _declarations('''
class Turret extends EntityStruct {
  @sub
  final barrel = Barrel();
}

class Tower extends EntityStruct {
  @sub
  final barrel = Barrel();
  @sub
  final spare = Barrel();
}

class Barrel extends EntityStruct {}
''');

      expect(scan.cycles, isEmpty);
      expect(
        <String>[for (final declarer in scan.declarers) declarer.type],
        <String>['Turret', 'Tower'],
      );
    });
  });

  group('scanScenes', () {
    const String pubspec = '''
name: demo
good:
  assets:
    - assets/
''';

    Directory sceneProject(Map<String, String> files) {
      final project = _project(files, pubspec: pubspec);
      for (final name in const <String>['player.png', 'menu.png']) {
        File(p.join(project.path, 'assets', name))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(const <int>[0x89, 0x50, 0x4E, 0x47]);
      }
      return project;
    }

    test('attributes an asset to the scene that reaches its prefab', () async {
      final project = sceneProject(<String, String>{
        'good.dart': _kernel,
        'game.dart': "import 'good.dart';\n\n"
            '''
class Player extends EntityStruct {
  late final Object texture;

  @override
  void describeAssets(Object descriptor) {
    texture = Textures.player;
  }
}

class MainScene extends SceneStruct {
  late final Player player;

  @override
  void describeScene(Object descriptor) {
    player = descriptor.has(Player.new);
  }
}
''',
      });
      final usage = await scanScenes(project, scanAssets(project));

      expect(usage.byScene.keys, <String>['MainScene']);
      expect(usage.byScene['MainScene'], contains('assets/player.png'));
      expect(
        usage.byScene['MainScene'],
        isNot(contains('assets/menu.png')),
        reason: 'nothing reaches it, so it is not this scene\'s to load',
      );
    });

    test('leaves an asset no scene reaches unattributed', () async {
      final project = sceneProject(<String, String>{
        'good.dart': _kernel,
        'game.dart': "import 'good.dart';\n\n"
            '''
class MainScene extends SceneStruct {}

class Loose {
  final Object texture = Textures.menu;
}
''',
      });
      final usage = await scanScenes(project, scanAssets(project));

      expect(usage.byScene['MainScene'], isEmpty);
      expect(usage.unresolved.keys, contains('menu'));
      expect(usage.unresolved.keys, contains('player'));
    });
  });
}
