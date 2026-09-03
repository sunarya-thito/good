import 'dart:math' as math;

import 'package:goo2d/goo2d.dart';
import 'package:flutter_test/flutter_test.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// A sentinel written directly into a world field between ticks: if
// WorldTransformSystem actually recomputes an entity, it overwrites the
// sentinel with the real value, so the sentinel surviving a tick is proof
// the system skipped that entity rather than merely landing on the same
// answer by coincidence.
const double _sentinel = -999999.0;

class _Node extends EntityStruct
    with Transform2D, WorldTransform2D, Child, Parent {}

/// A prefab that can *be* parented but can never *have* children - no
/// `Parent` mixin. The shape almost every sprite in a real game has, and the
/// one `WorldTransformSystem._resolveChildless` takes its fast path for, so
/// nothing here is exercised by [_Node] at all.
class _Leaf extends EntityStruct with Transform2D, WorldTransform2D, Child {}

/// [_Node] without [WorldTransform2D] - a hierarchy `WorldTransformSystem`
/// composes nothing in. The control for the churn timing below: the system
/// hears every spawn and despawn in the game whether or not it has anything
/// to do with them, so this measures what a scene that never opted in pays.
class _Plain extends EntityStruct with Transform2D, Child, Parent {}

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

  late final _Node node;
  late final _Leaf leaf;
  late final _Plain plain;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    node = descriptor.has(_Node.new);
    leaf = descriptor.has(_Leaf.new);
    plain = descriptor.has(_Plain.new);
  }
}

/// Spawns a parent and a child from *inside* the fixed tick, once, on the
/// first tick after [armed] is set.
///
/// The churn timing at the bottom of this file stresses the set
/// `WorldTransformSystem` keeps of entities spawned since the last step, and
/// is worth nothing if that set is never populated. Nothing a test can read
/// from the outside settles that on its own: an entity created *between*
/// ticks is published before the pass runs, so the pass composes it and the
/// set makes no difference to the answer. Spawning from inside the tick is
/// the case where it does - the splice into the parent's chain is still in
/// the write slot, so the top-down pass cannot reach the child at all, and
/// the set is the only thing that composes it.
class _Spawner extends GameSystem with FixedTickable {
  bool armed = false;

  /// The child spawned on the armed tick.
  Entity? child;

  /// Ahead of `WorldTransformSystem`, which is where a spawner belongs: it
  /// writes the local transforms that pass then composes.
  @override
  int compareTo(GameSystem other) => other is WorldTransformSystem ? -1 : 0;

  @override
  void onFixedUpdate() {
    if (!armed) return;
    armed = false;
    final scene = run.state.singleScene<_Scene>();
    final parent = scene.addEntity(scene.node);
    scene.node.transformOffsetX[parent] = 100;
    final spawned = scene.addEntity(scene.node, parent: parent);
    scene.node.transformOffsetX[spawned] = 10;
    child = spawned;
  }
}

class _GameState extends GameState<_Game> {
  @override
  void onMounted() {
    loadScene(_Scene());
  }

  /// Inert in every test that does not arm it.
  late final _Spawner spawner;

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(WorldTransformSystem.new);
    spawner = descriptor.has(_Spawner.new);
  }
}

class _Game extends Game {
  _Game({this.pageSize = 4096});

  /// A field rather than a constant, for the churn tests at the bottom: the
  /// pool is capped at 128 pages and a freed row is not handed back out
  /// again, so tens of thousands of rows through one fixture needs a page
  /// big enough that they fit. Every other test here spawns a handful.
  @override
  final int pageSize;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _GameState();
}

