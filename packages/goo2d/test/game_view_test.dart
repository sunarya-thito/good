import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

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
  void onMounted(Scene scene) => handle = scene;

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

class _ViewState extends GameState<Game> {
  @override
  void onMounted() {
    loadScene(_Scene());
  }
}

class _ViewGame extends Game2D {
  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _ViewState();

  // No describeSystems at all: `extends Game2D` is the entire opt-in, and
  // WorldTransformSystem/GameRenderer2D come with it.
}

/// A game with no renderer declared - a HUD-only or headless-plus-Flutter
/// setup, which GameView has to tolerate rather than crash on.
class _RendererlessGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _ViewState();
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
  await game.start(inline: true, autoTick: false);
  addTearDown(() async {
    if (game.isRunning) await game.stop();
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
    final scene = game.state!.getScene<_Scene>();
    final entity = scene.addEntity(scene.sprite);
    scene.sprite.quad
      ..width[entity] = 20
      ..height[entity] = 10;
    scene.sprite
      ..transformOffsetX[entity] = 100
      ..transformOffsetY[entity] = 200;

    await tester.pumpWidget(GameView(game: game));
    expect(_paintThrough(tester).calls, isEmpty,
        reason: 'no tick has happened, so there is no frame to replay');
  });

  testWidgets('a tick drains, ingests and repaints - end to end', (tester) async {
    final game = await _start(_ViewGame());
    final scene = game.state!.getScene<_Scene>();
    final entity = scene.addEntity(scene.sprite);
    scene.sprite.quad
      ..width[entity] = 20
      ..height[entity] = 10;
    scene.sprite
      ..transformOffsetX[entity] = 100
      ..transformOffsetY[entity] = 200;

    await tester.pumpWidget(GameView(game: game));

    // One tick on the "game isolate": the renderer writes a batch into the
    // ring and the tick listener GameView registered drains it, all
    // synchronously on this isolate.
    game.state!.advance(_step);
    await tester.pump();

    final spy = _paintThrough(tester);
    expect(spy.calls, ['drawVertices'],
        reason: 'paint() replays and does nothing else - no save/restore, no '
            'per-sprite call');
    expect(spy.vertices, isNotNull);
  });

  testWidgets('a game with no renderer declared contributes no painter at all', (tester) async {
    final game = await _start(_RendererlessGame());
    await tester.pumpWidget(GameView(game: game));
    game.state!.advance(_step * 2);
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

  testWidgets('the tick listener is unregistered on dispose', (tester) async {
    final game = await _start(_ViewGame());
    await tester.pumpWidget(GameView(game: game));
    game.state!.advance(_step);
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    // Ticking after the widget is gone must not reach a disposed State (a
    // ChangeNotifier notified after dispose throws, so this would surface as
    // an exception rather than as silence).
    game.state!.advance(_step * 3);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Game that has not started is refused with a reason', (tester) async {
    final game = _ViewGame();
    await tester.pumpWidget(GameView(game: game));
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
