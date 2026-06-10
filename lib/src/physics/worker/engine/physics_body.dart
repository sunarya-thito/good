import 'dart:math' as math;
import 'package:forge2d/forge2d.dart' as f;
import 'package:vector_math/vector_math_64.dart';

// Converts 64-bit Vector2 (goo2d) → 32-bit f.Vector2 (forge2d)
f.Vector2 _fv(Vector2 v) => f.Vector2(v.x, v.y);

// Converts 32-bit f.Vector2 (forge2d) → 64-bit Vector2 (goo2d)
Vector2 _v(f.Vector2 v) => Vector2(v.x, v.y);

/// Thin wrapper around a Forge2D [f.Body], preserving the existing public API.
///
/// Rotation is in RADIANS, matching [ObjectTransform.angle] and Forge2D.
class EngineBody {
  final int handle;

  f.Body? _body;

  // Scalar gravity scale (Forge2D uses Vector2?, so we map scalar→Vector2)
  double _gravityScale = 1.0;

  // Plain fields with no direct Forge2D equivalent
  bool simulated = true;
  bool useAutoMass = false;
  bool useFullKinematicContacts = false;
  int constraints = 0;
  int interpolation = 0;
  int collisionDetectionMode = 0;
  int sleepMode = 0; // 0=startAwake, 1=startAsleep, 2=neverSleep
  int layer = 0;
  int excludeLayers = 0;
  int includeLayers = 0;
  int sharedMaterialHandle = -1;
  bool freezeRotation = false;

  // Attached collider handles
  final List<int> colliderHandles = [];

  EngineBody(this.handle);

  void initForgeBody(f.Body body) {
    _body = body;
    body.userData = handle;
  }

  f.Body? get forgeBody => _body;

  // ---- Position ----

  Vector2 get position {
    final b = _body;
    if (b == null) return Vector2.zero();
    return _v(b.position);
  }

  set position(Vector2 v) {
    final b = _body;
    if (b == null) return;
    b.setTransform(_fv(v), b.angle);
  }

  // ---- Rotation (radians) ----

  double get rotation {
    final b = _body;
    return b == null ? 0.0 : b.angle;
  }

  set rotation(double rad) {
    final b = _body;
    if (b == null) return;
    b.setTransform(f.Vector2(b.position.x, b.position.y), rad);
  }

  // ---- Linear velocity ----

  Vector2 get linearVelocity {
    final b = _body;
    if (b == null) return Vector2.zero();
    return _v(b.linearVelocity);
  }

  set linearVelocity(Vector2 v) {
    _body?.linearVelocity.setValues(v.x, v.y);
  }

  // ---- Angular velocity ----

  double get angularVelocity => _body?.angularVelocity ?? 0.0;
  set angularVelocity(double v) { _body?.angularVelocity = v; }

  // ---- Damping ----

  double get linearDamping => _body?.linearDamping ?? 0.0;
  set linearDamping(double v) { _body?.linearDamping = v; }

  double get angularDamping => _body?.angularDamping ?? 0.0;
  set angularDamping(double v) { _body?.angularDamping = v; }

  // ---- Gravity scale (scalar → Forge2D Vector2?) ----

  double get gravityScale => _gravityScale;

  set gravityScale(double v) {
    _gravityScale = v;
    _body?.gravityScale = v == 1.0 ? null : f.Vector2(v, v);
  }

  // ---- Mass ----

  double get mass => _body?.mass ?? 1.0;

  set mass(double v) {
    final b = _body;
    if (b == null || useAutoMass) return;
    final md = f.MassData()
      ..mass = v
      ..I = b.inertia;
    md.center.setFrom(b.getLocalCenter());
    b.setMassData(md);
  }

  // ---- Inertia ----

  double get inertia => _body?.inertia ?? 0.0;

  set inertia(double v) {
    final b = _body;
    if (b == null || useAutoMass) return;
    final md = f.MassData()
      ..mass = b.mass
      ..I = v;
    md.center.setFrom(b.getLocalCenter());
    b.setMassData(md);
  }

  // ---- Body type ----

  int _bodyType = 0; // 0=dynamic, 1=static, 2=kinematic

  int get bodyType => _bodyType;

  set bodyType(int v) {
    _bodyType = v;
    _body?.setType(_toForgeType(v));
  }

