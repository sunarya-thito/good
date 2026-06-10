import 'package:flutter/foundation.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/physics/worker/physics_worker.dart';
import 'package:goo2d/src/physics/worker/data/contact_delta.dart';
import 'package:goo2d/src/physics/worker/direct/direct_body_ops.dart';
import 'package:goo2d/src/physics/worker/direct/direct_physics_worker.dart';
import 'package:goo2d/src/physics/worker/isolate/isolate_physics_worker.dart';

/// The [GameSystem] that manages the physics worker lifecycle and dispatches
/// per-frame collision and trigger events to [PhysicsContactListener] components.
class PhysicsSystem implements GameSystem {
  static bool _isInitialized = false;
  static PhysicsWorker? _worker;

  GameEngine? _game;
  static PhysicsSystem? _instance;

  /// The active [PhysicsSystem] instance, available after [initialize].
  static PhysicsSystem get instance {
    assert(_instance != null, 'PhysicsSystem has not been attached to a game.');
    return _instance!;
  }

  /// Returns the active instance, or null if not currently attached to a game.
  /// Safe to call across async gaps where the game engine may have been disposed.
  static PhysicsSystem? get maybeInstance => _instance;

  // Registered ECS world — when set, PhysicsWorldSystem owns the tick.
  static Object? _ecsWorld;

  final bool _forceDirectWorker;

  PhysicsSystem({bool forceDirectWorker = false})
      : _forceDirectWorker = forceDirectWorker;

  PhysicsWorker get worker {
    assert(_worker != null, 'PhysicsSystem has not been initialized.');
    return _worker!;
  }

  static bool get platformSupportsIsolate => !kIsWeb;

  @override
  GameEngine get game => _game!;

  @override
  bool get gameAttached => _game != null;

  @override
  Future<void> attach(GameEngine game) async {
    _game = game;
    _instance = this;
    if (!_isInitialized) {
      _worker = (!_forceDirectWorker && platformSupportsIsolate)
          ? IsolatePhysicsWorker()
          : DirectPhysicsWorker();
      await _worker!.initialize();
      Physics.initialize(_worker!);
      _isInitialized = true;
    }
  }

  // ── ECS world registration ──────────────────────────────────────────────

  static void registerEcsWorld(Object world) => _ecsWorld = world;
  static void unregisterEcsWorld() => _ecsWorld = null;

  // ── Step ────────────────────────────────────────────────────────────────

  /// Advances the simulation by one fixed tick.
  /// When a PhysicsWorldSystem is attached, this is a no-op (ECS owns the tick).
  Future<void> step() async {
    if (_worker == null) return;
    if (_ecsWorld != null) return;
    final dt = _game!.getSystem<TickerState>()!.fixedDeltaTime;
    final delta = await stepWithDelta(dt);
    await _dispatchEcEventsFromDelta(delta);
  }

  /// Advances the simulation and returns the contact delta.
  /// Used directly by [PhysicsWorldSystem]; EC-only games go through [step()].
  Future<ContactDelta> stepWithDelta(double dt) async {
    await _syncTransformsToPhysics();
    final delta = await _worker!.stepWithContactDelta(dt);
    await _syncTransformsFromPhysics();
    return delta;
  }

  // ── Transform sync ──────────────────────────────────────────────────────

  Future<void> _syncTransformsToPhysics() async {
    if (_worker == null) return;
    final entries = _rigidbodyRegistry.entries.toList();
    for (final entry in entries) {
      final rb = entry.value;
      if (!rb.isAttached || rb.bodyType != RigidbodyType.kinematic) continue;
      final transform = rb.gameObject.tryGetComponent<ObjectTransform>();
      if (transform == null) continue;
      await _worker!.bodyMovePositionAndRotation(
        entry.key,
        transform.position,
        transform.angle,
      );
    }
  }

  Future<void> _syncTransformsFromPhysics() async {
    if (_worker == null) return;
    final entries = _rigidbodyRegistry.entries.toList();
    for (final entry in entries) {
      final rb = entry.value;
      if (!rb.isAttached || rb.bodyType != RigidbodyType.dynamic) continue;
      final pos =
          (await _worker!.getBodyProperty(entry.key, BodyProp.position))
              as Vector2;
      final rot =
          (await _worker!.getBodyProperty(entry.key, BodyProp.rotation))
              as double;
      rb.gameObject.tryGetComponent<ObjectTransform>()
        ?..position = pos
        ..angle = rot;
    }
  }

