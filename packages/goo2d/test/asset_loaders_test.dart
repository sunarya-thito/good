// #123: goo2d's payload decoders are registered by the game, not by a canvas.
//
// `AudioLoader` existed and was registered nowhere, so every `Audios.x` load
// threw the `StateError` from `AssetLoaders.of`. The CLI transcodes audio,
// keys it, packs it and ships it, and the pipeline terminated there.
//
// `Texture`'s decoder had the opposite problem: it was registered, but from
// `DrawCanvas2D`'s constructor. Build no canvas and no texture decoded - which
// is what left the example suite red for sixty commits (#83), and what these
// cases now boot without.
//
// Loading is the whole bar here. goo2d has no audio backend, no mixer and no
// voice management, so a loaded `AudioClip` is bytes held in memory; playback
// is #17.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

final Uint8List _oggish = Uint8List.fromList(<int>[
  0x4F,
  0x67,
  0x67,
  0x53,
  1,
  2,
  3,
  4,
]);

class _State extends GameState2D<_Game> {}

class _Game extends Game2D {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState2D createState() => _State();
}

/// A game that is not a [Game2D] but mixes the renderer in - the escape hatch
/// `Renderer2D` documents for a game whose base class is already something
/// else. It has to get the texture decoder too.
class _MixedState extends GameState<_Mixed> {}

class _Mixed extends Game with Renderer2D {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _MixedState();
}

Future<G> _boot<G extends Game>(G game) async {
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

  test(
    'a Game2D registers both payload decoders, with no canvas built',
    () async {
      expect(AssetLoaders.isRegistered<Texture>(), isFalse);
      expect(AssetLoaders.isRegistered<AudioClip>(), isFalse);

      await _boot(_Game());

      expect(
        AssetLoaders.isRegistered<Texture>(),
        isTrue,
        reason:
            'nothing here builds a DrawCanvas2D, and that used to be the only '
            'place a texture decoder was ever registered',
      );
      expect(
        AssetLoaders.isRegistered<AudioClip>(),
        isTrue,
        reason: 'and this one was registered nowhere at all before #123',
      );
    },
  );

  test('an audio clip loads instead of throwing', () async {
    await _boot(_Game());

    final key = AudioKey(MemorySource(_oggish, name: 'shot.ogg'));
    final clip = await AssetLoaders.of<AudioClip>().load(key);

    expect(clip.bytes, _oggish);
    expect(
      clip.format,
      AudioContainer.ogg,
      reason: 'the container comes from the source description',
    );
  });

  test('mixing in Renderer2D is enough to get the texture decoder', () async {
    await _boot(_Mixed());
    expect(
      AssetLoaders.isRegistered<Texture>(),
      isTrue,
      reason:
          'the decoder is registered by the mixin that provides rendering, so '
          'the documented "base class is already something else" path gets it '
          'from the same line that gets it the renderer',
    );
  });
}
