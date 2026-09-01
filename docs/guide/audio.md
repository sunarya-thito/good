# Audio

<!-- snippet-scope
late Voice? music;
late Asset<AudioClip> hit;
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
    final voice = audio.play(level.theme, AudioBus.music);
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
music = state.audio.play(singleScene<MusicScene>().theme, AudioBus.music);
state.unloadScene(state.loadedScenes.first); // the music keeps playing
```

That matters more than it looks. A `Game` declares no asset of its own — a
prefab field and a scene's `describeAssets` are the only places one can be
declared — so **a scene is the only asset lifetime the engine has**, and every
clip is declared by a scene that will eventually unload. Without the voice's claim, a
backend would be left holding a source whose bytes were freed underneath it,
which is not a silent degradation: the handle simply goes invalid.

To ask whether a track is still the one playing, compare the clip:

<!-- snippet: body -->
```dart
final theme = singleScene<MusicScene>().theme;
final alreadyPlaying =
    music != null && music!.isPlaying && music!.clip == theme;
if (!alreadyPlaying) music = state.audio.play(theme, AudioBus.music);
```

`Audios.musicTheme` *is* an `AssetKey`, so that is an identity comparison the
analyzer checks. Nothing here compares a file path, and nothing should: a typo
in a string is a miss that reports nothing.

## Buses and levels

`play` takes an `AudioBus`, and there are five of them: `master`, `music`,
`effects`, `dialogue` and `interface`. Each carries a level of its own, and
each starts at 1.0.

<!-- snippet: body -->
```dart
state.audio.setLevel(AudioBus.music, 0.4);
state.audio.setLevel(AudioBus.master, 0.0); // a global mute
assert(state.audio.levelOf(AudioBus.music) == 0.4);
```

Players treat music, effects, speech and interface as four separate controls —
turning music down while keeping effects up is the most common audio preference
there is — and a single master volume does not decompose into four later
without editing every call site that ever played a sound.

`master` is the bus the other four mix into. Its level multiplies theirs, so
zero there is silence whatever the other four hold, and it is where a global
mute belongs. A voice played on `master` itself is scaled by the master level
alone: nothing is scaled by a bus twice.

A level applies to the voices **already sounding**, so a slider moved mid-game
moves the sound that is already playing. It lands as a step with no ramp, so
1.0 to 0.0 in one call is heard as a cut — fades are not built. The cost is one
call into the backend per sounding voice on the bus that moved, paid when a
level changes and never per tick.

`dialogue` is spoken lines. It is not spelled `voice` because a `Voice` here is
one sounding clip on any bus, which is the term SoLoud and Wwise both use for
that.

## The voice budget, and what a full bus gives up

`Game.maxVoicesPerBus` caps how many voices may sound at once on **each** bus.
Sixteen by default.

```dart
class BudgetedGame extends SoundGame {
  @override
  int get maxVoicesPerBus => 8;
}
```

A bus at its budget does not refuse the next sound. It stops the voice that
started first on that bus and hands the slot to the new one, and
`oldestVoiceOn` names the voice that goes next:

<!-- snippet: body -->
```dart
final leaving = state.audio.oldestVoiceOn(AudioBus.effects);
final replacing = state.audio.play(hit, AudioBus.effects);
assert(replacing.isPlaying);
assert(leaving == null || !leaving.isPlaying);
```

**Oldest-first is the policy.** The newest sound is the one the player just
caused, so dropping it is the wrong answer: a weapon that goes quiet under fire
reads as broken input. Stealing the quietest is the other candidate and has
nothing to sort by here — `play` takes no per-voice volume, so every voice on a
bus sounds at exactly that bus's level.

Counting per bus is also what keeps music safe without a flag on it. A hundred
impacts spend the effects budget; the music bus is a different count, and they
cannot reach it.

The count is the engine's, and no backend supplies one. flutter_soloud 4.1.7
has `setMaxActiveVoiceCount`, and it caps how many voices are **mixed** per
buffer, not how many may be alive: voices past the cap keep their slots and are
skipped by the mixer, while `play` goes on minting handles. A cap of 4 reads
back as 4 and then permits 59 concurrent voices, measured on its supported
public API. Nothing above `AudioBackend` assumes a backend enforces a budget.

## What is not built yet

- **Looping and authored loop points.** Music that loops from the top loses its
  intro; the loop start has to become a property of the clip, which is an asset
  pipeline change before it is a mixer change.
- **A settings surface.** Levels are set through `setLevel` and nothing
  persists them: a game writes its own preferences and applies them on boot.
- **Fades.** A level change is a step, and so is a stop.
- **Positional and distance-attenuated audio.**
- **Web.**
