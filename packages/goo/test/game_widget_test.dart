import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/archetype.dart';
import 'package:goo/src/game.dart';
import 'package:goo/src/game_state.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/system.dart';
import 'package:goo/src/widget/game_view.dart';

// The Flutter-facing surface of a Game, which is now one method: buildView.
//
// There used to be a whole second event lane here - WidgetEvent,
// WidgetListener, BuildWidgetEvent - so that several declared systems could
// each wrap the widget tree. It is gone, and this file is what replaced it:
// one object builds the view, systems live wholly on the game isolate, and
// the "which isolate does this run on" question has one answer per type.

class _BareState extends GameState<Game> {
  @override
  void onMounted() {
    loadScene(_BareScene());
  }
}

class _BareScene extends SceneStruct {
  _BareScene();
}

class _TickingSystem extends GameSystem {}

/// The shape a renderer package takes: a `Game` subclass that answers
/// [Game.buildView]. `Game2D` in `goo2d` is exactly this with a `CustomPaint`
/// in it.
class _ViewGame extends Game {
  @override
  int get pageSize => 4096;

  BuildContext? seen;
  bool show = true;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _BareState();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_TickingSystem());
  }

  @override
  Widget? buildView(BuildContext context) {
    seen = context;
    return show ? const Text('game', textDirection: TextDirection.ltr) : null;
  }
}

/// A game that draws nothing - headless, or a game whose whole UI is ordinary
/// Flutter widgets around the view.
class _SilentGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  GameState createState() => _BareState();
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

  group('buildView', () {
    testWidgets('what the game returns is what the view shows', (tester) async {
      final game = await _start(_ViewGame());
      await tester.pumpWidget(GameView(game: game));
      expect(find.text('game'), findsOneWidget);
    });

    testWidgets('a game that draws nothing is not an error', (tester) async {
      final game = await _start(_SilentGame());
      await tester.pumpWidget(GameView(game: game));
      expect(tester.takeException(), isNull,
          reason: 'the default buildView returns null, and a game with no '
              'renderer is a real configuration - a HUD-only app, a headless '
              'game someone attached a view to - not a misconfiguration to '
              'crash on');
    });

    testWidgets('null and a widget are both honoured on rebuild',
        (tester) async {
      final game = await _start(_ViewGame());
      await tester.pumpWidget(GameView(game: game));
      expect(find.text('game'), findsOneWidget);

      game.show = false;
      await tester.pumpWidget(GameView(game: game, key: const Key('again')));
      expect(find.text('game'), findsNothing,
          reason: 'returning null mid-life is how a renderer says "there is '
              'no scene to draw yet" - Game2D does exactly this between '
              'loadScene calls');
    });

    testWidgets('the context is the real one from the element tree',
        (tester) async {
      final game = await _start(_ViewGame());
      await tester.pumpWidget(GameView(game: game));
      expect(game.seen, isNotNull);
      expect(game.seen!.mounted, isTrue,
          reason: 'a live context, so buildView can read an InheritedWidget - '
              'a theme, a MediaQuery - like any other build method');
    });
  });

}
