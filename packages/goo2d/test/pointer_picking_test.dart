import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// PointerPickingSystem end to end: a synthetic pointer written through the
// same InputDevice a GameView writes through, a real scene of colliders, and
// the events a PointerReceiver prefab actually receives. Everything runs on one
// copy (start(inline: true, autoTick: false)) and is stepped by hand, so
// there are no timers and every tick boundary in these tests is explicit -
// which matters here, because half of what is being checked is *when* an
// event fires rather than whether.

/// What every receiver in this file appends to.
final List<String> events = <String>[];

/// A round button. One circle collider, one sprite, so it participates in
/// the z-order tie-break.
class _Button extends EntityStruct
    with
        Transform2D,
        WorldTransform2D,
        Renderable2D,
        Collider2D,
        PointerReceiver,
        HoverReceiver {
  final sprite = Sprite.of(width: 40, height: 40);
  final hitArea = CircleBody.of(radius: 20);

  @override
  void onHoverEnter(PointerPickEvent event) =>
      events.add('enter ${event.entity.value}');
  @override
  void onHoverExit(PointerPickEvent event) =>
      events.add('exit ${event.entity.value}');
  @override
  void onHover(PointerPickEvent event) =>
      events.add('hover ${event.entity.value}');
  @override
  void onPointerDown(PointerPickEvent event) =>
      events.add('pressed ${event.entity.value}');
  @override
  void onPointerUp(PointerPickEvent event) =>
      events.add('released ${event.entity.value}');
}

/// A panel drawn above the buttons - same shape family, higher z, and it
/// records the world position it was clicked at.
class _Panel extends EntityStruct
    with
        Transform2D,
        WorldTransform2D,
        Renderable2D,
        Collider2D,
        PointerReceiver,
        HoverReceiver {
  final sprite = Sprite.of(width: 200, height: 100, zIndex: 10);
  final hitArea = BoxBody.of(halfWidth: 100, halfHeight: 50);

  double lastWorldX = double.nan;
  double lastWorldY = double.nan;

  @override
  void onHoverEnter(PointerPickEvent event) {
    events.add('panel enter');
    lastWorldX = event.worldSpace.x;
    lastWorldY = event.worldSpace.y;
  }

  @override
  void onHoverExit(PointerPickEvent event) => events.add('panel exit');
}

/// A receiver with no `Renderable2D` at all - an invisible click zone.
class _Zone extends EntityStruct
    with
        Transform2D,
        WorldTransform2D,
        Collider2D,
        PointerReceiver,
        HoverReceiver {
  final hitArea = BoxBody.of(halfWidth: 50, halfHeight: 50);

  @override
  void onHoverEnter(PointerPickEvent event) => events.add('zone enter');
  @override
  void onHoverExit(PointerPickEvent event) => events.add('zone exit');
}

/// A receiver that declares no collider - the "silently never picked" case.
class _Naked extends EntityStruct
    with Transform2D, WorldTransform2D, PointerReceiver, HoverReceiver {
  @override
  void onHoverEnter(PointerPickEvent event) => events.add('naked enter');
}

/// A small box held 100 units out from the entity's own origin. The shape
/// most of the coarse reject's failure modes show up on: the cursor is
/// nowhere near the origin when it is on the box, and rotating the entity
/// swings the box a long way without changing its distance from the origin.
class _Satellite extends EntityStruct
    with
        Transform2D,
        WorldTransform2D,
        Collider2D,
        PointerReceiver,
        HoverReceiver {
  final hitArea = BoxBody.of(
    halfWidth: 10,
    halfHeight: 10,
    offsetX: 100,
  );
}

/// Two circles, far apart, on one entity - so a bound taken from the first
/// body it happens to walk, or from one bound shared by the whole entity,
/// answers differently from a bound per body.
class _Compound extends EntityStruct
    with
        Transform2D,
        WorldTransform2D,
        Collider2D,
        PointerReceiver,
        HoverReceiver {
  final near = CircleBody.of(radius: 5);
  final far = CircleBody.of(radius: 5, offsetY: 150);
}

