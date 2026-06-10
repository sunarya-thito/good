import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';
// ignore: implementation_imports
import 'package:google_fonts/google_fonts.dart';

// --- Assets ---

enum MyGameTexture with AssetEnum, AssetTextureEnum {
  ship,
  tilesPacked,
  enemy,
  explosion,
  ;

  @override
  AssetSource get source => AssetSource.local("assets/sprites/$name.png");
}

enum MyGameSound with AssetEnum, AudioAssetEnum {
  shoot,
  explosion,
  bgm
  ;

  @override
  AssetSource get source => AssetSource.local("assets/audios/$name.ogg");
}

Future<void> loadAllGameAssets() async {
  await GoogleFonts.pendingFonts([
    GoogleFonts.jersey10(),
  ]);
  await for (final p in GameAsset.loadAll(MyGameTexture.values)) {
    if (kDebugMode) {
      print(
        'Loading ${p.loadingAsset.source.name} (${p.assetLoaded}/${p.assetCount})',
      );
    }
  }
  await for (final p in GameAsset.loadAll(MyGameSound.values)) {
    if (kDebugMode) {
      print(
        'Loading ${p.loadingAsset.source.name} (${p.assetLoaded}/${p.assetCount})',
      );
    }
  }
}

// --- Entry Point ---

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  GameEngine? _engine;
  late Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _initialize();
  }

  Future<void> _initialize() async {
    _engine = await GameEngine.create();
    await loadAllGameAssets();
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: FutureBuilder(
          future: _loadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return DefaultTextStyle(
              style: GoogleFonts.jersey10(),
              child: Game(
                engine: _engine!,
                child: BattleWorld(),
              ),
            );
          },
        ),
      ),
    );
  }
}

// --- Game World ---

class BattleWorld extends StatefulGameWidget {
  const BattleWorld({super.key});
  @override
  GameState<BattleWorld> createState() => BattleWorldState();
}

class BattleWorldState extends GameState<BattleWorld> with Tickable {
  final List<Widget> bullets = [];
  final List<Widget> enemies = [];
  late SpriteSheet<TileCoord> explosionSheet;
  double _enemySpawnTimer = 0;

