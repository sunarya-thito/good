// The one order in this repository that a generator has to reproduce rather
// than choose, and the only test that can fail if it stops reproducing it.
//
// `collectDeclarations` hands a class's declarations to
// `ArchetypeDataDescriptor.declare`, which reserves in the order it is given,
// so the list a collector returns *is* the field order of every row of that
// archetype. While the ambient declaration window still existed, that order
// was whatever Dart's field initialisers did; the window is gone and nothing
// runs at a declaration now, so `flattenedDeclarations` has to walk the
// `extends` and `with` clauses and arrive at the same answer.
//
// # Why the fixture is this file
//
// Both halves have to come from one source text or the test proves nothing.
// So the shapes below are real Dart, constructed here to record the order
// Dart actually initialised them in - and this file's own source is copied
// into a temp directory and scanned, so the scan reads exactly the classes
// that ran. A fixture written as a string beside a copy of it in Dart would
// let the two drift apart, which is the failure this is meant to catch.

import 'dart:io';

// ignore: implementation_imports
import 'package:good_cli/src/generate/scan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '_repo.dart';

// ---------------------------------------------------------------------------
// A stand-in engine, in this file so the scan reads it with everything else
// ---------------------------------------------------------------------------

/// Stands in for `good`'s marker of the same name - the supertype walk finds
/// it by name through what it read, so a local one is the real thing as far
/// as a scan is concerned.
abstract interface class Scannable {}

/// Stands in for `good`'s marker that makes a field's value a declaration.
abstract interface class ScannableField {}

/// What a declaration produces here. It records itself, which is what makes
/// the runtime half of this test readable at all.
class Declared implements ScannableField {
  Declared(this.name) {
    initialised.add(name);
  }

  final String name;
}

/// Every declaration built so far, in the order it was built.
final List<String> initialised = <String>[];

/// Stands in for `Field`. A declaration is recognised by the declared return
/// type of the static that produced it, so this has to have one.
abstract final class Mark {
  static Declared of(String name) => Declared(name);
}

// ---------------------------------------------------------------------------
// The shape
// ---------------------------------------------------------------------------

abstract class Root implements Scannable {
  final rootA = Mark.of('Root.rootA');
  final rootB = Mark.of('Root.rootB');
}

class Middle extends Root {
  final middleA = Mark.of('Middle.middleA');
}

mixin First on Root {
  final firstA = Mark.of('First.firstA');
  final firstB = Mark.of('First.firstB');
}

mixin Second on Root {
  final secondA = Mark.of('Second.secondA');
}

mixin Third on Root {
  final thirdA = Mark.of('Third.thirdA');
}

class Leaf extends Middle with First, Second, Third {
  final leafA = Mark.of('Leaf.leafA');
  final leafB = Mark.of('Leaf.leafB');
}

void main() {
  group('declaration order', () {
    // Written out so a reader can see the claim without running anything, and
    // so a change that broke both halves the same way still fails.
    const expected = <String>[
      'Leaf.leafA',
      'Leaf.leafB',
      'Third.thirdA',
      'Second.secondA',
      'First.firstA',
      'First.firstB',
      'Middle.middleA',
      'Root.rootA',
      'Root.rootB',
    ];

    test('Dart runs own fields, then mixins backwards, then the superclass', () {
      initialised.clear();
      Leaf();
      expect(
        initialised,
        expected,
        reason:
            'This is the language, not a convention: a class runs its own '
            'field initialisers before its superclass constructor, and a '
            'mixin application is a superclass - so the last name in the '
            'with clause is initialised first. Everything downstream of '
            'collectDeclarations is laid out in this order.',
      );
    });

    test('flattenedDeclarations arrives at the same order', () async {
      final dir = testTempDir('declaration_order');
      final source = File(
        p.join(Directory.current.path, 'test', 'declaration_order_test.dart'),
      );
      expect(
        source.existsSync(),
        isTrue,
        reason:
            'This test scans its own source, so it has to be run from the '
            'good_tool package root - which is where `dart test` puts the '
            'working directory.',
      );
      File(p.join(dir.path, 'fixture.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(source.readAsStringSync());

      final read = await readSources(dir, rootOverride: <String>[dir.path]);
      expect(read.unparsed, isEmpty);
      final typesByName = read.typesByName;
      final leaf = typesByName['Leaf'];
      expect(leaf, isNotNull);

      final flattened = flattenedDeclarations(
        leaf!,
        typesByName,
        markers: scannableAnnotationNames(read),
      );
      expect(
        <String>[
          for (final declaration in flattened)
            '${declaration.owner}.${declaration.name}',
        ],
        expected,
      );
    });

    test('a mixin contributes its own fields and none of its on type\'s', () async {
      final dir = testTempDir('declaration_order_mixin');
      File(p.join(dir.path, 'fixture.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          File(
            p.join(
              Directory.current.path,
              'test',
              'declaration_order_test.dart',
            ),
          ).readAsStringSync(),
        );
      final read = await readSources(dir, rootOverride: <String>[dir.path]);
      final typesByName = read.typesByName;

      // `mixin First on Root` names Root, and Root's two declarations belong
      // to whichever class applies First - once, through its own superclass
      // chain. A walk that followed `on` would hand them over again per mixin,
      // and Leaf's row would hold rootA three times over.
      expect(
        <String>[
          for (final declaration in flattenedDeclarations(
            typesByName['First']!,
            typesByName,
            markers: scannableAnnotationNames(read),
          ))
            declaration.name,
        ],
        <String>['firstA', 'firstB'],
      );
    });
  });
}
