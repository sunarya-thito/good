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

late Game run;
late Box2DPhysicsSystem physics;

/// Every dispatch, in order, as "phase:entity".
final List<String> log = <String>[];

/// Whether the reused event instance was ever a different object. Pins the
/// no-allocation-per-contact contract from the outside.
Collision2DEvent? seenInstance;
bool sawSecondInstance = false;

void record(String phase, Collision2DEvent event) {
  log.add(phase);
  if (seenInstance == null) {
    seenInstance = event;
  } else if (!identical(seenInstance, event)) {
    sawSecondInstance = true;
  }
}

/// A falling crate that reports what it touches.
class _Crate extends EntityStruct
    with Transform2D, Collider2D, RigidBody2D, CollisionListener {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor d) {
    super.describeCollider(d);
    box = d.hasBoxCollider(halfWidth: 0.5, halfHeight: 0.5);
  }

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

/// A static floor that says nothing - so a test can tell which side heard.
class _Floor extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor d) {
    super.describeCollider(d);
    box = d.hasBoxCollider(halfWidth: 50, halfHeight: 1);
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    bodyType.defaultValue = BodyType2D.staticBody;
  }
}

/// A static trigger volume.
class _Zone extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor d) {
    super.describeCollider(d);
    box = d.hasBoxCollider(halfWidth: 5, halfHeight: 0.5, isTrigger: true);
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    bodyType.defaultValue = BodyType2D.staticBody;
  }
}

class _Scene extends SceneStruct {
  late Scene handle;
  late final _Crate crate;
  late final _Floor floor;
  late final _Zone zone;

  @override
  void onSceneMounted(Scene scene) => handle = scene;

  Entity addEntity<T extends EntityStruct>(T prefab) =>
      handle.addEntity(prefab);

  @override
  void describeScene(SceneDescriptor d) {
    super.describeScene(d);
    crate = d.has(_Crate.new);
    floor = d.has(_Floor.new);
    zone = d.has(_Zone.new);
  }
}

class _GameState extends GameState<_Game> {
  @override
  void onMounted() => loadScene(_Scene());

  @override
  void describeSystems(SystemDescriptor d) {
    super.describeSystems(d);
    physics = d.has(Box2DPhysicsSystem.new);
  }
}

class _Game extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(microseconds: 16667);

  @override
  GameState createState() => _GameState();
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

void _advance(int steps) {
  for (var i = 0; i < steps; i++) {
    run.state.advance(_step);
  }
}

void main() {
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

  test('landing on a floor fires collision enter exactly once', () async {
    final scene = await _boot();

    final floor = scene.addEntity(scene.floor);
    scene.floor.transformOffsetY[floor] = -10;
    scene.addEntity(scene.crate);

    _advance(180);

    expect(
      log.where((e) => e == 'enter').length,
      1,
      reason: 'a crate that lands and stays landed touches once',
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
    final afterLanding = log.where((e) => e == 'stay').length;
    expect(afterLanding, greaterThan(0), reason: 'it should be resting by now');

    _advance(30);
    expect(
      log.where((e) => e == 'stay').length,
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
      log,
      contains('triggerEnter'),
      reason: 'entering a sensor should fire onTriggerEnter2D',
    );
    expect(
      log.where((e) => e.startsWith('enter') || e == 'stay'),
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

    expect(log, contains('triggerEnter'));
    expect(
      log,
      contains('triggerExit'),
      reason: 'having fallen past the zone, the crate has left it',
    );
    expect(
      log.indexOf('triggerEnter'),
      lessThan(log.lastIndexOf('triggerExit')),
      reason: 'enter must precede exit',
    );
  });

  test(
    'the event names the listener as source and the other as target',
    () async {
      final scene = await _boot();

      final floor = scene.addEntity(scene.floor);
      scene.floor.transformOffsetY[floor] = -10;
      final crate = scene.addEntity(scene.crate);

      Entity? reportedSource;
      Entity? reportedTarget;
      // Capture on the first enter by reading the shared instance during it.
      var captured = false;
      for (var i = 0; i < 180 && !captured; i++) {
        run.state.advance(_step);
        if (log.contains('enter') && seenInstance != null) {
          reportedSource = seenInstance!.sourceEntity;
          reportedTarget = seenInstance!.targetEntity;
          captured = true;
        }
      }

      expect(captured, isTrue);
      expect(
        reportedSource,
        crate,
        reason: 'the crate is the listener, so it must read itself as source',
      );
      expect(reportedTarget, floor);
    },
  );

  test('a collider with no listener is simply skipped', () async {
    // The floor mixes in no CollisionListener. Dispatching to it must be a
    // no-op rather than an error, and must not stop the crate hearing.
    final scene = await _boot();

    final floor = scene.addEntity(scene.floor);
    scene.floor.transformOffsetY[floor] = -10;
    scene.addEntity(scene.crate);

    _advance(180);

    expect(log, contains('enter'), reason: 'the crate still heard');
  });
}
