/// ECS-facing Box2D physics for `goo2d`.
///
/// Add `RigidBody2D` to a prefab beside `Transform2D` (and usually
/// `Collider2D`), declare a [Box2DPhysicsSystem], and entities simulate:
///
/// ```dart
/// class Crate extends EntityStruct<Crate>
///     with Transform2D, WorldTransform2D, Collider2D, RigidBody2D {
///   late final BoxBody box;
///
///   @override
///   void describeCollider(ColliderDescriptor d) {
///     box = d.hasBoxCollider(halfWidth: 0.5, halfHeight: 0.5, friction: 0.4);
///   }
///
///   @override
///   void describeRigidBody(RigidBody2DDescriptor d) {
///     d.has(type: BodyType2D.dynamicBody);
///   }
/// }
/// ```
///
/// The shapes themselves are declared through `goo2d`'s existing
/// `Collider2D`, not through anything here - a collider is a description of
/// an entity's geometry whether or not it is ever simulated, so it belongs in
/// the engine rather than in a backend package. This package adds the body
/// (mass, velocity, damping) and the system that steps them.
///
/// ## Units
///
/// Box2D is tuned for **metres, kilograms and seconds**, and works best with
/// moving objects between roughly 0.1 and 10 metres. A game that treats one
/// world unit as one pixel will have a 32-pixel crate acting like a 32-metre
/// building - technically simulated, and visibly wrong. Pick a pixels-per-
/// metre scale and apply it in the camera or the sprite sizes, not in the
/// physics.
///
/// ## Transform authority
///
/// Per body type, and it matters - see `RigidBody2D`'s class doc. Dart owns
/// static and kinematic bodies; Box2D owns dynamic ones. Writing a dynamic
/// body's `Transform2D` every tick fights the solver.
library;

/// ## Joints and effectors
///
/// All nine of Unity's 2D joints are here, on [Box2DPhysicsSystem]:
/// distance (and distance-with-spring, Unity's Spring Joint), revolute
/// (Hinge), prismatic (Slider), weld (Fixed), wheel, mouse (Target) and
/// motor - which covers both Relative and Friction, since the difference is
/// only what you ask it to hold.
///
/// The effectors are in `Effectors2D`, an extension rather than components,
/// because **Box2D has no effectors**: Unity's are gameplay code that finds
/// bodies in a region and applies a force, so there is nothing to bind a
/// component to. Area, Point, Buoyancy and Surface are there; Platform
/// (one-way) is not, and that file says why.
export 'src/effector.dart'
    show
        AreaEffector,
        BuoyancyEffector,
        Effector,
        Effector2D,
        EffectorDescriptor,
        PointEffector,
        SurfaceEffector;
export 'src/effectors.dart' show Effectors2D;
export 'src/joint.dart' show Joint;
export 'src/physics_system.dart' show Box2DPhysicsSystem;
export 'src/rigid_body.dart'
    show BodyType2D, RigidBody2D, RigidBody2DDescriptor;
