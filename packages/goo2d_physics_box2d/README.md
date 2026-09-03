# goo2d_physics_box2d

Box2D v3 physics for [`goo2d`](https://pub.dev/packages/goo2d). Bodies and
colliders are declared on an entity like any other component, and the world is
stepped inside the game isolate in step with the fixed tick.

```bash
flutter pub add goo2d_physics_box2d
```

## A falling crate

```dart
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

class Crate extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D, Collider2D, RigidBody2D {
  late final BoxBody box;
  late final Sprite sprite;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(
      halfWidth: 0.5, halfHeight: 0.5, friction: 0.4,
    );
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    sprite = descriptor.has(width: 1, height: 1, color: 0xFFCC8844);
  }
}
```

Nothing here says the crate is dynamic, because that is where `RigidBody2D`
starts. A prefab configures its body by moving the column defaults it wants
different, and only those:

```dart
class Ground extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    bodyType.defaultValue = BodyType2D.staticBody;
  }
}
```

Declare the system once, and that is the whole opt-in. Bodies appear as
entities spawn and go away as they despawn:

```dart
@override
void describeSystems(SystemDescriptor descriptor) {
  super.describeSystems(descriptor);
  descriptor.has(() => Box2DPhysicsSystem(gravityY: 10));
}
```

Push a body around, or change what kind of body it is:

```dart
final body = entity<RigidBody2D>().component;
body.applyImpulse(entity, 5, 0);
body.setVelocity(entity, 3, 0);
body.bodyType[entity] = BodyType2D.staticBody;
```

> **Work in metres.** Box2D is tuned for objects roughly 0.1 m to 10 m. Treating
one world unit as one pixel gives a 32-pixel crate the mass of a 32-metre
building, which is usually reported as "the physics feels floaty". Apply the
pixels-per-metre scale once, at the rendering edge.

## Next

- **[Physics](https://sunarya-thito.github.io/good/guide/physics/)** covers the
  nine joints, effectors, raycasts and overlap queries.

Bodies, colliders, all nine joints, effectors and queries work today, with the
solver spread across worker threads.
