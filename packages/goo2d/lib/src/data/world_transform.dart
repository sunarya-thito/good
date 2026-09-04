import 'dart:math' as math;

import 'package:good/good.dart';
import 'package:meta/meta.dart';

import 'package:goo2d/src/data/transform.dart';

/// An entity's resolved *world*-space transform - `Transform2D`'s own
/// fields, composed with every ancestor's, outermost last. Opt-in
/// (mixed in alongside `Transform2D`, not automatic): an entity that is
/// always at the scene root and never reparented has world == local by
/// construction and does not need the extra fields.
///
/// Fields are read-only from every other system's perspective - only
/// [WorldTransformSystem] ever writes them, once per fixed tick, the
/// same cadence local `Transform2D` fields themselves only ever change at.
/// Cached, not recomputed on every read: an unchanged subtree costs one
/// flat comparison per entity per tick, not a re-walk to the root - see
/// [WorldTransformSystem]'s own doc for the mechanism.
///
/// `worldRotation`/`worldScaleX`/`worldScaleY` are composed by accumulating
/// the *scalar* local values up the chain (rotation summed, scale
/// multiplied), not by decomposing the true composed affine matrix back
/// into rotation+scale. Those agree exactly as long as no ancestor combines
/// rotation with non-uniform scale (`scaleX != scaleY`); if one does, the
/// composed shape is genuinely sheared and no single rotation+scale pair
/// describes it exactly - the same caveat Unity documents on
/// `Transform.lossyScale`. `worldX`/`worldY` have no such caveat: they are
/// the exact result of transforming the origin through the real composed
/// affine chain.
mixin WorldTransform2D on Component {
  final worldX = Field.float64();
  final worldY = Field.float64();
  final worldScaleX = Field.float64(1);
  final worldScaleY = Field.float64(1);
  final worldRotation = Field.float64();

  // Change-detection cache, packed into the same row - not meant to be read
  // by anything outside WorldTransformSystem. Defaulted to NaN (offsets/
  // rotation) so the very first resolve for a freshly-spawned entity always
  // sees "changed" (NaN never compares equal to anything, including
  // itself) without a separate "have I ever run" flag.
  //
  // Public with `@internal` because a column has to be named to be collected,
  // and the collector for a struct mixing this in is generated into that
  // struct's own library. Private, these six reached no collector, so they
  // were absent from the row and every read below addressed a column that was
  // never reserved.
  @internal
  final worldCachedOffsetX = Field.float64(double.nan);
  @internal
  final worldCachedOffsetY = Field.float64(double.nan);
  @internal
  final worldCachedRotation = Field.float64(double.nan);
  @internal
  final worldCachedScaleX = Field.float64(double.nan);
  @internal
  final worldCachedScaleY = Field.float64(double.nan);
  @internal
  final worldCachedParent = Field.optEntity();

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<WorldTransform2D>();
  }
}