  // ── EC-only event dispatch (fallback when no PhysicsWorldSystem) ────────

  Future<void> _dispatchEcEventsFromDelta(ContactDelta delta) async {
    const hasC = true;
    const hasPB = true;

    // Solid contacts
    await _dispatchContactList(
      delta.enterContacts, delta.contactPoints, delta.contactPointCounts,
      isEnter: true, hasC: hasC, hasPB: hasPB,
    );
    await _dispatchContactList(
      delta.stayContacts, null, null,
      isEnter: false, hasC: hasC, hasPB: hasPB,
    );
    await _dispatchExitList(delta.exitContacts, isContact: true, hasC: hasC, hasPB: hasPB);

    // Triggers
    await _dispatchOverlapList(delta.enterTriggers, isEnter: true, hasC: hasC, hasPB: hasPB);
    await _dispatchOverlapList(delta.stayTriggers, isEnter: false, hasC: hasC, hasPB: hasPB);
    await _dispatchExitList(delta.exitTriggers, isContact: false, hasC: hasC, hasPB: hasPB);
  }

  Future<void> _dispatchContactList(
    Int32List pairs,
    Float32List? rawPoints,
    Int32List? pointCounts,
    {required bool isEnter, required bool hasC, required bool hasPB}
  ) async {
    final pairCount = pairs.length ~/ 2;
    var ptOffset = 0;
    for (var i = 0; i < pairCount; i++) {
      final hA = pairs[i * 2], hB = pairs[i * 2 + 1];
      final cA = _colliderRegistry[hA];
      final cB = _colliderRegistry[hB];

      List<PhysicsContactPoint> pts = const [];
      if (isEnter && rawPoints != null && pointCounts != null) {
        final n = pointCounts[i];
        if (n > 0) {
          pts = List.generate(n, (j) {
            final base = (ptOffset + j) * ContactDelta.floatsPerPoint;
            return PhysicsContactPoint(
              point: Vector2(rawPoints[base].toDouble(), rawPoints[base + 1].toDouble()),
              normal: Vector2(rawPoints[base + 2].toDouble(), rawPoints[base + 3].toDouble()),
              separation: rawPoints[base + 4].toDouble(),
              normalImpulse: rawPoints[base + 5].toDouble(),
              tangentImpulse: rawPoints[base + 6].toDouble(),
            );
          });
          ptOffset += n;
        }
      }

      if (cA != null && cB != null && cA.isAttached && cB.isAttached) {
        if (hasC) {
          if (isEnter) {
            await ContactEnterEvent(PhysicsContact<Collider>(bodyA: cA, bodyB: cB, contacts: pts))
                .dispatchTo(cA.gameObject);
            await ContactEnterEvent(PhysicsContact<Collider>(bodyA: cB, bodyB: cA, contacts: pts))
                .dispatchTo(cB.gameObject);
          } else {
            await ContactStayEvent(PhysicsContact<Collider>(bodyA: cA, bodyB: cB))
                .dispatchTo(cA.gameObject);
            await ContactStayEvent(PhysicsContact<Collider>(bodyA: cB, bodyB: cA))
                .dispatchTo(cB.gameObject);
          }
        }
        if (hasPB) {
          if (isEnter) {
            await ContactEnterEvent(PhysicsContact<PhysicsBody>(bodyA: cA, bodyB: cB, contacts: pts))
                .dispatchTo(cA.gameObject);
            await ContactEnterEvent(PhysicsContact<PhysicsBody>(bodyA: cB, bodyB: cA, contacts: pts))
                .dispatchTo(cB.gameObject);
          } else {
            await ContactStayEvent(PhysicsContact<PhysicsBody>(bodyA: cA, bodyB: cB))
                .dispatchTo(cA.gameObject);
            await ContactStayEvent(PhysicsContact<PhysicsBody>(bodyA: cB, bodyB: cA))
                .dispatchTo(cB.gameObject);
          }
        }
      }
    }
  }

