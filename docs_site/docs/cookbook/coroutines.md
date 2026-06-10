---
sidebar_position: 6
---

# Coroutines & Sequences

This page shows how to write multi-step sequences using coroutines. An object runs a looping attack pattern — approach, pause, charge, retreat — with each phase expressed as a sequential series of yields. Pressing Space interrupts and restarts the sequence.

## Live Demo

<iframe 
  src="/goo2d/play/#/coroutines" 
  width="100%" 
  height="400px" 
  style={{ border: 'none', borderRadius: '8px', background: '#000' }}
/>

## Assets Used

No external assets. The object is a colored rectangle.

---

## Tutorial

### 1. Imports and main()

```dart
// Add this: ------
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

void main() => runApp(const CoroutineExample());
// --------
```

### 2. Root Widget

```dart
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

void main() => runApp(const CoroutineExample());

// Add this: ------
class CoroutineExample extends StatelessWidget {
  const CoroutineExample({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Game(child: CoroutineWorld())),
    );
  }
}
// --------
```

### 3. Game World and Camera Scaffold

```dart
// Add this: ------
class CoroutineWorld extends StatefulGameWidget {
  const CoroutineWorld({super.key});

  @override
  GameState<CoroutineWorld> createState() => CoroutineWorldState();
}

class CoroutineWorldState extends GameState<CoroutineWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues(
            (c) => c
              ..orthographicSize = 5.0
              ..backgroundColor = const Color(0xFF0d1117),
          ),
        ),
      ],
    );
  }
}
// --------
```

### 4. Attacker Widget

Define the object that will run the attack pattern.

```dart
// Add this: ------
class Attacker extends StatefulGameWidget {
  const Attacker({super.key});

  @override
  GameState<Attacker> createState() => AttackerState();
}

class AttackerState extends GameState<Attacker> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
// --------
```

### 5. Add Attacker to the World

```dart
class CoroutineWorldState extends GameState<CoroutineWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    // Add this: ------
    yield const Attacker();
    // --------

    yield GameObjectWidget( /* camera */ );
  }
}
```

### 6. Attacker Components

Attach a transform, a renderer, and an interrupt input action.

```dart
class AttackerState extends GameState<Attacker> {
  // Add this: ------
  late InputAction interruptAction;

  @override
  void initState() {
    super.initState();
    interruptAction = InputAction()
      ..name = 'interrupt'
      ..type = InputActionType.button
      ..bindings = [Keyboard.space];
    addComponent(
      interruptAction,
      ObjectTransform()..position = Vector2(-2.0, 0.0),
      SpriteRenderer()..color = Colors.redAccent,
    );
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

### 7. Declare Coroutine Handle Field

A `Future<void>` returned by `startCoroutine` acts as a handle. Store it so you can stop and restart the sequence.

```dart
class AttackerState extends GameState<Attacker> with LifecycleListener {
  late InputAction interruptAction;
  // Add this: ------
  Future<void>? _patternHandle;
  // --------

  @override
  void initState() { /* ... */ }

