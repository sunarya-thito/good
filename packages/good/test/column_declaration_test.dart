// What a `Field.*` declaration does, and - mostly - what it does not.
//
// A declaration names a column and works nothing out. Every question that
// could be answered wrong is answered at the reservation pass instead, where
// there is an archetype and a prefab to name, so the tests here are about
// *when* a mistake surfaces rather than about what the column then holds.
//
// The two halves are separate claims and each has its own test. A declaration
// nothing collects has to be able to hold a mistake in silence, or the rule
// buys nothing; and one that is collected has to report the mistake with the
// class attached, or the rule costs a diagnosis.

import 'package:flutter_test/flutter_test.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scannable.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';

part 'column_declaration_test.g.dart';

/// A representation whose width no row can hold.
///
/// 65 rather than 0 or -1, because the refusal is about a value that does not
/// fit in the row and not about a nonsense number: a representation is user
/// code, and this is what one that miscounts its own bits looks like.
class _TooWide implements IntRepresentation<_Wide> {
  const _TooWide();

  @override
  int get bitWidth => 65;

  @override
  _Wide unpack(int packed) => const _Wide();

  @override
  _Wide? tryUnpack(int bits) => const _Wide();
}

class _Wide implements IntRepresentable {
  const _Wide();

  @override
  int pack() => 0;
}

/// Declares a column the row cannot hold, and is registered.
class _WideColumn extends EntityStruct {
  final wide = Field.packed(const _TooWide(), const _Wide());
}

/// Declares an array with no elements, and is registered.
class _EmptyArray extends EntityStruct {
  final slots = Field.array(.uint8, 0);
}

/// Constructed, and handed to nothing.
///
/// A prefab reaches a row layout by being registered - `SceneDescriptor.has`,
/// or a field of a scene the generator saw. One that is only constructed
/// declares into nothing, which is what this pins: its malformed column has
/// to cost nothing at all.
///
/// The case #404 names for this, a subclass shadowing an inherited column, is
/// not reachable: `good_tool` lists a shadowed field once per class in the
/// chain and every one of those reads answers with the override, so the
/// override is collected twice and realizing it twice throws. That is a
/// defect of the collector rather than of the declaration, and it is the same
/// before and after the split.
class _NeverRegistered extends EntityStruct {
  final slots = Field.array(.uint8, 0);
  final wide = Field.packed(const _TooWide(), const _Wide());
}

/// The registration error a scene's prefab produced, or null.
///
/// A column reserves its row space at realize, so a refusal there comes out
/// of the registration and never reaches a scene handle.
Object? _registrationError(SceneStruct scene) {
  final pool = MemoryPool(pageSize: 4096);
  addTearDown(pool.dispose);
  try {
    scene.initializeScene(pool);
  } catch (error) {
    return error;
  }
  return null;
}

class _WideScene extends SceneStruct {
  @prefab
  final wide = _WideColumn();
}

class _EmptyArrayScene extends SceneStruct {
  @prefab
  final empty = _EmptyArray();
}

void main() {
  _installDeclarations();

  setUp(() {
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  tearDown(SceneRegistry.reset);

  group('a declaration works nothing out', () {
    test('a malformed one can be written', () {
      // Nothing has been collected at this line and nothing ever will be, so
      // there is no class to attribute a refusal to and no row for the
      // column to be wrong about. Both of these threw here before the split.
      expect(() => Field.array(.uint8, 0), returnsNormally);
      expect(
        () => Field.packed(const _TooWide(), const _Wide()),
        returnsNormally,
      );
    });

    test('a prefab nothing registers declares into nothing', () {
      // Constructing it runs both initialisers, and both of them ask for
      // something no row could hold. Nothing collects them, so nothing is
      // laid out and nothing can be refused - which is the property the rule
      // buys: "was this collected" and "did this run" stop being different
      // questions.
      expect(_NeverRegistered.new, returnsNormally);
    });
  });

  group('a malformed declaration is reported at the reservation pass', () {
    test('a representation wider than a row, naming the prefab', () {
      final error = _registrationError(_WideScene());

      // On the message, not on the type: the reservation pass wraps every
      // `ArgumentError` a column raises, so the type alone would pass for any
      // of them - including a `RangeError`, which is one.
      expect(error, isA<StateError>());
      expect(
        (error! as StateError).message,
        allOf(
          contains('_WideColumn'),
          contains('declares a width outside 1..64'),
        ),
        reason:
            'the class is the half a field initialiser could not supply; '
            'without it the message names only the representation',
      );
    });

    test('an array with no elements, naming the prefab', () {
      final error = _registrationError(_EmptyArrayScene());

      expect(error, isA<StateError>());
      expect(
        (error! as StateError).message,
        allOf(contains('_EmptyArray'), contains('must be at least 1')),
      );
    });
  });
}
