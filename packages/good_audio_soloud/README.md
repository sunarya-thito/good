# good_audio_soloud

The audio backend for [`good`](https://pub.dev/packages/good), over
[SoLoud](https://solhsa.com/soloud/). One class, and a game names it once.

```bash
flutter pub add good_audio_soloud
```

## Playing a sound

```dart
import 'package:good_audio_soloud/good_audio_soloud.dart';

class MyGame extends Game {
  @override
  AudioBackend createAudioBackend() => SoLoudAudioBackend();
}
```

Then, anywhere on the game isolate:

```dart
final voice = state.audio.play(scene.theme, AudioBus.master);
// ...
voice.stop();
```

`scene.theme` is an `Asset<AudioClip>` a scene declared in `describeAssets`
(a prefab declares one with `Asset.of` on the field),
like a texture. The voice holds a claim on it for as long as it sounds, so the
scene that declared it can unload without the music stopping.

## Why this is a separate package

A native audio engine is a plugin: a platform build on five targets, plus a
`path_provider` dependency. `good` does not depend on it, so a game that ships
no sound compiles neither.

## What it does not do yet

No looping or authored loop points, no per-bus levels, no fades, no voice cap,
no web. `AudioBus` has one member and its level is fixed at 1.0.

The voice cap is worth stating separately, because it looks like something the
backend could supply and it cannot. Measured on flutter_soloud 4.1.7's
supported public API: `setMaxActiveVoiceCount(4)` reports back 4 and then
permits 59 concurrent voices, and `setProtectVoice` does not stop a protected
looping music voice being destroyed by the first burst of effects. A cap and a
stealing policy have to be counted above this layer, and nothing should be
written that assumes otherwise.

## It reaches past flutter_soloud's public API

`SoLoud`, the public wrapper, gates every method on
`ServicesBinding.rootIsolateToken != null`, so it refuses to initialise, load
or play from a spawned isolate. This engine's mixer runs on the game isolate on
purpose, so this package drives the FFI layer underneath the wrapper - the same
layer flutter_soloud's own `Bus` class uses.

That layer is unversioned, so `flutter_soloud` is pinned to an exact version
rather than a range. A new release has to be read before it can be resolved
into.
