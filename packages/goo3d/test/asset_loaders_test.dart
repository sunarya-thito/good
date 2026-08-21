// #93: what a 3D project can load.
//
// goo3d declared no payload type and registered no loader, so a 3D project
// could load nothing at all - and `good create --3d` papered over it by typing
// every generated key `Object?`, which the #12 commit body itself called "not
// a design".
//
// The honest answer to "what does a 3D project load today" turned out to be
// audio and nothing else. goo3d has transforms, hierarchy and a camera, and no
// renderer until #43, so a texture would be an image it cannot draw and a mesh
// format would be invented purely to give a loader a subject. `AudioClip` is
// bytes and a container name - no canvas, no device, no dimension - so it moved
// into the kernel, which every engine package re-exports.
//
// Loading, not playback. Nothing here makes a sound; that is #17.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo3d/goo3d.dart';

final Uint8List _oggish = Uint8List.fromList(<int>[
  0x4F,
  0x67,
  0x67,
  0x53,
  9,
  8,
  7,
  6,
]);

/// A payload type nothing registers a decoder for.
class _Unloadable {}

class _State extends GameState<_Game> {}

class _Game extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _State();
}

Future<_Game> _boot() async {
  final game = _Game();
  final run = await Game.startInline(game);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
    AssetLoaders.reset();
  });

  test('a 3D game registers the audio decoder without declaring one', () async {
    expect(AssetLoaders.isRegistered<AudioClip>(), isFalse);
    await _boot();
    expect(
      AssetLoaders.isRegistered<AudioClip>(),
      isTrue,
      reason:
          'goo3d declares no loaders of its own. This one comes from the '
          'kernel Game, which is what makes a 3D project able to load '
          'anything at all',
    );
  });

  test('an audio clip loads in a 3D project', () async {
    await _boot();

    final key = AudioKey(MemorySource(_oggish, name: 'step.ogg'));
    final clip = await AssetLoaders.of<AudioClip>().load(key);

    expect(clip.bytes, _oggish);
    expect(clip.format, AudioContainer.ogg);
  });

  test('a payload goo3d has no decoder for still fails loudly', () async {
    await _boot();
    // Audio is the whole of what a 3D project can load today, and the registry
    // is not a catch-all that quietly answers for anything else. There is no
    // texture case to write here at all: `Texture` is a goo2d type and this
    // package cannot name it, which is the gap stated more plainly than an
    // assertion could.
    expect(
      () => AssetLoaders.of<_Unloadable>(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('_Unloadable'),
        ),
      ),
    );
  });
}
