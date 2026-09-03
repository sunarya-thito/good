// #49: destroying an entity has to free the `HeapObjectRegistry` slots its row
// holds, through every entrance that stops a row being an entity.
//
// A heap-object field is the one field kind whose value lives outside the row.
// Everything else an entity owns is bytes in a `MemoryPage`, and freeing the
// row - or dropping the whole page, which is what unloading a scene does -
// reclaims those. A registry slot survives both, so unless teardown says so
// explicitly the table grows for the life of the process.
//
// # Why the assertion is "the next register reuses it"
//
// `HeapObjectRegistry.slotCount` counts slots ever allocated, free ones
// included, and `register` pops the free list before it appends. So a slot
// that was really reclaimed shows up as a `register` that does *not* grow the
// count - which is the registry's own stated definition of the leak ("a
// growing count across register/unregister cycles is the exact leak this
// registry exists to avoid").
//
// Asserting that nothing threw would pass on the bug, and so would asserting
// on `slotCount` alone, because the count never shrinks either way. These read
// the occupancy instead: they make the registry hand out a slot and check
// whether it had to make a new one.
//
// # The trap these tests are shaped around
//
// `writeInitialValue` runs once, at `ArchetypeStorage.seal`, and `allocateRow`
// memcpys that prototype row into every spawn - so an entity that never writes
// a `hasHeapObject` field carries *the prototype's* address, one slot shared by
// every entity of the archetype. A teardown that freed it on the first destroy
// would dangle every surviving entity and hand the slot to the next unrelated
// `register`. The 'shared factory default' case below is what stops a fix from
// being written that way; it fails against the obvious wrong one.
import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/data/hierarchy.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/heap_object.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'heap_object_lifetime_test.g.dart';

/// A distinct instance per entity, so one row's slot is never mistaken for
/// another's.
List<int> _payload(int n) => <int>[n];

/// Shared by every entity that never writes the field - see the file header.
final List<int> sharedDefault = <int>[-1];

mixin _Holder on Component {
  late final DataPointer<List<int>> owned;
  late final DataPointer<List<int>?> maybe;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    owned = data.hasHeapObject<List<int>>(() => sharedDefault);
    maybe = data.optHeapObject<List<int>>();
  }

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Holder>();
  }
}

class _Thing extends EntityStruct with _Holder, Child, Parent {}

class _Level extends SceneStruct {
  late final Scene handle;

  late final _Thing thing;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    thing = descriptor.has(_Thing.new);
  }

  Entity add({Entity? parent}) => handle.addEntity(thing, parent: parent);
}

_Level _level() {
  final level = _Level()..initializeScene(MemoryPool(pageSize: 4096));
  level.handle = SceneRegistry.register(level);
  addTearDown(level.pool.dispose);
  return level;
}

/// Registers one throwaway object and reports whether it had to grow the
/// table. `false` means it reused a slot something released.
bool _registerGrewTable() {
  final before = HeapObjectRegistry.slotCount;
  HeapObjectRegistry.register(Object());
  return HeapObjectRegistry.slotCount > before;
}

// --- the real-game half, for scene unload -------------------------------

late Game run;

class _GameLevel extends SceneStruct {
  late final _Thing thing;

  static const int spawnPerMount = 3;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    thing = descriptor.has(_Thing.new);
  }

  @override
  void onSceneMounted(Scene scene) {
    for (var i = 0; i < spawnPerMount; i++) {
      final e = scene.addEntity(thing);
      // Written, not left at the default: an untouched field shares the
      // prototype's slot, and a test built on those would pass with no
      // teardown at all.
      thing.owned[e] = _payload(i);
    }
  }
}

class _HeapState extends GameState<_HeapGame> {}

class _HeapGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  late final _GameLevel level;

  @override
  GameState createState() => _HeapState();

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    level = descriptor.has(_GameLevel());
  }
}

