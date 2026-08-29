import 'dart:async';

import 'package:good/src/asset.dart';
import 'package:good/src/audio/audio_backend.dart';
import 'package:good/src/audio/audio_clip.dart';
import 'package:good/src/game_state.dart';
import 'package:meta/meta.dart';

/// Which mix a voice plays through.
///
/// One member, and that is the whole point of the type existing this early.
/// A game exposes music, effects, voice and interface as four separate
/// controls because players treat them as four separate things, and a single
/// master volume does not decompose into four later without touching every
/// call site that ever played a sound. So [AudioMixer.play] takes a bus from
/// the first line of code, while there is still exactly one of them.
///
/// [master] survives that growth rather than being replaced by it: it is the
/// bus everything else mixes into, and it is where a global mute belongs even
/// once music and effects have levels of their own.
///
/// Its level is fixed at 1.0. Per-bus levels are a later slice - see
/// [AudioMixer] for the list.
enum AudioBus {
  /// Everything, at full level.
  master,
}

/// One playback of one clip.
///
/// Handed back by [AudioMixer.play] and worth keeping only for as long as you
/// intend to [stop] it: a one-shot sound can be started and forgotten, and
/// the mixer will release everything it holds when the clip ends.
///
/// # Identity, never a path
///
/// [clip] is the `Asset<AudioClip>` that was played, so "is this the theme
/// still playing?" is `voice.clip == Audios.theme` - an identity comparison
/// the analyzer checks. Nothing here compares a file name or a description,
/// and nothing should: a typo in a string is a silent runtime miss.
final class Voice {
  Voice._(this._mixer, this.clip, this.bus);

  final AudioMixer _mixer;

  /// The asset this voice is playing.
  final Asset<AudioClip> clip;

  /// Which mix it plays through.
  final AudioBus bus;

  /// The backend's token, once the engine has actually started it. Null while
  /// the engine is still coming up or the clip is still uploading, and null
  /// again once the voice is over.
  int? _token;

  bool _over = false;

  /// Whether this voice still holds a claim on [clip].
  ///
  /// True from the moment [AudioMixer.play] returns until the clip ends or
  /// [stop] is called - which includes the stretch before the engine has
  /// actually started making noise. That is deliberate: the claim is what
  /// stops a scene unload from freeing the bytes out from under a voice, and
  /// the bytes are needed *most* during that stretch.
  bool get isPlaying => !_over;

  /// Stops this voice and releases its claim on [clip]. A no-op once the
  /// voice is over.
  void stop() => _mixer._end(this, fromBackend: false);

  @override
  String toString() => 'Voice(${clip.debugLabel} on $bus)';
}

/// Plays clips, and holds the engine's claim on what is sounding.
///
/// Lives on the **game isolate**, next to the systems that decide a footstep
/// happened and the scene whose claim keeps the clip alive, and calls the
/// native engine directly from there. Nothing crosses the isolate boundary to
/// start a sound: a `play` costs a couple of microseconds, which is less than
/// a port send, and the mixing itself runs on the engine's own thread - so a
/// tick that overruns, or a game paused with its timer stopped, does not
/// perturb playback. The mixer was never in the tick.
///
/// # A voice claims its clip, exactly as a loaded scene does
///
/// `GameState` counts one claim per loaded scene per declared asset and frees
/// an asset when the count reaches zero. A playing voice takes a claim of the
/// same kind, so a scene unloading while its music is still sounding drops
/// the scene's claim and finds the voice's, and the bytes survive. Without
/// that, a track cannot outlive the scene that declared it - and there is no
/// game-level `describeAssets`, so *some* scene declared it and every scene
/// eventually unloads.
///
/// This is not politeness. A backend does not keep a voice alive over its
/// source being freed underneath it: the handle simply goes invalid.
///
/// # What this slice does not do
///
/// Looping and authored loop points, per-bus levels, fades, voice caps and
/// a stealing policy, a settings surface, and web. Each of those is a slice of
/// its own. The two things that could not wait - the [AudioBus] parameter and
/// the asset claim - are here because neither retrofits without auditing
/// every call site that ever played a sound.
///
/// Note in particular that there is **no voice cap**, and that nothing here
/// assumes the backend enforces one. `flutter_soloud` 4.1.7's
/// `setMaxActiveVoiceCount` reports the cap back and then permits an order of
/// magnitude more voices than it, measured on its supported public API, so a
/// cap will have to be counted here when it lands.
final class AudioMixer {
  @internal
  AudioMixer(this.backend, this._state);

  /// The engine this mixer drives.
  final AudioBackend backend;

  final GameState _state;

  /// Address -> the upload of that asset's bytes, in flight or finished.
  ///
  /// Keyed by address rather than by handle so that the entry is a plain
  /// integer key, and cached so that playing one clip a thousand times
  /// uploads it once.
  final Map<int, Future<int>> _sources = <int, Future<int>>{};

  /// Backend voice token -> the [Voice] that owns it.
  final Map<int, Voice> _byToken = <int, Voice>{};

  /// Every voice this mixer still holds a claim for, started or not.
  final Set<Voice> _live = <Voice>{};

  Future<void>? _opening;
  StreamSubscription<int>? _ended;
  bool _closed = false;

