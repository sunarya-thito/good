// Landing 4: contact and sensor events reaching CollisionListener.
//
// Requires the native library. packages/goo2d_ffi_box2d/README.md has the
// build for each platform.
//
// **Positive y is UP** - so a floor sits at a SMALLER y than the bodies
// falling onto it, and free fall decreases y. Box2D uses the same convention,
// and `Box2DPhysicsSystem.gravityY` defaults to -10.

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

part 'contact_test.g.dart';

late Game run;
Box2DPhysicsSystem get physics => run.state.getSystem<Box2DPhysicsSystem>();

/// One dispatch: which method it arrived through, and the two sides it named.
typedef Delivery = ({String phase, Entity source, Entity target});

/// Every dispatch, in order.
final List<Delivery> log = <Delivery>[];

Iterable<Delivery> phase(String phase) => log.where((d) => d.phase == phase);

/// Whether the reused event instance was ever a different object. Pins the
/// no-allocation-per-contact contract from the outside.
Collision2DEvent? seenInstance;
bool sawSecondInstance = false;

void record(String phase, Collision2DEvent event) {
  log.add((
    phase: phase,
    source: event.sourceEntity,
    target: event.targetEntity,
  ));
  if (seenInstance == null) {
    seenInstance = event;
  } else if (!identical(seenInstance, event)) {
    sawSecondInstance = true;
  }
}

/// Hears every contact in the world and writes down what it was told.
///
/// A system and not a prefab: `CollisionListener` is `on GameListener` now, and
/// the six dispatchers live on the physics system.
class _Watcher extends GameSystem with CollisionListener {
  @override
  void onCollisionEnter2D(Collision2DEvent event) => record('enter', event);

  @override
  void onCollisionExit2D(Collision2DEvent event) => record('exit', event);

  @override
  void onCollisionStay2D(Collision2DEvent event) => record('stay', event);

  @override
  void onTriggerEnter2D(Collision2DEvent event) =>
      record('triggerEnter', event);

  @override
  void onTriggerExit2D(Collision2DEvent event) => record('triggerExit', event);

  @override
  void onTriggerStay2D(Collision2DEvent event) => record('triggerStay', event);
}

/// A falling crate.
class _Crate extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  final box = ColliderBody.box(halfWidth: 0.5, halfHeight: 0.5);
}

/// A static floor.
class _Floor extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  final box = ColliderBody.box(halfWidth: 50, halfHeight: 1);

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    bodyType.initialValue = BodyType2D.staticBody;
  }
}

/// A static trigger volume.
class _Zone extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  final box = ColliderBody.box(halfWidth: 5, halfHeight: 0.5, isTrigger: true);

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    bodyType.initialValue = BodyType2D.staticBody;
  }
}

class _Scene extends SceneStruct {
  late Scene handle;
  @prefab
  final crate = _Crate();
  @prefab
  final floor = _Floor();
  @prefab
  final zone = _Zone();

  @override
  void onSceneMounted(Scene scene) => handle = scene;

  Entity addEntity<T extends EntityStruct>(T prefab) =>
      handle.addEntity(prefab);
}

class _GameState extends GameState<_Game> {
  @override
  void onMounted() => loadScene(_Scene());

  @system
  final physics = Box2DPhysicsSystem();

  @system
  final watcher = _Watcher();
}

class _Game extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(microseconds: 16667);

  @override
  GameState createState() => _GameState();
}

/// The same game with nothing listening, for the case where the dispatchers
/// are empty.
class _DeafState extends GameState<_DeafGame> {
  @override
  void onMounted() => loadScene(_Scene());

  @system
  final physics = Box2DPhysicsSystem();
}

class _DeafGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(microseconds: 16667);

  @override
  GameState createState() => _DeafState();
}

const Duration _step = Duration(microseconds: 16667);

Future<_Scene> _boot() async {
  run = await Game.startInline(_Game.new);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
    physics.dispose();
  });
  return run.state.singleScene<_Scene>();
}

Future<_Scene> _bootDeaf() async {
  run = await Game.startInline(_DeafGame.new);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
    physics.dispose();
  });
  return run.state.singleScene<_Scene>();
}

void _advance(int steps) {
  for (var i = 0; i < steps; i++) {
    run.state.advance(_step);
  }
}

