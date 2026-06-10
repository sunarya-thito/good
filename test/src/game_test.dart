import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/game.dart';
import 'package:goo2d/src/ticker.dart';

Future<GameEngine> _createMinimalEngine() => GameEngine.create({
  TickerSystem.new,
  InputSystem.new,
  CameraSystem.new,
  ScreenSystem.new,
});

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('Game', () {
    testWidgets('should provide GameEngine via GameProvider', (tester) async {
      final engine = await _createMinimalEngine();
      GameEngine? foundEngine;

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: Builder(
            builder: (context) {
              foundEngine = GameProvider.of(context);
              return Container();
            },
          ),
        ),
      );

      expect(foundEngine, isNotNull);
      await engine.dispose();
    });

    testWidgets(
      'should automatically inject World, GameLoop, and GameRenderer',
      (tester) async {
        final engine = await _createMinimalEngine();

        await tester.pumpWidget(Game(engine: engine, child: Container()));

        expect(find.byType(World), findsOneWidget);
        expect(find.byType(GameLoop), findsOneWidget);
        expect(find.byType(GameRenderer), findsOneWidget);

        await engine.dispose();
      },
    );

    testWidgets('should support custom GameEngine instance', (tester) async {
      final customEngine = await _createMinimalEngine();
      GameEngine? foundEngine;

      await tester.pumpWidget(
        Game(
          engine: customEngine,
          child: Builder(
            builder: (context) {
              foundEngine = GameProvider.of(context);
              return Container();
            },
          ),
        ),
      );

      expect(foundEngine, equals(customEngine));
      await customEngine.dispose();
    });

    testWidgets('should allow nesting multiple game instances', (tester) async {
      final engine1 = await _createMinimalEngine();
      final engine2 = await _createMinimalEngine();
      GameEngine? found1;
      GameEngine? found2;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Game(
                engine: engine1,
                child: Builder(
                  builder: (c) {
                    found1 = GameProvider.of(c);
                    return Container();
                  },
                ),
              ),
              Game(
                engine: engine2,
                child: Builder(
                  builder: (c) {
                    found2 = GameProvider.of(c);
                    return Container();
                  },
                ),
              ),
            ],
          ),
        ),
      );

      expect(found1, isNotNull);
      expect(found2, isNotNull);
      expect(found1, isNot(equals(found2)));

      await engine1.dispose();
      await engine2.dispose();
    });
  });
}
