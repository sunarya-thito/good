import 'dart:typed_data';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/physics/worker/data/contact_delta.dart';
import 'package:goo2d/src/physics/worker/physics_worker.dart';
import 'package:goo2d/src/physics/worker/direct/direct_body_ops.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/src/physics/worker/direct/direct_collider_ops.dart';

/// A [WorldSystem] that owns the physics fixed tick and bridges physics events
/// to both EC GameObjects and ECS WorldSystems.
///
/// Add to a [WorldController] alongside [TransformSystem] to enable ECS physics.
/// Entities with [RigidbodyData] (and optionally [ColliderData]) participate in
/// the simulation; entities with [TransformData] have their position synced.
///
/// Physics events are dispatched in three flavors:
/// - `PhysicsContactListener<Collider>` — EC↔EC contacts via `dispatchTo(gameObject)`
/// - `PhysicsContactListener<Entity>` — ECS↔ECS contacts via `broadcastEventAsync`
/// - `PhysicsContactListener<PhysicsBody>` — all contacts including cross-paradigm
class PhysicsWorldSystem extends WorldSystem with FixedTickable {
  late final RigidbodyData _rbd = define(RigidbodyData.new);
  late final ColliderData _cold = define(ColliderData.new);
  late final TransformData _td = define(TransformData.new);

  // handle → Entity for ECS bodies; rebuilt each fixed tick.
  final Map<int, Entity> _entityByCollider = {};

  // Entity slot → handle tracking for cleanup when entities are removed.
  final Map<int, int> _trackedBodies = {};
  final Map<int, int> _trackedColliders = {};

  // Scratch slot buffers for async sync passes; grown on demand.
  Int32List _slots = Int32List(64);
  int _slotCount = 0;

  @override
  void onAttach() => PhysicsSystem.registerEcsWorld(this);

  @override
  void onDetach() => PhysicsSystem.unregisterEcsWorld();

  @override
  Future<void> onFixedUpdate(double dt) async {
    // Capture before any await — mode switches can dispose the system mid-tick.
    final ps = PhysicsSystem.maybeInstance;
    if (ps == null) return;
    _syncEntityRegistrations(ps.worker);
    _buildReverseLookup();
    await _syncEcsKinematicToPhysics(ps.worker);
    if (PhysicsSystem.maybeInstance == null) return;
    final delta = await ps.stepWithDelta(dt);
    if (PhysicsSystem.maybeInstance == null) return;
    await _syncPhysicsToDynamicEcs(ps.worker);
    await _dispatchAll(delta);
  }

  // ── Entity registration ─────────────────────────────────────────────────────

