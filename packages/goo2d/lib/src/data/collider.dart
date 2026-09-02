import 'dart:math' as math;

import 'package:good/good.dart';

/// One collider shape, plus the fields every shape shares (offset, enable,
/// trigger flag, layer mask). Not instantiated directly - a concrete
/// subtype ([CircleBody]/[BoxBody]/[CapsuleBody]/[PolygonBody]) is declared
/// through its own `of`, so a caller only ever sees the fields the shape it
/// asked for actually has - no dead
/// `halfWidth` on a circle, no branching on a shape-kind enum to know which
/// fields are live. `sealed` so a `switch` over a `ColliderBody` (a future
/// narrow-phase dispatch in Phase 2 physics) is exhaustiveness-checked by
/// the compiler.
///
/// `enable`/`isTrigger` are `DataPointer<bool>`, stored as a `uint1` - see
/// `DataDescriptor.hasBool`.
sealed class ColliderBody({
  /// Local x offset from the entity's `WorldTransform2D` origin.
  required final DataPointer<double> offsetX,

  /// Local y offset from the entity's `WorldTransform2D` origin. Positive is
  /// up - see [containsLocalPoint].
  required final DataPointer<double> offsetY,

  // --- surface material ---------------------------------------------------
  //
  // On the base, not per shape, because every shape has all three, and a
  // physics backend needs all three for any of them. They live here and not
  // on a `RigidBody2D` because they are properties of a *shape*, not of a
  // body: a compound collider can legitimately have a low-friction ramp
  // and a high-friction pad on one entity.
  //
  // These are read by `goo2d_physics_box2d`, but they are declared here
  // because a collider without a material is not fully described - a debug
  // overlay or a custom backend wants them just as much, and putting them in
  // the physics package would mean two ways to describe one collider.

  /// Mass per unit area. A body's mass is the sum over its shapes, so a
  /// zero-density shape contributes none - which is how a dynamic body ends
  /// up with a collider that participates in collision but not in mass.
  required final DataPointer<double> density,

  /// Coulomb friction coefficient, `0` (frictionless) upward. Combined
  /// between two touching shapes by the physics backend, not by either
  /// shape alone.
  required final DataPointer<double> friction,

  /// Bounciness, `0` (inelastic) to `1` (no energy lost).
  required final DataPointer<double> restitution,

  /// Whether this body takes part in collision. Set it false and the body
  /// stays where it is - its fields are still declared, still readable and
  /// writable - while every pass that walks colliders looking for hits steps
  /// over it. `Sprite.visible` is the same "exists but inert" shape for
  /// sprites.
  required final DataPointer<bool> enable,

  /// Whether this body passes through what it touches. A trigger keeps the
  /// shape it was given and reports the same enter/exit/stay events; what it
  /// drops is the physical response.
  required final DataPointer<bool> isTrigger,

  /// Bit index into a layer mask - which layer this body belongs to.
  required final DataPointer<int> layer,

  /// Bitmask - which layers this body ignores.
  required final DataPointer<int> excludeLayers,
}) {

  /// Whether this body, on [entity], covers the point ([x], [y]) given in
  /// the **entity's own local space** - the space the body's
  /// [offsetX]/[offsetY] are measured in, i.e. after the entity's world
  /// rotation, scale and translation have been undone.
  ///
  /// That space is **y-up**, like world space: an [offsetY] of +5 puts the
  /// body 5 units *above* the entity's origin.
  ///
  /// A `Sprite`'s pivot agrees with it. The pivot's *fraction* is measured
  /// from the texture's top-left, because that is where a texture's own
  /// coordinates start - but moving a pivot down the texture lifts the drawn
  /// sprite off it, so a pivot `offsetY` of +5 and an [offsetY] of +5 each
  /// move their own side 5 units up. A collider covering an off-centre sprite
  /// takes the same sign, and the same number when the pivot was nudged with
  /// an offset. See `docs/guide/rendering.md` for the worked version.
  ///
  /// Local, and not world: undoing the transform is one trig-and-divide per
  /// *entity*, while a shape test is one per *body*, and an entity can carry
  /// several bodies. Taking a world point here would redo that work once per
  /// body and make each shape test carry a copy of the same inverse.
  /// `PointerPickingSystem` is the worked example - it inverts once, then calls
  /// this for every body the entity declared.
  ///
  /// [enable] is *not* checked here: this answers a question about geometry,
  /// and whether a disabled body should be skipped is a policy its caller
  /// owns (picking skips them; a debug overlay drawing every declared shape
  /// would not).
  bool containsLocalPoint(Entity entity, double x, double y);

  /// Whether a local point that far from the entity's origin could be inside
  /// this body at all - the cheap, conservative half of
  /// [containsLocalPoint].
  ///
  /// [distanceSquared] is a **squared** distance from local `(0, 0)`, and it
  /// may be a lower bound and not the exact one: a caller holding the
  /// cursor in world space can divide its squared world distance by the
  /// square of the entity's largest scale factor and pass that, which is
  /// what `PointerPickingSystem._pick` does. Rotation does not change a length
  /// and scaling stretches one by at most the larger factor, so that number
  /// never exceeds the real local distance - and a bound test fed something
  /// too small can only answer `true` too often.
  ///
  /// The point of it is what the caller does *not* have to do first: the
  /// exact test needs the cursor in local space, and getting it there costs a
  /// `cos` and a `sin`. This needs a subtraction, so a scene of receivers the
  /// cursor is nowhere near pays no trig at all.
  ///
  /// # Why a distance from the origin, and not from the body
  ///
  /// The origin is the point the entity's rotation turns about, so every
  /// point of the body stays the same distance from it however the entity is
  /// turned. A radius measured from there is therefore right at every angle
  /// and needs no angle to compute - the same reason `GameRenderer2D` culls
  /// sprites on a circle about the pivot instead of on a rectangle. A bound
  /// measured from the body's own [offsetX]/[offsetY] would be tighter and
  /// wrong: a body hung well off the origin swings a long way as the entity
  /// rotates, and a bound blind to that clips it.
  ///
  /// # It over-covers
  ///
  /// A circle around a box reaches past its corners, and `|offset| + reach`
  /// measures to the far side of the body, not to the far side of the
  /// *union* - both round outwards. Answering `true` too often costs the
  /// caller the exact test it was going to do anyway. Answering `false` too
  /// often would stop picking something the player clicked on, which reads as
  /// "the click did nothing" and not as a failure. So everything here
  /// rounds towards `true`, `NaN` included: each shape rejects on `>` and
  /// negates, so a `NaN` field - which loses every comparison - comes out as
  /// keep.
  ///
  /// A degenerate or negatively-sized body answers instead of throwing: the
  /// shape tests square their extents, so a negative radius already behaves
  /// as its magnitude, and a bound tighter than what [containsLocalPoint]
  /// accepts is the one thing this must never be.
  ///
  /// Returns a `bool` and not the radius itself, and that is a cost
  /// decision as much as an API one. This is called per body per candidate
  /// per tick through a virtual dispatch, and a `double` coming back out of
  /// one of those is a boxed `double` - an allocation on the tick path (the
  /// no-allocation rule), which measured as more than the trig the whole
  /// thing exists to skip.
  bool boundCovers(Entity entity, double distanceSquared);

  /// How far an ([x], [y]) offset puts a body from the entity's origin - the
  /// first term of every [boundCovers].
  ///
  /// `static`, taking two doubles, and not an instance method reading
  /// [offsetX]/[offsetY] itself. That is measurable: as an instance method it
  /// does not inline into the four overrides even under this pragma, and
  /// walking 20,000 receivers costs 5 ns each for the call. The zero case is
  /// carved out because it is the common one - a body declared with no offset
  /// at all - and a `sqrt` per body per tick is worth not taking when the
  /// answer is already known.
  @pragma('vm:prefer-inline')
  static double originDistance(double x, double y) =>
      x == 0 && y == 0 ? 0.0 : math.sqrt(x * x + y * y);

  // getContacts/getContactColliders (Unity's Collider2D surface) are not
  // declared here yet: they need a real broad/narrow-phase structure to
  // answer "what is this touching right now", which is Phase 2 (Box2D)
  // scope. Declaring them now with an UnimplementedError body would just be
  // API surface that looks finished and isn't; they land with the physics
  // system that can actually back them.
}