  @override
  void initState() {
    super.initState();
    explosionSheet = SpriteSheet.grid(
      texture: MyGameTexture.explosion,
      rows: 1,
      columns: 13,
      ppu: 64.0,
    );
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {
    const playerTag = 'Player';

    // Background & Music
    yield GameObjectWidget(
      tag: 'Background',
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(TiledBackground.new),
        ComponentWidget(
          AudioSource.new.withInitialValues(
            (c) => c
              ..clip = MyGameSound.bgm
              ..loop = true
              ..volume = 0.5,
          ),
        ),
      ],
    );

    // Player
    yield BattleWorldProvider(
      world: this,
      child: Player(tag: playerTag),
    );

    // Cameras
    yield GameObjectWidget(
      tag: 'MainCamera',
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues(
            (c) => c
              ..depth = 1.0
              ..backgroundColor = Colors.black
              ..orthographicSize = 2.0,
          ),
        ),
        ComponentWidget(
          FollowTarget.new.withInitialValues((c) => c.targetTag = playerTag),
        ),
        ComponentWidget(CameraShake.new),
      ],
    );

    yield GameObjectWidget(
      tag: 'MinimapCamera',
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues(
            (c) => c
              ..depth = 0.0
              ..orthographicSize = 3.0
              ..backgroundColor = Colors.black87
              ..cullingMask = RenderLayer.world,
          ),
        ),
        ComponentWidget(
          FollowTarget.new.withInitialValues((c) => c.targetTag = playerTag),
        ),
      ],
    );

    yield* bullets;
    yield* enemies;

    // HUD
    yield const InstructionsUI(
      tag: 'Instructions',
      layer: RenderLayer.ui,
    );
    yield const MinimapUI(tag: 'Minimap', layer: RenderLayer.ui);
    yield const FPSUI(tag: 'FPS', layer: RenderLayer.ui);
    yield const MuteUI(tag: 'Mute', layer: RenderLayer.ui);
  }

  @override
  void onUpdate(double dt) {
    _enemySpawnTimer -= dt;
    if (_enemySpawnTimer <= 0) {
      _spawnEnemy();
      _enemySpawnTimer = 2.0;
    }
  }

  void _spawnEnemy() {
    final player = GameObject.findWithTag(gameObject, 'Player');
    if (player == null) return;
    final pTrans = player.getComponent<ObjectTransform>();

    final forward = Vector2(-math.sin(-pTrans.angle), -math.cos(-pTrans.angle));
    final angle =
        math.atan2(forward.y, forward.x) +
        (math.Random().nextDouble() - 0.5) * (math.pi / 1.5);
    final pos =
        pTrans.position + Vector2(math.cos(angle), math.sin(angle)) * 15.0;

    setState(() {
      final key = UniqueKey();
      enemies.add(
        GameObjectWidget(
          key: key,
          tag: key,
          children: [
            ComponentWidget(
              ObjectTransform.new.withInitialValues((c) => c.position = pos),
            ),
            ComponentWidget(
              Rigidbody.new.withInitialValues(
                (c) => c.bodyType = RigidbodyType.kinematic,
              ),
            ),
            ComponentWidget(
              SpriteRenderer.new.withInitialValues(
                (c) => c
                  ..sprite = GameSprite(
                    mesh: SimpleMesh(texture: MyGameTexture.enemy),
                    pixelsPerUnit: 64.0,
                  )
                  ..filterQuality = ui.FilterQuality.none,
              ),
            ),
            ComponentWidget(EnemyController.new),
            ComponentWidget(
              CircleCollider.new.withInitialValues((c) => c.radius = 0.2),
            ),
          ],
        ),
      );
    });
  }

  void _spawnExplosion(Vector2 position) {
    setState(() {
      final key = UniqueKey();
      enemies.add(
        GameObjectWidget(
          key: key,
          tag: key,
          children: [
            ComponentWidget(
              ObjectTransform.new.withInitialValues(
                (c) => c
                  ..position = position
                  ..scale = Vector2(1.0, -1.0),
              ),
            ),
            ComponentWidget(
              SpriteRenderer.new.withInitialValues(
                (c) => c
                  ..sprite = explosionSheet[(0, 0)]
                  ..filterQuality = ui.FilterQuality.none,
              ),
            ),
            ComponentWidget(ExplosionController.new),
            ComponentWidget(
              AudioSource.new.withInitialValues(
                (c) => c
                  ..clip = MyGameSound.explosion
                  ..volume = 1.5,
              ),
            ),
          ],
        ),
      );
    });
  }

  void _destroyObject(GameObject obj) {
    setState(() {
      bullets.removeWhere((w) => w.key == obj.tag);
      enemies.removeWhere((w) => w.key == obj.tag);
    });
  }

  void addBullet(Widget bullet) => setState(() => bullets.add(bullet));
  void removeBullet(Widget bullet) => setState(() => bullets.remove(bullet));
}

// --- Player & Entities ---

class Player extends StatefulGameWidget {
  const Player({super.key, super.tag});
  @override
  GameState<Player> createState() => PlayerState();
}

class PlayerState extends GameState<Player> with Tickable {
  late InputAction moveAction, shootAction;
  late BattleWorldState _world;
  late GameSprite _bulletSprite;
  late AudioSource _audioSource;

