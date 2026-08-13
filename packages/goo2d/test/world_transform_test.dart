import 'dart:math' as math;

import 'package:goo2d/goo2d.dart';
import 'package:flutter_test/flutter_test.dart';

// A sentinel written directly into a world field between ticks: if
// WorldTransformSystem actually recomputes an entity, it overwrites the
// sentinel with the real value, so the sentinel surviving a tick is proof
// the system skipped that entity rather than merely landing on the same
// answer by coincidence.
const double _sentinel = -999999.0;

class _Node extends EntityStruct<_Node> with Transform2D, WorldTransform2D, Child, Parent {}

class _Scene extends SceneStruct {
  @override
  void onMounted(Scene scene) => handle = scene;

  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late Scene handle;

  Entity addEntity<T extends EntityStruct<T>>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Scene();

  late final _Node node;

  @override
  void describeScene(SceneDescriptor descriptor) {
    node = descriptor.has(_Node());
  }
}

class _GameState extends GameState<_Game> with LifecycleListener {
  @override
  void onMounted() {
    loadScene(_Scene());
  }
}

class _Game extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _GameState();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(WorldTransformSystem());
  }
}

Future<_Game> _game() async {
  final game = _Game();
  await game.start(inline: true, autoTick: false);
  addTearDown(() async {
    if (game.isRunning) await game.stop();
  });
  return game;
}

const Duration _step = Duration(milliseconds: 10);

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('hierarchy composition matches hand-computed numbers', () {
    test('a 2-level hierarchy: offset + 2x scale composes exactly like the renderer\'s own math', () async {
      final game = await _game();
      final scene = game.state!.getScene<_Scene>();

      final parent = scene.addEntity(scene.node);
      scene.node
        ..transformOffsetX[parent] = 100
        ..transformOffsetY[parent] = 100
        ..transformScaleX[parent] = 2
        ..transformScaleY[parent] = 2;

      final child = scene.addEntity(scene.node, parent: parent);
      scene.node.transformOffsetX[child] = 10; // no own scale/rotation

      game.state!.advance(_step);

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

    test('a 3-level hierarchy with rotation composes correctly, root to leaf', () async {
      final game = await _game();
      final scene = game.state!.getScene<_Scene>();

      final root = scene.addEntity(scene.node);
      scene.node
        ..transformOffsetX[root] = 50
        ..transformOffsetY[root] = 0
        ..transformRotation[root] = math.pi / 2; // 90 degrees

      final middle = scene.addEntity(scene.node, parent: root);
      scene.node.transformOffsetX[middle] = 10; // local +x

      final leaf = scene.addEntity(scene.node, parent: middle);
      scene.node.transformOffsetY[leaf] = 5; // local +y

      game.state!.advance(_step);

      // middle: root's world (50,0) rotated 90deg, local offset (10,0)
      // rotates to (0,10) -> world (50, 10).
      expect(scene.node.worldX[middle], closeTo(50, 1e-9));
      expect(scene.node.worldY[middle], closeTo(10, 1e-9));
      expect(scene.node.worldRotation[middle], closeTo(math.pi / 2, 1e-9));

      // leaf: middle's world (50,10) at world rotation 90deg, local offset
      // (0,5) rotates to (-5,0) -> world (45, 10).
      expect(scene.node.worldX[leaf], closeTo(45, 1e-9));
      expect(scene.node.worldY[leaf], closeTo(10, 1e-9));
    });

    test('a non-rendering system can read the resolved world transform too', () async {
      final game = await _game();
      final scene = game.state!.getScene<_Scene>();
      final entity = scene.addEntity(scene.node);
      scene.node
        ..transformOffsetX[entity] = 7
        ..transformOffsetY[entity] = 9;
      game.state!.advance(_step);

      // No GameRenderer2D involved anywhere in this test - WorldTransform2D
      // is genuinely readable by any system, not just the renderer.
      expect(scene.node.worldX[entity], 7);
      expect(scene.node.worldY[entity], 9);
    });
  });

  group('change-detection caching', () {
    test("an unchanged subtree's cached world fields are untouched after a tick where nothing moved", () async {
      final game = await _game();
      final scene = game.state!.getScene<_Scene>();
      final entity = scene.addEntity(scene.node);
      scene.node.transformOffsetX[entity] = 42;
      game.state!.advance(_step); // first tick: real compute, worldX becomes 42

      expect(scene.node.worldX[entity], 42);
      game.state!.pool.beginTick();
      scene.node.worldX[entity] = _sentinel; // poke directly - see file doc
      game.state!.pool.commitTick();
      game.state!.advance(_step); // nothing changed local-side

      expect(scene.node.worldX[entity], _sentinel,
          reason: 'the system must have skipped this entity entirely - a '
              'real recompute would have overwritten the sentinel with 42 '
              'again, not merely happened to leave it alone');
    });

    test('moving a leaf does not touch its unrelated sibling\'s cache', () async {
      final game = await _game();
      final scene = game.state!.getScene<_Scene>();
      final parent = scene.addEntity(scene.node);
      final a = scene.addEntity(scene.node, parent: parent);
      final b = scene.addEntity(scene.node, parent: parent);
      scene.node
        ..transformOffsetX[a] = 1
        ..transformOffsetX[b] = 2;
      game.state!.advance(_step);

      game.state!.pool.beginTick();
      scene.node.worldX[b] = _sentinel;
      scene.node.transformOffsetX[a] = 100; // only a changes
      game.state!.pool.commitTick();
      game.state!.advance(_step);

      expect(scene.node.worldX[a], 100, reason: 'a really did move');
      expect(scene.node.worldX[b], _sentinel,
          reason: "b's cache must survive - a's change has no bearing on it");
    });

    test('moving a parent invalidates every descendant even though their own local fields did not change', () async {
      final game = await _game();
      final scene = game.state!.getScene<_Scene>();
      final parent = scene.addEntity(scene.node);
      final child = scene.addEntity(scene.node, parent: parent);
      scene.node.transformOffsetX[child] = 5;
      game.state!.advance(_step);
      expect(scene.node.worldX[child], 5);

      game.state!.pool.beginTick();
      scene.node.worldX[child] = _sentinel;
      scene.node.transformOffsetX[parent] = 100; // only the parent moves
      game.state!.pool.commitTick();
      game.state!.advance(_step);

      expect(scene.node.worldX[child], 105,
          reason: 'the child never touched its own local offset, but its '
              'world position must still follow its parent - the sentinel '
              'must have been overwritten, not preserved');
    });

    test('reparenting is detected as a change even when the local offset is untouched', () async {
      final game = await _game();
      final scene = game.state!.getScene<_Scene>();
      final parentA = scene.addEntity(scene.node);
      final parentB = scene.addEntity(scene.node);
      scene.node
        ..transformOffsetX[parentA] = 0
        ..transformOffsetX[parentB] = 1000;
      final child = scene.addEntity(scene.node, parent: parentA);
      // Deliberately zero local offset - if reparenting were only detected
      // via a local-field diff, this case would slip through.
      game.state!.advance(_step);
      expect(scene.node.worldX[child], 0);

      game.state!.pool.beginTick();
      scene.node.worldX[child] = _sentinel;
      parentA.get<Parent>().removeChild(parentA, child);
      parentB.get<Parent>().addChild(parentB, child);
      game.state!.pool.commitTick();
      game.state!.advance(_step);

      expect(scene.node.worldX[child], 1000,
          reason: 'reparenting alone (no local offset change) must still '
              'trigger a recompute - the sentinel must not survive');
    });
  });
}
