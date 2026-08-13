import 'dart:math' as math;

import 'package:goo/goo.dart';

import 'package:goo2d/src/data/camera.dart';
import 'package:goo2d/src/data/collider.dart';
import 'package:goo2d/src/data/world_transform.dart';
import 'package:goo2d/src/render/render_2d.dart';

/// One mouse interaction with one entity.
///
/// **Borrowed, not owned.** [MousePickingSystem] keeps a single event and
/// re-points it before each callback, so a handler that stores the event (or
/// any of the objects hanging off it) is storing something that will describe
/// a different entity a millisecond later. Read what you need inside the
/// callback. The alternative - a fresh event per hover, per entity, per tick -
/// is a heap object on a path that runs every tick forever (RULES.md rules 1
/// and 2), which is the same reason `Input<Vector2>.value` hands back a vector
/// it owns.
class MouseEvent {
  MouseEvent._(this.position, this.worldSpace);

  /// Which entity this event is about. Components are shared per archetype
  /// rather than instantiated per entity, so `this` inside a handler is the
  /// whole archetype's component - this is the only thing that says which
  /// entity was clicked, the same reason `onCreated` takes one.
  late Entity entity;

  /// Where the pointer is, in the spaces the kernel can answer for (screen
  /// and view). The same instance `Input<MousePosition>.value` hands out.
  final MousePosition position;

  /// Where the pointer is in **world** space - what [position] deliberately
  /// cannot carry, because projecting needs a `Camera` and cameras are a
  /// `goo2d` concept. Useful for the "grab the thing at the offset I grabbed
  /// it by" case: subtract the entity's own world position from this.
  final Vector2 worldSpace;
}

/// The five things that can happen to an entity under the cursor.
///
/// Split out from [MouseReceiver] so the *contract* is one place and the
/// no-op defaults are another - the same shape `LifecycleListener` and
/// `CollisionListener` already use.
abstract interface class MouseListener {
  void onMouseEnter(MouseEvent event);
  void onMouseHover(MouseEvent event);
  void onMouseExit(MouseEvent event);
  void onMousePressed(MouseEvent event);
  void onMouseReleased(MouseEvent event);
}

/// Makes a prefab clickable: mix in, override the events you care about, and
/// leave the rest.
///
/// An entity is a candidate when it has this **and** `Collider2D` **and**
/// `WorldTransform2D` - the shapes are what get hit-tested, so a receiver
/// with no collider is silently never picked. That is deliberate rather than
/// an assert: `Renderable2D`'s bounds would be the obvious fallback, and it
/// is the wrong one - a sprite is a rectangle even when the thing it draws is
/// a coin, and clicking the corner of a coin should miss.
mixin MouseReceiver on Component implements MouseListener {
  @override
  void onMouseEnter(MouseEvent event) {}

  @override
  void onMouseHover(MouseEvent event) {}

  @override
  void onMouseExit(MouseEvent event) {}

  @override
  void onMousePressed(MouseEvent event) {}

  @override
  void onMouseReleased(MouseEvent event) {}

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<MouseReceiver>();
  }
}

