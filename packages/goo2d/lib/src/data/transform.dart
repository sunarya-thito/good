import 'dart:math' as math;

import 'package:good/good.dart';

mixin Transform2D on Component {
  final transformOffsetX = Field.float64();
  final transformOffsetY = Field.float64();

  // Scale defaults to 1, not to the field's own 0 default. A zero scale is
  // a degenerate transform - it collapses every point to the origin, so an
  // entity that simply never assigned a scale would be invisible to the
  // renderer with nothing anywhere saying why. Offset and rotation are the
  // opposite: 0 *is* their identity, so they keep the plain default.
  final transformScaleX = Field.float64(1);
  final transformScaleY = Field.float64(1);

  final transformRotation = Field.float64();

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Transform2D>();
  }
}

/// What a game does with a [Transform2D], on the **entity** and not on the
/// component: `entity<Transform2D>().lookAt(x, y)`.
///
/// These operate on *local* values (what the raw fields hold) - a world-space
/// equivalent, accounting for ancestors, goes through [WorldTransform2D]'s
/// fields instead. The typed accessor makes the entity the receiver, so a
/// helper cannot accidentally index one archetype's columns with a row from
/// another. It erases to [Entity], so this spelling adds no allocation or
/// indirection to the tick path.
extension Transform2DAccessor on Accessor<Transform2D> {
  /// Local-space (no ancestors, no `WorldTransform2D`) distance between
  /// this entity's and [other]'s offsets.
  double distanceTo(Entity other) {
    final ta = component;
    final tb = other<Transform2D>().component;
    final dx = tb.transformOffsetX[other] - ta.transformOffsetX[this];
    final dy = tb.transformOffsetY[other] - ta.transformOffsetY[this];
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Sets this entity's `transformRotation` so it faces the local-space point
  /// ([targetX], [targetY]). Rotation 0 already means "facing +x" (see
  /// [forwardX]/[forwardY]), so this is exactly `atan2(dy, dx)`.
  void lookAt(double targetX, double targetY) {
    final t = component;
    final dx = targetX - t.transformOffsetX[this];
    final dy = targetY - t.transformOffsetY[this];
    t.transformRotation[this] = math.atan2(dy, dx);
  }

  /// [lookAt], sugar for facing [target]'s own local-space offset.
  void lookAtEntity(Entity target) {
    final tt = target<Transform2D>().component;
    lookAt(tt.transformOffsetX[target], tt.transformOffsetY[target]);
  }

  /// The unit direction this entity's current local rotation points, as two
  /// separate scalar getters and not one record: the engine allocates nothing
  /// per tick, and a record here would be betting on Dart to unbox it.
  double get forwardX => math.cos(component.transformRotation[this]);
  double get forwardY => math.sin(component.transformRotation[this]);
}