/// Pressable and nothing else - no `HoverReceiver` at all. The prefab a
/// touch-driven game writes, and the one that shows a press arriving with the
/// cursor parked somewhere else entirely.
class _Pad extends EntityStruct
    with Transform2D, WorldTransform2D, Collider2D, PointerReceiver {
  final hitArea = BoxBody.of(halfWidth: 20, halfHeight: 20);

  /// What the last event said, recorded field by field: the borrowed event is
  /// re-pointed before the next callback, so nothing here keeps it.
  int lastPointerId = -1;
  ContactKind? lastKind;
  bool lastCancelled = false;
  double lastWorldX = double.nan;
  double lastWorldY = double.nan;
  double lastViewX = double.nan;

  void _record(PointerPickEvent event) {
    lastPointerId = event.pointerId;
    lastKind = event.kind;
    lastCancelled = event.cancelled;
    lastWorldX = event.worldSpace.x;
    lastWorldY = event.worldSpace.y;
    lastViewX = event.viewSpace.x;
  }

  @override
  void onPointerDown(PointerPickEvent event) {
    _record(event);
    events.add('pad down ${event.entity.value}');
  }

  @override
  void onPointerUp(PointerPickEvent event) {
    _record(event);
    events.add('pad up ${event.entity.value}');
  }
}

/// Hoverable and nothing else, drawn above everything. A press aimed at what
/// is underneath has to go through it, because it declares no interest in
/// presses at all.
class _Glass extends EntityStruct
    with
        Transform2D,
        WorldTransform2D,
        Renderable2D,
        Collider2D,
        HoverReceiver {
  final sprite = Sprite.of(width: 60, height: 60, zIndex: 50);
  final hitArea = BoxBody.of(halfWidth: 30, halfHeight: 30);

  @override
  void onHoverEnter(PointerPickEvent event) => events.add('glass enter');

  @override
  void onHoverExit(PointerPickEvent event) => events.add('glass exit');
}

class _Eye extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

class _Scene extends SceneStruct {
  @override
  void onSceneMounted(Scene scene) => handle = scene;

  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Scene();

  late final _Button button;
  late final _Panel panel;
  late final _Zone zone;
  late final _Naked naked;
  late final _Eye eye;
  late final _Satellite satellite;
  late final _Compound compound;
  late final _Pad pad;
  late final _Glass glass;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    button = descriptor.has(_Button.new);
    panel = descriptor.has(_Panel.new);
    zone = descriptor.has(_Zone.new);
    naked = descriptor.has(_Naked.new);
    eye = descriptor.has(_Eye.new);
    // Declared last, so the archetype registration order the z tie-break
    // cases above lean on is the order they were written for.
    satellite = descriptor.has(_Satellite.new);
    compound = descriptor.has(_Compound.new);
    pad = descriptor.has(_Pad.new);
    glass = descriptor.has(_Glass.new);
  }
}

class _GameState extends GameState<_Game> {
  @override
  void onMounted() {
    loadScene(_Scene());
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(PointerPickingSystem.new);
    // Declared *after* the picker, so the ordering that makes picking read
    // resolved transforms has to come from compareTo rather than from the
    // order these two are written in.
    descriptor.has(WorldTransformSystem.new);
  }
}

class _Game extends Game {
  /// Picking projects through a declared view, so this fixture declares one.
  final view = CameraView.of();

  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _GameState();
}

