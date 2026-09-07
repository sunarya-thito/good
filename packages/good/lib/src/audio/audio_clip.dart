import 'dart:typed_data';

import 'package:good/src/asset.dart';

/// An audio file's bytes, loaded and addressed like any other asset.
///
/// # This is the asset, not the playback
///
/// A clip is declared in `describeAssets`, addressed, pointed at from a
/// component row, packed, encrypted and shipped exactly like a texture, and a
/// readiness check can tell you it is missing before the game starts. What
/// turns it into a sound is `AudioMixer` - `state.audio.play(clip, bus)` -
/// which hands [bytes] to whatever `AudioBackend` the game declared.
///
/// The split is what let the pipeline ship a whole release before anything
/// could play a sound: it is uniform over asset *kinds*, because `Asset<T>`
/// does not care what `T` is. Nothing above this line changed when the mixer
/// landed.
///
/// # A clip records no container
///
/// Bytes and their length, and nothing about what container they are in.
/// Carrying one would need two things to be true, and neither is.
///
/// Nothing reads it. `AudioMixer` hands the bytes and a name to
/// `AudioBackend.upload`, and a backend identifies the container from the
/// bytes it was given - SoLoud's `loadMem` does, and that is the one backend
/// there is.
///
/// And a key could not answer for it in any case. `good generate` converts
/// every audio file to the single container the project configures, and a
/// development build ships the originals while a production build ships the
/// converted bytes - so one key resolves to two containers by design, and
/// #357 states the rule that follows: no code may read a container off a key.
/// It used to be read off the extension here, which additionally labelled
/// anything carrying no extension - a `MemorySource`, and so every
/// procedurally generated or network-delivered clip - Ogg Vorbis whatever it
/// held (#257).
class AudioClip {
  AudioClip(this.bytes);

  /// The file's bytes, in whatever `good generate` normalised them to - Ogg
  /// Vorbis by default.
  final Uint8List bytes;

  /// How many bytes the clip occupies. The one thing that can be answered
  /// without a decoder, and enough for a budget report.
  int get byteLength => bytes.length;
}

/// The handle a component field points at.
typedef AudioAsset = Asset<AudioClip>;

/// An audio clip's identity: where its bytes come from, and nothing else.
typedef AudioKey = AssetKey<AudioClip>;

/// What decoding discovered about a clip, replicated to every isolate copy.
///
/// Byte length only, for now. Duration and sample rate need a decoder, and
/// inventing them from a header would be a guess reported as a fact - when a
/// backend lands it can publish them here, which is what [AssetInfo] is for.
class AudioInfo extends AssetInfo {
  const AudioInfo(this.byteLength);

  final int byteLength;
}

/// Reads an audio file's bytes.
///
/// Does no decoding, so it is the one loader with nothing platform-specific
/// in it: it hands back what the source gave it. That also
/// means it works on the game isolate in principle - though nothing asks it
/// to, because loading still happens on the copy that can do I/O.
class AudioLoader extends AssetLoader<AudioClip> {
  const AudioLoader();

  @override
  Future<AudioClip> load(AssetKey<AudioClip> key) async =>
      AudioClip(await key.source.load());

  @override
  AssetInfo describe(AudioClip value) => AudioInfo(value.byteLength);
}
