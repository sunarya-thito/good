import 'dart:async';
import 'dart:typed_data';

// ignore_for_file: implementation_imports, invalid_use_of_internal_member
//
// `SoLoud`, flutter_soloud's public wrapper, cannot be called from a spawned
// isolate. The gate is one getter:
//
//     bool get _isMainIsolate => kIsWeb || ServicesBinding.rootIsolateToken != null;
//
// (soloud.dart:310). It is read in exactly one place, `isInitialized`
// (soloud.dart:302), and 83 public methods open with
// `if (!isInitialized) throw const SoLoudNotInitializedException()` - `init`,
// every `load*` and every `play*` among them. So a spawned isolate has no
// root isolate token, `isInitialized` is false there whatever the engine is
// really doing, and the wrapper refuses to initialise, load or play. Read
// against the 4.1.7 the pubspec pins.
//
// This engine's mixer runs on the game isolate, and that is the whole point
// of the arrangement, measured: a `play` from there costs one to two
// microseconds and a native mixing thread does not care that the isolate
// calling it is busy.
//
// So this drives the FFI layer underneath the wrapper instead. It is not an
// undocumented back door: flutter_soloud's own shipped `Bus` class imports
// exactly this file (`src/bindings/soloud_controller.dart`, mixing_bus.dart:2)
// and calls the same object. What it is, is unversioned - a private layer
// carries no compatibility promise - which is why `pubspec.yaml` pins
// `flutter_soloud: 4.1.7` exactly rather than taking a caret range. A new
// release has to be read before it can be resolved into, and this file and
// that pin move together.
//
// The alternative was carrying a patch that deletes the gate, or vendoring the
// C++. Both cost the same review on every upstream release and neither gets
// the fix upstream; a pin plus a comment is the honest version of the same
// bet. The gate is worth an upstream issue - the wrapper's own doc already
// says the engine is a C++ singleton meant to be usable from another isolate,
// and then blocks `load*` and `play*` from doing it.
//
// `invalid_use_of_internal_member` is the same decision spelled a second time:
// `PlayerErrors` is the vocabulary that layer answers in - `initEngine` and
// `loadMem` return one - and it is `@internal`, so reading the layer at all
// means naming it. Comparing its `name` against a string instead would swap a
// warning the analyzer can see for a typo it cannot.
import 'package:flutter_soloud/flutter_soloud.dart' show Channels, LoadMode;
import 'package:flutter_soloud/src/bindings/bindings_player.dart';
import 'package:flutter_soloud/src/bindings/soloud_controller.dart';
import 'package:flutter_soloud/src/enums.dart' show PlayerErrors;
import 'package:flutter_soloud/src/sound_handle.dart';
import 'package:flutter_soloud/src/sound_hash.dart';
import 'package:good/good.dart';

/// The [AudioBackend] the engine ships, over SoLoud.
///
/// ```dart
/// class MyGame extends Game {
///   @override
///   AudioBackend createAudioBackend() => SoLoudAudioBackend();
/// }
/// ```
///
/// Constructed on the game isolate (`GameState.audio` is what builds it) and
/// called from there for the rest of the run. Nothing here touches a method
/// channel, so the game isolate needs no `BackgroundIsolateBinaryMessenger`
/// and `Game` does not have to ship a `RootIsolateToken` through the spawn.
///
/// # One engine per process
///
/// SoLoud is a singleton in C++ and `SoLoudController` is a singleton in Dart,
/// so two of these are two names for one engine: the second [open] finds it
/// already inited and the first [close] takes it down under both. One game,
/// one backend. That is also true of a `SoLoud.instance` used elsewhere in the
/// same app - do not mix the two.
///
/// # The voice cap is `AudioMixer`'s, and this layer supplies none
///
/// `setMaxActiveVoiceCount` is not called, and it would not do the job if it
/// were. It caps how many voices SoLoud **mixes** per buffer, not how many may
/// be alive: `Soloud::calcActiveVoices_internal` sets `mActiveVoiceCount` to
/// the cap and culls the rest, leaving each culled voice in its slot, while
/// `play` goes on minting handles up to `VOICE_COUNT`. Measured on
/// flutter_soloud 4.1.7's supported public API on the main isolate, a cap of 4
/// reads back as 4 and then permits 59 concurrent voices, and
/// `setProtectVoice` does not stop a protected looping music voice being
/// destroyed by the first burst of effects.
///
/// So `AudioMixer` counts a budget per [AudioBus] and stops the oldest voice
/// on a full one. Nothing here is asked about it, and nothing written against
/// this layer should assume it enforces a cap.
///
/// # Bus levels are volumes on this layer, not SoLoud mixing buses
///
/// `AudioMixer` multiplies a voice's bus level by the master level and hands
/// the product to [play], and calls [setVoiceVolume] on the voices of a bus
/// whose level moves. `busId` stays 0 - SoLoud's own main bus - so a level
/// change costs one `setVolume` per sounding voice on that bus and no
/// routing. A real SoLoud mixing bus per [AudioBus] would move that cost into
/// the engine and buys nothing until there are filters to hang on one.
///
/// # What this slice implements
///
/// Uploading a clip, starting a voice at a volume, changing that volume,
/// stopping it, and being told when one ends. No looping, no loop points, no
/// pan, no fades.
final class SoLoudAudioBackend extends AudioBackend {
  /// [sampleRate], [bufferSize] and [channels] are handed straight to
  /// `initEngine`. The defaults are flutter_soloud's own.
  SoLoudAudioBackend({
    this.sampleRate = 44100,
    this.bufferSize = 2048,
    this.channels = Channels.stereo,
  });

