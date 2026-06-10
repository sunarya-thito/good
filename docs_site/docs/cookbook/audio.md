---
sidebar_position: 5
---

# Audio & Sound

This page shows how to use audio in goo2d: a looping ambient sound that starts on mount, a one-shot sound effect triggered by Space, and background music that crossfades when the player enters a zone.

`AudioSystem.initialize()` must be called in `main()` before `runApp`. Without it, no audio will play.

## Live Demo

<iframe 
  src="/goo2d/play/#/audio" 
  width="100%" 
  height="400px" 
  style={{ border: 'none', borderRadius: '8px', background: '#000' }}
/>

## Assets Used

This example uses sound effects from [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds) and music from [OpenGameArt](https://opengameart.org).

| Asset | Description | Action |
| :--- | :--- | :--- |
| `shoot.ogg` | One-shot sound effect | Provide your own `.ogg` or `.mp3` |
| `ambient.ogg` | Looping ambient sound | Provide your own `.ogg` or `.mp3` |
| `music_a.ogg` | Zone A background music | Provide your own `.ogg` or `.mp3` |
| `music_b.ogg` | Zone B background music | Provide your own `.ogg` or `.mp3` |

---

## Tutorial

### 0. Asset Setup

1. Create `assets/audios/` in your project root.
2. Place `shoot.ogg`, `ambient.ogg`, `music_a.ogg`, `music_b.ogg` in that directory.
3. Register in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/audios/
```

### 1. Imports, Asset Enum, and main()

Audio requires `AudioSystem.initialize()` before `runApp`. Without it, the underlying `flutter_soloud` engine is not started and all `play()` calls are no-ops.

```dart
// Add this: ------
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

enum GameSounds with AssetEnum, AudioAssetEnum {
  shoot,
  ambient,
  musicA,
  musicB;

  @override
  AssetSource get source => AssetSource.local('assets/audios/$name.ogg');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AudioSystem.initialize();
  await GameAsset.loadAll(GameSounds.values).drain();
  runApp(const AudioExample());
}
// --------
```

`AudioSystem.initialize()` is async and must complete before any audio asset is used. Loading assets after initialization ensures the audio engine can register them correctly.

### 2. Root Widget

```dart
// Add this: ------
class AudioExample extends StatelessWidget {
  const AudioExample({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Game(child: AudioWorld())),
    );
  }
}
// --------
```

### 3. Game World and Camera Scaffold

```dart
// Add this: ------
class AudioWorld extends StatefulGameWidget {
  const AudioWorld({super.key});

  @override
  GameState<AudioWorld> createState() => AudioWorldState();
}

class AudioWorldState extends GameState<AudioWorld> {
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
        ComponentWidget(AudioListener.new),
      ],
    );
  }
}
// --------
```

`AudioListener` is the "ears" of the scene. Placing it on the camera means spatial audio is calculated relative to the camera position. Only one `AudioListener` should be active at a time.

### 4. Background Music with BackgroundMusic Widget

`BackgroundMusic` is a Flutter widget, not a component. Place it around your `Game` widget to start music as soon as the widget mounts.

```dart
class AudioExample extends StatelessWidget {
  const AudioExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: BackgroundMusic(
          // Add this: ------
          audio: GameSounds.musicA,
          transition: const CrossFadeMusicTransition(duration: 1.5),
          // --------
          child: const Game(child: AudioWorld()),
        ),
      ),
    );
  }
}
```

`BackgroundMusic` loops the given audio on the default channel (`channel: 0`). When `audio` is changed via `setState`, the `transition` policy is applied between the old and new tracks.

### 5. Zone Switch Button in the World

Add a zone indicator to the world that switches music when pressed.

```dart
class AudioWorldState extends GameState<AudioWorld> {
  // Add this: ------
  bool _inZoneB = false;
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {
    // Add this: ------
    yield GameObjectWidget(
      children: [
        ComponentWidget(ScreenTransform.new),
      ],
      // Flutter UI is also valid inside game objects
    );
    // --------

    yield GameObjectWidget( /* camera + listener */ );
  }
}
```

### 6. Reactive Background Music

Store the music selection in state so rebuilding the widget updates the `BackgroundMusic`.

```dart
class AudioExample extends StatelessWidget {
  const AudioExample({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: _AudioRoot()),
    );
  }
}

// Add this: ------
class _AudioRoot extends StatefulWidget {
  const _AudioRoot();

  @override
  State<_AudioRoot> createState() => _AudioRootState();
}

class _AudioRootState extends State<_AudioRoot> {
  GameSounds _currentMusic = GameSounds.musicA;

  void switchMusic(GameSounds next) => setState(() => _currentMusic = next);

  @override
  Widget build(BuildContext context) {
    return BackgroundMusic(
      audio: _currentMusic,
      transition: const CrossFadeMusicTransition(duration: 1.5),
      child: Game(
        child: AudioWorld(onZoneChange: switchMusic),
      ),
    );
  }
}
// --------
```

When `_currentMusic` changes, Flutter rebuilds `BackgroundMusic` with the new audio, triggering the crossfade transition automatically.

### 7. Player Widget with Sound Effect

Define a player that plays a one-shot sound when Space is pressed.

```dart
// Add this: ------
class Player extends StatefulGameWidget {
  const Player({super.key});

