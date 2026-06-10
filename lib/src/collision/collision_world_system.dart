import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/collision/collision_system.dart';
import 'package:goo2d/src/collision/worker/collision_delta.dart';
import 'package:goo2d/src/collision/worker/collision_worker.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';

/// An ECS [WorldSystem] that bridges [CollisionSystem] to entities carrying
/// [ColliderData] and [TransformData] (no [RigidbodyData] required).
///
/// On each fixed tick this system:
/// 1. Creates/destroys collision shapes to match living entities.
/// 2. Pushes entity transforms into the collision worker.
/// 3. Steps the worker and dispatches overlap events.
///
/// Add to a [WorldController] to enable ECS collision:
/// ```dart
/// world.addSystem(CollisionWorldSystem());
/// ```
///
/// Overlap events are dispatched per-paradigm to avoid Dart covariant-generic
/// collisions (since `Entity` and `Collider` both extend `PhysicsBody`, a
/// `<PhysicsBody>` broadcast would incorrectly reach `<Entity>` and `<Collider>`
/// listeners at runtime):
/// - ECS–ECS: [PhysicsOverlap<Entity>] via [WorldController.broadcastEventAsync]
/// - EC–EC: [PhysicsOverlap<Collider>] via [GameObject.dispatchTo] + world broadcast
/// - Cross-paradigm: [PhysicsOverlap<PhysicsBody>] via [GameObject.dispatchTo] only
class CollisionWorldSystem extends WorldSystem with FixedTickable, LifecycleListener {
  late final ColliderData _cold = define(ColliderData.new);
  late final TransformData _td  = define(TransformData.new);

  CollisionSystem? _cs;

  // slot → collider handle (to detect removed entities)
  final Map<int, int> _trackedEntities = {};
  // handle → Entity (incremental; updated on spawn/despawn, not rebuilt each tick)
  final Map<int, Entity> _handleToEntity = {};

  // Generation counter for zero-allocation dead-entity detection.
  // _slotGen[s] == _syncGen means slot s was alive in the current tick.
  int _syncGen = 0;
  final Map<int, int> _slotGen = {};

  bool _dbgFirstEnter = true;

  @override
  void onMounted() {
    _cs = gameObject?.game.getSystem<CollisionSystem>();
    _cs?.registerEcsWorld(this);
    debugPrint('[CWS] onMounted: _cs=${_cs != null ? "OK" : "NULL"}, gameObject=${gameObject != null ? "OK" : "NULL"}');
  }

  @override
  void onUnmounted() {
    _cs?.unregisterEcsWorld();
    _cs = null;
  }

  @override
  Future<void> onFixedUpdate(double dt) async {
    final cs = _cs;
    if (cs == null) return;
    _syncAll(cs.worker);
    final CollisionDelta delta;
    try {
      delta = await cs.worker.step();
    } catch (_) {
      return; // worker disposed mid-step (e.g. tab switch during await)
    }
    if (_cs == null) return; // disposed mid-await
    if (_dbgFirstEnter && delta.enterPairs.isNotEmpty) {
      _dbgFirstEnter = false;
      debugPrint('[CWS] first enter: ${delta.enterPairs.length ~/ 2} pairs, tracked=${_trackedEntities.length}');
    }
    await _dispatchAll(delta);
  }

  // ── Single-pass sync: registration, reverse-lookup, and transforms ─────────
  //
  // Merging these three operations into one query eliminates two redundant
  // full-entity iterations per fixed tick compared to the original three-pass
  // approach. The handle→entity map is maintained incrementally (updated only
  // on spawn/despawn) rather than rebuilt from scratch every tick.

  void _syncAll(CollisionWorker w) {
    final gen = ++_syncGen;

    (world.query()..withAll(_cold, _td)).withEntity().forEach((r) {
      final s = r.entity.index;
      _slotGen[s] = gen;

      int handle;
      if (_cold.colliderHandle.getSlot(s) < 0) {
        // New entity — if the slot was previously occupied, the old shape and
        // its reverse-lookup entry must be cleaned up before registering a new one.
        // This happens when an entity is destroyed and its pool slot is reused: the
        // previous fixed tick saw the old entity alive, _trackedEntities still holds
        // its handle, and the collision worker still has its shape alive.
        final staleHandle = _trackedEntities[s];
        if (staleHandle != null) {
          _handleToEntity.remove(staleHandle);
          _trackedEntities.remove(s);
          w.destroyShape(staleHandle);
        }
        final st = _cold.shapeType.getSlot(s);
        handle = w.createShape(st);
        _cold.colliderHandle.setSlot(s, handle);
        _trackedEntities[s] = handle;
        _handleToEntity[handle] = r.entity;
        w.setShapeOffset(handle, _cold.offsetX.getSlot(s), _cold.offsetY.getSlot(s));
        _applyShapeGeometry(w, handle, s);
      } else {
        handle = _cold.colliderHandle.getSlot(s);
        if (!_trackedEntities.containsKey(s)) {
          _trackedEntities[s] = handle;
          _handleToEntity[handle] = r.entity;
        }
      }

      w.setShapeTransform(handle, _td.x.getSlot(s), _td.y.getSlot(s), _td.angle.getSlot(s));
    });

    // Remove despawned entities — no allocation: removeWhere iterates in-place.
    _trackedEntities.removeWhere((s, handle) {
      if (_slotGen[s] == gen) return false;
      _handleToEntity.remove(handle);
      w.destroyShape(handle);
      return true;
    });
  }

