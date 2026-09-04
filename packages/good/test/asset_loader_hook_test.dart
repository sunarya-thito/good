// #123: who registers an asset decoder, and where.
//
// `AssetLoaders` is a per-isolate static map, so a decoder has to be
// registered on the isolate that decodes, before anything is loaded. Until
// this hook existed the only registration in the whole repository was
// `Texture`'s, inside `DrawCanvas2D`'s constructor - so a game that built no
// canvas decoded no textures, and `AudioClip`'s loader, which has no canvas to
// hang on, was never registered at all. Every `Audios.x` load threw.
//
// These cases pin the hook's semantics on one isolate. The property that
// cannot be tested here - that the *game* isolate registers nothing - needs a
// real spawn and lives in `game_isolate_test.dart`.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/asset_kinds.dart';
import 'package:good/src/audio/audio_clip.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'asset_loader_hook_test.g.dart';

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

/// The engine layer: registers one decoder.
class _EngineGame extends _BareGame {
  @override
  void describeAssetLoaders(AssetLoaderRegistrar loaders) {
    super.describeAssetLoaders(loaders);
    loaders.register<_Payload>(const _MarkLoader('engine'));
  }
}

/// A game on top of it, adding its own and replacing the engine's.
class _UserGame extends _EngineGame {
  @override
  void describeAssetLoaders(AssetLoaderRegistrar loaders) {
    super.describeAssetLoaders(loaders);
    loaders.register<_Other>(const _OtherLoader());
    loaders.register<_Payload>(const _MarkLoader('game'));
  }
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
  _installDeclarations();

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
          'the hook is opt-in, and nothing registers a decoder a game never '
          'asked for',
    );
  });

  test('a subclass registering after super replaces what it found', () async {
    // The ordering rule stated on AssetLoaders.register: later wins. It is
    // what lets a game substitute its own decoder for one the engine ships,
    // and it only reads that way because every layer calls super first.
    await _boot(_UserGame.new);
    expect(
      (AssetLoaders.of<_Payload>() as _MarkLoader).mark,
      'game',
      reason: 'the game registered the same type after its super call',
    );
    expect(
      AssetLoaders.isRegistered<_Other>(),
      isTrue,
      reason: 'and the type only it declared is registered too',
    );
  });

  test('the kernel registers its own payload types unasked', () async {
    // What the kernel ships is every payload that needs no device to decode -
    // bytes and a container name for audio, `dart:convert` for JSON and text,
    // nothing at all for a blob. No canvas and no dimension in any of them, so
    // the kernel registers their decoders and every game gets them without
    // declaring anything. That is what lets a 3D project load a sound (#93)
    // and what gives a level layout or a save file somewhere to go (#357);
    // goo3d declares no loaders at all.
    await _boot(_BareGame.new);
    expect(AssetLoaders.isRegistered<AudioClip>(), isTrue);
    expect(AssetLoaders.isRegistered<JsonValue>(), isTrue);
    expect(AssetLoaders.isRegistered<String>(), isTrue);
    expect(AssetLoaders.isRegistered<Uint8List>(), isTrue);
  });

  test(
    'a game that overrides the hook still inherits the kernel decoder',
    () async {
      await _boot(_UserGame.new);
      expect(
        AssetLoaders.isRegistered<AudioClip>(),
        isTrue,
        reason: 'the super chain reaches Game, which registers it',
      );
    },
  );

  test('the engine layer still contributes when the game adds its own', () async {
    // The failure this guards is a subclass that overrides the hook and forgets
    // super - which #64's checker now fails the build over, and which this
    // asserts the consequence of.
    await _boot(_UserGame.new);
    expect(AssetLoaders.isRegistered<_Payload>(), isTrue);
    expect(AssetLoaders.isRegistered<_Other>(), isTrue);
  });
}
