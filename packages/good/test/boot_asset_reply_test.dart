import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/event/state.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/system.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'boot_asset_reply_test.g.dart';

// The boot window in which main can produce a reply the game isolate is
// already waiting on.
//
// `GameRuntime.runOnIsolate` mounts the world and *then* sends `ready`, so a
// `loadScene` in `GameState.onMounted` sends `loadAssets` to main first.
// `ready` is what carries the port main answers over, so between the two
// messages main has a request in hand and nowhere to reply to.
//
// Every reply the request produces has to survive that window. What used to
// close it by accident was the decode: main handles `loadAssets` before
// `ready`, and awaiting a real file read yields to the event loop, which is
// where `ready` gets delivered. A source that resolves entirely in microtasks
// never yields, so the whole decode - and both of its replies - happens before
// `ready` lands (#260).
//
// A spawned run, therefore, and not `Game.startInline`: inline has
// `decodesAssets` true, decodes in place through `_reconcileAssets` and sends
// no message at all, so an inline version of this test passes whether or not
// the window is closed.

/// Set on the game isolate when the `onMounted` load returns.
///
/// A per-isolate static, published into a state channel by a system once a
/// tick. That is the only way a number gets back: this isolate registers no
/// archetypes and holds no pages.
int _sceneLoadedHere = 0;

/// A decoded payload with nothing in it. `_Blob` exists so this file registers
/// its own loader and does not borrow one whose behaviour it does not control.
class _Blob {
  const _Blob(this.byteCount);

  final int byteCount;
}

class _BlobLoader extends AssetLoader<_Blob> {
  const _BlobLoader();

  @override
  Future<_Blob> load(AssetKey<_Blob> key) async =>
      _Blob((await key.source.load()).length);
}

/// Resolves without ever yielding to the event loop.
///
/// `async` with no `await` in the body: the future completes in a microtask,
/// and the microtask queue drains completely between two port messages. This
/// is what `MemorySource` is - the documented source for tests and generated
/// content - so it is not a contrived shape.
class _SynchronousSource extends AssetSource {
  const _SynchronousSource(this.name);

  final String name;

  @override
  Future<Uint8List> load() async => Uint8List(4);

  @override
  Future<AssetAvailability> check() async => AssetAvailability.present;

  @override
  String get description => name;

  @override
  bool operator ==(Object other) =>
      other is _SynchronousSource && other.name == name;

  @override
  int get hashCode => Object.hash(_SynchronousSource, name);
}

/// The same source with one event-loop turn in it.
///
/// The control for the test below: everything else about the two runs is
/// identical, so a pass here and a failure there isolates the missing turn as
/// the cause and nothing else.
class _YieldingSource extends AssetSource {
  const _YieldingSource(this.name);

  final String name;

  @override
  Future<Uint8List> load() async {
    await Future<void>.delayed(Duration.zero);
    return Uint8List(4);
  }

  @override
  Future<AssetAvailability> check() async => AssetAvailability.present;

  @override
  String get description => name;

  @override
  bool operator ==(Object other) =>
      other is _YieldingSource && other.name == name;

  @override
  int get hashCode => Object.hash(_YieldingSource, name);
}

const AssetKey<_Blob> _synchronousBlob = AssetKey<_Blob>(
  _SynchronousSource('synchronous-blob'),
);

const AssetKey<_Blob> _yieldingBlob = AssetKey<_Blob>(
  _YieldingSource('yielding-blob'),
);

class _SynchronousScene extends SceneStruct {
  final blob = Asset.of(_synchronousBlob);
}

class _YieldingScene extends SceneStruct {
  final blob = Asset.of(_yieldingBlob);
}

/// Carries [_sceneLoadedHere] back across the boundary, once a tick.
class _Reporter extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() =>
      (state.game as _BootLoadGame).loaded.value = _sceneLoadedHere;
}

class _BootLoadState extends GameState<_BootLoadGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_Reporter.new);
  }

  @override
  void onMounted() {
    unawaited(_load());
  }

  Future<void> _load() async {
    await loadScene(game.scene);
    _sceneLoadedHere = 1;
  }
}

abstract class _BootLoadGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  late final SceneStruct scene;

  /// Written on the game isolate, read here.
  final loaded = Channel.int32();

  @override
  void describeAssetLoaders(AssetLoaderRegistrar loaders) {
    super.describeAssetLoaders(loaders);
    loaders.register<_Blob>(const _BlobLoader());
  }

  @override
  GameState createState() => _BootLoadState();
}

class _SynchronousGame extends _BootLoadGame {
  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    scene = descriptor.has(_SynchronousScene());
  }
}

class _YieldingGame extends _BootLoadGame {
  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    scene = descriptor.has(_YieldingScene());
  }
}

late Game _run;

void main() {
  _installDeclarations();

  setUp(() {
    _sceneLoadedHere = 0;
  });

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
  });

  test('a scene loaded from onMounted completes when its source never yields', () async {
    final game = await Game.start(_SynchronousGame.new);
    _run = game;
    addTearDown(() async {
      if (_run.isRunning) await _run.stop();
    });

    expect(
      await _waitUntil(game, () => game.loaded.value == 1),
      isTrue,
      reason:
          'the scene never loaded. Its one asset decodes without yielding, so '
          'main finished the request - and produced both of its replies - '
          'before `ready` gave it the port to answer over. A dropped reply '
          'leaves the `Completer` inside `_AssetLoadRequest` uncompleted and '
          'the `await loadScene` in `onMounted` never returns (#260)',
    );

    await _run.stop();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'and when it yields, which is the only difference between the two',
    () async {
      final game = await Game.start(_YieldingGame.new);
      _run = game;
      addTearDown(() async {
        if (_run.isRunning) await _run.stop();
      });

      expect(
        await _waitUntil(game, () => game.loaded.value == 1),
        isTrue,
        reason:
            'one event-loop turn inside the decode is enough for `ready` to be '
            'delivered mid-request, so the replies find a port even with '
            'nothing holding them. This run passes on either side of the fix; '
            'it is here so a failure of the run above is attributable to the '
            'missing turn and not to the fixture',
      );

      await _run.stop();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

Future<bool> _waitUntil(
  Game run,
  bool Function() done, {
  int within = 60,
}) async {
  for (var i = 0; i < within; i++) {
    if (done()) return true;
    await _waitTicks(run, 1);
  }
  return done();
}

Future<void> _waitTicks(Game run, int count) {
  final target = run.tick + count;
  final reached = Completer<void>();
  void listener(int tick) {
    if (tick >= target && !reached.isCompleted) reached.complete();
  }

  // Through `runtimeOrNull` rather than a public hook, matching
  // game_isolate_test.dart and audio_isolate_test.dart: tick listening is
  // framework plumbing and is not API.
  final runtime = run.runtimeOrNull!;
  runtime.addTickListener(listener);
  return reached.future
      .timeout(const Duration(seconds: 20))
      .whenComplete(() => runtime.removeTickListener(listener));
}
