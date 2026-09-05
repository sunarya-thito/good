import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

part 'multi_view_test.g.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// Two views, two cameras, two scenes - the thing the whole camera-view design
// exists for, asserted end to end.
//
// Everything else about cameras is unit-level (good's camera_view_test) or
// exercises the single-view path (render_2d_test, game_view_test). This file
// is the one that would fail if per-view rendering were quietly still global.

class _Sprite extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  final quad = Sprite.of(width: 10, height: 10);
}

class _Eye extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

/// What every receiver in this file appends to.
final List<String> events = <String>[];

/// Drawable *and* clickable, which is what makes it able to tell the renderer
/// and the picker apart: anything it reports here it should also have drawn a
/// quad for.
class _Target extends EntityStruct
    with
        Transform2D,
        WorldTransform2D,
        Renderable2D,
        Collider2D,
        PointerReceiver,
        HoverReceiver {
  final quad = Sprite.of(width: 40, height: 40);
  late final BoxBody hitArea;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    hitArea = descriptor.hasBoxCollider(halfWidth: 20, halfHeight: 20);
  }

  @override
  void onHoverEnter(PointerPickEvent event) => events.add('enter');

  @override
  void onHover(PointerPickEvent event) => events.add('hover');

  @override
  void onHoverExit(PointerPickEvent event) => events.add('exit');

  /// Records the entity, because the point of the two-view contact test is
  /// which entity each finger reached.
  @override
  void onPointerDown(PointerPickEvent event) =>
      events.add('down ${event.entity.value} at ${event.worldSpace.x}');
}

class _Level extends SceneStruct {
  @override
  void onSceneMounted(Scene scene) => handle = scene;

  late Scene handle;

  @sub
  final sprite = _Sprite();
  @sub
  final eye = _Eye();
  @sub
  final target = _Target();
}

/// A second, structurally identical scene type. Two *types* rather than two
/// loads of one, so each has its own prefabs and the sprites cannot be
/// confused for each other.
class _Overlay extends SceneStruct {
  @override
  void onSceneMounted(Scene scene) => handle = scene;

  late Scene handle;

  @sub
  final sprite = _Sprite();
  @sub
  final eye = _Eye();
  @sub
  final target = _Target();
}

class _MultiState extends GameState2D<_MultiGame> {
  late final _Level level;
  late final _Overlay overlay;

  @override
  void onMounted() {
    level = _Level();
    overlay = _Overlay();
    loadScene(level);
    loadScene(overlay);
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(PointerPickingSystem.new);
  }
}

class _MultiGame extends Game2D {
  @override
  int get pageSize => 8192;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  /// `defaultCamera` is address 0 and comes from `Renderer2D`; this is the
  /// second one, and calling super is what keeps that ordering.
  late final CameraView minimap;

  @override
  void describeCameras(CameraDescriptor descriptor) {
    super.describeCameras(descriptor);
    minimap = descriptor.has();
  }

  @override
  GameState2D<_MultiGame> createState() => _MultiState();
}

const Duration _step = Duration(milliseconds: 10);

