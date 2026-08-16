import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

// Solid-colour quads, not textures: no image-decoding GameAsset type exists
// in the engine yet, so DrawSpriteData2D carries a colour and a world-space
// quad. See draw_2d.dart's doc on DrawSpriteData2D.
const int _playerColor = 0xFF4FC3F7;
const int _visorColor = 0xFF1A237E;
const int _enemyColor = 0xFFEF5350;
const int _wingmanColor = 0xFFFFEE58;

/// The player. `Parent` as well as `Child` so the wingman can be attached to
/// it - which is what puts `GameRenderer2D`'s hierarchy flattening under load
/// in this example rather than only in the tests.
///
/// Two sprites, to show what `Renderable2D` being a `MultiComponent` buys: the
/// body and the visor are one entity with one transform, drawn as two
/// independently sized, coloured and depth-sorted rectangles. The visor's
/// higher `zIndex` is what keeps it on top of the body whatever order the
/// query happens to yield.
/// The player's breathing pulse, as a declared timeline.
///
/// A `TimelineStruct` is a declaration shared by every entity of the archetype,
/// exactly like the prefab itself - there is no animation *object* per player.
/// Sampling it is `animate()` plus a lookup, both allocation-free, which is why
/// a system can do it per entity per tick without thinking about it.
class Breath extends TimelineStruct {
  late final Track<double> scale;

  late final TimelineAnimation pulse;

  @override
  void describeTrack(TimelineDescriptor descriptor) {
    scale = descriptor.has<double>(1.0);
  }

  @override
  void describeAnimation(TimelineAnimationDescriptor descriptor) {
    // Half a second up. `WrapMode.pingPong` at sample time plays it back down
    // again, so the shape is authored once rather than twice and cannot go
    // asymmetric when someone edits one half.
    pulse = descriptor.has()..track(scale).key(1.0).key(1.12, 0.5);
  }
}

class Player extends EntityStruct
    with Transform2D, WorldTransform2D, Child, Parent, Renderable2D {
  late final Sprite body;
  late final Sprite visor;

  /// Declared with no `with Animations` in sight: every `EntityStruct` has
  /// `describeAnimation`, defaulting to declaring nothing.
  late final Breath breath;

  @override
  void describeAnimation(AnimationTypeDescriptor descriptor) {
    breath = descriptor.has(Breath());
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    // Every field is a declared archetype default, so there is no onMounted
    // here at all - these values are stamped into the row when the entity is
    // created, by the storage layer, not by a write on the creation tick.
    body = descriptor.has(width: 64, height: 64, color: _playerColor);
    visor = descriptor.has(
      width: 28,
      height: 12,
      color: _visorColor,
      zIndex: 1,
      // Sitting the visor above the body's centre: half a body-height up is
      // not expressible as a fraction of the *visor's* own bounds, which is
      // why the pivot carries an absolute offset alongside its fraction.
      pivot: const RelativeOffset2D(
        fractionX: 0.5,
        fractionY: 0.5,
        offsetY: 18,
      ),
    );
  }
}

class Enemy extends EntityStruct
    with
        Transform2D,
        WorldTransform2D,
        Child,
        Renderable2D,
        EntityLifecycleListener {
  late final Sprite body;

  /// Plain Dart state on the prefab, which lives on the game isolate and is
  /// never shared - the cheap way to fan spawns out instead of stacking every
  /// one of them on the same pixel.
  int _spawned = 0;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    body = descriptor.has(width: 36, height: 36, color: _enemyColor);
  }

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    // Writing (never reading-then-writing) on the creation tick: a read here
    // would see the previous tick's published snapshot, not what was just
    // stamped. See data_layout.dart's note on _readRow. Only the position
    // needs this - it differs per spawn, where the sprite's size and colour
    // are the same for every enemy and so are declared defaults instead.
    // Laid out around the world origin, because that is the middle of the
    // view - the camera's position is what the view is centred on, so a
    // scene written for a top-left origin would sit off to one side.
    transformOffsetX[entity] = -140 + (_spawned % 6) * 56;
    transformOffsetY[entity] = -160 + (_spawned ~/ 6) * 56;
    _spawned++;
  }
}

