import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

Future<GameEngine> _createEngine() => GameEngine.create({
  TickerSystem.new,
  InputSystem.new,
  CameraSystem.new,
  ScreenSystem.new,
});

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('Coroutine', () {
    late GameEngine engine;
    setUp(() async => engine = await _createEngine());
    tearDown(() async => engine.dispose());

    testWidgets('should run a simple coroutine', (tester) async {
      bool reached = false;
      Stream myCoroutine() async* {
        yield null;
        reached = true;
      }

      await tester.pumpWidget(
        Game(engine: engine, child: GameObjectWidget()),
      );
      await tester.pump();
      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      gameObject.startCoroutine(myCoroutine);
      await tester.idle();
      expect(reached, isFalse);

      await tester.pump();
      await tester.pump();
      expect(reached, isTrue);
    });

    testWidgets('should wait for seconds', (tester) async {
      int count = 0;
      Stream myCoroutine() async* {
        count++;
        yield WaitForSeconds(0.1);
        count++;
      }

      await tester.pumpWidget(
        Game(engine: engine, child: GameObjectWidget()),
      );
      await tester.pump();
      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      gameObject.startCoroutine(myCoroutine);
      await tester.idle();
      await tester.pump();
      expect(count, equals(1));

      await tester.pump(const Duration(milliseconds: 110));
      expect(count, equals(2));
    });

    testWidgets('should wait until condition is met', (tester) async {
      bool condition = false;
      bool reached = false;
      Stream myCoroutine() async* {
        yield WaitUntil(() => condition);
        reached = true;
      }

      await tester.pumpWidget(
        Game(engine: engine, child: GameObjectWidget()),
      );
      await tester.pump();
      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      gameObject.startCoroutine(myCoroutine);
      await tester.idle();
      await tester.pump();
      expect(reached, isFalse);

      await tester.pump(const Duration(milliseconds: 16));
      expect(reached, isFalse);

      condition = true;
      await tester.pump();
      expect(reached, isTrue);
    });

    testWidgets('should stop specific coroutine', (tester) async {
      bool reached = false;
      Stream myCoroutine() async* {
        yield WaitForSeconds(1.0);
        reached = true;
      }

      await tester.pumpWidget(
        Game(engine: engine, child: GameObjectWidget()),
      );
      await tester.pump();
      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      final future = gameObject.startCoroutine(myCoroutine);
      await tester.idle();

      gameObject.stopCoroutine(future);

      await tester.pump(const Duration(seconds: 2));
      expect(reached, isFalse);
    });

    testWidgets('should stop all coroutines on unmount', (tester) async {
      int count = 0;
      Stream myCoroutine() async* {
        while (true) {
          yield null;
          count++;
        }
      }

      await tester.pumpWidget(
        Game(engine: engine, child: GameObjectWidget()),
      );
      await tester.pump();
      final obj = tester.element(find.byType(GameObjectWidget)) as GameObject;
      obj.startCoroutine(myCoroutine);
      await tester.idle();

      await tester.pump();
      expect(count, greaterThan(0));
      final lastCount = count;

      await tester.pumpWidget(Game(engine: engine, child: const SizedBox()));
      await tester.pump();
      await tester.idle();

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(count, lessThanOrEqualTo(lastCount + 1));
      final finalCount = count;

      await tester.pump(const Duration(milliseconds: 100));
      expect(count, equals(finalCount));
    });

    testWidgets('should handle nested coroutines', (tester) async {
      bool innerReached = false;
      Stream inner() async* {
        yield null;
        innerReached = true;
      }

      Stream outer() async* {
        yield inner();
      }

      await tester.pumpWidget(
        Game(engine: engine, child: GameObjectWidget()),
      );
      await tester.pump();
      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      gameObject.startCoroutine(outer);
      await tester.idle();
      await tester.pump();
      await tester.pump();
      await tester.idle();

      expect(innerReached, isTrue);
    });
  });
}
