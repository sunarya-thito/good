![GOO2D](header.png)

# GOO2D

[![Documentation](https://img.shields.io/badge/docs-site-rose)](https://sunarya-thito.github.io/goo2d)
[![Build Status](https://github.com/sunarya-thito/goo2d/actions/workflows/deploy_docs.yml/badge.svg)](https://github.com/sunarya-thito/goo2d/actions/workflows/deploy_docs.yml)
[![Flutter](https://img.shields.io/badge/Flutter-stable-02569B.svg)](https://flutter.dev)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)

> **⚠️ Under Heavy Development**
>
> GOO2D is in an early, active phase of development. APIs may change without notice. External contributions may not be accepted while the core architecture is being finalized.

A Flutter package for building 2D games using an Entity-Component pattern.

[**Documentation**](https://sunarya-thito.github.io/goo2d)

## Installation

```yaml
dependencies:
  goo2d: ^1.0.0
```

## Example

```dart
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

void main() {
  runApp(const MaterialApp(
    home: Scaffold(body: Game(child: Player())),
  ));
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
      SpriteRenderer(),
    );
  }

  @override
  void onUpdate(double dt) {
    getComponent<ObjectTransform>().position += Vector2(2 * dt, 0);
  }
}
```

## Running the example app

```bash
cd example
flutter run
```