final class CircleBody({
  required super.offsetX,
  required super.offsetY,
  required super.enable,
  required super.isTrigger,
  required super.layer,
  required super.excludeLayers,
  required super.density,
  required super.friction,
  required super.restitution,

  required final DataPointer<double> radius,
}) extends ColliderBody {

  /// Declares a circle collider on the prefab being constructed and returns
  /// the handle to keep in a field.
  ///
  /// ```dart
  /// class Ball extends EntityStruct with Transform2D, Collider2D {
  ///   final hull = CircleBody.of(radius: 8);
  /// }
  /// ```
  ///
  /// Every parameter is that archetype's declared row default. The prefab has
  /// to mix in [Collider2D], which is what takes the declaration.
  static CircleBody of({
    double radius = 0,
    double offsetX = 0,
    double offsetY = 0,
    bool enable = true,
    bool isTrigger = false,
    int layer = 0,
    int excludeLayers = 0,
    double density = 1,
    double friction = 0.6,
    double restitution = 0,
  }) => Component.declare(
    CircleBody(
      offsetX: Field.float64(offsetX),
      offsetY: Field.float64(offsetY),
      enable: Field.boolean(enable),
      isTrigger: Field.boolean(isTrigger),
      layer: Field.int32(layer),
      excludeLayers: Field.int32(excludeLayers),
      density: Field.float64(density),
      friction: Field.float64(friction),
      restitution: Field.float64(restitution),
      radius: Field.float64(radius),
    ),
  );

  @override
  bool containsLocalPoint(Entity entity, double x, double y) {
    final dx = x - offsetX[entity];
    final dy = y - offsetY[entity];
    final r = radius[entity];
    // Squared, so no sqrt on what is a per-body, per-tick test.
    return dx * dx + dy * dy <= r * r;
  }

  /// The offset out, then the circle itself. `abs`, because the test above
  /// squares [radius] and so already treats a negative one as its magnitude.
  @override
  bool boundCovers(Entity entity, double distanceSquared) {
    final r = radius[entity];
    final away = ColliderBody.originDistance(offsetX[entity], offsetY[entity]);
    final reach = away + (r < 0 ? -r : r);
    return !(distanceSquared > reach * reach);
  }
}

