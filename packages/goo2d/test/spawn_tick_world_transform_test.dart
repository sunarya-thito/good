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

class _Scene extends SceneStruct {
  late Scene handle;
  late final _Leaf leaf;

  @override
  void onSceneMounted(Scene scene) => handle = scene;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    leaf = descriptor.has(_Leaf());
  }
}

/// Spawns and destroys from inside a tick, as a real game does.
class _Spawner extends GameSystem with FixedTickable {
  Entity? spawned;
  double? spawnX;
  double? spawnY;
  Entity? toDestroy;

  /// Sorted before WorldTransformSystem so the spawn happens first in the
  /// tick - the ordering a gameplay system spawning something would have.
  @override
  int compareTo(GameSystem other) =>
      other is WorldTransformSystem ? -1 : 0;

  @override
  void onFixedUpdate() {
    final kill = toDestroy;
    if (kill != null) {
      toDestroy = null;
      kill.destroy();
    }
    final x = spawnX;
    if (x == null) return;
    spawnX = null;
    final scene = state.getScene<_Scene>();
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
    spawner = descriptor.has(_Spawner());
    descriptor.has(WorldTransformSystem());
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
    final run = await Game.startInline(_Game());
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });
    final leaf = run.state.getScene<_Scene>().leaf;

    spawner
      ..spawnX = 500
      ..spawnY = 300;
    run.state.advance(_step);
    final a = spawner.spawned!;

    expect(leaf.worldX[a], 500);
    expect(leaf.worldY[a], 300);
  });

  test('a RECYCLED row is at the world origin for exactly one tick', () async {
    // **This asserts the bug, deliberately.** It is not the behaviour anyone
    // wants - one frame of a sprite at the world origin is a visible pop -
    // but it is what the engine does today, and pinning it means a fix has a
    // test that already fails in the right place rather than a rumour to
    // chase. Change the first expectation to (111, 222) when fixing it.
    //
    // The options, none of them free:
    //
    //  * make a row that has never published read its own write slot, as
    //    pages already do - principled, fixes all four instances of this
    //    found so far, but needs a per-row check on the hottest read path in
    //    the engine (2.25 ns today);
    //  * compose world transforms in a presentation pass instead of a fixed
    //    step, so they are computed after the tick's writes are published;
    //  * hide a renderable until its world transform has been composed once.
    final run = await Game.startInline(_Game());
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });
    final leaf = run.state.getScene<_Scene>().leaf;

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
      0,
      reason: 'CURRENT BEHAVIOUR, not desired: the world transform composed '
          'from the row as it was before this tick wrote to it',
    );
    expect(leaf.worldY[b], 0);

    run.state.advance(_step);

    expect(
      leaf.worldX[b],
      111,
      reason: 'and it is right one tick later, so the error is exactly one '
          'frame long',
    );
    expect(leaf.worldY[b], 222);
  });
}