  void _syncEntityRegistrations(PhysicsWorker w) {
    final currentSlots = <int>{};

    // Create rigidbodies for entities that have RigidbodyData but no body yet.
    (world.query()..withAll(_rbd)).withEntity().forEach((r) {
      final s = r.entity.index;
      currentSlots.add(s);
      if (_rbd.bodyHandle.getSlot(s) >= 0) {
        _trackedBodies.putIfAbsent(s, () => _rbd.bodyHandle.getSlot(s));
        return;
      }
      final handle = w.createBody();
      _rbd.bodyHandle.setSlot(s, handle);
      _trackedBodies[s] = handle;
      w.setBodyProperty(handle, BodyProp.bodyType, _rbd.bodyType.getSlot(s).index);
      w.setBodyProperty(
        handle,
        BodyProp.gravityScale,
        _rbd.gravityScale.getSlot(s),
      );
      w.setBodyProperty(
        handle,
        BodyProp.angularDamping,
        _rbd.angularDamping.getSlot(s),
      );
      w.setBodyProperty(
        handle,
        BodyProp.linearDamping,
        _rbd.linearDampingX.getSlot(s),
      );
      w.setBodyProperty(
        handle,
        BodyProp.freezeRotation,
        _rbd.freezeRotation.getSlot(s),
      );
      w.setBodyProperty(handle, BodyProp.simulated, _rbd.simulated.getSlot(s));
      // Set initial position from TransformData if present (default 0,0 otherwise).
      w.setBodyProperty(
        handle,
        BodyProp.position,
        Vector2(_td.x.getSlot(s), _td.y.getSlot(s)),
      );
      w.setBodyProperty(handle, BodyProp.rotation, _td.angle.getSlot(s));
    });

    // Destroy bodies/colliders for entity slots that no longer exist.
    final deadSlots = _trackedBodies.keys.where((s) => !currentSlots.contains(s)).toList();
    for (final s in deadSlots) {
      final ch = _trackedColliders.remove(s);
      final bh = _trackedBodies.remove(s)!;
      if (ch != null) w.destroyCollider(ch);
      w.destroyBody(bh);
    }

    // Create colliders for entities that have both RigidbodyData (body created)
    // and ColliderData (collider not yet created).
    (world.query()..withAll(_cold, _rbd)).withEntity().forEach((r) {
      final s = r.entity.index;
      final bodyHandle = _rbd.bodyHandle.getSlot(s);
      if (bodyHandle < 0) return;
      if (_cold.colliderHandle.getSlot(s) >= 0) {
        _trackedColliders.putIfAbsent(s, () => _cold.colliderHandle.getSlot(s));
        return;
      }
      final shapeType = _cold.shapeType.getSlot(s);
      final handle = w.createCollider(shapeType, bodyHandle);
      _cold.colliderHandle.setSlot(s, handle);
      _trackedColliders[s] = handle;
      w.setColliderProperty(
        handle,
        ColliderProp.isTrigger,
        _cold.isTrigger.getSlot(s),
      );
      w.setColliderProperty(
        handle,
        ColliderProp.density,
        _cold.density.getSlot(s),
      );
      w.setColliderProperty(
        handle,
        ColliderProp.friction,
        _cold.friction.getSlot(s),
      );
      w.setColliderProperty(
        handle,
        ColliderProp.bounciness,
        _cold.bounciness.getSlot(s),
      );
      w.setColliderProperty(
        handle,
        ColliderProp.offset,
        Vector2(_cold.offsetX.getSlot(s), _cold.offsetY.getSlot(s)),
      );
      // Shape-specific size properties
      final st = _cold.shapeType.getSlot(s);
      if (st == ColliderShapeType.circle) {
        w.setColliderProperty(handle, ColliderProp.circleRadius, _cold.radius.getSlot(s));
      } else if (st == ColliderShapeType.box) {
        w.setColliderProperty(
          handle,
          ColliderProp.boxSize,
          Vector2(_cold.width.getSlot(s), _cold.height.getSlot(s)),
        );
      }
    });
  }

  // ── Reverse lookup ──────────────────────────────────────────────────────────

  void _buildReverseLookup() {
    _entityByCollider.clear();
    (world.query()..withAll(_cold)).withEntity().forEach((r) {
      final handle = _cold.colliderHandle.getSlot(r.entity.index);
      if (handle >= 0) _entityByCollider[handle] = r.entity;
    });
  }

  // ── Transform sync ──────────────────────────────────────────────────────────

  Future<void> _syncEcsKinematicToPhysics(PhysicsWorker w) async {
    _slotCount = 0;
    (world.query()..withAll(_rbd, _td)).withEntity().forEach((r) {
      final s = r.entity.index;
      final bh = _rbd.bodyHandle.getSlot(s);
      if (bh < 0) return;
      if (_rbd.bodyType.getSlot(s) != RigidbodyType.kinematic) return;
      _growSlots(_slotCount + 2);
      _slots[_slotCount++] = bh;
      _slots[_slotCount++] = s;
    });
    for (var i = 0; i < _slotCount; i += 2) {
      await w.bodyMovePositionAndRotation(
        _slots[i],
        Vector2(_td.x.getSlot(_slots[i + 1]), _td.y.getSlot(_slots[i + 1])),
        _td.angle.getSlot(_slots[i + 1]),
      );
    }
  }

  Future<void> _syncPhysicsToDynamicEcs(PhysicsWorker w) async {
    _slotCount = 0;
    (world.query()..withAll(_rbd, _td)).withEntity().forEach((r) {
      final s = r.entity.index;
      final bh = _rbd.bodyHandle.getSlot(s);
      if (bh < 0) return;
      if (_rbd.bodyType.getSlot(s) != RigidbodyType.dynamic) return;
      _growSlots(_slotCount + 2);
      _slots[_slotCount++] = bh;
      _slots[_slotCount++] = s;
    });
    for (var i = 0; i < _slotCount; i += 2) {
      final bh = _slots[i];
      final s = _slots[i + 1];
      final pos = (await w.getBodyProperty(bh, BodyProp.position)) as Vector2;
      final rot = (await w.getBodyProperty(bh, BodyProp.rotation)) as double;
      _td.x.setSlot(s, pos.x);
      _td.y.setSlot(s, pos.y);
      _td.angle.setSlot(s, rot);
    }
  }

  void _growSlots(int need) {
    if (need <= _slots.length) return;
    final n = need * 2;
    _slots = Int32List(n)..setRange(0, _slots.length, _slots);
  }

