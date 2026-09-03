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
Directory _project(
  Map<String, String> files, {
  String pubspec = 'name: demo\n',
}) {
  final dir = testTempDir('good_cli_scan');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
  files.forEach((path, contents) {
    File(p.join(dir.path, 'lib', path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(contents);
  });
  return dir;
}

ScanSources _scan(Directory project) => readSources(project);

/// The engine declarations the derivations read out of the walk.
///
/// Transcribed rather than imported, and that is the point of the design being
/// tested: `Field.float64`'s value type is read off this text, so a fixture
/// that spells the factory differently gets a different answer with nothing
/// hard-coded anywhere.
const String _kernel = '''
abstract interface class Scannable {}
abstract interface class ScannableField {}
abstract interface class ScannableAnnotation {}

abstract interface class Component implements Scannable {}
abstract interface class MultiComponent implements Component {}
abstract class EntityStruct implements MultiComponent {}
abstract class SceneStruct implements Scannable {}
abstract class GameSystem implements Scannable {}

class DataPointer<T> implements ScannableField {}
class InitialPointer<T> extends DataPointer<T> {}
class DataArrayPointer<T> implements ScannableField {}
class Query implements ScannableField {
  static Query all(Type a) => throw UnimplementedError();
}

class LoadBefore implements ScannableAnnotation {
  const LoadBefore(this.other);
  final Type other;
}

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
DeclarationScan _declarations(String source) => scanDeclarations(
  _scan(
    _project(<String, String>{'kernel.dart': _kernel, 'game.dart': source}),
  ),
);

/// The refusals as `Owner.field`, so a test names what it expects rather than
/// matching a sentence that is free to be rewritten.
List<String> _refused(DeclarationScan scan) => <String>[
  for (final refusal in scan.refusals) '${refusal.owner}.${refusal.field}',
];

void main() {
  group('the walk', () {
    test('parses a file that uses primary constructors', () {
      // #348. `parseString` does not read `analysis_options.yaml`, so the
      // experiment has to be named in the FeatureSet. Without it this file
      // parses to a shorter tree with no error anywhere, and everything it
      // declares vanishes from every answer below.
      final project = _project(<String, String>{
        'shape.dart': 'class Sprite({final int width, final int height});\n',
      });
      final sources = _scan(project);

      expect(sources.unparsed, isEmpty);
      expect(sources.typesByName.keys, contains('Sprite'));
    });

    test('reports a file it could not parse instead of half-reading it', () {
      final project = _project(<String, String>{
        'broken.dart': 'class Player {\n  int speed = 0\n',
        'fine.dart': 'class Enemy {}\n',
      });
      final sources = _scan(project);

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

    test('leaves out a file named in exclude', () {
      final project = _project(<String, String>{
        'a.dart': 'class A {}\n',
        'b.dart': 'class B {}\n',
      });
      final sources = readSources(
        project,
        rootOverride: <String>[p.join(project.path, 'lib')],
        exclude: <String>{p.join(project.path, 'lib', 'b.dart')},
      );

      expect(sources.typesByName.keys, contains('A'));
      expect(sources.typesByName.keys, isNot(contains('B')));
    });
  });

  group('what a column is', () {
    ScannedType typeOf(Directory project, String name) =>
        _scan(project).typesByName[name]!;

    Map<String, ScannedType> namesOf(Directory project) =>
        _scan(project).typesByName;

    test('a factory call takes its value type from the factory', () {
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': 'mixin Velocity on Component {\n'
            '  final velocitySpeed = Field.float64();\n}\n',
      });
      final field = typeOf(project, 'Velocity').fields.single;

      expect(
        columnValueType(field, namesOf(project))?.valueType,
        'double',
      );
    });

    test('a declared type takes its value type from the annotation', () {
      // `Camera.cameraView` is this shape in the tree: the column is assigned
      // in `describeStruct` because the table it is declared against comes
      // from `getScene`, so there is no initialiser to read a type off.
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': 'class CameraView {}\n\n'
            'mixin Camera on Component {\n'
            '  late final DataPointer<CameraView?> cameraView;\n}\n',
      });
      final field = typeOf(project, 'Camera').fields.single;

      expect(
        columnValueType(field, namesOf(project))?.valueType,
        'CameraView?',
        reason: 'the nullability is written and has to survive - it is the '
            'thing a runtime Type cannot carry',
      );
    });

    test('an array column is reported, not passed over', () {
      // `DataArrayPointer` is a separate root and not a `DataPointer` at all,
      // so a test written as `is DataPointer` drops every array column and
      // says nothing. This is what says it did not.
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': 'mixin Text2D on Component {\n'
            '  late final DataArrayPointer<int> textCodeUnits;\n}\n',
      });
      final field = typeOf(project, 'Text2D').fields.single;
      final column = columnValueType(field, namesOf(project));

      expect(column, isNotNull);
      expect(column!.valueType, isNull);
      expect(column.problem, contains('DataArrayPointer'));
    });

    test('an enum column takes its type from the values it was given', () {
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': 'enum BodyType2D { staticBody, dynamicBody }\n\n'
            'mixin RigidBody2D on Component {\n'
            '  final bodyType = Field.enumOf(BodyType2D.values);\n}\n',
      });
      final field = typeOf(project, 'RigidBody2D').fields.single;

      expect(
        columnValueType(field, namesOf(project))?.valueType,
        'BodyType2D',
      );
    });

    test('a value type inference cannot reach is refused, not guessed', () {
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': 'mixin Odd on Component {\n'
            '  final oddThing = Field.enumOf(somethingElse());\n}\n'
            'List<Never> somethingElse() => const <Never>[];\n',
      });
      final field = typeOf(project, 'Odd').fields.single;
      final column = columnValueType(field, namesOf(project));

      expect(column?.valueType, isNull);
      expect(column?.problem, contains('inference'));
    });

    test('an ordinary field is not a column', () {
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': 'mixin Velocity on Component {\n'
            '  final List<int> history = <int>[];\n'
            '  int plain = 0;\n}\n',
      });
      final names = namesOf(project);
      for (final field in typeOf(project, 'Velocity').fields) {
        expect(columnValueType(field, names), isNull, reason: field.name);
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
    test('follows on, extends, with and implements by name', () {
      final project = _project(<String, String>{
        'good.dart': _kernel,
        'game.dart': 'mixin Collider2D on MultiComponent {}\n'
            'class Player extends EntityStruct with Collider2D {}\n',
      });
      final names = _scan(project).typesByName;

      expect(isSubtypeOf('Collider2D', 'Component', names), isTrue);
      expect(isSubtypeOf('Player', 'Component', names), isTrue);
      expect(isSubtypeOf('SceneStruct', 'Component', names), isFalse);
    });

    test('stops at a name it never read, rather than looping', () {
      final project = _project(<String, String>{
        'game.dart': 'class A extends B {}\nclass B extends A {}\n',
      });
      final names = _scan(project).typesByName;

      expect(isSubtypeOf('A', 'Component', names), isFalse);
    });

    test('a mixin on Component is one even with no engine read', () {
      // The state `good generate` runs in on a project that has never been
      // resolved: `Component` is a name and nothing else. Every check that
      // reads names still works, which is why the walk does not resolve.
      final project = _project(<String, String>{
        'game.dart': 'mixin Velocity on Component {}\n',
      });

      expect(
        isSubtypeOf('Velocity', 'Component', _scan(project).typesByName),
        isTrue,
      );
    });
  });

  group('scanStructRules', () {
    test('reports one mixin hiding another mixin\'s field', () {
      final project = _project(<String, String>{
        'game.dart': 'mixin Velocity on Component {\n'
            '  final speed = Field.float64();\n}\n'
            'mixin Momentum on Component {\n'
            '  final speed = Field.float64();\n}\n'
            'class Player extends EntityStruct with Velocity, Momentum {}\n',
      });
      final scan = scanStructRules(project);

      expect(scan.shadowed, hasLength(1));
      expect(scan.shadowed.single.later, 'Momentum');
      expect(scan.shadowed.single.earlier, 'Velocity');
      expect(
        shadowedFieldsMessage(scan),
        contains('Momentum.speed shadows Velocity.speed'),
      );
    });

    test('does not report a private field declared in another file', () {
      // A private field is library-scoped, so `_cached` on two mixins in two
      // files is two names and hides nothing.
      final project = _project(<String, String>{
        'a.dart': 'mixin A on Component {\n  final _cached = 0;\n}\n',
        'b.dart': 'mixin B on Component {\n  final _cached = 0;\n}\n',
        'game.dart': 'class Player extends EntityStruct with A, B {}\n',
      });

      expect(scanStructRules(project).shadowed, isEmpty);
    });

    test('reports a component describe override that drops the chain', () {
      final project = _project(<String, String>{
        'game.dart': 'mixin Velocity on Component {\n'
            '  @override\n'
            '  void describeType(ComponentDescriptor component) {\n'
            '    component.has<Velocity>();\n'
            '  }\n}\n',
      });
      final scan = scanStructRules(project);

      expect(scan.missingSuper, hasLength(1));
      expect(
        missingSuperMessage(scan),
        contains('Velocity.describeType does not call super.describeType()'),
      );
    });

    test('leaves an override of an abstract hook alone', () {
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

      expect(scanStructRules(project).missingSuper, isEmpty);
    });

    test('leaves an empty base declaration alone', () {
      final project = _project(<String, String>{
        'game.dart': 'mixin Velocity on Component {\n'
            '  @override\n'
            '  void describeAssets(Object descriptor) {}\n}\n',
      });

      expect(scanStructRules(project).missingSuper, isEmpty);
    });

    test('names a mixin it could not read rather than passing over it', () {
      final project = _project(<String, String>{
        'game.dart':
            'class Player extends EntityStruct with SomethingElsewhere {}\n',
      });

      expect(
        scanStructRules(project).unresolved.keys,
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
    test('an eager field is a declaration, named and typed', () {
      final scan = _declarations('''
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

    test('a late declaration is refused, whether or not it is assigned', () {
      // The Camera.cameraView shape - the field declared here, the value
      // assigned from a describe pass - and the `late final x = ...` shape,
      // which defers the initialiser to the first read instead.
      final scan = _declarations('''
class Player extends EntityStruct {
  late final DataPointer<double> filled;
  late final deferred = Field.float64();
}
''');

      expect(_refused(scan), <String>['Player.filled', 'Player.deferred']);
      expect(scan.declarers, isEmpty);
      expect(scan.refusals.first.reason, contains('freshly constructed'));
    });

    test('a declaration with no initialiser at all is refused', () {
      final scan = _declarations('''
class Player extends EntityStruct {
  DataPointer<double> filled;
}
''');

      expect(_refused(scan), <String>['Player.filled']);
      expect(scan.refusals.single.reason, contains('no initialiser'));
    });

    test('a static declaration is refused', () {
      final scan = _declarations('''
class Player extends EntityStruct {
  static final speed = Field.float64(220);
}
''');

      expect(_refused(scan), <String>['Player.speed']);
      expect(scan.refusals.single.reason, contains('lazily'));
    });

    test('a top-level declaration is refused, named by its file', () {
      final scan = _declarations('''
final speed = Field.float64(220);
''');

      expect(_refused(scan), <String>['game.dart.speed']);
      expect(scan.refusals.single.reason, contains('top-level'));
    });

    test('a nullable handle is a binding, not a declaration', () {
      // `Child._declaredIn` in `good/lib/src/data/hierarchy.dart`: a column on
      // somebody *else's* archetype, handed over at registration and null
      // until then. A column cannot be declared conditionally, so a nullable
      // handle is never a declaration - which is what keeps this off the
      // refusal list rather than on it with no way to satisfy it.
      final scan = _declarations('''
class Player extends EntityStruct {
  DataPointer<double>? bound;
}
''');

      expect(scan.refusals, isEmpty);
      expect(scan.declarers, isEmpty);
    });

    test('every ScannableField root counts, not just DataPointer', () {
      // The array root is separate - a DataArrayPointer is not a DataPointer -
      // so a pass testing one root drops every array column with nothing said.
      final scan = _declarations('''
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

    test('a class that is not Scannable declares nothing', () {
      final scan = _declarations('''
class Helper {
  final speed = Field.float64(220);
}
''');

      expect(scan.refusals, isEmpty);
      expect(scan.declarers, isEmpty);
    });

    test('a private declaration is accepted and listed as uncollectable', () {
      // Not refused. A collector cannot read it, and saying so is the whole
      // point; whether the engine's 28 private cache columns become public is
      // a separate call, and refusing here would be making it.
      final scan = _declarations('''
class Player extends EntityStruct {
  final _cached = Field.float64();
}
''');

      expect(scan.refusals, isEmpty);
      expect(scan.declarers.single.declarations.single.isPrivate, isTrue);
      expect(scan.uncollectable.keys, <String>['Player._cached']);
    });

    test('only a marked annotation is carried', () {
      final scan = _declarations('''
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
  });

  group('scanScenes', () {
    const String pubspec = '''
name: demo
flutter:
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

    test('attributes an asset to the scene that reaches its prefab', () {
      final project = sceneProject(<String, String>{
        'good.dart': _kernel,
        'game.dart': '''
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
      final usage = scanScenes(project, scanAssets(project));

      expect(usage.byScene.keys, <String>['MainScene']);
      expect(usage.byScene['MainScene'], contains('assets/player.png'));
      expect(
        usage.byScene['MainScene'],
        isNot(contains('assets/menu.png')),
        reason: 'nothing reaches it, so it is not this scene\'s to load',
      );
    });

    test('leaves an asset no scene reaches unattributed', () {
      final project = sceneProject(<String, String>{
        'good.dart': _kernel,
        'game.dart': '''
class MainScene extends SceneStruct {}

class Loose {
  final Object texture = Textures.menu;
}
''',
      });
      final usage = scanScenes(project, scanAssets(project));

      expect(usage.byScene['MainScene'], isEmpty);
      expect(usage.unresolved.keys, contains('menu'));
      expect(usage.unresolved.keys, contains('player'));
    });
  });
}
