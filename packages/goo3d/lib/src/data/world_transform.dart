import 'package:good/good.dart';

import 'package:goo3d/src/data/transform.dart';

/// An entity's resolved *world*-space transform - `Transform3D`'s own fields,
/// composed with every ancestor's, outermost last. Opt-in (mixed in alongside
/// `Transform3D`, not automatic): an entity that is always at the scene root
/// and never reparented has world == local by construction and does not need
/// the extra fields.
///
/// **Leaving it off is the cheaper choice for a static prop, and deliberately
/// so.** In 2D, requiring the world columns meant `WorldTransformSystem`
/// copied local to world for every sprite on every fixed step, and at 20k flat
/// sprites that copy was a third of the step. A prefab that is never parented
/// pays nothing here for the same reason.
///
/// Fields are read-only from every other system's perspective - only
/// [WorldTransform3DSystem] ever writes them, once per `FixedTickEvent`, the
/// same cadence local `Transform3D` fields themselves only ever change at.
/// Cached, not recomputed on every read: an unchanged subtree costs one flat
/// comparison per entity per tick, not a re-walk to the root.
///
/// `worldScaleX`/`worldScaleY`/`worldScaleZ` are composed by multiplying the
/// per-axis local scales up the chain, not by decomposing the true composed
/// affine matrix back into rotation and scale. Those agree exactly as long as
/// no ancestor combines rotation with non-uniform scale; if one does, the
/// composed shape is genuinely sheared and no rotation-plus-scale pair
/// describes it exactly - the same caveat Unity documents on
/// `Transform.lossyScale`, and the same one `WorldTransform2D` carries.
/// `worldX`/`worldY`/`worldZ` and the world quaternion have no such caveat
/// while scales are uniform, and the position is exact regardless.
mixin WorldTransform3D on Component {
  final worldX = Field.float64();
  final worldY = Field.float64();
  final worldZ = Field.float64();
  final worldScaleX = Field.float64(1);
  final worldScaleY = Field.float64(1);
  final worldScaleZ = Field.float64(1);
  final worldRotationX = Field.float64();
  final worldRotationY = Field.float64();
  final worldRotationZ = Field.float64();
  final worldRotationW = Field.float64(1);

  // Change-detection cache, packed into the same row - not meant to be read
  // by anything outside WorldTransform3DSystem. Defaulted to NaN so the very
  // first resolve for a freshly-spawned entity always sees "changed" (NaN
  // never compares equal to anything, including itself) without a separate
  // "have I ever run" flag.
  final _cachedOffsetX = Field.float64(double.nan);
  final _cachedOffsetY = Field.float64(double.nan);
  final _cachedOffsetZ = Field.float64(double.nan);
  final _cachedRotationX = Field.float64(double.nan);
  final _cachedRotationY = Field.float64(double.nan);
  final _cachedRotationZ = Field.float64(double.nan);
  final _cachedRotationW = Field.float64(double.nan);
  final _cachedScaleX = Field.float64(double.nan);
  final _cachedScaleY = Field.float64(double.nan);
  final _cachedScaleZ = Field.float64(double.nan);
  final _cachedParent = Field.optEntity();

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<WorldTransform3D>();
  }
}

