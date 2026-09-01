import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/data/hierarchy.dart';
import 'package:good/src/declare.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';

// A component declares its own type in a field, so a prefab that mixes it in
// carries the bit without writing anything (#287). What this file pins is the
// four things that were a hook body's job and are now the framework's:
// attribution to the right archetype, the barrier, the prefab's own bit, and
// the pair a component refuses.

mixin _Armour on Component {
  final armourType = Component.type<_Armour>();

  final armourPlates = Field.uint8(3);
}

mixin _Cloaked on Component {
  final cloakedType = Component.type<_Cloaked>();
}

/// Declares a type it refuses to share an archetype with.
mixin _Solid on Component {
  final solidType = Component.type<_Solid>(
    conflictsWith: <Type, String>{
      _Cloaked: 'A solid body is drawn, and a cloaked one is not.',
    },
  );
}

/// Declares columns and no type at all, which is legal and means it is not
/// queryable.
mixin _Untyped on Component {
  final untypedMark = Field.uint8(1);
}

class _Barrel extends EntityStruct with Child, _Cloaked {}

class _Turret extends EntityStruct with Parent, _Armour {
  final barrel = EntityStruct.of(_Barrel.new);
}

class _Plain extends EntityStruct with _Untyped {}

class _Clash extends EntityStruct with _Solid, _Cloaked {}

/// Carries the half of the refused pair that declares the refusal, and not the
/// half it names.
class _Shielded extends EntityStruct with _Solid {}

/// Declares a component type from a `describeStruct` body, which runs after
/// the constructor and so has no registrar open.
class _LateDeclarer extends EntityStruct with _Armour {
  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    Component.type<_Cloaked>();
  }
}

class _Level extends SceneStruct {
  _Level(this._prefabs);

  final List<EntityStruct Function()> _prefabs;

  final List<EntityStruct> registered = <EntityStruct>[];

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    for (final create in _prefabs) {
      registered.add(descriptor.has(create));
    }
  }
}

_Level _level(List<EntityStruct Function()> prefabs) {
  final level = _Level(prefabs)..initializeScene(MemoryPool(pageSize: 4096));
  SceneRegistry.register(level);
  addTearDown(level.pool.dispose);
  return level;
}

/// What [_level] throws while registering, or `null` if it got through.
Object? _levelError(List<EntityStruct Function()> prefabs) {
  try {
    _level(prefabs);
    return null;
  } catch (error) {
    return error;
  }
}

bool _carries(EntityStruct prefab, Type type) =>
    prefab.archetype.componentSignature &
        ComponentTypeRegistry.bitFor(type) !=
    0;

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('a component type declared in a field', () {
    test('is in the signature of every prefab that mixes the component in', () {
      final level = _level(<EntityStruct Function()>[_Turret.new, _Plain.new]);
      final turret = level.registered[0];
      final plain = level.registered[1];

      expect(_carries(turret, _Armour), isTrue);
      expect(
        _carries(plain, _Armour),
        isFalse,
        reason: 'a prefab that does not mix it in must not carry the bit, or '
            'withNone would exclude nothing',
      );
    });

    test('leaves a component that declares none out of every signature', () {
      final level = _level(<EntityStruct Function()>[_Plain.new]);
      expect(_carries(level.registered.single, _Untyped), isFalse);
    });

    test('hands back the bit it declared', () {
      final level = _level(<EntityStruct Function()>[_Turret.new]);
      final turret = level.registered.single as _Turret;
      expect(
        (turret as _Armour).armourType.bit,
        ComponentTypeRegistry.bitFor(_Armour),
      );
      expect((turret as _Armour).armourType.type, _Armour);
    });

    test('lands on the prefab being constructed, not on its declarer', () {
      // `_Turret` registers `_Barrel` from a field initialiser, so the two
      // constructions are nested. `_Cloaked` is `_Barrel`'s and must not reach
      // the turret; `_Armour` is the turret's and must not reach the barrel.
      final level = _level(<EntityStruct Function()>[_Turret.new]);
      final turret = level.registered.single as _Turret;

      expect(_carries(turret, _Armour), isTrue);
      expect(_carries(turret, _Cloaked), isFalse);
      expect(_carries(turret.barrel, _Cloaked), isTrue);
      expect(_carries(turret.barrel, _Armour), isFalse);
    });

    test("carries the prefab's own type, which no source names", () {
      final level = _level(<EntityStruct Function()>[_Turret.new]);
      final turret = level.registered.single;
      expect(
        _carries(turret, _Turret),
        isTrue,
        reason: 'withAll(_Turret) is how a query names one archetype, and the '
            'bit comes from runtimeType after the constructor returns',
      );
    });
  });

  group('a declaration with no prefab being constructed', () {
    test('names the field-initialiser spelling and throws', () {
      expect(
        () => Component.type<_Armour>(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('no struct being constructed'),
              contains('Component.type<Health>()'),
            ),
          ),
        ),
      );
    });

    test('is what a describeStruct body gets, rather than the outer prefab', () {
      // The barrier. Without it this declaration lands on whatever construction
      // is still open one level out, which for a nested prefab is its declarer:
      // a bit on the wrong archetype, silently.
      final error = _levelError(<EntityStruct Function()>[_LateDeclarer.new]);
      expect(error, isA<StateError>());
      expect('$error', contains('no struct being constructed'));
    });
  });

  group('a refused pair of components', () {
    test('fails the registration, naming the prefab and both types', () {
      final error = _levelError(<EntityStruct Function()>[_Clash.new]);
      expect(error, isNotNull, reason: 'declaring the prefab has to fail');
      expect(
        '$error',
        allOf(
          contains('_Clash'),
          contains('_Solid'),
          contains('_Cloaked'),
          contains('A solid body is drawn, and a cloaked one is not.'),
        ),
      );
    });

    test('is silent when only one of the pair is there', () {
      expect(
        _levelError(<EntityStruct Function()>[_Barrel.new]),
        isNull,
        reason: '_Barrel is _Cloaked and not _Solid, so nothing is refused',
      );
    });

    test('spends no bit on the component it names', () {
      // `_Shielded` mixes in `_Solid`, so the refusal of `_Cloaked` is
      // recorded and the check does ask about `_Cloaked`. Nothing in this
      // scene declares `_Cloaked`, so it must still hold no bit: a signature
      // holds sixty-four, and a refusal is a question, not a declaration.
      expect(ComponentTypeRegistry.declaredBitFor(_Cloaked), 0);
      final level = _level(<EntityStruct Function()>[_Shielded.new]);
      expect(_carries(level.registered.single, _Solid), isTrue);
      expect(
        ComponentTypeRegistry.declaredBitFor(_Cloaked),
        0,
        reason: 'asking whether the archetype carries _Cloaked must not be '
            'what gives _Cloaked a bit',
      );
    });
  });

  group('the declaration stack', () {
    test('is left as it was found when a constructor throws', () {
      expect(
        () => _level(<EntityStruct Function()>[_Boom.new]),
        throwsA(isA<UnimplementedError>()),
      );
      expect(
        () => DeclarationContext.components,
        throwsA(isA<StateError>()),
        reason: 'the push has to be paired with a pop in a finally',
      );
    });
  });
}

class _Boom extends EntityStruct with _Armour {
  _Boom() {
    throw UnimplementedError('constructing this prefab fails');
  }
}
