import 'dart:typed_data';

import 'package:good/src/asset.dart';

/// An audio file's bytes, loaded and addressed like any other asset.
///
/// # This is the asset, not the playback
///
/// A clip is declared like any other asset, addressed, pointed at from a
/// component row, packed, encrypted and shipped exactly like a texture, and a
/// readiness check can tell you it is missing before the game starts. What
/// turns it into a sound is `AudioMixer` - `state.audio.play(clip, bus)` -
/// which hands [bytes] to whatever `AudioBackend` the game declared.
///
/// The split is what let the pipeline ship a whole release before anything
/// could play a sound: it is uniform over asset *kinds*, because `Asset<T>`
/// does not care what `T` is. Nothing above this line changed when the mixer
/// landed.
class AudioClip {
  AudioClip(this.bytes, this.format);

  /// The file's bytes, in [format]. Whatever `good assets compact` produced -
  /// Ogg Vorbis by default.
  final Uint8List bytes;

  /// The container the bytes are in, from the source path's extension.
  ///
  /// Carried, never re-sniffed: the loader already knows it, and a backend
  /// would otherwise have to guess from a header. `AudioContainer.of` reads it
  /// off the source's extension, and answers [AudioContainer.ogg] for a source
  /// that has none - which a `MemorySource` generally does not, so a
  /// procedurally generated clip is labelled Ogg whatever it holds (#17).
  final AudioContainer format;

  /// How many bytes the clip occupies. The one thing that can be answered
  /// without a decoder, and enough for a budget report.
  int get byteLength => bytes.length;
}

/// The audio containers the pipeline recognises.
enum AudioContainer {
  ogg('.ogg'),
  wav('.wav'),
  mp3('.mp3'),
  flac('.flac');

  const AudioContainer(this.extension);

  final String extension;

  /// The container [path]'s extension names, or [AudioContainer.ogg] when it
  /// names none - which is what a packed asset resolved through a manifest
  /// looks like.
  static AudioContainer of(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return AudioContainer.ogg;
    final extension = path.substring(dot).toLowerCase();
    for (final container in values) {
      if (container.extension == extension) return container;
    }
    return AudioContainer.ogg;
  }
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
  const AudioInfo(this.byteLength, this.format);

  final int byteLength;
  final AudioContainer format;
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
  Future<AudioClip> load(AssetKey<AudioClip> key) async => AudioClip(
    await key.source.load(),
    AudioContainer.of(key.source.description),
  );

  @override
  AssetInfo describe(AudioClip value) =>
      AudioInfo(value.byteLength, value.format);
}
