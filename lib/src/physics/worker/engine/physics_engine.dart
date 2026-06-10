import 'dart:math' as math;
import 'dart:typed_data';
import 'package:forge2d/forge2d.dart' as f;
import 'package:forge2d/src/settings.dart' as f_settings; // ignore: implementation_imports
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/worker/engine/physics_body.dart';
import 'package:goo2d/src/physics/worker/engine/physics_collider.dart';
import 'package:goo2d/src/physics/worker/engine/physics_joint.dart';
import 'package:goo2d/src/physics/worker/engine/physics_effector.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/src/physics/worker/data/contact_delta.dart';
import 'package:goo2d/src/physics/worker/data/raycast_hit_data.dart';
import 'package:goo2d/src/physics/worker/data/contact_point_data.dart';

f.Vector2 _fv(Vector2 v) => f.Vector2(v.x, v.y);
Vector2 _v(f.Vector2 v) => Vector2(v.x, v.y);

// ===================== Query helpers =====================

class _FnQueryCallback extends f.QueryCallback {
  final bool Function(f.Fixture) fn;
  _FnQueryCallback(this.fn);
  @override
  bool reportFixture(f.Fixture fixture) => fn(fixture);
}

class _FnRayCastCallback extends f.RayCastCallback {
  final double Function(f.Fixture, f.Vector2, f.Vector2, double) fn;
  _FnRayCastCallback(this.fn);
  @override
  double reportFixture(
    f.Fixture fixture,
    f.Vector2 point,
    f.Vector2 normal,
    double fraction,
  ) =>
      fn(fixture, point, normal, fraction);
}

bool _matchesLayer(int mask, int layer) =>
    mask == -1 || (mask & (1 << layer)) != 0;

bool _fixturePassesFilter(f.Fixture fixture, PhysicsEngine engine, int layerMask) {
  final cHandle = fixture.userData as int?;
  if (cHandle == null) return false;
  final collider = engine.colliders[cHandle];
  if (collider == null) return false;
  final body = engine.bodies[collider.bodyHandle];
  if (body == null || !body.simulated) return false;
  if (fixture.isSensor && !engine.queriesHitTriggers) return false;
  final layer = collider.layer != 0 ? collider.layer : body.layer;
  return _matchesLayer(layerMask, layer);
}

// ===================== Contact Filter =====================

class _LayerContactFilter extends f.ContactFilter {
  final PhysicsEngine engine;
  _LayerContactFilter(this.engine);

  @override
  bool shouldCollide(f.Fixture fixtureA, f.Fixture fixtureB) {
    final cA = fixtureA.userData as int?;
    final cB = fixtureB.userData as int?;
    if (cA == null || cB == null) return true;

    final colliderA = engine.colliders[cA];
    final colliderB = engine.colliders[cB];
    if (colliderA == null || colliderB == null) return true;

    // No self-collision
    if (colliderA.bodyHandle == colliderB.bodyHandle) return false;

    // Check ignored pairs
    final lo = math.min(cA, cB);
    final hi = math.max(cA, cB);
    if (engine.ignoredColliderPairs.contains((lo, hi))) return false;

    final bodyA = engine.bodies[colliderA.bodyHandle];
    final bodyB = engine.bodies[colliderB.bodyHandle];
    if (bodyA == null || bodyB == null) return true;

    final layerA = colliderA.layer != 0 ? colliderA.layer : bodyA.layer;
    final layerB = colliderB.layer != 0 ? colliderB.layer : bodyB.layer;

    // 32-layer collision matrix
    if ((engine.layerCollisionMask[layerA] & (1 << layerB)) == 0) return false;
    if ((engine.layerCollisionMask[layerB] & (1 << layerA)) == 0) return false;

    // Collider-level excludeLayers
    if (colliderA.excludeLayers != 0 &&
        (colliderA.excludeLayers & (1 << layerB)) != 0) { return false; }
    if (colliderB.excludeLayers != 0 &&
        (colliderB.excludeLayers & (1 << layerA)) != 0) { return false; }

    return true;
  }
}

// ===================== Contact Listener =====================