Future<_HeapGame> _boot() async {
  final game = await Game.startInline(_HeapGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
    HeapObjectRegistry.reset();
  });

  group('destroy() frees the heap-object slots a row holds', () {
    test('the slot an entity wrote is reclaimed, not leaked', () {
      final level = _level();
      final e = level.add();

      final before = HeapObjectRegistry.slotCount;
      level.thing.owned[e] = _payload(1);
      expect(
        HeapObjectRegistry.slotCount,
        before + 1,
        reason: 'the write took a fresh slot',
      );

      e.destroy();
      expect(
        _registerGrewTable(),
        isFalse,
        reason:
            'destroy() must have put that slot back on the free list, so the '
            'next register reuses it instead of growing the table',
      );
    });

    test('both field kinds are released, not just the non-nullable one', () {
      final level = _level();
      final e = level.add();
      level.thing
        ..owned[e] = _payload(1)
        ..maybe[e] = _payload(2);

      e.destroy();
      // Two slots freed, so two registrations fit without growing.
      expect(_registerGrewTable(), isFalse);
      expect(
        _registerGrewTable(),
        isFalse,
        reason:
            'optHeapObject stores its address in the wrapped value field, so '
            'teardown has to reach through the nullable wrapper to find it',
      );
    });

    test('the shared factory default survives one entity being destroyed', () {
      final level = _level();
      final keeper = level.add();
      final doomed = level.add();

      // Neither wrote `owned`, so both rows carry the one address
      // `writeInitialValue` registered at seal.
      expect(level.thing.owned[keeper], same(sharedDefault));
      doomed.destroy();

      expect(
        level.thing.owned[keeper],
        same(sharedDefault),
        reason:
            'the prototype slot is shared by every entity of the archetype - '
            'freeing it on the first destroy would dangle all the others',
      );
      expect(
        _registerGrewTable(),
        isTrue,
        reason:
            'nothing was released, because the doomed row never owned a slot '
            'of its own. A teardown that freed the shared default would make '
            'this reuse it instead',
      );
    });

    test('destroying a subtree frees the slot of every descendant', () {
      final level = _level();
      final root = level.add();
      final a = level.add(parent: root);
      final b = level.add(parent: root);
      final grandchild = level.add(parent: a);

      final before = HeapObjectRegistry.slotCount;
      var n = 0;
      for (final e in <Entity>[root, a, b, grandchild]) {
        level.thing.owned[e] = _payload(n++);
      }
      expect(HeapObjectRegistry.slotCount, before + 4);

      // One call, four rows: destroy() recurses through
      // Parent.parentFirstChild.
      root.destroy();
      for (var i = 0; i < 4; i++) {
        expect(
          _registerGrewTable(),
          isFalse,
          reason: 'slot ${i + 1} of the subtree was not reclaimed',
        );
      }
    });
  });

  group('scene unload frees the heap-object slots of every row', () {
    test('unloadScene reclaims what its entities owned', () async {
      final game = await _boot();
      final state = run.state;

      final baseline = HeapObjectRegistry.slotCount;
      final scene = await state.loadScene(game.level);
      expect(
        HeapObjectRegistry.slotCount,
        baseline + _GameLevel.spawnPerMount,
        reason: 'three entities each wrote their own object at mount',
      );

      state.unloadScene(scene);

      for (var i = 0; i < _GameLevel.spawnPerMount; i++) {
        expect(
          _registerGrewTable(),
          isFalse,
          reason:
              'unloading a scene frees its pages wholesale rather than row by '
              'row, so without a release pass slot ${i + 1} leaks',
        );
      }
    });

    // Deliberately against `unmountEntitiesOf` rather than through `stop()`.
    // Stopping a game does tear every loaded scene down through here, but it
    // then calls `HeapObjectRegistry.reset()` and wipes the table wholesale -
    // so a probe after `stop()` reports a grown table whether or not the row
    // pass ran, and would have said "leak" against a working fix. This is the
    // call both `unloadScene` and `stop()` actually funnel through, so testing
    // it directly is what pins the third entrance.
    test('unmountEntitiesOf releases every row it announces', () {
      final level = _level();
      final slot = level.handle.slot;

      final before = HeapObjectRegistry.slotCount;
      for (var i = 0; i < 3; i++) {
        level.thing.owned[level.add()] = _payload(i);
      }
      expect(HeapObjectRegistry.slotCount, before + 3);

      level.unmountEntitiesOf(slot);

      for (var i = 0; i < 3; i++) {
        expect(
          _registerGrewTable(),
          isFalse,
          reason:
              'unmountEntitiesOf is the one call scene unload and game stop '
              'share, so slot ${i + 1} has to come back through it',
        );
      }
    });

    test('load/unload cycles do not grow the table without bound', () async {
      final game = await _boot();
      final state = run.state;

      final first = await state.loadScene(game.level);
      state.unloadScene(first);
      final afterFirst = HeapObjectRegistry.slotCount;

      for (var i = 0; i < 5; i++) {
        final scene = await state.loadScene(game.level);
        state.unloadScene(scene);
      }

      expect(
        HeapObjectRegistry.slotCount,
        afterFirst,
        reason:
            'five more load/unload cycles reused the slots the first released. '
            'A steady count across cycles is what the free list is for, and '
            'the exact thing #49 was losing',
      );
    });
  });
}