  /// Whether the native engine has been opened.
  ///
  /// False until the first [play]. Declaring a backend costs nothing on its
  /// own: a game that never plays a sound never opens an audio device, never
  /// starts a mixing thread, and never pays the hundred milliseconds it takes
  /// to do either.
  bool get isOpen => _opening != null;

  /// How many voices are alive - started, or still waiting for the engine.
  int get liveVoiceCount => _live.length;

  /// Starts [clip] on [bus] and returns the voice that plays it.
  ///
  /// Returns immediately. The claim on [clip] is taken **here**, before this
  /// returns, so a scene unload on the very next line cannot free the bytes;
  /// the engine may not have made a sound yet when it does.
  ///
  /// Allocates: a [Voice], and on the first play of a clip, an upload. Playing
  /// a sound is an on-demand act and this is not on the per-tick path - a game
  /// that plays nothing runs none of this, and a game that plays something
  /// pays for the sound it asked for.
  Voice play(Asset<AudioClip> clip, AudioBus bus) {
    if (_closed) {
      throw StateError(
        'The audio mixer has been closed, so $clip cannot be played. This '
        'happens after the game has stopped; a voice started here would hold '
        'an asset claim nothing would ever release.',
      );
    }
    final voice = Voice._(this, clip, bus);
    // Before anything asynchronous, and before the engine is even asked to
    // come up. The claim is the thing that must not race a scene unload.
    _state.claimAsset(clip);
    _live.add(voice);
    unawaited(_start(voice));
    return voice;
  }

  /// The bring-up, the upload and the actual `play`, in that order.
  ///
  /// Each step re-checks whether the voice is still wanted, because [Voice.stop]
  /// can land at any point in here - a caller that starts a sound and stops it
  /// two lines later must not get a sound.
  Future<void> _start(Voice voice) async {
    try {
      await (_opening ??= backend.open().then((_) {
        // Subscribed once per open, and only after it succeeded: a backend
        // that failed to come up has no events to give.
        _ended ??= backend.voiceEnded.listen(_onBackendEnded);
      }));
      if (voice._over || _closed) return;
      final source = await _sourceFor(voice.clip);
      if (voice._over || _closed) return;
      final token = backend.play(source, 1);
      if (token == null) {
        // Refused. The voice never sounds, so it must not keep holding the
        // clip alive either.
        _end(voice, fromBackend: true);
        return;
      }
      if (voice._over) {
        // Stopped while `play` was on the stack. Undo it rather than leaving
        // a voice nothing can name sounding forever.
        backend.stop(token);
        return;
      }
      voice._token = token;
      _byToken[token] = voice;
    } catch (error) {
      // A failed upload or a device that would not open must not strand the
      // claim: the sound is not going to happen, and holding the bytes for it
      // would keep a whole scene's audio resident for the rest of the run.
      _end(voice, fromBackend: true);
      rethrow;
    }
  }

  Future<int> _sourceFor(Asset<AudioClip> clip) {
    final address = clip.pack();
    final existing = _sources[address];
    if (existing != null) return existing;
    // The address leads, because it is what makes the name unique: an asset's
    // address is assigned once per run and never recycled, while
    // `debugLabel` comes off the key and a key subclass decides what it says.
    // A backend may key its own source table by this string.
    final upload = _state
        .readAudioBytes(clip)
        .then((bytes) => backend.upload(bytes, '$address ${clip.debugLabel}'));
    _sources[address] = upload;
    return upload;
  }

  void _onBackendEnded(int token) {
    final voice = _byToken[token];
    if (voice == null) return;
    _end(voice, fromBackend: true);
  }

  /// The one place a voice's claim is released, whichever way it ended.
  void _end(Voice voice, {required bool fromBackend}) {
    if (voice._over) return;
    voice._over = true;
    final token = voice._token;
    voice._token = null;
    if (token != null) {
      _byToken.remove(token);
      // Not when the backend is the one telling us: the voice is already gone
      // on its side, and `stop` on a dead token is at best wasted work.
      if (!fromBackend) backend.stop(token);
    }
    _live.remove(voice);
    _state.releaseAssetClaim(voice.clip);
  }

  /// Stops everything and takes the engine down - the game is going away.
  ///
  /// Releases every live voice's claim first, so an asset held only by a
  /// sounding voice is freed rather than left claimed on a state that is
  /// about to be discarded. Safe on a mixer that never opened anything, and
  /// safe with voices playing.
  @internal
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // A copy: `_end` removes from `_live`. Each voice is stopped explicitly
    // rather than left for `backend.close()` to take down with the device -
    // stopping a voice and closing an engine are different acts, and a
    // backend is entitled to expect the first before the second.
    for (final voice in _live.toList(growable: false)) {
      _end(voice, fromBackend: false);
    }
    _sources.clear();
    _byToken.clear();
    await _ended?.cancel();
    _ended = null;
    final opening = _opening;
    if (opening == null) return;
    // Awaited rather than ignored: a device that is still opening has to
    // finish before it can be closed, and a half-open engine outliving the
    // game is a native thread nothing owns.
    try {
      await opening;
    } catch (_) {
      // An open that failed has nothing to close, and the failure was already
      // reported to whoever asked for the sound.
      return;
    }
    await backend.close();
  }
}