/// Answers "what is the cursor over, and what just happened to it".
///
/// Declare it like any other system (`descriptor.has(MousePickingSystem())`)
/// and every `MouseReceiver` entity in the scene starts receiving events. It
/// also publishes the world-space cursor ([worldSpace]) for anything that
/// wants the position without the picking - placing a build ghost, aiming a
/// turret at the mouse.
///
/// # What it hits
///
/// Every enabled `ColliderBody` on a candidate, tested against the cursor in
/// that entity's own local space - so a rotated, scaled entity hit-tests as
/// the shape you see, and a circle collider is a circle rather than its
/// bounding box.
///
/// Where several entities overlap, the topmost wins: the highest `zIndex`
/// among that entity's visible sprites, with later query order breaking a
/// tie, which is exactly the order `GameRenderer2D` draws in. What is on top
/// visually is what you click. An entity with no `Renderable2D` at all - an
/// invisible click zone - competes at zero, which is where an undeclared
/// `zIndex` already sits.
///
/// # Why it is fixed-rate
///
/// The plan called for the render rate, on the reasoning that input
/// resolution runs there. It does not: resolution is the first thing
/// `GameState.runFixedStep` does, and `wasPressedThisFrame` lives for exactly
/// one fixed step. A presentation-phase picker would therefore *miss clicks* -
/// a frame containing two fixed steps clears the edge in the second before
/// presentation ever sees it. Running here means every resolution is seen
/// exactly once.
///
/// The cost is that the world transforms it reads are one tick behind what
/// was last drawn (a fixed-phase read sees the last published snapshot, while
/// the renderer runs after `commitTick` and sees the new one). For a cursor
/// against a target moving at any playable speed that is under a pixel; a
/// missed click is not.
class MousePickingSystem extends GameSystem with FixedTickable {
  /// The pointer position, screen and view space. Public because a system
  /// that wants the cursor should not have to declare a second binding for
  /// the same one physical mouse.
  late final Input<MousePosition> cursor;

  /// The button that drives [MouseListener.onMousePressed] /
  /// [MouseListener.onMouseReleased].
  ///
  /// Rebindable like any action (`click.binding = const
  /// TriggerBinding(.rightMouseButton)`), which is what a left-handed
  /// settings screen needs - the picking has no opinion about which physical
  /// button it is.
  late final Input<bool> click;

  /// The camera mapping this system inverts. Exposed so a caller can project
  /// its own points without resolving a second camera - it is refreshed at
  /// the top of every tick.
  final CameraProjection projection = CameraProjection();

  /// The cursor in world space, updated once per tick.
  ///
  /// One instance for the life of the system, mutated in place - the same
  /// contract (and the same reason) as `Input<Vector2>.value`. Copy it if you
  /// need to keep it.
  final Vector2 worldSpace = Vector2.zero();

  /// The entity currently under the cursor, or `null`. The enter/exit pair is
  /// simply this changing.
  Entity? get hovered => _hovered;
  Entity? _hovered;

  late final Query _receivers;
  late final Query _cameras;

  late final MouseEvent _event = MouseEvent._(cursor.value, worldSpace);

