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
class Player extends EntityStruct<Player> with Transform2D, WorldTransform2D, Child, Parent, Renderable2D {
  late final Sprite body;
  late final Sprite visor;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    // Every field is a declared archetype default, so there is no onCreated
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
      pivot: const RelativeOffset2D(fractionX: 0.5, fractionY: 0.5, offsetY: 18),
    );
  }
}

class Enemy extends EntityStruct<Enemy> with Transform2D, WorldTransform2D, Child, Renderable2D {
  late final Sprite body;

  /// Plain Dart state on the prefab, which lives on the game isolate and is
  /// never shared - the cheap way to fan spawns out instead of stacking every
  /// one of them on the same pixel.
  int _spawned = 0;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    body = descriptor.has(width: 36, height: 36, color: _enemyColor);
  }

  @override
  void onCreated(Entity entity) {
    super.onCreated(entity);
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
class Wingman extends EntityStruct<Wingman> with Transform2D, WorldTransform2D, Child, Renderable2D {
  late final Sprite body;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    body = descriptor.has(width: 28, height: 28, color: _wingmanColor);
  }

  @override
  void onCreated(Entity entity) {
    super.onCreated(entity);
    transformOffsetX[entity] = 70;
  }
}

/// The view. A camera entity is an ordinary entity - `GameRenderer2D` finds it
/// by query, so nothing here has to hand it to the renderer.
class Eye extends EntityStruct<Eye> with Transform2D, WorldTransform2D, Camera {}

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
  void onMounted(Scene scene) {
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
      transform.transformRotation[entity] = transform.transformRotation[entity] + 0.01;
    }
  }
}

/// The simulation half. Everything that mutates the world lives on this side
/// of the split; `MyAwesomeGame` below only *declares*.
class MyGameState extends GameState<MyAwesomeGame> with LifecycleListener {
  /// Built once per isolate, on each copy of the Game - never assigned to a
  /// field in a constructor, because the Game instance *is* the Isolate.spawn
  /// message and a scene drags a MemoryPool full of pointers with it. See the
  /// class doc on Game.
  @override
  void onMounted() {
    loadScene(MainScene());
  }
}

/// `Game2D` rather than `Game`: that is the opt-in for painting, and it is
/// what puts a `CustomPaint` fed by the draw buffer under the `GameView`.
/// Declaring `GameRenderer2D` below is the other half - it is what produces
/// the frames to paint.
class MyAwesomeGame extends Game2D {
  @override
  GameState createState() => MyGameState();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    // super first: Game2D declares WorldTransformSystem and GameRenderer2D
    // itself, so this game only declares what is actually its own. Ordering
    // between them is not positional anyway - GameRenderer2D's compareTo puts
    // it after WorldTransformSystem wherever either is declared.
    super.describeSystems(descriptor);
    descriptor.has(SpinSystem());
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
  late final Game game;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    game = MyAwesomeGame();
    _boot();
  }

  /// `GameView` may only be built once `start()` has completed: it registers a
  /// tick listener, and a closure reachable from the Game at spawn time would
  /// make the spawn message unsendable. Hence the gate rather than firing
  /// start() off and building the view in the same frame.
  Future<void> _boot() async {
    await game.start();
    if (mounted) setState(() => _started = true);
  }

  @override
  void dispose() {
    game.stop();
    super.dispose();
  }

  // Spawning entities from the UI (e.g. a HUD button) goes through a command,
  // which writes into the shared RingBuffer rather than sending one SendPort
  // message per press - see the project root plan's "Cross-isolate
  // architecture" section, lane 2. The prefab is named by archetype id
  // because a prefab instance is a Dart object owned by the game isolate's
  // scene and cannot cross; the id is the same integer on both sides.
  Future<void> _onSpawnPressed() async {
    // The main-isolate copy runs the same declaration passes, so its
    // GameState mirrors the scene and can name a prefab's archetype id - the
    // integer that means the same thing on both isolates.
    final scene = game.state!.getScene<MainScene>();
    // Awaitable, and worth awaiting: the entity comes back over the reply
    // ring once the game isolate has actually created it, so a HUD that wants
    // to track what it spawned gets a handle rather than having to guess.
    final spawned = await game.spawnEntity(scene.enemyPrefab.archetypeId);
    debugPrint('spawned enemy ${spawned.value}');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'goo2d example',
      home: Scaffold(
        backgroundColor: const Color(0xFF101418),
        body: Stack(
          children: [
            if (_started) GameView(game: game),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FloatingActionButton(
                  onPressed: _started ? _onSpawnPressed : null,
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
