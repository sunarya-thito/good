
import 'package:goo/goo.dart';
/// One collider shape, plus the fields every shape shares (offset, enable,
/// trigger flag, layer mask). Not instantiated directly - a concrete
/// subtype ([CircleBody]/[BoxBody]/[CapsuleBody]/[PolygonBody]) is what
/// [ColliderDescriptor]'s `has*Collider` methods return, so a caller only
/// ever sees the fields the shape it asked for actually has - no dead
/// `halfWidth` on a circle, no branching on a shape-kind enum to know which
/// fields are live. `sealed` so a `switch` over a `ColliderBody` (a future
/// narrow-phase dispatch in Phase 2 physics) is exhaustiveness-checked by
/// the compiler.
///
/// `enable`/`isTrigger` are `DataPointer<int>` (0/1), not `DataPointer<bool>`
/// - this engine has no boolean field kind (see `Renderable2D.renderVisible`
/// for the same convention already in use), so booleans are represented as
/// a `uint1` throughout.
sealed class ColliderBody {
  ColliderBody({
    required this.offsetX,
    required this.offsetY,
    required this.enable,
    required this.isTrigger,
    required this.layer,
    required this.excludeLayers,
  });

  /// Local offset from the entity's `WorldTransform2D` origin.
  final DataPointer<double> offsetX;
  final DataPointer<double> offsetY;

  /// `0`/`1`. A disabled body still exists (its fields are still declared,
  /// still readable/writable) but should be skipped by anything that walks
  /// colliders looking for hits - the same "exists but inert" shape
  /// `Renderable2D.renderVisible` already uses for sprites.
  final DataPointer<int> enable;

  /// `0`/`1`. No physical response when set - only enter/exit/stay events,
  /// same body shape either way.
  final DataPointer<int> isTrigger;

  /// Bit index into a layer mask - which layer this body belongs to.
  final DataPointer<int> layer;

  /// Bitmask - which layers this body ignores.
  final DataPointer<int> excludeLayers;

  /// Whether this body, on [entity], covers the point ([x], [y]) given in
  /// the **entity's own local space** - the space the body's
  /// [offsetX]/[offsetY] are measured in, i.e. after the entity's world
  /// rotation, scale and translation have been undone.
  ///
  /// Local rather than world on purpose: undoing the transform is one
  /// trig-and-divide per *entity*, while a shape test is one per *body*, and
  /// an entity can carry several bodies. Taking a world point here would
  /// redo that work once per body and make each shape test carry a copy of
  /// the same inverse. `MousePickingSystem` is the worked example - it
  /// inverts once, then calls this for every body the entity declared.
  ///
  /// [enable] is deliberately *not* checked here: this answers a question
  /// about geometry, and whether a disabled body should be skipped is a
  /// policy its caller owns (picking skips them; a debug overlay drawing
  /// every declared shape would not).
  bool containsLocalPoint(Entity entity, double x, double y);

  // getContacts/getContactColliders (Unity's Collider2D surface) are
  // deliberately not declared here yet: they need a real broad/narrow-phase
  // structure to answer "what is this touching right now", which is Phase 2
  // (Box2D) scope. Declaring them now with an UnimplementedError body would
  // just be API surface that looks finished and isn't; they land with the
  // physics system that can actually back them.
}

final class CircleBody extends ColliderBody {
  CircleBody({
    required super.offsetX,
    required super.offsetY,
    required super.enable,
    required super.isTrigger,
    required super.layer,
    required super.excludeLayers,
    required this.radius,
  });

  final DataPointer<double> radius;

  @override
  bool containsLocalPoint(Entity entity, double x, double y) {
    final dx = x - offsetX[entity];
    final dy = y - offsetY[entity];
    final r = radius[entity];
    // Squared, so no sqrt on what is a per-body, per-tick test.
    return dx * dx + dy * dy <= r * r;
  }
}

final class BoxBody extends ColliderBody {
  BoxBody({
    required super.offsetX,
    required super.offsetY,
    required super.enable,
    required super.isTrigger,
    required super.layer,
    required super.excludeLayers,
    required this.halfWidth,
    required this.halfHeight,
  });

  final DataPointer<double> halfWidth;
  final DataPointer<double> halfHeight;

  @override
  bool containsLocalPoint(Entity entity, double x, double y) {
    final dx = x - offsetX[entity];
    if (dx < -halfWidth[entity] || dx > halfWidth[entity]) return false;
    final dy = y - offsetY[entity];
    return dy >= -halfHeight[entity] && dy <= halfHeight[entity];
  }
}

