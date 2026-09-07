// #257, #357: a clip is bytes, and says nothing about their container.
//
// `AudioLoader` used to label one from the source description's extension,
// answering ogg for anything that named no extension it recognised - which
// `MemorySource` never does, and it is the documented route for a
// procedurally generated or network-delivered sound. The label is gone rather
// than corrected: nothing read it, and a key cannot answer for a container
// that `good generate` decides for the whole build.
//
// What is worth pinning is that the loader reads the source and nothing else,
// so an extension is never again load-bearing.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/asset.dart';
import 'package:good/src/audio/audio_clip.dart';

final Uint8List _bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

void main() {
  test('a clip is the bytes the source handed over', () async {
    final AudioClip clip = await const AudioLoader().load(
      AudioKey(MemorySource(_bytes, name: 'sfx/hit.ogg')),
    );

    expect(clip.bytes, same(_bytes));
    expect(clip.byteLength, 4);
  });

  // The three names that used to resolve to three different answers - one
  // read off the extension, and two the fallback invented. A source names
  // itself for diagnostics; nothing about it reaches the clip.
  test('the source name changes nothing about the clip', () async {
    const AudioLoader loader = AudioLoader();

    for (final String name in <String>[
      'music.wav',
      'voice.opus',
      'in-memory',
    ]) {
      final AudioClip clip = await loader.load(
        AudioKey(MemorySource(_bytes, name: name)),
      );

      expect(clip.bytes, _bytes, reason: name);
    }
  });

  test('describe reports the byte length, which needs no decoder', () {
    final AudioInfo info =
        const AudioLoader().describe(AudioClip(_bytes)) as AudioInfo;

    expect(info.byteLength, 4);
  });
}
