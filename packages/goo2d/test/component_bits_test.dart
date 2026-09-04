// The generated table `good_tool` writes for this package (#18), against the
// real component types rather than against fixtures.
//
// The indices below are written out rather than derived. That is the point of
// the whole exercise: a bit index that a test computes from the same table it
// is checking would pass however the table was reordered, and what has to hold
// is that this repository hands `Transform2D` bit 3 on every machine and in
// every run. A regeneration that reorders anything fails here, in the same
// commit that moved it.

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

part 'component_bits_test.g.dart';

class _Ship extends EntityStruct with Transform2D, WorldTransform2D {}

class _Eye extends EntityStruct with Transform2D, Camera {}

class _Bare extends EntityStruct with Child {}

/// One declaration order.
class _Forward extends SceneStruct {
  _Forward();

  @sub
  final ship = _Ship();
  @sub
  final eye = _Eye();
  @sub
  final bare = _Bare();
}

/// The same three prefabs, declared the other way round - a second project, or
/// the same one after somebody moved a line.
class _Reversed extends SceneStruct {
  _Reversed();

  @sub
  final bare = _Bare();
  @sub
  final eye = _Eye();
  @sub
  final ship = _Ship();
}

T _build<T extends SceneStruct>(T scene) {
  scene.initializeScene(MemoryPool(pageSize: 4096));
  SceneRegistry.register(scene);
  addTearDown(scene.pool.dispose);
  return scene;
}

/// What a `withAll(...)` of [types] compiles to.
int _required(List<Type> types) =>
    types.fold(0, (mask, type) => mask | ComponentTypeRegistry.bitFor(type));

bool _matches(ArchetypeStorage storage, int required) =>
    storage.componentSignature & required == required;

void main() {
  _installDeclarations();

  setUp(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('goo2dComponentBits', () {
    test('numbers this package and good, in one fixed order', () {
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        goo2dComponentBits,
      ]);
      expect(ComponentTypeRegistry.seededCount, 11);
      // `goo2d` sorts before `good` - the digit beats the letter - and inside
      // each table the order is the declaring file, then the type name.
      expect(ComponentTypeRegistry.indexFor(Camera), 0);
      expect(ComponentTypeRegistry.indexFor(Collider2D), 1);
      expect(ComponentTypeRegistry.indexFor(ScreenTransform2D), 2);
      expect(ComponentTypeRegistry.indexFor(Transform2D), 3);
      expect(ComponentTypeRegistry.indexFor(WorldTransform2D), 4);
      expect(ComponentTypeRegistry.indexFor(HoverReceiver), 5);
      expect(ComponentTypeRegistry.indexFor(PointerReceiver), 6);
      expect(ComponentTypeRegistry.indexFor(Renderable2D), 7);
      expect(ComponentTypeRegistry.indexFor(Text2D), 8);
      expect(ComponentTypeRegistry.indexFor(Child), 9);
      expect(ComponentTypeRegistry.indexFor(Parent), 10);
    });

    test('leaves each of the eleven a bit of its own', () {
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        goo2dComponentBits,
      ]);
      final types = <Type>[
        Child,
        Parent,
        Camera,
        Collider2D,
        ScreenTransform2D,
        Transform2D,
        WorldTransform2D,
        HoverReceiver,
        PointerReceiver,
        Renderable2D,
        Text2D,
      ];
      final masks = <int>[
        for (final type in types) ComponentTypeRegistry.bitFor(type),
      ];
      expect(masks.toSet().length, types.length);
      expect(masks.fold<int>(0, (a, b) => a | b), 0x7FF);
    });
  });

  group('a component mask', () {
    test('is the same under two opposite scene declaration orders', () {
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        goo2dComponentBits,
      ]);
      _build(_Forward());
      final forward = _required(<Type>[Transform2D, WorldTransform2D, Camera]);

      SceneRegistry.reset();
      ArchetypeRegistry.reset();
      ComponentTypeRegistry.reset();
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        goo2dComponentBits,
      ]);
      _build(_Reversed());
      expect(_required(<Type>[Transform2D, WorldTransform2D, Camera]), forward);
    });

    test('is not, with nothing seeded - which is what this replaces', () {
      _build(_Forward());
      final forward = _required(<Type>[Transform2D, WorldTransform2D, Camera]);

      SceneRegistry.reset();
      ArchetypeRegistry.reset();
      ComponentTypeRegistry.reset();
      _build(_Reversed());
      expect(
        _required(<Type>[Transform2D, WorldTransform2D, Camera]),
        isNot(forward),
        reason: 'first-seen order follows the scene, which is why '
            'archetype.dart says not to persist a signature',
      );
    });

    test('still matches the archetypes that carry it and no others', () {
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        goo2dComponentBits,
      ]);
      final scene = _build(_Forward());
      // Three archetypes with three different component sets, because a scene
      // with one cannot tell "matches the right one" from "matches anything".
      final camera = _required(<Type>[Camera]);
      expect(_matches(scene.eye.archetype, camera), isTrue);
      expect(_matches(scene.ship.archetype, camera), isFalse);
      expect(_matches(scene.bare.archetype, camera), isFalse);

      final transform = _required(<Type>[Transform2D]);
      expect(_matches(scene.ship.archetype, transform), isTrue);
      expect(_matches(scene.eye.archetype, transform), isTrue);
      expect(_matches(scene.bare.archetype, transform), isFalse);

      final both = _required(<Type>[Transform2D, WorldTransform2D]);
      expect(_matches(scene.ship.archetype, both), isTrue);
      expect(_matches(scene.eye.archetype, both), isFalse);
    });

    test('a type in no table matches nothing rather than everything', () {
      // #293: the claim that an unregistered type "silently matches every
      // archetype" is the wrong way round. `bitFor` hands it a fresh bit, and
      // no archetype's signature carries that bit.
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        goo2dComponentBits,
      ]);
      final scene = _build(_Forward());
      final never = _required(<Type>[_Ship]);
      expect(_matches(scene.eye.archetype, never), isFalse);
      expect(_matches(scene.bare.archetype, never), isFalse);
      // And on the one archetype that does carry it, it matches.
      expect(_matches(scene.ship.archetype, never), isTrue);
    });
  });
}