/// A capsule standing on its **y axis**: a rectangle of width `2 * radius`
/// with a semicircular cap of `radius` at each end.
///
/// [halfHeight] is half the *total* height, caps included - Unity's own
/// `CapsuleCollider2D.size` semantics, where the size is the capsule's
/// bounding box rather than the length of the straight section. So the
/// straight section runs `-(halfHeight - radius) .. +(halfHeight - radius)`,
/// and a capsule whose `halfHeight` is at most its `radius` is simply a
/// circle rather than an error - the degenerate case has an obvious right
/// answer, so it gets it instead of an assert.
final class CapsuleBody extends ColliderBody {
  CapsuleBody({
    required super.offsetX,
    required super.offsetY,
    required super.enable,
    required super.isTrigger,
    required super.layer,
    required super.excludeLayers,
    required this.radius,
    required this.halfHeight,
  });

  final DataPointer<double> radius;
  final DataPointer<double> halfHeight;

  @override
  bool containsLocalPoint(Entity entity, double x, double y) {
    final dx = x - offsetX[entity];
    var dy = y - offsetY[entity];
    final r = radius[entity];
    // The straight section's half-length. Negative when the capsule is
    // shorter than it is wide, which is the circle case - clamped to zero
    // rather than special-cased, since a segment of length zero *is* a
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
}

/// A polygon of up to [maxPoints] vertices, in local space relative to
/// [ColliderBody.offsetX]/[offsetY]. `pointCount` (0..`pointsX.length`) is
/// how many of the declared slots are actually in use per entity - the
/// polygon's real vertex count can vary per entity even though the storage
/// capacity is fixed per archetype (declared once, at `describeCollider`
/// time).
///
/// Points are two parallel `DataArrayPointer<double>` arrays (x, then y),
/// not a single array of some `Vector2`-shaped element - `goo2d` has no
/// vector-math dependency, matching `Transform2D`'s own established
/// convention of separate x/y `double` fields throughout this engine rather
/// than a point/vector type.
final class PolygonBody extends ColliderBody {
  PolygonBody({
    required super.offsetX,
    required super.offsetY,
    required super.enable,
    required super.isTrigger,
    required super.layer,
    required super.excludeLayers,
    required this.pointsX,
    required this.pointsY,
    required this.pointCount,
  });

  final DataArrayPointer<double> pointsX;
  final DataArrayPointer<double> pointsY;

  /// How many of `pointsX`/`pointsY`'s declared capacity are actually used
  /// for a given entity, `0..pointsX.length`. Defaults to `0` (an empty
  /// polygon) - `onMounted` (or `hasPolygonCollider`'s named defaults) is
  /// where a prefab actually populates the points and sets this.
  final DataPointer<int> pointCount;

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
      // Does this edge straddle the horizontal ray, and if so, does it cross
      // it to the right of the point? The asymmetric `>` / `<=` pair is what
      // makes a vertex exactly on the ray count once rather than twice.
      if ((iy > py) != (jy > py) &&
          px < (jx - ix) * (py - iy) / (jy - iy) + ix) {
        inside = !inside;
      }
      jx = ix;
      jy = iy;
    }
    return inside;
  }
}

/// Declares one entity's colliders. `Collider2D` (below) is a
/// `MultiComponent` - an entity can declare several bodies, one call per
/// `has*Collider` invocation, and a compound collider is simply calling
/// more than one of them, not a separate shape kind.
///
/// Every `has*Collider` method takes named parameters for every field its
/// returned body exposes, doubling as that archetype's default row state -
/// the standing `MultiComponent` convention (see `Renderable2D.Sprite`'s
/// `SpriteDescriptor.has` for the same shape) - so the common case needs no
/// separate `onMounted` write.
class ColliderDescriptor {
  ColliderDescriptor._(this._data, this._bodies);

  final DataDescriptor _data;
  final List<ColliderBody> _bodies;

  CircleBody hasCircleCollider({
    double radius = 0,
    double offsetX = 0,
    double offsetY = 0,
    bool enable = true,
    bool isTrigger = false,
    int layer = 0,
    int excludeLayers = 0,
  }) {
    final body = CircleBody(
      offsetX: _data.hasFloat64(offsetX),
      offsetY: _data.hasFloat64(offsetY),
      enable: _data.hasUint1(enable ? 1 : 0),
      isTrigger: _data.hasUint1(isTrigger ? 1 : 0),
      layer: _data.hasInt32(layer),
      excludeLayers: _data.hasInt32(excludeLayers),
      radius: _data.hasFloat64(radius),
    );
    _bodies.add(body);
    return body;
  }

