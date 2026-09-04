import 'package:goo2d/goo2d.dart';
import 'package:flutter_test/flutter_test.dart';

part 'collider_test.g.dart';

class _Player extends EntityStruct
    with Transform2D, Collider2D, CollisionListener {
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
  void onTriggerEnter2D(Collision2DEvent event) =>
      firedEvents.add('triggerEnter');
}

class _Wall extends EntityStruct with Transform2D, Collider2D {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(halfWidth: 100, halfHeight: 10);
  }
}

/// Three points in eight slots, so the cases below can tell the outline
/// apart from the capacity it is stored in.
class _Polygon extends EntityStruct with Transform2D, Collider2D {
  late final PolygonBody triangle;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    triangle = descriptor.hasPolygonCollider(
      points: const [(0, 0), (10, 0), (5, 10)],
      maxPoints: 8,
    );
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
class _Concave extends EntityStruct with Transform2D, Collider2D {
  late final PolygonBody arrow;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    // (0,0) tip, out to both base corners, with (0,20) notched back in
    // between them - so the point (0, 25) is inside the bounding box and
    // inside the convex hull, but outside the shape itself.
    arrow = descriptor.hasPolygonCollider(
      points: const [(0, 0), (20, 40), (0, 20), (-20, 40)],
    );
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
    player = descriptor.has(_Player.new);
    wall = descriptor.has(_Wall.new);
    polygon = descriptor.has(_Polygon.new);
    capsule = descriptor.has(_Capsule.new);
    concave = descriptor.has(_Concave.new);
  }
}

/// A prefab whose one collider is whatever [_declare] declares, so a case
/// can assert on what `hasPolygonCollider` rejects.
class _AdHoc extends EntityStruct with Transform2D, Collider2D {
  _AdHoc(this._declare);

  final void Function(ColliderDescriptor descriptor) _declare;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    _declare(descriptor);
  }
}

class _AdHocScene extends SceneStruct {
  _AdHocScene(this._declare);

  final void Function(ColliderDescriptor descriptor) _declare;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    descriptor.has(() => _AdHoc(_declare));
  }
}

/// Builds the layout for a prefab declaring [declare], which is where a
/// rejected declaration throws - `describeCollider` runs from
/// `initializeScene`.
void _adHocScene(void Function(ColliderDescriptor descriptor) declare) {
  final pool = MemoryPool(pageSize: 4096);
  addTearDown(pool.dispose);
  _AdHocScene(declare).initializeScene(pool);
}