  // ── Event dispatch ──────────────────────────────────────────────────────────

  Future<void> _dispatchAll(ContactDelta delta) async {
    // Solid contacts
    await _dispatchContactPairs(
      delta.enterContacts,
      delta.contactPoints,
      delta.contactPointCounts,
      isEnter: true,
    );
    await _dispatchContactPairs(delta.stayContacts, null, null, isEnter: false);
    await _dispatchExitPairs(delta.exitContacts, isContact: true);

    // Triggers
    await _dispatchOverlapPairs(delta.enterTriggers, isEnter: true);
    await _dispatchOverlapPairs(delta.stayTriggers, isEnter: false);
    await _dispatchExitPairs(delta.exitTriggers, isContact: false);
  }

  Future<void> _dispatchContactPairs(
    Int32List pairs,
    Float32List? rawPoints,
    Int32List? counts, {
    required bool isEnter,
  }) async {
    final n = pairs.length ~/ 2;
    var ptOffset = 0;
    for (var i = 0; i < n; i++) {
      final hA = pairs[i * 2], hB = pairs[i * 2 + 1];

      List<PhysicsContactPoint> pts = const [];
      if (isEnter && rawPoints != null && counts != null) {
        final pc = counts[i];
        if (pc > 0) {
          pts = List.generate(pc, (j) {
            final b = (ptOffset + j) * ContactDelta.floatsPerPoint;
            return PhysicsContactPoint(
              point: Vector2(
                rawPoints[b].toDouble(),
                rawPoints[b + 1].toDouble(),
              ),
              normal: Vector2(
                rawPoints[b + 2].toDouble(),
                rawPoints[b + 3].toDouble(),
              ),
              separation: rawPoints[b + 4].toDouble(),
              normalImpulse: rawPoints[b + 5].toDouble(),
              tangentImpulse: rawPoints[b + 6].toDouble(),
            );
          });
          ptOffset += pc;
        }
      }

      final cA = PhysicsSystem.getCollider(hA);
      final cB = PhysicsSystem.getCollider(hB);
      final eA = _entityByCollider[hA];
      final eB = _entityByCollider[hB];

      if (cA != null && cB != null && cA.isAttached && cB.isAttached) {
        // EC↔EC — dispatch to gameObjects and broadcast <Collider> + <PhysicsBody>
        if (isEnter) {
          await ContactEnterEvent(
            PhysicsContact<Collider>(bodyA: cA, bodyB: cB, contacts: pts),
          ).dispatchTo(cA.gameObject);
          await ContactEnterEvent(
            PhysicsContact<Collider>(bodyA: cB, bodyB: cA, contacts: pts),
          ).dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
            ContactEnterEvent(
              PhysicsContact<Collider>(bodyA: cA, bodyB: cB, contacts: pts),
            ),
          );
          await world.broadcastEventAsync(
            ContactEnterEvent(
              PhysicsContact<PhysicsBody>(bodyA: cA, bodyB: cB, contacts: pts),
            ),
          );
        } else {
          await ContactStayEvent(
            PhysicsContact<Collider>(bodyA: cA, bodyB: cB),
          ).dispatchTo(cA.gameObject);
          await ContactStayEvent(
            PhysicsContact<Collider>(bodyA: cB, bodyB: cA),
          ).dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
            ContactStayEvent(PhysicsContact<Collider>(bodyA: cA, bodyB: cB)),
          );
          await world.broadcastEventAsync(
            ContactStayEvent(PhysicsContact<PhysicsBody>(bodyA: cA, bodyB: cB)),
          );
        }
      } else if (eA != null && eB != null) {
        // ECS↔ECS — broadcast <Entity> + <PhysicsBody>
        if (isEnter) {
          await world.broadcastEventAsync(
            ContactEnterEvent(
              PhysicsContact<Entity>(bodyA: eA, bodyB: eB, contacts: pts),
            ),
          );
          await world.broadcastEventAsync(
            ContactEnterEvent(
              PhysicsContact<PhysicsBody>(bodyA: eA, bodyB: eB, contacts: pts),
            ),
          );
        } else {
          await world.broadcastEventAsync(
            ContactStayEvent(PhysicsContact<Entity>(bodyA: eA, bodyB: eB)),
          );
          await world.broadcastEventAsync(
            ContactStayEvent(PhysicsContact<PhysicsBody>(bodyA: eA, bodyB: eB)),
          );
        }
      } else if (cA != null && eB != null && cA.isAttached) {
        // EC↔ECS — dispatch <PhysicsBody> to EC gameObject; broadcast <PhysicsBody>
        if (isEnter) {
          await ContactEnterEvent(
            PhysicsContact<PhysicsBody>(bodyA: cA, bodyB: eB, contacts: pts),
          ).dispatchTo(cA.gameObject);
          await world.broadcastEventAsync(
            ContactEnterEvent(
              PhysicsContact<PhysicsBody>(bodyA: eB, bodyB: cA, contacts: pts),
            ),
          );
        } else {
          await ContactStayEvent(
            PhysicsContact<PhysicsBody>(bodyA: cA, bodyB: eB),
          ).dispatchTo(cA.gameObject);
          await world.broadcastEventAsync(
            ContactStayEvent(PhysicsContact<PhysicsBody>(bodyA: eB, bodyB: cA)),
          );
        }
      } else if (eA != null && cB != null && cB.isAttached) {
        // ECS↔EC — symmetric of above
        if (isEnter) {
          await ContactEnterEvent(
            PhysicsContact<PhysicsBody>(bodyA: cB, bodyB: eA, contacts: pts),
          ).dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
            ContactEnterEvent(
              PhysicsContact<PhysicsBody>(bodyA: eA, bodyB: cB, contacts: pts),
            ),
          );
        } else {
          await ContactStayEvent(
            PhysicsContact<PhysicsBody>(bodyA: cB, bodyB: eA),
          ).dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
            ContactStayEvent(PhysicsContact<PhysicsBody>(bodyA: eA, bodyB: cB)),
          );
        }
      }
    }
  }

  Future<void> _dispatchExitPairs(
    Int32List pairs, {
    required bool isContact,
  }) async {
    final n = pairs.length ~/ 2;
    for (var i = 0; i < n; i++) {
      final hA = pairs[i * 2], hB = pairs[i * 2 + 1];
      final cA = PhysicsSystem.getCollider(hA);
      final cB = PhysicsSystem.getCollider(hB);
      final eA = _entityByCollider[hA];
      final eB = _entityByCollider[hB];

      if (isContact) {
        if (cA != null && cB != null && cA.isAttached && cB.isAttached) {
          await ContactExitEvent(
            PhysicsContact<Collider>(bodyA: cA, bodyB: cB),
          ).dispatchTo(cA.gameObject);
          await ContactExitEvent(
            PhysicsContact<Collider>(bodyA: cB, bodyB: cA),
          ).dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
            ContactExitEvent(PhysicsContact<Collider>(bodyA: cA, bodyB: cB)),
          );
          await world.broadcastEventAsync(
            ContactExitEvent(PhysicsContact<PhysicsBody>(bodyA: cA, bodyB: cB)),
          );
        } else if (eA != null && eB != null) {
          await world.broadcastEventAsync(
            ContactExitEvent(PhysicsContact<Entity>(bodyA: eA, bodyB: eB)),
          );
          await world.broadcastEventAsync(
            ContactExitEvent(PhysicsContact<PhysicsBody>(bodyA: eA, bodyB: eB)),
          );
        } else if (cA != null && eB != null && cA.isAttached) {
          await ContactExitEvent(
            PhysicsContact<PhysicsBody>(bodyA: cA, bodyB: eB),
          ).dispatchTo(cA.gameObject);
          await world.broadcastEventAsync(
            ContactExitEvent(PhysicsContact<PhysicsBody>(bodyA: eB, bodyB: cA)),
          );
        } else if (eA != null && cB != null && cB.isAttached) {
          await ContactExitEvent(
            PhysicsContact<PhysicsBody>(bodyA: cB, bodyB: eA),
          ).dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
            ContactExitEvent(PhysicsContact<PhysicsBody>(bodyA: eA, bodyB: cB)),
          );
        }
      } else {
        if (cA != null && cB != null && cA.isAttached && cB.isAttached) {
          await OverlapExitEvent(
            PhysicsOverlap<Collider>(trigger: cA, other: cB),
          ).dispatchTo(cA.gameObject);
          await OverlapExitEvent(
            PhysicsOverlap<Collider>(trigger: cB, other: cA),
          ).dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
            OverlapExitEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB)),
          );
          await world.broadcastEventAsync(
            OverlapExitEvent(
              PhysicsOverlap<PhysicsBody>(trigger: cA, other: cB),
            ),
          );
        } else if (eA != null && eB != null) {
          await world.broadcastEventAsync(
            OverlapExitEvent(PhysicsOverlap<Entity>(trigger: eA, other: eB)),
          );
          await world.broadcastEventAsync(
            OverlapExitEvent(
              PhysicsOverlap<PhysicsBody>(trigger: eA, other: eB),
            ),
          );
        } else if (cA != null && eB != null && cA.isAttached) {
          await OverlapExitEvent(
            PhysicsOverlap<PhysicsBody>(trigger: cA, other: eB),
          ).dispatchTo(cA.gameObject);
          await world.broadcastEventAsync(
            OverlapExitEvent(
              PhysicsOverlap<PhysicsBody>(trigger: eB, other: cA),
            ),
          );
        } else if (eA != null && cB != null && cB.isAttached) {
          await OverlapExitEvent(
            PhysicsOverlap<PhysicsBody>(trigger: cB, other: eA),
          ).dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
            OverlapExitEvent(
              PhysicsOverlap<PhysicsBody>(trigger: eA, other: cB),
            ),
          );
        }
      }
    }
  }

  Future<void> _dispatchOverlapPairs(
    Int32List pairs, {
    required bool isEnter,
  }) async {
    final n = pairs.length ~/ 2;
    for (var i = 0; i < n; i++) {
      final hA = pairs[i * 2], hB = pairs[i * 2 + 1];
      final cA = PhysicsSystem.getCollider(hA);
      final cB = PhysicsSystem.getCollider(hB);
      final eA = _entityByCollider[hA];
      final eB = _entityByCollider[hB];

      if (cA != null && cB != null && cA.isAttached && cB.isAttached) {
        if (isEnter) {
          await OverlapEnterEvent(
            PhysicsOverlap<Collider>(trigger: cA, other: cB),
          ).dispatchTo(cA.gameObject);
          await OverlapEnterEvent(
            PhysicsOverlap<Collider>(trigger: cB, other: cA),
          ).dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
            OverlapEnterEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB)),
          );
          await world.broadcastEventAsync(
            OverlapEnterEvent(
              PhysicsOverlap<PhysicsBody>(trigger: cA, other: cB),
            ),
          );
        } else {
          await OverlapStayEvent(
            PhysicsOverlap<Collider>(trigger: cA, other: cB),
          ).dispatchTo(cA.gameObject);
          await OverlapStayEvent(
            PhysicsOverlap<Collider>(trigger: cB, other: cA),
          ).dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
            OverlapStayEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB)),
          );
          await world.broadcastEventAsync(
            OverlapStayEvent(
              PhysicsOverlap<PhysicsBody>(trigger: cA, other: cB),
            ),
          );
        }
      } else if (eA != null && eB != null) {
        if (isEnter) {
          await world.broadcastEventAsync(
            OverlapEnterEvent(PhysicsOverlap<Entity>(trigger: eA, other: eB)),
          );
          await world.broadcastEventAsync(
            OverlapEnterEvent(
              PhysicsOverlap<PhysicsBody>(trigger: eA, other: eB),
            ),
          );
        } else {
          await world.broadcastEventAsync(
            OverlapStayEvent(PhysicsOverlap<Entity>(trigger: eA, other: eB)),
          );
          await world.broadcastEventAsync(
            OverlapStayEvent(
              PhysicsOverlap<PhysicsBody>(trigger: eA, other: eB),
            ),
          );
        }
      } else if (cA != null && eB != null && cA.isAttached) {
        if (isEnter) {
          await OverlapEnterEvent(
            PhysicsOverlap<PhysicsBody>(trigger: cA, other: eB),
          ).dispatchTo(cA.gameObject);
          await world.broadcastEventAsync(
            OverlapEnterEvent(
              PhysicsOverlap<PhysicsBody>(trigger: eB, other: cA),
            ),
          );
        } else {
          await OverlapStayEvent(
            PhysicsOverlap<PhysicsBody>(trigger: cA, other: eB),
          ).dispatchTo(cA.gameObject);
          await world.broadcastEventAsync(
            OverlapStayEvent(
              PhysicsOverlap<PhysicsBody>(trigger: eB, other: cA),
            ),
          );
        }
      } else if (eA != null && cB != null && cB.isAttached) {
        if (isEnter) {
          await OverlapEnterEvent(
            PhysicsOverlap<PhysicsBody>(trigger: cB, other: eA),
          ).dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
            OverlapEnterEvent(
              PhysicsOverlap<PhysicsBody>(trigger: eA, other: cB),
            ),
          );
        } else {
          await OverlapStayEvent(
            PhysicsOverlap<PhysicsBody>(trigger: cB, other: eA),
          ).dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
            OverlapStayEvent(
              PhysicsOverlap<PhysicsBody>(trigger: eA, other: cB),
            ),
          );
        }
      }
    }
  }
}
