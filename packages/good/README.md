# good

Game Overdrive On Dart. The kernel every good engine is built on: the ECS, the
fixed-tick loop, scenes, native component storage, input, assets and
coroutines.

**Building a 2D game? Install [`goo2d`](https://pub.dev/packages/goo2d)
instead.** It re-exports everything here, so you get this package anyway and a
renderer with it. Depend on `good` directly when you are writing a renderer, a
headless server, or a package that should work under either engine.

```bash
flutter pub add good
```

## The one idea

Components are not objects. A field declared on an entity kind is a **column**
in native memory, and an entity is a **row index** into it:

```dart
import 'package:good/good.dart';

class Player extends EntityStruct {
  late final DataPointer<double> speed;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    speed = data.hasFloat64(220);   // the default every new row starts at
  }
}
```

```dart
speed[entity] = 400;   // write one row
```

That is what keeps the frame loop free of allocation, and it is the thing worth
understanding before anything else. Systems then query for the entities they
care about and walk those columns:

```dart
class PlayerSystem extends GameSystem with FixedTickable {
  late final Query players;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    players = descriptor.query().withAll(Player).build();
  }

  @override
  void onFixedUpdate() { /* ... */ }
}
```

## Next

- **[Entities and components](https://sunarya-thito.github.io/good/guide/entities-and-components/)**
  for the column-and-row model in full.
- **[Architecture](https://sunarya-thito.github.io/good/guide/architecture/)**
  for how the Flutter isolate and the game isolate split the work.

It does depend on Flutter, because `GameView` is a widget and `StateChannel` is
a `ValueListenable`.

The ECS, memory pool, scheduler, scenes, hierarchy, input, assets, coroutines
and timelines work today. Audio playback and array-typed fields are not
implemented, and the web is unsupported because this needs `dart:ffi` and
isolates. [What works today](https://sunarya-thito.github.io/good/reference/roadmap/).
