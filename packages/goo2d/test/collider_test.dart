import 'package:goo2d/goo2d.dart';
import 'package:flutter_test/flutter_test.dart';

class _Player extends EntityStruct with Transform2D, Collider2D, CollisionListener {
  late final BoxBody box;
  late final CircleBody hurtbox;
  late final CircleBody pickupRange;

  final List<String> firedEvents = <String>[];

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(halfWidth: 16, halfHeight: 24);
    hurtbox = descriptor.hasCircleCollider(radius: 20);
    pickupRange = descriptor.hasCircleCollider(radius: 48, isTrigger: true);
  }

  @override
  void onCollisionEnter2D(Collision2DEvent event) => firedEvents.add('enter');
  @override
  void onTriggerEnter2D(Collision2DEvent event) => firedEvents.add('triggerEnter');
}

class _Wall extends EntityStruct with Transform2D, Collider2D {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(halfWidth: 100, halfHeight: 10);
  }
}

class _Polygon extends EntityStruct
    with Transform2D, Collider2D, EntityLifecycleListener {
  late final PolygonBody triangle;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    triangle = descriptor.hasPolygonCollider(maxPoints: 8);
  }

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    triangle.pointsX.set(entity, 0, 0);
    triangle.pointsY.set(entity, 0, 0);
    triangle.pointsX.set(entity, 1, 10);
    triangle.pointsY.set(entity, 1, 0);
    triangle.pointsX.set(entity, 2, 5);
    triangle.pointsY.set(entity, 2, 10);
    triangle.pointCount[entity] = 3;
  }
}

/// A capsule taller than it is wide, plus one deliberately squashed flatter
/// than its own radius - the degenerate case that has to read as a circle.
class _Capsule extends EntityStruct with Transform2D, Collider2D {
  late final CapsuleBody pill;
  late final CapsuleBody squashed;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    pill = descriptor.hasCapsuleCollider(radius: 10, halfHeight: 30);
    squashed = descriptor.hasCapsuleCollider(radius: 10, halfHeight: 4);
  }
}

/// A concave outline - an arrowhead with a notch cut out of its base. A
/// convex-only containment test passes every other polygon case and fails
/// this one, which is why it is here.
class _Concave extends EntityStruct
    with Transform2D, Collider2D, EntityLifecycleListener {
  late final PolygonBody arrow;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    arrow = descriptor.hasPolygonCollider(maxPoints: 8);
  }

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    // (0,0) tip, out to both base corners, with (0,20) notched back in
    // between them - so the point (0, 25) is inside the bounding box and
    // inside the convex hull, but outside the shape itself.
    const xs = <double>[0, 20, 0, -20];
    const ys = <double>[0, 40, 20, 40];
    for (var i = 0; i < xs.length; i++) {
      arrow.pointsX.set(entity, i, xs[i]);
      arrow.pointsY.set(entity, i, ys[i]);
    }
    arrow.pointCount[entity] = 4;
  }
}

class _Scene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Scene();

  late final _Player player;
  late final _Wall wall;
  late final _Polygon polygon;
  late final _Capsule capsule;
  late final _Concave concave;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    player = descriptor.has(_Player());
    wall = descriptor.has(_Wall());
    polygon = descriptor.has(_Polygon());
    capsule = descriptor.has(_Capsule());
    concave = descriptor.has(_Concave());
  }
}