/// Keeps every [WorldTransform3D] current, once per `FixedTickEvent`.
///
/// The 3D counterpart of `goo2d`'s `WorldTransformSystem`, and the same
/// machinery: it walks the hierarchy **top-down** through the intrusive
/// `Parent.firstChild`/`Child.nextSibling` list the kernel already maintains,
/// starting from roots (no parent, or no `Child` mixin at all) so a parent is
/// always resolved before its children read it. Each entity's "did anything
/// change" check is a handful of field comparisons against last tick's cached
/// values, not a walk back to the root, so an unchanged subtree is cheap to
/// skip past.
///
/// Ordering: any system reading `WorldTransform3D` should extend its own
/// `compareTo` to run after this one (`other is WorldTransform3DSystem ? 1 :
/// 0`). This system does not declare "I run first" unconditionally, because a
/// system with no opinion about ordering should not be silently forced to run
/// after this one just because this one has an opinion about everyone.
class WorldTransform3DSystem extends GameSystem
    with FixedTickable, EntitySpawnListener {
  /// Guards against a cycle in the parent chain.
  static const int maxHierarchyDepth = 64;

  late final Query _roots;

  /// Entities spawned since the last step.
  ///
  /// A spawner writes an entity's transform during the tick it creates it.
  /// Every read in the pass below serves the last **published** snapshot, so
  /// on that tick it cannot see those writes - it composes from whatever the
  /// row held before. On a page that has never published that is harmless,
  /// because the read falls through to the write slot; on a **recycled row**
  /// it is the previous occupant's transform, or zero, and the visible result
  /// in 2D was one frame of a sprite at the world origin.
  ///
  /// A row that is new cannot be detected through a published read - any flag
  /// you might check has the same staleness as the data - so the system has
  /// to be told out of band, which is what `EntitySpawnListener` is for.
  ///
  /// A set, and [_composeSpawned] still gets the spawn order it depends on: a
  /// `Set` literal is a `LinkedHashSet`, which iterates in insertion order. As
  /// a `List` it did keep that order, but [onEntityDespawned] then removed
  /// from it by scanning, for *every* despawn in the game - so a tick that
  /// spawned and destroyed the same thousands of parented entities, an
  /// explosion clearing a squad or a level unloading, was quadratic in how
  /// many.
  final Set<Entity> _spawned = <Entity>{};

  @override
  void onEntitySpawned(Entity entity) {
    // Cheap filter: only entities this system would compose at all. The
    // listener hears every spawn in the game.
    if (entity.tryGet<WorldTransform3D>() != null) _spawned.add(entity);
  }

  @override
  void onEntityDespawned(Entity entity) {
    // Spawned and destroyed within one tick - composing it afterwards would
    // write through a freed row. Unlike [onEntitySpawned] this does not
    // filter on [WorldTransform3D] first: with a constant-time removal, the
    // `tryGet` would cost more than the removal it guards. The emptiness test
    // is what a scene with no [WorldTransform3D] in it pays, which is every
    // despawn in such a game, and it is cheaper than hashing a handle that
    // cannot be in here.
    if (_spawned.isNotEmpty) _spawned.remove(entity);
  }

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    // withOptional(Child) because an entity is a root whether it never mixes
    // in Child at all, or mixes it in but happens to be unparented.
    _roots = descriptor
        .query()
        .withAll(WorldTransform3D, Transform3D)
        .withOptional(Child)
        .build();
  }

  @override
  void onFixedUpdate() {
    // Grouped rather than `run()`, and all four components resolved per group
    // rather than per entity: a component belongs to an archetype, so
    // `entity.tryGet<Child>()` returns the same object for every row in the
    // group, and `tryGet` is a registry lookup plus a runtime subtype test
    // against a type *variable*. Four of those per entity was the single
    // largest thing in the 2D system that produced no answer.
    for (final group in _roots.groups()) {
      // Guaranteed by the query's `withAll`, so `get` rather than `tryGet`.
      final local = group.get<Transform3D>();
      final world = group.get<WorldTransform3D>();
      final childLink = group.tryGet<Child>();
      final parentComp = group.tryGet<Parent>();
      if (parentComp == null) {
        _resolveChildless(group, local, world, childLink);
        continue;
      }
      for (final entity in group) {
        if (childLink != null && childLink.parent[entity] != null) {
          continue; // not a root - reached via its real root's recursion below
        }
        // Roots have no parent to compose with - the parentWorld* arguments
        // are unused whenever hasParent is false, so their value here does
        // not matter.
        _resolve(
          entity,
          local,
          world,
          childLink,
          parentComp,
          parentChanged: false,
          hasParent: false,
          parentWorldX: 0,
          parentWorldY: 0,
          parentWorldZ: 0,
          parentWorldRotationX: 0,
          parentWorldRotationY: 0,
          parentWorldRotationZ: 0,
          parentWorldRotationW: 1,
          parentWorldScaleX: 1,
          parentWorldScaleY: 1,
          parentWorldScaleZ: 1,
          depth: 0,
        );
      }
    }

    _composeSpawned();
  }

  /// Recomposes entities spawned this tick from their **pending** transform.
  ///
  /// Runs after the main pass and overwrites what it produced for these few
  /// entities - the pass composed them from a stale row, or never reached
  /// them at all, and could not have known better either way. Doing it here
  /// rather than branching inside the pass keeps the per-entity hot path
  /// exactly as it was: this costs nothing in a tick where nothing spawned.
  ///
  /// [DataPointer.readPending] is the write slot - the value the spawner just
  /// wrote. It is normally forbidden for a system to read uncommitted state,
  /// and this is the narrow exception that rule names: initialising something
  /// from a write made earlier in its own tick.
  ///
  /// A spawned *child* needs this as much as a root does: the main pass
  /// descends through `Parent.firstChild`, an ordinary published read, and
  /// the splice that put a freshly spawned entity into its parent's child
  /// list happened *this* tick, so the pass does not visit it at all.
  void _composeSpawned() {
    if (_spawned.isEmpty) return;
    // Spawn order, and that is load-bearing: a parent necessarily exists
    // before a child can name it, so a spawned parent always precedes its
    // spawned children here and has its own world transform written by the
    // time [_pendingWorldOf] reads it back below. A `Set` literal is a
    // `LinkedHashSet`, which iterates in insertion order, so that holds.
    for (final entity in _spawned) {
      final world = entity.tryGet<WorldTransform3D>();
      if (world == null) continue;
      _pendingWorldOf(entity, 0);
      world
        ..worldX[entity] = _outX
        ..worldY[entity] = _outY
        ..worldZ[entity] = _outZ
        ..worldScaleX[entity] = _outScaleX
        ..worldScaleY[entity] = _outScaleY
        ..worldScaleZ[entity] = _outScaleZ
        ..worldRotationX[entity] = _outRotationX
        ..worldRotationY[entity] = _outRotationY
        ..worldRotationZ[entity] = _outRotationZ
        ..worldRotationW[entity] = _outRotationW;
    }
    _spawned.clear();
  }

  // [_compose]'s and [_pendingWorldOf]'s result. Instance scratch rather than
  // a returned record or a temporary vector: ten doubles out of a method
  // called per entity per tick is ten allocations a tick otherwise, which the
  // no-allocation rule forbids on this path. Every caller copies them into
  // locals before doing anything that could overwrite them.
  double _outX = 0;
  double _outY = 0;
  double _outZ = 0;
  double _outRotationX = 0;
  double _outRotationY = 0;
  double _outRotationZ = 0;
  double _outRotationW = 1;
  double _outScaleX = 1;
  double _outScaleY = 1;
  double _outScaleZ = 1;

  /// One step of the composition: `world = parent * local`, into the `_out*`
  /// fields.
  ///
  /// The whole of the 3D hierarchy's maths, written once. Both callers go
  /// through it, because two spellings of one affine composition is how the
  /// two drift apart.
  ///
  ///  * Position: the local offset is scaled by the parent's world scale,
  ///    turned by the parent's world rotation, then moved to the parent's
  ///    world position.
  ///  * Rotation: the quaternion product, parent first.
  ///  * Scale: per axis, multiplied. See [WorldTransform3D] on when that is
  ///    an approximation.
  void _compose(
    double offsetX,
    double offsetY,
    double offsetZ,
    double rotationX,
    double rotationY,
    double rotationZ,
    double rotationW,
    double scaleX,
    double scaleY,
    double scaleZ,
    double parentX,
    double parentY,
    double parentZ,
    double parentRotationX,
    double parentRotationY,
    double parentRotationZ,
    double parentRotationW,
    double parentScaleX,
    double parentScaleY,
    double parentScaleZ,
  ) {
    final scaledX = offsetX * parentScaleX;
    final scaledY = offsetY * parentScaleY;
    final scaledZ = offsetZ * parentScaleZ;

    // v + 2 * (q.xyz x (q.xyz x v + q.w * v)) - rotating a vector by a
    // quaternion without building the matrix. Two cross products and no
    // temporaries beyond these six doubles.
    final tx = 2 * (parentRotationY * scaledZ - parentRotationZ * scaledY);
    final ty = 2 * (parentRotationZ * scaledX - parentRotationX * scaledZ);
    final tz = 2 * (parentRotationX * scaledY - parentRotationY * scaledX);
    final turnedX =
        scaledX +
        parentRotationW * tx +
        (parentRotationY * tz - parentRotationZ * ty);
    final turnedY =
        scaledY +
        parentRotationW * ty +
        (parentRotationZ * tx - parentRotationX * tz);
    final turnedZ =
        scaledZ +
        parentRotationW * tz +
        (parentRotationX * ty - parentRotationY * tx);

    _outX = parentX + turnedX;
    _outY = parentY + turnedY;
    _outZ = parentZ + turnedZ;

    _outRotationX =
        parentRotationW * rotationX +
        parentRotationX * rotationW +
        parentRotationY * rotationZ -
        parentRotationZ * rotationY;
    _outRotationY =
        parentRotationW * rotationY -
        parentRotationX * rotationZ +
        parentRotationY * rotationW +
        parentRotationZ * rotationX;
    _outRotationZ =
        parentRotationW * rotationZ +
        parentRotationX * rotationY -
        parentRotationY * rotationX +
        parentRotationZ * rotationW;
    _outRotationW =
        parentRotationW * rotationW -
        parentRotationX * rotationX -
        parentRotationY * rotationY -
        parentRotationZ * rotationZ;

    _outScaleX = parentScaleX * scaleX;
    _outScaleY = parentScaleY * scaleY;
    _outScaleZ = parentScaleZ * scaleZ;
  }

  /// Composes [entity]'s world transform from **pending** reads, into the
  /// `_out*` fields.
  ///
  /// Every read here is `readPending`, and it is safe for rows this tick
  /// never touched as well as rows it did: the pool starts each page's write
  /// slot as a copy of the last published one, so the write slot always holds
  /// the latest value. Which means this reads an ancestor's world transform
  /// correctly in all three cases that matter - composed by the main pass
  /// earlier this tick, skipped by it as unchanged, or written by an earlier
  /// iteration of [_composeSpawned].
  void _pendingWorldOf(Entity entity, int depth) {
    final local = entity.tryGet<Transform3D>();
    // A bare grouping node contributes identity, exactly as in [_resolve].
    final offsetX = local == null
        ? 0.0
        : local.transformOffsetX.readPending(entity);
    final offsetY = local == null
        ? 0.0
        : local.transformOffsetY.readPending(entity);
    final offsetZ = local == null
        ? 0.0
        : local.transformOffsetZ.readPending(entity);
    final rotationX = local == null
        ? 0.0
        : local.transformRotationX.readPending(entity);
    final rotationY = local == null
        ? 0.0
        : local.transformRotationY.readPending(entity);
    final rotationZ = local == null
        ? 0.0
        : local.transformRotationZ.readPending(entity);
    final rotationW = local == null
        ? 1.0
        : local.transformRotationW.readPending(entity);
    final scaleX = local == null
        ? 1.0
        : local.transformScaleX.readPending(entity);
    final scaleY = local == null
        ? 1.0
        : local.transformScaleY.readPending(entity);
    final scaleZ = local == null
        ? 1.0
        : local.transformScaleZ.readPending(entity);

    final childLink = entity.tryGet<Child>();
    final parent = childLink?.parent.readPending(entity);
    if (parent == null || depth >= maxHierarchyDepth) {
      assert(
        parent == null,
        'the parent chain above $entity is deeper than $maxHierarchyDepth, '
        'or contains a cycle. Composing it as a root rather than recursing '
        'forever - same policy as _resolve.',
      );
      _outX = offsetX;
      _outY = offsetY;
      _outZ = offsetZ;
      _outRotationX = rotationX;
      _outRotationY = rotationY;
      _outRotationZ = rotationZ;
      _outRotationW = rotationW;
      _outScaleX = scaleX;
      _outScaleY = scaleY;
      _outScaleZ = scaleZ;
      return;
    }

    final double parentX,
        parentY,
        parentZ,
        parentRotationX,
        parentRotationY,
        parentRotationZ,
        parentRotationW,
        parentScaleX,
        parentScaleY,
        parentScaleZ;
    final parentWorld = parent.tryGet<WorldTransform3D>();
    if (parentWorld != null) {
      parentX = parentWorld.worldX.readPending(parent);
      parentY = parentWorld.worldY.readPending(parent);
      parentZ = parentWorld.worldZ.readPending(parent);
      parentRotationX = parentWorld.worldRotationX.readPending(parent);
      parentRotationY = parentWorld.worldRotationY.readPending(parent);
      parentRotationZ = parentWorld.worldRotationZ.readPending(parent);
      parentRotationW = parentWorld.worldRotationW.readPending(parent);
      parentScaleX = parentWorld.worldScaleX.readPending(parent);
      parentScaleY = parentWorld.worldScaleY.readPending(parent);
      parentScaleZ = parentWorld.worldScaleZ.readPending(parent);
    } else {
      // An ancestor that opted out of `WorldTransform3D` has nowhere to have
      // stored one, so it gets recomposed here on the way past.
      _pendingWorldOf(parent, depth + 1);
      parentX = _outX;
      parentY = _outY;
      parentZ = _outZ;
      parentRotationX = _outRotationX;
      parentRotationY = _outRotationY;
      parentRotationZ = _outRotationZ;
      parentRotationW = _outRotationW;
      parentScaleX = _outScaleX;
      parentScaleY = _outScaleY;
      parentScaleZ = _outScaleZ;
    }

    _compose(
      offsetX,
      offsetY,
      offsetZ,
      rotationX,
      rotationY,
      rotationZ,
      rotationW,
      scaleX,
      scaleY,
      scaleZ,
      parentX,
      parentY,
      parentZ,
      parentRotationX,
      parentRotationY,
      parentRotationZ,
      parentRotationW,
      parentScaleX,
      parentScaleY,
      parentScaleZ,
    );
  }

  /// The whole pass for an archetype that has no [Parent] - so no entity in
  /// it can ever have a child, and its roots are the entire subtree they
  /// belong to. A flat field of props is exactly this, and so is every
  /// particle and projectile in most games.
  ///
  /// # Why it may skip the change-detection cache
  ///
  /// [_resolve]'s cache accesses buy one thing: not re-walking a subtree
  /// whose ancestors did not move. These entities have no subtree, and with
  /// no parent to compose with, `world` *is* `local`. Recomputing that is ten
  /// reads and ten writes, which is cheaper than deciding whether to.
  ///
  /// # Except for one write, which is not optional
  ///
  /// An archetype with [Child] but no [Parent] - a leaf that can be parented,
  /// which is the common shape - has *both* kinds of row: unparented ones
  /// this method handles, and parented ones [_resolve] reaches through their
  /// real root's recursion. A row can move between the two at runtime, and
  /// [_resolve] trusts its cache. Leaving the cache untouched here would
  /// leave a stale-but-self-consistent entry behind: parent a row, unparent
  /// it (this method overwrites `world` with the *local* transform and says
  /// nothing), then re-parent it to the same parent without touching its
  /// offsets, and [_resolve] would compare equal on every field, conclude
  /// nothing changed, and read back a `world` that was never composed.
  /// Clearing [WorldTransform3D._cachedParent] makes that impossible.
  void _resolveChildless(
    Iterable<Entity> group,
    Transform3D local,
    WorldTransform3D world,
    Child? childLink,
  ) {
    // Two loops rather than one with the null check inside: `childLink` is
    // fixed for the whole group, and an archetype that never mixes in `Child`
    // needs neither the root test nor the cache invalidation.
    if (childLink == null) {
      for (final entity in group) {
        _composeRoot(entity, local, world);
      }
      return;
    }
    for (final entity in group) {
      if (childLink.parent[entity] != null) {
        continue; // not a root - reached via its real root's recursion
      }
      _composeRoot(entity, local, world);
      world._cachedParent[entity] = null;
    }
  }

  /// `world = local`, which is the whole of a root's world transform.
  @pragma('vm:prefer-inline')
  void _composeRoot(Entity entity, Transform3D local, WorldTransform3D world) {
    world.worldX[entity] = local.transformOffsetX[entity];
    world.worldY[entity] = local.transformOffsetY[entity];
    world.worldZ[entity] = local.transformOffsetZ[entity];
    world.worldRotationX[entity] = local.transformRotationX[entity];
    world.worldRotationY[entity] = local.transformRotationY[entity];
    world.worldRotationZ[entity] = local.transformRotationZ[entity];
    world.worldRotationW[entity] = local.transformRotationW[entity];
    world.worldScaleX[entity] = local.transformScaleX[entity];
    world.worldScaleY[entity] = local.transformScaleY[entity];
    world.worldScaleZ[entity] = local.transformScaleZ[entity];
  }

  /// Resolves [entity] and recurses into its children.
  ///
  /// **Why the parent's world transform is passed in as plain arguments, not
  /// read back from `parentWorld.worldX[parent]` after writing it a few lines
  /// above**: this storage layer's reads always see the *last published*
  /// snapshot, never a write made earlier in the same tick. A parent resolved
  /// earlier in this top-down pass, this same tick, has a fresh value in the
  /// write slot that a same-tick read cannot see - reading it back would
  /// silently return last tick's stale value instead. Carrying the
  /// just-computed numbers down as parameters sidesteps the whole problem:
  /// nothing this method just wrote is ever read back within the same call
  /// tree.
  ///
  /// [local], [world], [childLink] and [parentComp] are [entity]'s
  /// archetype's components, resolved by the caller, because the caller
  /// usually already knows them for a whole group of rows at once. Each may
  /// be null: the recursion walks *every* child in the hierarchy, and a child
  /// need not have any of them.
  ///
  ///  * No [Transform3D]: a bare grouping node - Child/Parent links and
  ///    nothing else. It contributes identity and the walk steps over it,
  ///    rather than aborting and stranding its whole subtree at the origin.
  ///  * No [WorldTransform3D]: nothing to cache into, but its descendants may
  ///    still opt in, so the composed transform is threaded straight through
  ///    to them.
  ///
  /// The query only guarantees these for the *roots* it yields; from there on
  /// the parent/child links decide who gets visited, and they know nothing
  /// about component makeup.
  void _resolve(
    Entity entity,
    Transform3D? local,
    WorldTransform3D? world,
    Child? childLink,
    Parent? parentComp, {
    required bool parentChanged,
    required bool hasParent,
    required double parentWorldX,
    required double parentWorldY,
    required double parentWorldZ,
    required double parentWorldRotationX,
    required double parentWorldRotationY,
    required double parentWorldRotationZ,
    required double parentWorldRotationW,
    required double parentWorldScaleX,
    required double parentWorldScaleY,
    required double parentWorldScaleZ,
    required int depth,
  }) {
    if (depth > maxHierarchyDepth) {
      assert(
        false,
        'the parent chain above $entity is deeper than $maxHierarchyDepth, '
        'or contains a cycle. Leaving the rest of this subtree as-is rather '
        'than hanging the tick.',
      );
      return;
    }

    final parent = childLink?.parent[entity];

    final offsetX = local == null ? 0.0 : local.transformOffsetX[entity];
    final offsetY = local == null ? 0.0 : local.transformOffsetY[entity];
    final offsetZ = local == null ? 0.0 : local.transformOffsetZ[entity];
    final rotationX = local == null ? 0.0 : local.transformRotationX[entity];
    final rotationY = local == null ? 0.0 : local.transformRotationY[entity];
    final rotationZ = local == null ? 0.0 : local.transformRotationZ[entity];
    final rotationW = local == null ? 1.0 : local.transformRotationW[entity];
    final scaleX = local == null ? 1.0 : local.transformScaleX[entity];
    final scaleY = local == null ? 1.0 : local.transformScaleY[entity];
    final scaleZ = local == null ? 1.0 : local.transformScaleZ[entity];

    // Without somewhere to cache, there is no change to detect - such an
    // entity is recomposed every tick, which costs the arithmetic and nothing
    // else. `parentChanged` still has to propagate through it, so its
    // descendants that *do* cache invalidate correctly.
    final changed =
        world == null ||
        parentChanged ||
        world._cachedParent[entity] != parent ||
        world._cachedOffsetX[entity] != offsetX ||
        world._cachedOffsetY[entity] != offsetY ||
        world._cachedOffsetZ[entity] != offsetZ ||
        world._cachedRotationX[entity] != rotationX ||
        world._cachedRotationY[entity] != rotationY ||
        world._cachedRotationZ[entity] != rotationZ ||
        world._cachedRotationW[entity] != rotationW ||
        world._cachedScaleX[entity] != scaleX ||
        world._cachedScaleY[entity] != scaleY ||
        world._cachedScaleZ[entity] != scaleZ;

    // This entity's resolved world transform, as local variables - what gets
    // passed down to children as their parentWorld* arguments. Either freshly
    // computed below (changed) or read back from storage (not changed - safe
    // here specifically *because* nothing wrote to this entity's world fields
    // this tick in that branch, so the last-published value already is this
    // tick's correct value).
    double thisWorldX,
        thisWorldY,
        thisWorldZ,
        thisWorldRotationX,
        thisWorldRotationY,
        thisWorldRotationZ,
        thisWorldRotationW,
        thisWorldScaleX,
        thisWorldScaleY,
        thisWorldScaleZ;

    if (changed) {
      if (!hasParent) {
        thisWorldX = offsetX;
        thisWorldY = offsetY;
        thisWorldZ = offsetZ;
        thisWorldRotationX = rotationX;
        thisWorldRotationY = rotationY;
        thisWorldRotationZ = rotationZ;
        thisWorldRotationW = rotationW;
        thisWorldScaleX = scaleX;
        thisWorldScaleY = scaleY;
        thisWorldScaleZ = scaleZ;
      } else {
        _compose(
          offsetX,
          offsetY,
          offsetZ,
          rotationX,
          rotationY,
          rotationZ,
          rotationW,
          scaleX,
          scaleY,
          scaleZ,
          parentWorldX,
          parentWorldY,
          parentWorldZ,
          parentWorldRotationX,
          parentWorldRotationY,
          parentWorldRotationZ,
          parentWorldRotationW,
          parentWorldScaleX,
          parentWorldScaleY,
          parentWorldScaleZ,
        );
        // Copied out before the recursion below can overwrite the scratch.
        thisWorldX = _outX;
        thisWorldY = _outY;
        thisWorldZ = _outZ;
        thisWorldRotationX = _outRotationX;
        thisWorldRotationY = _outRotationY;
        thisWorldRotationZ = _outRotationZ;
        thisWorldRotationW = _outRotationW;
        thisWorldScaleX = _outScaleX;
        thisWorldScaleY = _outScaleY;
        thisWorldScaleZ = _outScaleZ;
      }
      // A grouping node with no WorldTransform3D has nowhere to store this -
      // it is composed purely to be handed down to its children below.
      if (world != null) {
        world.worldX[entity] = thisWorldX;
        world.worldY[entity] = thisWorldY;
        world.worldZ[entity] = thisWorldZ;
        world.worldRotationX[entity] = thisWorldRotationX;
        world.worldRotationY[entity] = thisWorldRotationY;
        world.worldRotationZ[entity] = thisWorldRotationZ;
        world.worldRotationW[entity] = thisWorldRotationW;
        world.worldScaleX[entity] = thisWorldScaleX;
        world.worldScaleY[entity] = thisWorldScaleY;
        world.worldScaleZ[entity] = thisWorldScaleZ;
        world._cachedParent[entity] = parent;
        world._cachedOffsetX[entity] = offsetX;
        world._cachedOffsetY[entity] = offsetY;
        world._cachedOffsetZ[entity] = offsetZ;
        world._cachedRotationX[entity] = rotationX;
        world._cachedRotationY[entity] = rotationY;
        world._cachedRotationZ[entity] = rotationZ;
        world._cachedRotationW[entity] = rotationW;
        world._cachedScaleX[entity] = scaleX;
        world._cachedScaleY[entity] = scaleY;
        world._cachedScaleZ[entity] = scaleZ;
      }
    } else {
      // `changed` is forced true when `world` is null, so reaching here means
      // there is a cache to read back.
      thisWorldX = world.worldX[entity];
      thisWorldY = world.worldY[entity];
      thisWorldZ = world.worldZ[entity];
      thisWorldRotationX = world.worldRotationX[entity];
      thisWorldRotationY = world.worldRotationY[entity];
      thisWorldRotationZ = world.worldRotationZ[entity];
      thisWorldRotationW = world.worldRotationW[entity];
      thisWorldScaleX = world.worldScaleX[entity];
      thisWorldScaleY = world.worldScaleY[entity];
      thisWorldScaleZ = world.worldScaleZ[entity];
    }

    // No `Parent` on this archetype means no entity in it has children, so
    // there is nothing below to walk - and for a flat scene that is every
    // entity, which is why this is the one early return worth having here.
    if (parentComp == null) return;
    var next = parentComp.firstChild[entity];
    while (next != null) {
      // Per child, because a child may be any archetype at all - this is the
      // lookup [onFixedUpdate] hoisted out of the *root* pass and the reason
      // it could not simply be hoisted out of this one too.
      _resolve(
        next,
        next.tryGet<Transform3D>(),
        next.tryGet<WorldTransform3D>(),
        next.tryGet<Child>(),
        next.tryGet<Parent>(),
        parentChanged: changed,
        hasParent: true,
        parentWorldX: thisWorldX,
        parentWorldY: thisWorldY,
        parentWorldZ: thisWorldZ,
        parentWorldRotationX: thisWorldRotationX,
        parentWorldRotationY: thisWorldRotationY,
        parentWorldRotationZ: thisWorldRotationZ,
        parentWorldRotationW: thisWorldRotationW,
        parentWorldScaleX: thisWorldScaleX,
        parentWorldScaleY: thisWorldScaleY,
        parentWorldScaleZ: thisWorldScaleZ,
        depth: depth + 1,
      );
      next = next.get<Child>().nextSibling[next];
    }
  }
}