class EngineContactListener extends f.ContactListener {
  // bidirectional lookup for legacy getTouchingColliders / getContactPoints
  final Map<int, Set<int>> _activeContacts = {};
  // normalized (min, max) pair sets — diffed each frame
  final Set<(int, int)> _activeContactPairs = {};
  final Set<(int, int)> _activeTriggerPairs = {};
  Set<(int, int)> _prevContactPairs = {};
  Set<(int, int)> _prevTriggerPairs = {};
  // (min, max) → contact point data from last postSolve
  final Map<(int, int), List<ContactPointData>> _contactPoints = {};

  @override
  void beginContact(f.Contact contact) {
    final cA = contact.fixtureA.userData as int?;
    final cB = contact.fixtureB.userData as int?;
    if (cA == null || cB == null) return;
    final key = (math.min(cA, cB), math.max(cA, cB));
    if (contact.fixtureA.isSensor || contact.fixtureB.isSensor) {
      _activeTriggerPairs.add(key);
    } else {
      _activeContactPairs.add(key);
      (_activeContacts[cA] ??= {}).add(cB);
      (_activeContacts[cB] ??= {}).add(cA);
    }
  }

  @override
  void endContact(f.Contact contact) {
    final cA = contact.fixtureA.userData as int?;
    final cB = contact.fixtureB.userData as int?;
    if (cA == null || cB == null) return;
    final key = (math.min(cA, cB), math.max(cA, cB));
    if (contact.fixtureA.isSensor || contact.fixtureB.isSensor) {
      _activeTriggerPairs.remove(key);
    } else {
      _activeContactPairs.remove(key);
      _activeContacts[cA]?.remove(cB);
      _activeContacts[cB]?.remove(cA);
      _contactPoints.remove(key);
    }
  }

  @override
  void postSolve(f.Contact contact, f.ContactImpulse impulse) {
    final cA = contact.fixtureA.userData as int?;
    final cB = contact.fixtureB.userData as int?;
    if (cA == null || cB == null) return;

    final wm = f.WorldManifold();
    wm.initialize(
      contact.manifold,
      contact.fixtureA.body.transform,
      contact.fixtureA.shape.radius,
      contact.fixtureB.body.transform,
      contact.fixtureB.shape.radius,
    );

    final pts = <ContactPointData>[];
    final count = contact.manifold.pointCount;
    for (var i = 0; i < count; i++) {
      final pt = wm.points[i];
      pts.add(ContactPointData(
        point: Vector2(pt.x, pt.y),
        normal: Vector2(wm.normal.x, wm.normal.y),
        relativeVelocity: Vector2.zero(),
        separation: wm.separations[i],
        normalImpulse: i < impulse.count ? impulse.normalImpulses[i] : 0.0,
        tangentImpulse: i < impulse.count ? impulse.tangentImpulses[i] : 0.0,
        colliderHandle: cA,
        otherColliderHandle: cB,
      ));
    }
    final key = (math.min(cA, cB), math.max(cA, cB));
    _contactPoints[key] = pts;
  }

  ContactDelta buildContactDelta() {
    final enterC = _activeContactPairs.difference(_prevContactPairs).toList();
    final stayC = _activeContactPairs.intersection(_prevContactPairs).toList();
    final exitC = _prevContactPairs.difference(_activeContactPairs).toList();
    final enterT = _activeTriggerPairs.difference(_prevTriggerPairs).toList();
    final stayT = _activeTriggerPairs.intersection(_prevTriggerPairs).toList();
    final exitT = _prevTriggerPairs.difference(_activeTriggerPairs).toList();

    _prevContactPairs = Set.of(_activeContactPairs);
    _prevTriggerPairs = Set.of(_activeTriggerPairs);

    // Serialize pairs to flat Int32Lists
    Int32List serializePairs(List<(int, int)> list) {
      final buf = Int32List(list.length * 2);
      for (var i = 0; i < list.length; i++) {
        buf[i * 2] = list[i].$1;
        buf[i * 2 + 1] = list[i].$2;
      }
      return buf;
    }

    // Contact points for solid enter pairs only
    var totalPoints = 0;
    final counts = Int32List(enterC.length);
    for (var i = 0; i < enterC.length; i++) {
      final n = _contactPoints[enterC[i]]?.length ?? 0;
      counts[i] = n;
      totalPoints += n;
    }
    final pts = Float32List(totalPoints * ContactDelta.floatsPerPoint);
    var offset = 0;
    for (var i = 0; i < enterC.length; i++) {
      final cpList = _contactPoints[enterC[i]];
      if (cpList == null) continue;
      for (final cp in cpList) {
        pts[offset++] = cp.point.x;
        pts[offset++] = cp.point.y;
        pts[offset++] = cp.normal.x;
        pts[offset++] = cp.normal.y;
        pts[offset++] = cp.separation;
        pts[offset++] = cp.normalImpulse;
        pts[offset++] = cp.tangentImpulse;
      }
    }

    return ContactDelta(
      enterContacts: serializePairs(enterC),
      stayContacts: serializePairs(stayC),
      exitContacts: serializePairs(exitC),
      enterTriggers: serializePairs(enterT),
      stayTriggers: serializePairs(stayT),
      exitTriggers: serializePairs(exitT),
      contactPoints: pts,
      contactPointCounts: counts,
    );
  }

