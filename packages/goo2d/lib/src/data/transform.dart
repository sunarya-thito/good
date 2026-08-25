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

  // --- Unity-Transform-inspired helpers -----------------------------------
  //
  // These operate on *local* values (what the raw fields hold) - a
  // world-space equivalent (accounting for ancestors) goes through
  // WorldTransform2D's fields instead (world_transform.dart).
  //
  // Every helper resolves each Entity argument's own Transform2D instance
  // fresh via Entity.get<Transform2D>(), and never reads a second entity
  // through `this` (the receiver). `this` is bound to whichever *concrete*
  // archetype's Transform2D declared it, and a second Entity argument may
  // well belong to a different archetype (a different prefab class) with a
  // different row layout entirely. Resolving fresh per-argument is correct
  // whether or not the two entities share an archetype; reading a foreign
  // entity through the wrong archetype's DataPointer would silently address
  // the wrong storage.

  /// Local-space (no ancestors, no `WorldTransform2D`) distance between
  /// [a]'s and [b]'s offsets.
  double distanceTo(Entity a, Entity b) {
    final ta = a.get<Transform2D>();
    final tb = b.get<Transform2D>();
    final dx = tb.transformOffsetX[b] - ta.transformOffsetX[a];
    final dy = tb.transformOffsetY[b] - ta.transformOffsetY[a];
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Sets [entity]'s `transformRotation` so it faces the local-space point
  /// ([targetX], [targetY]). Rotation 0 already means "facing +x" (see
  /// [forwardX]/[forwardY]), so this is exactly `atan2(dy, dx)`.
  void lookAt(Entity entity, double targetX, double targetY) {
    final t = entity.get<Transform2D>();
    final dx = targetX - t.transformOffsetX[entity];
    final dy = targetY - t.transformOffsetY[entity];
    t.transformRotation[entity] = math.atan2(dy, dx);
  }

  /// [lookAt], sugar for facing [target]'s own local-space offset.
  void lookAtEntity(Entity entity, Entity target) {
    final tt = target.get<Transform2D>();
    lookAt(entity, tt.transformOffsetX[target], tt.transformOffsetY[target]);
  }

  /// The unit direction [entity]'s current local rotation points, as two
  /// separate scalar getters and not one record: the engine allocates nothing
  /// per tick, and a record here would be betting on Dart to unbox it.
  double forwardX(Entity entity) =>
      math.cos(entity.get<Transform2D>().transformRotation[entity]);
  double forwardY(Entity entity) =>
      math.sin(entity.get<Transform2D>().transformRotation[entity]);
}

class Transform2DSystem extends GameSystem with FixedTickable {
  late final Query query;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    query = descriptor.query().withAll(Transform2D).withOptional(Child).build();
  }

  @override
  void onFixedUpdate() {
    // just example
    for (final instance in query.run()) {
      final transform = instance.get<Transform2D>();
      transform.transformOffsetX[instance] += 1;
      transform.transformOffsetY[instance] += 1;
      final optChildren = instance.tryGet<Child>();
      if (optChildren != null) {
        optChildren.parent[instance] = null;
      }
    }
  }
}