  void _applyShapeGeometry(CollisionWorker w, int handle, int s) {
    final st = _cold.shapeType.getSlot(s);
    if (st == ColliderShapeType.circle) {
      w.setShapeCircle(handle, _cold.radius.getSlot(s));
    } else if (st == ColliderShapeType.box) {
      w.setShapeBox(handle, _cold.width.getSlot(s) / 2, _cold.height.getSlot(s) / 2);
    }
  }

  // ── Event dispatch ────────────────────────────────────────────────────────

  Future<void> _dispatchAll(CollisionDelta delta) async {
    await _dispatchPairs(delta.enterPairs, isEnter: true, isExit: false);
    await _dispatchPairs(delta.stayPairs,  isEnter: false, isExit: false);
    await _dispatchPairs(delta.exitPairs,  isEnter: false, isExit: true);
  }

  Future<void> _dispatchPairs(
      Int32List pairs, {required bool isEnter, required bool isExit}) async {
    final n = pairs.length ~/ 2;
    for (var i = 0; i < n; i++) {
      final hA = pairs[i * 2], hB = pairs[i * 2 + 1];
      final cA = _cs?.getCollider(hA);
      final cB = _cs?.getCollider(hB);
      final eA = _handleToEntity[hA];
      final eB = _handleToEntity[hB];

      if (isExit) {
        if (cA != null && cB != null && cA.isAttached && cB.isAttached) {
          await OverlapExitEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB))
              .dispatchTo(cA.gameObject);
          await OverlapExitEvent(PhysicsOverlap<Collider>(trigger: cB, other: cA))
              .dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
              OverlapExitEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB)));
        } else if (eA != null && eB != null) {
          await world.broadcastEventAsync(
              OverlapExitEvent(PhysicsOverlap<Entity>(trigger: eA, other: eB)));
        } else if (cA != null && eB != null && cA.isAttached) {
          await OverlapExitEvent(PhysicsOverlap<PhysicsBody>(trigger: cA, other: eB))
              .dispatchTo(cA.gameObject);
        } else if (eA != null && cB != null && cB.isAttached) {
          await OverlapExitEvent(PhysicsOverlap<PhysicsBody>(trigger: cB, other: eA))
              .dispatchTo(cB.gameObject);
        }
      } else if (isEnter) {
        if (cA != null && cB != null && cA.isAttached && cB.isAttached) {
          await OverlapEnterEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB))
              .dispatchTo(cA.gameObject);
          await OverlapEnterEvent(PhysicsOverlap<Collider>(trigger: cB, other: cA))
              .dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
              OverlapEnterEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB)));
        } else if (eA != null && eB != null) {
          await world.broadcastEventAsync(
              OverlapEnterEvent(PhysicsOverlap<Entity>(trigger: eA, other: eB)));
        } else if (cA != null && eB != null && cA.isAttached) {
          await OverlapEnterEvent(PhysicsOverlap<PhysicsBody>(trigger: cA, other: eB))
              .dispatchTo(cA.gameObject);
        } else if (eA != null && cB != null && cB.isAttached) {
          await OverlapEnterEvent(PhysicsOverlap<PhysicsBody>(trigger: cB, other: eA))
              .dispatchTo(cB.gameObject);
        }
      } else {
        if (cA != null && cB != null && cA.isAttached && cB.isAttached) {
          await OverlapStayEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB))
              .dispatchTo(cA.gameObject);
          await OverlapStayEvent(PhysicsOverlap<Collider>(trigger: cB, other: cA))
              .dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
              OverlapStayEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB)));
        } else if (eA != null && eB != null) {
          await world.broadcastEventAsync(
              OverlapStayEvent(PhysicsOverlap<Entity>(trigger: eA, other: eB)));
        } else if (cA != null && eB != null && cA.isAttached) {
          await OverlapStayEvent(PhysicsOverlap<PhysicsBody>(trigger: cA, other: eB))
              .dispatchTo(cA.gameObject);
        } else if (eA != null && cB != null && cB.isAttached) {
          await OverlapStayEvent(PhysicsOverlap<PhysicsBody>(trigger: cB, other: eA))
              .dispatchTo(cB.gameObject);
        }
      }
    }
  }
}