Future<_Game> _boot() async {
  final game = await Game.startInline(_Game.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

/// Puts the cursor at a view-space point and runs one fixed step, which is
/// one input resolution and one pass of the picker.
void _moveTo(_Game game, double x, double y) {
  game.inputDevice!.movePointer(screenX: x, screenY: y);
  run.state.runFixedStep();
}

/// A tick with no pointer movement - the picker still runs.
void _step(_Game game) => run.state.runFixedStep();

/// Runs the first tick - the one that resolves the world transforms of
/// whatever the test just spawned - with the cursor parked far away from
/// anything, then clears the events it produced.
///
/// Worth a helper rather than a bare `runFixedStep`: a device nobody has
/// written to reports the pointer at (0, 0), which is exactly where a test
/// puts an entity when it does not care where it is. Without this, every
/// test would start out already hovering something.
void _settle(_Game game) {
  game.inputDevice!.movePointer(screenX: 5000, screenY: 5000);
  run.state.runFixedStep();
  events.clear();
}

/// Adds the camera entity **and points it at the game's view** - a camera not
/// occupying a view is not the view's camera, which is the whole of how a
/// view decides what it looks at now.
Entity _eye(_Game game, _Scene scene) {
  final eye = scene.addEntity(scene.eye);
  // No tick management at all: this runs immediately after the row is
  // created, so its page has never published and the write is allowed - the
  // same path every other field default here takes. Opening a tick would
  // publish the page and make the caller's *next* write assert.
  scene.eye.cameraView[eye] = game.view;
  return eye;
}

void main() {
  setUp(events.clear);

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('hit testing', () {
    test(
      'the cursor picks the shape, not the sprite\'s bounding box',
      () async {
        final game = await _boot();
        final scene = run.state.singleScene<_Scene>();
        final button = scene.addEntity(scene.button);
        _settle(game);

        // The button is a radius-20 circle at the origin under a 40x40 sprite.
        _moveTo(game, 0, 0);
        expect(run.state.getSystem<PointerPickingSystem>().hovered, button);

        _moveTo(game, 19, 0);
        expect(run.state.getSystem<PointerPickingSystem>().hovered, button);

        _moveTo(game, 15, 15);
        expect(
          run.state.getSystem<PointerPickingSystem>().hovered,
          isNull,
          reason:
              'the corner of the sprite is outside the circle - the '
              'whole reason picking goes through Collider2D instead of '
              'Renderable2D\'s bounds',
        );
      },
    );

    test('a receiver with no collider is never picked', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      scene.addEntity(scene.naked);
      _settle(game);

      _moveTo(game, 0, 0);
      expect(run.state.getSystem<PointerPickingSystem>().hovered, isNull);
      expect(
        events,
        isEmpty,
        reason:
            'the query requires Collider2D, so a receiver with nothing '
            'to hit-test simply is not a candidate',
      );
    });

    test('the entity\'s world transform moves its shape', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final button = scene.addEntity(scene.button);
      scene.pool.beginTick();
      scene.button.transformOffsetX[button] = 300;
      scene.pool.commitTick();
      _settle(game);

      _moveTo(game, 0, 0);
      expect(run.state.getSystem<PointerPickingSystem>().hovered, isNull);
      _moveTo(game, 300, 0);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        button,
        reason:
            'the collider is declared in local space and placed by the '
            'entity\'s own WorldTransform2D, which is what makes a moving '
            'target clickable where it is drawn rather than where it '
            'started',
      );
    });

    test(
      'rotation and scale are undone, so a box hit-tests as it looks',
      () async {
        final game = await _boot();
        final scene = run.state.singleScene<_Scene>();
        final panel = scene.addEntity(scene.panel);
        scene.pool.beginTick();
        scene.panel
          ..transformRotation[panel] =
              math.pi /
              2 // a quarter turn
          ..transformScaleX[panel] = 2;
        scene.pool.commitTick();
        _settle(game);

        // The panel is 200x100 (half-extents 100x50) and its x axis is scaled
        // 2x, so unrotated it would cover +/-200 horizontally and +/-50
        // vertically. Turned a quarter turn, those swap.
        _moveTo(game, 0, 190);
        expect(
          run.state.getSystem<PointerPickingSystem>().hovered,
          panel,
          reason: 'the long axis now runs down the screen',
        );
        _moveTo(game, 190, 0);
        expect(
          run.state.getSystem<PointerPickingSystem>().hovered,
          isNull,
          reason:
              'and no longer runs across it - a picker that ignored '
              'rotation would report a hit here',
        );
        _moveTo(game, 0, 210);
        expect(run.state.getSystem<PointerPickingSystem>().hovered, isNull);
        _moveTo(game, 40, 0);
        expect(
          run.state.getSystem<PointerPickingSystem>().hovered,
          panel,
          reason:
              'the short axis is 50 local units, unaffected by the x '
              'scale',
        );
      },
    );

    test('picking turns the same way the renderer draws', () async {
      // The quarter-turn test above cannot catch a handedness error: a
      // rectangle turned 90 degrees is the same set of points whichever way it
      // went. This one uses an oblique angle, where the two answers are
      // different shapes and the mirrored point is outside.
      //
      // Picking and drawing have to agree or a click lands next to what you
      // can see, and they reach the same answer by different routes - the
      // renderer composes corners on the y-down canvas with a negated sine,
      // while this inverts the rotation in y-up world space and lets
      // `viewToWorldY` carry the flip. That they still meet is the property
      // under test.
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final panel = scene.addEntity(scene.panel);
      scene.pool.beginTick();
      scene.panel.transformRotation[panel] = 0.5;
      scene.pool.commitTick();
      _settle(game);

      // The panel is 200x100. Its long axis started along +x; a positive
      // rotation is counter-clockwise, so it now points up and to the right -
      // and up the screen is a *smaller* view y. Local (90, 0) is well inside
      // the panel and lands at world (79, 43), i.e. view (79, -43).
      _moveTo(game, 79, -43);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        panel,
        reason: 'the long axis leans up the screen, so this is on it',
      );

      // The mirror image of that point about the view's horizontal midline.
      // It is 76 local units off the panel's short axis, which is only 50
      // half-extents wide, so it misses - unless picking turned the panel the
      // other way, in which case it is the hit and the point above is not.
      _moveTo(game, 79, 43);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        isNull,
        reason:
            'and the mirrored point is off it entirely. A picker that '
            'rotated clockwise would swap these two results and pass every '
            'other test in this file',
      );
    });

    test('a disabled body stops picking without being removed', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final button = scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 0, 0);
      expect(run.state.getSystem<PointerPickingSystem>().hovered, button);

      scene.pool.beginTick();
      scene.button.hitArea.enable[button] = false;
      scene.pool.commitTick();
      _step(game);

      expect(run.state.getSystem<PointerPickingSystem>().hovered, isNull);
      expect(
        events.last,
        'exit ${button.value}',
        reason:
            'disabling what the cursor was over is a real exit - the '
            'entity stopped being under the cursor, however it happened',
      );
    });
  });

  // Picking rejects a candidate on a cheap bound before it inverts the
  // entity's transform, and the way that goes wrong is silent. A bound too
  // tight does not throw and does not look like anything: the entity is
  // simply never hit-tested, and the click reads as landing on nothing. So
  // every case here puts the cursor somewhere a hit is *expected* and
  // demands it, and pairs it with the nearby miss that a bound stretched to
  // infinity would get wrong.
  group('the reject before the hit test', () {
    test('just inside the shape hits, just outside misses', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final button = scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 19.9, 0);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        button,
        reason:
            'a hair inside a radius-20 circle. Shrink the bound the '
            'reject uses and this is what stops working - with no error, '
            'no dropped frame and nothing on screen to see',
      );
      _moveTo(game, 20.1, 0);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        isNull,
        reason:
            'and a hair outside it, so a bound widened to infinity does '
            'not pass this group by accident',
      );
    });

    test('a collider held out from the origin is picked where it is', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final satellite = scene.addEntity(scene.satellite);
      _settle(game);

      _moveTo(game, 100, 0);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        satellite,
        reason:
            'the body is a 20x20 box 100 units out. A bound measured '
            'from the body rather than from the entity origin would be '
            'right here and wrong the moment the entity turns',
      );
      _moveTo(game, 0, 0);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        isNull,
        reason: 'the origin itself is empty - the collider moved off it',
      );
      _moveTo(game, 111, 0);
      expect(run.state.getSystem<PointerPickingSystem>().hovered, isNull);
    });

    test('rotation swings that collider, and the bound follows', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final satellite = scene.addEntity(scene.satellite);
      scene.pool.beginTick();
      scene.satellite.transformRotation[satellite] = math.pi / 2;
      scene.pool.commitTick();
      _settle(game);

      // Screen y runs down and world y runs up, so world (0, 100) is
      // -100 here - the same inversion `CameraProjection.viewToWorldY` has.
      _moveTo(game, 0, -100);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        satellite,
        reason:
            'a quarter turn puts the box at world (0, 100). The bound is a '
            'circle about the origin precisely so that it does not have '
            'to know that - rotation does not change a distance from the '
            'point it turns about, so the same radius holds at every '
            'angle and the reject never reads the angle at all',
      );
      _moveTo(game, 100, 0);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        isNull,
        reason: 'and the box is no longer where it was',
      );
    });

    test('scale stretches how far the collider reaches', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final satellite = scene.addEntity(scene.satellite);
      scene.pool.beginTick();
      scene.satellite.transformScaleX[satellite] = 2;
      scene.pool.commitTick();
      _settle(game);

      _moveTo(game, 200, 0);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        satellite,
        reason:
            'the offset scales with everything else, so the box is now '
            '200 out - twice as far as the unscaled bound allows for',
      );
      _moveTo(game, 219, 0);
      expect(run.state.getSystem<PointerPickingSystem>().hovered, satellite);
      _moveTo(game, 221, 0);
      expect(run.state.getSystem<PointerPickingSystem>().hovered, isNull);
    });

    test('a non-uniform scale is bounded by its larger axis', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final button = scene.addEntity(scene.button);
      scene.pool.beginTick();
      scene.button.transformScaleY[button] = 4;
      scene.pool.commitTick();
      _settle(game);

      _moveTo(game, 0, 79);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        button,
        reason:
            'a radius-20 circle stretched 4x vertically reaches 80 up. '
            'The bound divides the world distance by the *larger* scale '
            'factor - taking the smaller one would put this at 79 local '
            'units against a radius of 20 and drop it',
      );
      _moveTo(game, 0, 81);
      expect(run.state.getSystem<PointerPickingSystem>().hovered, isNull);
      _moveTo(game, 21, 0);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        isNull,
        reason:
            'the bound over-covers on the short axis, and the exact '
            'test is what decides - the reject is allowed to be generous, '
            'never mean',
      );
    });

    test('each body on a compound collider gets its own bound', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final compound = scene.addEntity(scene.compound);
      _settle(game);

      _moveTo(game, 0, 0);
      expect(run.state.getSystem<PointerPickingSystem>().hovered, compound);
      // World (0, 150): screen y runs the other way.
      _moveTo(game, 0, -150);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        compound,
        reason:
            'the second body is 150 units up and radius 5. A bound '
            'taken from the first body it walks, or one bound shared by '
            'the whole entity and stopped at the first that fails, would '
            'never reach it',
      );
      _moveTo(game, 0, -75);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        isNull,
        reason: 'and the gap between the two is still a gap',
      );
    });

    test('a body grown after it was declared is still picked', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final button = scene.addEntity(scene.button);
      scene.pool.beginTick();
      scene.button.hitArea.radius[button] = 300;
      scene.pool.commitTick();
      _settle(game);

      _moveTo(game, 290, 0);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        button,
        reason:
            'the bound is read from the row every tick, not cached from '
            'the declaration. A per-archetype maximum would have been '
            'cheaper and would be wrong here, silently',
      );
    });
  });

  group('overlap order', () {
    test('the higher zIndex wins', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      // Both cover the origin; the panel's sprite is at zIndex 10.
      scene.addEntity(scene.button);
      final panel = scene.addEntity(scene.panel);
      _settle(game);

      _moveTo(game, 0, 0);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        panel,
        reason:
            'what is drawn on top is what gets clicked - one ordering, '
            'not two that can disagree',
      );
      expect(events, contains('panel enter'));
    });

    test('at equal z the later entity wins, matching the draw order', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final first = scene.addEntity(scene.button);
      final second = scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 0, 0);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        second,
        reason:
            'the renderer\'s z sort is stable over query order, so of '
            'two sprites at the same depth the later one is drawn second - '
            'i.e. on top. Picking the earlier one would mean clicking '
            'through the thing you can see (${first.value} is underneath)',
      );
    });

    test('an invisible click zone competes at zero', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final zone = scene.addEntity(scene.zone);
      _settle(game);

      _moveTo(game, 0, 0);
      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        zone,
        reason:
            'no Renderable2D at all is not a disqualification - an '
            'entity with only a collider is a click zone, and it sits at '
            'the depth an undeclared zIndex already means',
      );

      // Now put a drawn button over it, one layer up.
      final button = scene.addEntity(scene.button);
      scene.pool.beginTick();
      scene.button.sprite.zIndex[button] = 1;
      scene.pool.commitTick();
      _step(game);

      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        button,
        reason:
            'zero is a real depth, not an exemption: anything actually '
            'drawn above the zone takes the click, exactly as if the zone '
            'were a sprite at zIndex 0',
      );
    });

    test('an entity is measured by its topmost visible sprite', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final button = scene.addEntity(scene.button);
      final panel = scene.addEntity(scene.panel);
      scene.pool.beginTick();
      // Between the two, but still under the panel's 10.
      scene.button.sprite.zIndex[button] = 5;
      scene.pool.commitTick();
      _settle(game);

      _moveTo(game, 0, 0);
      expect(run.state.getSystem<PointerPickingSystem>().hovered, panel);

      // Hide the panel's only sprite: it now draws nothing, so it has no
      // visible depth to win with.
      scene.pool.beginTick();
      scene.panel.sprite.visible[panel] = false;
      scene.pool.commitTick();
      _step(game);

      expect(
        run.state.getSystem<PointerPickingSystem>().hovered,
        button,
        reason:
            'an invisible sprite is not drawn, so it cannot be what '
            'you are clicking on - depth comes from what is actually on '
            'screen. The panel is still a candidate at depth zero, it just '
            'no longer outranks the button\'s 5',
      );
    });
  });

  group('hover and click events', () {
    test(
      'enter fires once on the transition, hover every tick after',
      () async {
        final game = await _boot();
        final scene = run.state.singleScene<_Scene>();
        final button = scene.addEntity(scene.button);
        _settle(game);

        _moveTo(game, 0, 0);
        _step(game);
        _step(game);

        final id = button.value;
        expect(
          events,
          <String>['enter $id', 'hover $id', 'hover $id', 'hover $id'],
          reason:
              'enter is a transition and hover is a state - a hover that '
              'only fired on entry would be an enter with a second name',
        );
      },
    );

    test('exit fires when the cursor leaves, and nothing after', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final button = scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 0, 0);
      events.clear();
      _moveTo(game, 500, 500);
      _step(game);

      expect(events, <String>['exit ${button.value}']);
    });

    test(
      'moving straight from one receiver to another exits before entering',
      () async {
        final game = await _boot();
        final scene = run.state.singleScene<_Scene>();
        final button = scene.addEntity(scene.button);
        final panel = scene.addEntity(scene.panel);
        scene.pool.beginTick();
        scene.panel.transformOffsetX[panel] = 400;
        scene.pool.commitTick();
        _settle(game);

        _moveTo(game, 0, 0);
        events.clear();
        _moveTo(game, 400, 0);

        expect(
          events,
          <String>['exit ${button.value}', 'panel enter'],
          reason:
              'a handler that swaps a shared highlight has to see the '
              'two in this order, or it ends up clearing the highlight it '
              'just set',
        );
      },
    );

    test('press and release fire on whatever is under the cursor', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final button = scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 0, 0);
      events.clear();

      game.inputDevice!.press(InputKey.leftMouseButton);
      _step(game);
      game.inputDevice!.release(InputKey.leftMouseButton);
      _step(game);

      final id = button.value;
      expect(events, <String>[
        'hover $id',
        'pressed $id',
        'hover $id',
        'released $id',
      ]);
    });

    test('a press that drags off the entity fires no release on it', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final button = scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 0, 0);
      game.inputDevice!.press(InputKey.leftMouseButton);
      _step(game);
      _moveTo(game, 500, 500);
      events.clear();
      game.inputDevice!.release(InputKey.leftMouseButton);
      _step(game);

      expect(
        events,
        isEmpty,
        reason:
            'dragging off a button before letting go cancels the '
            'click, which is what every OS button does - and it falls out '
            'of dispatching to whatever is hovered *now* rather than '
            'remembering what was pressed (${button.value} is long gone)',
      );
    });

    test('clicking empty space fires nothing at all', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 500, 500);
      game.inputDevice!.press(InputKey.leftMouseButton);
      _step(game);
      game.inputDevice!.release(InputKey.leftMouseButton);
      _step(game);

      expect(events, isEmpty);
    });

    test('the button is rebindable like any other action', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final button = scene.addEntity(scene.button);
      final picking = run.state.getSystem<PointerPickingSystem>();
      picking.click.binding = const TriggerBinding(.rightMouseButton);
      _settle(game);

      _moveTo(game, 0, 0);
      events.clear();
      game.inputDevice!.press(InputKey.leftMouseButton);
      _step(game);
      expect(
        events,
        <String>['hover ${button.value}'],
        reason:
            'the picking has no opinion about which physical button '
            'clicks - that is the binding\'s job, and a left-handed '
            'settings screen swaps it',
      );

      game.inputDevice!.press(InputKey.rightMouseButton);
      _step(game);
      expect(events.last, 'pressed ${button.value}');
    });
  });

  group('the camera', () {
    test('with no camera the view is the world', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 12, 34);
      final picking = run.state.getSystem<PointerPickingSystem>();
      expect(
        picking.worldSpace,
        Vector2(12, -34),
        reason:
            'with no camera the x half is the identity byte for byte, '
            'and the y half is the plain negation that makes world +y up - '
            'a pointer 34 pixels down the view is 34 world units below the '
            'camera. That is what makes the camera optional rather than '
            'something every scene has to declare',
      );
    });

    test('a moved camera shifts what the cursor is over', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      scene.addEntity(scene.button);
      final eye = _eye(game, scene);
      scene.pool.beginTick();
      scene.eye.transformOffsetX[eye] = 1000;
      scene.pool.commitTick();
      _settle(game);

      _moveTo(game, 0, 0);
      final picking = run.state.getSystem<PointerPickingSystem>();
      expect(
        picking.worldSpace,
        Vector2(1000, 0),
        reason:
            'this game has no view, so the middle of it is (0, 0) and '
            'the cursor there reads as exactly the camera position - see '
            '"a laid-out view puts the camera in the middle" below for the '
            'same check with a real viewport',
      );
      expect(
        picking.hovered,
        isNull,
        reason:
            'the button is at the world origin, which the camera has '
            'panned a thousand units away from',
      );
    });

    test('zoom scales the projection', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final button = scene.addEntity(scene.button);
      final eye = _eye(game, scene);
      scene.pool.beginTick();
      scene.eye.cameraZoom[eye] = 2; // everything draws twice as large
      scene.pool.commitTick();
      _settle(game);

      // The radius-20 circle now covers 40 view pixels.
      _moveTo(game, 39, 0);
      final picking = run.state.getSystem<PointerPickingSystem>();
      expect(picking.hovered, button);
      expect(picking.worldSpace.x, closeTo(19.5, 1e-9));

      _moveTo(game, 41, 0);
      expect(picking.hovered, isNull);
    });

    test('the world position reaches the handler that was clicked', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final panel = scene.addEntity(scene.panel);
      scene.pool.beginTick();
      scene.panel.transformOffsetX[panel] = 500;
      scene.pool.commitTick();
      _settle(game);

      _moveTo(game, 530, 20);
      expect(scene.panel.lastWorldX, 530);
      expect(
        scene.panel.lastWorldY,
        -20,
        reason:
            'PointerPickEvent carries the world point so a handler can work '
            'out where *within* itself it was grabbed - subtract the '
            'entity\'s own world position and you have the grab offset',
      );
    });

    test(
      'a second camera is a programmer error, not a silent choice',
      () async {
        final game = await _boot();
        final scene = run.state.singleScene<_Scene>();
        _eye(game, scene);
        _eye(game, scene);

        expect(
          () => _step(game),
          throwsA(isA<AssertionError>()),
          reason:
              'one view origin, so a second camera has no meaning - the '
              'shared ActiveCameraResolver says so once, here as everywhere '
              'else that asks',
        );
      },
    );
  });

  group('the projection', () {
    test('view and world round-trip through each other', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final eye = _eye(game, scene);
      scene.pool.beginTick();
      scene.eye
        ..transformOffsetX[eye] = 120
        ..transformOffsetY[eye] = -40;
      scene.eye.cameraZoom[eye] = 1.5;
      scene.pool.commitTick();
      _settle(game);
      _moveTo(game, 0, 0);

      final projection = run.state.getSystem<PointerPickingSystem>().projection;
      expect(
        projection.worldToViewX(projection.viewToWorldX(87)),
        closeTo(87, 1e-9),
      );
      expect(
        projection.worldToViewY(projection.viewToWorldY(-13)),
        closeTo(-13, 1e-9),
      );
      expect(
        projection.worldToViewX(120),
        0,
        reason: 'the camera itself is at the view origin',
      );
    });

    test('a laid-out view puts the camera in the middle', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final button = scene.addEntity(scene.button);
      final eye = _eye(game, scene);
      scene.pool.beginTick();
      scene.eye.transformOffsetX[eye] = 1000;
      scene.pool.commitTick();
      game.inputDevice!.setViewSize(800, 600);
      game.view.setViewport(800, 600);
      _settle(game);

      final picking = run.state.getSystem<PointerPickingSystem>();
      _moveTo(game, 400, 300);
      expect(
        picking.worldSpace,
        Vector2(1000, 0),
        reason:
            'the centre of the view is where the camera is - the same '
            'rule the renderer draws by, inverted',
      );

      _moveTo(game, 0, 0);
      expect(
        picking.worldSpace,
        Vector2(600, 300),
        reason:
            'and the top-left corner is half a view up and to the left '
            'of it - up being a *larger* world y now that world +y is up, '
            'which is the sign this used to have the other way round',
      );

      // The button is at the world origin, which this camera has panned away
      // from - but a button parked under the camera is clickable at the
      // middle of the view, which is the property that would break if
      // picking and drawing disagreed about the anchor.
      scene.pool.beginTick();
      scene.button.transformOffsetX[button] = 1000;
      scene.pool.commitTick();
      _step(game);
      _moveTo(game, 400, 300);
      expect(picking.hovered, button);
    });

    test(
      'a zero zoom reports the camera origin instead of an infinity',
      () async {
        final game = await _boot();
        final scene = run.state.singleScene<_Scene>();
        final eye = _eye(game, scene);
        scene.pool.beginTick();
        scene.eye.transformOffsetX[eye] = 7;
        scene.eye.cameraZoom[eye] = 0;
        scene.pool.commitTick();
        _settle(game);
        _moveTo(game, 100, 100);

        final picking = run.state.getSystem<PointerPickingSystem>();
        expect(
          picking.worldSpace,
          Vector2(7, 0),
          reason:
              'a zoom of zero maps the world onto one pixel, so the '
              'inverse has no answer - reporting the camera origin keeps a '
              'NaN out of every distance comparison downstream, which is the '
              'kind of value that shows up three systems away from its '
              'cause',
        );
      },
    );
  });

  group('contacts', () {
    test('two contacts pick two different entities on one tick', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final left = scene.addEntity(scene.pad);
      final right = scene.addEntity(scene.pad);
      scene.pool.beginTick();
      scene.pad.transformOffsetX[left] = -300;
      scene.pad.transformOffsetX[right] = 300;
      scene.pool.commitTick();
      _settle(game);

      // Both down before a single step runs, so the tick that dispatches
      // them sees two live contacts at once. One at a time passes against a
      // picker that only ever tracks one pointer, which is what this has to
      // discriminate against.
      game.inputDevice!.pressContact(1, screenX: -300, screenY: 0);
      game.inputDevice!.pressContact(2, screenX: 300, screenY: 0);
      _step(game);

      expect(events, <String>[
        'pad down ${left.value}',
        'pad down ${right.value}',
      ], reason: 'two fingers, two entities, one tick');
      expect(
        left.value,
        isNot(right.value),
        reason: 'the two are different entities, or the test proves nothing',
      );

      // Still down. A held contact re-picks nothing.
      events.clear();
      _step(game);
      expect(events, isEmpty);

      game.inputDevice!.releaseContact(1);
      game.inputDevice!.releaseContact(2);
      _step(game);
      expect(events, <String>['pad up ${left.value}', 'pad up ${right.value}']);
    });

    test('a finger picks with the cursor parked somewhere else', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final pad = scene.addEntity(scene.pad);
      scene.pool.beginTick();
      scene.pad.transformOffsetX[pad] = 300;
      scene.pool.commitTick();
      // _settle parks the cursor at 5000, 5000 and never moves it again.
      _settle(game);

      game.inputDevice!.pressContact(7, screenX: 300, screenY: 0);
      _step(game);

      final picking = run.state.getSystem<PointerPickingSystem>();
      expect(events, <String>['pad down ${pad.value}']);
      expect(
        picking.cursor.value.screenSpace,
        Vector2(5000, 5000),
        reason:
            'a finger does not move the cursor - InputDevice reads a '
            'position into the pointer block for PointerDeviceKind.mouse '
            'only, so anything that projected the cursor here would have '
            'picked nothing',
      );
      expect(
        picking.worldSpace,
        Vector2(5000, -5000),
        reason: 'and worldSpace still answers for the cursor, not the finger',
      );
      expect(
        scene.pad.lastWorldX,
        300,
        reason:
            'the event carries the contact position, projected through the '
            'view the contact landed in',
      );
      expect(scene.pad.lastViewX, 300);
      expect(scene.pad.lastPointerId, 7);
      expect(scene.pad.lastKind, ContactKind.touch);
      expect(scene.pad.lastCancelled, isFalse);
    });

    test('one mouse click fires one press, not two', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final pad = scene.addEntity(scene.pad);
      _settle(game);
      _moveTo(game, 0, 0);
      events.clear();

      // What a real GameView writes for one left click: a button bit *and* a
      // contact of kind mouse. Both reach the picker.
      game.inputDevice!.press(InputKey.leftMouseButton);
      game.inputDevice!.pressContact(
        3,
        screenX: 0,
        screenY: 0,
        kind: ContactKind.mouse,
      );
      _step(game);

      expect(
        events,
        <String>['pad down ${pad.value}'],
        reason:
            'the contact pass skips ContactKind.mouse, so the button '
            'bit is the only thing that dispatches',
      );

      events.clear();
      game.inputDevice!.release(InputKey.leftMouseButton);
      game.inputDevice!.releaseContact(3);
      _step(game);
      expect(events, <String>['pad up ${pad.value}']);
    });

    test('a cancelled contact ends with cancelled set', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final pad = scene.addEntity(scene.pad);
      _settle(game);

      game.inputDevice!.pressContact(4, screenX: 0, screenY: 0);
      _step(game);
      expect(scene.pad.lastCancelled, isFalse);

      events.clear();
      game.inputDevice!.cancelContact(4);
      _step(game);

      expect(
        events,
        <String>['pad up ${pad.value}'],
        reason:
            'a cancelled contact still ends, so a handler that only '
            'listens for the lift does not leave a drag running forever',
      );
      expect(
        scene.pad.lastCancelled,
        isTrue,
        reason:
            'and it says so, so a handler that commits on release can '
            'abandon instead - where a cancelled contact stopped means '
            'nothing',
      );
    });

    test('a hover-only entity above does not swallow the press', () async {
      final game = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final pad = scene.addEntity(scene.pad);
      // Same place, drawn far above: z 50 against the pad, which draws
      // nothing and competes at zero.
      final glass = scene.addEntity(scene.glass);
      expect(glass.value, isNot(pad.value));
      _settle(game);

      game.inputDevice!.pressContact(5, screenX: 0, screenY: 0);
      _step(game);

      expect(
        events,
        <String>['pad down ${pad.value}'],
        reason:
            'the two mixins are queried separately, so an entity that '
            'declares only HoverReceiver is not a candidate for a press',
      );

      events.clear();
      _moveTo(game, 0, 0);
      expect(events, contains('glass enter'));
      expect(
        events.where((e) => e.startsWith('pad')),
        isEmpty,
        reason:
            'and the pad, which declares only PointerReceiver, receives '
            'no hover',
      );
    });
  });
}
