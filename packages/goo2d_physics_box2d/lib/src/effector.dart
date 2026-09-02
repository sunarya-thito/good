import 'package:goo2d/goo2d.dart';

/// One declared effector: a region, and what it does to bodies inside it.
///
/// # Declared here, one-shot in `effectors.dart`
///
/// Those functions are the primitive and stay the primitive - a one-shot
/// explosion, or a region computed from gameplay state, has no entity to hang
/// off. What they are bad at is the *standing* case: a wind zone or a pool of
/// water is a thing in the level, and writing it as
/// `areaEffector(scene, -20, -20, 20, 0, forceX: 30)` from a hand-ordered
/// system means world-space constants a caller must recompute by hand the
/// moment the zone moves, plus a `compareTo` every game has to get right.
///
/// A declared effector puts the region on the entity's own [ColliderBody], so
/// it travels with the entity for free, and turns every knob into a per-entity
/// `DataPointer` instead of a call argument. `Box2DPhysicsSystem` walks these
/// itself, immediately before the step - a point that is already ordered
/// correctly - so the `compareTo` disappears.
///
/// This is Unity's model, reached for Unity's reason: an effector there is a
/// component beside a trigger collider, and the collider *is* the region.
///
/// `sealed` so the dispatch in the physics system is exhaustiveness-checked by
/// the compiler - the same reason [ColliderBody] is sealed.
sealed class Effector({
  /// The collider this effector acts through.
  ///
  /// A plain object reference, not a per-entity field: an archetype's
  /// effector always acts through the same declared body, and it is that
  /// body's *fields* that vary per entity. Resizing the region for one entity
  /// is therefore `region.halfWidth[entity] = 30`, one write, shared with the
  /// physics shape.
  ///
  /// Declare it `isTrigger: true` unless the region is meant to be solid too.
  /// Nothing here requires it, but a force field you can stand on is rarely
  /// what was meant.
  required final ColliderBody region,

  /// Off means skipped entirely - no query, no force.
  ///
  /// Takes effect on the **next** step, not the current one: the walk reads
  /// this through the published snapshot, like every other component read in
  /// this engine. Disabling a force field and seeing one more frame of force
  /// is the pipeline, not a bug.
  required final DataPointer<bool> enable,

  /// Which layers this affects, as a bit mask. -1 is everything.
  required final DataPointer<int> layerMask,
}) {
}

/// A uniform force on everything in the region - Unity's Area Effector 2D.
/// Wind, currents, updraughts.
///
/// The force is in world space, where +y is up, so an updraught is a positive
/// [forceY].
final class AreaEffector({
  required super.region,
  required super.enable,
  required super.layerMask,

  required final DataPointer<double> forceX,
  required final DataPointer<double> forceY,
  required final DataPointer<double> torque,
}) extends Effector {

  /// Declares a uniform-force effector on the prefab being constructed and
  /// returns the handle to keep in a field.
  ///
  /// ```dart
  /// class Updraught extends EntityStruct
  ///     with Transform2D, Collider2D, Effector2D {
  ///   final wind = AreaEffector.of(
  ///     BoxBody.of(halfWidth: 20, halfHeight: 10, isTrigger: true),
  ///     forceY: 30,
  ///   );
  /// }
  /// ```
  ///
  /// [region] is the collider this acts through, and it is normally declared
  /// inline: a field initialiser cannot read a sibling field, so the body and
  /// the effector are one expression and [Effector.region] is how the body is
  /// reached afterwards.
  ///
  /// Every other parameter is that archetype's declared row default. The
  /// prefab has to mix in [Effector2D], which is what takes the
  /// declaration.
  static AreaEffector of(
    ColliderBody region, {
    double forceX = 0,
    double forceY = 0,
    double torque = 0,
    bool enable = true,
    int layerMask = -1,
  }) => Component.declare(
    AreaEffector(
      region: region,
      enable: Field.boolean(enable),
      layerMask: Field.int32(layerMask),
      forceX: Field.float64(forceX),
      forceY: Field.float64(forceY),
      torque: Field.float64(torque),
    ),
  );
}

/// Attraction or repulsion about the region's centre - Unity's Point Effector
/// 2D. Negative [force] attracts, positive repels.
final class PointEffector({
  required super.region,
  required super.enable,
  required super.layerMask,

  required final DataPointer<double> force,

  /// Floor on the distance used in the falloff, so a body sitting exactly on
  /// the centre does not take an unbounded impulse.
  required final DataPointer<double> minDistance,
}) extends Effector {

  /// Declares an attract/repel effector on the prefab being constructed and
  /// returns the handle to keep in a field.
  ///
  /// ```dart
  /// class Magnet extends EntityStruct
  ///     with Transform2D, Collider2D, Effector2D {
  ///   final pull = PointEffector.of(
  ///     CircleBody.of(radius: 30, isTrigger: true),
  ///     force: -40,
  ///   );
  /// }
  /// ```
  ///
  /// [region] is the collider this acts through, and it is normally declared
  /// inline: a field initialiser cannot read a sibling field, so the body and
  /// the effector are one expression and [Effector.region] is how the body is
  /// reached afterwards.
  ///
  /// Every other parameter is that archetype's declared row default. The
  /// prefab has to mix in [Effector2D], which is what takes the
  /// declaration.
  static PointEffector of(
    ColliderBody region, {
    required double force,
    double minDistance = 0.5,
    bool enable = true,
    int layerMask = -1,
  }) => Component.declare(
    PointEffector(
      region: region,
      enable: Field.boolean(enable),
      layerMask: Field.int32(layerMask),
      force: Field.float64(force),
      minDistance: Field.float64(minDistance),
    ),
  );
}

