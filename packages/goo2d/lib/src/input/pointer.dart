import 'dart:math' as math;

import 'package:good/good.dart';

import 'package:goo2d/src/data/camera.dart';
import 'package:goo2d/src/data/collider.dart';
import 'package:goo2d/src/data/world_transform.dart';
import 'package:goo2d/src/render/render_2d.dart';

/// One pointer interaction with one entity - a finger, a stylus, or the mouse.
///
/// **Borrowed, not owned.** [PointerPickingSystem] keeps a single event and
/// re-points it before each callback, so a handler that stores the event (or
/// any of the objects hanging off it) is storing something that will describe
/// a different entity a millisecond later. Read what you need inside the
/// callback.
///
/// A fresh event per hover, per entity, per tick would be a heap object on a
/// path that runs every tick forever (the no-allocation and hot-event rules).
/// `Input<Vector2>.value` hands back a vector it owns for the same reason.
class PointerPickEvent {
  PointerPickEvent._();

  /// Which entity this event is about. Components are shared per archetype
  /// and not instantiated per entity, so `this` inside a handler is the whole
  /// archetype's component - this is the only thing that says which entity
  /// was picked, the same reason `onEntityMounted` takes one.
  late Entity entity;

  /// This pointer in window coordinates, origin at the window's top-left -
  /// the space `CursorPosition.screenSpace` and `PointerContact.screenSpace`
  /// both report in.
  ///
  /// Copied out of whichever of the two drove this event, and not a reference
  /// to it: a finger does not move the cursor
  /// (`InputDevice.handlePointerEvent` reads a position into the pointer
  /// block for `PointerDeviceKind.mouse` only), so an event carrying a
  /// `CursorPosition` would answer a touch handler with wherever the mouse
  /// was last.
  final Vector2 screenSpace = Vector2.zero();

  /// This pointer within the `GameView`'s own rect, origin at its top-left -
  /// the space to hit-test a HUD in. See [screenSpace] on why it is a copy.
  final Vector2 viewSpace = Vector2.zero();

  /// This pointer in **world** space, projected through the camera of the
  /// view it is actually in - which for a contact is `Game.viewOfContact` and
  /// not `Game.pointerView`, so two fingers on two views project through two
  /// cameras.
  ///
  /// Useful for the "grab the thing at the offset I grabbed it by" case:
  /// subtract the entity's own world position from this.
  final Vector2 worldSpace = Vector2.zero();

  /// The contact this event came from, stable for that contact's whole life,
  /// and `0` for the cursor.
  ///
  /// What to key a per-finger drag on: the position of a contact in
  /// `PointerContacts` moves as earlier contacts end, and this does not.
  int get pointerId => _pointerId;
  int _pointerId = 0;

  /// What is pressing or hovering. [ContactKind.mouse] for anything the
  /// cursor drove, which is every [HoverListener] callback.
  ContactKind get kind => _kind;
  ContactKind _kind = ContactKind.mouse;

  /// Whether the contact behind this [PointerListener.onPointerUp] ended
  /// **without** a lift - a notification, an incoming call, or a widget that
  /// won the gesture arena.
  ///
  /// Where it ended says nothing about intent, so a handler that commits an
  /// action on release checks this and abandons instead. This rides the event
  /// rather than firing a callback of its own so that every callback on both
  /// mixins is reachable by every device that can apply the mixin: the
  /// cursor's press and release come off a button bit through [click], which
  /// carries no cancellation, so an `onPointerCancel` would be a callback a
  /// mouse-driven game could never receive.
  ///
  /// Always false on a cursor-driven event and on
  /// [PointerListener.onPointerDown].
  bool get cancelled => _cancelled;
  bool _cancelled = false;
}

