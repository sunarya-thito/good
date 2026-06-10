import 'dart:typed_data';

/// Flat-buffer diff produced by the physics isolate each frame.
///
/// Pairs are stored as interleaved handles: [handleA, handleB, handleA, handleB, ...].
/// Contact points (only for solid enter pairs) use 7 floats each:
///   [px, py, nx, ny, separation, normalImpulse, tangentImpulse]
/// [contactPointCounts] has one entry per enter pair giving the point count.
class ContactDelta {
  final Int32List enterContacts;
  final Int32List stayContacts;
  final Int32List exitContacts;
  final Int32List enterTriggers;
  final Int32List stayTriggers;
  final Int32List exitTriggers;
  final Float32List contactPoints;
  final Int32List contactPointCounts;

  static const int floatsPerPoint = 7;

  const ContactDelta({
    required this.enterContacts,
    required this.stayContacts,
    required this.exitContacts,
    required this.enterTriggers,
    required this.stayTriggers,
    required this.exitTriggers,
    required this.contactPoints,
    required this.contactPointCounts,
  });

  static final empty = ContactDelta(
    enterContacts: Int32List(0),
    stayContacts: Int32List(0),
    exitContacts: Int32List(0),
    enterTriggers: Int32List(0),
    stayTriggers: Int32List(0),
    exitTriggers: Int32List(0),
    contactPoints: Float32List(0),
    contactPointCounts: Int32List(0),
  );
}