  @override
  void initState() {
    super.initState();
    _world = getComponentInParent<BattleWorldState>();
    _bulletSprite = SpriteSheet.grid(
      texture: MyGameTexture.tilesPacked,
      rows: 10,
      columns: 12,
      ppu: 64.0,
    )[(0, 0)];

    addComponent(
      moveAction = InputAction()
        ..name = 'thrust'
        ..type = InputActionType.button
        ..bindings = [Keyboard.keyW],
      shootAction = InputAction()
        ..name = 'shoot'
        ..type = InputActionType.button
        ..bindings = [Keyboard.space],
    );

    addComponent(
      ObjectTransform()..position = Vector2.zero(),
      Rigidbody()..bodyType = RigidbodyType.kinematic,
      SpriteRenderer()
        ..sprite = GameSprite(
          mesh: SimpleMesh(texture: MyGameTexture.ship),
          pivot: Point2D.center,
          pixelsPerUnit: 64.0,
        )
        ..filterQuality = ui.FilterQuality.none,
      CircleCollider()..radius = 0.2,
      BlinkEffect(),
      _audioSource = AudioSource()
        ..clip = MyGameSound.shoot
        ..volume = 0.4
        ..playOnAwake = false,
    );
  }

  double _shootTimer = 0,
      _rotationVel = 0,
      _rotationVelVel = 0,
      _speed = 2.0,
      _speedVel = 0;

  @override
  void onUpdate(double dt) {
    final trans = getComponent<ObjectTransform>();

    // Rotation
    double targetRot = 0;
    if (Keyboard.keyA.isPressed(game)) targetRot += 1.0;
    if (Keyboard.keyD.isPressed(game)) targetRot -= 1.0;

    final rotRes = MathUtils.smoothDamp(
      _rotationVel,
      targetRot * 4.5,
      _rotationVelVel,
      0.1,
      dt,
    );
    _rotationVel = rotRes.value;
    _rotationVelVel = rotRes.velocity;
    trans.angle += _rotationVel * dt;

    // Movement
    final facing = Vector2(-math.sin(-trans.angle), -math.cos(-trans.angle));
    final speedRes = MathUtils.smoothDamp(
      _speed,
      moveAction.inProgress ? 4.0 : 2.0,
      _speedVel,
      0.4,
      dt,
    );
    _speed = speedRes.value;
    _speedVel = speedRes.velocity;
    trans.position += facing * _speed * dt;

    // Shooting
    _shootTimer -= dt;
    if (shootAction.inProgress && _shootTimer <= 0) {
      _audioSource.play();
      final key = UniqueKey();
      _world.addBullet(
        GameObjectWidget(
          key: key,
          tag: key,
          children: [
            ComponentWidget(
              ObjectTransform.new.withInitialValues(
                (c) => c
                  ..position = trans.position + facing * 0.25
                  ..angle = trans.angle,
              ),
            ),
            ComponentWidget(
              SpriteRenderer.new.withInitialValues(
                (c) => c
                  ..sprite = _bulletSprite
                  ..filterQuality = ui.FilterQuality.none,
              ),
            ),
            ComponentWidget(
              BulletController.new.withInitialValues(
                (c) => c.direction = facing,
              ),
            ),
            ComponentWidget(
              Rigidbody.new.withInitialValues(
                (c) => c.bodyType = RigidbodyType.kinematic,
              ),
            ),
            ComponentWidget(BulletOutOfScreenDestroyer.new),
            ComponentWidget(
              CircleCollider.new.withInitialValues((c) => c.radius = 0.2),
            ),
          ],
        ),
      );
      _shootTimer = 0.1;
    }
  }
}

class BulletController extends Behavior
    with Tickable, LifecycleListener, PhysicsContactListener<Collider> {
  late Vector2 direction;
  late ObjectTransform _transform;
  late BattleWorldState world;
  double _lifetime = 0;

  @override
  void onMounted() {
    _transform = getComponent<ObjectTransform>();
    world = getComponentInParent<BattleWorldState>();
  }

  @override
  void onUpdate(double dt) {
    _transform.position += direction * 15.0 * dt;
    if ((_lifetime += dt) >= 2.0) world._destroyObject(gameObject);
  }

  @override
  Future<void> onContactEnter(PhysicsContact<Collider> e) async {
    if (e.bodyB.gameObject.tryGetComponent<EnemyController>() != null) {
      world._destroyObject(gameObject);
    }
  }
}