final class BoxBody({
  required super.offsetX,
  required super.offsetY,
  required super.enable,
  required super.isTrigger,
  required super.layer,
  required super.excludeLayers,
  required super.density,
  required super.friction,
  required super.restitution,

  required final DataPointer<double> halfWidth,
  required final DataPointer<double> halfHeight,
}) extends ColliderBody {

  /// Declares an axis-aligned box collider on the prefab being constructed
  /// and returns the handle to keep in a field.
  ///
  /// ```dart
  /// class Crate extends EntityStruct with Transform2D, Collider2D {
  ///   final hull = BoxBody.of(halfWidth: 8, halfHeight: 8);
  /// }
  /// ```
  ///
  /// Every parameter is that archetype's declared row default. The prefab has
  /// to mix in [Collider2D], which is what takes the declaration.
  static BoxBody of({
    double halfWidth = 0,
    double halfHeight = 0,
    double offsetX = 0,
    double offsetY = 0,
    bool enable = true,
    bool isTrigger = false,
    int layer = 0,
    int excludeLayers = 0,
    double density = 1,
    double friction = 0.6,
    double restitution = 0,
  }) => Component.declare(
    BoxBody(
      offsetX: Field.float64(offsetX),
      offsetY: Field.float64(offsetY),
      enable: Field.boolean(enable),
      isTrigger: Field.boolean(isTrigger),
      layer: Field.int32(layer),
      excludeLayers: Field.int32(excludeLayers),
      density: Field.float64(density),
      friction: Field.float64(friction),
      restitution: Field.float64(restitution),
      halfWidth: Field.float64(halfWidth),
      halfHeight: Field.float64(halfHeight),
    ),
  );


  @override
  bool containsLocalPoint(Entity entity, double x, double y) {
    final dx = x - offsetX[entity];
    if (dx < -halfWidth[entity] || dx > halfWidth[entity]) return false;
    final dy = y - offsetY[entity];
    return dy >= -halfHeight[entity] && dy <= halfHeight[entity];
  }

  /// The offset out, then the half-diagonal - the corner is the furthest
  /// point of a rectangle from its own centre, whichever way it is turned.
  ///
  /// No `abs` on the halves: they are squared before the root, and a
  /// negative half makes [containsLocalPoint] reject everything, so a bound
  /// taken from the magnitude only over-covers.
  @override
  bool boundCovers(Entity entity, double distanceSquared) {
    final hw = halfWidth[entity];
    final hh = halfHeight[entity];
    final away = ColliderBody.originDistance(offsetX[entity], offsetY[entity]);
    final reach = away + math.sqrt(hw * hw + hh * hh);
    return !(distanceSquared > reach * reach);
  }
}