/// Keeps every [WorldTransform2D] current, once per fixed tick.
///
/// Walks the hierarchy **top-down** using the intrusive
/// `Parent.parentFirstChild`/`Child.childNextSibling` linked list
/// `data/hierarchy.dart` already maintains - no separate adjacency
/// structure needed - starting from roots (no parent,
/// or no `Child` mixin at all) so a parent's world transform is always
/// resolved before its children read it. Each entity's "did anything
/// change" check is a handful of field comparisons against last tick's
/// cached values, not a walk back to the root, so an unchanged subtree is
/// cheap to skip past.
///
/// Ordering: any system reading `WorldTransform2D` should extend its own
/// `compareTo` to run after this one (`other is WorldTransformSystem ? 1 :
/// 0`), and any system *writing* a `Transform2D` this pass then composes
/// should declare -1 against it. This system states no opinion of its own: a
/// system with no view about ordering should not be forced behind this one
/// just because this one has a view about everyone.
///
/// That the constraint is one-sided is fine - `GameState.sortSystems` asks
/// both directions and treats the answer as a graph edge, so a single -1 from
/// the other side is honoured. Sort the systems with `List.sort` instead and
/// it is not: `CritterSystem`'s -1 goes missing among unrelated systems'
/// contradictory opinions, this pass runs *before* its spawner, and every new
/// entity is composed a tick late. That was #5, the one-frame sprite at the
/// world origin, and `goo2d/example/test/swarm_origin_flash_test.dart` pins
/// it.
class WorldTransformSystem extends GameSystem
    with FixedTickable, EntitySpawnListener {
  /// Guards against a cycle in the parent chain, matching
  /// `GameRenderer2D.maxHierarchyDepth`'s reasoning.
  static const int maxHierarchyDepth = 64;

  // withOptional(Child) because an entity is a root whether it never mixes
  // in Child at all, or mixes it in but happens to be unparented.
  @internal
  final roots = Query.where()
      .withAll(WorldTransform2D, Transform2D)
      .withOptional(Child)
      .build();

  /// Entities spawned since the last step.
  ///
  /// # Why this set exists at all
  ///
  /// A spawner writes an entity's transform during the tick it creates it.
  /// Every read in the pass below serves the last **published** snapshot, so
  /// on that tick it cannot see those writes - it composes from whatever the
  /// row held before. On a page that has never published that is harmless,
  /// because `MemoryPage.resolveRow` falls through to the write slot; on a
  /// **recycled row** it is the previous occupant's transform, or zero.
  ///
  /// The visible result was one frame of a sprite at the world origin, seen
  /// while dragging the population slider in the hierarchy demo - where
  /// entities are spawned and destroyed constantly, so rows are always
  /// recycled. It is invisible in a scene that only ever grows.
  ///
  /// **A row that is new cannot be detected through a published read** - any
  /// flag you might check has the same staleness as the data. So the system
  /// has to be *told*, out of band, which is what `EntitySpawnListener` is
  /// for. This is the same shape that fixed body creation in the Box2D
  /// backend, for the same underlying reason.
  ///
  /// # Why a set, when [_composeSpawned] needs spawn order
  ///
  /// It is both. A `Set` literal is a `LinkedHashSet`, which iterates in
  /// insertion order, so [_composeSpawned] still gets spawn order - and
  /// [onEntityDespawned] removes in constant time. A `List` scans instead,
  /// for *every* despawn in the game, so a tick that spawns and destroys the
  /// same thousands of parented entities - an explosion clearing a squad, a
  /// level unloading - is quadratic in the number of them.
  final Set<Entity> _spawned = <Entity>{};

  @override
  void onEntitySpawned(Entity entity) {
    // Cheap filter: only entities this system would compose at all. The
    // listener hears every spawn in the game.
    if (entity.has<WorldTransform2D>()) _spawned.add(entity);
  }

  @override
  void onEntityDespawned(Entity entity) {
    // Spawned and destroyed within one tick - composing it afterwards would
    // write through a freed row. The emptiness test is what a scene with no
    // [WorldTransform2D] in it pays, which is every despawn in such a game:
    // cheaper than hashing a handle that cannot be in here.
    if (_spawned.isNotEmpty) _spawned.remove(entity);
  }

  @override
  void onFixedUpdate() {
    // Grouped, not `run()`, and **all four components resolved per group,
    // not per entity**. A component belongs to an archetype, so
    // `entity<Child>().component` hands back the same object for every row in
    // the group - and each resolve is a registry lookup plus an `is T` against
    // a type *variable*, which is a runtime subtype test and not a compare.
    // Four of those per entity, on the system that owns two thirds of the
    // fixed step at 20k entities, is the single largest thing in it that
    // produces no answer.
    //
    // The recursion below still resolves per entity, and has to: a child may
    // be a different archetype entirely. That is the right split - a flat
    // scene, which is the overwhelmingly common one, pays nothing for the
    // hierarchy case it is not using.
    for (final group in roots.groups()) {
      // Guaranteed by the query's `withAll`, so `Transform2D` and not
      // `Transform2D?`.
      final local = group<Transform2D>();
      final world = group<WorldTransform2D>();
      final childLink = group<Child?>();
      final parentComp = group<Parent?>();
      if (parentComp == null) {
        _resolveChildless(group, local, world, childLink);
        continue;
      }
      for (final entity in group) {
        if (childLink != null && childLink.childParent[entity] != null) {
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
          parentWorldRotation: 0,
          parentWorldScaleX: 1,
          parentWorldScaleY: 1,
          depth: 0,
        );
      }
    }

    _composeSpawned();
  }

  /// Recomposes entities spawned this tick from their **pending** transform.
  ///
  /// Runs after the main pass and overwrites what it produced for these few
  /// entities - the pass composed them from a stale row, or never reached them
  /// at all, and could not have known better either way. Doing it here instead
  /// of branching inside the pass leaves the per-entity hot path untouched:
  /// this costs nothing at all in a tick where nothing spawned.
  ///
  /// [DataPointer.readPending] is the write slot - the value the spawner just
  /// wrote. It is normally forbidden for a system to read uncommitted state,
  /// and this is the narrow exception that rule names: initialising something
  /// from a write made earlier in its own tick.
  ///
  /// # Why a spawned *child* needs this just as much as a root
  ///
  /// The main pass does not reach a spawned child. It descends through
  /// `Parent.parentFirstChild`, an ordinary published read, and the splice
  /// that put this entity into its parent's child list happened *this* tick.
  /// So a spawned child is not visited at all on its spawn tick, and its world
  /// row publishes holding whatever it held before - the defaults `(0, 0)` for
  /// a row never used, which is the sprite at the world origin.
  ///
  /// Which of three row states a spawn lands in decides whether you see that
  /// at all, so without this it is maddening to reproduce. A *recycled* row
  /// holds the previous occupant's position, which is somewhere plausible in
  /// the swarm and invisible. A row on a page that has never published reads
  /// through to the write slot and is simply correct. Only a new row on a
  /// page that *has* published shows anything, and that comes up only while
  /// the population is growing onto fresh rows: never at the start, never
  /// once it settles, and at no repeatable point in between.
  void _composeSpawned() {
    if (_spawned.isEmpty) return;
    // Spawn order, and that is load-bearing: a parent necessarily exists
    // before a child can name it, so a spawned parent always precedes its
    // spawned children here and has its own world transform written by the
    // time [_pendingWorldOf] reads it back below. A `Set` literal is a
    // `LinkedHashSet`, which iterates in insertion order, so that holds.
    for (final entity in _spawned) {
      if (!entity.has<WorldTransform2D>()) continue;
      final world = entity<WorldTransform2D>().component;
      _pendingWorldOf(entity, 0);
      world
        ..worldX[entity] = _pendingX
        ..worldY[entity] = _pendingY
        ..worldScaleX[entity] = _pendingScaleX
        ..worldScaleY[entity] = _pendingScaleY
        ..worldRotation[entity] = _pendingRotation;
    }
    _spawned.clear();
  }

  // [_pendingWorldOf]'s result. Instance scratch, and not a returned record,
  // the same technique `GameRenderer2D` uses: five doubles out of a method
  // called per spawned entity would be five allocations a tick (rule 1). Not
  // read anywhere outside that method and its caller.
  double _pendingX = 0;
  double _pendingY = 0;
  double _pendingRotation = 0;
  double _pendingScaleX = 1;
  double _pendingScaleY = 1;

  /// Composes [entity]'s world transform from **pending** reads, into the
  /// `_pending*` fields.
  ///
  /// Every read here is `readPending`, and it is safe for rows this tick never
  /// touched as well as rows it did: `MemoryPool.beginTick` starts each page's
  /// write slot as a copy of the last published one, so the write slot always
  /// holds the latest value, whether or not this tick wrote it. Which means
  /// this reads an ancestor's world transform correctly in all three cases
  /// that matter - composed by the main pass earlier this tick, skipped by it
  /// as unchanged, or written by an earlier iteration of [_composeSpawned].
  void _pendingWorldOf(Entity entity, int depth) {
    final local = entity.has<Transform2D>()
        ? entity<Transform2D>().component
        : null;
    // A bare grouping node contributes identity, exactly as in [_resolve].
    final offsetX = local == null
        ? 0.0
        : local.transformOffsetX.readPending(entity);
    final offsetY = local == null
        ? 0.0
        : local.transformOffsetY.readPending(entity);
    final rotation = local == null
        ? 0.0
        : local.transformRotation.readPending(entity);
    final scaleX = local == null
        ? 1.0
        : local.transformScaleX.readPending(entity);
    final scaleY = local == null
        ? 1.0
        : local.transformScaleY.readPending(entity);

    final parent = entity.has<Child>()
        ? entity<Child>().component.childParent.readPending(entity)
        : null;
    if (parent == null || depth >= maxHierarchyDepth) {
      assert(
        parent == null,
        'the parent chain above $entity is deeper than $maxHierarchyDepth, '
        'or contains a cycle. Composing it as a root rather than recursing '
        'forever - same policy as _resolve.',
      );
      _pendingX = offsetX;
      _pendingY = offsetY;
      _pendingRotation = rotation;
      _pendingScaleX = scaleX;
      _pendingScaleY = scaleY;
      return;
    }

    final double parentX, parentY, parentRotation, parentScaleX, parentScaleY;
    if (parent.has<WorldTransform2D>()) {
      final parentWorld = parent<WorldTransform2D>().component;
      parentX = parentWorld.worldX.readPending(parent);
      parentY = parentWorld.worldY.readPending(parent);
      parentRotation = parentWorld.worldRotation.readPending(parent);
      parentScaleX = parentWorld.worldScaleX.readPending(parent);
      parentScaleY = parentWorld.worldScaleY.readPending(parent);
    } else {
      // An ancestor that opted out of `WorldTransform2D` has nowhere to have
      // stored one, so it gets recomposed here on the way past.
      _pendingWorldOf(parent, depth + 1);
      parentX = _pendingX;
      parentY = _pendingY;
      parentRotation = _pendingRotation;
      parentScaleX = _pendingScaleX;
      parentScaleY = _pendingScaleY;
    }

    // The same single-parent-step composition as [_resolve]'s `hasParent`
    // branch, and it has to stay the same - two spellings of one affine
    // composition is rule 10's failure mode.
    final cos = math.cos(parentRotation);
    final sin = math.sin(parentRotation);
    final scaledX = offsetX * parentScaleX;
    final scaledY = offsetY * parentScaleY;
    _pendingX = parentX + scaledX * cos - scaledY * sin;
    _pendingY = parentY + scaledX * sin + scaledY * cos;
    _pendingRotation = parentRotation + rotation;
    _pendingScaleX = parentScaleX * scaleX;
    _pendingScaleY = parentScaleY * scaleY;
  }

  /// The whole pass for an archetype that has no [Parent] - so no entity in it
  /// can ever have a child, and its roots are the entire subtree they belong
  /// to. A flat field of sprites is exactly this, and so is every particle,
  /// projectile and pickup in most games.
  ///
  /// # Why it may skip the change-detection cache
  ///
  /// [_resolve]'s twelve cache accesses per entity - six to decide `changed`,
  /// six to update it - buy one thing: not re-walking a subtree whose
  /// ancestors did not move. These entities have no subtree, and with no
  /// parent to compose with, `world` *is* `local`. Recomputing that is five
  /// reads and five writes, which is cheaper than deciding whether to. So the
  /// cache is not consulted and the composition is done unconditionally.
  ///
  /// # Except for one write, which is not optional
  ///
  /// An archetype with [Child] but no [Parent] - a leaf that can be parented,
  /// which is the common shape - has *both* kinds of row: unparented ones this
  /// method handles, and parented ones [_resolve] reaches through their real
  /// root's recursion. A row can move between the two at runtime, and
  /// [_resolve] trusts its cache. Leaving the cache untouched here would leave
  /// a stale-but-self-consistent entry behind: parent a row, unparent it (this
  /// method overwrites `world` with the *local* transform and says nothing),
  /// then re-parent it to the same parent without touching its offsets, and
  /// [_resolve] would compare equal on every field, conclude nothing changed,
  /// and read back a `world` that was never composed. Clearing
  /// [worldCachedParent] makes that impossible - a row leaving this method
  /// always looks reparented to [_resolve], because it is. One flag-bit
  /// write, only for archetypes that can be parented at all.
  void _resolveChildless(
    Iterable<Entity> group,
    Transform2D local,
    WorldTransform2D world,
    Child? childLink,
  ) {
    // Two loops, not one with the null check inside: `childLink` is
    // fixed for the whole group, and an archetype that never mixes in `Child`
    // needs neither the root test nor the cache invalidation.
    if (childLink == null) {
      for (final entity in group) {
        _composeRoot(entity, local, world);
      }
      return;
    }
    for (final entity in group) {
      if (childLink.childParent[entity] != null) {
        continue; // not a root - reached via its real root's recursion
      }
      _composeRoot(entity, local, world);
      world.worldCachedParent[entity] = null;
    }
  }

  /// `world = local`, which is the whole of a root's world transform.
  @pragma('vm:prefer-inline')
  void _composeRoot(Entity entity, Transform2D local, WorldTransform2D world) {
    world.worldX[entity] = local.transformOffsetX[entity];
    world.worldY[entity] = local.transformOffsetY[entity];
    world.worldRotation[entity] = local.transformRotation[entity];
    world.worldScaleX[entity] = local.transformScaleX[entity];
    world.worldScaleY[entity] = local.transformScaleY[entity];
  }

  /// Resolves [entity] and recurses into its children.
  ///
  /// [local], [world], [childLink] and [parentComp] are [entity]'s archetype's
  /// components, resolved by the caller. Passed in, and not looked up here,
  /// because the caller usually already knows them for a whole group of rows
  /// at once - see [onFixedUpdate]. Each may be null: the recursion walks
  /// *every* child in the hierarchy, and a child need not have any of them.
  ///
  ///  * No [Transform2D]: a bare grouping node - Child/Parent links and
  ///    nothing else. It contributes identity and the walk steps over it,
  ///    instead of aborting and stranding its whole subtree at the origin.
  ///  * No [WorldTransform2D]: nothing to cache into, but its descendants may
  ///    still opt in, so the composed transform is threaded straight through
  ///    to them.
  ///
  /// The query only guarantees these for the *roots* it yields; from there on
  /// the parent/child links decide who gets visited, and they know nothing
  /// about component makeup.
  ///
  /// **Why the parent's world transform is passed in as plain arguments,
  /// not read back from `parentWorld.worldX[parent]` after writing it a few
  /// lines above**: this storage layer's reads always see the *last
  /// published* snapshot, never a write made earlier in the same tick (see
  /// `data_layout.dart`'s `_readRow` doc - the same reason a read-modify-
  /// write in `onEntityMounted` is unsafe). A parent resolved earlier in this
  /// top-down pass, this same tick, has a fresh value in the write slot that
  /// a same-tick read cannot see yet - reading it back would silently
  /// return last tick's stale value instead. Carrying the just-computed
  /// numbers down as parameters (mirroring `GameRenderer2D`'s own instance-
  /// scratch-field technique, just parameterized per recursion level instead
  /// of flat fields, since this walks top-down and not root-ward) sidesteps
  /// the whole problem: nothing this method just wrote is ever read back
  /// within the same call tree.
  void _resolve(
    Entity entity,
    Transform2D? local,
    WorldTransform2D? world,
    Child? childLink,
    Parent? parentComp, {
    required bool parentChanged,
    required bool hasParent,
    required double parentWorldX,
    required double parentWorldY,
    required double parentWorldRotation,
    required double parentWorldScaleX,
    required double parentWorldScaleY,
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

    final parent = childLink?.childParent[entity];

    final offsetX = local == null ? 0.0 : local.transformOffsetX[entity];
    final offsetY = local == null ? 0.0 : local.transformOffsetY[entity];
    final rotation = local == null ? 0.0 : local.transformRotation[entity];
    final scaleX = local == null ? 1.0 : local.transformScaleX[entity];
    final scaleY = local == null ? 1.0 : local.transformScaleY[entity];

    // Without somewhere to cache, there is no change to detect - such an
    // entity is recomposed every tick, which costs the arithmetic below and
    // nothing else. `parentChanged` still has to propagate through it, so
    // its descendants that *do* cache invalidate correctly.
    final changed =
        world == null ||
        parentChanged ||
        world.worldCachedParent[entity] != parent ||
        world.worldCachedOffsetX[entity] != offsetX ||
        world.worldCachedOffsetY[entity] != offsetY ||
        world.worldCachedRotation[entity] != rotation ||
        world.worldCachedScaleX[entity] != scaleX ||
        world.worldCachedScaleY[entity] != scaleY;

    // This entity's resolved world transform, as local variables - what
    // gets passed down to children as their parentWorld* arguments. Either
    // freshly computed below (changed) or read back from storage (not
    // changed - safe here specifically *because* nothing wrote to this
    // entity's world fields this tick in that branch, so the last-published
    // value already is this tick's correct value).
    double thisWorldX,
        thisWorldY,
        thisWorldRotation,
        thisWorldScaleX,
        thisWorldScaleY;

    if (changed) {
      if (!hasParent) {
        thisWorldX = offsetX;
        thisWorldY = offsetY;
        thisWorldRotation = rotation;
        thisWorldScaleX = scaleX;
        thisWorldScaleY = scaleY;
      } else {
        final cos = math.cos(parentWorldRotation);
        final sin = math.sin(parentWorldRotation);
        // Rotate+scale the local offset by the parent's world transform,
        // then translate by the parent's world position - exactly
        // GameRenderer2D._premultiplyByLocalOf's math, specialized to a
        // single parent step since this only ever composes with the
        // immediate parent's already-known world transform, not the whole
        // chain by hand.
        final scaledX = offsetX * parentWorldScaleX;
        final scaledY = offsetY * parentWorldScaleY;
        thisWorldX = parentWorldX + scaledX * cos - scaledY * sin;
        thisWorldY = parentWorldY + scaledX * sin + scaledY * cos;
        thisWorldRotation = parentWorldRotation + rotation;
        thisWorldScaleX = parentWorldScaleX * scaleX;
        thisWorldScaleY = parentWorldScaleY * scaleY;
      }
      // A grouping node with no WorldTransform2D has nowhere to store this -
      // it is composed purely to be handed down to its children below.
      if (world != null) {
        world.worldX[entity] = thisWorldX;
        world.worldY[entity] = thisWorldY;
        world.worldRotation[entity] = thisWorldRotation;
        world.worldScaleX[entity] = thisWorldScaleX;
        world.worldScaleY[entity] = thisWorldScaleY;
        world.worldCachedParent[entity] = parent;
        world.worldCachedOffsetX[entity] = offsetX;
        world.worldCachedOffsetY[entity] = offsetY;
        world.worldCachedRotation[entity] = rotation;
        world.worldCachedScaleX[entity] = scaleX;
        world.worldCachedScaleY[entity] = scaleY;
      }
    } else {
      // `changed` is forced true when `world` is null, so reaching here means
      // there is a cache to read back.
      thisWorldX = world.worldX[entity];
      thisWorldY = world.worldY[entity];
      thisWorldRotation = world.worldRotation[entity];
      thisWorldScaleX = world.worldScaleX[entity];
      thisWorldScaleY = world.worldScaleY[entity];
    }

    // No `Parent` on this archetype means no entity in it has children, so
    // there is nothing below to walk - and for a flat scene that is every
    // entity, so this is the one early return worth having here.
    if (parentComp == null) return;
    var next = parentComp.parentFirstChild[entity];
    while (next != null) {
      // Per child, because a child may be any archetype at all - this is the
      // lookup [onFixedUpdate] hoisted out of the *root* pass and the reason
      // it could not simply be hoisted out of this one too.
      _resolve(
        next,
        next.has<Transform2D>() ? next<Transform2D>().component : null,
        next.has<WorldTransform2D>()
            ? next<WorldTransform2D>().component
            : null,
        next.has<Child>() ? next<Child>().component : null,
        next.has<Parent>() ? next<Parent>().component : null,
        parentChanged: changed,
        hasParent: true,
        parentWorldX: thisWorldX,
        parentWorldY: thisWorldY,
        parentWorldRotation: thisWorldRotation,
        parentWorldScaleX: thisWorldScaleX,
        parentWorldScaleY: thisWorldScaleY,
        depth: depth + 1,
      );
      next = next<Child>().component.childNextSibling[next];
    }
  }
}