/// The two things that can happen to an entity under **any** pointer.
///
/// Split out from [PointerReceiver] so the *contract* is one place and the
/// no-op defaults are another - the same shape `LifecycleListener` and
/// `CollisionListener` already use.
abstract interface class PointerListener {
  void onPointerDown(PointerPickEvent event);
  void onPointerUp(PointerPickEvent event);
}

/// The three things that can happen to an entity under a pointer that reports
/// a position **without** pressing. [PointerListener], for hovering.
abstract interface class HoverListener {
  void onHoverEnter(PointerPickEvent event);
  void onHover(PointerPickEvent event);
  void onHoverExit(PointerPickEvent event);
}

/// Makes a prefab pressable by any pointer: mix in, override the events you
/// care about, and leave the rest.
///
/// A finger, a stylus, a trackpad and a mouse button all reach these. That is
/// what the input layer already says: `ContactKind`'s doc has it as *"a
/// contact is a press, and a mouse that is merely over the window is not
/// pressing"*, and `InputDevice` opens a contact slot for a `PointerDownEvent`
/// of every device kind. So press and release are the whole of what is common
/// to pointer devices, and they are the whole of this mixin.
///
/// Hovering is not here. A finger is either down on an entity or absent from
/// it, with no state in between to enter or leave, so enter/hover/exit live on
/// [HoverReceiver] - which a touch-driven game does not apply, and is told so
/// by the name. A prefab that wants both applies both.
///
/// An entity is a candidate when it has this **and** `Collider2D` **and**
/// `WorldTransform2D` - the shapes are what get hit-tested, so a receiver
/// with no collider is silently never picked. Nothing asserts on that, and
/// nothing falls back to `Renderable2D`'s bounds: a sprite is a rectangle
/// even when the thing it draws is a coin, and clicking the corner of a coin
/// should miss.
mixin PointerReceiver on Component implements PointerListener {
  @override
  void onPointerDown(PointerPickEvent event) {}

  @override
  void onPointerUp(PointerPickEvent event) {}

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<PointerReceiver>();
  }
}

/// Makes a prefab respond to a pointer that is over it without pressing:
/// a mouse cursor, or a stylus a device reports hovering.
///
/// **A finger never reaches these.** Hover is a position without a press, and
/// a touch device reports no position at all until it presses - which is
/// exactly why this is a mixin of its own instead of three more callbacks on
/// [PointerReceiver]. A game built for fingers applies [PointerReceiver] and
/// gets a surface where every callback fires.
///
/// One entity hovers at a time, because there is one cursor. The pressing half
/// is per contact and lives on [PointerReceiver].
///
/// Candidacy is [PointerReceiver]'s: this **and** `Collider2D` **and**
/// `WorldTransform2D`. The two are queried separately, so an entity that
/// declares only this does not swallow a press aimed at something beneath it,
/// and one that declares only [PointerReceiver] does not block a highlight.
mixin HoverReceiver on Component implements HoverListener {
  @override
  void onHoverEnter(PointerPickEvent event) {}

  @override
  void onHover(PointerPickEvent event) {}

  @override
  void onHoverExit(PointerPickEvent event) {}

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<HoverReceiver>();
  }
}

