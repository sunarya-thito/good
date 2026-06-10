---
sidebar_position: 1
---

# Getting Started

Goo2D is a Flutter package for building 2D games. It uses an Entity-Component pattern where
game objects are Flutter widgets and behaviors are components attached to those widgets.

## Installation

Add goo2d to your `pubspec.yaml`:

```yaml
dependencies:
  goo2d: ^1.0.0
```

## Quickstart

The minimal setup below creates a moving object:

```dart
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

void main() {
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Game(
          child: Player(),
        ),
      ),
    ),
  );
}

class Player extends StatefulGameWidget {
  const Player({super.key});

  @override
  GameState createState() => PlayerState();
}

class PlayerState extends GameState<Player> with Tickable {
  @override
  void initState() {
    super.initState();
    addComponent(
      ObjectTransform()..position = Vector2.zero(),
    );
  }

  @override
  void onUpdate(double dt) {
    getComponent<ObjectTransform>().position += Vector2(2 * dt, 0);
  }
}
```

`Game` initializes the engine loop, input handling, and physics. Everything inside it participates in the game world.

## Platform Support

Goo2D runs on mobile, desktop, and web. Web requires extra setup for audio and may benefit from WASM builds.

See the **[Web Platform Guide](./web)** for details.