_Scene _scene() {
  final scene = _Scene()..initializeScene(MemoryPool(pageSize: 4096));
  scene.handle = SceneRegistry.register(scene);
  addTearDown(scene.pool.dispose);
  return scene;
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('Collider2D as a MultiComponent', () {
    test('declaring several has*Collider calls is a compound collider - all end up in bodies', () {
      final scene = _scene();
      expect(scene.player.bodies, hasLength(3));
      expect(scene.player.bodies, containsAll([scene.player.box, scene.player.hurtbox, scene.player.pickupRange]));
    });

    test('named params on has*Collider double as the declared default, no onMounted needed', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      expect(scene.player.box.halfWidth[player], 16);
      expect(scene.player.box.halfHeight[player], 24);
      expect(scene.player.hurtbox.radius[player], 20);
      expect(scene.player.hurtbox.isTrigger[player], 0);
      expect(scene.player.pickupRange.radius[player], 48);
      expect(scene.player.pickupRange.isTrigger[player], 1);
      expect(scene.player.box.enable[player], 1, reason: 'enable defaults to true (1)');
    });

    test('each declared body has independent, non-aliasing storage', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      scene.pool.beginTick();
      scene.player.box.enable[player] = 0;
      scene.pool.commitTick();

      // Disabling box must not disturb hurtbox/pickupRange's own enable bit.
      expect(scene.player.box.enable[player], 0);
      expect(scene.player.hurtbox.enable[player], 1);
      expect(scene.player.pickupRange.enable[player], 1);
    });

    test('different prefabs are genuinely different archetypes with independent layouts', () {
      final scene = _scene();
      expect(scene.player.archetypeId, isNot(scene.wall.archetypeId));
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      final wall = scene.addEntity(scene.wall);
      scene.pool.commitTick();
      expect(scene.wall.box.halfWidth[wall], 100);
      expect(scene.player.box.halfWidth[player], 16);
    });
  });

  group('PolygonBody', () {
    test('point array round-trips independently per index, and pointCount is separate storage', () {
      final scene = _scene();
      scene.pool.beginTick();
      final triangle = scene.addEntity(scene.polygon);
      scene.pool.commitTick();

      expect(scene.polygon.triangle.pointCount[triangle], 3);
      expect(scene.polygon.triangle.pointsX.get(triangle, 0), 0);
      expect(scene.polygon.triangle.pointsY.get(triangle, 0), 0);
      expect(scene.polygon.triangle.pointsX.get(triangle, 1), 10);
      expect(scene.polygon.triangle.pointsY.get(triangle, 1), 0);
      expect(scene.polygon.triangle.pointsX.get(triangle, 2), 5);
      expect(scene.polygon.triangle.pointsY.get(triangle, 2), 10);
    });

    test('capacity is fixed at maxPoints - out of range throws rather than corrupting', () {
      final scene = _scene();
      scene.pool.beginTick();
      final triangle = scene.addEntity(scene.polygon);
      scene.pool.commitTick();
      expect(() => scene.polygon.triangle.pointsX.get(triangle, 8), throwsRangeError);
    });

    test('an entity can use fewer points than the declared capacity', () {
      final scene = _scene();
      scene.pool.beginTick();
      final triangle = scene.addEntity(scene.polygon);
      scene.pool.commitTick();
      // maxPoints defaults to 8 but this entity's onMounted only set 3 -
      // pointCount is what a consumer should trust, not the array's own
      // fixed capacity.
      expect(scene.polygon.triangle.pointCount[triangle], lessThan(scene.polygon.triangle.pointsX.length));
    });
  });

  group('CollisionListener', () {
    test('is a no-op-default mixin - a prefab overriding only some methods compiles and the rest stay silent', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      // Calling the un-overridden ones directly must not throw - they're
      // real no-op bodies, not abstract methods forcing an override.
      final event = Collision2DEvent()
        ..set(scene.player.box, player, scene.player.box, player);
      expect(() => scene.player.onCollisionExit2D(event), returnsNormally);
      expect(() => scene.player.onCollisionStay2D(event), returnsNormally);
      expect(() => scene.player.onTriggerExit2D(event), returnsNormally);
      expect(() => scene.player.onTriggerStay2D(event), returnsNormally);
      expect(scene.player.firedEvents, isEmpty, reason: 'none of the no-op ones should record anything');

      scene.player.onCollisionEnter2D(event);
      scene.player.onTriggerEnter2D(event);
      expect(scene.player.firedEvents, ['enter', 'triggerEnter']);
    });

    test('Collision2DEvent carries which entity, not just which prefab', () {
      final scene = _scene();
      scene.pool.beginTick();
      final a = scene.addEntity(scene.player);
      final b = scene.addEntity(scene.player);
      scene.pool.commitTick();

      // One instance, repointed per dispatch - a physics step can produce
      // hundreds of contacts and allocating per contact is the hot-path cost
      // RULES.md rule 1 forbids.
      final event = Collision2DEvent()
        ..set(scene.player.box, a, scene.player.hurtbox, b);
      expect(event.sourceEntity, a);
      expect(event.targetEntity, b);
      expect(event.source, isA<BoxBody>());
      expect(event.target, isA<CircleBody>());

      // Reused, not replaced: the same object answers for the next collision.
      event.set(scene.player.hurtbox, b, scene.player.box, a);
      expect(event.sourceEntity, b);
      expect(event.source, isA<CircleBody>());
    });
  });

  group('containsLocalPoint', () {
    test('a circle is a circle, not its bounding box', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      final circle = scene.player.hurtbox; // radius 20, no offset
      expect(circle.containsLocalPoint(player, 0, 0), isTrue);
      expect(circle.containsLocalPoint(player, 20, 0), isTrue,
          reason: 'exactly on the edge counts as inside - a boundary has to '
              'belong to one side, and picking the shape means the pixel you '
              'can see is clickable');
      expect(circle.containsLocalPoint(player, 20.001, 0), isFalse);
      expect(circle.containsLocalPoint(player, 14.1, 14.1), isTrue,
          reason: 'inside the circle: 14.1^2 * 2 = 397.6, just under 20^2');
      expect(circle.containsLocalPoint(player, 14.1, -14.1), isTrue);
      expect(circle.containsLocalPoint(player, 14.2, 14.2), isFalse,
          reason: 'and just outside it: 14.2^2 * 2 = 403.3, over 20^2 - the '
              'edge is where the radius says it is, not a tolerance');
      expect(circle.containsLocalPoint(player, 15, 15), isFalse,
          reason: 'the corner of the bounding box is outside the circle - '
              'this is the whole difference between hit-testing a shape and '
              'hit-testing a rectangle');
    });

    test('a box covers its full extent and nothing past it', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      final box = scene.player.box; // 16 x 24 half-extents
      expect(box.containsLocalPoint(player, 15.9, 23.9), isTrue);
      expect(box.containsLocalPoint(player, -16, -24), isTrue);
      expect(box.containsLocalPoint(player, 16.1, 0), isFalse);
      expect(box.containsLocalPoint(player, 0, 24.1), isFalse);
    });

    test('offset moves the shape, not the point', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      scene.pool.beginTick();
      scene.player.hurtbox.offsetX[player] = 100;
      scene.pool.commitTick();

      expect(scene.player.hurtbox.containsLocalPoint(player, 0, 0), isFalse,
          reason: 'the body moved out from under the origin');
      expect(scene.player.hurtbox.containsLocalPoint(player, 100, 0), isTrue);
    });

    test('a capsule is a rectangle with round ends', () {
      final scene = _scene();
      scene.pool.beginTick();
      final entity = scene.addEntity(scene.capsule);
      scene.pool.commitTick();

      // radius 10, half-height 30 - so the straight section runs -20..20 and
      // each cap centre sits at +/-20.
      final pill = scene.capsule.pill;
      expect(pill.containsLocalPoint(entity, 10, 0), isTrue,
          reason: 'the straight section is the full radius wide');
      expect(pill.containsLocalPoint(entity, 10, 20), isTrue,
          reason: 'and stays that wide right up to the cap centre');
      expect(pill.containsLocalPoint(entity, 0, 30), isTrue,
          reason: 'the very top of the cap - halfHeight is the *total* half '
              'height, caps included, like Unity\'s own capsule size');
      expect(pill.containsLocalPoint(entity, 0, 30.1), isFalse);
      expect(pill.containsLocalPoint(entity, 10, 30), isFalse,
          reason: 'the corner of the bounding box is rounded away - that is '
              'the only thing that makes this a capsule and not a box');
      expect(pill.containsLocalPoint(entity, 7, 27), isTrue,
          reason: 'inside the top cap: 7^2 + 7^2 is under 10^2');
    });

    test('a capsule shorter than its radius is a circle', () {
      final scene = _scene();
      scene.pool.beginTick();
      final entity = scene.addEntity(scene.capsule);
      scene.pool.commitTick();

      // radius 10, half-height 4: the straight section would be -6 long.
      final squashed = scene.capsule.squashed;
      expect(squashed.containsLocalPoint(entity, 0, 9), isTrue,
          reason: 'the degenerate case has an obvious right answer - a '
              'segment of negative length is a point, so this is a circle of '
              'the declared radius rather than an error or an empty shape');
      expect(squashed.containsLocalPoint(entity, 0, 10), isTrue);
      expect(squashed.containsLocalPoint(entity, 0, 10.1), isFalse);
      expect(squashed.containsLocalPoint(entity, 8, 8), isFalse);
    });

    test('a polygon follows its outline', () {
      final scene = _scene();
      scene.pool.beginTick();
      final entity = scene.addEntity(scene.polygon);
      scene.pool.commitTick();

      // The triangle (0,0), (10,0), (5,10).
      final triangle = scene.polygon.triangle;
      expect(triangle.containsLocalPoint(entity, 5, 5), isTrue);
      expect(triangle.containsLocalPoint(entity, 5, 1), isTrue);
      expect(triangle.containsLocalPoint(entity, 1, 8), isFalse,
          reason: 'inside the bounding box, outside the sloped edge');
      expect(triangle.containsLocalPoint(entity, 9, 8), isFalse);
      expect(triangle.containsLocalPoint(entity, 5, 11), isFalse);
    });

    test('a concave polygon keeps its notch', () {
      final scene = _scene();
      scene.pool.beginTick();
      final entity = scene.addEntity(scene.concave);
      scene.pool.commitTick();

      final arrow = scene.concave.arrow;
      expect(arrow.containsLocalPoint(entity, 0, 10), isTrue,
          reason: 'up the middle of the arrowhead, above the notch');
      expect(arrow.containsLocalPoint(entity, 12, 30), isTrue,
          reason: 'inside the right barb');
      expect(arrow.containsLocalPoint(entity, 0, 30), isFalse,
          reason: 'inside the bounding box and inside the convex hull, but '
              'in the notch - a convex-only test would report a hit here');
    });

    test('a polygon with fewer than three points contains nothing', () {
      final scene = _scene();
      scene.pool.beginTick();
      final entity = scene.addEntity(scene.polygon);
      scene.pool.commitTick();

      scene.pool.beginTick();
      scene.polygon.triangle.pointCount[entity] = 2;
      scene.pool.commitTick();

      expect(scene.polygon.triangle.containsLocalPoint(entity, 5, 5), isFalse,
          reason: 'two points enclose no area, and the default pointCount is '
              'zero - a prefab that forgot to populate its outline should '
              'pick up nothing rather than everything');
    });

    test('a disabled body still answers the geometry question', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      scene.pool.beginTick();
      scene.player.hurtbox.enable[player] = 0;
      scene.pool.commitTick();

      expect(scene.player.hurtbox.containsLocalPoint(player, 0, 0), isTrue,
          reason: 'containsLocalPoint is about the shape, not about policy - '
              'whether a disabled body should be skipped belongs to the '
              'caller, and a debug overlay drawing every declared shape '
              'wants the honest answer');
    });
  });
}