/// Parented to the player, so its own transform is only an offset *from* the
/// player - the renderer composes the two.
class Wingman extends EntityStruct
    with
        Transform2D,
        WorldTransform2D,
        Child,
        Renderable2D,
        EntityLifecycleListener {
  late final Sprite body;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    body = descriptor.has(width: 28, height: 28, color: _wingmanColor);
  }

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    transformOffsetX[entity] = 70;
  }
}

/// The view. A camera entity is an ordinary entity - `GameRenderer2D` finds it
/// by query, so nothing here has to hand it to the renderer.
class Eye extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

class MainScene extends SceneStruct {
  late final Player playerPrefab;
  late final Enemy enemyPrefab;
  late final Wingman wingmanPrefab;
  late final Eye eyePrefab;

  @override
  void describeScene(SceneDescriptor descriptor) {
    playerPrefab = descriptor.has(Player());
    enemyPrefab = descriptor.has(Enemy());
    wingmanPrefab = descriptor.has(Wingman());
    eyePrefab = descriptor.has(Eye());
  }

  /// Runs on the game isolate before the first tick. Writing component data
  /// here is safe specifically because nothing has been published yet, so the
  /// first `beginTick` has no snapshot to copy over these writes - see the
  /// assertion in `data_layout.dart`'s `_Field._write`.
  @override
  void onSceneMounted(Scene scene) {
    final player = scene.addEntity(playerPrefab);
    playerPrefab.transformOffsetX[player] = 0;
    playerPrefab.transformOffsetY[player] = 120;

    for (var i = 0; i < 5; i++) {
      scene.addEntity(enemyPrefab);
    }

    // The wingman is a child, so it renders at player + (70, 0) rotated by the
    // player's rotation - it orbits as the player spins.
    scene.addEntity(wingmanPrefab, parent: player);

    // Left at the origin with the default zoom of 1, so the world origin is
    // the middle of the view - the same place an implicit camera would put
    // it, which is why this scene looks identical with the eye removed. It
    // is here so the camera path is exercised by the example and not only by
    // tests: move this entity's transform (or parent it to the player) and
    // the whole scene scrolls.
    scene.addEntity(eyePrefab);
  }
}

/// Something to make the frame move, so "does it render" and "does it render
/// the *current* tick" are distinguishable.
///
/// Note this example does not declare `Transform2DSystem`. That system's body
/// is an explicitly-labelled placeholder which, among other things, clears
/// `Child.parent` on every entity every tick - which would tear down the
/// hierarchy this example exists to exercise before the first frame.
class SpinSystem extends GameSystem with FixedTickable {
  late final Query spinnable;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    spinnable = descriptor.query().withAll(Transform2D, Renderable2D).build();
  }

  @override
  void onFixedUpdate() {
    for (final entity in spinnable.run()) {
      final transform = entity.get<Transform2D>();
      // Reads see last tick's published value, so this is exactly one
      // increment per tick no matter what else ran first.
      transform.transformRotation[entity] =
          transform.transformRotation[entity] + 0.01;

      // `tryGet` rather than a type test on the entity: only the player has a
      // Breath, and asking the row whether it has the component is the
      // sanctioned lookup (RULES.md rule 11 names it explicitly).
      final player = entity.tryGet<Player>();
      if (player == null) continue;
      // Sampled fresh every tick from the clock - no per-entity animation
      // state anywhere, and nothing to keep in step.
      final at = player.breath.pulse.animate(wrapMode: WrapMode.pingPong);
      final scale = player.breath.scale[at];
      transform
        ..transformScaleX[entity] = scale
        ..transformScaleY[entity] = scale;
    }
  }
}

/// The simulation half. Everything that mutates the world lives on this side
/// of the split; `MyAwesomeGame` below only *declares*.
/// "Add an enemy, and tell me which one" - how the UI asks the simulation for
/// something.
///
/// Note what does *not* cross: the prefab, and its archetype id. The Flutter
/// isolate names the **intent**; [MyGameState] is what decides that an enemy
/// means `MainScene.enemyPrefab`, because it runs where the scene and its
/// memory actually are. An engine-supplied `spawnEntity(archetypeId)` used to
/// live here and was removed for exactly that reason - it made the UI name an
/// identifier belonging to the other isolate.
class SpawnEnemy extends SupplierCommand<Entity> {
  late final ParamPointer<int> spawned;