class EnemyController extends Behavior
    with Tickable, LifecycleListener, PhysicsContactListener<Collider> {
  late ObjectTransform _transform;
  late BattleWorldState world;
  late double speed, _swerveOffset, _swerveSpeed;

  @override
  void onMounted() {
    _transform = getComponent<ObjectTransform>();
    world = getComponentInParent<BattleWorldState>();
    final rand = math.Random();
    speed = 1.5 + rand.nextDouble() * 1.5;
    _swerveOffset = rand.nextDouble() * math.pi * 2;
    _swerveSpeed = 0.5 + rand.nextDouble() * 1.5;
  }

  @override
  void onUpdate(double dt) {
    final player = GameObject.findWithTag(gameObject, 'Player');
    if (player == null) return;
    final toPlayer =
        player.getComponent<ObjectTransform>().position - _transform.position;
    final dist = toPlayer.length;
    if (dist > 0.1) {
      final dir = toPlayer / dist;
      _transform.position += dir * speed * dt;
      _transform.position +=
          Vector2(-dir.y, dir.x) *
          math.sin(game.ticker.time * _swerveSpeed + _swerveOffset) *
          1.2 *
          dt;
      _transform.angle = -math.atan2(toPlayer.x, toPlayer.y) + math.pi;
    }
  }

  @override
  Future<void> onContactEnter(PhysicsContact<Collider> e) async {
    final other = e.bodyB;
    if (other.gameObject.tag == 'Player') {
      GameObject.findWithTag(gameObject, 'MainCamera')
          ?.getComponent<CameraShake>()
          .shake();
      other.gameObject.getComponent<BlinkEffect>().blink();
    }
    if (other.gameObject.tryGetComponent<BulletController>() != null ||
        other.gameObject.tag == 'Player') {
      world._spawnExplosion(_transform.position);
      world._destroyObject(gameObject);
    }
  }
}

// --- Reusable Behaviors & Helpers ---

class FollowTarget extends Behavior with LifecycleListener, LateTickable {
  late Object targetTag;
  @override
  void onLateUpdate(double dt) {
    final target = GameObject.findWithTag(gameObject, targetTag)
        ?.tryGetComponent<ObjectTransform>();
    if (target != null) {
      getComponent<ObjectTransform>().position = target.position;
    }
  }
}

class CameraShake extends Behavior with LifecycleListener, LateTickable {
  double _trauma = 0, _magnitude = 0, _timer = 0, _decayRate = 2.0;
  Vector2 _currentOffset = Vector2.zero(),
      _targetOffset = Vector2.zero(),
      _velocity = Vector2.zero();
  final math.Random _random = math.Random();

  void shake([double duration = 0.4, double magnitude = 0.25]) {
    _trauma = 1.0;
    _magnitude = magnitude;
    _decayRate = 1.0 / duration;
  }

  @override
  void onLateUpdate(double dt) {
    if (_trauma <= 0) return;
    _trauma = math.max(0, _trauma - _decayRate * dt);
    if ((_timer -= dt) <= 0) {
      _timer = 0.02;
      final s = _trauma * _trauma;
      _targetOffset = Vector2(
        (_random.nextDouble() * 2 - 1) * _magnitude * s,
        (_random.nextDouble() * 2 - 1) * _magnitude * s,
      );
    }
    final res = MathUtils.smoothDampVector2(
      _currentOffset,
      _targetOffset,
      _velocity,
      0.015,
      dt,
    );
    _currentOffset = res.value;
    _velocity = res.velocity;
    getComponent<ObjectTransform>().position += _currentOffset;
  }
}

