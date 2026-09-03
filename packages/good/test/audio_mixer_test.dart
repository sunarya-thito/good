import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/audio/audio_backend.dart';
import 'package:good/src/audio/audio_clip.dart';
import 'package:good/src/audio/audio_mixer.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'audio_mixer_test.g.dart';

// The real backend cannot be driven from here, and that is a property of the
// backend rather than a gap in these tests. `SoLoudAudioBackend` opens
// `flutter_soloud_plugin.dll` through `DynamicLibrary.open`, and a
// `flutter test` host has no plugin registrant and no bundled native library -
// the open fails before any assertion could be made. Playing a sound also
// needs an output device, which a headless runner does not have.
//
// So what is under test here is the mixer: when a claim is taken, when it is
// released, what a teardown does to a voice that is still sounding, and what a
// game that plays nothing costs. Those are engine decisions and none of them
// live in the backend. What the backend contributes - that `initEngine`
// returns `isInited=true` from a spawned isolate, that `play` from there costs
// one to two microseconds, that a 1500 ms busy-wait on the calling isolate
// does not perturb playback - was measured on the device with a spike, and no
// `flutter test` run could have shown any of it.

/// An [AudioBackend] that records rather than plays.
///
/// Deliberately not a stub that answers everything successfully: it can be
/// told to refuse a voice, and it can be made slow, because both are states
/// the mixer has to hold a claim through.
class _FakeBackend extends AudioBackend {
  _FakeBackend();

  int opens = 0;
  int closes = 0;
  final List<String> uploads = <String>[];
  final List<int> started = <int>[];
  final List<int> stopped = <int>[];

  /// The last volume this backend was told for each voice token, whether at
  /// [play] or through [setVoiceVolume]. A test reads the number the mixer
  /// computed rather than trusting that it called something.
  final Map<int, double> volumeOf = <int, double>{};

  /// One entry per [setVoiceVolume], so a test can tell a voice that was told
  /// its volume from one that merely happens to hold the right number.
  final List<int> volumeChanges = <int>[];

  /// Set to make [play] refuse - the "out of voices" answer.
  bool refuse = false;

  /// Held open to keep [open] pending, so a test can look at the mixer while
  /// the device is still coming up.
  Completer<void>? opening;

  final StreamController<int> _ended = StreamController<int>.broadcast();
  int _nextToken = 100;
  bool _isOpen = false;

  /// Ends [voice] the way a one-shot clip reaching its end does.
  void endNaturally(int voice) => _ended.add(voice);

  @override
  Future<void> open() async {
    if (_isOpen) return;
    opens++;
    final gate = opening;
    if (gate != null) await gate.future;
    _isOpen = true;
  }

  @override
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;
    closes++;
  }

  @override
  Future<int> upload(Uint8List bytes, String name) async {
    uploads.add(name);
    return uploads.length;
  }

  @override
  void discard(int source) {}

  @override
  int? play(int source, double volume) {
    if (refuse) return null;
    final token = _nextToken++;
    started.add(token);
    volumeOf[token] = volume;
    return token;
  }

  @override
  void setVoiceVolume(int voice, double volume) {
    volumeChanges.add(voice);
    volumeOf[voice] = volume;
  }

  @override
  void stop(int voice) => stopped.add(voice);

  @override
  Stream<int> get voiceEnded => _ended.stream;
}

Uint8List _bytes(int n) => Uint8List.fromList(List<int>.filled(n, 7));

// Not const: `MemorySource` holds a `Uint8List`, which no const expression can
// build. Its identity is the name either way - see `MemorySource.name`.
final _theme = AssetKey<AudioClip>(MemorySource(_bytes(64), name: 'theme.ogg'));
final _hit = AssetKey<AudioClip>(MemorySource(_bytes(16), name: 'hit.ogg'));

/// A scene that declares [_theme] and nothing else - the music case, where the
/// clip outlives the scene that named it.
class _MusicScene extends SceneStruct {
  late final Asset<AudioClip> theme;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    theme = descriptor.has(_theme);
  }
}

/// A second scene declaring the same clip, so that a shared claim can be
/// distinguished from a voice's.
class _AlsoMusicScene extends SceneStruct {
  late final Asset<AudioClip> theme;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    theme = descriptor.has(_theme);
  }
}

class _EffectScene extends SceneStruct {
  late final Asset<AudioClip> hit;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    hit = descriptor.has(_hit);
  }
}

