import 'dart:math' as math;

import 'package:good/good.dart';

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
/// callback.
///
/// A fresh event per hover, per entity, per tick would be a heap object on a
/// path that runs every tick forever (the no-allocation and hot-event rules).
/// `Input<Vector2>.value` hands back a vector it owns for the same reason.
class MouseEvent {
  MouseEvent._(this.position, this.worldSpace);

  /// Which entity this event is about. Components are shared per archetype
  /// and not instantiated per entity, so `this` inside a handler is the whole
  /// archetype's component - this is the only thing that says which entity
  /// was clicked, the same reason `onEntityMounted` takes one.
  late Entity entity;

  /// Where the pointer is, in the spaces the kernel can answer for (screen
  /// and view). The same instance `Input<CursorPosition>.value` hands out.
  final CursorPosition position;

  /// Where the pointer is in **world** space - what [position] cannot carry,
  /// because projecting needs a `Camera` and cameras are a `goo2d` concept.
  /// Useful for the "grab the thing at the offset I grabbed it by" case:
  /// subtract the entity's own world position from this.
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
/// with no collider is silently never picked. Nothing asserts on that, and
/// nothing falls back to `Renderable2D`'s bounds: a sprite is a rectangle
/// even when the thing it draws is a coin, and clicking the corner of a coin
/// should miss.
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
/// the shape you see, and a circle collider is a circle, not its bounding
/// box.
///
/// Where several entities overlap, the topmost wins: the highest `zIndex`
/// among that entity's visible sprites, with later query order breaking a
/// tie, which is exactly the order `GameRenderer2D` draws in. What is on top
/// visually is what you click. An entity with no `Renderable2D` at all - an
/// invisible click zone - competes at zero, which is where an undeclared
/// `zIndex` already sits.
///
/// Only entities the view under the pointer actually draws are candidates. A
/// view draws the scene its camera is in, and picking asks the same
/// `CameraProjection` the drawing asked, so a level preloaded behind the one
/// on screen is not clickable and a click cannot reach something that was
/// never drawn.
///
/// # Why it is fixed-rate
///
/// Input resolution is the first thing `GameState.runFixedStep` does, and
/// `wasPressedThisFrame` lives for exactly one fixed step. A picker in the
/// presentation phase would therefore *miss clicks* - a frame containing two
/// fixed steps clears the edge in the second before presentation ever sees
/// it. Running here means every resolution is seen exactly once.
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
  late final Input<CursorPosition> cursor;

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

  final _receivers = Query.all(MouseReceiver, Collider2D, WorldTransform2D);
  final _cameras = Query.all(Camera, WorldTransform2D);

  late final MouseEvent _event = MouseEvent._(cursor.value, worldSpace);

  @override
  void describeInputs(InputDescriptor descriptor) {
    super.describeInputs(descriptor);
    cursor = descriptor.has<CursorPosition>(const MouseBinding());
    click = descriptor.has<bool>(const TriggerBinding(.leftMouseButton));
  }

  /// After the transforms it hit-tests against - the same declaration
  /// `GameRenderer2D` makes, for the same reason.
  @override
  int compareTo(GameSystem other) => other is WorldTransformSystem ? 1 : 0;

