import 'dart:math' as math;
import 'package:goo/goo.dart';

import 'package:goo2d/src/data/transform.dart';

/// An entity's resolved *world*-space transform - `Transform2D`'s own
/// fields, composed with every ancestor's, outermost last. Opt-in
/// (mixed in alongside `Transform2D`, not automatic): an entity that is
/// always at the scene root and never reparented has world == local by
/// construction and does not need the extra fields.
///
/// Fields are read-only from every other system's perspective - only
/// [WorldTransformSystem] ever writes them, once per `FixedTickEvent`, the
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
  late final DataPointer<double> worldX;
  late final DataPointer<double> worldY;
  late final DataPointer<double> worldScaleX;
  late final DataPointer<double> worldScaleY;
  late final DataPointer<double> worldRotation;

  // Change-detection cache, packed into the same row - not meant to be read
  // by anything outside WorldTransformSystem. Defaulted to NaN (offsets/
  // rotation) so the very first resolve for a freshly-spawned entity always
  // sees "changed" (NaN never compares equal to anything, including
  // itself) without a separate "have I ever run" flag.
  late final DataPointer<double> _cachedOffsetX;
  late final DataPointer<double> _cachedOffsetY;
  late final DataPointer<double> _cachedRotation;
  late final DataPointer<double> _cachedScaleX;
  late final DataPointer<double> _cachedScaleY;
  late final DataPointer<int?> _cachedParent;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<WorldTransform2D>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    worldX = data.hasFloat64();
    worldY = data.hasFloat64();
    worldScaleX = data.hasFloat64(1);
    worldScaleY = data.hasFloat64(1);
    worldRotation = data.hasFloat64();
    _cachedOffsetX = data.hasFloat64(double.nan);
    _cachedOffsetY = data.hasFloat64(double.nan);
    _cachedRotation = data.hasFloat64(double.nan);
    _cachedScaleX = data.hasFloat64(double.nan);
    _cachedScaleY = data.hasFloat64(double.nan);
    _cachedParent = data.optInt64();
  }
}

/// Keeps every [WorldTransform2D] current, once per `FixedTickEvent`.
///
/// Walks the hierarchy **top-down** using the intrusive `Parent.firstChild`/
/// `Child.nextSibling` linked list `data/hierarchy.dart` already maintains -
/// no separate adjacency structure needed - starting from roots (no parent,
/// or no `Child` mixin at all) so a parent's world transform is always
/// resolved before its children read it. Each entity's "did anything
/// change" check is a handful of field comparisons against last tick's
/// cached values, not a walk back to the root, so an unchanged subtree is
/// cheap to skip past.
///
/// Ordering: any system reading `WorldTransform2D` should extend its own
/// `compareTo` to run after this one (`other is WorldTransformSystem ? 1 :
/// 0`) - this system does not declare "I run first" unconditionally, since
/// that would only reciprocate for systems that happen to land as the "a"
/// argument in a given comparison (see `Game._sortSystems`'s own doc on
/// checking both comparison directions) and, more importantly, is simply
/// the wrong default: a system with no opinion about ordering should not be
/// silently forced to run after this one just because this one has an
/// opinion about everyone.
class WorldTransformSystem extends GameSystem with FixedTickable {
  /// Guards against a cycle in the parent chain, matching
  /// `GameRenderer2D.maxHierarchyDepth`'s reasoning.
  static const int maxHierarchyDepth = 64;

