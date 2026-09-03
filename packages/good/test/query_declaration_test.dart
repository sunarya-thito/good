import 'package:good/src/archetype.dart';
import 'package:good/src/scannable.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';
import 'package:flutter_test/flutter_test.dart';

// Three component types and no prefab, because nothing here is about rows.
// What is under test is the numbering: which `ComponentTypeRegistry` a query
// takes its bits out of, and when.
//
// An archetype signature is built by ORing `ComponentTypeRegistry.bitFor` per
// declared type - that one line is the whole of `ArchetypeComponentDescriptor.
// has` - so a signature written by hand here is the same value a registered
// archetype would carry, without a scene to register one.
mixin _Position on Component {}

mixin _Health on Component {}

mixin _Cloaked on Component {}

void main() {
  setUp(ComponentTypeRegistry.reset);
  tearDown(ComponentTypeRegistry.reset);

  group('numbered where it resolves, not where it is written', () {
    test('writing one takes no bit', () {
      // The registry a `GameState`'s field initialisers run against: main's,
      // which `_bootMain` never fills and `_bootGame` never reaches. A system
      // held on a state field is built here, so this is where its queries are
      // written.
      expect(ComponentTypeRegistry.assignedCount, 0);

      Query.all(_Position, _Health);
      Query.where()
          .withAll(_Position)
          .withNone(_Health)
          .withAny(_Cloaked, _Health)
          .withOptional(_Cloaked)
          .build();
      Query.has<_Position>();

      expect(
        ComponentTypeRegistry.assignedCount,
        0,
        reason:
            'a bit assigned here is a number out of a table nothing on '
            'this copy ever compares a signature against',
      );
    });

    test('resolving one takes its bits from the registry it resolves in', () {
      // Written where nothing has registered: eagerly, `_Health` would take
      // the first bit here.
      final health = Query.all(_Health);
      final anyOf = Query.where().withAny(_Health, _Cloaked).build();
      final single = Query.has<_Health>();

      // The spawn. Every static is per-isolate and main's table does not ride
      // the copy, so resetting is how one process stands in for two: whatever
      // main assigned is gone, and this side numbers from zero in its own
      // order - `_Position` first, because that is the order its scenes
      // register. Without this line the two halves share one table and a
      // query numbered in the wrong one still reads right, which is the whole
      // failure this test exists to see.
      ComponentTypeRegistry.reset();
      final position = ComponentTypeRegistry.bitFor(_Position);
      final healthBit = ComponentTypeRegistry.bitFor(_Health);
      expect(position, isNot(healthBit));

      ArchetypeQueryDescriptor()
        ..declare(<ScannableField>[health, anyOf, single])
        ..resolve();

      expect(health.matches(healthBit), isTrue);
      expect(health.matches(position), isFalse);
      expect(anyOf.matches(healthBit), isTrue);
      expect(anyOf.matches(position), isFalse);
      expect(single.matches(healthBit), isTrue);
      expect(single.matches(position), isFalse);
    });

    test('an optional type still holds a bit, and takes it at the resolve', () {
      final query = Query.where()
          .withAll(_Position)
          .withOptional(_Cloaked)
          .build();
      expect(ComponentTypeRegistry.assignedCount, 0);

      ArchetypeQueryDescriptor()
        ..declare(<ScannableField>[query])
        ..resolve();

      expect(ComponentTypeRegistry.assignedCount, 2);
      // Narrows nothing: an archetype without it still matches.
      expect(query.matches(ComponentTypeRegistry.bitFor(_Position)), isTrue);
    });

    test('a query the pass never saw is refused, not answered', () {
      final orphan = Query.all(_Position);
      expect(
        () => orphan.matches(ComponentTypeRegistry.bitFor(_Health)),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            contains('still holds the types it named and no bits'),
          ),
        ),
      );
    });

    test('a declaration that is not a query is left alone', () {
      final query = Query.all(_Position);
      final descriptor = ArchetypeQueryDescriptor()
        ..declare(<ScannableField>[_NotAQuery(), query])
        ..resolve();
      expect(descriptor, isNotNull);
      expect(query.matches(ComponentTypeRegistry.bitFor(_Position)), isTrue);
    });
  });

  group('the bare-Type check', () {
    test('fires at the call that named the type, not at the resolve', () {
      expect(
        () => Query.all(_Position, String),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('a query names Component types'),
              contains('String is not one'),
            ),
          ),
        ),
      );
      expect(
        () => Query.where().withNone(int).build(),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Query.where().withOptional(double).build(),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Query.where().withAny(_Position, bool).build(),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}

/// A declaration of the kind this pass does not resolve.
final class _NotAQuery implements ScannableField {}