  BoxBody hasBoxCollider({
    double halfWidth = 0,
    double halfHeight = 0,
    double offsetX = 0,
    double offsetY = 0,
    bool enable = true,
    bool isTrigger = false,
    int layer = 0,
    int excludeLayers = 0,
  }) {
    final body = BoxBody(
      offsetX: _data.hasFloat64(offsetX),
      offsetY: _data.hasFloat64(offsetY),
      enable: _data.hasUint1(enable ? 1 : 0),
      isTrigger: _data.hasUint1(isTrigger ? 1 : 0),
      layer: _data.hasInt32(layer),
      excludeLayers: _data.hasInt32(excludeLayers),
      halfWidth: _data.hasFloat64(halfWidth),
      halfHeight: _data.hasFloat64(halfHeight),
    );
    _bodies.add(body);
    return body;
  }

  CapsuleBody hasCapsuleCollider({
    double radius = 0,
    double halfHeight = 0,
    double offsetX = 0,
    double offsetY = 0,
    bool enable = true,
    bool isTrigger = false,
    int layer = 0,
    int excludeLayers = 0,
  }) {
    final body = CapsuleBody(
      offsetX: _data.hasFloat64(offsetX),
      offsetY: _data.hasFloat64(offsetY),
      enable: _data.hasUint1(enable ? 1 : 0),
      isTrigger: _data.hasUint1(isTrigger ? 1 : 0),
      layer: _data.hasInt32(layer),
      excludeLayers: _data.hasInt32(excludeLayers),
      radius: _data.hasFloat64(radius),
      halfHeight: _data.hasFloat64(halfHeight),
    );
    _bodies.add(body);
    return body;
  }

  /// [maxPoints] defaults to 8, matching Box2D's own hard cap on a single
  /// convex polygon (`b2_maxPolygonVertices`) - not an arbitrary number.
  /// Fixed per archetype at declare time; `pointCount` (per entity, at most
  /// [maxPoints]) is how many of those slots a given entity actually uses.
  PolygonBody hasPolygonCollider({
    int maxPoints = 8,
    double offsetX = 0,
    double offsetY = 0,
    bool enable = true,
    bool isTrigger = false,
    int layer = 0,
    int excludeLayers = 0,
  }) {
    final body = PolygonBody(
      offsetX: _data.hasFloat64(offsetX),
      offsetY: _data.hasFloat64(offsetY),
      enable: _data.hasUint1(enable ? 1 : 0),
      isTrigger: _data.hasUint1(isTrigger ? 1 : 0),
      layer: _data.hasInt32(layer),
      excludeLayers: _data.hasInt32(excludeLayers),
      pointsX: _data.hasFloat64Array(maxPoints),
      pointsY: _data.hasFloat64Array(maxPoints),
      pointCount: _data.hasInt32(0),
    );
    _bodies.add(body);
    return body;
  }
}

/// A `MultiComponent`: an entity can declare several bodies (a compound
/// collider is just calling `has*Collider` more than once), reached
/// generically via [bodies] by anything that needs to walk every collider
/// an entity has without knowing this prefab's own field names - the same
/// role `Renderable2D.sprites` plays for sprites.
mixin Collider2D on MultiComponent {
  /// Populated automatically as each `has*Collider` call inside
  /// [describeCollider] runs.
  final List<ColliderBody> bodies = [];

  /// Implemented by the concrete prefab - declares this entity type's
  /// colliders via the [ColliderDescriptor] passed in.
  void describeCollider(ColliderDescriptor descriptor);

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Collider2D>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    describeCollider(ColliderDescriptor._(data, bodies));
  }
}

/// One collider's involvement in a collision or trigger event - what a
/// [CollisionListener] method receives. `source`/`target` are the common
/// [ColliderBody] base type (a collision can involve any shape); cast to
/// the concrete subtype (`event.source as BoxBody`) for shape-specific
/// fields, or skip the cast entirely when the listener already knows the
/// concrete type of the body it declared (see `describeCollider`'s own
/// `late final BoxBody boxCollider` style fields).
class Collision2DEvent {
  const Collision2DEvent(this.source, this.sourceEntity, this.target, this.targetEntity);

  final ColliderBody source;
  final Entity sourceEntity;
  final ColliderBody target;
  final Entity targetEntity;
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