Future<_MultiGame> _start() async {
  final game = await Game.startInline(_MultiGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

/// How many bytes the newest frame for [view] occupies, or null if nothing has
/// been published for it.
int? _publishedBytes(_MultiGame game, CameraView view) {
  final buffer = run.state.getSystem<GameRenderer2D>().framesFor(view).buffer;
  return buffer.beginRead() == null ? null : buffer.readUsedBytes;
}

/// How many quads the newest frame for [view] carries. Reading the published
/// batch rather than `lastSpriteCount`, which is the total across every view
/// and so cannot say which view drew what.
int _publishedQuads(_MultiGame game, CameraView view) {
  final buffer = run.state.getSystem<GameRenderer2D>().framesFor(view).buffer;
  if (buffer.beginRead() == null) return 0;
  return const DrawSpriteData2D().itemCount(buffer.readUsedBytes);
}

void main() {
  _installDeclarations();

  setUp(events.clear);

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  testWidgets('each view draws the scene its own camera is in', (tester) async {
    final game = await _start();
    final state = run.state as _MultiState;
    final level = state.level;
    final overlay = state.overlay;

    // One sprite in the level, two in the overlay - different counts so the
    // two views cannot accidentally agree.
    level.handle.addEntity(level.sprite);
    overlay.handle.addEntity(overlay.sprite);
    overlay.handle.addEntity(overlay.sprite);

    // A camera in each scene, each occupying a different view.
    final levelEye = level.handle.addEntity(level.eye);
    level.eye.cameraView[levelEye] = game.defaultCamera;
    final overlayEye = overlay.handle.addEntity(overlay.eye);
    overlay.eye.cameraView[overlayEye] = game.minimap;

    run.state.advance(_step);

    // Three, not six. Each view walked every renderable in the game and kept
    // only the ones sharing a scene with its camera - which is what replaced
    // the deleted global front scene. Without that scoping both views would
    // draw all three sprites and this would read six.
    expect(
      run.state.getSystem<GameRenderer2D>().lastSpriteCount,
      3,
      reason: 'one sprite for the level view, two for the overlay view',
    );

    // And they landed in *different* buffers, carrying different amounts.
    final levelBytes = _publishedBytes(game, game.defaultCamera);
    final overlayBytes = _publishedBytes(game, game.minimap);
    expect(levelBytes, isNotNull);
    expect(overlayBytes, isNotNull);
    expect(
      overlayBytes! > levelBytes!,
      isTrue,
      reason:
          'two quads occupy more of a slot than one - the two views did '
          'not write the same bytes, which is the whole claim',
    );
  });

  testWidgets('a view whose camera is elsewhere still draws its own scene', (
    tester,
  ) async {
    final game = await _start();
    final state = run.state as _MultiState;

    state.level.handle.addEntity(state.level.sprite);
    final eye = state.overlay.handle.addEntity(state.overlay.eye);
    state.overlay.eye.cameraView[eye] = game.minimap;

    run.state.advance(_step);

    // The minimap's camera is in the overlay, which holds no sprites, so it
    // publishes an empty frame rather than borrowing the level's.
    final levelBytes = _publishedBytes(game, game.defaultCamera)!;
    final minimapBytes = _publishedBytes(game, game.minimap)!;
    expect(
      minimapBytes < levelBytes,
      isTrue,
      reason:
          'an empty scene draws nothing, and must not fall back to '
          'whatever another view is looking at',
    );
  });

  testWidgets('two GameViews on two cameras both paint', (tester) async {
    final game = await _start();
    final state = run.state as _MultiState;
    state.level.handle.addEntity(state.level.sprite);
    state.overlay.handle.addEntity(state.overlay.sprite);

    final levelEye = state.level.handle.addEntity(state.level.eye);
    state.level.eye.cameraView[levelEye] = game.defaultCamera;
    final overlayEye = state.overlay.handle.addEntity(state.overlay.eye);
    state.overlay.eye.cameraView[overlayEye] = game.minimap;

    await tester.pumpWidget(
      Row(
        textDirection: TextDirection.ltr,
        children: <Widget>[
          Expanded(child: GameView(camera: game.defaultCamera)),
          Expanded(child: GameView(camera: game.minimap)),
        ],
      ),
    );

    run.state.advance(_step);
    await tester.pump();

    expect(
      find.byType(CustomPaint),
      findsNWidgets(2),
      reason: 'one painter per view, each fed by its own surface',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('each GameView reports its own size to its own view', (
    tester,
  ) async {
    final game = await _start();
    final state = run.state as _MultiState;
    final eye = state.level.handle.addEntity(state.level.eye);
    state.level.eye.cameraView[eye] = game.defaultCamera;

    await tester.pumpWidget(
      Row(
        textDirection: TextDirection.ltr,
        children: <Widget>[
          SizedBox(
            width: 200,
            height: 100,
            child: GameView(camera: game.defaultCamera),
          ),
          SizedBox(
            width: 600,
            height: 400,
            child: GameView(camera: game.minimap),
          ),
        ],
      ),
    );

    // The reason the viewport moved off `Game` and onto the view: one number
    // could not have answered for both of these, and the projection centres on
    // it - so a shared number would put one of the two cameras off-centre.
    expect(game.defaultCamera.viewportWidth, 200);
    expect(game.defaultCamera.viewportHeight, 100);
    expect(game.minimap.viewportWidth, 600);
    expect(game.minimap.viewportHeight, 400);
  });

  testWidgets('the pointer picks against the view it is actually over', (
    tester,
  ) async {
    final game = await _start();
    final state = run.state as _MultiState;

    // The two cameras sit a thousand units apart, so the *same* pointer
    // position means two completely different world points. Without routing
    // this test cannot tell the views apart; with it, the answer flips.
    final levelEye = state.level.handle.addEntity(state.level.eye);
    state.level.eye.cameraView[levelEye] = game.defaultCamera;
    final overlayEye = state.overlay.handle.addEntity(state.overlay.eye);
    state.overlay.eye
      ..cameraView[overlayEye] = game.minimap
      ..transformOffsetX[overlayEye] = 1000;

    game.defaultCamera.setViewport(400, 400);
    game.minimap.setViewport(400, 400);
    run.state.runFixedStep();

    final picking = run.state.getSystem<PointerPickingSystem>();

    game.inputDevice!.movePointer(
      screenX: 0,
      screenY: 0,
      viewX: 200,
      viewY: 200,
      view: game.defaultCamera,
    );
    run.state.runFixedStep();
    expect(game.pointerView, same(game.defaultCamera));
    expect(
      picking.worldSpace.x,
      0,
      reason:
          'the centre of a view is where its camera is, and the level '
          'camera is at the origin',
    );

    game.inputDevice!.movePointer(
      screenX: 0,
      screenY: 0,
      viewX: 200,
      viewY: 200,
      view: game.minimap,
    );
    run.state.runFixedStep();
    expect(game.pointerView, same(game.minimap));
    expect(
      picking.worldSpace.x,
      1000,
      reason:
          'same pixel, different view - so a different world point. '
          'Projecting through the first declared view instead would report '
          '0 here, which is a click landing on something the user is not '
          'even looking at',
    );
  });

  testWidgets('a click cannot land on an entity the view did not draw', (
    tester,
  ) async {
    final game = await _start();
    final state = run.state as _MultiState;

    // A camera per view, each in its own scene, and the one clickable target
    // in the overlay - so the level view has nothing to draw and the minimap
    // draws the target.
    final levelEye = state.level.handle.addEntity(state.level.eye);
    state.level.eye.cameraView[levelEye] = game.defaultCamera;
    final overlayEye = state.overlay.handle.addEntity(state.overlay.eye);
    state.overlay.eye.cameraView[overlayEye] = game.minimap;
    state.overlay.handle.addEntity(state.overlay.target);

    game.defaultCamera.setViewport(400, 400);
    game.minimap.setViewport(400, 400);
    run.state.advance(_step);
    events.clear();

    // Dead centre of the level view, which is where the level camera is and
    // where the target sits in world space too - both cameras are at the
    // origin, so the *only* thing between this pointer and that target is
    // which scene each is in.
    game.inputDevice!.movePointer(
      screenX: 0,
      screenY: 0,
      viewX: 200,
      viewY: 200,
      view: game.defaultCamera,
    );
    run.state.advance(_step);

    final picking = run.state.getSystem<PointerPickingSystem>();
    expect(_publishedQuads(game, game.defaultCamera), 0);
    expect(picking.hovered, isNull);
    expect(
      events,
      isEmpty,
      reason:
          'the picker walked every loaded scene until it read the view\'s '
          'scene slot, so this fired enter and hover on an entity the '
          'level view refused to draw',
    );

    // The other half, and it is what stops the first from passing for the
    // wrong reason: point at the view that *does* draw the target and it
    // picks exactly as it always did.
    game.inputDevice!.movePointer(
      screenX: 0,
      screenY: 0,
      viewX: 200,
      viewY: 200,
      view: game.minimap,
    );
    run.state.advance(_step);

    expect(_publishedQuads(game, game.minimap), 1);
    expect(picking.hovered, isNotNull);
    expect(events, contains('enter'));
  });

  // NOT COVERED: that `CursorPosition.viewSize` follows the pointer as it
  // crosses from one view into another of a different size. What cannot be
  // driven here is a **hover**, and a hover is the only way a cursor crosses.
  //
  // Established with an isolated probe (a *bare* `Listener`, no engine code in
  // sight): `onPointerHover` never fires by any route, and the textbook
  // recipe - `createGesture(kind: mouse)` then `addPointer` - trips a
  // `MouseTracker` assertion inside Flutter itself.
  //
  // The widget->device leg does dispatch for everything else, and #275 is
  // measured across it. `tester.startGesture(kind: PointerDeviceKind.mouse,
  // buttons: kPrimaryMouseButton)` delivers down, move and up carrying
  // `PointerDeviceKind.mouse`, so the mouse branch of `handlePointerEvent`
  // runs and `pointerView` can be read; `tester.tapAt` delivers touch, which
  // the contact half reads. `good`'s `test/stacked_game_view_test.dart`
  // drives both.
  //
  // The trap that remains: a pressed pointer is *captured* by whatever it went
  // down on, so a drag cannot move between two views even though it
  // dispatches. Covering the crossing needs an integration test on a device,
  // alongside the rendering perf demo.

  testWidgets('a pointer over no view reports none', (tester) async {
    final game = await _start();
    game.inputDevice!.movePointer(screenX: 10, screenY: 10);
    expect(
      game.pointerView,
      isNull,
      reason:
          'a headless harness driving the cursor names no view, and '
          'that is not an error - picking falls back to the first',
    );
  });

  testWidgets('two GameViews on the same camera share one surface', (
    tester,
  ) async {
    final game = await _start();
    final state = run.state as _MultiState;
    state.level.handle.addEntity(state.level.sprite);
    final eye = state.level.handle.addEntity(state.level.eye);
    state.level.eye.cameraView[eye] = game.defaultCamera;

    await tester.pumpWidget(
      Row(
        textDirection: TextDirection.ltr,
        children: <Widget>[
          Expanded(child: GameView(camera: game.defaultCamera)),
          Expanded(child: GameView(camera: game.defaultCamera)),
        ],
      ),
    );

    run.state.advance(_step);
    await tester.pump();

    // Both painters exist and both replay - but there is one ingest behind
    // them, because the surface is keyed by the view rather than by the
    // widget. Two widgets showing one camera is a supported shape (the same
    // view at two sizes) and must not cost two decodes of the same frame.
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .toList();
    expect(painters, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('two contacts in two views project through two cameras', (
    tester,
  ) async {
    final game = await _start();
    final state = run.state as _MultiState;

    // One camera per view, a thousand units apart, and one target parked
    // under each - so the *same* view-space pixel means two different world
    // points and two different entities. Resolving one view for the whole
    // system sends both fingers to the same camera, and only one of the two
    // targets can be found that way.
    final levelEye = state.level.handle.addEntity(state.level.eye);
    state.level.eye.cameraView[levelEye] = game.defaultCamera;
    final overlayEye = state.overlay.handle.addEntity(state.overlay.eye);
    state.overlay.eye
      ..cameraView[overlayEye] = game.minimap
      ..transformOffsetX[overlayEye] = 1000;

    final levelTarget = state.level.handle.addEntity(state.level.target);
    final overlayTarget = state.overlay.handle.addEntity(state.overlay.target);
    state.overlay.target.transformOffsetX[overlayTarget] = 1000;

    game.defaultCamera.setViewport(400, 400);
    game.minimap.setViewport(400, 400);
    run.state.advance(_step);
    events.clear();

    // Both down before a step runs, each named against the view whose pixels
    // it landed on.
    game.inputDevice!.pressContact(
      1,
      screenX: 0,
      screenY: 0,
      viewX: 200,
      viewY: 200,
      view: game.defaultCamera,
    );
    game.inputDevice!.pressContact(
      2,
      screenX: 0,
      screenY: 0,
      viewX: 200,
      viewY: 200,
      view: game.minimap,
    );
    run.state.advance(_step);

    expect(
      events,
      <String>[
        'down ${levelTarget.value} at 0.0',
        'down ${overlayTarget.value} at 1000.0',
      ],
      reason:
          'the same pixel in two views is two world points, and the view '
          'address rides on the contact - Game.pointerView answers for the '
          'cursor and cannot answer for two fingers at once',
    );
    expect(levelTarget.value, isNot(overlayTarget.value));
  });
}