  Set<int> getTouchingColliders(int handle) =>
      _activeContacts[handle] ?? const {};

  List<ContactPointData> getContactPoints(int handle) {
    final results = <ContactPointData>[];
    for (final entry in _contactPoints.entries) {
      final (a, b) = entry.key;
      if (a == handle || b == handle) results.addAll(entry.value);
    }
    return results;
  }
}

// ===================== PhysicsEngine =====================

/// The core 2D physics simulation engine — a thin facade over Forge2D.
///
/// Both [DirectPhysicsWorker] and [IsolatePhysicsWorker] delegate to this.
class PhysicsEngine {
  // --- Global Settings ---
  Vector2 gravity = Vector2(0, -9.81);
  bool callbacksOnDisable = true;
  double bounceThreshold = 1.0;
  double contactThreshold = 0.01;
  double baumgarteTOIScale = 0.75;
  double baumgarteScale = 0.2;
  double angularSleepTolerance = 2.0;
  double linearSleepTolerance = 0.01;
  double defaultContactOffset = 0.01;
  double maxAngularCorrection = 8.0;
  double maxLinearCorrection = 0.2;
  double maxRotationSpeed = 360.0;
  double maxTranslationSpeed = 100.0;
  double minSubStepFPS = 50.0;
  double timeToSleep = 0.5;
  int positionIterations = 3;
  int velocityIterations = 8;
  int maxSubStepCount = 8;
  int maxPolygonShapeVertices = 8;
  int allLayers = ~0;
  int defaultRaycastLayers = ~0;
  int ignoreRaycastLayer = 1 << 2;
  int simulationLayers = ~0;
  int simulationMode = 0;
  bool queriesStartInColliders = true;
  bool queriesHitTriggers = true;
  bool reuseCollisionCallbacks = true;
  bool useSubStepping = false;
  bool useSubStepContacts = false;

  // --- Layer collision matrix (32×32) ---
  final List<int> layerCollisionMask = List.filled(32, ~0);

  // --- Handle storage ---
  int _nextHandle = 1;
  final Map<int, EngineBody> bodies = {};
  final Map<int, PhysicsCollider> colliders = {};
  final Map<int, PhysicsJoint> joints = {};
  final Map<int, PhysicsEffector> effectors = {};

  // --- Collision ignore pairs (ordered: min, max) ---
  final Set<(int, int)> ignoredColliderPairs = {};

  // --- Forge2D internals ---
  late final f.World _world;
  late final f.Body _groundBody; // static anchor for MouseJoint
  final EngineContactListener _contactListener = EngineContactListener();

  PhysicsEngine() {
    _world = f.World(_fv(gravity));
    _world.setContactListener(_contactListener);
    _world.setContactFilter(_LayerContactFilter(this));

    final groundDef = f.BodyDef(type: f.BodyType.static);
    _groundBody = _world.createBody(groundDef);
  }

  int allocHandle() => _nextHandle++;

  // ===================== Body CRUD =====================

  int createBody() {
    final h = allocHandle();
    final def = f.BodyDef(type: f.BodyType.dynamic);
    final fb = _world.createBody(def);
    final body = EngineBody(h);
    body.initForgeBody(fb);
    bodies[h] = body;
    return h;
  }