/// A capsule standing on its **y axis**: a rectangle of width `2 * radius`
/// with a semicircular cap of `radius` at each end.
///
/// [halfHeight] is half the *total* height, caps included - Unity's own
/// `CapsuleCollider2D.size` semantics, where the size is the capsule's
/// bounding box, not the length of the straight section. So the straight
/// section runs `-(halfHeight - radius) .. +(halfHeight - radius)`, and a
/// capsule whose `halfHeight` is at most its `radius` is simply a circle and
/// not an error - the degenerate case has an obvious right answer, so it gets
/// it instead of an assert.
final class CapsuleBody({
  required super.offsetX,
  required super.offsetY,
  required super.enable,
  required super.isTrigger,
  required super.layer,
  required super.excludeLayers,
  required super.density,
  required super.friction,
  required super.restitution,

  required final DataPointer<double> radius,
  required final DataPointer<double> halfHeight,
}) extends ColliderBody {

  /// Declares a capsule collider on the prefab being constructed and returns
  /// the handle to keep in a field.
  ///
  /// ```dart
  /// class Actor extends EntityStruct with Transform2D, Collider2D {
  ///   final hull = CapsuleBody.of(radius: 4, halfHeight: 12);
  /// }
  /// ```
  ///
  /// Every parameter is that archetype's declared row default. The prefab has
  /// to mix in [Collider2D], which is what takes the declaration.
  static CapsuleBody of({
    double radius = 0,
    double halfHeight = 0,
    double offsetX = 0,
    double offsetY = 0,
    bool enable = true,
    bool isTrigger = false,
    int layer = 0,
    int excludeLayers = 0,
    double density = 1,
    double friction = 0.6,
    double restitution = 0,
  }) => Component.declare(
    CapsuleBody(
      offsetX: Field.float64(offsetX),
      offsetY: Field.float64(offsetY),
      enable: Field.boolean(enable),
      isTrigger: Field.boolean(isTrigger),
      layer: Field.int32(layer),
      excludeLayers: Field.int32(excludeLayers),
      density: Field.float64(density),
      friction: Field.float64(friction),
      restitution: Field.float64(restitution),
      radius: Field.float64(radius),
      halfHeight: Field.float64(halfHeight),
    ),
  );


  @override
  bool containsLocalPoint(Entity entity, double x, double y) {
    final dx = x - offsetX[entity];
    var dy = y - offsetY[entity];
    final r = radius[entity];
    // The straight section's half-length. Negative when the capsule is
    // shorter than it is wide, which is the circle case - clamped to zero
    // instead of special-cased, since a segment of length zero *is* a
    // point and the test below then reads as a circle by itself.
    final half = halfHeight[entity] - r;
    final segment = half > 0 ? half : 0.0;
    // Distance to the segment: slide the point onto the nearest end cap's
    // centre, then it is a circle test against that centre.
    if (dy > segment) {
      dy -= segment;
    } else if (dy < -segment) {
      dy += segment;
    } else {
      dy = 0;
    }
    return dx * dx + dy * dy <= r * r;
  }

  /// The offset out, then the far cap: the straight section's half-length
  /// plus one radius, which is the furthest a capsule reaches from its own
  /// centre.
  ///
  /// `halfHeight - radius` is spelled the same way [containsLocalPoint]
  /// spells it, and it has to be: the two have to agree about where the caps
  /// sit, and a sign nobody expected (a negative [radius] pushes the caps
  /// *apart*) then moves both together instead of only the exact one. No
  /// `sqrt`: the capsule's axis is the y axis, so the furthest point is on it.
  @override
  bool boundCovers(Entity entity, double distanceSquared) {
    final r = radius[entity];
    final half = halfHeight[entity] - r;
    final segment = half > 0 ? half : 0.0;
    final away = ColliderBody.originDistance(offsetX[entity], offsetY[entity]);
    final reach = away + segment + (r < 0 ? -r : r);
    return !(distanceSquared > reach * reach);
  }
}

