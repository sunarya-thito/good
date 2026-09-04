import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:goo3d/goo3d.dart';

part 'world_transform_3d_test.g.dart';

/// The live run under test. A file-level binding: the bring-up helper returns
/// the `Game` (the description) while tests also need the run, and one inline
/// run per isolate means one binding is enough.
late Game run;

// A sentinel written directly into a world field between ticks: if
// WorldTransform3DSystem actually recomputes an entity, it overwrites the
// sentinel with the real value, so the sentinel surviving a tick is proof the
// system skipped that entity rather than merely landing on the same answer by
// coincidence.
const double _sentinel = -999999.0;

class _Node extends EntityStruct
    with Transform3D, WorldTransform3D, Child, Parent {}

/// A prefab that can *be* parented but can never *have* children - no
/// `Parent` mixin. The shape almost every prop in a real game has, and the one
/// `WorldTransform3DSystem._resolveChildless` takes its fast path for.
class _Leaf extends EntityStruct with Transform3D, WorldTransform3D, Child {}

/// A grouping node: hierarchy links and a local transform, but no world
/// columns of its own. Its descendants still get composed through it.
class _Group extends EntityStruct with Transform3D, Child, Parent {}

/// A prop that is never parented and never asked for world columns. The
/// cheapest thing this package can express, and the reason `WorldTransform3D`
/// is opt-in at all.
class _Prop extends EntityStruct with Transform3D {}

class _Scene extends SceneStruct {
  @override
  void onSceneMounted(Scene scene) => handle = scene;

  /// This fixture's loaded handle. Entity creation lives on `Scene` (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Scene();

  @sub
  final node = _Node();
  @sub
  final leaf = _Leaf();
  @sub
  final group = _Group();
  @sub
  final prop = _Prop();
}

/// Spawns from inside a tick, as a real game does - before
/// `WorldTransform3DSystem` runs, which is the ordering a gameplay system
/// spawning something would have.
class _Spawner extends GameSystem with FixedTickable {
  double? spawnX;
  Entity? spawnParent;
  Entity? spawned;

  @override
  int compareTo(GameSystem other) => other is WorldTransform3DSystem ? -1 : 0;

  @override
  void onFixedUpdate() {
    final x = spawnX;
    if (x == null) return;
    spawnX = null;
    final scene = state.singleScene<_Scene>();
    final parent = spawnParent;
    final entity = parent == null
        ? scene.handle.addEntity(scene.node)
        : scene.handle.addEntity(scene.node, parent: parent);
    scene.node.transformOffsetX[entity] = x;
    spawned = entity;
  }
}

class _GameState extends GameState<_Game> {
  @override
  void onMounted() {
    loadScene(_Scene());
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(WorldTransform3DSystem.new);
    descriptor.has(_Spawner.new);
  }
}

class _Game extends Game {
  _Game({this.pageSize = 4096});