  static f.BodyType _toForgeType(int t) => switch (t) {
    0 => f.BodyType.dynamic,
    1 => f.BodyType.static,
    2 => f.BodyType.kinematic,
    _ => f.BodyType.dynamic,
  };

  // ---- Center of mass ----

  Vector2 get centerOfMass {
    final b = _body;
    if (b == null) return Vector2.zero();
    return _v(b.getLocalCenter());
  }

  set centerOfMass(Vector2 v) {
    final b = _body;
    if (b == null) return;
    final md = f.MassData()
      ..mass = b.mass
      ..I = b.inertia;
    md.center.setFrom(_fv(v));
    b.setMassData(md);
  }

  Vector2 get worldCenterOfMass {
    final b = _body;
    if (b == null) return Vector2.zero();
    return _v(b.worldCenter);
  }

  // ---- Force / torque (write-only accumulation) ----

  Vector2 get totalForce => Vector2.zero();

  set totalForce(Vector2 v) {
    _body?.applyForce(_fv(v));
  }

  double get totalTorque => 0.0;

  set totalTorque(double v) {
    _body?.applyTorque(v);
  }

  // ---- Sleep ----

  bool get isAwake => _body?.isAwake ?? true;
  bool get isSleeping => !isAwake;

  void wake() => _body?.setAwake(true);
  void putToSleep() => _body?.setAwake(false);

  // ---- Force application ----

  void addForce(Vector2 force, int mode) {
    final b = _body;
    if (b == null) return;
    if (mode == 0) {
      b.applyLinearImpulse(_fv(force), wake: true);
    } else {
      b.applyForce(_fv(force));
    }
  }

  void addForceAtPosition(Vector2 force, Vector2 point, int mode) {
    final b = _body;
    if (b == null) return;
    if (mode == 0) {
      b.applyLinearImpulse(_fv(force), point: _fv(point), wake: true);
    } else {
      b.applyForce(_fv(force), point: _fv(point));
    }
  }

  void addTorque(double torque, int mode) {
    final b = _body;
    if (b == null) return;
    if (mode == 0) {
      b.applyAngularImpulse(torque);
    } else {
      b.applyTorque(torque);
    }
  }

  void addRelativeForce(Vector2 relativeForce, int mode) {
    final b = _body;
    if (b == null) return;
    final rad = b.angle;
    final c = math.cos(rad);
    final s = math.sin(rad);
    final worldForce = Vector2(
      relativeForce.x * c - relativeForce.y * s,
      relativeForce.x * s + relativeForce.y * c,
    );
    addForce(worldForce, mode);
  }

  // ---- Movement ----

  void movePosition(Vector2 target) {
    final b = _body;
    if (b == null) return;
    b.setTransform(_fv(target), b.angle);
  }

  void moveRotation(double rad) {
    final b = _body;
    if (b == null) return;
    b.setTransform(f.Vector2(b.position.x, b.position.y), rad);
  }

  void movePositionAndRotation(Vector2 target, double rad) {
    final b = _body;
    if (b == null) return;
    b.setTransform(_fv(target), rad);
  }

  void setRotation(double rad) => moveRotation(rad);

  // ---- World/local space helpers ----

  Vector2 getPoint(Vector2 worldPoint) {
    final b = _body;
    if (b == null) return worldPoint.clone();
    return _v(b.localPoint(_fv(worldPoint)));
  }

  Vector2 getRelativePoint(Vector2 localPoint) {
    final b = _body;
    if (b == null) return localPoint.clone();
    return _v(b.worldPoint(_fv(localPoint)));
  }

  Vector2 getVector(Vector2 worldVector) {
    final b = _body;
    if (b == null) return worldVector.clone();
    return _v(b.localVector(_fv(worldVector)));
  }

  Vector2 getRelativeVector(Vector2 localVector) {
    final b = _body;
    if (b == null) return localVector.clone();
    return _v(b.worldVector(_fv(localVector)));
  }

  Vector2 getPointVelocity(Vector2 worldPoint) {
    final b = _body;
    if (b == null) return Vector2.zero();
    return _v(b.linearVelocityFromWorldPoint(_fv(worldPoint)));
  }

  Vector2 getRelativePointVelocity(Vector2 localPoint) =>
      getPointVelocity(getRelativePoint(localPoint));
}