/// A polygon of up to [maxPoints] vertices, in local space relative to
/// [ColliderBody.offsetX]/[offsetY]. `pointCount` (0..`pointsX.length`) is
/// how many of the declared slots are actually in use per entity - the
/// polygon's real vertex count can vary per entity even though the storage
/// capacity is fixed per archetype (declared once, when the prefab is
/// constructed).
///
/// Points are two parallel `DataArrayPointer<double>` arrays (x, then y),
/// not a single array of some `Vector2`-shaped element - `goo2d` has no
/// vector-math dependency, matching `Transform2D`'s own established
/// convention of separate x/y `double` fields throughout this engine, never
/// a point/vector type.
final class PolygonBody({
  required super.offsetX,
  required super.offsetY,
  required super.enable,
  required super.isTrigger,
  required super.layer,
  required super.excludeLayers,
  required super.density,
  required super.friction,
  required super.restitution,

  required final DataArrayPointer<double> pointsX,
  required final DataArrayPointer<double> pointsY,

  /// How many of `pointsX`/`pointsY`'s declared capacity are actually used
  /// for a given entity, `0..pointsX.length`. Defaults to the number of
  /// points `hasPolygonCollider` was declared with, or to `0` (an empty
  /// polygon) for a prefab that declared none and populates its outline from
  /// `onEntityMounted` instead.
  required final DataPointer<int> pointCount,
}) extends ColliderBody {

  /// Declares a polygon collider on the prefab being constructed and returns
  /// the handle to keep in a field.
  ///
  /// ```dart
  /// class Ramp extends EntityStruct with Transform2D, Collider2D {
  ///   final hull = PolygonBody.of(points: [(0, 0), (10, 0), (10, 5)]);
  /// }
  /// ```
  ///
  /// [points] is the outline in local space, `(x, y)` per vertex, and it
  /// doubles as the archetype's default row state: every entity of this
  /// prefab starts with those vertices and `pointCount` set to
  /// `points.length`. Writing `pointsX`/`pointsY` per entity still gives an
  /// entity its own shape.
  ///
  /// [maxPoints] is the storage capacity, fixed per archetype at declare
  /// time, and defaults to `points.length` - or to 8 for a prefab that
  /// declares no outline. Reserving more than [points] fills leaves slots an
  /// entity can grow into, `pointCount` saying how many it currently uses.
  ///
  /// The default of 8 is Box2D's hard cap on a single convex polygon
  /// (`b2_maxPolygonVertices`). A larger capacity is allowed: containment
  /// here is even-odd crossing, which handles any outline, so a polygon used
  /// for picking is not bound by what a solver can simulate. A physics
  /// backend that cannot take the shape says so itself.
  ///
  /// An outline of one or two points is rejected: it encloses no area, so
  /// [PolygonBody.containsLocalPoint] and any solver alike read it as nothing
  /// at all.
  ///
  /// The prefab has to mix in [Collider2D], which is what takes the
  /// declaration.
  static PolygonBody of({
    List<(double, double)>? points,
    int? maxPoints,
    double offsetX = 0,
    double offsetY = 0,
    bool enable = true,
    bool isTrigger = false,
    int layer = 0,
    int excludeLayers = 0,
    double density = 1,
    double friction = 0.6,
    double restitution = 0,
  }) {
    final outline = points ?? const <(double, double)>[];
    if (points != null && outline.length < 3) {
      throw ArgumentError.value(
        points,
        'points',
        'a polygon needs at least three points',
      );
    }
    final capacity = maxPoints ?? (points == null ? 8 : outline.length);
    if (capacity < outline.length) {
      throw ArgumentError.value(
        capacity,
        'maxPoints',
        'must hold every declared point (${outline.length})',
      );
    }
    return Component.declare(
      PolygonBody(
        offsetX: Field.float64(offsetX),
        offsetY: Field.float64(offsetY),
        enable: Field.boolean(enable),
        isTrigger: Field.boolean(isTrigger),
        layer: Field.int32(layer),
        excludeLayers: Field.int32(excludeLayers),
        density: Field.float64(density),
        friction: Field.float64(friction),
        restitution: Field.float64(restitution),
        pointsX: Field.arrayOf(
          .float64,
          capacity,
          List<double>.generate(outline.length, (i) => outline[i].$1),
        ),
        pointsY: Field.arrayOf(
          .float64,
          capacity,
          List<double>.generate(outline.length, (i) => outline[i].$2),
        ),
        pointCount: Field.int32(outline.length),
      ),
    );
  }


  /// Even-odd (crossing-number) containment, which handles convex and
  /// concave polygons alike - Box2D's own shapes are convex, but nothing
  /// stops a prefab declaring a concave outline for picking, and a
  /// convex-only test would silently include the dents.
  ///
  /// A polygon of fewer than three points encloses no area and therefore
  /// contains nothing - including the default, empty polygon a prefab that
  /// forgot to populate its points leaves behind.
  @override
  bool containsLocalPoint(Entity entity, double x, double y) {
    final count = pointCount[entity];
    if (count < 3) return false;
    final px = x - offsetX[entity];
    final py = y - offsetY[entity];
    var inside = false;
    // `j` trails `i` by one, so each iteration considers the edge from the
    // previous vertex to this one, wrapping the last back to the first.
    var jx = pointsX.get(entity, count - 1);
    var jy = pointsY.get(entity, count - 1);
    for (var i = 0; i < count; i++) {
      final ix = pointsX.get(entity, i);
      final iy = pointsY.get(entity, i);
      // Whether this edge straddles the horizontal ray and, if it does,
      // whether it crosses to the right of the point. The asymmetric `>` /
      // `<=` pair is what makes a vertex exactly on the ray count once and
      // not twice.
      if ((iy > py) != (jy > py) &&
          px < (jx - ix) * (py - iy) / (jy - iy) + ix) {
        inside = !inside;
      }
      jx = ix;
      jy = iy;
    }
    return inside;
  }

  /// The offset out, then the vertex furthest from the outline's own centre.
  ///
  /// One `sqrt` for the whole outline instead of one per vertex, by keeping
  /// the running maximum squared - the vertex furthest in square is the
  /// vertex furthest.
  ///
  /// An outline of fewer than three points encloses no area, so nothing is
  /// near enough to be covered by it. This is the one shape whose bound costs
  /// the same order as its exact test, since both walk every vertex; what it
  /// saves is still the `cos`/`sin` the caller would otherwise have taken
  /// first.
  @override
  bool boundCovers(Entity entity, double distanceSquared) {
    final count = pointCount[entity];
    if (count < 3) return false;
    var furthest = 0.0;
    for (var i = 0; i < count; i++) {
      final px = pointsX.get(entity, i);
      final py = pointsY.get(entity, i);
      final squared = px * px + py * py;
      // Negated, not `squared > furthest`: the two differ only for `NaN`,
      // where every comparison is false and only this form lets it through
      // to poison the bound. A vertex that has gone wrong must keep the body,
      // not quietly shrink the circle around it.
      if (!(squared <= furthest)) furthest = squared;
    }
    final away = ColliderBody.originDistance(offsetX[entity], offsetY[entity]);
    final reach = away + math.sqrt(furthest);
    return !(distanceSquared > reach * reach);
  }
}