  /// A field rather than a constant, for the churn tests at the bottom: a
  /// freed row is not handed back out again within the run, so tens of
  /// thousands of rows through one fixture needs a page big enough that they
  /// all fit. Every other test here spawns a handful.
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
/// `WorldTransform3DSystem` does with it, and including it would only dilute
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

/// sin/cos of a quarter turn, as the quaternion stores them.
final double _quarter = math.sqrt(2) / 2;

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('hierarchy composition matches hand-computed numbers', () {
    test('a root\'s world transform is its local one', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();
      final entity = scene.addEntity(scene.node);
      scene.node
        ..transformOffsetX[entity] = 7
        ..transformOffsetY[entity] = 9
        ..transformOffsetZ[entity] = -3
        ..transformScaleY[entity] = 4;
      entity<Transform3D>().setEuler(yaw: 0.25);

      run.state.advance(_step);

      expect(scene.node.worldX[entity], 7);
      expect(scene.node.worldY[entity], 9);
      expect(scene.node.worldZ[entity], -3);
      expect(scene.node.worldScaleY[entity], 4);
      expect(scene.node.worldRotationY[entity], math.sin(0.125));
      expect(scene.node.worldRotationW[entity], math.cos(0.125));
    });

    test('a 3-deep chain composes position, rotation and scale', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();

      final root = scene.addEntity(scene.node);
      scene.node
        ..transformOffsetX[root] = 50
        ..transformScaleX[root] = 2
        ..transformScaleY[root] = 2
        ..transformScaleZ[root] = 2;
      root<Transform3D>().setEuler(yaw: math.pi / 2);

      final middle = scene.addEntity(scene.node, parent: root);
      scene.node
        ..transformOffsetX[middle] = 10
        ..transformScaleX[middle] = 3
        ..transformScaleY[middle] = 3
        ..transformScaleZ[middle] = 3;

      final leaf = scene.addEntity(scene.node, parent: middle);
      scene.node
        ..transformOffsetZ[leaf] = -5
        ..transformScaleX[leaf] = 0.5
        ..transformScaleY[leaf] = 0.5
        ..transformScaleZ[leaf] = 0.5;

      run.state.advance(_step);

      // middle: its local (10, 0, 0) is scaled by the root's 2 to (20, 0, 0),
      // then turned a quarter turn about +Y, which sends +X to -Z: (0, 0, -20).
      // Plus the root's own (50, 0, 0).
      expect(scene.node.worldX[middle], closeTo(50, 1e-9));
      expect(scene.node.worldY[middle], closeTo(0, 1e-9));
      expect(scene.node.worldZ[middle], closeTo(-20, 1e-9));
      expect(scene.node.worldScaleX[middle], 6);
      expect(scene.node.worldScaleZ[middle], 6);

      // leaf: local (0, 0, -5) scaled by middle's world 6 is (0, 0, -30), and
      // the same quarter turn sends -Z to -X: (-30, 0, 0), from middle's
      // (50, 0, -20).
      expect(scene.node.worldX[leaf], closeTo(20, 1e-9));
      expect(scene.node.worldY[leaf], closeTo(0, 1e-9));
      expect(scene.node.worldZ[leaf], closeTo(-20, 1e-9));
      expect(scene.node.worldScaleX[leaf], closeTo(3, 1e-12));

      // Rotation is inherited whole - neither descendant added any.
      for (final entity in [middle, leaf]) {
        expect(scene.node.worldRotationX[entity], closeTo(0, 1e-15));
        expect(scene.node.worldRotationY[entity], closeTo(_quarter, 1e-15));
        expect(scene.node.worldRotationZ[entity], closeTo(0, 1e-15));
        expect(scene.node.worldRotationW[entity], closeTo(_quarter, 1e-15));
      }
    });

    test(
      'two quarter turns about the same axis compose into a half turn',
      () async {
        await _game();
        final scene = run.state.singleScene<_Scene>();

        final root = scene.addEntity(scene.node);
        root<Transform3D>().setEuler(yaw: math.pi / 2);
        final child = scene.addEntity(scene.node, parent: root);
        child<Transform3D>().setEuler(yaw: math.pi / 2);

        run.state.advance(_step);

        // A half turn about +Y is (0, 1, 0, 0) - and the quaternion product is
        // what produces it, not an angle sum.
        expect(scene.node.worldRotationX[child], closeTo(0, 1e-15));
        expect(scene.node.worldRotationY[child], closeTo(1, 1e-15));
        expect(scene.node.worldRotationZ[child], closeTo(0, 1e-15));
        expect(scene.node.worldRotationW[child], closeTo(0, 1e-15));
      },
    );