  @override
  void describeInputs(InputDescriptor descriptor) {
    super.describeInputs(descriptor);
    cursor = descriptor.has<MousePosition>(const MouseBinding());
    click = descriptor.has<bool>(const TriggerBinding(.leftMouseButton));
  }

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    _receivers =
        descriptor.query().withAll(MouseReceiver, Collider2D, WorldTransform2D).build();
    _cameras = descriptor.query().withAll(Camera, WorldTransform2D).build();
  }

  /// After the transforms it hit-tests against - the same declaration
  /// `GameRenderer2D` makes, for the same reason.
  @override
  int compareTo(GameSystem other) => other is WorldTransformSystem ? 1 : 0;

  @override
  void onFixedUpdate() {
    projection.resolve(_cameras, game.viewWidth, game.viewHeight);
    final position = cursor.value;
    worldSpace.setValues(
      projection.viewToWorldX(position.viewSpace.x),
      projection.viewToWorldY(position.viewSpace.y),
    );

    final picked = _pick(worldSpace.x, worldSpace.y);
    final previous = _hovered;
    if (!identical(picked, previous)) {
      // Exit before enter, so a handler that swaps a shared highlight sees
      // the two in the order that leaves it on the right entity.
      if (previous != null) _dispatch(previous, _Phase.exit);
      _hovered = picked;
      if (picked != null) _dispatch(picked, _Phase.enter);
    }
    if (picked == null) return;

    _dispatch(picked, _Phase.hover);
    // Press and release both go to whatever is under the cursor *now*. A
    // press that drifts off the entity before the button comes up therefore
    // fires no release on it - which is what makes dragging off a button a
    // cancel, the behaviour every OS button has.
    if (click.wasPressedThisFrame) _dispatch(picked, _Phase.pressed);
    if (click.wasReleasedThisFrame) _dispatch(picked, _Phase.released);
  }

  /// The topmost entity whose shapes cover ([x], [y]) in world space.
  Entity? _pick(double x, double y) {
    Entity? best;
    var bestZ = 0;
    // Only the front scene is clickable, for the same reason only it is drawn
    // - picking has to agree with what the player can actually see, or a
    // background scene would swallow clicks aimed at the one on screen. See
    // `GameRenderer2D`, which resolves the same slot the same way.
    final activeSlot = SceneRegistry.active?.slot ?? -1;
    for (final entity in _receivers.run()) {
      if (entity.sceneSlot != activeSlot) continue;
      final world = entity.get<WorldTransform2D>();
      final scaleX = world.worldScaleX[entity];
      final scaleY = world.worldScaleY[entity];
      // A collapsed entity has no area to hit, and dividing by its scale
      // below would hand every shape test an infinity.
      if (scaleX == 0 || scaleY == 0) continue;

      // World -> local: undo the translation, then the rotation, then the
      // scale. Once per entity, however many bodies it declared - see
      // `ColliderBody.containsLocalPoint`.
      final dx = x - world.worldX[entity];
      final dy = y - world.worldY[entity];
      final rotation = world.worldRotation[entity];
      final cos = math.cos(rotation);
      final sin = math.sin(rotation);
      final localX = (dx * cos + dy * sin) / scaleX;
      final localY = (dy * cos - dx * sin) / scaleY;

      final bodies = entity.get<Collider2D>().bodies;
      var hit = false;
      // Indexed, not `for (final body in bodies)`: an iterator per entity per
      // tick is a heap object (RULES.md rules 1 and 5).
      for (var i = 0; i < bodies.length; i++) {
        final body = bodies[i];
        if (body.enable[entity] == 0) continue;
        if (body.containsLocalPoint(entity, localX, localY)) {
          hit = true;
          break;
        }
      }
      if (!hit) continue;

      final z = _depthOf(entity);
      // `>=`, so a later entity wins an equal-z tie. That is not arbitrary:
      // the renderer's sort is stable over query order, so of two things at
      // the same depth the later one is drawn second, i.e. on top.
      if (best == null || z >= bestZ) {
        best = entity;
        bestZ = z;
      }
    }
    return best;
  }

  /// How high up an entity is: the largest `zIndex` among its visible
  /// sprites, or zero if it draws nothing at all.
  ///
  /// The largest rather than the first, because an entity with a body sprite
  /// at 0 and a hat at 10 is, as far as anything looking at the screen is
  /// concerned, at 10.
  int _depthOf(Entity entity) {
    final renderable = entity.tryGet<Renderable2D>();
    if (renderable == null) return 0;
    final sprites = renderable.sprites;
    var z = 0;
    for (var i = 0; i < sprites.length; i++) {
      final sprite = sprites[i];
      if (sprite.visible[entity] == 0) continue;
      final own = sprite.zIndex[entity];
      if (own > z) z = own;
    }
    return z;
  }

  void _dispatch(Entity entity, _Phase phase) {
    final event = _event..entity = entity;
    final receiver = entity.get<MouseReceiver>();
    switch (phase) {
      case _Phase.enter:
        receiver.onMouseEnter(event);
      case _Phase.hover:
        receiver.onMouseHover(event);
      case _Phase.exit:
        receiver.onMouseExit(event);
      case _Phase.pressed:
        receiver.onMousePressed(event);
      case _Phase.released:
        receiver.onMouseReleased(event);
    }
  }
}

/// Which callback [MousePickingSystem._dispatch] is about to make. An enum
/// rather than passing the method itself, because a tear-off of an instance
/// method is an allocation and this happens several times a tick.
enum _Phase { enter, hover, exit, pressed, released }

/// The prebuilt shortcut for the picking system, so a component never spells
/// out `getSystem<MousePickingSystem>()` - the standing convention for this
/// engine's own built-in systems.
extension MousePickingAccess on Component {
  MousePickingSystem get mousePicking => getSystem<MousePickingSystem>();
}

extension MousePickingAccessForSystems on GameSystem {
  MousePickingSystem get mousePicking => getSystem<MousePickingSystem>();
}
