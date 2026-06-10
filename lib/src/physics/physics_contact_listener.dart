import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/event.dart';
import 'package:goo2d/src/physics/physics_body.dart';

// ---------------------------------------------------------------------------
// PhysicsContactPoint
// ---------------------------------------------------------------------------

class PhysicsContactPoint {
  final Vector2 point;
  final Vector2 normal;
  final double separation;
  final double normalImpulse;
  final double tangentImpulse;

  const PhysicsContactPoint({
    required this.point,
    required this.normal,
    required this.separation,
    required this.normalImpulse,
    required this.tangentImpulse,
  });
}

// ---------------------------------------------------------------------------
// Payload structs
// ---------------------------------------------------------------------------

/// Payload for a solid contact event.
/// [bodyA] is "self" by convention when dispatched to a specific gameObject.
class PhysicsContact<T extends PhysicsBody> {
  final T bodyA;
  final T bodyB;
  // Only populated for enter events; empty for stay and exit.
  final List<PhysicsContactPoint> contacts;

  const PhysicsContact({
    required this.bodyA,
    required this.bodyB,
    this.contacts = const [],
  });
}

/// Payload for a trigger overlap event.
class PhysicsOverlap<T extends PhysicsBody> {
  final T trigger;
  final T other;

  const PhysicsOverlap({required this.trigger, required this.other});
}

// ---------------------------------------------------------------------------
// PhysicsEvent — unified interface for all physics async events
//
// Exposes the two involved bodies as a [BodyPair] so that
// PhysicsContactListener<T> can perform the covariance guard with a single
// `is` check, then delegate dispatch back to the event via [_invokeOn].
// ---------------------------------------------------------------------------

typedef BodyPair = (PhysicsBody, PhysicsBody);

abstract interface class PhysicsEvent {
  BodyPair get bodies;
  Future<void> _invokeOn<T extends PhysicsBody>(PhysicsContactListener<T> l);
}

// ---------------------------------------------------------------------------
// PhysicsContactListener<T> mixin
//
// Mix into Component (EC) or WorldSystem (ECS) to receive physics events.
// Type parameter controls which bodies you receive:
//   <Collider>     — EC↔EC contacts only
//   <Entity>       — ECS↔ECS contacts only
//   <PhysicsBody>  — all contacts including cross-paradigm
// ---------------------------------------------------------------------------

mixin PhysicsContactListener<T extends PhysicsBody> on EventListener {
  Future<void> onContactEnter(PhysicsContact<T> e) async {}
  Future<void> onContactStay(PhysicsContact<T> e) async {}
  Future<void> onContactExit(PhysicsContact<T> e) async {}
  Future<void> onOverlapEnter(PhysicsOverlap<T> e) async {}
  Future<void> onOverlapStay(PhysicsOverlap<T> e) async {}
  Future<void> onOverlapExit(PhysicsOverlap<T> e) async {}

  @override
  Future<bool> onDispatchEventAsync<L extends EventListener>(
    AsyncEvent<L> event,
  ) async {
    if (event is PhysicsEvent) {
      final physicsEvent = event as PhysicsEvent;
      final (a, b) = physicsEvent.bodies;
      if (a is! T || b is! T) return false;
      await physicsEvent._invokeOn(this);
      return true;
    }
    return super.onDispatchEventAsync(event);
  }
}

// ---------------------------------------------------------------------------
// Event classes — one set used for both EC dispatch and ECS broadcast
// ---------------------------------------------------------------------------

class ContactEnterEvent<T extends PhysicsBody>
    extends AsyncEvent<PhysicsContactListener<T>>
    implements PhysicsEvent {
  final PhysicsContact<T> data;
  const ContactEnterEvent(this.data);
  @override
  BodyPair get bodies => (data.bodyA, data.bodyB);
  @override
  Future<void> _invokeOn<S extends PhysicsBody>(PhysicsContactListener<S> l) =>
      l.onContactEnter(
        PhysicsContact(
          bodyA: data.bodyA as S,
          bodyB: data.bodyB as S,
          contacts: data.contacts,
        ),
      );
  @override
  Future<void> dispatch(PhysicsContactListener<T> l) => l.onContactEnter(data);
}

class ContactStayEvent<T extends PhysicsBody>
    extends AsyncEvent<PhysicsContactListener<T>>
    implements PhysicsEvent {
  final PhysicsContact<T> data;
  const ContactStayEvent(this.data);
  @override
  BodyPair get bodies => (data.bodyA, data.bodyB);
  @override
  Future<void> _invokeOn<S extends PhysicsBody>(PhysicsContactListener<S> l) =>
      l.onContactStay(
        PhysicsContact(
          bodyA: data.bodyA as S,
          bodyB: data.bodyB as S,
          contacts: data.contacts,
        ),
      );
  @override
  Future<void> dispatch(PhysicsContactListener<T> l) => l.onContactStay(data);
}

class ContactExitEvent<T extends PhysicsBody>
    extends AsyncEvent<PhysicsContactListener<T>>
    implements PhysicsEvent {
  final PhysicsContact<T> data;
  const ContactExitEvent(this.data);
  @override
  BodyPair get bodies => (data.bodyA, data.bodyB);
  @override
  Future<void> _invokeOn<S extends PhysicsBody>(PhysicsContactListener<S> l) =>
      l.onContactExit(
        PhysicsContact(
          bodyA: data.bodyA as S,
          bodyB: data.bodyB as S,
          contacts: data.contacts,
        ),
      );
  @override
  Future<void> dispatch(PhysicsContactListener<T> l) => l.onContactExit(data);
}

class OverlapEnterEvent<T extends PhysicsBody>
    extends AsyncEvent<PhysicsContactListener<T>>
    implements PhysicsEvent {
  final PhysicsOverlap<T> data;
  const OverlapEnterEvent(this.data);
  @override
  BodyPair get bodies => (data.trigger, data.other);
  @override
  Future<void> _invokeOn<S extends PhysicsBody>(PhysicsContactListener<S> l) =>
      l.onOverlapEnter(
        PhysicsOverlap(trigger: data.trigger as S, other: data.other as S),
      );
  @override
  Future<void> dispatch(PhysicsContactListener<T> l) => l.onOverlapEnter(data);
}

class OverlapStayEvent<T extends PhysicsBody>
    extends AsyncEvent<PhysicsContactListener<T>>
    implements PhysicsEvent {
  final PhysicsOverlap<T> data;
  const OverlapStayEvent(this.data);
  @override
  BodyPair get bodies => (data.trigger, data.other);
  @override
  Future<void> _invokeOn<S extends PhysicsBody>(PhysicsContactListener<S> l) =>
      l.onOverlapStay(
        PhysicsOverlap(trigger: data.trigger as S, other: data.other as S),
      );
  @override
  Future<void> dispatch(PhysicsContactListener<T> l) => l.onOverlapStay(data);
}

class OverlapExitEvent<T extends PhysicsBody>
    extends AsyncEvent<PhysicsContactListener<T>>
    implements PhysicsEvent {
  final PhysicsOverlap<T> data;
  const OverlapExitEvent(this.data);
  @override
  BodyPair get bodies => (data.trigger, data.other);
  @override
  Future<void> _invokeOn<S extends PhysicsBody>(PhysicsContactListener<S> l) =>
      l.onOverlapExit(
        PhysicsOverlap(trigger: data.trigger as S, other: data.other as S),
      );
  @override
  Future<void> dispatch(PhysicsContactListener<T> l) => l.onOverlapExit(data);
}
