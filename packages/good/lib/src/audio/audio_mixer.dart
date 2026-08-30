import 'dart:async';
import 'dart:typed_data';

import 'package:good/src/asset.dart';
import 'package:good/src/audio/audio_backend.dart';
import 'package:good/src/audio/audio_clip.dart';
import 'package:good/src/game_state.dart';
import 'package:meta/meta.dart';

/// Which mix a voice plays through.
///
/// Five buses, each with a level of its own, because players treat them as
/// five separate controls - turning music down while keeping effects up is
/// the most common audio preference there is, and a single master volume does
/// not decompose into five later without touching every call site that ever
/// played a sound.
///
/// [master] is the bus the other four mix into: its level multiplies theirs,
/// so a global mute belongs there and nowhere else. A voice may also play on
/// [master] itself, at the master level alone - nothing is scaled by a bus
/// twice.
///
/// Each bus carries its own voice budget. `Game.maxVoicesPerBus` caps every
/// bus separately, so a burst of effects spends the effects budget and cannot
/// reach the music. See [AudioMixer] for what happens at the cap, and
/// [AudioMixer.setLevel] for the levels.
enum AudioBus {
  /// Everything. This level multiplies every other bus's, and zero here is
  /// silence whatever the other four hold.
  master,

  /// Score and ambience - the long material, usually one clip at a time.
  music,

  /// Footsteps, impacts, weapons: the short sounds the world makes, and the
  /// bus a cap is for.
  effects,

  /// Spoken lines. Named for what is said and not for the playback: a [Voice]
  /// is one sounding clip on any bus, which is what SoLoud and Wwise both
  /// call it, so the bus is `dialogue` and the playback is `Voice`.
  dialogue,

  /// Menu clicks, notifications, and the rest of what belongs to the
  /// interface over the world.
  interface,
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

  /// Which mix it plays through, and whose level and voice budget it is
  /// counted against.
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
  ///
  /// Three things end a voice: this, the clip reaching its end, and its bus
  /// filling up - a full bus stops the voice that started first on it to make
  /// room. [isPlaying] reports all three the same way. See
  /// [AudioMixer.oldestVoiceOn] for which voice a bus gives up next.
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
/// # A level per bus, applied to the voices already sounding
///
/// [setLevel] writes a bus's level and multiplies it into every voice already
/// on that bus, so a slider moved mid-game moves the sound that is already
/// playing. [AudioBus.master] multiplies into all of them. The change lands
/// as a step with no ramp - fades are a slice of their own - so 1.0 to 0.0 in
/// one call is audible as a cut.
///
/// The cost is one backend call per sounding voice on the bus that moved,
/// paid when a level changes and never per tick. No native mixing bus is
/// involved: the multiply happens here and the backend is handed a number.
///
/// # A full bus stops its oldest voice
///
/// `Game.maxVoicesPerBus` is the budget, counted here and counted per bus.
/// Reaching it does not refuse the new sound: the voice that started first on
/// that bus is stopped, its claim released, and the new one takes the slot.
/// [oldestVoiceOn] names the voice that goes next, and [voiceCountOn] says
/// how close a bus is.
///
/// Dropping the newest is the wrong answer. The newest sound is the one the
/// player just caused, and a game whose weapon goes silent while an old
/// ambience loop keeps its slot reads as broken input. Stealing the quietest
/// is the other candidate and cannot discriminate here: [play] takes no
/// per-voice volume, so every voice on a bus sounds at exactly that bus's
/// level and there is nothing to sort by. Oldest-first is a total order over
/// start time, it is stable, and it costs one list index.
///
/// A per-bus budget is also what keeps music safe without a flag on it. An
/// effects burst spends the effects budget; the music bus is a different list
/// with a different count, and a hundred impacts cannot reach it.
///
/// The count is this mixer's, and nothing here assumes a backend keeps one.
/// `flutter_soloud` 4.1.7 has `setMaxActiveVoiceCount`, and it caps how many
/// voices are **mixed** per buffer, not how many may be alive:
/// `Soloud::calcActiveVoices_internal` sets `mActiveVoiceCount` to the cap and
/// culls the rest, leaving each culled voice in its slot, while `play` goes on
/// minting handles up to `VOICE_COUNT`. So a cap of 4 reads back as 4 and
/// admits an order of magnitude more sounding voices, and `setProtectVoice`
/// does not keep a protected music voice through a burst.
///
/// # What this slice does not do
///
/// Looping and authored loop points, fades, a settings surface, and web. Each
/// of those is a slice of its own.
final class AudioMixer {
  @internal
  AudioMixer(this.backend, this._state, {required this.maxVoicesPerBus}) {
    if (maxVoicesPerBus < 1) {
      throw ArgumentError.value(
        maxVoicesPerBus,
        'maxVoicesPerBus',
        'a bus that can hold no voices can play nothing, and every play would '
            'steal the sound started one line above it. Game.maxVoicesPerBus '
            'has to be one or more.',
      );
    }
    _levels.fillRange(0, _levels.length, 1);
  }