  void createBodyWithHandle(int h) {
    final def = f.BodyDef(type: f.BodyType.dynamic);
    final fb = _world.createBody(def);
    final body = EngineBody(h);
    body.initForgeBody(fb);
    bodies[h] = body;
  }

  void destroyBody(int handle) {
    final body = bodies.remove(handle);
    if (body == null) return;
    final fb = body.forgeBody;
    if (fb == null) return;

    // Remove joints that reference this body
    joints.removeWhere((_, j) {
      if (j.bodyHandleA == handle || j.bodyHandleB == handle) {
        final fj = j.forgeJoint;
        if (fj != null) _world.destroyJoint(fj);
        return true;
      }
      return false;
    });

    // Clear collider records (fixtures destroyed with body)
    for (final ch in List.of(body.colliderHandles)) {
      colliders.remove(ch);
    }

    _world.destroyBody(fb);
  }

  EngineBody getBody(int handle) => bodies[handle]!;

  // ===================== Collider CRUD =====================

  int createCollider(ColliderShapeType type, int bodyHandle) {
    final h = allocHandle();
    final collider = PhysicsCollider(h, type, bodyHandle);
    colliders[h] = collider;

    final body = bodies[bodyHandle];
    if (body != null) {
      body.colliderHandles.add(h);
      collider.onGeometryChanged = () => _rebuildColliderFixtures(h);
    }

    return h;
  }

  void createColliderWithHandle(int h, ColliderShapeType type, int bodyHandle) {
    final collider = PhysicsCollider(h, type, bodyHandle);
    colliders[h] = collider;
    final body = bodies[bodyHandle];
    if (body != null) {
      body.colliderHandles.add(h);
      collider.onGeometryChanged = () => _rebuildColliderFixtures(h);
    }
  }

  void destroyCollider(int handle) {
    final c = colliders.remove(handle);
    if (c == null) return;

    bodies[c.bodyHandle]?.colliderHandles.remove(handle);

    final fb = bodies[c.bodyHandle]?.forgeBody;
    if (fb != null) {
      for (final fixture in c.fixtures) {
        fb.destroyFixture(fixture);
      }
    }
    c.fixtures.clear();
    c.onGeometryChanged = null;
  }

  PhysicsCollider getCollider(int handle) => colliders[handle]!;

  void _rebuildColliderFixtures(int handle) {
    final collider = colliders[handle];
    if (collider == null) return;
    final body = bodies[collider.bodyHandle];
    if (body == null) return;
    final fb = body.forgeBody;
    if (fb == null) return;

    for (final fixture in collider.fixtures) {
      fb.destroyFixture(fixture);
    }
    collider.fixtures.clear();

    for (final fd in _buildFixtureDefs(collider, handle)) {
      collider.fixtures.add(fb.createFixture(fd));
    }

    if (body.useAutoMass) {
      fb.resetMassData();
    } else {
      final explicitMass = fb.mass;
      fb.resetMassData();
      if (explicitMass > 0.0 && fb.mass > 0.0) {
        final scaledInertia = fb.inertia * (explicitMass / fb.mass);
        final md = f.MassData()
          ..mass = explicitMass
          ..I = scaledInertia;
        md.center.setFrom(fb.getLocalCenter());
        fb.setMassData(md);
      }
    }
  }

