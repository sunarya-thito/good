import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/src/data/component.dart';
import 'package:goo2d/src/data/system.dart';
import 'package:goo2d/src/data/world.dart';
import 'package:goo2d/src/ticker.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

// Use List<int> as the heap type: it's a reference type, so identical() checks
// prove the actual reference (not a copy) is stored and retrieved.
final _kDefault = <int>[];

class _ObjData extends EntityData {
  late final Field<List<int>> items;

  @override
  void describe(DataDescriptor d) {
    items = d.newHeap<List<int>>(initialValue: _kDefault);
  }
}

class _DualData extends EntityData {
  late final Field<String> name;
  late final Field<List<int>> values;

  @override
  void describe(DataDescriptor d) {
    name = d.newHeap<String>(initialValue: '');
    values = d.newHeap<List<int>>(initialValue: _kDefault);
  }
}

// Helper: creates entities via commandBuffer on each tick using enqueued payloads.
class _CommandBufferCreator extends WorldSystem with Tickable {
  final List<List<int>> payloads;
  bool _done = false;

  _CommandBufferCreator(this.payloads);

  @override
  void onUpdate(double dt) {
    if (_done) return;
    _done = true;
    for (final p in payloads) {
      world.commandBuffer.createEntityAll([
        _ObjData.new.withInit((d, r) {
          d.items.set(r, p);
        }),
      ]);
    }
  }
}

// Helper: creates one entity via commandBuffer WITHOUT withInit.
class _CommandBufferCreatorNoInit extends WorldSystem with Tickable {
  bool _done = false;