/// Answers "what is a pointer over, and what just happened to it".
///
/// Declare it like any other system (`descriptor.has(PointerPickingSystem.new)`)
/// and every [PointerReceiver] and [HoverReceiver] entity in the scene starts
/// receiving events. It also publishes the world-space cursor ([worldSpace])
/// for anything that wants the position without the picking - placing a build
/// ghost, aiming a turret at the mouse.
///
/// # The two passes
///
/// **Contacts** drive [PointerListener.onPointerDown] and
/// [PointerListener.onPointerUp], one dispatch per contact per tick, each
/// projected through the view that contact landed in. Two fingers on two
/// entities both fire on the same tick, and two fingers on two `GameView`s
/// project through two cameras.
///
/// **The cursor** drives [HoverListener] and, through [click], the pressing
/// pair as well.
///
/// A mouse button produces *both* a contact and a button bit, so the contact
/// pass skips [ContactKind.mouse] - the convention `ContactBinding`'s own doc
/// states. Without that skip one click fires [PointerListener.onPointerDown]
/// twice.
///
/// The cursor pass runs second so [projection] and [worldSpace] describe the
/// cursor when the tick ends, which is what their own docs promise.
///
/// # What it hits
///
/// Every enabled `ColliderBody` on a candidate, tested against the pointer in
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
/// the renderer runs after `commitTick` and sees the new one). For a pointer
/// against a target moving at any playable speed that is under a pixel; a
/// missed click is not.
class PointerPickingSystem extends GameSystem with FixedTickable {
  /// The cursor position, screen and view space. Public because a system
  /// that wants the cursor should not have to declare a second binding for
  /// the same one physical mouse.
  ///
  /// The mouse's, and nothing else's: a finger does not move it. Read
  /// [contacts] for those.
  final cursor = Input.of<CursorPosition>(const MouseBinding());

  /// The button that drives [PointerListener.onPointerDown] /
  /// [PointerListener.onPointerUp] **for the cursor**.
  ///
  /// Rebindable like any action (`click.binding = const
  /// TriggerBinding(.rightMouseButton)`), which is what a left-handed
  /// settings screen needs - the picking has no opinion about which physical
  /// button it is. Contacts are not rebindable and do not need to be: a
  /// finger has one button.
  final click = Input.of(const TriggerBinding(.leftMouseButton));

  /// Everything pressing on the screen, which is what makes a tap pick.
  ///
  /// Public for the same reason [cursor] is: there is one screen, and
  /// `ContactBinding` refuses to be combined, so a system that wants the
  /// fingers reads this one rather than declaring a second list of the same
  /// contacts.
  final contacts = Input.of<PointerContacts>(const ContactBinding());

  /// The camera mapping this system inverts. Exposed so a caller can project
  /// its own points without resolving a second camera - it is refreshed at
  /// the top of every tick.
  ///
  /// It describes the cursor's view once a tick has finished, because the
  /// contact pass runs first and the cursor pass re-resolves it afterwards.
  final CameraProjection projection = CameraProjection();

  /// The cursor in world space, updated once per tick.
  ///
  /// One instance for the life of the system, mutated in place - the same
  /// contract (and the same reason) as `Input<Vector2>.value`. Copy it if you
  /// need to keep it.
  final Vector2 worldSpace = Vector2.zero();

  /// The entity currently under the cursor, or `null`. The enter/exit pair is
  /// simply this changing.
  ///
  /// Singular, and correctly so: hover belongs to the cursor and there is one
  /// cursor. The pressing half is per contact and keeps no such field, since
  /// a press goes to whatever is under that contact now.
  Entity? get hovered => _hovered;
  Entity? _hovered;

  final _pressables = Query.all(PointerReceiver, Collider2D, WorldTransform2D);
  final _hoverables = Query.all(HoverReceiver, Collider2D, WorldTransform2D);
  final _cameras = Query.all(Camera, WorldTransform2D);

  late final PointerPickEvent _event = PointerPickEvent._();

  /// After the transforms it hit-tests against - the same declaration
  /// `GameRenderer2D` makes, for the same reason.
  @override
  int compareTo(GameSystem other) => other is WorldTransformSystem ? 1 : 0;

  @override
  void onFixedUpdate() {
    final views = game.cameraViews;
    if (views.length == 0) return;
    _runContacts(views);
    _runCursor(views);
  }