  List<f.FixtureDef> _buildFixtureDefs(PhysicsCollider c, int handle) {
    final result = <f.FixtureDef>[];

    void add(f.Shape shape) {
      result.add(f.FixtureDef(
        shape,
        userData: handle,
        density: c.density,
        friction: c.friction,
        restitution: c.bounciness,
        isSensor: c.isTrigger,
      ));
    }

    final off = _fv(c.offset);

    switch (c.shapeType) {
      case ColliderShapeType.box:
        final poly = f.PolygonShape();
        poly.setAsBox(c.boxSize.x * 0.5, c.boxSize.y * 0.5, off, 0.0);
        add(poly);

      case ColliderShapeType.circle:
        final circle = f.CircleShape(radius: c.circleRadius);
        circle.position.setFrom(off);
        add(circle);

      case ColliderShapeType.capsule:
        final w = c.capsuleSize.x;
        final h = c.capsuleSize.y;
        if (c.capsuleDirection == 0) {
          // Vertical
          final r = w * 0.5;
          final halfH = math.max((h - w) * 0.5, 0.0);
          final poly = f.PolygonShape();
          poly.setAsBox(r, halfH > 0 ? halfH : r * 0.01, off, 0.0);
          add(poly);
          final top = f.CircleShape(radius: r);
          top.position.setValues(off.x, off.y + halfH);
          add(top);
          final bot = f.CircleShape(radius: r);
          bot.position.setValues(off.x, off.y - halfH);
          add(bot);
        } else {
          // Horizontal
          final r = h * 0.5;
          final halfW = math.max((w - h) * 0.5, 0.0);
          final poly = f.PolygonShape();
          poly.setAsBox(halfW > 0 ? halfW : r * 0.01, r, off, 0.0);
          add(poly);
          final right = f.CircleShape(radius: r);
          right.position.setValues(off.x + halfW, off.y);
          add(right);
          final left = f.CircleShape(radius: r);
          left.position.setValues(off.x - halfW, off.y);
          add(left);
        }

      case ColliderShapeType.polygon:
        if (c.polygonPoints.length >= 3) {
          final verts = c.polygonPoints.take(8).map(_fv).toList();
          add(f.PolygonShape()..set(verts));
        }

      case ColliderShapeType.edge:
        final pts = c.edgePoints;
        if (pts.length == 2) {
          add(f.EdgeShape()..set(_fv(pts[0]), _fv(pts[1])));
        } else if (pts.length > 2) {
          final chain = f.ChainShape();
          chain.createChain(pts.map(_fv).toList());
          add(chain);
        }

      case ColliderShapeType.composite:
        break; // Handled by sub-colliders
    }

    return result;
  }

  // ===================== Joint CRUD =====================

  int createJoint(int type, int bodyHandleA) {
    final h = allocHandle();
    joints[h] = PhysicsJoint(h, type, bodyHandleA);
    return h;
  }

  void createJointWithHandle(int h, int type, int bodyHandleA) {
    joints[h] = PhysicsJoint(h, type, bodyHandleA);
  }

  void destroyJoint(int handle) {
    final j = joints.remove(handle);
    if (j == null) return;
    final fj = j.forgeJoint;
    if (fj != null) _world.destroyJoint(fj);
  }

  PhysicsJoint getJoint(int handle) => joints[handle]!;

  void _ensureJointCreated(PhysicsJoint j) {
    if (j.forgeJoint != null) return;
    final bA = bodies[j.bodyHandleA]?.forgeBody;
    if (bA == null) return;

    // bodyHandleB < 0 means "anchor to world" — use the static ground body
    final bB = j.bodyHandleB >= 0 ? bodies[j.bodyHandleB]?.forgeBody : _groundBody;
    if (bB == null) return;

    final fj = _createForge2dJoint(j, bA, bB);
    if (fj != null) {
      _world.createJoint(fj);
      j.initForgeJoint(fj);
    }
  }