class BlinkEffect extends Behavior with LifecycleListener, Tickable {
  double _timer = 0;
  late SpriteRenderer _renderer;
  @override
  void onMounted() => _renderer = getComponent<SpriteRenderer>();
  void blink([double duration = 0.15]) {
    _timer = duration;
    _renderer.color = Colors.white;
    _renderer.blendMode = ui.BlendMode.srcIn;
  }

  @override
  void onUpdate(double dt) {
    if (_timer > 0 && (_timer -= dt) <= 0) {
      _renderer.color = Colors.white;
      _renderer.blendMode = ui.BlendMode.modulate;
    }
  }
}

class ExplosionController extends Behavior with Tickable, LifecycleListener {
  int _frame = 0;
  double _timer = 0;
  @override
  void onUpdate(double dt) {
    if ((_timer += dt) >= 0.05) {
      _timer = 0;
      if (++_frame >= 13) {
        getComponentInParent<BattleWorldState>()._destroyObject(gameObject);
      } else {
        getComponent<SpriteRenderer>().sprite =
            getComponentInParent<BattleWorldState>().explosionSheet[(
              _frame,
              0,
            )];
      }
    }
  }
}

class BulletOutOfScreenDestroyer extends Behavior
    with ScreenCollidable, LifecycleListener {
  @override
  void onExitScreen() =>
      getComponentInParent<BattleWorldState>().removeBullet(gameObject.widget);
}

class TiledBackground extends Component with LifecycleListener, Renderable {
  late SpriteSheet _sheet;
  late GameSprite _grass;

  @override
  void onMounted() {
    _sheet = SpriteSheet.grid(
      texture: MyGameTexture.tilesPacked,
      rows: 10,
      columns: 12,
      ppu: 64.0,
    );
    _grass = _sheet[(2, 4)];
  }

  int _hash(int x, int y) {
    var h = x * 374761393 + y * 668265263;
    return (h ^ (h >> 13)) * 12741261 & 0x7FFFFFFF;
  }

  final _paint = ui.Paint()
    ..filterQuality = ui.FilterQuality.none
    ..isAntiAlias = false;

  @override
  void render(ui.Canvas canvas) {
    final double size = _grass.size.width / _grass.pixelsPerUnit;
    final grassMesh = _grass.mesh as SimpleMesh;

    // Get the visible area in world space.
    ui.Rect bounds = canvas.getLocalClipBounds();

    // Fallback if the clip bounds are missing or practically infinite (no clip).
    if (bounds.width > 10000 || bounds.isEmpty) {
      final camera = game.cameras.main;
      final camPos =
          camera.gameObject.tryGetComponent<ObjectTransform>()?.position ??
          Vector2.zero();
      final halfHeight = camera.orthographicSize;
      final screenSize = game.screen.screenSize;
      final aspect = screenSize.height > 0
          ? screenSize.width / screenSize.height
          : 1.0;
      final halfWidth = halfHeight * aspect;

      bounds = ui.Rect.fromLTWH(
        camPos.x - halfWidth,
        camPos.y - halfHeight,
        halfWidth * 2,
        halfHeight * 2,
      );
    }

    final int startX = (bounds.left / size).floor() - 2;
    final int enx = (bounds.right / size).ceil() + 2;
    final int startY = (bounds.top / size).floor() - 2;
    final int eny = (bounds.bottom / size).ceil() + 2;

    canvas.save();
    // Flip the canvas for the entire background.
    canvas.scale(1, -1);

    // 1. Minimap Optimization
    // In secondary passes (like the minimap), drawing thousands of tiles is overkill.
    // We just draw a single representative color for the whole visible area.
    if (game.getSystem<CameraSystem>()?.isSecondaryPass ?? false) {
      canvas.drawRect(
        ui.Rect.fromLTRB(
          startX * size,
          -(eny * size + size),
          (enx + 1) * size,
          -(startY * size),
        ),
        ui.Paint()..color = const Color(0xFF354c26),
      );
      canvas.restore();
      return;
    }

    // 2. Main Pass Rendering
    for (int y = startY; y <= eny; y++) {
      for (int x = startX; x <= enx; x++) {
        // Draw grass
        canvas.drawImageRect(
          grassMesh.texture.image,
          grassMesh.srcRect!,
          ui.Rect.fromLTWH(x * size, -(y * size + size), size, size),
          _paint,
        );

        // Draw deco (Random details)
        final h = _hash(x, y);
        if (h % 10 == 0) {
          final decoMesh = _sheet[(0, 3 + (h % 6))].mesh as SimpleMesh;
          canvas.drawImageRect(
            decoMesh.texture.image,
            decoMesh.srcRect!,
            ui.Rect.fromLTWH(x * size, -(y * size + size), size, size),
            _paint,
          );
        }
      }
    }
    canvas.restore();
  }
}