  Future<void> _dispatchExitList(
    Int32List pairs, {required bool isContact, required bool hasC, required bool hasPB}
  ) async {
    final pairCount = pairs.length ~/ 2;
    for (var i = 0; i < pairCount; i++) {
      final hA = pairs[i * 2], hB = pairs[i * 2 + 1];
      final cA = _colliderRegistry[hA];
      final cB = _colliderRegistry[hB];
      if (cA == null || cB == null) continue;
      if (!cA.isAttached || !cB.isAttached) continue;

      if (isContact) {
        if (hasC) {
          await ContactExitEvent(PhysicsContact<Collider>(bodyA: cA, bodyB: cB))
              .dispatchTo(cA.gameObject);
          await ContactExitEvent(PhysicsContact<Collider>(bodyA: cB, bodyB: cA))
              .dispatchTo(cB.gameObject);
        }
        if (hasPB) {
          await ContactExitEvent(PhysicsContact<PhysicsBody>(bodyA: cA, bodyB: cB))
              .dispatchTo(cA.gameObject);
          await ContactExitEvent(PhysicsContact<PhysicsBody>(bodyA: cB, bodyB: cA))
              .dispatchTo(cB.gameObject);
        }
      } else {
        if (hasC) {
          await OverlapExitEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB))
              .dispatchTo(cA.gameObject);
          await OverlapExitEvent(PhysicsOverlap<Collider>(trigger: cB, other: cA))
              .dispatchTo(cB.gameObject);
        }
        if (hasPB) {
          await OverlapExitEvent(PhysicsOverlap<PhysicsBody>(trigger: cA, other: cB))
              .dispatchTo(cA.gameObject);
          await OverlapExitEvent(PhysicsOverlap<PhysicsBody>(trigger: cB, other: cA))
              .dispatchTo(cB.gameObject);
        }
      }
    }
  }

  Future<void> _dispatchOverlapList(
    Int32List pairs, {required bool isEnter, required bool hasC, required bool hasPB}
  ) async {
    final pairCount = pairs.length ~/ 2;
    for (var i = 0; i < pairCount; i++) {
      final hA = pairs[i * 2], hB = pairs[i * 2 + 1];
      final cA = _colliderRegistry[hA];
      final cB = _colliderRegistry[hB];
      if (cA == null || cB == null) continue;
      if (!cA.isAttached || !cB.isAttached) continue;

      if (hasC) {
        if (isEnter) {
          await OverlapEnterEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB)).dispatchTo(cA.gameObject);
          await OverlapEnterEvent(PhysicsOverlap<Collider>(trigger: cB, other: cA)).dispatchTo(cB.gameObject);
        } else {
          await OverlapStayEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB)).dispatchTo(cA.gameObject);
          await OverlapStayEvent(PhysicsOverlap<Collider>(trigger: cB, other: cA)).dispatchTo(cB.gameObject);
        }
      }
      if (hasPB) {
        if (isEnter) {
          await OverlapEnterEvent(PhysicsOverlap<PhysicsBody>(trigger: cA, other: cB)).dispatchTo(cA.gameObject);
          await OverlapEnterEvent(PhysicsOverlap<PhysicsBody>(trigger: cB, other: cA)).dispatchTo(cB.gameObject);
        } else {
          await OverlapStayEvent(PhysicsOverlap<PhysicsBody>(trigger: cA, other: cB)).dispatchTo(cA.gameObject);
          await OverlapStayEvent(PhysicsOverlap<PhysicsBody>(trigger: cB, other: cA)).dispatchTo(cB.gameObject);
        }
      }
    }
  }

  @override
  Future<void> dispose() async {
    _worker?.dispose();
    _worker = null;
    _isInitialized = false;
    _instance = null;
    _ecsWorld = null;
    _colliderRegistry.clear();
    _rigidbodyRegistry.clear();
    _game = null;
  }

  // ── Collider registry ────────────────────────────────────────────────────

  static final Map<int, Collider> _colliderRegistry = {};

  static void registerCollider(int handle, Collider collider) =>
      _colliderRegistry[handle] = collider;

  static void unregisterCollider(int handle, Collider collider) {
    if (_colliderRegistry[handle] == collider) _colliderRegistry.remove(handle);
  }

  static Collider? getCollider(int handle) => _colliderRegistry[handle];

  Iterable<Collider> get activeColliders => _colliderRegistry.values;

  // ── Rigidbody registry ───────────────────────────────────────────────────

  static final Map<int, Rigidbody> _rigidbodyRegistry = {};

  static void registerRigidbody(int handle, Rigidbody rb) =>
      _rigidbodyRegistry[handle] = rb;

  static void unregisterRigidbody(int handle, Rigidbody rb) {
    if (_rigidbodyRegistry[handle] == rb) _rigidbodyRegistry.remove(handle);
  }

  static Rigidbody? getRigidbody(int handle) => _rigidbodyRegistry[handle];
}
