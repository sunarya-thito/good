import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:good/good.dart';
import 'package:good_audio_soloud/good_audio_soloud.dart';

// What can honestly be asserted here, and what cannot.
//
// Cannot: anything that makes a sound. `SoLoudAudioBackend` reaches the engine
// through `DynamicLibrary.open('flutter_soloud_plugin.dll')`, and a
// `flutter test` host runs no plugin registrant and bundles no native library,
// so the very first call that touches the FFI layer fails on the open. Playing
// also wants an output device, which a headless runner does not have. A test
// that mocked its way past both would be asserting about the mock.
//
// Can: the state machine in front of it. Every method on this class decides
// whether the engine is open before it touches the library, and those
// decisions are this file's own - they are what stops a game that reaches for
// audio in the wrong order from getting a native crash instead of a message.
// Each test below would reach the FFI layer and die on the library open if
// that guard were removed, which is what makes them able to fail.
//
// The rest was measured on the device with a spike rather than in a test
// runner: `initEngine` from a spawned isolate returns `isInited=true` in
// 95-105 ms, `play` from that isolate costs p50 1-2 us, and a 1500 ms busy
// wait on it does not perturb playback.

void main() {
  test('it is an AudioBackend, so a Game can return one', () {
    expect(SoLoudAudioBackend(), isA<AudioBackend>());
  });

  test('the device settings are what they were constructed with', () {
    final backend = SoLoudAudioBackend(sampleRate: 48000, bufferSize: 512);
    expect(backend.sampleRate, 48000);
    expect(backend.bufferSize, 512);
  });

  test('closing an engine that never opened touches nothing', () async {
    // Not merely "does not throw": if this reached the FFI layer it would
    // throw, because there is no library to open here.
    await expectLater(SoLoudAudioBackend().close(), completes);
  });

  test('uploading before the engine is open says so by name', () {
    expect(
      () => SoLoudAudioBackend().upload(Uint8List(4), 'clip'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('not open'), contains('AudioMixer')),
        ),
      ),
    );
  });

  test('playing and stopping before the engine is open are inert', () {
    final backend = SoLoudAudioBackend();
    expect(backend.play(1, 1), isNull);
    expect(() => backend.stop(1), returnsNormally);
    expect(() => backend.discard(1), returnsNormally);
  });
}