  /// The most voices that may sound at once on any one [AudioBus].
  ///
  /// Read once, from `Game.maxVoicesPerBus`, when this mixer is built. A
  /// game changes the mix at runtime through [setLevel], not through the
  /// budget: the budget sizes what the engine is willing to keep alive.
  final int maxVoicesPerBus;

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

  /// Every voice this mixer still holds a claim for, started or not, split by
  /// bus and held in start order.
  ///
  /// One list per [AudioBus], allocated once here. The oldest voice on a bus
  /// is its element zero, which is the whole of the stealing policy, and the
  /// per-bus split is what the budget is counted over. Nothing else records
  /// which voices are live: a second structure to keep in step is what drifts.
  final List<List<Voice>> _onBus = List<List<Voice>>.generate(
    AudioBus.values.length,
    (_) => <Voice>[],
    growable: false,
  );

  /// Each bus's level, indexed by `AudioBus.index`, filled with 1.0.
  ///
  /// A `Float64List` and not a map: a level is read on every [play], and a
  /// map lookup on that path costs a hash for a number an index already
  /// finds.
  final Float64List _levels = Float64List(AudioBus.values.length);

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

  /// How many voices are alive across every bus - started, or still waiting
  /// for the engine.
  int get liveVoiceCount {
    var total = 0;
    for (var i = 0; i < _onBus.length; i++) {
      total += _onBus[i].length;
    }
    return total;
  }

  /// How many voices are alive on [bus], against [maxVoicesPerBus].
  int voiceCountOn(AudioBus bus) => _onBus[bus.index].length;

  /// The voice [bus] gives up next, or null while the bus is empty.
  ///
  /// The stealing policy stated as a value: this is the voice that started
  /// first on [bus], and it is the one [play] stops when the bus is at
  /// [maxVoicesPerBus]. A game that must not lose a track compares it against
  /// the track and plays the new sound on another bus.
  Voice? oldestVoiceOn(AudioBus bus) {
    final voices = _onBus[bus.index];
    return voices.isEmpty ? null : voices[0];
  }

  /// [bus]'s level - 1.0 until [setLevel] moves it.
  double levelOf(AudioBus bus) => _levels[bus.index];

  /// Sets [bus]'s level and applies it to every voice already sounding on it.
  ///
  /// 0.0 is silent, 1.0 is the clip as it was authored, and above 1.0 the
  /// device clips. [AudioBus.master] multiplies every other bus, so setting
  /// it to zero mutes the game and setting it back restores whatever the
  /// other four hold.
  ///
  /// The new level lands as a step. A voice that was sounding is told its new
  /// volume in one call with no ramp between the two, so a large move in one
  /// call is heard as a cut.
  ///
  /// Costs one backend call per sounding voice on [bus], and on
  /// [AudioBus.master] one per sounding voice anywhere. A voice that has not
  /// started yet is not called for: it reads the level when it starts.
  void setLevel(AudioBus bus, double level) {
    if (!level.isFinite || level < 0) {
      throw ArgumentError.value(
        level,
        'level',
        'an audio level is a finite multiplier at or above zero - 0.0 silent, '
            '1.0 the clip as authored, above 1.0 clipping at the device.',
      );
    }
    _levels[bus.index] = level;
    if (bus == AudioBus.master) {
      for (var i = 0; i < _onBus.length; i++) {
        _applyLevel(AudioBus.values[i]);
      }
    } else {
      _applyLevel(bus);
    }
  }

