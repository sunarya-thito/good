import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;


// GameView, lane 3's main-isolate end: tick ping -> drain -> ingest ->
// repaint, and nothing in paint() but a replay.
//
// The Game here runs through start(inline: true, autoTick: false) rather than
// a real isolate: this widget only ever talks to a Game through
// addTickListener and the renderer system's BufferHandle, both of which behave
// identically on the inline path, and driving GameState.advance() by hand is
// what makes "a tick happened" a fact the test states rather than a race it
// waits on. The isolate handoff itself is covered in goo's
// game_isolate_test.dart.

class _Sprite extends EntityStruct with Transform2D, WorldTransform2D, Renderable2D {
  /// Declared unsized, so each test states the extent it cares about - this
  /// file is about the widget-side plumbing, not about geometry.
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    quad = descriptor.has();
  }
}

class _Scene extends SceneStruct {
  @override
  void onSceneMounted(Scene scene) => handle = scene;

  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Scene();

  late final _Sprite sprite;

  @override
  void describeScene(SceneDescriptor descriptor) {
    sprite = descriptor.has(_Sprite());
  }
}

class _ViewState extends GameState2D<_ViewGame> {
  @override
  void onMounted() {
    loadScene(_Scene());
  }
}

class _ViewGame extends Game2D {
  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState2D<_ViewGame> createState() => _ViewState();

  // No describeSystems at all: `extends Game2D` + `extends GameState2D` is
  // the entire opt-in, and WorldTransformSystem/GameRenderer2D come with the
  // second one. Note it cannot be forgotten: `createState` is narrowed to
  // GameState2D, so a plain GameState here would not compile.
}

/// The rendererless game's state - a plain `GameState`, since there is no
/// `Game2D` to satisfy.
class _BareViewState extends GameState<_RendererlessGame> {
  @override
  void onMounted() {
    loadScene(_Scene());
  }
}

/// A game with no renderer declared - a HUD-only or headless-plus-Flutter
/// setup, which GameView has to tolerate rather than crash on.
class _RendererlessGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _BareViewState();
}

class _SpyCanvas implements Canvas {
  final List<String> calls = <String>[];
  ui.Vertices? vertices;

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) {
    calls.add('drawVertices');
    this.vertices = vertices;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    calls.add(name.substring(name.indexOf('"') + 1, name.lastIndexOf('"')));
    return null;
  }
}

const Duration _step = Duration(milliseconds: 10);

/// Paints the widget's painter onto a spy - the only way to observe what
/// GameView would put on screen without a golden.
_SpyCanvas _paintThrough(WidgetTester tester) {
  final painter = tester.widget<CustomPaint>(find.byType(CustomPaint).first).painter!;
  final spy = _SpyCanvas();
  painter.paint(spy, const Size(400, 600));
  return spy;
}

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

  testWidgets('paints nothing until a tick has produced a frame', (tester) async {
    final game = await _start(_ViewGame());
    final scene = run.state.getScene<_Scene>();
    final entity = scene.addEntity(scene.sprite);
    scene.sprite.quad
      ..width[entity] = 20
      ..height[entity] = 10;
    scene.sprite
      ..transformOffsetX[entity] = 100
      ..transformOffsetY[entity] = 200;

    await tester.pumpWidget(GameView(camera: game.defaultCamera));
    expect(_paintThrough(tester).calls, isEmpty,
        reason: 'no tick has happened, so there is no frame to replay');
  });

  testWidgets('a tick drains, ingests and repaints - end to end', (tester) async {
    final game = await _start(_ViewGame());
    final scene = run.state.getScene<_Scene>();
    final entity = scene.addEntity(scene.sprite);
    scene.sprite.quad
      ..width[entity] = 20
      ..height[entity] = 10;
    scene.sprite
      ..transformOffsetX[entity] = 100
      ..transformOffsetY[entity] = 200;

    await tester.pumpWidget(GameView(camera: game.defaultCamera));

    // One tick on the "game isolate": the renderer writes a batch into the
    // ring and the tick listener GameView registered drains it, all
    // synchronously on this isolate.
    run.state.advance(_step);
    await tester.pump();

    final spy = _paintThrough(tester);
    expect(spy.calls, ['drawVertices'],
        reason: 'paint() replays and does nothing else - no save/restore, no '
            'per-sprite call');
    expect(spy.vertices, isNotNull);
  });

  testWidgets('a game with no renderer declared contributes no painter at all', (tester) async {
    await _start(_RendererlessGame());
    await tester.pumpWidget(GameView.headless(game: run));
    run.state.advance(_step * 2);
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Stronger than "paints nothing": with rendering moved out of GameView
    // and into a declared RenderSystem2D, a game that never declares one
    // produces no CustomPaint in the tree whatsoever - GameView builds
    // exactly what its systems contribute, which here is the empty box
    // BuildWidgetEvent starts with. A HUD-only or headless-plus-Flutter
    // setup is a first-class shape, not a degenerate case to tolerate.
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('the frame callback is disarmed on dispose', (tester) async {
    final game = await _start(_ViewGame());
    await tester.pumpWidget(GameView(camera: game.defaultCamera));
    run.state.advance(_step);
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    // Two things at once. Ticking after the widget is gone must not reach a
    // disposed ChangeNotifier (notifying one throws, so it would surface as an
    // exception rather than as silence) - and the self-rescheduling frame
    // callback must be gone too, which the binding checks for us at the end of
    // the test: a callback still pending is reported as "an animation is still
    // running even after the widget tree was disposed".
    run.state.advance(_step * 3);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('stopping while the view is still mounted disarms the renderer',
      (tester) async {
    final game = await _start(_ViewGame());
    final scene = run.state.getScene<_Scene>();
    scene.addEntity(scene.sprite);

    await tester.pumpWidget(GameView(camera: game.defaultCamera));
    run.state.advance(_step);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0),
        reason: 'the renderer samples on a self-rescheduling frame callback, '
            'so an armed one is what "showing a game" looks like');

    // The case `onViewDetached` cannot cover: the game goes first and the
    // widget is still up, so no detach ever fires. Without `Game.onStopped`
    // the callback reschedules itself forever, against draw buffers that
    // `stop()` has already unmapped - and the widget binding reports it as
    // "an animation is still running even after the widget tree was
    // disposed", one test later and nowhere near the cause.
    await run.stop();

    expect(tester.binding.transientCallbackCount, 0,
        reason: 'Game.onStopped must have cancelled it - and it has to happen '
            'on the presentation isolate, because that is where the callback '
            'and the decoded frames are');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Game that has not started is refused with a reason', (tester) async {
    _ViewGame();
    await tester.pumpWidget(GameView.headless(game: run));
    final error = tester.takeException();
    expect(error, isStateError);
    expect(
      (error as StateError).message,
      contains('unsendable'),
      reason: 'the message has to say *why* - a tick listener registered '
          'before start() poisons the Isolate.spawn message',
    );
  });
}