  @override
  void onUpdate(double dt) {
    if (_done) return;
    _done = true;
    world.commandBuffer.createEntityAll([_ObjData.new]);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('newHeap<T>', () {
    // ---- default initialValue ------------------------------------------------

    test('direct createEntity: field starts with initialValue when no withInit',
        () {
      final world = WorldController();
      world.createEntity(_ObjData.new);

      final r = (world.query()..withAll(_ObjData)).executeSingle()!;
      expect(r.get<_ObjData>().items.get(r), same(_kDefault));
    });

    test('commandBuffer createEntity: field starts with initialValue when no withInit',
        () {
      final world = WorldController()
        ..addSystem(_CommandBufferCreatorNoInit());
      world.broadcastEvent(TickEvent(0.016));

      final r = (world.query()..withAll(_ObjData)).executeSingle()!;
      expect(r.get<_ObjData>().items.get(r), same(_kDefault));
    });

    // ---- withInit -----------------------------------------------------------

    test('direct createEntity: withInit stores the provided reference', () {
      final world = WorldController();
      final payload = [1, 2, 3];
      world.createEntity(_ObjData.new.withInit((d, r) {
        d.items.set(r, payload);
      }));

      final r = (world.query()..withAll(_ObjData)).executeSingle()!;
      expect(r.get<_ObjData>().items.get(r), same(payload));
    });

    test('commandBuffer: withInit stores the correct reference after flush', () {
      final payload = [10, 20];
      final world = WorldController()
        ..addSystem(_CommandBufferCreator([payload]));
      world.broadcastEvent(TickEvent(0.016));

      final r = (world.query()..withAll(_ObjData)).executeSingle()!;
      expect(r.get<_ObjData>().items.get(r), same(payload));
    });

    test('commandBuffer: multiple entities in one tick each receive their own payload',
        () {
      final p0 = [0];
      final p1 = [1];
      final p2 = [2];
      final world = WorldController()
        ..addSystem(_CommandBufferCreator([p0, p1, p2]));
      world.broadcastEvent(TickEvent(0.016));

      final results = <List<int>>[];
      for (final r in (world.query()..withAll(_ObjData)).execute()) {
        results.add(r.get<_ObjData>().items.get(r));
      }

      expect(results, containsAll([same(p0), same(p1), same(p2)]));
    });

    test('commandBuffer: withInit across successive ticks works independently',
        () {
      final p1 = [1];
      final p2 = [2];
      final world = WorldController();

      // Tick 1: create entity with p1
      world.addSystem(_CommandBufferCreator([p1]));
      world.broadcastEvent(TickEvent(0.016));

      final r1 = (world.query()..withAll(_ObjData)).executeSingle()!;
      expect(r1.get<_ObjData>().items.get(r1), same(p1));

      // Remove old entity, create another via a fresh system for p2
      world.createEntity(_ObjData.new.withInit((d, r) { d.items.set(r, p2); }));
      // Verify p1's entity is still p1
      for (final r in (world.query()..withAll(_ObjData)).withEntity().execute()) {
        final val = r.get<_ObjData>().items.get(r);
        expect(val == p1 || val == p2, isTrue);
      }
    });

    // ---- read / write after creation ----------------------------------------

    test('get/set via QueryResult cursor reads and writes the reference', () {
      final world = WorldController();
      world.createEntity(_ObjData.new);

      final q = world.query()..withAll(_ObjData);
      final r = q.executeSingle()!;
      final newList = [99];
      r.get<_ObjData>().items.set(r, newList);
      expect(r.get<_ObjData>().items.get(r), same(newList));
    });

    test('getSlot/setSlot provide direct storage access', () {
      final world = WorldController();
      final entity = world.createEntity(_ObjData.new);

      final slot = entity.index;
      final d = (world.query()..withAll(_ObjData)).executeSingle()!.get<_ObjData>();
      final newList = [7, 8, 9];
      d.items.setSlot(slot, newList);
      expect(d.items.getSlot(slot), same(newList));
    });

    // ---- slot recycling -----------------------------------------------------

    test('recycled slot resets to initialValue', () {
      final world = WorldController();
      final e = world.createEntity(_ObjData.new);

      final slot = e.index;
      final d = (world.query()..withAll(_ObjData)).executeSingle()!.get<_ObjData>();
      d.items.setSlot(slot, [42]);

      world.removeEntity(e);
      // Create new entity — it should recycle the freed slot
      world.createEntity(_ObjData.new);

      final r2 = (world.query()..withAll(_ObjData)).executeSingle()!;
      expect(r2.get<_ObjData>().items.get(r2), same(_kDefault));
    });

    // ---- pool growth --------------------------------------------------------

    test('pool growth: heap values survive a capacity expansion', () {
      final world = WorldController();
      const n = 200; // exceeds default initial capacity of 64

      final payloads = List.generate(n, (i) => [i]);
      for (final p in payloads) {
        world.createEntity(_ObjData.new.withInit((d, r) { d.items.set(r, p); }));
      }

      int found = 0;
      for (final r in (world.query()..withAll(_ObjData)).execute()) {
        final v = r.get<_ObjData>().items.get(r);
        expect(payloads.any((p) => identical(p, v)), isTrue);
        found++;
      }
      expect(found, n);
    });

    // ---- multiple heap fields -----------------------------------------------

    test('two heap fields on the same EntityData are independent', () {
      final world = WorldController();
      final myList = [1, 2, 3];
      world.createEntity(_DualData.new.withInit((d, r) {
        d.name.set(r, 'hello');
        d.values.set(r, myList);
      }));

      final r = (world.query()..withAll(_DualData)).executeSingle()!;
      final dd = r.get<_DualData>();
      expect(dd.name.get(r), 'hello');
      expect(dd.values.get(r), same(myList));

      // Overwrite one, the other is unaffected
      dd.name.set(r, 'world');
      expect(dd.name.get(r), 'world');
      expect(dd.values.get(r), same(myList));
    });

    test('two heap fields: default initialValues are independent', () {
      final world = WorldController();
      world.createEntity(_DualData.new);

      final r = (world.query()..withAll(_DualData)).executeSingle()!;
      final dd = r.get<_DualData>();
      expect(dd.name.get(r), '');
      expect(dd.values.get(r), same(_kDefault));
    });
  });
}