  f.Joint? _createForge2dJoint(PhysicsJoint j, f.Body bA, f.Body bB) {
    final worldAnchorA = bA.worldPoint(_fv(j.anchor));
    final worldAnchorB = j.autoConfigureConnectedAnchor
        ? worldAnchorA
        : bB.worldPoint(_fv(j.connectedAnchor));

    switch (j.jointType) {
      case 0: // distance
        final def = f.DistanceJointDef()
          ..initialize(bA, bB, worldAnchorA, worldAnchorB)
          ..collideConnected = j.enableCollision;
        if (!j.autoConfigureDistance) def.length = j.distance;
        return f.DistanceJoint(def);

      case 1: // fixed / weld
        final def = f.WeldJointDef()
          ..initialize(bA, bB, worldAnchorA)
          ..collideConnected = j.enableCollision;
        return f.WeldJoint(def);

      case 2: // friction
        final def = f.FrictionJointDef()
          ..initialize(bA, bB, worldAnchorA)
          ..maxForce = j.maxForce
          ..maxTorque = j.maxTorque
          ..collideConnected = j.enableCollision;
        return f.FrictionJoint(def);

      case 3: // hinge / revolute
        final def = f.RevoluteJointDef()
          ..initialize(bA, bB, worldAnchorA)
          ..enableLimit = j.useLimits
          ..lowerAngle = j.lowerAngle * (math.pi / 180.0)
          ..upperAngle = j.upperAngle * (math.pi / 180.0)
          ..enableMotor = j.useMotor
          ..motorSpeed = j.motorSpeed
          ..maxMotorTorque = j.maxMotorTorque
          ..collideConnected = j.enableCollision;
        return f.RevoluteJoint(def);

      case 4: // relative / motor
        final def = f.MotorJointDef()
          ..initialize(bA, bB)
          ..angularOffset = j.angularOffset
          ..correctionFactor = j.correctionScale
          ..collideConnected = j.enableCollision;
        def.linearOffset.setFrom(_fv(j.linearOffset));
        return f.MotorJoint(def);

      case 5: // slider / prismatic
        final angle = j.autoConfigureAngle
            ? 0.0
            : j.sliderAngle * (math.pi / 180.0);
        final axis = f.Vector2(math.cos(angle), math.sin(angle));
        final def = f.PrismaticJointDef()
          ..initialize(bA, bB, worldAnchorA, axis)
          ..enableLimit = j.useTranslationLimits
          ..lowerTranslation = j.lowerTranslation
          ..upperTranslation = j.upperTranslation
          ..collideConnected = j.enableCollision;
        return f.PrismaticJoint(def);

      case 6: // spring (distance + damping)
        final def = f.DistanceJointDef()
          ..initialize(bA, bB, worldAnchorA, worldAnchorB)
          ..frequencyHz = j.springFrequency
          ..dampingRatio = j.springDampingRatio
          ..collideConnected = j.enableCollision;
        if (!j.autoConfigureDistance) def.length = j.distance;
        return f.DistanceJoint(def);

      case 7: // target / mouse
        final def = f.MouseJointDef()
          ..bodyA = _groundBody
          ..bodyB = bA  // bA is the joint-owner body (the body being dragged)
          ..maxForce = j.targetMaxForce
          ..frequencyHz = j.springFrequency
          ..dampingRatio = j.springDampingRatio;
        def.target.setFrom(_fv(j.target));
        return f.MouseJoint(def);

      case 8: // wheel
        final suspAngle = j.wheelSuspensionAngle * (math.pi / 180.0);
        final axis = f.Vector2(math.cos(suspAngle), math.sin(suspAngle));
        final def = f.WheelJointDef()
          ..initialize(bA, bB, worldAnchorA, axis)
          ..frequencyHz = j.springFrequency
          ..dampingRatio = j.springDampingRatio
          ..collideConnected = j.enableCollision;
        return f.WheelJoint(def);

      default:
        return null;
    }
  }

  // ===================== Effector CRUD =====================

  int createEffector(int type) {
    final h = allocHandle();
    effectors[h] = PhysicsEffector(h, type);
    return h;
  }

  void createEffectorWithHandle(int h, int type) {
    effectors[h] = PhysicsEffector(h, type);
  }

  void destroyEffector(int handle) => effectors.remove(handle);
  PhysicsEffector getEffector(int handle) => effectors[handle]!;

  // ===================== Step =====================

  bool step(double dt) {
    _world.gravity.setFrom(_fv(gravity));

    f_settings.velocityIterations = velocityIterations;
    f_settings.positionIterations = positionIterations;

    for (final j in joints.values) {
      _ensureJointCreated(j);
    }

    _world.stepDt(dt);

    _checkJointBreaks();

    return true;
  }

  ContactDelta stepDelta(double dt) {
    step(dt);
    return _contactListener.buildContactDelta();
  }

  void _checkJointBreaks() {
    final broken = <int>[];
    for (final entry in joints.entries) {
      final j = entry.value;
      if (j.forgeJoint == null) continue;
      if (j.reactionForce.length > j.breakForce ||
          j.reactionTorque.abs() > j.breakTorque) {
        broken.add(entry.key);
      }
    }
    for (final h in broken) {
      destroyJoint(h);
    }
  }

  void syncTransforms() {}

  // ===================== Queries =====================

