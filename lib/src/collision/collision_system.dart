import 'package:flutter/foundation.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/collision/worker/collision_delta.dart';
import 'package:goo2d/src/collision/worker/collision_worker.dart';
import 'package:goo2d/src/collision/worker/direct/direct_collision_worker.dart';
import 'package:goo2d/src/collision/worker/isolate/isolate_collision_worker.dart';

/// The [GameSystem] that manages the collision worker lifecycle and dispatches
/// per-frame overlap events to [PhysicsContactListener] components.
///
/// [CollisionSystem] is mutually exclusive with [PhysicsSystem] — add one or
/// the other to [GameEngine], not both. Unlike [PhysicsSystem], no [Rigidbody]
/// is required: EC [Collider] components register directly with this system.
///
/// Overlap events use the same [PhysicsContactListener] mixin already used by
/// the physics system, so switching engines requires no EC-component changes:
/// - [PhysicsContactListener.onOverlapEnter]
/// - [PhysicsContactListener.onOverlapStay]
/// - [PhysicsContactListener.onOverlapExit]
class CollisionSystem implements GameSystem {
  bool _isInitialized = false;
  CollisionWorker? _worker;
  Object? _ecsWorld;

  GameEngine? _game;

  final bool _forceDirectWorker;

  CollisionSystem({bool forceDirectWorker = false})
      : _forceDirectWorker = forceDirectWorker;

  static bool get platformSupportsIsolate => !kIsWeb;

  CollisionWorker get worker {
    assert(_worker != null, 'CollisionSystem has not been initialized.');
    return _worker!;
  }

  @override
  GameEngine get game => _game!;

  @override
  bool get gameAttached => _game != null;

  @override
  Future<void> attach(GameEngine game) async {
    assert(
      game.getSystem<PhysicsSystem>() == null,
      'CollisionSystem and PhysicsSystem cannot run simultaneously. '
      'Remove PhysicsSystem before adding CollisionSystem.',
    );
    _game = game;
    if (!_isInitialized) {
      _worker = (!_forceDirectWorker && platformSupportsIsolate)
          ? IsolateCollisionWorker()
          : DirectCollisionWorker();
      await _worker!.initialize();
      _isInitialized = true;
    }
  }

  @override
  Future<void> dispose() async {
    _worker?.dispose();
    _worker = null;
    _isInitialized = false;
    _ecsWorld = null;
    _clearColliderRegistry();
    _game = null;
  }

  // ── ECS world registration ──────────────────────────────────────────────

  void registerEcsWorld(Object world) => _ecsWorld = world;
  void unregisterEcsWorld() => _ecsWorld = null;

  // ── Step ────────────────────────────────────────────────────────────────

  Future<void> step() async {
    if (_worker == null) return;
    if (_ecsWorld != null) return; // ECS world owns the tick
    _syncEcTransforms();
    final delta = await _worker!.step();
    if (_game == null) return; // disposed mid-await
    await _dispatchEcEvents(delta);
  }

  // ── EC transform sync ────────────────────────────────────────────────────

  void _syncEcTransforms() {
    // Iterate registry by index — safe during async gaps (slot set to null)
    for (var i = 0; i < _registryCap; i++) {
      if (_registryHandles[i] == -1) continue;
      final collider = _registryValues[i];
      if (collider == null || !collider.isAttached) continue;
      final t = collider.gameObject.tryGetComponent<ObjectTransform>();
      if (t == null) continue;
      _worker!.setShapeTransform(
          _registryHandles[i], t.position.x, t.position.y, t.angle);
    }
  }

  // ── Event dispatch ────────────────────────────────────────────────────────

  Future<void> _dispatchEcEvents(CollisionDelta delta) async {
    await _dispatchPairs(delta.enterPairs, isEnter: true, isExit: false);
    await _dispatchPairs(delta.stayPairs, isEnter: false, isExit: false);
    await _dispatchPairs(delta.exitPairs, isEnter: false, isExit: true);
  }