  /// The rate the device is opened at, in hertz.
  final int sampleRate;

  /// The device buffer, in samples. Smaller is lower latency and more
  /// underruns.
  final int bufferSize;

  /// How many output channels the device is opened with.
  final Channels channels;

  FlutterSoLoud get _ffi => SoLoudController().soLoudFFI;

  /// Source token -> the hash SoLoud knows that source by.
  ///
  /// A `SoundHash` is an extension type over `int`, so this map holds no more
  /// than the token itself would - it exists so that [discard] can hand back
  /// a typed hash without this file inventing one.
  final Map<int, SoundHash> _sources = <int, SoundHash>{};

  bool _open = false;

  @override
  Future<void> open() async {
    if (_open) return;
    // Both halves of what the public wrapper does before it dispatches an
    // init: `prepareEngineInit` publishes the native init state that
    // `initEngine` then completes against, and skipping it leaves the engine
    // reporting a shutdown that never happened.
    _ffi.prepareEngineInit();
    final error = await _ffi.initEngine(
      -1,
      sampleRate,
      bufferSize,
      channels,
      false,
    );
    if (error != PlayerErrors.noError) {
      throw StateError('the audio device would not open: ${error.name}');
    }
    // After the engine is up, not before: these install `NativeCallable`
    // listeners, and a listener delivers to the isolate that created it -
    // which is this one, the game isolate, which is exactly where the mixer
    // wants to hear that a voice ended.
    await _ffi.setDartEventCallbacks();
    _open = true;
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    _ffi.disposeAllSound();
    _sources.clear();
    // The wrapper's own sequence: publish the shutdown request, let the
    // native side finish, and only then close the callables. Closing them
    // first would free a `NativeCallable` a native thread can still reach.
    _ffi.requestEngineShutdown();
    await _ffi.deinitAsync();
    _ffi.disposeNativeCallables();
  }

  @override
  Future<int> upload(Uint8List bytes, String name) async {
    _requireOpen('upload $name');
    // `LoadMode.memory` because the alternative streams from a file and there
    // is no file - these bytes came out of the asset pipeline, possibly out of
    // an encrypted pack, and were never on disk under a name.
    //
    // `name` is SoLoud's only input to the hash it keys the source by, so two
    // uploads sharing one would collapse into a single source. That is why
    // `AudioBackend.upload` asks for a name unique within the run rather than
    // a label - see `AudioMixer`, which builds it from the asset's address.
    final result = _ffi.loadMem(name, bytes, LoadMode.memory);
    if (result.error != PlayerErrors.noError || !result.soundHash.isValid) {
      throw StateError('$name would not load: ${result.error.name}');
    }
    final token = result.soundHash.hash;
    _sources[token] = result.soundHash;
    return token;
  }

  @override
  void discard(int source) {
    final hash = _sources.remove(source);
    if (hash == null || !_open) return;
    _ffi.disposeSound(hash);
  }

  @override
  int? play(int source, double volume) {
    final hash = _sources[source];
    if (hash == null || !_open) return null;
    // busId 0 is SoLoud's main bus. See the class doc: an `AudioBus` is a
    // level `AudioMixer` has already folded into `volume`, so there is
    // nothing to route to.
    final result = _ffi.play(hash, volume: volume);
    if (result.error != PlayerErrors.noError || result.newHandle.isError) {
      return null;
    }
    return result.newHandle.id;
  }

  @override
  void setVoiceVolume(int voice, double volume) {
    if (!_open) return;
    // The error code is not read: the one failure it reports here is a handle
    // the engine has already finished with, which is the documented no-op.
    // `AudioMixer` calls this over every voice on a bus whose level moved,
    // and a voice can end between the walk starting and reaching it.
    _ffi.setVolume(SoundHandle(voice), volume);
  }

  @override
  void stop(int voice) {
    if (!_open) return;
    _ffi.stop(SoundHandle(voice));
  }

  @override
  Stream<int> get voiceEnded => _ffi.voiceEndedEvents;

  void _requireOpen(String what) {
    if (_open) return;
    throw StateError(
      'the SoLoud engine is not open, so it cannot $what. AudioMixer opens it '
      'on the first play and closes it when the game stops; a backend driven '
      'by hand has to call open() first.',
    );
  }
}
