import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

// MousePickingSystem end to end: a synthetic pointer written through the
// same InputDevice a GameView writes through, a real scene of colliders, and
// the events a MouseReceiver prefab actually receives. Everything runs on one
// copy (start(inline: true, autoTick: false)) and is stepped by hand, so
// there are no timers and every tick boundary in these tests is explicit -
// which matters here, because half of what is being checked is *when* an
// event fires rather than whether.

/// What every receiver in this file appends to.
final List<String> events = <String>[];

/// A round button. One circle collider, one sprite, so it participates in
/// the z-order tie-break.
class _Button extends EntityStruct<_Button>
    with Transform2D, WorldTransform2D, Renderable2D, Collider2D, MouseReceiver {
  late final Sprite sprite;
  late final CircleBody hitArea;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    sprite = descriptor.has(width: 40, height: 40);
  }

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    hitArea = descriptor.hasCircleCollider(radius: 20);
  }

  @override
  void onMouseEnter(MouseEvent event) => events.add('enter ${event.entity.value}');
  @override
  void onMouseExit(MouseEvent event) => events.add('exit ${event.entity.value}');
  @override
  void onMouseHover(MouseEvent event) => events.add('hover ${event.entity.value}');
  @override
  void onMousePressed(MouseEvent event) => events.add('pressed ${event.entity.value}');
  @override
  void onMouseReleased(MouseEvent event) => events.add('released ${event.entity.value}');
}

/// A panel drawn above the buttons - same shape family, higher z, and it
/// records the world position it was clicked at.
class _Panel extends EntityStruct<_Panel>
    with Transform2D, WorldTransform2D, Renderable2D, Collider2D, MouseReceiver {
  late final Sprite sprite;
  late final BoxBody hitArea;

  double lastWorldX = double.nan;
  double lastWorldY = double.nan;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    sprite = descriptor.has(width: 200, height: 100, zIndex: 10);
  }

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    hitArea = descriptor.hasBoxCollider(halfWidth: 100, halfHeight: 50);
  }

  @override
  void onMouseEnter(MouseEvent event) {
    events.add('panel enter');
    lastWorldX = event.worldSpace.x;
    lastWorldY = event.worldSpace.y;
  }

  @override
  void onMouseExit(MouseEvent event) => events.add('panel exit');
}

/// A receiver with no `Renderable2D` at all - an invisible click zone.
class _Zone extends EntityStruct<_Zone>
    with Transform2D, WorldTransform2D, Collider2D, MouseReceiver {
  late final BoxBody hitArea;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    hitArea = descriptor.hasBoxCollider(halfWidth: 50, halfHeight: 50);
  }

  @override
  void onMouseEnter(MouseEvent event) => events.add('zone enter');
  @override
  void onMouseExit(MouseEvent event) => events.add('zone exit');
}

/// A receiver that declares no collider - the "silently never picked" case.
class _Naked extends EntityStruct<_Naked>
    with Transform2D, WorldTransform2D, MouseReceiver {
  @override
  void onMouseEnter(MouseEvent event) => events.add('naked enter');
}

class _Eye extends EntityStruct<_Eye> with Transform2D, WorldTransform2D, Camera {}

class _Scene extends SceneStruct {
  @override
  void onMounted(Scene scene) => handle = scene;

  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late Scene handle;

  Entity addEntity<T extends EntityStruct<T>>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Scene();

  late final _Button button;
  late final _Panel panel;
  late final _Zone zone;
  late final _Naked naked;
  late final _Eye eye;

  @override
  void describeScene(SceneDescriptor descriptor) {
    button = descriptor.has(_Button());
    panel = descriptor.has(_Panel());
    zone = descriptor.has(_Zone());
    naked = descriptor.has(_Naked());
    eye = descriptor.has(_Eye());
  }
}

class _GameState extends GameState<_Game> with LifecycleListener {
  @override
  void onMounted() {
    loadScene(_Scene());
  }
}

class _Game extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _GameState();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(MousePickingSystem());
    // Declared *after* the picker, so the ordering that makes picking read
    // resolved transforms has to come from compareTo rather than from the
    // order these two are written in.
    descriptor.has(WorldTransformSystem());
  }
}

Future<_Game> _boot() async {
  final game = _Game();
  await game.start(inline: true, autoTick: false);
  addTearDown(() async {
    if (game.isRunning) await game.stop();
  });
  return game;
}

/// Puts the cursor at a view-space point and runs one fixed step, which is
/// one input resolution and one pass of the picker.
void _moveTo(_Game game, double x, double y) {
  game.inputDevice!.movePointer(screenX: x, screenY: y);
  game.state!.runFixedStep();
}

/// A tick with no pointer movement - the picker still runs.
void _step(_Game game) => game.state!.runFixedStep();

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
  game.state!.runFixedStep();
  events.clear();
}