/// A `MultiComponent`: an entity can declare several bodies (a compound
/// collider is two `<Shape>Body.of` fields), reached
/// generically via [bodies] by anything that needs to walk every collider
/// an entity has without knowing this prefab's own field names - the same
/// role `Renderable2D.sprites` plays for sprites.
mixin Collider2D on MultiComponent {
  /// Every `<Shape>Body.of` the prefab declared, in declaration order.
  ///
  /// A mixin's field initialisers run after the applying class's, so this one
  /// runs once every body on the prefab has been declared - see
  /// `MultiComponent`.
  final List<ColliderBody> bodies = MultiComponent.declared<ColliderBody>();

  final collider2DType = Component.type<Collider2D>();
}

/// One collider's involvement in a collision or trigger event - what a
/// [CollisionListener] method receives. `source`/`target` are the common
/// [ColliderBody] base type (a collision can involve any shape); cast to
/// the concrete subtype (`event.source as BoxBody`) for shape-specific
/// fields, or skip the cast entirely when the listener already knows the
/// concrete type of the body it declared (`final hull = BoxBody.of(...)`
/// keeps the concrete type).
///
/// **A single instance is reused for every dispatch.** A physics step can
/// produce hundreds of contacts, and every framework event is hot path
/// (the hot-path rules), so allocating one of these per contact is
/// exactly the cost the rule forbids. `PointerPickingSystem` already
/// established the shape with its own reused `PointerPickEvent`.
///
/// The consequence for a listener: **do not keep this object.** Its fields
/// are overwritten before the next call. Read what you need during the
/// callback and store that instead - the `Entity` values are plain packed
/// ints and are safe to keep; the event wrapper around them is not.
class Collision2DEvent {
  /// Constructed by a physics backend, once, and reused for every dispatch.
  /// Game code never builds one.
  ///
  /// Not `@internal`: that annotation is package-scoped, and a backend
  /// (`goo2d_physics_box2d`) is a separate package that legitimately needs
  /// both this and [set]. The same "internal in spirit, not in annotation"
  /// call `RigidBody2D.bodyHandle` makes.
  Collision2DEvent();

