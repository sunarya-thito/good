// #123: who declares an asset decoder, and where it is built.
//
// `AssetLoaders` is a per-isolate static map, so a decoder has to be
// registered on the isolate that decodes, before anything is loaded. Before
// #123 the only registration in the whole repository was `Texture`'s, inside
// `DrawCanvas2D`'s constructor - so a game that built no canvas decoded no
// textures, and `AudioClip`'s loader, which has no canvas to hang on, was
// never registered at all. Every `Audios.x` load threw.
//
// These cases pin `AssetLoader.of`'s semantics on one isolate: that a
// declaration is built and filed by boot, that the most derived one wins, and
// that a game declaring none still gets the kernel's. The property that cannot
// be tested here - that the *game* isolate registers nothing - needs a real
// spawn and lives in `game_isolate_test.dart`.
import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/audio/audio_clip.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene_handle.dart';

class _Payload {
  const _Payload(this.mark);
  final String mark;
}

class _Info extends AssetInfo {
  const _Info();
}

/// Two loaders for one payload type, so a test can tell which registration won.
class _MarkLoader extends AssetLoader<_Payload> {
  const _MarkLoader(this.mark);
  final String mark;

  @override
  Future<_Payload> load(AssetKey<_Payload> key) async => _Payload(mark);

  @override
  AssetInfo describe(_Payload value) => const _Info();
}

class _Other {}

class _OtherLoader extends AssetLoader<_Other> {
  const _OtherLoader();

  @override
  Future<_Other> load(AssetKey<_Other> key) async => _Other();

  @override
  AssetInfo describe(_Other value) => const _Info();
}

class _BareState extends GameState<Game> {}

/// Registers nothing, to show the hook is opt-in.
class _BareGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _BareState();
}

/// The engine layer: declares one decoder.
class _EngineGame extends _BareGame {
  final payload = AssetLoader.of(() => const _MarkLoader('engine'));
}

/// A game on top of it, adding its own and replacing the engine's.
class _UserGame extends _EngineGame {
  final other = AssetLoader.of(_OtherLoader.new);
  final ownPayload = AssetLoader.of(() => const _MarkLoader('game'));
}

/// A decoder written `late`, ahead of the eager one, for the same reason every
/// other declaration has a case like it.
class _LateLoaderGame extends _BareGame {
  late final lazyPayload = AssetLoader.of(() => const _MarkLoader('late'));

  final other = AssetLoader.of(_OtherLoader.new);
}

Future<G> _boot<G extends Game>(G Function() create) async {
  final run = await Game.startInline(create);
  final game = run;
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
    'a declared loader is registered by the time the game is running',
    () async {
      expect(AssetLoaders.isRegistered<_Payload>(), isFalse);
      await _boot(_EngineGame.new);
      expect(AssetLoaders.isRegistered<_Payload>(), isTrue);
      expect(
        (AssetLoaders.of<_Payload>() as _MarkLoader).mark,
        'engine',
        reason: 'the decoder the game declared is the one that answers',
      );
    },
  );

  test('a game that declares none registers none', () async {
    await _boot(_BareGame.new);
    expect(
      AssetLoaders.isRegistered<_Payload>(),
      isFalse,
      reason:
          'a declaration is opt-in, and nothing registers a decoder a game '
          'never asked for',
    );
  });

  test('a late decoder reaches no pass at all', () async {
    final game = await _boot(_LateLoaderGame.new);

    expect(
      AssetLoaders.isRegistered<_Other>(),
      isTrue,
      reason:
          'the eager one registered, so the window was open and working and '
          'the throw below is the closed-window guard',
    );
    expect(
      AssetLoaders.isRegistered<_Payload>(),
      isFalse,
      reason:
          'written first and still not registered: a late initialiser runs on '
          'first read, after boot built and filed the declared decoders',
    );
    expect(
      () => game.lazyPayload,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('no game being constructed'),
            contains('eager, always'),
          ),
        ),
      ),
    );
  });

  test(
    'the most derived declaration for a type is the one that answers',
    () async {
      // The ordering rule stated on AssetLoaders.register: later wins, and boot
      // installs back to front so "later" comes out as "more derived". It is
      // what lets a game substitute its own decoder for one the engine ships,
      // and there is no super call for it to depend on.
      final game = await _boot(_UserGame.new);
      expect(
        (AssetLoaders.of<_Payload>() as _MarkLoader).mark,
        'game',
        reason: 'the subclass declared the same payload type as its base',
      );
      expect(
        ((game.payload.value) as _MarkLoader).mark,
        'game',
        reason:
            'and the base class handle answers with the winner too, because a '
            'handle answers for the payload type rather than restating the '
            'loader it was handed',
      );
      expect(
        AssetLoaders.isRegistered<_Other>(),
        isTrue,
        reason: 'and the type only it declared is registered too',
      );
    },
  );

  test('the kernel registers its own payload type unasked', () async {
    // `AudioClip` is the one payload the kernel ships - bytes and a container
    // name, no canvas and no dimension - so the kernel registers its decoder
    // and every game gets audio loading without declaring anything. That is
    // what lets a 3D project load a sound (#93); goo3d declares no loaders at
    // all.
    await _boot(_BareGame.new);
    expect(AssetLoaders.isRegistered<AudioClip>(), isTrue);
  });

  test('a game declaring its own still inherits the kernel decoder', () async {
    await _boot(_UserGame.new);
    expect(
      AssetLoaders.isRegistered<AudioClip>(),
      isTrue,
      reason:
          'the kernel files its own ahead of every declaration, so there is '
          'nothing a game can do to drop it - the failure this replaces was '
          'an override that forgot its super call',
    );
  });

  test(
    'the engine layer still contributes when the game adds its own',
    () async {
      await _boot(_UserGame.new);
      expect(AssetLoaders.isRegistered<_Payload>(), isTrue);
      expect(AssetLoaders.isRegistered<_Other>(), isTrue);
    },
  );
}
