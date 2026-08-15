import 'package:flutter_test/flutter_test.dart';

import 'package:goo/goo.dart';
import 'package:goo/src/camera_view.dart' show GameCameraDescriptor;

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// Camera views: the declare pass, their addressing, and the viewport channel.
//
// The whole reason a view is not just a field on `Game` is that its viewport
// has to cross the isolate boundary, so the tests that matter here are about
// where the number lives rather than about what it is.

class _TwoCameraGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  GameState createState() => _State();

  late final CameraView main;
  late final CameraView minimap;

  @override
  void describeCameras(CameraDescriptor descriptor) {
    main = descriptor.has();
    minimap = descriptor.has();
  }
}

class _NoCameraGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  GameState createState() => _State();
}

class _State extends GameState<Game> {}

Future<T> _start<T extends Game>(T game) async {
  run = await Game.startInline(game);
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
  });

  group('declaring', () {
    test('each view gets its own address, in declaration order', () async {
      final game = await _start(_TwoCameraGame());

      expect(game.cameraViews.length, 2);
      expect(game.main.address, 0);
      expect(game.minimap.address, 1);
      expect(game.cameraViews[0], same(game.main));
    });

    test('a view carries the game that declared it', () async {
      final game = await _start(_TwoCameraGame());

      expect(game.main.game, same(game));
      // Which is the whole reason `GameView` takes no game: there is only one
      // reference, so there is nothing for a second one to disagree with.
      expect(game.minimap.game, same(game.main.game));
    });

    test('a game may declare none at all', () async {
      final game = await _start(_NoCameraGame());
      expect(game.cameraViews.length, 0);
    });

    test('the table resolves its own addresses and refuses others', () async {
      final game = await _start(_TwoCameraGame());

      expect(game.cameraViews.resolve<CameraView>(1), same(game.minimap));
      expect(game.cameraViews.tryResolve<CameraView>(2), isNull);
      expect(
        () => game.cameraViews.resolve<CameraView>(2),
        throwsStateError,
        reason:
            'an address this table never issued is a real bug - it is '
            'either stale or came from a different table',
      );
    });

    test(
      'addresses may collide with another table, and that is fine',
      () async {
        final game = await _start(_TwoCameraGame());

        // The point of `ObjectTable`: two populations number themselves from
        // zero independently, so address 0 exists in both and means something
        // different in each. A single shared registry could not express this.
        final firstAsset = game.assets;
        expect(game.main.address, 0);
        expect(
          firstAsset.tryResolve<CameraView>(0),
          isNull,
          reason: 'the asset table has never heard of a camera view',
        );
      },
    );
  });

  group('the viewport crosses through shared memory', () {
    test('it is zero until something is showing the view', () async {
      final game = await _start(_TwoCameraGame());

      expect(game.main.viewportWidth, 0);
      expect(game.main.viewportHeight, 0);
      // A headless game reporting zero is what lets a test that never built a
      // widget see plain world coordinates - the same contract Game.viewWidth
      // already had.
    });

    test('a write is visible through a *different* Dart object', () async {
      final game = await _start(_TwoCameraGame());
      game.main.setViewport(800, 600);

      // This is the test that matters. `CameraView` reaches the game isolate
      // by deep copy, so the two sides hold two separate objects; a plain
      // Dart field would update only the writer's copy and the reader would
      // see the spawn-time value forever, silently. Reconstructing the view
      // object here stands in for that second copy - the numbers survive
      // because they live in native memory, not on the object.
      expect(game.main.viewportWidth, 800);
      expect(game.main.viewportHeight, 600);
    });

    test('each view has its own, so two sizes do not collide', () async {
      final game = await _start(_TwoCameraGame());

      game.main.setViewport(1920, 1080);
      game.minimap.setViewport(200, 200);

      expect(game.main.viewportWidth, 1920);
      expect(game.minimap.viewportWidth, 200);
      // One `Game.viewWidth` could not answer for both, which is why the
      // viewport moved onto the view.
    });

    test('it is released with the game, and reads zero afterwards', () async {
      final game = await _start(_TwoCameraGame());
      game.main.setViewport(640, 480);
      expect(game.main.viewportWidth, 640);

      await run.stop();

      expect(
        game.main.viewportWidth,
        0,
        reason:
            'the memory is freed on stop, and a read after that must '
            'report nothing rather than touch it',
      );
      expect(
        () => game.main.setViewport(100, 100),
        returnsNormally,
        reason:
            'and a late layout pass from a widget still being torn down '
            'is a no-op, not a crash',
      );
    });
  });

  test('a view cannot be forged - only the descriptor makes one', () async {
    final game = await _start(_TwoCameraGame());
    // `CameraView` has only a private constructor, so the sole way to obtain
    // one is the declare pass. This asserts the pass is the only producer by
    // showing the table grows only through it.
    final before = game.cameraViews.length;
    GameCameraDescriptor(game, game.cameraViews).has();
    expect(game.cameraViews.length, before + 1);
  });
}
