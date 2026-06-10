import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

class MockSystem implements GameSystem {
  @override
  late final GameEngine game;
  @override
  bool get gameAttached => _attached;
  bool _attached = false;
  bool disposed = false;

  @override
  Future<void> attach(GameEngine game) async {
    this.game = game;
    _attached = true;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('GameSystem', () {
    test('GameEngine should initialize systems', () async {
      final engine = await GameEngine.create({
        TickerSystem.new,
        InputSystem.new,
        CameraSystem.new,
        ScreenSystem.new,
      });

      expect(engine.hasSystem<TickerSystem>(), isTrue);
      expect(engine.hasSystem<InputSystem>(), isTrue);
      expect(engine.hasSystem<CameraSystem>(), isTrue);
      expect(engine.hasSystem<ScreenSystem>(), isTrue);

      await engine.dispose();
    });

    test('GameEngine should support custom system configurations', () async {
      final engine = await GameEngine.create({MockSystem.new});

      expect(engine.hasSystem<MockSystem>(), isTrue);
      expect(engine.hasSystem<TickerSystem>(), isFalse);

      await engine.dispose();
    });

    test('Operator - and ~ should exclude systems', () async {
      final engine = await GameEngine.create({
        TickerSystem.new,
        InputSystem.new,
        CameraSystem.new,
        ScreenSystem.new,
        -InputSystem.new,
        ~CameraSystem.new,
      });

      expect(engine.hasSystem<TickerSystem>(), isTrue);
      expect(engine.hasSystem<InputSystem>(), isFalse);
      expect(engine.hasSystem<CameraSystem>(), isFalse);

      await engine.dispose();
    });

    test('Systems should be disposed when engine is disposed', () async {
      final system = MockSystem();
      final engine = await GameEngine.create({() => system});
      expect(system.gameAttached, isTrue);

      await engine.dispose();
      expect(system.disposed, isTrue);
    });

    test('getSystem should return null for missing systems', () async {
      final engine = await GameEngine.create({});
      expect(engine.getSystem<TickerSystem>(), isNull);
      await engine.dispose();
    });
  });
}