  /// The collider this event is being reported *to*.
  late ColliderBody source;

  /// The entity [source] belongs to.
  late Entity sourceEntity;

  /// The other side.
  late ColliderBody target;

  /// The entity [target] belongs to.
  late Entity targetEntity;

  /// Repoints this instance at one collision. Called by the physics backend
  /// immediately before each dispatch; see [Collision2DEvent] on why this is
  /// not `@internal`.
  void set(
    ColliderBody source,
    Entity sourceEntity,
    ColliderBody target,
    Entity targetEntity,
  ) {
    this.source = source;
    this.sourceEntity = sourceEntity;
    this.target = target;
    this.targetEntity = targetEntity;
  }
}

/// No-op-default reaction surface for collision/trigger events - the same
/// "mixin implementing an interface with no-op defaults, override only
/// what you need" shape `LifecycleListener` already established elsewhere
/// in this engine. `on Component`, not `on MultiComponent`: this is the
/// *prefab's* reaction to events involving whichever `ColliderBody` it
/// declared through `Collider2D` - one set of six methods per prefab type,
/// independent of how many bodies that prefab declared.
///
/// Event names are Unity's own (`OnCollisionEnter2D` etc.), kept exactly.
mixin CollisionListener on Component {
  void onCollisionEnter2D(Collision2DEvent event) {}
  void onCollisionExit2D(Collision2DEvent event) {}
  void onCollisionStay2D(Collision2DEvent event) {}
  void onTriggerEnter2D(Collision2DEvent event) {}
  void onTriggerExit2D(Collision2DEvent event) {}
  void onTriggerStay2D(Collision2DEvent event) {}
}