  /// Dispatches every contact that began or ended this tick.
  ///
  /// A held contact dispatches nothing: there is no per-tick "still down on
  /// this" callback, which matches the cursor, where a drag with the button
  /// held across an entity fires nothing either. A game that wants a drag
  /// reads [contacts] itself.
  void _runContacts(CameraViewTable views) {
    final list = contacts.value;
    if (list.count == 0) return;
    // The view the last contact resolved, so a handful of fingers in one view
    // - which is every touch game - walks the camera query once instead of
    // once per finger. Identity, not equality: a `CameraView` is its own
    // identity in the table.
    CameraView? resolved;
    for (var i = 0; i < list.count; i++) {
      final contact = list[i];
      // A mouse press arrives as a contact *and* as a button bit, and the
      // cursor pass below dispatches the bit. Taking both fires one click
      // twice.
      if (contact.kind == ContactKind.mouse) continue;
      final phase = contact.phase;
      if (phase == PointerPhase.held) continue;

      // Where this contact is, not where the pointer block says the cursor
      // is. `Game.pointerView` answers for the cursor, and two fingers on two
      // views have two answers - so the address on the contact is the only
      // one that can be right for both.
      final view = game.viewOfContact(contact) ?? views[0];
      if (!identical(view, resolved)) {
        projection.resolve(_cameras, view);
        resolved = view;
      }
      final viewSpace = contact.viewSpace;
      final worldX = projection.viewToWorldX(viewSpace.x);
      final worldY = projection.viewToWorldY(viewSpace.y);
      final picked = _pick(_pressables, worldX, worldY);
      if (picked == null) continue;

      final screenSpace = contact.screenSpace;
      final event = _event
        ..entity = picked
        .._pointerId = contact.id
        .._kind = contact.kind
        .._cancelled = phase == PointerPhase.cancelled;
      event.screenSpace.setValues(screenSpace.x, screenSpace.y);
      event.viewSpace.setValues(viewSpace.x, viewSpace.y);
      event.worldSpace.setValues(worldX, worldY);

      final receiver = picked<PointerReceiver>().component;
      // A press and a lift that both land between two fixed ticks are
      // reported once, as ended - see `PointerContacts`. So a tap that fast
      // fires the release and never the press, which is where a real tap
      // gesture fires too.
      if (phase == PointerPhase.began) {
        receiver.onPointerDown(event);
      } else {
        receiver.onPointerUp(event);
      }
    }
  }

  /// Hover, and the cursor's half of press and release.
  void _runCursor(CameraViewTable views) {
    // The view the pointer is actually over, reported by the `GameView` that
    // received the event. That is what makes picking correct with several
    // views on screen - a click has to be projected through the camera whose
    // pixels it landed on, or it hits whatever a different camera is looking
    // at.
    //
    // Falls back to the first declared view when nothing named one: a
    // headless harness driving `movePointer` without a view, and every
    // single-view game, where the fallback and the answer are the same view.
    projection.resolve(_cameras, game.pointerView ?? views[0]);
    final position = cursor.value;
    worldSpace.setValues(
      projection.viewToWorldX(position.viewSpace.x),
      projection.viewToWorldY(position.viewSpace.y),
    );

    final hovering = _pick(_hoverables, worldSpace.x, worldSpace.y);
    final previous = _hovered;
    if (!identical(hovering, previous)) {
      // Exit before enter, so a handler that swaps a shared highlight sees
      // the two in the order that leaves it on the right entity.
      if (previous != null) {
        _fillFromCursor(previous, position);
        previous<HoverReceiver>().component.onHoverExit(_event);
      }
      _hovered = hovering;
      if (hovering != null) {
        _fillFromCursor(hovering, position);
        hovering<HoverReceiver>().component.onHoverEnter(_event);
      }
    }
    if (hovering != null) {
      _fillFromCursor(hovering, position);
      hovering<HoverReceiver>().component.onHover(_event);
    }

    // A second pick, off the pressable query rather than the hoverable one,
    // and only on the tick an edge lands - so the common tick pays one pick,
    // not two. A prefab may declare either mixin without the other, which is
    // what makes this a different question from the hover pick.
    final pressed = click.wasPressedThisFrame;
    final released = click.wasReleasedThisFrame;
    if (!pressed && !released) return;
    final target = _pick(_pressables, worldSpace.x, worldSpace.y);
    if (target == null) return;
    _fillFromCursor(target, position);
    final receiver = target<PointerReceiver>().component;
    // Press and release both go to whatever is under the cursor *now*. A
    // press that drifts off the entity before the button comes up therefore
    // fires no release on it - which is what makes dragging off a button a
    // cancel, the behaviour every OS button has.
    if (pressed) receiver.onPointerDown(_event);
    if (released) receiver.onPointerUp(_event);
  }