_Scene _scene() {
  final scene = _Scene()..initializeScene(MemoryPool(pageSize: 4096));
  scene.handle = SceneRegistry.register(scene);
  addTearDown(scene.pool.dispose);
  return scene;
}

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('Collider2D as a MultiComponent', () {
    test('declaring several has*Collider calls is a compound collider - all end up in bodies', () {
      final scene = _scene();
      expect(scene.player.bodies, hasLength(3));
      expect(
        scene.player.bodies,
        containsAll([
          scene.player.box,
          scene.player.hurtbox,
          scene.player.pickupRange,
        ]),
      );
    });

    test('named params on has*Collider double as the declared default, no onMounted needed', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      expect(scene.player.box.halfWidth[player], 16);
      expect(scene.player.box.halfHeight[player], 24);
      expect(scene.player.hurtbox.radius[player], 20);
      expect(scene.player.hurtbox.isTrigger[player], false);
      expect(scene.player.pickupRange.radius[player], 48);
      expect(scene.player.pickupRange.isTrigger[player], true);
      expect(
        scene.player.box.enable[player],
        true,
        reason: 'enable defaults to true (1)',
      );
    });

    test('each declared body has independent, non-aliasing storage', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      scene.pool.beginTick();
      scene.player.box.enable[player] = false;
      scene.pool.commitTick();

      // Disabling box must not disturb hurtbox/pickupRange's own enable bit.
      expect(scene.player.box.enable[player], false);
      expect(scene.player.hurtbox.enable[player], true);
      expect(scene.player.pickupRange.enable[player], true);
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
      expect(
        () => scene.polygon.triangle.pointsX.get(triangle, 8),
        throwsRangeError,
      );
    });

    test(
      'declared points land on every entity, and a per-entity write wins',
      () {
        final scene = _scene();
        scene.pool.beginTick();
        final first = scene.addEntity(scene.polygon);
        final second = scene.addEntity(scene.polygon);
        scene.pool.commitTick();

        final triangle = scene.polygon.triangle;
        for (final entity in [first, second]) {
          expect(triangle.pointCount[entity], 3);
          expect(triangle.pointsX.get(entity, 2), 5);
          expect(triangle.pointsY.get(entity, 2), 10);
        }

        scene.pool.beginTick();
        triangle.pointsX.set(second, 2, -5);
        triangle.pointsY.set(second, 2, 20);
        scene.pool.commitTick();

        expect(triangle.pointsX.get(second, 2), -5);
        expect(triangle.pointsY.get(second, 2), 20);
        expect(
          triangle.pointsX.get(first, 2),
          5,
          reason:
              'the declared outline is stamped into each row, not shared '
              'between them',
        );
      },
    );

    test('a capacity past the eight vertices Box2D allows is accepted', () {
      // Containment here is even-odd crossing, which handles any outline, so
      // a picking polygon is not bound by what a solver can simulate. The
      // Box2D bridge refuses a shape it cannot take; this layer does not.
      late final PolygonBody body;
      _adHocScene((descriptor) {
        body = descriptor.hasPolygonCollider(
          points: const [(0, 0), (10, 0), (5, 10)],
          maxPoints: 12,
        );
      });
      expect(body.pointsX.length, 12);
    });

    test(
      'an outline of fewer than three points is rejected at declare time',
      () {
        expect(
          () => _adHocScene(
            (descriptor) =>
                descriptor.hasPolygonCollider(points: const [(0, 0), (10, 0)]),
          ),
          throwsArgumentError,
        );
      },
    );

    test('an entity can use fewer points than the declared capacity', () {
      final scene = _scene();
      scene.pool.beginTick();
      final triangle = scene.addEntity(scene.polygon);
      scene.pool.commitTick();
      // Eight slots were reserved and the declared outline fills three -
      // pointCount is what a consumer should trust, not the array's own
      // fixed capacity.
      expect(
        scene.polygon.triangle.pointCount[triangle],
        lessThan(scene.polygon.triangle.pointsX.length),
      );
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
      expect(
        scene.player.firedEvents,
        isEmpty,
        reason: 'none of the no-op ones should record anything',
      );

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
      // the no-allocation rule forbids.
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
      expect(
        circle.containsLocalPoint(player, 20, 0),
        isTrue,
        reason:
            'exactly on the edge counts as inside - a boundary has to '
            'belong to one side, and picking the shape means the pixel you '
            'can see is clickable',
      );
      expect(circle.containsLocalPoint(player, 20.001, 0), isFalse);
      expect(
        circle.containsLocalPoint(player, 14.1, 14.1),
        isTrue,
        reason: 'inside the circle: 14.1^2 * 2 = 397.6, just under 20^2',
      );
      expect(circle.containsLocalPoint(player, 14.1, -14.1), isTrue);
      expect(
        circle.containsLocalPoint(player, 14.2, 14.2),
        isFalse,
        reason:
            'and just outside it: 14.2^2 * 2 = 403.3, over 20^2 - the '
            'edge is where the radius says it is, not a tolerance',
      );
      expect(
        circle.containsLocalPoint(player, 15, 15),
        isFalse,
        reason:
            'the corner of the bounding box is outside the circle - '
            'this is the whole difference between hit-testing a shape and '
            'hit-testing a rectangle',
      );
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

      expect(
        scene.player.hurtbox.containsLocalPoint(player, 0, 0),
        isFalse,
        reason: 'the body moved out from under the origin',
      );
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
      expect(
        pill.containsLocalPoint(entity, 10, 0),
        isTrue,
        reason: 'the straight section is the full radius wide',
      );
      expect(
        pill.containsLocalPoint(entity, 10, 20),
        isTrue,
        reason: 'and stays that wide right up to the cap centre',
      );
      expect(
        pill.containsLocalPoint(entity, 0, 30),
        isTrue,
        reason:
            'the very top of the cap - halfHeight is the *total* half '
            'height, caps included, like Unity\'s own capsule size',
      );
      expect(pill.containsLocalPoint(entity, 0, 30.1), isFalse);
      expect(
        pill.containsLocalPoint(entity, 10, 30),
        isFalse,
        reason:
            'the corner of the bounding box is rounded away - that is '
            'the only thing that makes this a capsule and not a box',
      );
      expect(
        pill.containsLocalPoint(entity, 7, 27),
        isTrue,
        reason: 'inside the top cap: 7^2 + 7^2 is under 10^2',
      );
    });

    test('a capsule shorter than its radius is a circle', () {
      final scene = _scene();
      scene.pool.beginTick();
      final entity = scene.addEntity(scene.capsule);
      scene.pool.commitTick();

      // radius 10, half-height 4: the straight section would be -6 long.
      final squashed = scene.capsule.squashed;
      expect(
        squashed.containsLocalPoint(entity, 0, 9),
        isTrue,
        reason:
            'the degenerate case has an obvious right answer - a '
            'segment of negative length is a point, so this is a circle of '
            'the declared radius rather than an error or an empty shape',
      );
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
      expect(
        triangle.containsLocalPoint(entity, 1, 8),
        isFalse,
        reason: 'inside the bounding box, outside the sloped edge',
      );
      expect(triangle.containsLocalPoint(entity, 9, 8), isFalse);
      expect(triangle.containsLocalPoint(entity, 5, 11), isFalse);
    });

    test('a concave polygon keeps its notch', () {
      final scene = _scene();
      scene.pool.beginTick();
      final entity = scene.addEntity(scene.concave);
      scene.pool.commitTick();

      final arrow = scene.concave.arrow;
      expect(
        arrow.containsLocalPoint(entity, 0, 10),
        isTrue,
        reason: 'up the middle of the arrowhead, above the notch',
      );
      expect(
        arrow.containsLocalPoint(entity, 12, 30),
        isTrue,
        reason: 'inside the right barb',
      );
      expect(
        arrow.containsLocalPoint(entity, 0, 30),
        isFalse,
        reason:
            'inside the bounding box and inside the convex hull, but '
            'in the notch - a convex-only test would report a hit here',
      );
    });

    test('a polygon with fewer than three points contains nothing', () {
      final scene = _scene();
      scene.pool.beginTick();
      final entity = scene.addEntity(scene.polygon);
      scene.pool.commitTick();

      scene.pool.beginTick();
      scene.polygon.triangle.pointCount[entity] = 2;
      scene.pool.commitTick();

      expect(
        scene.polygon.triangle.containsLocalPoint(entity, 5, 5),
        isFalse,
        reason:
            'two points enclose no area - an entity that shrank its '
            'outline, like a prefab that declared none at all, should pick '
            'up nothing rather than everything',
      );
    });

    test('a disabled body still answers the geometry question', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      scene.pool.beginTick();
      scene.player.hurtbox.enable[player] = false;
      scene.pool.commitTick();

      expect(
        scene.player.hurtbox.containsLocalPoint(player, 0, 0),
        isTrue,
        reason:
            'containsLocalPoint is about the shape, not about policy - '
            'whether a disabled body should be skipped belongs to the '
            'caller, and a debug overlay drawing every declared shape '
            'wants the honest answer',
      );
    });
  });

  group('boundCovers', () {
    // Only one thing about a bound can hurt anybody, and it is not
    // tightness. A bound that drops a point `containsLocalPoint` would have
    // accepted stops picking something the player clicked on, and that reads
    // as "the click did nothing" rather than as a failure - #23 recorded a
    // bound shrunk to a quarter failing ten correctness cases while a
    // count-only assertion still passed.
    //
    // So these sweep points and check the implication *inside ==> covered*,
    // rather than asking the implementation what radius it chose and
    // agreeing with it. The last case is what keeps the sweep honest: a
    // `boundCovers` that returned `true` unconditionally would satisfy every
    // implication above and fail that one.
    void expectCoversEverythingItContains(
      ColliderBody body,
      Entity entity, {
      double extent = 200,
    }) {
      final step = extent / 60;
      var checked = 0;
      for (var x = -extent; x <= extent; x += step) {
        for (var y = -extent; y <= extent; y += step) {
          if (!body.containsLocalPoint(entity, x, y)) continue;
          checked++;
          expect(
            body.boundCovers(entity, x * x + y * y),
            isTrue,
            reason:
                '($x, $y) is inside the shape and outside its own bound, '
                'so a caller rejecting on the bound would never hit-test it',
          );
        }
      }
      expect(
        checked,
        greaterThan(0),
        reason:
            'the sweep found no point inside the shape at all, so it '
            'proved nothing - a bench, and a test, must be able to fail',
      );
    }

    test('a circle, centred and offset', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      expectCoversEverythingItContains(scene.player.hurtbox, player);

      scene.pool.beginTick();
      scene.player.hurtbox
        ..offsetX[player] = 90
        ..offsetY[player] = -40;
      scene.pool.commitTick();
      expectCoversEverythingItContains(scene.player.hurtbox, player);
    });

    test('a box, including its corners and an offset', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      expectCoversEverythingItContains(scene.player.box, player);

      scene.pool.beginTick();
      scene.player.box
        ..offsetX[player] = -70
        ..offsetY[player] = 110;
      scene.pool.commitTick();
      expectCoversEverythingItContains(scene.player.box, player);
    });

    test('a capsule, tall and squashed', () {
      final scene = _scene();
      scene.pool.beginTick();
      final entity = scene.addEntity(scene.capsule);
      scene.pool.commitTick();

      // The tall one reaches `halfHeight` and the squashed one is a circle
      // of `radius` - two different expressions for where the caps sit, and
      // the bound has to follow the same one the shape test does.
      expectCoversEverythingItContains(scene.capsule.pill, entity);
      expectCoversEverythingItContains(scene.capsule.squashed, entity);

      scene.pool.beginTick();
      scene.capsule.pill.offsetY[entity] = 120;
      scene.pool.commitTick();
      expectCoversEverythingItContains(scene.capsule.pill, entity);
    });

    test('a polygon, convex and concave', () {
      final scene = _scene();
      scene.pool.beginTick();
      final triangle = scene.addEntity(scene.polygon);
      final arrow = scene.addEntity(scene.concave);
      scene.pool.commitTick();

      expectCoversEverythingItContains(scene.polygon.triangle, triangle);
      expectCoversEverythingItContains(scene.concave.arrow, arrow);
    });

    test('a body grown past its declared default is still covered', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      // The declared radius is 20. Nothing anywhere caches that, and this is
      // why: a bare column write is all it takes to make a bound taken from
      // the declaration wrong, with no error and no dropped frame - only a
      // click that stops working.
      scene.pool.beginTick();
      scene.player.hurtbox.radius[player] = 150;
      scene.pool.commitTick();
      expectCoversEverythingItContains(scene.player.hurtbox, player);
    });

    test('an empty polygon covers nothing', () {
      final scene = _scene();
      scene.pool.beginTick();
      final triangle = scene.addEntity(scene.polygon);
      scene.pool.commitTick();

      scene.pool.beginTick();
      scene.polygon.triangle.pointCount[triangle] = 0;
      scene.pool.commitTick();

      expect(scene.polygon.triangle.boundCovers(triangle, 0), isFalse);
    });

    test('the bound is a bound, not a yes', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      final entity = scene.addEntity(scene.capsule);
      final triangle = scene.addEntity(scene.polygon);
      scene.pool.commitTick();

      // Far outside every one of these, so anything that answered `true`
      // unconditionally - which would pass every implication above - fails
      // here.
      const farAway = 1e6;
      expect(scene.player.hurtbox.boundCovers(player, farAway), isFalse);
      expect(scene.player.box.boundCovers(player, farAway), isFalse);
      expect(scene.capsule.pill.boundCovers(entity, farAway), isFalse);
      expect(scene.polygon.triangle.boundCovers(triangle, farAway), isFalse);
    });

    test('a NaN field keeps the body rather than dropping it', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.player);
      scene.pool.commitTick();

      scene.pool.beginTick();
      scene.player.hurtbox.radius[player] = double.nan;
      scene.pool.commitTick();

      expect(
        scene.player.hurtbox.boundCovers(player, 1e12),
        isTrue,
        reason:
            'a transform or a body that has gone wrong should be visibly '
            'wrong, not invisible - the same direction CameraProjection.'
            'showsCircle rounds a NaN',
      );
    });
  });
}