/// Buoyancy and drag for bodies below the region's top edge - Unity's
/// Buoyancy Effector 2D.
///
/// **The water line is the region's top edge**, derived from the collider
/// instead of given as a number. That is the one place this abstraction fits
/// worse than the function it wraps: a rotated region still has a horizontal
/// surface, because a water line that tilts is not what anyone means by one.
final class BuoyancyEffector({
  required super.region,
  required super.enable,
  required super.layerMask,

  required final DataPointer<double> density,
  required final DataPointer<double> linearDrag,
  required final DataPointer<double> angularDrag,
}) extends Effector {

  /// Declares a buoyancy effector on the prefab being constructed and returns
  /// the handle to keep in a field.
  ///
  /// ```dart
  /// class Pool extends EntityStruct
  ///     with Transform2D, Collider2D, Effector2D {
  ///   final water = BuoyancyEffector.of(
  ///     BoxBody.of(halfWidth: 50, halfHeight: 10, isTrigger: true),
  ///     density: 3,
  ///   );
  /// }
  /// ```
  ///
  /// [region] is the collider this acts through, and it is normally declared
  /// inline: a field initialiser cannot read a sibling field, so the body and
  /// the effector are one expression and [Effector.region] is how the body is
  /// reached afterwards.
  ///
  /// Every other parameter is that archetype's declared row default. The
  /// prefab has to mix in [Effector2D], which is what takes the
  /// declaration.
  static BuoyancyEffector of(
    ColliderBody region, {
    double density = 2,
    double linearDrag = 1,
    double angularDrag = 1,
    bool enable = true,
    int layerMask = -1,
  }) => Component.declare(
    BuoyancyEffector(
      region: region,
      enable: Field.boolean(enable),
      layerMask: Field.int32(layerMask),
      density: Field.float64(density),
      linearDrag: Field.float64(linearDrag),
      angularDrag: Field.float64(angularDrag),
    ),
  );
}

/// A conveyor - everything in the region is pushed toward a target velocity.
/// Unity's Surface Effector 2D.
final class SurfaceEffector({
  required super.region,
  required super.enable,
  required super.layerMask,

  required final DataPointer<double> speed,
  required final DataPointer<double> speedY,
  required final DataPointer<double> force,
}) extends Effector {

  /// Declares a conveyor effector on the prefab being constructed and returns
  /// the handle to keep in a field.
  ///
  /// ```dart
  /// class Belt extends EntityStruct
  ///     with Transform2D, Collider2D, Effector2D {
  ///   final drive = SurfaceEffector.of(
  ///     BoxBody.of(halfWidth: 40, halfHeight: 2, isTrigger: true),
  ///     speed: 10,
  ///   );
  /// }
  /// ```
  ///
  /// [region] is the collider this acts through, and it is normally declared
  /// inline: a field initialiser cannot read a sibling field, so the body and
  /// the effector are one expression and [Effector.region] is how the body is
  /// reached afterwards.
  ///
  /// Every other parameter is that archetype's declared row default. The
  /// prefab has to mix in [Effector2D], which is what takes the
  /// declaration.
  static SurfaceEffector of(
    ColliderBody region, {
    required double speed,
    double speedY = 0,
    double force = 20,
    bool enable = true,
    int layerMask = -1,
  }) => Component.declare(
    SurfaceEffector(
      region: region,
      enable: Field.boolean(enable),
      layerMask: Field.int32(layerMask),
      speed: Field.float64(speed),
      speedY: Field.float64(speedY),
      force: Field.float64(force),
    ),
  );
}

/// Declares standing effectors on a prefab, beside the colliders they act
/// through.
///
/// A `MultiComponent` exactly like `Collider2D`, because one entity can carry
/// several - a pool that both floats things and pushes them along.
///
/// ```dart
/// class Updraught extends EntityStruct
///     with Transform2D, Collider2D, Effector2D {
///   final wind = AreaEffector.of(
///     BoxBody.of(halfWidth: 20, halfHeight: 10, isTrigger: true),
///     forceY: 30,
///   );
/// }
/// ```
///
/// The region is declared inline because a field initialiser cannot read a
/// sibling field. Reading it afterwards is `wind.region`, and a prefab that
/// wants the concrete type keeps a getter:
///
/// ```dart
/// BoxBody get region => wind.region as BoxBody;
/// ```
///
/// Changing it later is a per-entity write, like any other component field:
///
/// ```dart
/// scene.updraught.wind
///   ..enable[entity] = false
///   ..forceY[entity] = 45;
/// ```
mixin Effector2D on MultiComponent {
  /// Every `<Kind>Effector.of` the prefab declared, in declaration order.
  ///
  /// A mixin's field initialisers run after the applying class's, so this one
  /// runs once every effector on the prefab has been declared - see
  /// `MultiComponent`.
  final List<Effector> effectors = MultiComponent.declared<Effector>();

  final effector2DType = Component.type<Effector2D>();
}