  Future<void> _dispatchPairs(
      Int32List pairs, {required bool isEnter, required bool isExit}) async {
    final pairCount = pairs.length ~/ 2;
    for (var i = 0; i < pairCount; i++) {
      final hA = pairs[i * 2], hB = pairs[i * 2 + 1];
      final cA = getCollider(hA);
      final cB = getCollider(hB);
      if (cA == null || cB == null) continue;
      if (!cA.isAttached || !cB.isAttached) continue;

      if (isExit) {
        await OverlapExitEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB))
            .dispatchTo(cA.gameObject);
        await OverlapExitEvent(PhysicsOverlap<Collider>(trigger: cB, other: cA))
            .dispatchTo(cB.gameObject);
      } else if (isEnter) {
        await OverlapEnterEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB))
            .dispatchTo(cA.gameObject);
        await OverlapEnterEvent(PhysicsOverlap<Collider>(trigger: cB, other: cA))
            .dispatchTo(cB.gameObject);
      } else {
        await OverlapStayEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB))
            .dispatchTo(cA.gameObject);
        await OverlapStayEvent(PhysicsOverlap<Collider>(trigger: cB, other: cA))
            .dispatchTo(cB.gameObject);
      }
    }
  }

  // ── EC Collider registry (open-addressing hash table, no Map) ────────────
  //
  // Two parallel arrays: _registryHandles (key) and _registryValues (value).
  // -1 in _registryHandles means the slot is empty.
  // Iteration by index is safe across async gaps (deleted slots become -1).

  Int32List _registryHandles = Int32List(128)..fillRange(0, 128, -1);
  List<Collider?> _registryValues = List.filled(128, null);
  int _registryCap = 128;
  int _registryMask = 127;
  int _registryCount = 0;

  int _regHash(int h) => (h * 0x9E3779B9) & _registryMask;

  void registerCollider(int handle, Collider collider) {
    if (_registryCount >= _registryCap * 3 ~/ 4) _growRegistry();
    var bucket = _regHash(handle);
    while (_registryHandles[bucket] != -1 &&
        _registryHandles[bucket] != handle) {
      bucket = (bucket + 1) & _registryMask;
    }
    _registryHandles[bucket] = handle;
    _registryValues[bucket] = collider;
    _registryCount++;
  }

  void unregisterCollider(int handle) {
    var bucket = _regHash(handle);
    while (true) {
      final h = _registryHandles[bucket];
      if (h == -1) return;
      if (h == handle) {
        _registryHandles[bucket] = -1;
        _registryValues[bucket] = null;
        _registryCount--;
        return;
      }
      bucket = (bucket + 1) & _registryMask;
    }
  }

  Collider? getCollider(int handle) {
    var bucket = _regHash(handle);
    while (true) {
      final h = _registryHandles[bucket];
      if (h == -1) return null;
      if (h == handle) return _registryValues[bucket];
      bucket = (bucket + 1) & _registryMask;
    }
  }

  void _growRegistry() {
    final newCap = _registryCap * 2;
    final newMask = newCap - 1;
    final newHandles = Int32List(newCap)..fillRange(0, newCap, -1);
    final newValues = List<Collider?>.filled(newCap, null);
    for (var i = 0; i < _registryCap; i++) {
      final h = _registryHandles[i];
      if (h == -1) continue;
      var bucket = (h * 0x9E3779B9) & newMask;
      while (newHandles[bucket] != -1) {
        bucket = (bucket + 1) & newMask;
      }
      newHandles[bucket] = h;
      newValues[bucket] = _registryValues[i];
    }
    _registryCap = newCap;
    _registryMask = newMask;
    _registryHandles = newHandles;
    _registryValues = newValues;
  }

  void _clearColliderRegistry() {
    _registryHandles.fillRange(0, _registryCap, -1);
    for (var i = 0; i < _registryCap; i++) {
      _registryValues[i] = null;
    }
    _registryCount = 0;
  }
}