    test('rotating a parent swings its child around it', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();

      final parent = scene.addEntity(scene.node);
      final child = scene.addEntity(scene.node, parent: parent);
      scene.node.transformOffsetX[child] = 10;

      run.state.advance(_step);
      expect(scene.node.worldX[child], 10);
      expect(scene.node.worldZ[child], 0);

      run.state.pool.beginTick();
      parent<Transform3D>().setEuler(yaw: math.pi / 2);
      run.state.pool.commitTick();
      run.state.advance(_step);

      // The child never touched its own transform: +X, a quarter turn about
      // +Y, is -Z.
      expect(scene.node.worldX[child], closeTo(0, 1e-9));
      expect(scene.node.worldY[child], closeTo(0, 1e-9));
      expect(scene.node.worldZ[child], closeTo(-10, 1e-9));
    });

    test('pitching a parent up lifts the child in front of it', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();

      final parent = scene.addEntity(scene.node);
      parent<Transform3D>().setEuler(pitch: math.pi / 2);
      final child = scene.addEntity(scene.node, parent: parent);
      scene.node.transformOffsetZ[child] = -4; // 4 in front, along -Z

      run.state.advance(_step);

      // A quarter turn about +X takes +Y to +Z and so -Z to +Y: what was in
      // front is now overhead, because +Y is up.
      expect(scene.node.worldX[child], closeTo(0, 1e-9));
      expect(scene.node.worldY[child], closeTo(4, 1e-9));
      expect(scene.node.worldZ[child], closeTo(0, 1e-9));
    });

    test(
      'a grouping node with no world columns still composes its subtree',
      () async {
        await _game();
        final scene = run.state.singleScene<_Scene>();

        final root = scene.addEntity(scene.node);
        scene.node.transformOffsetX[root] = 100;

        final middle = scene.addEntity(scene.group, parent: root);
        scene.group.transformOffsetY[middle] = 5;

        final leaf = scene.addEntity(scene.leaf, parent: middle);
        scene.leaf.transformOffsetZ[leaf] = -2;

        run.state.advance(_step);

        // The middle has nowhere to store a world transform, so it is composed
        // only to be handed down.
        expect(scene.leaf.worldX[leaf], 100);
        expect(scene.leaf.worldY[leaf], 5);
        expect(scene.leaf.worldZ[leaf], -2);
      },
    );
  });

  group('opting out', () {
    test(
      'an unparented entity with no WorldTransform3D is left alone',
      () async {
        await _game();
        final scene = run.state.singleScene<_Scene>();

        final prop = scene.addEntity(scene.prop);
        scene.prop
          ..transformOffsetX[prop] = 3
          ..transformOffsetY[prop] = -8
          ..transformOffsetZ[prop] = 12;
        prop<Transform3D>().setEuler(yaw: 1.1);

        run.state.advance(_step);
        run.state.advance(_step);

        // Its local transform *is* its world transform, and the system does not
        // touch it - a prop that is never parented pays nothing.
        expect(scene.prop.transformOffsetX[prop], 3);
        expect(scene.prop.transformOffsetY[prop], -8);
        expect(scene.prop.transformOffsetZ[prop], 12);
        expect(prop<Transform3D>().yaw, closeTo(1.1, 1e-12));
      },
    );

    test(
      'a childless archetype resolves world from its own local transform',
      () async {
        await _game();
        final scene = run.state.singleScene<_Scene>();

        final entity = scene.addEntity(scene.leaf);
        scene.leaf
          ..transformOffsetX[entity] = 12
          ..transformOffsetY[entity] = -4
          ..transformOffsetZ[entity] = 6
          ..transformScaleX[entity] = 3
          ..transformScaleZ[entity] = 0.5;
        entity<Transform3D>().setEuler(roll: 1.5);

        run.state.advance(_step);

        expect(scene.leaf.worldX[entity], 12);
        expect(scene.leaf.worldY[entity], -4);
        expect(scene.leaf.worldZ[entity], 6);
        expect(scene.leaf.worldScaleX[entity], 3);
        expect(scene.leaf.worldScaleZ[entity], 0.5);
        expect(scene.leaf.worldRotationZ[entity], math.sin(0.75));
        expect(scene.leaf.worldRotationW[entity], math.cos(0.75));
      },
    );
  });

  group('change-detection caching', () {
    test('an unchanged entity is skipped entirely', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();
      final parent = scene.addEntity(scene.node);
      final entity = scene.addEntity(scene.node, parent: parent);
      scene.node.transformOffsetX[entity] = 42;
      run.state.advance(_step);
      expect(scene.node.worldX[entity], 42);

      run.state.pool.beginTick();
      scene.node.worldX[entity] = _sentinel; // poke directly - see file doc
      run.state.pool.commitTick();
      run.state.advance(_step);

      expect(
        scene.node.worldX[entity],
        _sentinel,
        reason:
            'the system must have skipped this entity entirely - a real '
            'recompute would have overwritten the sentinel with 42 again, not '
            'merely happened to leave it alone',
      );
    });

    test('a rotation change alone invalidates the cache', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();
      final parent = scene.addEntity(scene.node);
      final child = scene.addEntity(scene.node, parent: parent);
      scene.node.transformOffsetX[child] = 10;
      run.state.advance(_step);

      run.state.pool.beginTick();
      scene.node.worldX[child] = _sentinel;
      // Only the quaternion columns change - no offset, no scale, no
      // reparent. A cache that compared position alone would sail past this.
      parent<Transform3D>().setEuler(yaw: math.pi / 2);
      run.state.pool.commitTick();
      run.state.advance(_step);

      expect(scene.node.worldX[child], closeTo(0, 1e-9));
      expect(scene.node.worldZ[child], closeTo(-10, 1e-9));
    });

    test('moving a parent invalidates every descendant', () async {
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
            'the child never touched its own local offset, but its world '
            'position must still follow its parent',
      );
    });

    test('parent, unparent, then re-parent with untouched offsets still '
        'recomposes', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();

      final parent = scene.addEntity(scene.node);
      scene.node.transformOffsetX[parent] = 500;
      final child = scene.addEntity(scene.leaf, parent: parent);
      scene.leaf.transformOffsetX[child] = 10;

      run.state.advance(_step);
      expect(scene.leaf.worldX[child], 510);

      // Unparent, keeping it alive - `detach`, not `removeChild`, which
      // destroys. The childless fast path now owns this row and writes
      // world = local without consulting or updating the composed cache.
      run.state.pool.beginTick();
      child<Child>().detach();
      run.state.pool.commitTick();
      run.state.advance(_step);
      expect(scene.leaf.worldX[child], 10, reason: 'unparented: world = local');

      // Re-parent to the *same* parent, with every local field identical to
      // what the cache last recorded. Every field-by-field comparison in
      // `_resolve` compares equal, so only the cleared `worldCachedParent`
      // stands between this and reading back the uncomposed 10.
      run.state.pool.beginTick();
      parent<Parent>().addChild(child);
      run.state.pool.commitTick();
      run.state.advance(_step);

      expect(
        scene.leaf.worldX[child],
        510,
        reason:
            'the fast path must invalidate the cache on its way past, or '
            'this reads back a world transform that was never composed',
      );
    });
  });

  group('entities spawned mid-tick', () {
    test('a root spawned during the tick has its world transform on that '
        'same tick', () async {
      await _game();
      final spawner = run.state.getSystem<_Spawner>();
      spawner.spawnX = 33;
      run.state.advance(_step);

      final scene = run.state.singleScene<_Scene>();
      final spawned = spawner.spawned!;
      expect(
        scene.node.worldX[spawned],
        33,
        reason:
            'the main pass reads the last published snapshot and cannot '
            'see a write made earlier in its own tick, so the spawn list is '
            'what makes this right',
      );
    });

    test('a child spawned during the tick composes with its parent', () async {
      await _game();
      final scene = run.state.singleScene<_Scene>();
      final parent = scene.addEntity(scene.node);
      scene.node.transformOffsetX[parent] = 200;
      run.state.advance(_step);

      final spawner = run.state.getSystem<_Spawner>();
      spawner
        ..spawnParent = parent
        ..spawnX = 7;
      run.state.advance(_step);

      expect(
        scene.node.worldX[spawner.spawned!],
        207,
        reason:
            'the splice into the parent\'s child list happened this tick, '
            'so the top-down walk never reached this entity at all',
      );
    });
  });

  // `WorldTransform3DSystem` is told about every spawn and every despawn in
  // the game, and holds the spawns it would compose until the next fixed step
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
  // # Why 4000, and not something quicker
  //
  // Both sides of the bound were measured rather than assumed. With the
  // `List` back this reads 15.5x to 16.0x; with the set it reads 4.0x to
  // 4.9x, and the control below reads about the same either way. The sizes
  // are what makes those separate, and shrinking them breaks the test's
  // ability to fail: the smaller size's absolute time falls to a few hundred
  // microseconds, where JIT warm-up is the larger term. Measured at 1000
  // against 4000, sitting where this test sits, the defect read **2.2x** and
  // would have passed any bound at all. At 4000 against 16000, in that same
  // position, it read 15.9x.

  group('churn inside one tick', () {
    // The timings below are two flat numbers, and a flat number is also what
    // a set nothing is ever put into produces. What says the set is populated
    // at all is `a child spawned during the tick composes with its parent`
    // above, which reads a value rather than a duration: the splice into the
    // parent's child list is still in the write slot, so the top-down pass
    // cannot reach that child and only the set can compose it. Stop
    // populating the set and both timings here still pass while that one
    // reads 0 - and so does its sibling, the *root* spawned mid-tick, which
    // lands on a fresh row whose read falls through to the write slot and is
    // composed either way.
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
            'destroying $large parented entities took ${largeMicros}us '
            'against ${smallMicros}us for $small - a 4x step. Linear is 4x '
            'and quadratic is 16x, so this is the per-despawn cost growing '
            'with how many entities are already waiting to be composed',
      );
    });

    test(
      'the same churn with no WorldTransform3D in the scene stays flat',
      () async {
        await _game(pageSize: 1 << 18);
        final scene = run.state.singleScene<_Scene>();

        _churnMicros(scene, scene.group, 400); // warm the JIT
        run.state.advance(_step);

        const int small = 4000;
        const int large = small * 4;
        final smallMicros = _fastestChurnMicros(scene, scene.group, small);
        run.state.advance(_step);
        final largeMicros = _fastestChurnMicros(scene, scene.group, large);

        // This one was linear before the fix too - `_Group` has no
        // `WorldTransform3D`, so the set is empty and the despawn hook
        // returns at its emptiness test. That is the point of running it: it
        // is the same harness, and it stays flat either way, so the test
        // above going red is about the set and not about the harness.
        expect(
          largeMicros / math.max(smallMicros, 1),
          lessThan(6.0),
          reason:
              'no entity in this scene has WorldTransform3D, so a despawn '
              'has nothing to do at all: ${largeMicros}us for $large against '
              '${smallMicros}us for $small',
        );
      },
    );
  });
}
