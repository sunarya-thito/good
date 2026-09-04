import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kPrimaryMouseButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:good/good.dart';

part 'stacked_game_view_test.g.dart';

// #275. Two `GameView`s in a `Stack` - the way a HUD is composed over a world
// - turned one finger into two live contacts under one id, and let the view
// behind name itself as the one the cursor is in.
//
// `GameView`'s `Listener` is `HitTestBehavior.translucent`, so every view the
// pointer passes through is handed the same dispatch and every one of them
// wrote to the device. The contact table saw a second press of an id already
// down and opened a second slot for it; the cursor's view address was
// overwritten by whichever view was hit last, which is the one furthest back.

/// The live run under test.
late Game run;

/// What [_ContactSystem] read on the last fixed step it ran.
final List<String> seen = <String>[];

class _ContactSystem extends GameSystem with FixedTickable {
  final contacts = Input.of<PointerContacts>(const ContactBinding());

  @override
  void onFixedUpdate() {
    final game = run as _StackedGame;
    final list = contacts.value;
    seen.clear();
    for (var i = 0; i < list.count; i++) {
      final contact = list[i];
      final view = game.viewOfContact(contact);
      final name = view == game.hud
          ? 'hud'
          : view == game.world
          ? 'world'
          : 'none';
      seen.add('#${contact.id} ${contact.phase.name} view=$name');
    }
  }
}

class _StackedState extends GameState<_StackedGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_ContactSystem.new);
  }
}

class _StackedGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  GameState createState() => _StackedState();

  /// The world layer, drawn first and so furthest back.
  late final CameraView world;

  /// The layer a HUD would live on, drawn over [world].
  late final CameraView hud;

  @override
  void describeCameras(CameraDescriptor descriptor) {
    super.describeCameras(descriptor);
    world = descriptor.has();
    hud = descriptor.has();
  }

  /// A surface with a size. `GameView` wraps whatever this returns in its
  /// `Listener`, so a view that builds nothing is a zero-sized hit target and
  /// no pointer ever reaches it - which is a game with no renderer, not the
  /// composition under test here.
  @override
  Widget? buildView(BuildContext context, CameraView? camera) =>
      const SizedBox.expand();
}

Future<_StackedGame> _start() async {
  final game = await Game.startInline(_StackedGame.new);
  run = game;
  seen.clear();
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

/// The composition #114 settles on: a HUD layer over a world layer, both
/// `GameView`s, both filling the same box.
///
/// `Alignment.topLeft` because the default is directional and there is no
/// `Directionality` over a bare `GameView`. `Center` around the `SizedBox`
/// because `pumpWidget` hands its child *tight* constraints, so an uncentred
/// box is stretched to the surface and the views stop being the size the
/// test asked for.
Future<void> _stack(WidgetTester tester, _StackedGame game) =>
    tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: Stack(
            alignment: Alignment.topLeft,
            children: <Widget>[
              GameView(camera: game.world),
              GameView(camera: game.hud),
            ],
          ),
        ),
      ),
    );

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  testWidgets('one finger through two stacked views is one contact', (
    tester,
  ) async {
    final game = await _start();
    await _stack(tester, game);

    await tester.tapAt(const Offset(400, 300));
    run.state.runFixedStep();

    expect(
      seen,
      hasLength(1),
      reason:
          'one finger is one contact however many views it passes through - '
          'a second entry is the same id opened twice, once per view the '
          'translucent hit test handed the dispatch to',
    );
  });

  // Passes before the fix as well as after: the front view wrote first, so
  // the surviving contact already named it. It is here to say which of the
  // two the claim keeps - a claim taken by the last caller instead of the
  // first reads `view=world` and leaves the count right.
  testWidgets('the contact that survives names the view drawn in front', (
    tester,
  ) async {
    final game = await _start();
    await _stack(tester, game);

    await tester.tapAt(const Offset(400, 300));
    run.state.runFixedStep();

    expect(seen.first, endsWith('view=hud'));
  });

  // The half that stops the first test passing for the wrong reason. A gate
  // that swallowed everything after the first pointer of a frame, or dropped
  // a dispatch whose id was already down, would report one contact here too.
  testWidgets('two fingers through two stacked views are two contacts', (
    tester,
  ) async {
    final game = await _start();
    await _stack(tester, game);

    final first = await tester.startGesture(const Offset(300, 250));
    final second = await tester.startGesture(const Offset(500, 350));
    run.state.runFixedStep();

    expect(
      seen,
      hasLength(2),
      reason:
          'two fingers are two dispatches, and each is claimed by the front '
          'view on its own',
    );

    await first.up();
    await second.up();
  });

  // The other way the gate can be too wide: a claim that is never released
  // takes the first dispatch of the run and refuses every one after it.
  testWidgets('a second tap after the first opens a contact of its own', (
    tester,
  ) async {
    final game = await _start();
    await _stack(tester, game);

    await tester.tapAt(const Offset(400, 300));
    run.state.runFixedStep();
    final firstTap = List<String>.of(seen);

    await tester.tapAt(const Offset(420, 320));
    run.state.runFixedStep();

    expect(firstTap, hasLength(1));
    expect(
      seen,
      hasLength(1),
      reason: 'the claim is per dispatch, so the next one is claimable again',
    );
    expect(
      seen.first,
      isNot(equals(firstTap.first)),
      reason: 'a fresh finger is a fresh id, not the first one reported twice',
    );
  });

  // The surface size travels with the claim, and is measured separately
  // because it is written by a second call. A HUD panel over a world view is
  // the case where the two views are not the same size, so whichever of them
  // wrote last is a number a test can read.
  testWidgets('a panel over a full-size view reports the panel size', (
    tester,
  ) async {
    final game = await _start();
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: Stack(
            alignment: Alignment.topLeft,
            children: <Widget>[
              GameView(camera: game.world),
              Positioned(
                left: 0,
                top: 0,
                width: 200,
                height: 150,
                child: GameView(camera: game.hud),
              ),
            ],
          ),
        ),
      ),
    );

    // Inside the panel, so both views are in the hit path.
    await tester.tapAt(const Offset(250, 200));
    run.state.runFixedStep();

    expect(run.viewWidth, 200.0);
    expect(
      run.viewHeight,
      150.0,
      reason:
          'the size belongs to the view the finger landed in, and the view '
          'behind must not write its own by being handed the same dispatch',
    );
  });

  // A game with one `GameView` is the ordinary case, and the gate must let it
  // through: the first caller of a dispatch is the only caller.
  testWidgets('one view on its own still reads the finger', (tester) async {
    final game = await _start();
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: GameView(camera: game.world),
        ),
      ),
    );

    await tester.tapAt(const Offset(400, 300));
    run.state.runFixedStep();

    // The id is whatever Flutter's running count is up to by now, so the
    // assertion is on the phase and the view.
    expect(seen, hasLength(1));
    expect(seen.first, endsWith('ended view=world'));
  });

  // A mouse with a button held, which is what dispatches through this
  // binding: `onPointerHover` never fires here, so the cursor's view address
  // is measured on a press and not on a hover. The two write `pointerView`
  // through the same line of `handlePointerEvent`, and a hover crossing
  // between two views is what `goo2d`'s multi_view_test records as needing a
  // device.
  testWidgets('a mouse press through two stacked views names the front view', (
    tester,
  ) async {
    final game = await _start();
    await _stack(tester, game);

    final gesture = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    addTearDown(() => gesture.up());
    run.state.runFixedStep();

    expect(
      run.pointerView,
      same(game.hud),
      reason:
          'the cursor is in the view drawn over the others, and the one '
          'behind must not overwrite it by being hit last',
    );
  });
}
