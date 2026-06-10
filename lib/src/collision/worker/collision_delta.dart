import 'dart:typed_data';

/// Trigger-only overlap diff produced by the collision worker each frame.
///
/// Pairs are stored as interleaved handles: [handleA, handleB, handleA, handleB, ...].
class CollisionDelta {
  final Int32List enterPairs;
  final Int32List stayPairs;
  final Int32List exitPairs;

  const CollisionDelta({
    required this.enterPairs,
    required this.stayPairs,
    required this.exitPairs,
  });

  static final empty = CollisionDelta(
    enterPairs: Int32List(0),
    stayPairs: Int32List(0),
    exitPairs: Int32List(0),
  );
}
