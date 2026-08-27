// What an entity's WORLD transform holds on the tick it was spawned.
//
// This pins a real, currently-unfixed engine behaviour rather than asserting
// that it is correct - see the group doc below. It exists so the behaviour is
// a known quantity with a number attached instead of a rumour, and so that
// whoever fixes it has a test that already fails in the right way.
//
// # The mechanism
//
// `WorldTransformSystem` is a `FixedTickable`: it reads `Transform2D` and
// writes `WorldTransform2D` inside the step. Component reads serve the last
// **published** snapshot, so a transform written earlier in the *same* tick -
// which is what spawning an entity and positioning it does - is not visible
// to it. It composes from whatever the row held before.
//
// **It only bites on recycled rows.** `MemoryPage.resolveRow` falls through
// to the write slot while a page has never published, so an entity spawned
// into a fresh page reads back its own same-tick writes and everything looks
// right. Every fixture that starts from an empty scene is in that case, which
// is exactly why this went unnoticed and was carried as an unverified
// hypothesis in the project's perf notes.
//
// Measured: a fresh row composes correctly on the spawn tick; a recycled row
// publishes **(0, 0)** for one tick and the right answer on the next. One
// frame of a sprite at the world origin, which on screen is a pop across the
// whole view.
import 'package:goo2d/goo2d.dart';
import 'package:flutter_test/flutter_test.dart';

class _Leaf extends EntityStruct with Transform2D, WorldTransform2D, Child {}

/// Both ends of a hierarchy in one archetype, so a whole chain shares a page -
/// which is what puts a spawned child on a page that has **already published**,
/// the only case where the bug below is visible at all.
class _Node extends EntityStruct
    with Transform2D, WorldTransform2D, Child, Parent {}

/// One queued spawn. [parent] names an entity that already exists; [afterIndex]
/// names one spawned earlier in this same tick, by its index in
/// `_Spawner.nodes` - that is the hub -> body -> limb shape the swarm demo
/// creates all at once.
class _NodeRequest {
  _NodeRequest(this.x, this.y, {this.parent, this.afterIndex});

  final double x;
  final double y;
  final Entity? parent;
  final int? afterIndex;
}

class _Scene extends SceneStruct {
  late Scene handle;
  late final _Leaf leaf;
  late final _Node node;

  @override
  void onSceneMounted(Scene scene) => handle = scene;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    leaf = descriptor.has(_Leaf.new);
    node = descriptor.has(_Node.new);
  }
}

/// Spawns and destroys from inside a tick, as a real game does.
class _Spawner extends GameSystem with FixedTickable {
  Entity? spawned;
  double? spawnX;
  double? spawnY;
  Entity? toDestroy;

  /// Drained in order, all within one tick.
  final List<_NodeRequest> nodeRequests = <_NodeRequest>[];

  /// Every `_Node` spawned so far, in spawn order.
  final List<Entity> nodes = <Entity>[];

  /// Sorted before WorldTransformSystem so the spawn happens first in the
  /// tick - the ordering a gameplay system spawning something would have.
  @override
  int compareTo(GameSystem other) => other is WorldTransformSystem ? -1 : 0;

  @override
  void onFixedUpdate() {
    final kill = toDestroy;
    if (kill != null) {
      toDestroy = null;
      kill.destroy();
    }
    final scene = state.singleScene<_Scene>();

    if (nodeRequests.isNotEmpty) {
      for (final request in nodeRequests) {
        final parent =
            request.parent ??
            (request.afterIndex == null ? null : nodes[request.afterIndex!]);
        final entity = parent == null
            ? scene.handle.addEntity(scene.node)
            : scene.handle.addEntity(scene.node, parent: parent);
        scene.node
          ..transformOffsetX[entity] = request.x
          ..transformOffsetY[entity] = request.y;
        nodes.add(entity);
      }
      nodeRequests.clear();
    }

    final x = spawnX;
    if (x == null) return;
    spawnX = null;
    final entity = scene.handle.addEntity(scene.leaf);
    scene.leaf
      ..transformOffsetX[entity] = x
      ..transformOffsetY[entity] = spawnY!;
    spawned = entity;
  }
}

class _GameState extends GameState<_Game> {
  @override
  void onMounted() => loadScene(_Scene());

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    spawner = descriptor.has(_Spawner.new);
    descriptor.has(WorldTransformSystem.new);
  }
}

// ignore: library_private_types_in_public_api
late _Spawner spawner;

class _Game extends Game {
  @override
  int get pageSize => 4096;
  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);
  @override
  GameState createState() => _GameState();
}

