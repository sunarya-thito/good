import 'dart:math' as math;
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

  group('ObjectTransform', () {
    late GameEngine engine;
    setUp(() async => engine = await _createEngine());
    tearDown(() async => engine.dispose());

    testWidgets('should have identity matrix by default', (tester) async {
      final transform = ObjectTransform();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(children: [ComponentWidget(() => transform)]),
        ),
      );
      await tester.pump();

      expect(transform.localMatrix, equals(Matrix4.identity()));
      expect(transform.worldMatrix, equals(Matrix4.identity()));
      expect(transform.localPosition.x, equals(0.0));
      expect(transform.localPosition.y, equals(0.0));
      expect(transform.localAngle, equals(0.0));
      expect(transform.localScale.x, equals(1.0));
      expect(transform.localScale.y, equals(1.0));
    });

    testWidgets(
      'should calculate localMatrix correctly when properties are set',
      (tester) async {
        final transform = ObjectTransform();
        await tester.pumpWidget(
          Game(
            engine: engine,
            child: GameObjectWidget(
              children: [ComponentWidget(() => transform)],
            ),
          ),
        );
        await tester.pump();

        transform.localPosition = Vector2(10, 20);
        transform.localAngle = math.pi / 2; // 90 degrees
        transform.localScale = Vector2(2, 3);

        final expected = Matrix4.identity()
          ..translateByDouble(10.0, 20.0, 0.0, 1.0)
          ..rotateZ(math.pi / 2)
          ..scaleByDouble(2.0, 3.0, 1.0, 1.0);

        for (int i = 0; i < 16; i++) {
          expect(
            transform.localMatrix.storage[i],
            closeTo(expected.storage[i], 0.0001),
          );
        }
      },
    );

    testWidgets('should propagate worldMatrix through hierarchy', (
      tester,
    ) async {
      final parentTransform = ObjectTransform();
      final childTransform = ObjectTransform();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => parentTransform),
              GameObjectWidget(
                children: [ComponentWidget(() => childTransform)],
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      parentTransform.localPosition = Vector2(100, 100);
      childTransform.localPosition = Vector2(50, 50);

      expect(parentTransform.worldMatrix.getTranslation().x, equals(100));
      expect(parentTransform.worldMatrix.getTranslation().y, equals(100));

      expect(childTransform.worldMatrix.getTranslation().x, equals(150));
      expect(childTransform.worldMatrix.getTranslation().y, equals(150));
      expect(childTransform.position.x, closeTo(150.0, 0.0001));
      expect(childTransform.position.y, closeTo(150.0, 0.0001));
    });

    testWidgets('should increment version and dirty cache on change', (
      tester,
    ) async {
      final parentTransform = ObjectTransform();
      final childTransform = ObjectTransform();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => parentTransform),
              GameObjectWidget(
                children: [ComponentWidget(() => childTransform)],
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      final initialParentVersion = parentTransform.version;
      final initialChildVersion = childTransform.version;

      var _ = childTransform.worldMatrix;

      parentTransform.localPosition = Vector2(1, 1);

      expect(parentTransform.version, greaterThan(initialParentVersion));
      expect(childTransform.version, greaterThan(initialChildVersion));

      expect(childTransform.position.x, closeTo(1.0, 0.0001));
      expect(childTransform.position.y, closeTo(1.0, 0.0001));
    });

    testWidgets('should handle deep nesting (10 levels)', (tester) async {
      final transforms = List.generate(10, (_) => ObjectTransform());

      Widget buildHierarchy(int index) {
        if (index >= transforms.length) return const SizedBox();
        return GameObjectWidget(
          children: [
            ComponentWidget(() => transforms[index]),
            buildHierarchy(index + 1),
          ],
        );
      }

      await tester.pumpWidget(Game(engine: engine, child: buildHierarchy(0)));
      await tester.pump();

      for (var t in transforms) {
        t.localPosition = Vector2(10, 0);
      }

      expect(transforms.last.position.x, closeTo(100.0, 0.0001));
    });

    testWidgets('should correctly convert localToWorld and worldToLocal', (
      tester,
    ) async {
      final transform = ObjectTransform();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(children: [ComponentWidget(() => transform)]),
        ),
      );
      await tester.pump();

      transform.localPosition = Vector2(100, 100);
      transform.localAngle = math.pi / 4; // 45 degrees

      final localPoint = Vector2(10, 10);
      final worldPoint = transform.localToWorld(localPoint);

      final convertedBack = transform.worldToLocal(worldPoint);
      expect(convertedBack.x, closeTo(localPoint.x, 0.0001));
      expect(convertedBack.y, closeTo(localPoint.y, 0.0001));
    });

    testWidgets('should set world-space position correctly with parent', (
      tester,
    ) async {
      final parentTransform = ObjectTransform();
      final childTransform = ObjectTransform();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => parentTransform),
              GameObjectWidget(
                children: [ComponentWidget(() => childTransform)],
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      parentTransform.localPosition = Vector2(100, 100);
      parentTransform.localAngle = math.pi / 2;

      childTransform.position = Vector2(100, 200);

      expect(childTransform.position.x, closeTo(100.0, 0.0001));
      expect(childTransform.position.y, closeTo(200.0, 0.0001));
      expect(childTransform.localPosition.x, closeTo(100.0, 0.0001));
      expect(childTransform.localPosition.y, closeTo(0.0, 0.0001));
    });
  });
}