Future<_Game> _game({int pageSize = 4096}) async {
  final game = await Game.startInline(() => _Game(pageSize: pageSize));
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

const Duration _step = Duration(milliseconds: 10);

/// Spawns [n] children under one parent and destroys all [n] again inside the
/// same tick, returning how long the destruction alone took in microseconds.
///
/// Creation is outside the stopwatch: it is linear in [n] whatever
/// `WorldTransformSystem` does with it, and including it would only dilute
/// the thing being measured.
///
/// The destroy loop runs in reverse creation order. That is the ordinary LIFO
/// teardown, and it is also the worst case for the defect this pins - the
/// entity being taken out of the system's spawned-this-tick set is at the far
/// end of it, so a linear scan pays its full length every time.
int _churnMicros(_Scene scene, EntityStruct prefab, int n) {
  // One tick, opened by hand: spawning and destroying within a single tick is
  // the whole case. Nothing calls `advance` in between, so the system is
  // still holding every one of these when the destroy loop starts.
  run.state.pool.beginTick();
  final root = scene.addEntity(prefab);
  final spawned = List<Entity>.generate(
    n,
    (_) => scene.addEntity(prefab, parent: root),
  );
  final watch = Stopwatch()..start();
  for (var i = n - 1; i >= 0; i--) {
    spawned[i].destroy();
  }
  watch.stop();
  root.destroy();
  run.state.pool.commitTick();
  return watch.elapsedMicroseconds;
}

/// [_churnMicros] three times over, keeping the fastest.
///
/// The minimum rather than the mean, because every source of noise here - GC,
/// the scheduler, JIT still deciding what to optimise - only ever adds time.
int _fastestChurnMicros(_Scene scene, EntityStruct prefab, int n) {
  var best = _churnMicros(scene, prefab, n);
  for (var attempt = 1; attempt < 3; attempt++) {
    run.state.advance(_step);
    final micros = _churnMicros(scene, prefab, n);
    if (micros < best) best = micros;
  }
  return best;
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('the declared systems write no local transform', () {
    test('thirty ticks leave Transform2D and the parent link as set', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();

      final parent = scene.addEntity(scene.node);
      scene.node
        ..transformOffsetX[parent] = 100
        ..transformOffsetY[parent] = 100
        ..transformScaleX[parent] = 2
        ..transformScaleY[parent] = 2;

      final child = scene.addEntity(scene.node, parent: parent);
      scene.node
        ..transformOffsetX[child] = 10
        ..transformOffsetY[child] = -10
        ..transformRotation[child] = 0.5;

      for (var tick = 0; tick < 30; tick++) {
        run.state.advance(_step);
      }

      // The composed answer first, so a run that ticked nothing fails here
      // instead of passing every assertion below by doing no work at all.
      // Child at parent-local (10, -10) under a 2x scale and no parent
      // rotation: world = (100 + 20, 100 - 20).
      expect(scene.node.worldX[child], 120);
      expect(scene.node.worldY[child], 80);
      expect(scene.node.worldScaleX[child], 2);
      expect(scene.node.worldRotation[child], 0.5);

      // A local `Transform2D` is the game's input. The systems goo2d declares
      // read it and compose into `WorldTransform2D`; none of them writes back,
      // so thirty ticks with no game code running leave every column holding
      // what was assigned.
      expect(scene.node.transformOffsetX[parent], 100);
      expect(scene.node.transformOffsetY[parent], 100);
      expect(scene.node.transformScaleX[parent], 2);
      expect(scene.node.transformOffsetX[child], 10);
      expect(scene.node.transformOffsetY[child], -10);
      expect(scene.node.transformRotation[child], 0.5);

      // And the hierarchy is the one that was built. A declared system body
      // that clears `childParent` on its matches takes the scene's whole tree
      // out on the first tick with nothing said - #185. Ticking the declared
      // set against a transform no game code writes is what catches that; a
      // test walking a hand-copied loop cannot, because it owns its entities
      // and can leave every one of them unparented.
      expect(scene.node.childParent[child], parent);
      expect(scene.node.childParent[parent], isNull);
    });
  });

  group('hierarchy composition matches hand-computed numbers', () {
    test('a 2-level hierarchy: offset + 2x scale composes exactly like the renderer\'s own math', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();

      final parent = scene.addEntity(scene.node);
      scene.node
        ..transformOffsetX[parent] = 100
        ..transformOffsetY[parent] = 100
        ..transformScaleX[parent] = 2
        ..transformScaleY[parent] = 2;

      final child = scene.addEntity(scene.node, parent: parent);
      scene.node.transformOffsetX[child] = 10; // no own scale/rotation

      run.state.advance(_step);

      // Child at parent-local (10, 0) under a 2x scale, no rotation:
      // world = parent.world + (10 * 2, 0 * 2) = (120, 100).
      expect(scene.node.worldX[child], 120);
      expect(scene.node.worldY[child], 100);
      expect(scene.node.worldScaleX[child], 2);
      expect(scene.node.worldScaleY[child], 2);
      expect(scene.node.worldRotation[child], 0);

      // The parent's own world transform must equal its local transform -
      // it has no ancestor to compose with.
      expect(scene.node.worldX[parent], 100);
      expect(scene.node.worldY[parent], 100);
    });

    test(
      'a 3-level hierarchy with rotation composes correctly, root to leaf',
      () async {
        await _game();
        final scene = run.state.singleScene<_Scene>();

        final root = scene.addEntity(scene.node);
        scene.node
          ..transformOffsetX[root] = 50
          ..transformOffsetY[root] = 0
          ..transformRotation[root] = math.pi / 2; // 90 degrees

        final middle = scene.addEntity(scene.node, parent: root);
        scene.node.transformOffsetX[middle] = 10; // local +x

        final leaf = scene.addEntity(scene.node, parent: middle);
        scene.node.transformOffsetY[leaf] = 5; // local +y

        run.state.advance(_step);

        // middle: root's world (50,0) rotated 90deg, local offset (10,0)
        // rotates to (0,10) -> world (50, 10).
        expect(scene.node.worldX[middle], closeTo(50, 1e-9));
        expect(scene.node.worldY[middle], closeTo(10, 1e-9));
        expect(scene.node.worldRotation[middle], closeTo(math.pi / 2, 1e-9));

        // leaf: middle's world (50,10) at world rotation 90deg, local offset
        // (0,5) rotates to (-5,0) -> world (45, 10).
        expect(scene.node.worldX[leaf], closeTo(45, 1e-9));
        expect(scene.node.worldY[leaf], closeTo(10, 1e-9));
      },
    );

    test(
      'a non-rendering system can read the resolved world transform too',
      () async {
        await _game();
        final scene = run.state.singleScene<_Scene>();
        final entity = scene.addEntity(scene.node);
        scene.node
          ..transformOffsetX[entity] = 7
          ..transformOffsetY[entity] = 9;
        run.state.advance(_step);

        // No GameRenderer2D involved anywhere in this test - WorldTransform2D
        // is genuinely readable by any system, not just the renderer.
        expect(scene.node.worldX[entity], 7);
        expect(scene.node.worldY[entity], 9);
      },
    );
  });

  group('change-detection caching', () {
    test("an unchanged subtree's cached world fields are untouched after a tick where nothing moved", () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();
      final entity = scene.addEntity(scene.node);
      scene.node.transformOffsetX[entity] = 42;
      run.state.advance(_step); // first tick: real compute, worldX becomes 42

      expect(scene.node.worldX[entity], 42);
      run.state.pool.beginTick();
      scene.node.worldX[entity] = _sentinel; // poke directly - see file doc
      run.state.pool.commitTick();
      run.state.advance(_step); // nothing changed local-side

      expect(
        scene.node.worldX[entity],
        _sentinel,
        reason:
            'the system must have skipped this entity entirely - a '
            'real recompute would have overwritten the sentinel with 42 '
            'again, not merely happened to leave it alone',
      );
    });

    test(
      'moving a leaf does not touch its unrelated sibling\'s cache',
      () async {
        await _game();
        final scene = run.state.singleScene<_Scene>();
        final parent = scene.addEntity(scene.node);
        final a = scene.addEntity(scene.node, parent: parent);
        final b = scene.addEntity(scene.node, parent: parent);
        scene.node
          ..transformOffsetX[a] = 1
          ..transformOffsetX[b] = 2;
        run.state.advance(_step);

        run.state.pool.beginTick();
        scene.node.worldX[b] = _sentinel;
        scene.node.transformOffsetX[a] = 100; // only a changes
        run.state.pool.commitTick();
        run.state.advance(_step);

        expect(scene.node.worldX[a], 100, reason: 'a really did move');
        expect(
          scene.node.worldX[b],
          _sentinel,
          reason: "b's cache must survive - a's change has no bearing on it",
        );
      },
    );

    test('moving a parent invalidates every descendant even though their own local fields did not change', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();
      final parent = scene.addEntity(scene.node);
      final child = scene.addEntity(scene.node, parent: parent);
      scene.node.transformOffsetX[child] = 5;
      run.state.advance(_step);
      expect(scene.node.worldX[child], 5);

      run.state.pool.beginTick();
      scene.node.worldX[child] = _sentinel;
      scene.node.transformOffsetX[parent] = 100; // only the parent moves
      run.state.pool.commitTick();
      run.state.advance(_step);

      expect(
        scene.node.worldX[child],
        105,
        reason:
            'the child never touched its own local offset, but its '
            'world position must still follow its parent - the sentinel '
            'must have been overwritten, not preserved',
      );
    });

    test('reparenting is detected as a change even when the local offset is untouched', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();
      final parentA = scene.addEntity(scene.node);
      final parentB = scene.addEntity(scene.node);
      scene.node
        ..transformOffsetX[parentA] = 0
        ..transformOffsetX[parentB] = 1000;
      final child = scene.addEntity(scene.node, parent: parentA);
      // Deliberately zero local offset - if reparenting were only detected
      // via a local-field diff, this case would slip through.
      run.state.advance(_step);
      expect(scene.node.worldX[child], 0);

      run.state.pool.beginTick();
      scene.node.worldX[child] = _sentinel;
      parentB<Parent>().adopt(child);
      run.state.pool.commitTick();
      run.state.advance(_step);

      expect(
        scene.node.worldX[child],
        1000,
        reason:
            'reparenting alone (no local offset change) must still '
            'trigger a recompute - the sentinel must not survive',
      );
    });
  });

  // An archetype with no `Parent` mixin skips the change-detection cache
  // entirely and recomposes `world = local` every tick - see
  // `WorldTransformSystem._resolveChildless`. These cover what that fast path
  // must still get right; `_Node` cannot reach it, because it has `Parent`.
  group('childless archetypes', () {
    test(
      'an unparented leaf resolves world from its own local transform',
      () async {
        await _game();
        final scene = run.state.singleScene<_Scene>();

        final entity = scene.addEntity(scene.leaf);
        scene.leaf
          ..transformOffsetX[entity] = 12
          ..transformOffsetY[entity] = -4
          ..transformRotation[entity] = 1.5
          ..transformScaleX[entity] = 3
          ..transformScaleY[entity] = 0.5;

        run.state.advance(_step);

        expect(scene.leaf.worldX[entity], 12);
        expect(scene.leaf.worldY[entity], -4);
        expect(scene.leaf.worldRotation[entity], 1.5);
        expect(scene.leaf.worldScaleX[entity], 3);
        expect(scene.leaf.worldScaleY[entity], 0.5);
      },
    );

    test(
      'a leaf parented under a node still composes with its ancestor',
      () async {
        await _game();
        final scene = run.state.singleScene<_Scene>();

        final parent = scene.addEntity(scene.node);
        scene.node
          ..transformOffsetX[parent] = 100
          ..transformScaleX[parent] = 2
          ..transformScaleY[parent] = 2;

        final child = scene.addEntity(scene.leaf, parent: parent);
        scene.leaf.transformOffsetX[child] = 10;

        run.state.advance(_step);

        // Parented rows of a childless archetype are reached through their
        // root's recursion, not the fast path - so they compose normally.
        expect(scene.leaf.worldX[child], 120);
        expect(scene.leaf.worldScaleX[child], 2);
      },
    );

    test('parent, unparent, then re-parent to the same parent with untouched '
        'offsets still recomposes', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();

      final parent = scene.addEntity(scene.node);
      scene.node.transformOffsetX[parent] = 500;
      final child = scene.addEntity(scene.leaf, parent: parent);
      scene.leaf.transformOffsetX[child] = 10;

      run.state.advance(_step);
      expect(scene.leaf.worldX[child], 510);

      // Unparent, keeping it alive - `detach`, not `removeChild`, which
      // destroys. The fast path now owns this row and writes world = local,
      // without consulting or updating the composed cache.
      run.state.pool.beginTick();
      child<Child>().detach();
      run.state.pool.commitTick();
      run.state.advance(_step);
      expect(scene.leaf.worldX[child], 10, reason: 'unparented: world = local');

      // Re-parent to the *same* parent, with every local field identical to
      // what the cache last recorded. Every field-by-field comparison in
      // `_resolve` compares equal, so only the cleared `_cachedParent` stands
      // between this and reading back the uncomposed 10 the fast path wrote.
      run.state.pool.beginTick();
      parent<Parent>().addChild(child);
      run.state.pool.commitTick();
      run.state.advance(_step);

      expect(
        scene.leaf.worldX[child],
        510,
        reason:
            'the fast path must invalidate the cache on its way past, '
            'or this reads back a world transform that was never composed',
      );
    });
  });

  // `WorldTransformSystem` is told about every spawn and every despawn in the
  // game, and holds the spawns it would compose until the next fixed step
  // reaches them. A despawn has to take an entity back out of that set, and
  // for as long as the set was a `List` that removal was a scan plus a shift -
  // so spawning and destroying N parented entities inside one tick cost
  // O(N^2). An explosion clearing a squad, or a level unloading, is exactly
  // that shape.
  //
  // # What these two numbers are worth
  //
  // They are **JIT** timings: `dart compile exe` cannot build anything that
  // imports `package:good/good.dart` (#154), so there is no AOT number to be
  // had here, and the microseconds themselves mean nothing. What survives the
  // constant factor is the *shape* - the ratio between two sizes - which is
  // the only thing asserted. Over a 4x step, linear is 4x and quadratic 16x,
  // and the bound is 6x.
  //
  // Both sides of that bound were measured rather than assumed. Put the
  // `List` back and this reads 11.6x; with the set it reads 2.7x, which is
  // *below* linear because a fixed per-run cost still shows at the smaller
  // size. Sizes are what make the two separate: at 1500 against 6000 the
  // defect measured 7.2x and would have passed a bound of 8.

  group('churn inside one tick', () {
    // The timings below are two flat numbers, and a flat number is also what
    // a set nothing is ever put into produces. This is what says the set is
    // populated at all, and it is a value rather than a duration.
    test('an entity spawned inside the tick is composed out of the set, not '
        'by the pass', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();

      // The page has to have published first, or this proves nothing: a read
      // of a row on a page that never published falls through to the write
      // slot, so on a fresh page the pass sees the pending splice after all
      // and composes the child whether or not the set holds it.
      scene.addEntity(scene.node);
      run.state.advance(_step);
      run.state.advance(_step);

      final state = run.state as _GameState;
      state.spawner.armed = true;
      run.state.advance(_step);

      expect(
        scene.node.worldX[state.spawner.child!],
        110,
        reason:
            'the pass walks `Parent.parentFirstChild` through published '
            'reads and the splice that put this child there is still in the '
            'write slot, so nothing but the spawned-this-tick set can have '
            'composed it - a 0 here means that set stayed empty, and the '
            'timings below would be measuring nothing',
      );
    });

    test('destroying many parented entities in one tick is linear in how '
        'many, not quadratic', () async {
      await _game(pageSize: 1 << 18);
      final scene = run.state.singleScene<_Scene>();

      _churnMicros(scene, scene.node, 400); // warm the JIT
      run.state.advance(_step);

      const int small = 4000;
      const int large = small * 4;
      final smallMicros = _fastestChurnMicros(scene, scene.node, small);
      run.state.advance(_step);
      final largeMicros = _fastestChurnMicros(scene, scene.node, large);

      expect(
        largeMicros / math.max(smallMicros, 1),
        lessThan(6.0),
        reason:
            'destroying ${large}x parented entities took ${largeMicros}us '
            'against ${smallMicros}us for $small - a 4x step. Linear is 4x '
            'and quadratic is 16x, so this is the per-despawn cost growing '
            'with how many entities are already waiting to be composed',
      );
    });

    test(
      'the same churn with no WorldTransform2D in the scene stays flat',
      () async {
        await _game(pageSize: 1 << 18);
        final scene = run.state.singleScene<_Scene>();

        _churnMicros(scene, scene.plain, 400); // warm the JIT
        run.state.advance(_step);

        const int small = 4000;
        const int large = small * 4;
        final smallMicros = _fastestChurnMicros(scene, scene.plain, small);
        run.state.advance(_step);
        final largeMicros = _fastestChurnMicros(scene, scene.plain, large);

        // This one was linear before the fix too - nothing here has
        // `WorldTransform2D`, so the set is empty and the despawn hook returns
        // at its emptiness test. That is the point of running it: it is the
        // same harness, and it stays flat either way, so the test above going
        // red is about the set and not about the harness.
        expect(
          largeMicros / math.max(smallMicros, 1),
          lessThan(6.0),
          reason:
              'no entity in this scene has WorldTransform2D, so a despawn has '
              'nothing to do at all: ${largeMicros}us for $large against '
              '${smallMicros}us for $small',
        );
      },
    );
  });
}