  /// Tells the backend the new volume of every started voice on [bus].
  void _applyLevel(AudioBus bus) {
    final voices = _onBus[bus.index];
    if (voices.isEmpty) return;
    final volume = _volumeOf(bus);
    for (var i = 0; i < voices.length; i++) {
      final token = voices[i]._token;
      if (token != null) backend.setVoiceVolume(token, volume);
    }
  }

  /// What the backend is handed for a voice on [bus].
  ///
  /// A bus's own level times the master's, and the master's alone for a voice
  /// on [AudioBus.master] - a voice is scaled by one bus, and by the master
  /// once.
  double _volumeOf(AudioBus bus) {
    final master = _levels[AudioBus.master.index];
    if (bus == AudioBus.master) return master;
    return master * _levels[bus.index];
  }

  /// Starts [clip] on [bus] and returns the voice that plays it, at [bus]'s
  /// level, stopping [bus]'s oldest voice first if the bus is full.
  ///
  /// Returns immediately, and always with a voice: a bus at
  /// [maxVoicesPerBus] gives up the voice that started first on it rather
  /// than refusing the new sound. That is the stated policy and not a
  /// consequence of the data structure - see the class doc for what it
  /// rejects. [oldestVoiceOn] is the voice that goes.
  ///
  /// The claim on [clip] is taken **here**, before this returns, so a scene
  /// unload on the very next line cannot free the bytes; the engine may not
  /// have made a sound yet when it does.
  ///
  /// Allocates: a [Voice], and on the first play of a clip, an upload. The
  /// bus lists and the level table are allocated once with the mixer, so a
  /// steady stream of one-shots on a full bus allocates one object per sound
  /// and nothing else. Playing a sound is an on-demand act and this is not on
  /// the per-tick path - a game that plays nothing runs none of this.
  Voice play(Asset<AudioClip> clip, AudioBus bus) {
    if (_closed) {
      throw StateError(
        'The audio mixer has been closed, so $clip cannot be played. This '
        'happens after the game has stopped; a voice started here would hold '
        'an asset claim nothing would ever release.',
      );
    }
    final voice = Voice._(this, clip, bus);
    // Before anything asynchronous, before the engine is even asked to come
    // up, and before the steal below. The claim is the thing that must not
    // race a scene unload - and taking it first is also what makes stealing
    // safe on a clip whose only claim is the voice being stolen: released
    // first, that clip's count would reach zero, the bytes would be freed,
    // and the claim taken here would count a payload that had already gone.
    _state.claimAsset(clip);
    final voices = _onBus[bus.index];
    if (voices.length >= maxVoicesPerBus) {
      // The policy, in one line, and through the same accessor a caller
      // reads it with, so the two cannot come to disagree. Non-null because
      // the bus is at a budget of one or more. `_end` is what removes it
      // from this very list, so the add below lands inside the budget.
      _end(oldestVoiceOn(bus)!, fromBackend: false);
    }
    voices.add(voice);
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
      final token = backend.play(source, _volumeOf(voice.bus));
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
    _onBus[voice.bus.index].remove(voice);
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
    // A copy per bus: `_end` removes from the very list being walked. Each
    // voice is stopped explicitly, and not left for `backend.close()` to take
    // down with the device - stopping a voice and closing an engine are
    // different acts, and a backend is entitled to expect the first before
    // the second.
    for (var i = 0; i < _onBus.length; i++) {
      for (final voice in _onBus[i].toList(growable: false)) {
        _end(voice, fromBackend: false);
      }
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