void main() {
  setUp(events.clear);

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('hit testing', () {
    test('the cursor picks the shape, not the sprite\'s bounding box',
        () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final button = scene.addEntity(scene.button);
      _settle(game);

      // The button is a radius-20 circle at the origin under a 40x40 sprite.
      _moveTo(game, 0, 0);
      expect(game.getSystem<MousePickingSystem>().hovered, button);

      _moveTo(game, 19, 0);
      expect(game.getSystem<MousePickingSystem>().hovered, button);

      _moveTo(game, 15, 15);
      expect(game.getSystem<MousePickingSystem>().hovered, isNull,
          reason: 'the corner of the sprite is outside the circle - the '
              'whole reason picking goes through Collider2D instead of '
              'Renderable2D\'s bounds');
    });

    test('a receiver with no collider is never picked', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      scene.addEntity(scene.naked);
      _settle(game);

      _moveTo(game, 0, 0);
      expect(game.getSystem<MousePickingSystem>().hovered, isNull);
      expect(events, isEmpty,
          reason: 'the query requires Collider2D, so a receiver with nothing '
              'to hit-test simply is not a candidate');
    });

    test('the entity\'s world transform moves its shape', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final button = scene.addEntity(scene.button);
      scene.pool.beginTick();
      scene.button.transformOffsetX[button] = 300;
      scene.pool.commitTick();
      _settle(game);

      _moveTo(game, 0, 0);
      expect(game.getSystem<MousePickingSystem>().hovered, isNull);
      _moveTo(game, 300, 0);
      expect(game.getSystem<MousePickingSystem>().hovered, button,
          reason: 'the collider is declared in local space and placed by the '
              'entity\'s own WorldTransform2D, which is what makes a moving '
              'target clickable where it is drawn rather than where it '
              'started');
    });

    test('rotation and scale are undone, so a box hit-tests as it looks',
        () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final panel = scene.addEntity(scene.panel);
      scene.pool.beginTick();
      scene.panel
        ..transformRotation[panel] = math.pi / 2 // a quarter turn
        ..transformScaleX[panel] = 2;
      scene.pool.commitTick();
      _settle(game);

      // The panel is 200x100 (half-extents 100x50) and its x axis is scaled
      // 2x, so unrotated it would cover +/-200 horizontally and +/-50
      // vertically. Turned a quarter turn, those swap.
      _moveTo(game, 0, 190);
      expect(game.getSystem<MousePickingSystem>().hovered, panel,
          reason: 'the long axis now runs down the screen');
      _moveTo(game, 190, 0);
      expect(game.getSystem<MousePickingSystem>().hovered, isNull,
          reason: 'and no longer runs across it - a picker that ignored '
              'rotation would report a hit here');
      _moveTo(game, 0, 210);
      expect(game.getSystem<MousePickingSystem>().hovered, isNull);
      _moveTo(game, 40, 0);
      expect(game.getSystem<MousePickingSystem>().hovered, panel,
          reason: 'the short axis is 50 local units, unaffected by the x '
              'scale');
    });

    test('a disabled body stops picking without being removed', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final button = scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 0, 0);
      expect(game.getSystem<MousePickingSystem>().hovered, button);

      scene.pool.beginTick();
      scene.button.hitArea.enable[button] = 0;
      scene.pool.commitTick();
      _step(game);

      expect(game.getSystem<MousePickingSystem>().hovered, isNull);
      expect(events.last, 'exit ${button.value}',
          reason: 'disabling what the cursor was over is a real exit - the '
              'entity stopped being under the cursor, however it happened');
    });
  });

  group('overlap order', () {
    test('the higher zIndex wins', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      // Both cover the origin; the panel's sprite is at zIndex 10.
      scene.addEntity(scene.button);
      final panel = scene.addEntity(scene.panel);
      _settle(game);

      _moveTo(game, 0, 0);
      expect(game.getSystem<MousePickingSystem>().hovered, panel,
          reason: 'what is drawn on top is what gets clicked - one ordering, '
              'not two that can disagree');
      expect(events, contains('panel enter'));
    });

    test('at equal z the later entity wins, matching the draw order',
        () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final first = scene.addEntity(scene.button);
      final second = scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 0, 0);
      expect(game.getSystem<MousePickingSystem>().hovered, second,
          reason: 'the renderer\'s z sort is stable over query order, so of '
              'two sprites at the same depth the later one is drawn second - '
              'i.e. on top. Picking the earlier one would mean clicking '
              'through the thing you can see (${first.value} is underneath)');
    });

    test('an invisible click zone competes at zero', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final zone = scene.addEntity(scene.zone);
      _settle(game);

      _moveTo(game, 0, 0);
      expect(game.getSystem<MousePickingSystem>().hovered, zone,
          reason: 'no Renderable2D at all is not a disqualification - an '
              'entity with only a collider is a click zone, and it sits at '
              'the depth an undeclared zIndex already means');

      // Now put a drawn button over it, one layer up.
      final button = scene.addEntity(scene.button);
      scene.pool.beginTick();
      scene.button.sprite.zIndex[button] = 1;
      scene.pool.commitTick();
      _step(game);

      expect(game.getSystem<MousePickingSystem>().hovered, button,
          reason: 'zero is a real depth, not an exemption: anything actually '
              'drawn above the zone takes the click, exactly as if the zone '
              'were a sprite at zIndex 0');
    });

    test('an entity is measured by its topmost visible sprite', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final button = scene.addEntity(scene.button);
      final panel = scene.addEntity(scene.panel);
      scene.pool.beginTick();
      // Between the two, but still under the panel's 10.
      scene.button.sprite.zIndex[button] = 5;
      scene.pool.commitTick();
      _settle(game);

      _moveTo(game, 0, 0);
      expect(game.getSystem<MousePickingSystem>().hovered, panel);

      // Hide the panel's only sprite: it now draws nothing, so it has no
      // visible depth to win with.
      scene.pool.beginTick();
      scene.panel.sprite.visible[panel] = 0;
      scene.pool.commitTick();
      _step(game);

      expect(game.getSystem<MousePickingSystem>().hovered, button,
          reason: 'an invisible sprite is not drawn, so it cannot be what '
              'you are clicking on - depth comes from what is actually on '
              'screen. The panel is still a candidate at depth zero, it just '
              'no longer outranks the button\'s 5');
    });
  });

  group('hover and click events', () {
    test('enter fires once on the transition, hover every tick after',
        () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final button = scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 0, 0);
      _step(game);
      _step(game);

      final id = button.value;
      expect(events, <String>['enter $id', 'hover $id', 'hover $id', 'hover $id'],
          reason: 'enter is a transition and hover is a state - a hover that '
              'only fired on entry would be an enter with a second name');
    });

    test('exit fires when the cursor leaves, and nothing after', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final button = scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 0, 0);
      events.clear();
      _moveTo(game, 500, 500);
      _step(game);

      expect(events, <String>['exit ${button.value}']);
    });

    test('moving straight from one receiver to another exits before entering',
        () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final button = scene.addEntity(scene.button);
      final panel = scene.addEntity(scene.panel);
      scene.pool.beginTick();
      scene.panel.transformOffsetX[panel] = 400;
      scene.pool.commitTick();
      _settle(game);

      _moveTo(game, 0, 0);
      events.clear();
      _moveTo(game, 400, 0);

      expect(events, <String>['exit ${button.value}', 'panel enter'],
          reason: 'a handler that swaps a shared highlight has to see the '
              'two in this order, or it ends up clearing the highlight it '
              'just set');
    });

    test('press and release fire on whatever is under the cursor', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
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
      final scene = game.state!.getScene<_Scene>();
      final button = scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 0, 0);
      game.inputDevice!.press(InputKey.leftMouseButton);
      _step(game);
      _moveTo(game, 500, 500);
      events.clear();
      game.inputDevice!.release(InputKey.leftMouseButton);
      _step(game);

      expect(events, isEmpty,
          reason: 'dragging off a button before letting go cancels the '
              'click, which is what every OS button does - and it falls out '
              'of dispatching to whatever is hovered *now* rather than '
              'remembering what was pressed (${button.value} is long gone)');
    });

    test('clicking empty space fires nothing at all', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
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
      final scene = game.state!.getScene<_Scene>();
      final button = scene.addEntity(scene.button);
      final picking = game.getSystem<MousePickingSystem>();
      picking.click.binding = const TriggerBinding(.rightMouseButton);
      _settle(game);

      _moveTo(game, 0, 0);
      events.clear();
      game.inputDevice!.press(InputKey.leftMouseButton);
      _step(game);
      expect(events, <String>['hover ${button.value}'],
          reason: 'the picking has no opinion about which physical button '
              'clicks - that is the binding\'s job, and a left-handed '
              'settings screen swaps it');

      game.inputDevice!.press(InputKey.rightMouseButton);
      _step(game);
      expect(events.last, 'pressed ${button.value}');
    });
  });

  group('the camera', () {
    test('with no camera the view is the world', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      scene.addEntity(scene.button);
      _settle(game);

      _moveTo(game, 12, 34);
      final picking = game.getSystem<MousePickingSystem>();
      expect(picking.worldSpace, Vector2(12, 34),
          reason: 'the identity, byte for byte - which is what makes the '
              'camera optional rather than something every scene has to '
              'declare');
    });

    test('a moved camera shifts what the cursor is over', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      scene.addEntity(scene.button);
      final eye = scene.addEntity(scene.eye);
      scene.pool.beginTick();
      scene.eye.transformOffsetX[eye] = 1000;
      scene.pool.commitTick();
      _settle(game);

      _moveTo(game, 0, 0);
      final picking = game.getSystem<MousePickingSystem>();
      expect(picking.worldSpace, Vector2(1000, 0),
          reason: 'this game has no view, so the middle of it is (0, 0) and '
              'the cursor there reads as exactly the camera position - see '
              '"a laid-out view puts the camera in the middle" below for the '
              'same check with a real viewport');
      expect(picking.hovered, isNull,
          reason: 'the button is at the world origin, which the camera has '
              'panned a thousand units away from');
    });

    test('zoom scales the projection', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final button = scene.addEntity(scene.button);
      final eye = scene.addEntity(scene.eye);
      scene.pool.beginTick();
      scene.eye.zoom[eye] = 2; // everything draws twice as large
      scene.pool.commitTick();
      _settle(game);

      // The radius-20 circle now covers 40 view pixels.
      _moveTo(game, 39, 0);
      final picking = game.getSystem<MousePickingSystem>();
      expect(picking.hovered, button);
      expect(picking.worldSpace.x, closeTo(19.5, 1e-9));

      _moveTo(game, 41, 0);
      expect(picking.hovered, isNull);
    });

    test('the world position reaches the handler that was clicked', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final panel = scene.addEntity(scene.panel);
      scene.pool.beginTick();
      scene.panel.transformOffsetX[panel] = 500;
      scene.pool.commitTick();
      _settle(game);

      _moveTo(game, 530, 20);
      expect(scene.panel.lastWorldX, 530);
      expect(scene.panel.lastWorldY, 20,
          reason: 'MouseEvent carries the world point so a handler can work '
              'out where *within* itself it was grabbed - subtract the '
              'entity\'s own world position and you have the grab offset');
    });

    test('a second camera is a programmer error, not a silent choice',
        () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      scene.addEntity(scene.eye);
      scene.addEntity(scene.eye);

      expect(() => _step(game), throwsA(isA<AssertionError>()),
          reason: 'one view origin, so a second camera has no meaning - the '
              'shared ActiveCameraResolver says so once, here as everywhere '
              'else that asks');
    });
  });

  group('the projection', () {
    test('view and world round-trip through each other', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final eye = scene.addEntity(scene.eye);
      scene.pool.beginTick();
      scene.eye
        ..transformOffsetX[eye] = 120
        ..transformOffsetY[eye] = -40;
      scene.eye.zoom[eye] = 1.5;
      scene.pool.commitTick();
      _settle(game);
      _moveTo(game, 0, 0);

      final projection = game.getSystem<MousePickingSystem>().projection;
      expect(projection.worldToViewX(projection.viewToWorldX(87)),
          closeTo(87, 1e-9));
      expect(projection.worldToViewY(projection.viewToWorldY(-13)),
          closeTo(-13, 1e-9));
      expect(projection.worldToViewX(120), 0,
          reason: 'the camera itself is at the view origin');
    });

    test('a laid-out view puts the camera in the middle', () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final button = scene.addEntity(scene.button);
      final eye = scene.addEntity(scene.eye);
      scene.pool.beginTick();
      scene.eye.transformOffsetX[eye] = 1000;
      scene.pool.commitTick();
      game.inputDevice!.setViewSize(800, 600);
      _settle(game);

      final picking = game.getSystem<MousePickingSystem>();
      _moveTo(game, 400, 300);
      expect(picking.worldSpace, Vector2(1000, 0),
          reason: 'the centre of the view is where the camera is - the same '
              'rule the renderer draws by, inverted');

      _moveTo(game, 0, 0);
      expect(picking.worldSpace, Vector2(600, -300),
          reason: 'and the top-left corner is half a view up and to the left '
              'of it');

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

    test('a zero zoom reports the camera origin instead of an infinity',
        () async {
      final game = await _boot();
      final scene = game.state!.getScene<_Scene>();
      final eye = scene.addEntity(scene.eye);
      scene.pool.beginTick();
      scene.eye.transformOffsetX[eye] = 7;
      scene.eye.zoom[eye] = 0;
      scene.pool.commitTick();
      _settle(game);
      _moveTo(game, 100, 100);

      final picking = game.getSystem<MousePickingSystem>();
      expect(picking.worldSpace, Vector2(7, 0),
          reason: 'a zoom of zero maps the world onto one pixel, so the '
              'inverse has no answer - reporting the camera origin keeps a '
              'NaN out of every distance comparison downstream, which is the '
              'kind of value that shows up three systems away from its '
              'cause');
    });
  });
}