  @override
  void onFixedUpdate() {
    // The view the pointer is actually over, reported by the `GameView` that
    // received the event. That is what makes picking correct with several
    // views on screen - a click has to be projected through the camera whose
    // pixels it landed on, or it hits whatever a different camera is looking
    // at.
    //
    // Falls back to the first declared view when nothing named one: a
    // headless harness driving `movePointer` without a view, and every
    // single-view game, where the fallback and the answer are the same view.
    final views = game.cameraViews;
    if (views.length == 0) return;
    projection.resolve(_cameras, game.pointerView ?? views[0]);
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
  ///
  /// # Two things keep this off the profile
  ///
  /// **Grouped.** A component instance belongs to an archetype, so
  /// `entity.get<WorldTransform2D>()` hands back the same object for every
  /// row - a registry lookup per candidate for an answer that changes once
  /// per archetype. `groups()` resolves it once per archetype instead, which
  /// is what `docs/guide/performance.md` names as the fix for the single most
  /// common cost in this engine.
  ///
  /// **A bound before the exact test.** Inverting a transform is a `cos`, a
  /// `sin` and two divides, and testing every body of every candidate exactly
  /// pays that for the whole scene on every tick. [ColliderBody.boundCovers]
  /// answers "is the cursor anywhere near this" from one squared distance
  /// first, and it is a circle about the entity's origin because that is the
  /// bound that does not need the angle. So the trig and the exact tests are
  /// paid once per entity the cursor is actually close to, and not at all for
  /// the rest.
  Entity? _pick(double x, double y) {
    Entity? best;
    var bestZ = 0;
    // Grouped, so `WorldTransform2D`, `Collider2D`, its body list and
    // `Renderable2D` are resolved once per archetype instead of once per row.
    // Group order is archetype registration order, the same order `run()`
    // walked and the same order `GameRenderer2D` draws in - which is what the
    // equal-z tie-break below leans on.
    for (final group in _receivers.groups()) {
      final world = group.get<WorldTransform2D>();
      final bodies = group.get<Collider2D>().bodies;
      // Not in the query - an invisible click zone is a receiver with no
      // sprites at all - so `tryGet`, once, and `_depthOf` is told the answer
      // instead of asking per hit.
      final renderable = group.tryGet<Renderable2D>();
      for (final entity in group) {
        // Only what the view under the pointer draws is clickable, and
        // `projection.shows` is the same call `GameRenderer2D` skips entities
        // with - off a projection resolved for the same view, so the two
        // cannot disagree about which scene that is. Let them disagree and a
        // click lands on an entity that was never drawn.
        if (!projection.shows(entity)) continue;
        final scaleX = world.worldScaleX[entity];
        final scaleY = world.worldScaleY[entity];
        // A collapsed entity has no area to hit, and dividing by its scale
        // below would hand every shape test an infinity.
        if (scaleX == 0 || scaleY == 0) continue;

        final dx = x - world.worldX[entity];
        final dy = y - world.worldY[entity];
        // How far the cursor is from the entity's origin, squared, in the
        // entity's **local** space - or rather, a number that cannot exceed
        // it. A local point `p` lands at `rotate(scale(p))` in world space;
        // rotation does not change a length and scaling stretches one by at
        // most the larger of the two factors, so dividing the squared world
        // distance by the larger factor squared can only come out short.
        // Short is the safe direction: `boundCovers` fed too small a distance
        // keeps a body it could have dropped. Taking the larger of the two
        // factors is what makes this hold on a squashed entity as well as a
        // stretched one, and the signs drop out because it is squared.
        final larger = scaleX * scaleX > scaleY * scaleY
            ? scaleX * scaleX
            : scaleY * scaleY;
        final localDistanceSquared = (dx * dx + dy * dy) / larger;

        // Deferred until a body survives its bound, which is the whole point:
        // the cursor is near nothing almost every tick, and an entity it is
        // near nothing of never reads its rotation at all.
        var inverted = false;
        var localX = 0.0;
        var localY = 0.0;

        var hit = false;
        // Indexed, not `for (final body in bodies)`: an iterator per entity
        // per tick is a heap object (the no-allocation and no-closure rules).
        for (var i = 0; i < bodies.length; i++) {
          final body = bodies[i];
          // The bound before `enable`, which is the other way round from how
          // it reads. `enable` only ever removes a body, so testing it second
          // gives the same answer - and it is a column read, which the bound
          // spares almost every body in the scene.
          if (!body.boundCovers(entity, localDistanceSquared)) continue;
          if (!body.enable[entity]) continue;
          if (!inverted) {
            // World -> local: undo the translation, then the rotation, then
            // the scale. Once per entity, however many bodies it declared -
            // see `ColliderBody.containsLocalPoint`.
            final rotation = world.worldRotation[entity];
            final cos = math.cos(rotation);
            final sin = math.sin(rotation);
            localX = (dx * cos + dy * sin) / scaleX;
            localY = (dy * cos - dx * sin) / scaleY;
            inverted = true;
          }
          if (body.containsLocalPoint(entity, localX, localY)) {
            hit = true;
            break;
          }
        }
        if (!hit) continue;

        final z = _depthOf(renderable, entity);
        // `>=`, so a later entity wins an equal-z tie. That is not arbitrary:
        // the renderer's sort is stable over query order, so of two things at
        // the same depth the later one is drawn second, i.e. on top.
        if (best == null || z >= bestZ) {
          best = entity;
          bestZ = z;
        }
      }
    }
    return best;
  }

  /// How high up an entity is: the largest `zIndex` among its visible
  /// sprites, or zero if it draws nothing at all.
  ///
  /// The largest, not the first, because an entity with a body sprite at 0
  /// and a hat at 10 is, as far as anything looking at the screen is
  /// concerned, at 10.
  ///
  /// [renderable] is this entity's archetype's, resolved by the caller once
  /// per group, and `null` for a receiver that declares no sprites.
  int _depthOf(Renderable2D? renderable, Entity entity) {
    if (renderable == null) return 0;
    final sprites = renderable.sprites;
    var z = 0;
    for (var i = 0; i < sprites.length; i++) {
      final sprite = sprites[i];
      if (!sprite.visible[entity]) continue;
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

/// Which callback [MousePickingSystem._dispatch] is about to make. An enum,
/// and not the method itself: a tear-off of an instance method is an
/// allocation, and this happens several times a tick.
enum _Phase { enter, hover, exit, pressed, released }

/// The prebuilt shortcut for the picking system, so a component never spells
/// out `getSystem<MousePickingSystem>()` - the standing convention for this
/// engine's own built-in systems.
extension MousePickingAccess on Component {
  MousePickingSystem get mousePicking => getSystem<MousePickingSystem>();
}

/// [MousePickingAccess], for a system instead of a component.
extension MousePickingAccessForSystems on GameSystem {
  MousePickingSystem get mousePicking => getSystem<MousePickingSystem>();
}
