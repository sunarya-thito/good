import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/src/data/system.dart';
import 'package:goo2d/src/data/world.dart';
import 'package:goo2d/src/ticker.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

class TestLog {
  final List<String> events = [];
}

class AttachTracker extends WorldSystem {
  final TestLog log;
  AttachTracker(this.log);
  @override
  void onAttach() => log.events.add('attach');
  @override
  void onDetach() => log.events.add('detach');
}

class AlphaSystem extends WorldSystem with Tickable {
  final TestLog log;
  AlphaSystem(this.log);
  @override
  void onUpdate(double dt) => log.events.add('tick:alpha');
}

class BetaSystem extends WorldSystem with Tickable {
  final TestLog log;
  BetaSystem(this.log);
  @override
  void onUpdate(double dt) => log.events.add('tick:beta');
}

class GammaSystem extends WorldSystem with Tickable {
  final TestLog log;
  GammaSystem(this.log);
  @override
  void onUpdate(double dt) => log.events.add('tick:gamma');
}

class FixedSystem extends WorldSystem with FixedTickable {
  final TestLog log;
  FixedSystem(this.log);
  @override
  Future<void> onFixedUpdate(double dt) async => log.events.add('fixed');
}

class LateSystem extends WorldSystem with LateTickable {
  final TestLog log;
  LateSystem(this.log);
  @override
  void onLateUpdate(double dt) => log.events.add('late');
}

class DualSystem extends WorldSystem with Tickable, FixedTickable {
  final TestLog log;
  DualSystem(this.log);
  @override
  void onUpdate(double dt) => log.events.add('dual:tick');
  @override
  Future<void> onFixedUpdate(double dt) async => log.events.add('dual:fixed');
}

class InspectSystem extends WorldSystem {
  final void Function(WorldController) onAttachCallback;
  InspectSystem({required this.onAttachCallback});
  @override
  void onAttach() => onAttachCallback(world);
}

// Unregistered type — used to test unresolved ordering constraint
class UnregisteredSystem extends WorldSystem with Tickable {
  @override
  void onUpdate(double dt) {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('WorldSystem lifecycle', () {
    test('world is injected before onAttach is called', () {
      final world = WorldController();
      late WorldController captured;
      world.addSystem(InspectSystem(onAttachCallback: (w) => captured = w));
      expect(captured, same(world));
    });

    test('onDetach called when system is removed', () {
      final log = TestLog();
      final world = WorldController();
      final sys = AttachTracker(log);
      world.addSystem(sys);
      world.removeSystem(sys);
      expect(log.events, containsAllInOrder(['attach', 'detach']));
    });
  });

  group('Tick routing', () {
    test('Tickable receives onUpdate; not called on fixedTick', () async {
      final log = TestLog();
      final world = WorldController()..addSystem(AlphaSystem(log));
      world.broadcastEvent(TickEvent(0.016));
      await world.broadcastEventAsync(FixedTickEvent(0.02));
      expect(log.events, ['tick:alpha']);
    });

    test('FixedTickable receives onFixedUpdate; not called on tick', () async {
      final log = TestLog();
      final world = WorldController()..addSystem(FixedSystem(log));
      world.broadcastEvent(TickEvent(0.016));
      await world.broadcastEventAsync(FixedTickEvent(0.02));
      expect(log.events, ['fixed']);
    });

    test('LateTickable receives onLateUpdate only on lateTick', () async {
      final log = TestLog();
      final world = WorldController()..addSystem(LateSystem(log));
      world.broadcastEvent(TickEvent(0.016));
      await world.broadcastEventAsync(FixedTickEvent(0.02));
      world.broadcastEvent(LateTickEvent(0.016));
      expect(log.events, ['late']);
    });

    test('system with both Tickable and FixedTickable receives both', () async {
      final log = TestLog();
      final world = WorldController()..addSystem(DualSystem(log));
      world.broadcastEvent(TickEvent(0.016));
      await world.broadcastEventAsync(FixedTickEvent(0.02));
      expect(log.events, containsAllInOrder(['dual:tick', 'dual:fixed']));
    });
  });

  group('System ordering', () {
    test(
      'insert(A, after: B) — A ticks after B regardless of insertion order',
      () {
        final log = TestLog();
        final world = WorldController();
        world.addSystem(AlphaSystem(log)); // registered first
        world.insert(
          BetaSystem(log),
          after: AlphaSystem,
        ); // must run after Alpha

        world.broadcastEvent(TickEvent(0.016));
        final ai = log.events.indexOf('tick:alpha');
        final bi = log.events.indexOf('tick:beta');
        expect(ai, lessThan(bi));
      },
    );

    test('insert(A, before: B) — A ticks before B', () {
      final log = TestLog();
      final world = WorldController();
      world.addSystem(BetaSystem(log)); // registered first
      world.insert(
        AlphaSystem(log),
        before: BetaSystem,
      ); // must run before Beta

      world.broadcastEvent(TickEvent(0.016));
      final ai = log.events.indexOf('tick:alpha');
      final bi = log.events.indexOf('tick:beta');
      expect(ai, lessThan(bi));
    });

    test(
      'after constraint stored before target is registered — still honoured',
      () {
        final log = TestLog();
        final world = WorldController();
        world.insert(
          BetaSystem(log),
          after: AlphaSystem,
        ); // Alpha not yet added
        world.addSystem(AlphaSystem(log));

        world.broadcastEvent(TickEvent(0.016));
        final ai = log.events.indexOf('tick:alpha');
        final bi = log.events.indexOf('tick:beta');
        expect(ai, lessThan(bi));
      },
    );

    test('unresolved type reference — no crash, system still ticks', () {
      final log = TestLog();
      final world = WorldController();
      world.insert(
        AlphaSystem(log),
        after: UnregisteredSystem,
      ); // never registered

      expect(() => world.broadcastEvent(TickEvent(0.016)), returnsNormally);
      expect(log.events, contains('tick:alpha'));
    });

    test('circular dependency throws on insert', () {
      final log = TestLog();
      final world = WorldController();
      world.insert(AlphaSystem(log), after: BetaSystem);
      expect(
        () => world.insert(BetaSystem(log), after: AlphaSystem),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