  @override
  void describeParams(ParamDescriptor descriptor) {
    // Signed: `Entity.pack` shifts the archetype id up into the sign bit, and
    // only getInt64/setInt64 round-trip every bit pattern.
    spawned = descriptor.hasInt64();
  }

  @override
  void bufferFromResult(CommandBuffer call, Entity result) =>
      spawned[call] = result.value;

  @override
  Entity resultFromBuffer(CommandBuffer call) => Entity(spawned[call]);
}

/// The simulation half. Everything that mutates the world lives here.
class MyGameState extends GameState2D<MyAwesomeGame> {
  /// Held in a field so the command handler below can reach the prefab. This
  /// side owns the scene; the `Game` never needs to name it.
  final MainScene level = MainScene();

  @override
  void onMounted() {
    loadScene(level);
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    // super first: GameState2D declares WorldTransformSystem and
    // GameRenderer2D itself, so this game only declares what is actually its
    // own. Ordering between them is not positional anyway - GameRenderer2D's
    // compareTo puts it after WorldTransformSystem wherever either is
    // declared.
    super.describeSystems(descriptor);
    descriptor.has(SpinSystem());
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    // `hasSupplier` only *handles* - the declaration itself belongs to the
    // Game, because that is the side holding the handle the UI calls through.
    descriptor.hasSupplier(game.spawnEnemy, _onSpawnEnemy);
  }

  /// Runs on the game isolate, inside the tick window and before any system,
  /// so the enemy is visible to the whole simulation on the tick it arrives.
  Entity _onSpawnEnemy() => loadedScenes.single.addEntity(level.enemyPrefab);
}

/// `Game2D` rather than `Game`: that is the opt-in for painting, and it is
/// what puts a `CustomPaint` fed by the draw buffer under the `GameView`. Its
/// simulation half is a [GameState2D], which is what declares the systems that
/// produce the frames - and `createState` is narrowed to that type, so the two
/// halves cannot come apart.
class MyAwesomeGame extends Game2D {
  /// Declared here, handled in [MyGameState]: the declaration site is whoever
  /// has to *hold* the handle, and it is the UI that calls this one.
  late final SpawnEnemy spawnEnemy;

  @override
  GameState2D<MyAwesomeGame> createState() => MyGameState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    spawnEnemy = descriptor.has(SpawnEnemy());
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  /// The game: the description *and* the run, because an instance backs
  /// exactly one of them. Typed as the subclass rather than as `Game` so
  /// `game.spawnEnemy` resolves without a cast, which is also why
  /// `Game.start` returns the type it was given.
  ///
  /// Null until `start()` completes - and that null is the gate on building a
  /// `GameView`, which throws if handed a game that is not running yet.
  MyAwesomeGame? game;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final started = await Game.start(MyAwesomeGame());
    if (!mounted) {
      // Disposed while the isolate was spawning. Nothing else will ever stop
      // this run, so it has to happen here.
      await started.stop();
      return;
    }
    setState(() => game = started);
  }

  @override
  void dispose() {
    game?.stop();
    super.dispose();
  }

  // Spawning from the UI goes through a command, which writes into the shared
  // RingBuffer rather than sending one SendPort message per press - see the
  // project root plan's "Cross-isolate architecture" section, lane 2.
  //
  // The whole call is `game.spawnEnemy()`. Nothing here reaches into the game
  // isolate's scene, names a prefab, or knows an archetype id exists: the UI
  // states what it wants and the handler on the other side decides what that
  // means. That is the boundary the command lane is for.
  Future<void> _onSpawnPressed() async {
    // Awaitable, and worth awaiting: the entity comes back over the reply ring
    // once the game isolate has actually created it, so a HUD that wants to
    // track what it spawned gets a handle rather than having to guess.
    final spawned = await game!.spawnEnemy();
    debugPrint('spawned enemy ${spawned.value}');
  }

  @override
  Widget build(BuildContext context) {
    // Promoted to a local so the null check below sticks - `game` is a field,
    // and a field cannot be promoted across the closure boundaries here.
    final game = this.game;
    return MaterialApp(
      title: 'goo2d example',
      home: Scaffold(
        backgroundColor: const Color(0xFF101418),
        body: Stack(
          children: [
            if (game != null) GameView(camera: game.defaultCamera),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FloatingActionButton(
                  onPressed: game == null ? null : _onSpawnPressed,
                  child: const Icon(Icons.add),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