const Duration _step = Duration(milliseconds: 10);

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('a FRESH row composes correctly on the tick it is spawned', () async {
    // The happy case, and the reason the broken one hid for so long. Nothing
    // on this page has published yet, so the read falls through to the write
    // slot and the system sees the position the spawner just wrote.
    final run = await Game.startInline(_Game.new);
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });
    final leaf = run.state.singleScene<_Scene>().leaf;

    spawner
      ..spawnX = 500
      ..spawnY = 300;
    run.state.advance(_step);
    final a = spawner.spawned!;

    expect(leaf.worldX[a], 500);
    expect(leaf.worldY[a], 300);
  });

  test('a RECYCLED row composes correctly on the tick it is spawned', () async {
    // **This asserted the bug until it was fixed**, which is why it exists:
    // it failed in exactly the right place the moment the behaviour changed.
    //
    // The fix is that `WorldTransformSystem` is *told* which entities are new,
    // through `EntitySpawnListener`, and composes those from the pending
    // transform. Being told is the only thing that works - a row that is new
    // cannot be detected through a published read, because any flag you might
    // check is as stale as the data itself. The per-entity hot path is
    // untouched; the extra pass costs nothing in a tick where nothing
    // spawned.
    final run = await Game.startInline(_Game.new);
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });
    final leaf = run.state.singleScene<_Scene>().leaf;

    // Use the row once, then free it so the next spawn recycles it - by
    // which point the page has published and the fall-through is gone.
    spawner
      ..spawnX = 500
      ..spawnY = 300;
    run.state.advance(_step);
    spawner.toDestroy = spawner.spawned;
    run.state.advance(_step);
    run.state.advance(_step);

    spawner
      ..spawnX = 111
      ..spawnY = 222;
    run.state.advance(_step);
    final b = spawner.spawned!;

    expect(
      leaf.worldX[b],
      111,
      reason:
          'a recycled row must compose from what the spawner just wrote, '
          'not from what the row held before - that was the one frame of a '
          'sprite at the world origin',
    );
    expect(leaf.worldY[b], 222);

    run.state.advance(_step);

    expect(leaf.worldX[b], 111, reason: 'and it stays right afterwards');
    expect(leaf.worldY[b], 222);
  });

  test('a spawned CHILD composes against its parent on the spawn tick', () async {
    // **The swarm demo's yellow ball.** A child is not merely composed from a
    // stale row like the cases above - it is not visited *at all* on its spawn
    // tick. The main pass descends through `Parent.firstChild`, an ordinary
    // published read, and the splice that added this entity to its parent's
    // child list happened this tick. So the pass walks straight past it and
    // its world row publishes holding the defaults: (0, 0), the world origin.
    //
    // The page must have published for this to bite, which is what the first
    // advance below is for - on a fresh page `resolveRow` falls through to the
    // write slot and everything is accidentally right. That is exactly why the
    // bug appeared at no repeatable point while dragging the population
    // slider: it needs a *new row on an already-published page*, and a
    // recycled row instead shows the previous occupant's position, which is
    // somewhere plausible in the swarm and invisible.
    final run = await Game.startInline(_Game.new);
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });
    final node = run.state.singleScene<_Scene>().node;

    spawner.nodeRequests.add(_NodeRequest(100, 0));
    run.state.advance(_step);
    final parent = spawner.nodes[0];
    expect(node.worldX[parent], 100, reason: 'the parent is an ordinary root');

    spawner.nodeRequests.add(_NodeRequest(10, 20, parent: parent));
    run.state.advance(_step);
    final child = spawner.nodes[1];

    expect(
      node.worldX[child],
      110,
      reason:
          'a child spawned this tick must be composed against its '
          'parent - 0 here is the sprite at the world origin for one frame',
    );
    expect(node.worldY[child], 20);

    run.state.advance(_step);

    expect(node.worldX[child], 110, reason: 'and it stays right afterwards');
    expect(node.worldY[child], 20);
  });

  test('a whole CHAIN spawned in one tick composes on that tick', () async {
    // hub -> body -> limb, created by a single `spawnCritter()` call, which is
    // literally what the swarm demo does. The grandchild's parent does not
    // exist in any published snapshot either, so it can only be composed
    // against a transform written moments earlier in this same pass - which
    // works because `_spawned` is in spawn order and a parent necessarily
    // precedes the children that name it.
    final run = await Game.startInline(_Game.new);
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });
    final node = run.state.singleScene<_Scene>().node;

    spawner.nodeRequests.add(_NodeRequest(100, 0));
    run.state.advance(_step);
    final root = spawner.nodes[0];

    spawner.nodeRequests
      ..add(_NodeRequest(10, 20, parent: root))
      ..add(_NodeRequest(1, 2, afterIndex: 1));
    run.state.advance(_step);
    final child = spawner.nodes[1];
    final grandChild = spawner.nodes[2];

    expect(node.worldX[child], 110);
    expect(node.worldY[child], 20);
    expect(
      node.worldX[grandChild],
      111,
      reason: 'composed against a parent that was itself spawned this tick',
    );
    expect(node.worldY[grandChild], 22);
  });
}