  late final Query _roots;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    // withOptional(Child) because an entity is a root whether it never mixes
    // in Child at all, or mixes it in but happens to be unparented.
    _roots = descriptor
        .query()
        .withAll(WorldTransform2D, Transform2D)
        .withOptional(Child)
        .build();
  }

  @override
  void onFixedUpdate() {
    for (final entity in _roots.run()) {
      final child = entity.tryGet<Child>();
      if (child != null && child.parent[entity] != null) {
        continue; // not a root - reached via its real root's recursion below
      }
      // Roots have no parent to compose with - the parentWorld* arguments
      // are unused whenever hasParent is false, so their value here does
      // not matter.
      _resolve(
        entity,
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

  /// Resolves [entity] and recurses into its children.
  ///
  /// **Why the parent's world transform is passed in as plain arguments,
  /// not read back from `parentWorld.worldX[parent]` after writing it a few
  /// lines above**: this storage layer's reads always see the *last
  /// published* snapshot, never a write made earlier in the same tick (see
  /// `data_layout.dart`'s `_readRow` doc - the same reason a read-modify-
  /// write in `onCreated` is unsafe). A parent resolved earlier in this same
  /// top-down pass, this same tick, has a fresh value in the write slot that
  /// a same-tick read cannot see yet - reading it back would silently
  /// return last tick's stale value instead. Carrying the just-computed
  /// numbers down as parameters (mirroring `GameRenderer2D`'s own instance-
  /// scratch-field technique, just parameterized per recursion level instead
  /// of flat fields, since this walks top-down rather than root-ward) sidesteps
  /// the whole problem: nothing this method just wrote is ever read back
  /// within the same call tree.
  void _resolve(
    Entity entity, {
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

    // Both are `tryGet`, because the recursion below walks *every* child in
    // the hierarchy, and a child need not have either component.
    //
    //  * No `Transform2D`: a bare grouping node - Child/Parent links and
    //    nothing else. It contributes identity and the walk steps over it,
    //    rather than aborting and stranding its whole subtree at the origin.
    //  * No `WorldTransform2D`: nothing to cache into, but its descendants
    //    may still opt in, so the composed transform is threaded straight
    //    through to them.
    //
    // The query only guarantees these for the *roots* it yields; from there
    // on the parent/child links decide who gets visited, and they know
    // nothing about component makeup.
    final local = entity.tryGet<Transform2D>();
    final world = entity.tryGet<WorldTransform2D>();
    final childLink = entity.tryGet<Child>();
    final parent = childLink?.parent[entity];

    final offsetX = local == null ? 0.0 : local.transformOffsetX[entity];
    final offsetY = local == null ? 0.0 : local.transformOffsetY[entity];
    final rotation = local == null ? 0.0 : local.transformRotation[entity];
    final scaleX = local == null ? 1.0 : local.transformScaleX[entity];
    final scaleY = local == null ? 1.0 : local.transformScaleY[entity];

    // Without somewhere to cache, there is no change to detect - such an
    // entity is recomposed every tick, which costs the arithmetic below and
    // nothing else. `parentChanged` still has to propagate through it, so
    // its descendants that *do* cache invalidate correctly.
    final changed = world == null ||
        parentChanged ||
        world._cachedParent[entity] != parent?.value ||
        world._cachedOffsetX[entity] != offsetX ||
        world._cachedOffsetY[entity] != offsetY ||
        world._cachedRotation[entity] != rotation ||
        world._cachedScaleX[entity] != scaleX ||
        world._cachedScaleY[entity] != scaleY;

    // This entity's resolved world transform, as local variables - what
    // gets passed down to children as their parentWorld* arguments. Either
    // freshly computed below (changed) or read back from storage (not
    // changed - safe here specifically *because* nothing wrote to this
    // entity's world fields this tick in that branch, so the last-published
    // value already is this tick's correct value).
    double thisWorldX, thisWorldY, thisWorldRotation, thisWorldScaleX, thisWorldScaleY;

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
        world._cachedParent[entity] = parent?.value;
        world._cachedOffsetX[entity] = offsetX;
        world._cachedOffsetY[entity] = offsetY;
        world._cachedRotation[entity] = rotation;
        world._cachedScaleX[entity] = scaleX;
        world._cachedScaleY[entity] = scaleY;
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

    final parentComp = entity.tryGet<Parent>();
    if (parentComp == null) return;
    var next = parentComp.firstChild[entity];
    while (next != null) {
      _resolve(
        next,
        parentChanged: changed,
        hasParent: true,
        parentWorldX: thisWorldX,
        parentWorldY: thisWorldY,
        parentWorldRotation: thisWorldRotation,
        parentWorldScaleX: thisWorldScaleX,
        parentWorldScaleY: thisWorldScaleY,
        depth: depth + 1,
      );
      next = next.get<Child>().nextSibling[next];
    }
  }
}
