import 'dart:typed_data';

/// The native audio engine, reduced to what a mixer needs from it.
///
/// The kernel holds this and never a concrete engine, for the ordinary
/// reason: `good` cannot depend on a plugin with a native build without
/// making every game that ships no sound pay for one. `good_audio_soloud`
/// is the implementation that plays; a test supplies its own.
///
/// # Two tokens, both plain `int`s
///
/// A **source** is uploaded bytes the engine can play from. A **voice** is one
/// playback of a source. Both are opaque integers minted by the backend, in
/// the same spirit as the row addresses elsewhere in this engine: an `int` is
/// what an FFI boundary actually carries, and wrapping one costs a heap object
/// on a path that can run several times a frame.
///
/// The tokens are the backend's to interpret. Nothing above this line does
/// arithmetic on one, compares one against a constant, or assumes an unused
/// value is free to invent.
///
/// # Everything here runs on the game isolate
///
/// [play] and [stop] are synchronous because they are cheap - a call into a
/// native engine whose mixing happens on its own thread, measured at one to
/// two microseconds. [open] and [upload] are not: opening a device and
/// decoding a file are real work, and a tick must not wait on either.
abstract class AudioBackend {
  const AudioBackend();

  /// Brings the engine up. Idempotent: a second call on an open engine
  /// completes without reopening it.
  Future<void> open();

  /// Takes the engine down, stopping whatever is sounding. Idempotent, and
  /// safe to call on an engine that was never opened.
  ///
  /// Every source uploaded through [upload] is released by this; a caller
  /// does not have to walk them.
  Future<void> close();

  /// Hands [bytes] to the engine and completes with a source token.
  ///
  /// [name] must be unique to this source within the run, and readable enough
  /// to appear in a log. An engine is free to key its own table by it - SoLoud
  /// hashes it - so two sources sharing a name is a collision, not a cosmetic
  /// problem. `AudioMixer` builds it from the asset's address, which is
  /// unique by construction.
  Future<int> upload(Uint8List bytes, String name);

  /// Frees [source] and stops every voice still playing it.
  void discard(int source);

  /// Starts a voice on [source] at [volume], or returns `null` if the engine
  /// refused - out of voices, or the source is gone.
  int? play(int source, double volume);

  /// Stops [voice]. A no-op on a voice that has already ended.
  ///
  /// An implementation **may** also raise [voiceEnded] for it - a native
  /// engine that reports every freed voice slot has no way to tell an
  /// explicit stop from a natural end. The mixer therefore treats a
  /// [voiceEnded] for a voice it has already accounted for as a no-op, and no
  /// implementation has to suppress one.
  void stop(int voice);

  /// The token of each voice the engine has finished with - a one-shot clip
  /// reaching its end, and possibly a [stop] the caller already knows about.
  ///
  /// Broadcast, because the mixer subscribes once per [open] and unsubscribes
  /// on [close], and a single-subscription stream would forbid the second
  /// open.
  Stream<int> get voiceEnded;
}