void main() {
  _installDeclarations();

  setUp(() {
    log.clear();
    seenInstance = null;
    sawSecondInstance = false;
  });

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('landing on a floor fires collision enter once per side', () async {
    final scene = await _boot();

    final floor = scene.addEntity(scene.floor);
    scene.floor.transformOffsetY[floor] = -10;
    final crate = scene.addEntity(scene.crate);

    _advance(180);

    final enters = phase('enter').toList();
    expect(
      enters.length,
      2,
      reason: 'one contact, delivered from each side',
    );
    expect(
      enters.map((d) => (d.source, d.target)),
      containsAll(<(Entity, Entity)>[(crate, floor), (floor, crate)]),
      reason:
          'each delivery names its own side as source, so a listener that '
          'filters on sourceEntity alone can see either entity',
    );
  });

  test('resting on a floor fires collision stay every tick', () async {
    // Box2D reports only transitions, so stay is derived from the pairs the
    // system tracks. If that tracking is broken, enter fires and stay never
    // does - which is why this asserts a growing count, not merely non-zero.
    final scene = await _boot();

    final floor = scene.addEntity(scene.floor);
    scene.floor.transformOffsetY[floor] = -10;
    scene.addEntity(scene.crate);

    _advance(180);
    final afterLanding = phase('stay').length;
    expect(afterLanding, greaterThan(0), reason: 'it should be resting by now');

    _advance(30);
    expect(
      phase('stay').length,
      greaterThan(afterLanding),
      reason: 'stay must keep firing while the pair is still touching',
    );
  });

  test('the reused event instance is genuinely reused', () async {
    final scene = await _boot();

    final floor = scene.addEntity(scene.floor);
    scene.floor.transformOffsetY[floor] = -10;
    scene.addEntity(scene.crate);

    _advance(180);

    expect(log, isNotEmpty, reason: 'nothing was dispatched to check');
    expect(
      sawSecondInstance,
      isFalse,
      reason:
          'every dispatch must repoint one instance - a second object '
          'means an allocation per contact, which the no-allocation rule forbids',
    );
  });

  test('a sensor fires trigger events and no collision events', () async {
    final scene = await _boot();

    final zone = scene.addEntity(scene.zone);
    scene.zone.transformOffsetY[zone] = -5;
    scene.addEntity(scene.crate);

    // Fall through the zone entirely.
    _advance(120);

    expect(
      phase('triggerEnter'),
      isNotEmpty,
      reason: 'entering a sensor should fire onTriggerEnter2D',
    );
    expect(
      log.where((d) => d.phase == 'enter' || d.phase == 'stay'),
      isEmpty,
      reason: 'a sensor must produce no collision events at all',
    );
  });

  test('a sensor produces no physical response', () async {
    final scene = await _boot();

    final zone = scene.addEntity(scene.zone);
    scene.zone.transformOffsetY[zone] = -5;
    final crate = scene.addEntity(scene.crate);

    _advance(120);

    expect(
      scene.crate.transformOffsetY[crate],
      lessThan(-10),
      reason:
          'the crate should have fallen straight through the trigger, '
          'not rested on it - and falling means a *smaller* y, since world '
          '+y is up',
    );
  });

  test('leaving a sensor fires trigger exit', () async {
    final scene = await _boot();

    final zone = scene.addEntity(scene.zone);
    scene.zone.transformOffsetY[zone] = -5;
    scene.addEntity(scene.crate);

    _advance(200);

    expect(phase('triggerEnter'), isNotEmpty);
    expect(
      phase('triggerExit'),
      isNotEmpty,
      reason: 'having fallen past the zone, the crate has left it',
    );
    expect(
      log.indexWhere((d) => d.phase == 'triggerEnter'),
      lessThan(log.lastIndexWhere((d) => d.phase == 'triggerExit')),
      reason: 'enter must precede exit',
    );
  });

  test(
    'a trigger is reported from both sides, sensor included',
    () async {
      final scene = await _boot();

      final zone = scene.addEntity(scene.zone);
      scene.zone.transformOffsetY[zone] = -5;
      final crate = scene.addEntity(scene.crate);

      _advance(200);

      final enters = phase('triggerEnter').toList();
      expect(
        enters.map((d) => d.source),
        containsAll(<Entity>[crate, zone]),
        reason:
            'Box2D names the sensor first in its own report; a listener '
            'watching for the visitor must still hear the visitor as source',
      );
    },
  );

  test('every dispatch names one side as source and the other as target', () async {
    final scene = await _boot();

    final floor = scene.addEntity(scene.floor);
    scene.floor.transformOffsetY[floor] = -10;
    final crate = scene.addEntity(scene.crate);

    _advance(180);

    expect(log, isNotEmpty);
    for (final delivery in log) {
      expect(
        {delivery.source, delivery.target},
        {crate, floor},
        reason: 'the two sides of the only contact in this scene',
      );
      expect(delivery.source, isNot(delivery.target));
    }
  });

  test('an entity whose prefab does nothing still reaches the listener', () async {
    // Nothing about the floor says it wants to hear anything, and under the
    // old shape it was skipped because it mixed in no CollisionListener. The
    // dispatcher does not ask the entity, so both sides now arrive and the
    // filtering is the listener's.
    final scene = await _boot();

    final floor = scene.addEntity(scene.floor);
    scene.floor.transformOffsetY[floor] = -10;
    scene.addEntity(scene.crate);

    _advance(180);

    expect(
      phase('enter').map((d) => d.source),
      contains(floor),
      reason: 'the floor is named as source by its own half of the contact',
    );
  });

  test('with nothing listening, no contact is dispatched and the touching set is still tracked', () async {
    final scene = await _bootDeaf();

    final floor = scene.addEntity(scene.floor);
    scene.floor.transformOffsetY[floor] = -10;
    scene.addEntity(scene.crate);

    _advance(180);

    expect(
      physics.collisionEnter2DEvent.listenerCount,
      0,
      reason: 'this game declares no CollisionListener',
    );
    expect(log, isEmpty);
    expect(
      physics.touchingPairCount,
      greaterThan(0),
      reason:
          'the pairs are remembered whether or not anybody is listening - a '
          'system disabled during the landing and enabled afterwards has to '
          'find the stay phase already correct',
    );
  });
}
