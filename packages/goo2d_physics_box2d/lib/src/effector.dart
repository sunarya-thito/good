import 'package:goo2d/goo2d.dart';
import 'package:meta/meta.dart';

/// One declared effector: a region, and what it does to bodies inside it.
///
/// # Why this exists alongside the functions in `effectors.dart`
///
/// Those functions are the primitive and stay the primitive - a one-shot
/// explosion, or a region computed from gameplay state, has no entity to hang
/// off. What they are bad at is the *standing* case: a wind zone or a pool of
/// water is a thing in the level, and writing it as
/// `areaEffector(-20, -20, 20, 0, forceX: 30)` from a hand-ordered system
/// means world-space constants a caller must recompute by hand the moment the
/// zone moves, plus a `compareTo` every game has to get right.
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
sealed class Effector {
  Effector({
    required this.region,
    required this.enable,
    required this.layerMask,
  });

  /// The collider this effector acts through.
  ///
  /// A plain object reference rather than a per-entity field: an archetype's
  /// effector always acts through the same declared body, and it is that
  /// body's *fields* that vary per entity. Resizing the region for one entity
  /// is therefore `region.halfWidth[entity] = 30`, one write, shared with the
  /// physics shape.
  ///
  /// Declare it `isTrigger: true` unless the region is meant to be solid too.
  /// Nothing here requires it, but a force field you can stand on is rarely
  /// what was meant.
  final ColliderBody region;

  /// Off means skipped entirely - no query, no force.
  ///
  /// Takes effect on the **next** step, not the current one: the walk reads
  /// this through the published snapshot, like every other component read in
  /// this engine. Disabling a force field and seeing one more frame of force
  /// is the pipeline, not a bug.
  final DataPointer<bool> enable;

  /// Which layers this affects, as a bit mask. -1 is everything.
  final DataPointer<int> layerMask;
}

/// A uniform force on everything in the region - Unity's Area Effector 2D.
/// Wind, currents, updraughts.
final class AreaEffector extends Effector {
  AreaEffector({
    required super.region,
    required super.enable,
    required super.layerMask,
    required this.forceX,
    required this.forceY,
    required this.torque,
  });

  final DataPointer<double> forceX;
  final DataPointer<double> forceY;
  final DataPointer<double> torque;
}

/// Attraction or repulsion about the region's centre - Unity's Point Effector
/// 2D. Negative [force] attracts, positive repels.
final class PointEffector extends Effector {
  PointEffector({
    required super.region,
    required super.enable,
    required super.layerMask,
    required this.force,
    required this.minDistance,
  });

  final DataPointer<double> force;

  /// Floor on the distance used in the falloff, so a body sitting exactly on
  /// the centre does not take an unbounded impulse.
  final DataPointer<double> minDistance;
}

/// Buoyancy and drag for bodies below the region's top edge - Unity's
/// Buoyancy Effector 2D.
///
/// **The water line is the region's top edge**, derived from the collider
/// rather than given as a number. That is the one place this abstraction fits
/// worse than the function it wraps: a rotated region still has a horizontal
/// surface, because a water line that tilts is not what anyone means by one.
final class BuoyancyEffector extends Effector {
  BuoyancyEffector({
    required super.region,
    required super.enable,
    required super.layerMask,
    required this.density,
    required this.linearDrag,
    required this.angularDrag,
  });

  final DataPointer<double> density;
  final DataPointer<double> linearDrag;
  final DataPointer<double> angularDrag;
}

/// A conveyor - everything in the region is pushed toward a target velocity.
/// Unity's Surface Effector 2D.
final class SurfaceEffector extends Effector {
  SurfaceEffector({
    required super.region,
    required super.enable,
    required super.layerMask,
    required this.speed,
    required this.speedY,
    required this.force,
  });

  final DataPointer<double> speed;
  final DataPointer<double> speedY;
  final DataPointer<double> force;
}

/// Declares one entity's effectors, mirroring `ColliderDescriptor`: the named
/// parameters double as that archetype's default row state, so the common case
/// needs no `onEntityMounted` write.
class EffectorDescriptor {
  EffectorDescriptor(this._data, this._effectors);

  final DataDescriptor _data;
  final List<Effector> _effectors;

  AreaEffector hasAreaEffector(
    ColliderBody region, {
    double forceX = 0,
    double forceY = 0,
    double torque = 0,
    bool enable = true,
    int layerMask = -1,
  }) {
    final effector = AreaEffector(
      region: region,
      enable: _data.hasBool(enable),
      layerMask: _data.hasInt32(layerMask),
      forceX: _data.hasFloat64(forceX),
      forceY: _data.hasFloat64(forceY),
      torque: _data.hasFloat64(torque),
    );
    _effectors.add(effector);
    return effector;
  }

  PointEffector hasPointEffector(
    ColliderBody region, {
    required double force,
    double minDistance = 0.5,
    bool enable = true,
    int layerMask = -1,
  }) {
    final effector = PointEffector(
      region: region,
      enable: _data.hasBool(enable),
      layerMask: _data.hasInt32(layerMask),
      force: _data.hasFloat64(force),
      minDistance: _data.hasFloat64(minDistance),
    );
    _effectors.add(effector);
    return effector;
  }

  BuoyancyEffector hasBuoyancyEffector(
    ColliderBody region, {
    double density = 2,
    double linearDrag = 1,
    double angularDrag = 1,
    bool enable = true,
    int layerMask = -1,
  }) {
    final effector = BuoyancyEffector(
      region: region,
      enable: _data.hasBool(enable),
      layerMask: _data.hasInt32(layerMask),
      density: _data.hasFloat64(density),
      linearDrag: _data.hasFloat64(linearDrag),
      angularDrag: _data.hasFloat64(angularDrag),
    );
    _effectors.add(effector);
    return effector;
  }

  SurfaceEffector hasSurfaceEffector(
    ColliderBody region, {
    required double speed,
    double speedY = 0,
    double force = 20,
    bool enable = true,
    int layerMask = -1,
  }) {
    final effector = SurfaceEffector(
      region: region,
      enable: _data.hasBool(enable),
      layerMask: _data.hasInt32(layerMask),
      speed: _data.hasFloat64(speed),
      speedY: _data.hasFloat64(speedY),
      force: _data.hasFloat64(force),
    );
    _effectors.add(effector);
    return effector;
  }
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
///   late final BoxBody region;
///   late final AreaEffector wind;
///
///   @override
///   void describeCollider(ColliderDescriptor descriptor) {
///     super.describeCollider(descriptor);
///     region = descriptor.hasBoxCollider(
///       halfWidth: 20,
///       halfHeight: 10,
///       isTrigger: true,
///     );
///   }
///
///   @override
///   void describeEffector(EffectorDescriptor descriptor) {
///     super.describeEffector(descriptor);
///     wind = descriptor.hasAreaEffector(region, forceY: -30);
///   }
/// }
/// ```
///
/// Changing it later is a per-entity write, like any other component field:
///
/// ```dart
/// scene.updraught.wind
///   ..enable[entity] = false
///   ..forceY[entity] = -45;
/// ```
mixin Effector2D on MultiComponent {
  /// Populated automatically as each `has*Effector` call runs.
  final List<Effector> effectors = [];

  /// Implemented by the concrete prefab.
  @mustCallSuper
  void describeEffector(EffectorDescriptor descriptor) {}

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Effector2D>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    describeEffector(EffectorDescriptor(data, effectors));
  }
}
