import 'package:goo2d/goo2d.dart';
import 'package:meta/meta.dart';

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
///
/// # Declared by the field that holds it
///
/// ```dart
/// class Updraught extends EntityStruct
///     with Transform2D, Collider2D, Effector2D {
///   final region = ColliderBody.box(
///     halfWidth: 20,
///     halfHeight: 10,
///     isTrigger: true,
///   );
///
///   late final wind = Effector.area(region: region, forceY: 30);
/// }
/// ```
///
/// `late final`, and that is the whole reason this could not be a field
/// before: [region] names a **sibling field**, an ordinary field initialiser
/// cannot reach `this`, and a field holding the result of a hook is the
/// double declaration this engine forbids. A `late final` initialiser runs on
/// first touch - which is the collector's read - so `region` is already
/// there, and the value is memoised, so the effector the columns are laid out
/// for is the effector the physics system walks. `#369` concluded the hook
/// was the answer; it was the answer to a problem `late final` removes.
///
/// The four factories live on the family's **root** and are named for the
/// variant: [area], [point], [buoyancy], [surface]. That is
/// `ColliderBody.box`'s shape, for `ColliderBody.box`'s reason - the set is
/// closed and `sealed`, so a reader sees all of it from one place - and each
/// returns its own concrete type, so `wind.forceY` is reachable and the
/// `switch` in the physics system still narrows.
///
/// A [CompositeDeclaration]: an effector is two shared columns plus whatever
/// its kind adds, all under the one name the field holds. [region] is **not**
/// among them - the body is declared by the field that holds *it*, and
/// listing it here would lay its columns out twice.
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
}) implements CompositeDeclaration {

  /// Declares a uniform force over [region] - wind, a current, an updraught.
  /// Keep it in a `late final` field beside the body it acts through; every
  /// named parameter doubles as that archetype's declared row default, so the
  /// common case needs no `onEntityMounted` write.
  ///
  /// ```dart
  /// late final wind = Effector.area(region: region, forceY: 30);
  /// ```
  static AreaEffector area({
    required ColliderBody region,
    double forceX = 0,
    double forceY = 0,
    double torque = 0,
    bool enable = true,
    int layerMask = -1,
  }) => AreaEffector(
    region: region,
    enable: Field.boolean(enable),
    layerMask: Field.int32(layerMask),
    forceX: Field.float64(forceX),
    forceY: Field.float64(forceY),
    torque: Field.float64(torque),
  );

  /// Declares attraction or repulsion about [region]'s centre. Negative
  /// [force] attracts, positive repels. See [area].
  static PointEffector point({
    required ColliderBody region,
    required double force,
    double minDistance = 0.5,
    bool enable = true,
    int layerMask = -1,
  }) => PointEffector(
    region: region,
    enable: Field.boolean(enable),
    layerMask: Field.int32(layerMask),
    force: Field.float64(force),
    minDistance: Field.float64(minDistance),
  );

  /// Declares buoyancy and drag below [region]'s top edge. See [area], and
  /// [BuoyancyEffector] for what the water line is measured from.
  static BuoyancyEffector buoyancy({
    required ColliderBody region,
    double density = 2,
    double linearDrag = 1,
    double angularDrag = 1,
    bool enable = true,
    int layerMask = -1,
  }) => BuoyancyEffector(
    region: region,
    enable: Field.boolean(enable),
    layerMask: Field.int32(layerMask),
    density: Field.float64(density),
    linearDrag: Field.float64(linearDrag),
    angularDrag: Field.float64(angularDrag),
  );

  /// Declares a conveyor over [region] - everything inside is pushed toward
  /// [speed]. See [area].
  static SurfaceEffector surface({
    required ColliderBody region,
    required double speed,
    double speedY = 0,
    double force = 20,
    bool enable = true,
    int layerMask = -1,
  }) => SurfaceEffector(
    region: region,
    enable: Field.boolean(enable),
    layerMask: Field.int32(layerMask),
    speed: Field.float64(speed),
    speedY: Field.float64(speedY),
    force: Field.float64(force),
  );

  /// The two columns every effector has, then [effectorDeclarations] - in the
  /// order each factory builds them, which is the order they take in the row.
  ///
  /// [region] is absent on purpose: the body is a sibling field's
  /// declaration, and a composite that repeated it would reserve its columns
  /// a second time.
  ///
  /// Walked once, while the scene lays the archetype out, and never on a tick
  /// path.
  @override
  Iterable<ScannableField> get composedDeclarations => <ScannableField>[
    enable,
    layerMask,
    ...effectorDeclarations,
  ];

  /// The columns this kind adds on top of the two shared ones.
  ///
  /// Declared here rather than each subtype overriding [composedDeclarations]
  /// outright, so the shared two cannot come out in a different order for one
  /// kind than for another - a row's field order is its layout, and four
  /// copies of one list is four chances to disagree. [ColliderBody] splits
  /// for the same reason.
  @protected
  Iterable<ScannableField> get effectorDeclarations;
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
  @override
  Iterable<ScannableField> get effectorDeclarations =>
      <ScannableField>[forceX, forceY, torque];
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
  @override
  Iterable<ScannableField> get effectorDeclarations =>
      <ScannableField>[force, minDistance];
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
  @override
  Iterable<ScannableField> get effectorDeclarations =>
      <ScannableField>[density, linearDrag, angularDrag];
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
  @override
  Iterable<ScannableField> get effectorDeclarations =>
      <ScannableField>[speed, speedY, force];
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
///   final region = ColliderBody.box(
///     halfWidth: 20,
///     halfHeight: 10,
///     isTrigger: true,
///   );
///
///   late final wind = Effector.area(region: region, forceY: 30);
/// }
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
  /// Every [Effector] this prefab declared, in the order it declared them.
  ///
  /// Filled in [describeStruct] from the prefab's own declarations, so an
  /// effector reaches the physics system by being held by a field and by
  /// nothing else - there is no register call to forget. `Collider2D.bodies`
  /// is the same list for the same reason.
  final List<Effector> effectors = [];

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Effector2D>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    // Read off the constructed prefab, not handed in - the same generated
    // collector the scene walked a moment ago to lay these columns out, so
    // the two cannot disagree about which effectors there are or in what
    // order. Nothing takes `data`: the columns were reserved during that
    // walk, where each field sits in the row.
    final declarations = collectDeclarations(this);
    effectors.addAll(declarations.whereType<Effector>());
    if (effectors.isEmpty) return;
    // An effector acts *through* a body, and reaching one this prefab never
    // declared is the one way the field form can go wrong that the hook
    // could not: `Effector.area(region: ColliderBody.box(...))` reads
    // perfectly well and declares a body no field holds, so its columns are
    // never laid out and the physics walk reads a column that was never
    // given row space. Named here, where the prefab and its declarations are
    // both in hand, rather than at the first step.
    final declared = declarations.whereType<ColliderBody>().toList();
    for (final effector in effectors) {
      if (declared.any((body) => identical(body, effector.region))) continue;
      throw StateError(
        '$runtimeType declares a ${effector.runtimeType} whose region is not '
        'one of its own declared bodies. An effector acts through a body the '
        'same prefab declares - keep the body in its own field and name that '
        'field: `final region = ColliderBody.box(...);` then `late final '
        'wind = Effector.area(region: region);`. A body built inside the '
        'effector call is held by no field, so no collector reads it, no '
        'column is laid out for it, and nothing would read it back.',
      );
    }
  }
}