class _AudioState extends GameState<_AudioGame> {
  Future<void>? loading;

  @override
  void onMounted() {
    loading = loadScene(game.music);
  }
}

class _AudioGame extends Game {
  _AudioGame(this.backend, {this.voiceCap = 16});

  /// Null for the game that declares no audio at all.
  final _FakeBackend? backend;

  /// What `maxVoicesPerBus` answers. A small number makes the cap reachable
  /// in a test without playing sixteen sounds to get there.
  final int voiceCap;

  @override
  int get maxVoicesPerBus => voiceCap;

  late final _MusicScene music;
  late final _AlsoMusicScene alsoMusic;
  late final _EffectScene effects;

  @override
  GameState createState() => _AudioState();

  @override
  AudioBackend? createAudioBackend() => backend;

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    music = descriptor.has(_MusicScene());
    alsoMusic = descriptor.has(_AlsoMusicScene());
    effects = descriptor.has(_EffectScene());
  }
}

// A file-level binding, matching what the other game tests do.
// ignore: library_private_types_in_public_api
late _AudioGame run;

Future<_AudioGame> _boot(_FakeBackend? backend, {int voiceCap = 16}) async {
  final game = await Game.startInline(
    () => _AudioGame(backend, voiceCap: voiceCap),
  );
  run = game;
  await (game.state as _AudioState).loading;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
  });

  group('a voice claims its clip', () {
    test('a scene unloading does not free a clip a voice is still on', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      expect(theme.isLoaded, isTrue, reason: 'the scene load decoded it');
      expect(state.assetClaimCount(theme), 1, reason: 'one loaded scene');

      final voice = state.audio.play(theme, AudioBus.master);
      expect(
        state.assetClaimCount(theme),
        2,
        reason: 'the claim is taken by play(), before anything asynchronous',
      );

      // The requirement, in one line: the scene that declared the music goes
      // away and the music does not.
      state.unloadScene(state.loadedScenes.first);

      expect(state.assetClaimCount(theme), 1, reason: 'the voice still holds one');
      expect(
        game.assets.tryGet(_theme)?.isLoaded,
        isTrue,
        reason: 'the bytes are still there, because the voice is still on them',
      );
      expect(voice.isPlaying, isTrue);

      // And when the voice lets go, and only then, the clip goes.
      voice.stop();
      expect(state.assetClaimCount(theme), 0);
      expect(
        game.assets.tryGet(_theme),
        isNull,
        reason: 'the last claim released is what frees it',
      );
      expect(voice.isPlaying, isFalse);
    });

    test('a clip ending on its own releases the claim too', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final voice = state.audio.play(theme, AudioBus.master);
      // Let the engine come up, the upload finish and the voice actually
      // start - the claim was taken long before any of that.
      await pumpEventQueue();
      expect(backend.started, hasLength(1));

      state.unloadScene(state.loadedScenes.first);
      expect(state.assetClaimCount(theme), 1);

      backend.endNaturally(backend.started.single);
      await pumpEventQueue();

      expect(voice.isPlaying, isFalse);
      expect(state.assetClaimCount(theme), 0);
      expect(game.assets.tryGet(_theme), isNull);
      expect(
        backend.stopped,
        isEmpty,
        reason: 'a voice the engine finished does not need stopping',
      );
    });

    test('a clip two scenes declare survives one of them unloading', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      await state.loadScene(game.alsoMusic);
      final theme = game.assets.tryGet(_theme)!;

      expect(state.assetClaimCount(theme), 2, reason: 'two loaded scenes');
      final voice = state.audio.play(theme, AudioBus.master);
      expect(state.assetClaimCount(theme), 3);

      voice.stop();
      state.unloadScene(state.loadedScenes.first);
      expect(state.assetClaimCount(theme), 1);
      expect(game.assets.tryGet(_theme)?.isLoaded, isTrue);
    });

    test('the claim survives the stretch before the engine is up', () async {
      final backend = _FakeBackend()..opening = Completer<void>();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final voice = state.audio.play(theme, AudioBus.master);
      await pumpEventQueue();
      expect(backend.started, isEmpty, reason: 'the device is still opening');
      expect(voice.isPlaying, isTrue);

      state.unloadScene(state.loadedScenes.first);
      expect(
        game.assets.tryGet(_theme)?.isLoaded,
        isTrue,
        reason:
            'the bytes are needed most here - the upload has not happened yet',
      );

      backend.opening!.complete();
      await pumpEventQueue();
      expect(backend.started, hasLength(1));
      expect(state.assetClaimCount(theme), 1);
    });

    test('a voice stopped before it starts never sounds, and lets go', () async {
      final backend = _FakeBackend()..opening = Completer<void>();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final voice = state.audio.play(theme, AudioBus.master);
      voice.stop();
      expect(state.assetClaimCount(theme), 1, reason: 'only the scene now');

      backend.opening!.complete();
      await pumpEventQueue();
      expect(
        backend.started,
        isEmpty,
        reason: 'a sound asked for and cancelled must not arrive late',
      );
    });

    test('a refused voice does not strand its claim', () async {
      final backend = _FakeBackend()..refuse = true;
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final voice = state.audio.play(theme, AudioBus.master);
      await pumpEventQueue();

      expect(voice.isPlaying, isFalse);
      expect(state.assetClaimCount(theme), 1, reason: 'the scene, and nobody else');
    });
  });

  group('voices', () {
    test('play returns a distinct Voice per call', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final first = state.audio.play(theme, AudioBus.master);
      final second = state.audio.play(theme, AudioBus.master);
      final third = state.audio.play(theme, AudioBus.master);

      expect(second, isNot(same(first)));
      expect(third, isNot(same(first)));
      expect(third, isNot(same(second)));
      expect(state.assetClaimCount(theme), 4, reason: 'one scene, three voices');

      await pumpEventQueue();
      expect(backend.started.toSet(), hasLength(3), reason: 'three engine voices');
      expect(
        backend.uploads,
        hasLength(1),
        reason: 'one clip is uploaded once however often it is played',
      );

      // Stopping one leaves the others alone.
      first.stop();
      expect(first.isPlaying, isFalse);
      expect(second.isPlaying, isTrue);
      expect(third.isPlaying, isTrue);
      expect(state.assetClaimCount(theme), 3);
    });

    test('a voice knows its clip by identity, never by name', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      await state.loadScene(game.effects);
      final theme = game.assets.tryGet(_theme)!;
      final hit = game.assets.tryGet(_hit)!;

      final music = state.audio.play(theme, AudioBus.master);
      final effect = state.audio.play(hit, AudioBus.master);

      expect(music.clip, same(theme));
      expect(effect.clip, same(hit));
      expect(music.clip == hit, isFalse);
      expect(music.bus, AudioBus.master);
    });

    test('stopping twice is a no-op, not a double release', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final voice = state.audio.play(theme, AudioBus.master);
      await pumpEventQueue();
      voice.stop();
      voice.stop();
      voice.stop();

      expect(state.assetClaimCount(theme), 1, reason: 'the scene keeps its own');
      expect(backend.stopped, hasLength(1));
    });

    test('an engine end for a voice already stopped changes nothing', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final voice = state.audio.play(theme, AudioBus.master);
      await pumpEventQueue();
      final token = backend.started.single;
      voice.stop();

      // What a native engine that reports every freed voice slot does.
      backend.endNaturally(token);
      await pumpEventQueue();

      expect(state.assetClaimCount(theme), 1);
    });
  });

  group('bring-up and teardown', () {
    test('a game that plays nothing never opens the backend', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);

      // A full run: booted, a scene loaded, ticked, stopped.
      game.state.stepOnce();
      await pumpEventQueue();
      expect(backend.opens, 0);
      expect(game.state.audio.isOpen, isFalse);

      await game.stop();
      await pumpEventQueue();
      expect(
        backend.opens,
        0,
        reason:
            'declaring a backend costs a method call; opening a device is the '
            'first play and nothing else',
      );
      expect(backend.closes, 0, reason: 'nothing to close');
    });

    test('a game with no backend declares none and says so by name', () async {
      final game = await _boot(null);
      expect(game.state.hasAudio, isFalse);
      expect(
        () => game.state.audio,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('createAudioBackend'),
          ),
        ),
      );
    });

    test('the backend opens once however many voices start', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      state.audio.play(theme, AudioBus.master);
      state.audio.play(theme, AudioBus.master);
      await pumpEventQueue();
      state.audio.play(theme, AudioBus.master);
      await pumpEventQueue();

      expect(backend.opens, 1);
      expect(state.audio.isOpen, isTrue);
    });

    test('the mixer is the same object on every read', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      expect(game.state.audio, same(game.state.audio));
    });

    test('teardown with a voice playing does not throw', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final voice = state.audio.play(theme, AudioBus.master);
      await pumpEventQueue();
      expect(backend.started, hasLength(1));

      await game.stop();
      await pumpEventQueue();

      expect(voice.isPlaying, isFalse, reason: 'the run is over');
      expect(backend.closes, 1);
      expect(
        backend.stopped,
        hasLength(1),
        reason: 'a sounding voice is stopped rather than left playing',
      );
    });

    test('teardown while the device is still opening does not throw', () async {
      final backend = _FakeBackend()..opening = Completer<void>();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      state.audio.play(theme, AudioBus.master);
      final stopping = game.stop();
      backend.opening!.complete();
      await stopping;
      await pumpEventQueue();

      expect(
        backend.closes,
        1,
        reason: 'a half-open engine outliving the game is a thread nobody owns',
      );
      expect(backend.started, isEmpty);
    });

    test('teardown is idempotent, and a closed mixer refuses to play', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;
      final mixer = state.audio;

      state.audio.play(theme, AudioBus.master);
      await pumpEventQueue();

      await game.stop();
      await mixer.close();
      await mixer.close();
      await pumpEventQueue();

      expect(backend.closes, 1);
      expect(
        () => mixer.play(theme, AudioBus.master),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
    });

    test('a run that opened nothing still tears down clean', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      // Reached for, never played through.
      expect(game.state.audio.liveVoiceCount, 0);
      await game.stop();
      expect(backend.opens, 0);
      expect(backend.closes, 0);
    });
  });

  group('per-bus levels', () {
    test('every bus starts at 1.0, and a voice starts there', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      for (final bus in AudioBus.values) {
        expect(state.audio.levelOf(bus), 1.0, reason: '$bus');
      }

      state.audio.play(theme, AudioBus.music);
      await pumpEventQueue();
      expect(backend.volumeOf[backend.started.single], 1.0);
    });

    test('a voice starts at the level its bus already holds', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      state.audio.setLevel(AudioBus.music, 0.25);
      expect(state.audio.levelOf(AudioBus.music), 0.25);

      state.audio.play(theme, AudioBus.music);
      await pumpEventQueue();

      expect(backend.volumeOf[backend.started.single], 0.25);
      expect(
        backend.volumeChanges,
        isEmpty,
        reason: 'the level was read at the start, not corrected after it',
      );
    });

    test('a level change reaches the voices already sounding', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      state.audio.play(theme, AudioBus.music);
      await pumpEventQueue();
      final token = backend.started.single;
      expect(backend.volumeOf[token], 1.0);

      // A slider moved mid-game moves the sound that is already playing.
      state.audio.setLevel(AudioBus.music, 0.5);

      expect(backend.volumeChanges, <int>[token]);
      expect(backend.volumeOf[token], 0.5);
    });

    test('one bus moving leaves the other buses untouched', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      await state.loadScene(game.effects);
      final theme = game.assets.tryGet(_theme)!;
      final hit = game.assets.tryGet(_hit)!;

      state.audio.play(theme, AudioBus.music);
      await pumpEventQueue();
      final musicToken = backend.started.single;
      state.audio.play(hit, AudioBus.effects);
      await pumpEventQueue();
      final effectToken = backend.started.last;

      state.audio.setLevel(AudioBus.effects, 0.5);

      expect(backend.volumeOf[effectToken], 0.5);
      expect(
        backend.volumeOf[musicToken],
        1.0,
        reason: 'the buses are mixed independently, which is the whole point',
      );
      expect(
        backend.volumeChanges,
        <int>[effectToken],
        reason: 'the music voice was not even called for',
      );
      expect(state.audio.levelOf(AudioBus.music), 1.0);
    });

    test('the master level multiplies every other bus', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      await state.loadScene(game.effects);
      final theme = game.assets.tryGet(_theme)!;
      final hit = game.assets.tryGet(_hit)!;

      state.audio.setLevel(AudioBus.music, 0.5);
      state.audio.play(theme, AudioBus.music);
      state.audio.play(hit, AudioBus.effects);
      await pumpEventQueue();
      final musicToken = backend.started.first;
      final effectToken = backend.started.last;

      state.audio.setLevel(AudioBus.master, 0.5);

      expect(backend.volumeOf[musicToken], 0.25, reason: '0.5 bus x 0.5 master');
      expect(backend.volumeOf[effectToken], 0.5, reason: '1.0 bus x 0.5 master');
      expect(
        backend.volumeChanges.toSet(),
        <int>{musicToken, effectToken},
        reason: 'a master move reaches every bus',
      );
    });

    test('a voice on the master bus is scaled by the master once', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      state.audio.setLevel(AudioBus.master, 0.5);
      state.audio.play(theme, AudioBus.master);
      await pumpEventQueue();

      expect(
        backend.volumeOf[backend.started.single],
        0.5,
        reason: 'nothing is scaled by a bus twice',
      );
    });

    test('a voice not started yet reads the level when it does', () async {
      final backend = _FakeBackend()..opening = Completer<void>();
      final game = await _boot(backend);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      state.audio.play(theme, AudioBus.music);
      state.audio.setLevel(AudioBus.music, 0.25);
      expect(
        backend.volumeChanges,
        isEmpty,
        reason: 'there is no engine voice to tell yet',
      );

      backend.opening!.complete();
      await pumpEventQueue();

      expect(backend.volumeOf[backend.started.single], 0.25);
      expect(backend.volumeChanges, isEmpty);
    });

    test('a level that is negative or not finite is refused by name', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend);
      final mixer = game.state.audio;

      for (final bad in <double>[-0.1, double.nan, double.infinity]) {
        expect(
          () => mixer.setLevel(AudioBus.music, bad),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('finite multiplier at or above zero'),
            ),
          ),
          reason: '$bad',
        );
      }
      expect(mixer.levelOf(AudioBus.music), 1.0, reason: 'nothing was written');
    });
  });

  group('the voice budget, and what a full bus gives up', () {
    test('a full bus stops the voice that started first', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend, voiceCap: 3);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final first = state.audio.play(theme, AudioBus.effects);
      final second = state.audio.play(theme, AudioBus.effects);
      final third = state.audio.play(theme, AudioBus.effects);
      expect(state.audio.voiceCountOn(AudioBus.effects), 3);
      expect(first.isPlaying, isTrue);

      final fourth = state.audio.play(theme, AudioBus.effects);

      expect(first.isPlaying, isFalse, reason: 'the oldest went');
      expect(second.isPlaying, isTrue);
      expect(third.isPlaying, isTrue);
      expect(fourth.isPlaying, isTrue);
      expect(state.audio.voiceCountOn(AudioBus.effects), 3);
    });

    test('the newest sound always plays', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend, voiceCap: 2);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      // Each is let start before the next, so all three reach the engine and
      // the token that is taken back names which voice the policy chose.
      state.audio.play(theme, AudioBus.effects);
      await pumpEventQueue();
      final oldestToken = backend.started.single;
      state.audio.play(theme, AudioBus.effects);
      await pumpEventQueue();
      // The sound the player just caused. Refusing it, or stopping it to keep
      // an older one, is the failure this names.
      final newest = state.audio.play(theme, AudioBus.effects);
      await pumpEventQueue();

      expect(newest.isPlaying, isTrue);
      expect(
        backend.started,
        hasLength(3),
        reason: 'the newest reached the engine like the two before it',
      );
      expect(
        backend.stopped,
        <int>[oldestToken],
        reason: 'the oldest is what was taken back, never the newest',
      );
    });

    test('voices are stolen oldest first, in order', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend, voiceCap: 2);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final a = state.audio.play(theme, AudioBus.effects);
      final b = state.audio.play(theme, AudioBus.effects);
      final c = state.audio.play(theme, AudioBus.effects);
      expect(<bool>[a.isPlaying, b.isPlaying, c.isPlaying], <bool>[
        false,
        true,
        true,
      ]);

      final d = state.audio.play(theme, AudioBus.effects);
      expect(<bool>[a.isPlaying, b.isPlaying, c.isPlaying, d.isPlaying], <bool>[
        false,
        false,
        true,
        true,
      ], reason: 'start order is the order they are given up in');
    });

    test('a stolen voice is stopped on the engine and lets go', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend, voiceCap: 1);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final first = state.audio.play(theme, AudioBus.effects);
      await pumpEventQueue();
      final firstToken = backend.started.single;
      expect(state.assetClaimCount(theme), 2, reason: 'the scene and the voice');

      state.audio.play(theme, AudioBus.effects);
      await pumpEventQueue();

      expect(first.isPlaying, isFalse);
      expect(
        backend.stopped,
        <int>[firstToken],
        reason: 'a stolen voice is silenced, not left sounding forever',
      );
      expect(
        state.assetClaimCount(theme),
        2,
        reason: 'the scene and the one voice that is left',
      );
    });

    test('a burst on one bus cannot reach another', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend, voiceCap: 2);
      final state = game.state;
      await state.loadScene(game.effects);
      final theme = game.assets.tryGet(_theme)!;
      final hit = game.assets.tryGet(_hit)!;

      final music = state.audio.play(theme, AudioBus.music);
      for (var i = 0; i < 20; i++) {
        state.audio.play(hit, AudioBus.effects);
      }

      expect(
        music.isPlaying,
        isTrue,
        reason: 'the budget is per bus, so music needs no protected flag',
      );
      expect(state.audio.voiceCountOn(AudioBus.music), 1);
      expect(state.audio.voiceCountOn(AudioBus.effects), 2);
    });

    test('oldestVoiceOn names the voice that goes next', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend, voiceCap: 2);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      expect(state.audio.oldestVoiceOn(AudioBus.effects), isNull);

      final a = state.audio.play(theme, AudioBus.effects);
      final b = state.audio.play(theme, AudioBus.effects);
      expect(state.audio.oldestVoiceOn(AudioBus.effects), same(a));
      expect(
        state.audio.oldestVoiceOn(AudioBus.music),
        isNull,
        reason: 'a different bus, a different list',
      );

      final c = state.audio.play(theme, AudioBus.effects);
      expect(
        state.audio.oldestVoiceOn(AudioBus.effects),
        same(b),
        reason: 'a said it would go, and it did',
      );
      expect(c.isPlaying, isTrue);
    });

    test('a voice that ends on its own frees its slot', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend, voiceCap: 2);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final a = state.audio.play(theme, AudioBus.effects);
      final b = state.audio.play(theme, AudioBus.effects);
      await pumpEventQueue();

      backend.endNaturally(backend.started.first);
      await pumpEventQueue();
      expect(a.isPlaying, isFalse);
      expect(state.audio.voiceCountOn(AudioBus.effects), 1);

      final c = state.audio.play(theme, AudioBus.effects);
      expect(
        b.isPlaying,
        isTrue,
        reason: 'the bus was under budget, so nothing was taken',
      );
      expect(c.isPlaying, isTrue);
    });

    test('a bus never holds more than its budget', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend, voiceCap: 4);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      for (var i = 0; i < 200; i++) {
        state.audio.play(theme, AudioBus.effects);
        expect(state.audio.voiceCountOn(AudioBus.effects), lessThanOrEqualTo(4));
      }
      expect(state.audio.voiceCountOn(AudioBus.effects), 4);
      expect(
        state.assetClaimCount(theme),
        5,
        reason: 'the scene and four voices - 200 plays strand no claim',
      );
    });

    test('a voice stolen before the engine is up never sounds', () async {
      final backend = _FakeBackend()..opening = Completer<void>();
      final game = await _boot(backend, voiceCap: 1);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      final first = state.audio.play(theme, AudioBus.effects);
      final second = state.audio.play(theme, AudioBus.effects);
      expect(first.isPlaying, isFalse);

      backend.opening!.complete();
      await pumpEventQueue();

      expect(
        backend.started,
        hasLength(1),
        reason: 'a sound taken back before it started must not arrive late',
      );
      expect(second.isPlaying, isTrue);
    });

    test('stealing the last claim on a clip does not free it', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend, voiceCap: 1);
      final state = game.state;
      final theme = game.assets.tryGet(_theme)!;

      state.audio.play(theme, AudioBus.music);
      await pumpEventQueue();
      // Now the voice is the only claimant: the scene that declared the clip
      // is gone and the bytes are alive on the voice's claim alone.
      state.unloadScene(state.loadedScenes.first);
      expect(state.assetClaimCount(theme), 1);

      final replacement = state.audio.play(theme, AudioBus.music);
      await pumpEventQueue();

      expect(
        game.assets.tryGet(_theme)?.isLoaded,
        isTrue,
        reason:
            'the replacement claims before the steal releases, so the count '
            'never reaches zero and the payload is never freed under it',
      );
      expect(state.assetClaimCount(theme), 1);
      expect(replacement.isPlaying, isTrue);
      expect(backend.started, hasLength(2));
    });

    test('a budget below one is refused by name', () async {
      final backend = _FakeBackend();
      final game = await _boot(backend, voiceCap: 0);
      expect(
        () => game.state.audio,
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Game.maxVoicesPerBus'),
          ),
        ),
      );
    });
  });
}