// --- UI Components ---

class InstructionsUI extends StatefulGameWidget {
  const InstructionsUI({super.key, super.layer, super.tag});
  @override
  GameState<InstructionsUI> createState() => InstructionsState();
}

class InstructionsState extends GameState<InstructionsUI> {
  @override
  void initState() {
    super.initState();
    addComponent(ScreenTransform());
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: const Text(
          'W (thrust) - A (rotate) - D (rotate) - Space (shoot)',
          style: TextStyle(
            fontSize: 48,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class MinimapUI extends StatefulGameWidget {
  const MinimapUI({super.key, super.layer, super.tag});
  @override
  GameState<MinimapUI> createState() => MinimapState();
}

class MinimapState extends GameState<MinimapUI> {
  @override
  void initState() {
    super.initState();
    addComponent(ScreenTransform());
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          width: 150,
          height: 150,
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 2),
          ),
          decoration: const BoxDecoration(color: Colors.black87),
          child: const CameraView(cameraTag: 'MinimapCamera'),
        ),
      ),
    );
  }
}

class BattleWorldProvider extends InheritedWidget {
  final BattleWorldState world;
  const BattleWorldProvider({
    super.key,
    required this.world,
    required super.child,
  });
  @override
  bool updateShouldNotify(BattleWorldProvider oldWidget) =>
      world != oldWidget.world;
  static BattleWorldState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BattleWorldProvider>()!.world;
}

class FPSUI extends StatefulGameWidget {
  const FPSUI({super.key, super.layer, super.tag});
  @override
  GameState<FPSUI> createState() => FPSState();
}

class FPSState extends GameState<FPSUI> with Tickable {
  double _fps = 0;
  double _timer = 0;

  @override
  void initState() {
    super.initState();
    addComponent(ScreenTransform());
  }

  @override
  void onUpdate(double dt) {
    _timer += dt;
    if (dt > 0) {
      _fps = _fps * 0.9 + (1.0 / dt) * 0.1;
    }

    // Only rebuild the FPS UI twice per second to save performance.
    if (_timer >= 0.5) {
      _timer = 0;
      if (mounted) setState(() {});
    }
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'FPS: ${_fps.round()}',
          style: const TextStyle(
            fontSize: 36,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class MuteUI extends StatefulGameWidget {
  const MuteUI({super.key, super.layer, super.tag});
  @override
  GameState<MuteUI> createState() => MuteState();
}

class MuteState extends GameState<MuteUI> {
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    addComponent(ScreenTransform());
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Material(
          color: Colors.transparent,
          child: IconButton(
            icon: Icon(
              _muted ? Icons.volume_off : Icons.volume_up,
              color: Colors.black,
              size: 48,
            ),
            onPressed: () {
              setState(() {
                _muted = !_muted;
                game.getSystem<AudioSystem>()?.globalVolume = _muted
                    ? 0.0
                    : 1.0;
              });
            },
          ),
        ),
      ),
    );
  }
}
