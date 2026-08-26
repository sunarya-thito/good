import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:good/good.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// #174. `Game.viewWidth` read zero on a `GameView` that shows a camera, and
// stayed zero until a pointer event landed. On a game played with a keyboard
// or a pad, that is forever.
//
// The layout builder in game_view.dart wrote the size only when
// `widget.camera == null`; with a camera the sole writer was
// `_onPointerEvent`. The guard was there for a reason - every view on screen
// lays out on every rebuild, so an unguarded write lets whichever laid out
// last overwrite whichever the pointer is in - so the fix is not to drop it.
// `InputDevice.seedViewSize` writes from layout only while no pointer event
// has claimed the size, which leaves the multi-view behaviour untouched and
// gives a no-pointer game a size that also survives a resize.

class _CameraGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  GameState createState() => _State();

  late final CameraView main;

  @override
  void describeCameras(CameraDescriptor descriptor) {
    super.describeCameras(descriptor);
    main = descriptor.has();
  }

  @override
  Widget? buildView(BuildContext context, CameraView? camera) => null;
}

class _State extends GameState<Game> {}

Future<T> _start<T extends Game>(T game) async {
  run = await Game.startInline(game);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

/// Lays the view out at exactly [width] x [height].
///
/// `Center` is load-bearing: `pumpWidget` hands its child the test surface's
/// *tight* constraints, so a bare `SizedBox` is stretched to 800x600 and the
/// builder never sees the size the test asked for. Loosening them first is
/// what makes the asserted number a number the widget was actually given,
/// and one the surface size cannot supply by accident.
Future<void> _layout(
  WidgetTester tester,
  CameraView camera, {
  required double width,
  required double height,
}) => tester.pumpWidget(
  Center(
    child: SizedBox(
      width: width,
      height: height,
      child: GameView(camera: camera),
    ),
  ),
);

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  // The test that has to be able to fail: no pointer event anywhere in it.
  // Every existing test either had no camera or moved a pointer first, which
  // is how the bug survived.
  testWidgets(
    'viewWidth and viewHeight are the layout size with a camera and no '
    'pointer event',
    (tester) async {
      final game = await _start(_CameraGame());

      await _layout(tester, game.main, width: 320, height: 240);

      // One fixed step, so the published block is copied into the state the
      // game reads. Nothing has touched the pointer - this is the situation
      // the bug lived in.
      run.state.runFixedStep();

      expect(run.viewWidth, 320.0);
      expect(run.viewHeight, 240.0);
    },
  );

  // The other half, and the reason "has the size been written yet" is the
  // wrong question to ask: a window resize on a game with no pointer used to
  // leave the first frame's size in place for good.
  testWidgets('a resize with a camera and no pointer event is picked up', (
    tester,
  ) async {
    final game = await _start(_CameraGame());

    await _layout(tester, game.main, width: 320, height: 240);
    run.state.runFixedStep();
    expect(run.viewWidth, 320.0, reason: 'first layout should seed the size');

    await _layout(tester, game.main, width: 512, height: 384);
    run.state.runFixedStep();

    expect(run.viewWidth, 512.0);
    expect(run.viewHeight, 384.0);
  });
}