  List<RaycastHitData> raycast(
    Vector2 origin,
    Vector2 direction,
    double distance,
    int layerMask,
    double minDepth,
    double maxDepth,
  ) {
    final results = <RaycastHitData>[];
    final dir = direction.normalized();
    final p1 = _fv(origin);
    final p2 = _fv(origin + dir * distance);

    _world.raycast(
      _FnRayCastCallback((fixture, point, normal, fraction) {
        if (!_fixturePassesFilter(fixture, this, layerMask)) return 1.0;
        final cHandle = fixture.userData as int;
        final collider = colliders[cHandle]!;
        results.add(RaycastHitData(
          point: _v(point),
          normal: _v(normal),
          centroid: bodies[collider.bodyHandle]!.position,
          distance: fraction * distance,
          fraction: fraction,
          colliderHandle: cHandle,
          bodyHandle: collider.bodyHandle,
        ));
        return 1.0;
      }),
      p1,
      p2,
    );

    results.sort((a, b) => a.fraction.compareTo(b.fraction));
    return results;
  }

  List<RaycastHitData> linecast(
    Vector2 start,
    Vector2 end,
    int layerMask,
    double minDepth,
    double maxDepth,
  ) {
    final dir = end - start;
    final dist = dir.length;
    if (dist == 0) return [];
    return raycast(start, dir / dist, dist, layerMask, minDepth, maxDepth);
  }

  List<int> overlapCircle(
    Vector2 point,
    double radius,
    int layerMask,
    double minDepth,
    double maxDepth,
  ) {
    final hits = <int>{};
    final aabb = f.AABB.withVec2(
      f.Vector2(point.x - radius, point.y - radius),
      f.Vector2(point.x + radius, point.y + radius),
    );

    _world.queryAABB(
      _FnQueryCallback((fixture) {
        if (!_fixturePassesFilter(fixture, this, layerMask)) return true;
        final cHandle = fixture.userData as int;
        if (hits.contains(cHandle)) return true;
        final fa = fixture.getAABB(0);
        final cx = point.x.clamp(fa.lowerBound.x, fa.upperBound.x);
        final cy = point.y.clamp(fa.lowerBound.y, fa.upperBound.y);
        final dx = point.x - cx;
        final dy = point.y - cy;
        if (dx * dx + dy * dy <= radius * radius) hits.add(cHandle);
        return true;
      }),
      aabb,
    );

    return hits.toList();
  }

  List<int> overlapBox(
    Vector2 point,
    Vector2 size,
    double angle,
    int layerMask,
    double minDepth,
    double maxDepth,
  ) {
    final hits = <int>{};
    final halfX = size.x * 0.5;
    final halfY = size.y * 0.5;
    final r = math.sqrt(halfX * halfX + halfY * halfY);
    final aabb = f.AABB.withVec2(
      f.Vector2(point.x - r, point.y - r),
      f.Vector2(point.x + r, point.y + r),
    );
    final cosA = math.cos(-angle);
    final sinA = math.sin(-angle);

    _world.queryAABB(
      _FnQueryCallback((fixture) {
        if (!_fixturePassesFilter(fixture, this, layerMask)) return true;
        final cHandle = fixture.userData as int;
        if (hits.contains(cHandle)) return true;
        final fa = fixture.getAABB(0);
        final cx = (fa.lowerBound.x + fa.upperBound.x) * 0.5;
        final cy = (fa.lowerBound.y + fa.upperBound.y) * 0.5;
        final lx = cosA * (cx - point.x) - sinA * (cy - point.y);
        final ly = sinA * (cx - point.x) + cosA * (cy - point.y);
        if (lx.abs() <= halfX && ly.abs() <= halfY) hits.add(cHandle);
        return true;
      }),
      aabb,
    );

    return hits.toList();
  }

  List<int> overlapPoint(
    Vector2 point,
    int layerMask,
    double minDepth,
    double maxDepth,
  ) {
    final hits = <int>{};
    const e = 0.001;
    final fp = _fv(point);
    final aabb = f.AABB.withVec2(
      f.Vector2(point.x - e, point.y - e),
      f.Vector2(point.x + e, point.y + e),
    );

    _world.queryAABB(
      _FnQueryCallback((fixture) {
        if (!_fixturePassesFilter(fixture, this, layerMask)) return true;
        final cHandle = fixture.userData as int;
        if (!hits.contains(cHandle) && fixture.testPoint(fp)) {
          hits.add(cHandle);
        }
        return true;
      }),
      aabb,
    );

    return hits.toList();
  }