  /// Re-points the borrowed event at [entity], carrying the cursor.
  ///
  /// [ContactKind.mouse] and a zero id, because that is what the cursor is:
  /// the pointer block is written from `PointerDeviceKind.mouse` events only,
  /// and contact ids are positive so zero cannot collide with one.
  void _fillFromCursor(Entity entity, CursorPosition position) {
    final event = _event
      ..entity = entity
      .._pointerId = 0
      .._kind = ContactKind.mouse
      .._cancelled = false;
    event.screenSpace.setValues(position.screenSpace.x, position.screenSpace.y);
    event.viewSpace.setValues(position.viewSpace.x, position.viewSpace.y);
    event.worldSpace.setValues(worldSpace.x, worldSpace.y);
  }

  /// The topmost entity in [receivers] whose shapes cover ([x], [y]) in world
  /// space.
  ///
  /// [receivers] is the query for the mixin about to be dispatched, which is
  /// what keeps a hover-only entity from swallowing a press and a
  /// press-only one from blocking a highlight.
  ///
  /// # Two things keep this off the profile
  ///
  /// **Grouped.** A component instance belongs to an archetype, so
  /// `entity<WorldTransform2D>().component` hands back the same object for every
  /// row - a registry lookup per candidate for an answer that changes once
  /// per archetype. `groups()` resolves it once per archetype instead, which
  /// is what `docs/guide/performance.md` names as the fix for the single most
  /// common cost in this engine.
  ///
  /// **A bound before the exact test.** Inverting a transform is a `cos`, a
  /// `sin` and two divides, and testing every body of every candidate exactly
  /// pays that for the whole scene on every tick. [ColliderBody.boundCovers]
  /// answers "is the pointer anywhere near this" from one squared distance
  /// first, and it is a circle about the entity's origin because that is the
  /// bound that does not need the angle. So the trig and the exact tests are
  /// paid once per entity the pointer is actually close to, and not at all
  /// for the rest.
  Entity? _pick(Query receivers, double x, double y) {
    Entity? best;
    var bestZ = 0;
    // Grouped, so `WorldTransform2D`, `Collider2D`, its body list and
    // `Renderable2D` are resolved once per archetype instead of once per row.
    // Group order is archetype registration order, the same order `run()`
    // walked and the same order `GameRenderer2D` draws in - which is what the
    // equal-z tie-break below leans on.
    for (final group in receivers.groups()) {
      final world = group<WorldTransform2D>();
      final bodies = group<Collider2D>().bodies;
      // Not in the query - an invisible click zone is a receiver with no
      // sprites at all - so the optional spelling, once, and `_depthOf` is
      // told the answer instead of asking per hit.
      final renderable = group<Renderable2D?>();
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
        // How far the pointer is from the entity's origin, squared, in the
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
        // the pointer is near nothing almost every tick, and an entity it is
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
}

/// The prebuilt shortcut for the picking system, so a component never spells
/// out `getSystem<PointerPickingSystem>()` - the standing convention for this
/// engine's own built-in systems.
extension PointerPickingAccess on Component {
  PointerPickingSystem get pointerPicking => getSystem<PointerPickingSystem>();
}

/// [PointerPickingAccess], for a system instead of a component.
extension PointerPickingAccessForSystems on GameSystem {
  PointerPickingSystem get pointerPicking => getSystem<PointerPickingSystem>();
}
