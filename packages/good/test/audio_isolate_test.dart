import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/audio/audio_backend.dart';
import 'package:good/src/audio/audio_clip.dart';
import 'package:good/src/audio/audio_mixer.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/event/state.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/system.dart';

// The half of audio that only a real spawn can show: a clip's **bytes**
// reaching the game isolate.
//
// Every other asset stays where it was decoded, because a decoded texture owns
// a `ui.Image` and a `ui.Image` does not cross. Audio is the exception - a
// decoded `AudioClip` is a `Uint8List` - and it has to be, because the mixer
// runs on the game isolate and a native engine wants the bytes there.
// `GameRuntime.requestAudioBytes` is that route, and this is the only
// configuration in which it runs at all: the inline path has the payload in
// hand and reads it in place.

/// How many bytes the backend was handed, on **this** isolate.
///
/// A per-isolate static, written by the backend on the game isolate and copied
/// into a state channel by a system each tick. Going through a tick rather
/// than writing the channel from the async continuation is the spelling that
/// says "this is simulation output" without anyone having to check whether a
/// write window was open.
int _uploadedHere = -1;

/// Set on the main isolate only, and read by [_MainOnlySource].
///
/// A spawned isolate gets its own copy of this library's statics, initialised
/// afresh, so this stays `false` there however many times main sets it. That
/// is what makes the test discriminating: if anything ever read a clip's bytes
/// *on* the game isolate instead of asking main for them, it would throw
/// rather than quietly succeeding on a source that rode the spawn inside the
/// key.
bool _onMain = false;

/// Readable on the copy with Flutter attached and nowhere else.
class _MainOnlySource extends AssetSource {
  const _MainOnlySource(this.name, this.length);

  final String name;
  final int length;

  @override
  Future<Uint8List> load() async {
    if (!_onMain) {
      throw StateError('$name can only be read on the Flutter isolate');
    }
    return Uint8List.fromList(List<int>.filled(length, 3));
  }

  @override
  Future<AssetAvailability> check() async => AssetAvailability.present;

  @override
  String get description => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _MainOnlySource && other.name == name && other.length == length;

  @override
  int get hashCode => Object.hash(name, length);
}

const _theme = AssetKey<AudioClip>(_MainOnlySource('theme.ogg', 96));

class _MusicScene extends SceneStruct {
  late final Asset<AudioClip> theme;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    theme = descriptor.has(_theme);
  }
}

/// Records what it was handed instead of playing it.
///
/// Constructed inside `createAudioBackend`, never held in a field on the
/// `Game`: the `Game` is what `Isolate.spawn` copies, and a `StreamController`
/// is not sendable. A factory method is copied as code and runs fresh on
/// whichever copy calls it, which is exactly the arrangement a backend wants -
/// a native engine handle has no business crossing a boundary either.
class _ReportingBackend extends AudioBackend {
  _ReportingBackend();

  final StreamController<int> _ended = StreamController<int>.broadcast();

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  Future<int> upload(Uint8List bytes, String name) async {
    _uploadedHere = bytes.length;
    return 1;
  }

  @override
  void discard(int source) {}

  @override
  int? play(int source, double volume) => 42;

  @override
  void setVoiceVolume(int voice, double volume) {}

  @override
  void stop(int voice) {}

  @override
  Stream<int> get voiceEnded => _ended.stream;
}

/// Carries [_uploadedHere] back across the boundary, once a tick.
class _Reporter extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() =>
      (state.game as _IsolateAudioGame).uploaded.value = _uploadedHere;
}

class _IsolateAudioState extends GameState<_IsolateAudioGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_Reporter.new);
  }

  @override
  void onMounted() {
    unawaited(_boot());
  }

  Future<void> _boot() async {
    await loadScene(game.music);
    audio.play(game.music.theme, AudioBus.master);
  }
}

class _IsolateAudioGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  late final _MusicScene music;

  /// Written on the game isolate, read here. The only way a number gets back.
  final uploaded = Channel.int32(-1);

  @override
  GameState createState() => _IsolateAudioState();

  @override
  AudioBackend? createAudioBackend() => _ReportingBackend();

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    music = descriptor.has(_MusicScene.new);
  }
}

// ignore: library_private_types_in_public_api
late _IsolateAudioGame run;

void main() {
  _onMain = true;

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
  });

  test("a clip's bytes reach the mixer on the game isolate", () async {
    final game = await Game.start(_IsolateAudioGame.new);
    run = game;
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    final arrived = await _waitUntil(game, () => game.uploaded.value >= 0);
    expect(
      arrived,
      isTrue,
      reason:
          'the game isolate declared the clip, main decoded it, and the mixer '
          'asked main for the bytes - which is the only route there is, since '
          'reading the source over there throws',
    );
    expect(
      game.uploaded.value,
      96,
      reason: 'the whole clip, not a truncated one',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}

Future<bool> _waitUntil(
  Game run,
  bool Function() ready, {
  int within = 60,
}) async {
  for (var i = 0; i < within; i++) {
    if (ready()) return true;
    await _waitTicks(run, 1);
  }
  return ready();
}

Future<void> _waitTicks(Game run, int count) {
  final target = run.tick + count;
  final done = Completer<void>();
  void listener(int tick) {
    if (tick >= target && !done.isCompleted) done.complete();
  }

  // Through `runtimeOrNull` rather than a public hook, matching
  // game_isolate_test.dart: tick listening is framework plumbing and
  // deliberately not API.
  final runtime = run.runtimeOrNull!;
  runtime.addTickListener(listener);
  return done.future
      .timeout(const Duration(seconds: 20))
      .whenComplete(() => runtime.removeTickListener(listener));
}