  Vector2 closestPoint(Vector2 position, int colliderHandle) {
    final collider = colliders[colliderHandle];
    if (collider == null) return position.clone();

    var bestDist = double.infinity;
    var best = position.clone();

    for (final fixture in collider.fixtures) {
      final aabb = fixture.getAABB(0);
      final cx = position.x.clamp(aabb.lowerBound.x, aabb.upperBound.x);
      final cy = position.y.clamp(aabb.lowerBound.y, aabb.upperBound.y);
      final candidate = Vector2(cx.toDouble(), cy.toDouble());
      final dist = (candidate - position).length;
      if (dist < bestDist) {
        bestDist = dist;
        best = candidate;
      }
    }

    return best;
  }

  double distanceBetween(int colliderA, int colliderB) {
    final cA = colliders[colliderA];
    final cB = colliders[colliderB];
    if (cA == null || cB == null) return double.maxFinite;
    final bA = bodies[cA.bodyHandle];
    if (bA == null) return double.maxFinite;
    final cpA = closestPoint(bA.position + cA.offset, colliderB);
    final bB = bodies[cB.bodyHandle];
    if (bB == null) return double.maxFinite;
    final cpB = closestPoint(bB.position + cB.offset, colliderA);
    return (cpA - cpB).length;
  }

  bool isTouching(int colliderA, int colliderB) =>
      _contactListener.getTouchingColliders(colliderA).contains(colliderB);

  bool isTouchingLayers(int colliderHandle, int layerMask) {
    for (final other in _contactListener.getTouchingColliders(colliderHandle)) {
      final c = colliders[other];
      if (c == null) continue;
      final b = bodies[c.bodyHandle];
      final layer = c.layer != 0 ? c.layer : (b?.layer ?? 0);
      if (_matchesLayer(layerMask, layer)) return true;
    }
    return false;
  }

  List<RaycastHitData> boxCast(
    Vector2 origin,
    Vector2 size,
    double angle,
    Vector2 direction,
    double distance,
    int layerMask,
    double minDepth,
    double maxDepth,
  ) =>
      raycast(origin, direction, distance, layerMask, minDepth, maxDepth);

  List<RaycastHitData> circleCast(
    Vector2 origin,
    double radius,
    Vector2 direction,
    double distance,
    int layerMask,
    double minDepth,
    double maxDepth,
  ) =>
      raycast(origin, direction, distance, layerMask, minDepth, maxDepth);

  List<RaycastHitData> capsuleCast(
    Vector2 origin,
    Vector2 size,
    int capsuleDirection,
    double angle,
    Vector2 direction,
    double distance,
    int layerMask,
    double minDepth,
    double maxDepth,
  ) =>
      raycast(origin, direction, distance, layerMask, minDepth, maxDepth);

  List<ContactPointData> getContacts(int colliderHandle) =>
      _contactListener.getContactPoints(colliderHandle);

  List<int> getContactColliders(int colliderHandle) =>
      _contactListener.getTouchingColliders(colliderHandle).toList();

  List<int> overlapCollider(int colliderHandle) {
    final collider = colliders[colliderHandle];
    if (collider == null || collider.fixtures.isEmpty) return [];

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final fixture in collider.fixtures) {
      final aabb = fixture.getAABB(0);
      minX = math.min(minX, aabb.lowerBound.x);
      minY = math.min(minY, aabb.lowerBound.y);
      maxX = math.max(maxX, aabb.upperBound.x);
      maxY = math.max(maxY, aabb.upperBound.y);
    }

    final queryAABB = f.AABB.withVec2(
      f.Vector2(minX, minY),
      f.Vector2(maxX, maxY),
    );

    final hits = <int>{};
    _world.queryAABB(
      _FnQueryCallback((fixture) {
        final cHandle = fixture.userData as int?;
        if (cHandle == null || cHandle == colliderHandle) return true;
        final other = colliders[cHandle];
        if (other == null) return true;
        if (other.bodyHandle == collider.bodyHandle) return true;
        final otherBody = bodies[other.bodyHandle];
        if (otherBody == null || !otherBody.simulated) return true;
        hits.add(cHandle);
        return true;
      }),
      queryAABB,
    );

    return hits.toList();
  }
}
