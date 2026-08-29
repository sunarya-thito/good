# Audio

<!-- snippet-scope
late Voice? music;
-->

!!! abstract "Layer: `AudioBackend` and the mixer are kernel; the engine that makes noise is `good_audio_soloud`"

A sound is played from the **game isolate**, next to the code that decided to
play it. There is no message to send and no main-isolate detour: the mixer calls
the native engine directly, a `play` costs a couple of microseconds, and mixing
runs on the engine's own thread. A tick that overruns does not stutter the
music, and neither does a game paused with its timer stopped.

## Two steps

**Declare a backend.** `good` ships none: a native audio engine is a plugin with
a platform build on five targets, and a game that ships no sound should not have
to compile one. Add the package and name it once.

```bash
flutter pub add good_audio_soloud
```

```dart
import 'package:good_audio_soloud/good_audio_soloud.dart';

class SoundGame extends Game2D {
  @override
  AudioBackend createAudioBackend() => SoLoudAudioBackend();

  @override
  GameState2D createState() => SoundState();
}
```

**Play a clip.** The clip is an `Asset<AudioClip>` a scene declared, exactly
like a texture — see [Assets](assets.md).

<!-- snippet: top -->
```dart
class MusicScene extends SceneStruct {
  late final AudioAsset theme;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    theme = descriptor.has(Audios.musicTheme);
  }
}

class SoundState extends GameState2D {
  late final MusicScene level = MusicScene();

  void startMusic() {
    final voice = audio.play(level.theme, AudioBus.master);
    voice.stop();
  }
}
```

`play` returns immediately. `stop` is a no-op on a voice that already finished,
so a one-shot effect can be started and forgotten.

A game that declares no backend costs nothing at all. One that declares a
backend but never plays anything costs one method call: the device opens on the
first `play`, not at boot.

## A track survives a scene swap

This is the part worth understanding, because the obvious implementation gets it
wrong and the failure is a sound cutting out.

A loaded scene takes one claim on every asset it declared, and the asset is
freed when the last claim is dropped. **A playing voice takes a claim of the
same kind.** So the scene that declared the music can unload while the music is
still playing — the scene lets go, the voice does not, and the bytes stay.

<!-- snippet: body -->
```dart
music = state.audio.play(singleScene<MusicScene>().theme, AudioBus.master);
state.unloadScene(state.loadedScenes.first); // the music keeps playing
```

That matters more than it looks. There is no game-level `describeAssets` —
`SceneStruct` and `Component` are the only places an asset can be declared — so
**a scene is the only asset lifetime the engine has**, and every clip is
declared by a scene that will eventually unload. Without the voice's claim, a
backend would be left holding a source whose bytes were freed underneath it,
which is not a silent degradation: the handle simply goes invalid.

To ask whether a track is still the one playing, compare the clip:

<!-- snippet: body -->
```dart
final theme = singleScene<MusicScene>().theme;
final alreadyPlaying =
    music != null && music!.isPlaying && music!.clip == theme;
if (!alreadyPlaying) music = state.audio.play(theme, AudioBus.master);
```

`Audios.musicTheme` *is* an `AssetKey`, so that is an identity comparison the
analyzer checks. Nothing here compares a file path, and nothing should: a typo
in a string is a miss that reports nothing.

## Buses

`play` takes an `AudioBus`. Today there is exactly one, `AudioBus.master`, and
its level is fixed at 1.0.

The parameter exists anyway, and on purpose. Players treat music, effects, voice
and interface as four separate things — turning music down while keeping effects
up is the most common audio preference there is — and a single master volume
does not decompose into four later without editing every call site that ever
played a sound. Passing a bus now costs one word and buys that.

## What is not built yet

- **Looping and authored loop points.** Music that loops from the top loses its
  intro; the loop start has to become a property of the clip, which is an asset
  pipeline change before it is a mixer change.
- **Per-bus levels**, and therefore a settings surface.
- **Fades.**
- **A voice cap and a stealing policy.** Worth stating plainly, because it looks
  like something the backend supplies: it does not. On flutter_soloud 4.1.7,
  `setMaxActiveVoiceCount(4)` reports back 4 and then permits 59 concurrent
  voices, and `setProtectVoice` does not protect. Measured on its supported
  public API. The engine will have to count a budget itself, so do not write
  anything that assumes a cap is being enforced beneath you.
- **Positional and distance-attenuated audio.**
- **Web.**