  @override
  GameState<Player> createState() => PlayerState();
}

class PlayerState extends GameState<Player> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
// --------
```

### 8. Player Components and Shoot Action

```dart
class PlayerState extends GameState<Player> {
  // Add this: ------
  late InputAction shootAction;
  late AudioSource _shootSource;

  @override
  void initState() {
    super.initState();
    shootAction = InputAction()
      ..name = 'shoot'
      ..type = InputActionType.button
      ..bindings = [Keyboard.space];
    addComponent(
      shootAction,
      ObjectTransform()..position = Vector2.zero(),
      SpriteRenderer()..color = Colors.cyanAccent,
      _shootSource = AudioSource()
        ..clip = GameSounds.shoot
        ..playOnAwake = false
        ..spatialBlend = 0.0,
    );
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`playOnAwake = false` means the sound does not start automatically on mount. `spatialBlend = 0.0` makes it a 2D sound regardless of position.

### 9. Trigger the Sound on Input

```dart
class PlayerState extends GameState<Player> with Tickable {
  late InputAction shootAction;
  late AudioSource _shootSource;

  @override
  void initState() { /* ... */ }

  // Add this: ------
  @override
  void onUpdate(double dt) {
    if (shootAction.triggered) {
      _shootSource.play();
    }
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`action.triggered` is true only on the frame the button was first pressed (equivalent to `wasPressedThisFrame`). Calling `play()` while already playing first calls `stop()` internally, so holding Space fires a new sound on each keypress without layering.

### 10. Looping Ambient Sound

Add an ambient sound component that loops from mount. Place it on its own game object so it is independent from the player.

```dart
class AudioWorldState extends GameState<AudioWorld> {
  final void Function(GameSounds)? onZoneChange;
  AudioWorldState({this.onZoneChange});

  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield const Player();

    // Add this: ------
    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          AudioSource.new.withInitialValues(
            (s) => s
              ..clip = GameSounds.ambient
              ..loop = true
              ..volume = 0.3
              ..spatialBlend = 0.0,
          ),
        ),
      ],
    );
    // --------

    yield GameObjectWidget( /* camera + listener */ );
  }
}
```

`loop = true` causes the clip to restart automatically when it reaches the end. The `AudioSource` component is enough — no extra setup is needed for looping.

---

## Final Code

```dart
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

enum GameSounds with AssetEnum, AudioAssetEnum {
  shoot,
  ambient,
  musicA,
  musicB;

  @override
  AssetSource get source => AssetSource.local('assets/audios/$name.ogg');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AudioSystem.initialize();
  await GameAsset.loadAll(GameSounds.values).drain();
  runApp(const AudioExample());
}

class AudioExample extends StatelessWidget {
  const AudioExample({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Scaffold(body: _AudioRoot()));
  }
}

class _AudioRoot extends StatefulWidget {
  const _AudioRoot();

  @override
  State<_AudioRoot> createState() => _AudioRootState();
}

class _AudioRootState extends State<_AudioRoot> {
  GameSounds _currentMusic = GameSounds.musicA;

  void switchMusic(GameSounds next) => setState(() => _currentMusic = next);

  @override
  Widget build(BuildContext context) {
    return BackgroundMusic(
      audio: _currentMusic,
      transition: const CrossFadeMusicTransition(duration: 1.5),
      child: Game(child: AudioWorld(onZoneChange: switchMusic)),
    );
  }
}

class AudioWorld extends StatefulGameWidget {
  final void Function(GameSounds)? onZoneChange;

  const AudioWorld({super.key, this.onZoneChange});

  @override
  GameState<AudioWorld> createState() => AudioWorldState();
}

class AudioWorldState extends GameState<AudioWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield const Player();

    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          AudioSource.new.withInitialValues(
            (s) => s
              ..clip = GameSounds.ambient
              ..loop = true
              ..volume = 0.3
              ..spatialBlend = 0.0,
          ),
        ),
      ],
    );

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
        ComponentWidget(AudioListener.new),
      ],
    );
  }
}

class Player extends StatefulGameWidget {
  const Player({super.key});

  @override
  GameState<Player> createState() => PlayerState();
}

class PlayerState extends GameState<Player> with Tickable {
  late InputAction shootAction;
  late AudioSource _shootSource;

  @override
  void initState() {
    super.initState();
    shootAction = InputAction()
      ..name = 'shoot'
      ..type = InputActionType.button
      ..bindings = [Keyboard.space];
    addComponent(
      shootAction,
      ObjectTransform()..position = Vector2.zero(),
      SpriteRenderer()..color = Colors.cyanAccent,
      _shootSource = AudioSource()
        ..clip = GameSounds.shoot
        ..playOnAwake = false
        ..spatialBlend = 0.0,
    );
  }

  @override
  void onUpdate(double dt) {
    if (shootAction.triggered) {
      _shootSource.play();
    }
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```
