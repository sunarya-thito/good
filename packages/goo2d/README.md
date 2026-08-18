# goo2d

Game Overdrive On 2D. A 2D game engine for Flutter that runs your simulation on
its own isolate at a fixed timestep, and keeps components in native memory so
the frame loop does not allocate.

```bash
flutter pub add goo2d
```

That is the only dependency you need. `goo2d` re-exports the
[`good`](https://pub.dev/packages/good) kernel, so one import covers both.

## What a game looks like

An entity kind is a struct of columns. `speed` here is a column, and `[entity]`
indexes a row in it:

```dart
import 'package:goo2d/goo2d.dart';

class Player extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final DataPointer<double> speed;
  late final Sprite sprite;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    speed = data.hasFloat64(220);
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    sprite = descriptor.has(width: 64, height: 64, color: 0xFFCC8844);
  }
}
```

A system queries for the entities it cares about and writes to their columns:

```dart
class PlayerSystem extends GameSystem with FixedTickable {
  late final Query players;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    players = descriptor.query().withAll(Transform2D, Player).build();
  }

  @override
  void onFixedUpdate() {
    final dt = game.fixedTimeStep.inMicroseconds / 1000000.0;
    for (final group in players.groups()) {
      final transform = group.get<Transform2D>();
      for (final entity in group) {
        transform.transformOffsetX[entity] += 60 * dt;
      }
    }
  }
}
```

Declare what exists and what runs, then show it:

```dart
class MyGameState extends GameState2D<MyGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(PlayerSystem());
  }

  @override
  void onMounted() => loadScene(MainScene());
}
```

```dart
GameView(camera: game.defaultCamera)
```

## Next

- **[Your first game](https://sunarya-thito.github.io/good/getting-started/your-first-game/)**
  builds the above into something you can run.
- **[Entities and components](https://sunarya-thito.github.io/good/guide/entities-and-components/)**
  explains the column-and-row model, which is the one idea worth learning first.
- Physics, networking and the build tool are separate packages:
  [`goo2d_physics_box2d`](https://pub.dev/packages/goo2d_physics_box2d),
  [`good_net`](https://pub.dev/packages/good_net),
  [`good_cli`](https://pub.dev/packages/good_cli).

Transforms, camera, sprite rendering, colliders and mouse picking work today.
Audio assets load, but there is no audio backend yet, and the web is
unsupported because the kernel needs `dart:ffi` and isolates.
[What works today](https://sunarya-thito.github.io/good/reference/roadmap/).

> **Coming from 0.0.2?** That was a different engine with a different API.
> Nothing carries over.