  // Add this: ------
  @override
  void onMounted() {
    _patternHandle = startCoroutine(_attackPattern);
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`onMounted` fires after the game object and all its components are fully attached. Starting a coroutine here ensures the transform and renderer are reachable from inside the sequence.

### 8. Write the Attack Pattern Coroutine

A coroutine is an `async*` function that returns `Stream`. Each `yield` pauses execution until the instruction's condition is met.

```dart
class AttackerState extends GameState<Attacker> with LifecycleListener {
  late InputAction interruptAction;
  Future<void>? _patternHandle;

  @override
  void initState() { /* ... */ }

  @override
  void onMounted() { /* ... */ }

  // Add this: ------
  Stream _attackPattern() async* {
    final transform = getComponent<ObjectTransform>();
    final renderer = getComponent<SpriteRenderer>();

    while (true) {
      // Phase 1: approach
      renderer.color = Colors.redAccent;
      while (transform.position.x < 2.0) {
        transform.position += Vector2(3.0 * (1 / 60.0), 0);
        yield null;  // wait one frame
      }

      // Phase 2: pause
      renderer.color = Colors.orangeAccent;
      yield WaitForSeconds(0.8);

      // Phase 3: charge forward
      renderer.color = Colors.yellowAccent;
      yield WaitForSeconds(0.2);
      transform.position = Vector2(4.0, 0.0);

      // Phase 4: retreat
      renderer.color = Colors.blueAccent;
      yield WaitForSeconds(0.3);
      transform.position = Vector2(-2.0, 0.0);

      yield WaitForSeconds(0.5);
    }
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`yield null` suspends for exactly one frame — equivalent to `yield WaitForEndOfFrame()`. `yield WaitForSeconds(n)` suspends for `n` seconds. The `while (true)` loop makes the pattern repeat indefinitely until stopped.

### 9. Interrupt and Restart on Space

Check for the interrupt input in `onUpdate` and restart the coroutine.

```dart
// Add this: ------
class AttackerState extends GameState<Attacker>
    with LifecycleListener, Tickable {
// --------
  late InputAction interruptAction;
  Future<void>? _patternHandle;

  @override
  void initState() { /* ... */ }

  @override
  void onMounted() { /* ... */ }

  Stream _attackPattern() async* { /* ... */ }

  // Add this: ------
  @override
  void onUpdate(double dt) {
    if (interruptAction.triggered) {
      if (_patternHandle != null) stopCoroutine(_patternHandle!);
      getComponent<ObjectTransform>().position = Vector2(-2.0, 0.0);
      _patternHandle = startCoroutine(_attackPattern);
    }
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`stopCoroutine` cancels the sequence mid-yield — the coroutine does not resume from where it paused. Calling `startCoroutine` with the same function immediately starts a fresh run from the top.

---

## Final Code

```dart
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

void main() => runApp(const CoroutineExample());

class CoroutineExample extends StatelessWidget {
  const CoroutineExample({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Game(child: CoroutineWorld())),
    );
  }
}

class CoroutineWorld extends StatefulGameWidget {
  const CoroutineWorld({super.key});

  @override
  GameState<CoroutineWorld> createState() => CoroutineWorldState();
}

class CoroutineWorldState extends GameState<CoroutineWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield const Attacker();

    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues(
            (c) => c
              ..orthographicSize = 5.0
              ..backgroundColor = const Color(0xFF0d1117),
          ),
        ),
      ],
    );
  }
}

class Attacker extends StatefulGameWidget {
  const Attacker({super.key});

  @override
  GameState<Attacker> createState() => AttackerState();
}

class AttackerState extends GameState<Attacker>
    with LifecycleListener, Tickable {
  late InputAction interruptAction;
  Future<void>? _patternHandle;

  @override
  void initState() {
    super.initState();
    interruptAction = InputAction()
      ..name = 'interrupt'
      ..type = InputActionType.button
      ..bindings = [Keyboard.space];
    addComponent(
      interruptAction,
      ObjectTransform()..position = Vector2(-2.0, 0.0),
      SpriteRenderer()..color = Colors.redAccent,
    );
  }

  @override
  void onMounted() {
    _patternHandle = startCoroutine(_attackPattern);
  }

  Stream _attackPattern() async* {
    final transform = getComponent<ObjectTransform>();
    final renderer = getComponent<SpriteRenderer>();

    while (true) {
      renderer.color = Colors.redAccent;
      while (transform.position.x < 2.0) {
        transform.position += Vector2(3.0 * (1 / 60.0), 0);
        yield null;
      }

      renderer.color = Colors.orangeAccent;
      yield WaitForSeconds(0.8);

      renderer.color = Colors.yellowAccent;
      yield WaitForSeconds(0.2);
      transform.position = Vector2(4.0, 0.0);

      renderer.color = Colors.blueAccent;
      yield WaitForSeconds(0.3);
      transform.position = Vector2(-2.0, 0.0);

      yield WaitForSeconds(0.5);
    }
  }

  @override
  void onUpdate(double dt) {
    if (interruptAction.triggered) {
      if (_patternHandle != null) stopCoroutine(_patternHandle!);
      getComponent<ObjectTransform>().position = Vector2(-2.0, 0.0);
      _patternHandle = startCoroutine(_attackPattern);
    }
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```
