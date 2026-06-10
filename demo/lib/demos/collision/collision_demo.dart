import 'dart:math';

import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/data/renderer/data.dart';
import 'package:goo2d/src/data/renderer/system.dart';
import 'package:goo2d/src/data/transform/system.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kWorldHeight  = 20.0;
const _kBallRadius   = 0.3;
const _kZoneY        = 0.0;
const _kZoneW        = 14.0;
const _kZoneH        = 2.0;
const _kSpawnY       = 9.5;
const _kSpawnXSpread = 6.0;
const _kGravity      = 9.8;
const _kMaxBalls     = 200;
const _kDefaultSpawn = 15.0;
const _kRemoveY      = -12.0;

final _rng = Random();

double _randRange(double lo, double hi) => lo + _rng.nextDouble() * (hi - lo);

Color _randomColor() =>
    HSVColor.fromAHSV(1.0, _rng.nextDouble() * 360.0, 0.9, 1.0).toColor();

// ---------------------------------------------------------------------------
// ECS — data
// ---------------------------------------------------------------------------

class _BallData extends EntityData {
  late final Field<int>    originalColor;
  late final Field<double> vx, vy;

  @override
  void describe(DataDescriptor d) {
    originalColor = d.newUint32();
    vx = d.newFloat32();
    vy = d.newFloat32();
  }
}

class _ZoneTag extends EntityData {
  @override
  void describe(DataDescriptor d) {}
}

// ---------------------------------------------------------------------------
// ECS — spawn system
// ---------------------------------------------------------------------------

class _BallSpawnSystem extends WorldSystem with Tickable {
  final ValueNotifier<double> spawnRate;
  double _acc = 0;

  _BallSpawnSystem(this.spawnRate);

  late final _bd = define(_BallData.new);

  @override
  void onUpdate(double dt) {
    _acc += spawnRate.value * dt;
    var n = _acc.floor();
    if (n <= 0) return;
    _acc -= n;

    final existing = (world.query()..withAll(_bd)).count();
    n = n.clamp(0, _kMaxBalls - existing);
    if (n <= 0) return;

    for (var i = 0; i < n; i++) {
      final color = _randomColor();
      world.commandBuffer.createEntityAll([
        TransformData.new.withInit((d, r) {
          d.x.set(r, _randRange(-_kSpawnXSpread, _kSpawnXSpread));
          d.y.set(r, _kSpawnY);
        }),
        ColliderData.new.withInit((d, r) {
          d.shapeType.set(r, ColliderShapeType.circle);
          d.radius.set(r, _kBallRadius);
        }),
        RenderData.new.withInit((d, r) {
          d.size.set(r, const Size(_kBallRadius * 2, _kBallRadius * 2));
          d.color.set(r, color);
        }),
        _BallData.new.withInit((d, r) {
          d.originalColor.set(r, color.toARGB32());
          d.vy.set(r, -2.0);
        }),
      ]);
    }
  }
}

// ---------------------------------------------------------------------------
// ECS — gravity system
// ---------------------------------------------------------------------------

class _GravitySystem extends WorldSystem with Tickable {
  late final _bd = define(_BallData.new);
  late final _td = define(TransformData.new);

  @override
  void onUpdate(double dt) {
    (world.query()..withAll(_bd, _td)).withEntity().forEach((r) {
      final s = r.entity.index;
      final vy = _bd.vy.getSlot(s) - _kGravity * dt;
      _bd.vy.setSlot(s, vy);
      _td.x.setSlot(s, _td.x.getSlot(s) + _bd.vx.getSlot(s) * dt);
      _td.y.setSlot(s, _td.y.getSlot(s) + vy * dt);
    });
  }
}

// ---------------------------------------------------------------------------
// ECS — color system
// ---------------------------------------------------------------------------

class _ColorSystem extends WorldSystem
    with EventListener, Tickable, PhysicsContactListener<Entity> {
  late final _bd = define(_BallData.new);
  late final _rd = define(RenderData.new);

  final Set<int> _ballSlots = {};

  @override
  void onUpdate(double dt) {
    _ballSlots.clear();
    (world.query()..withAll(_bd)).withEntity().forEach((r) {
      _ballSlots.add(r.entity.index);
    });
  }

  @override
  Future<void> onOverlapEnter(PhysicsOverlap<Entity> e) async {
    _applyHighlight(e.trigger.index, e.other.index);
  }

  @override
  Future<void> onOverlapExit(PhysicsOverlap<Entity> e) async {
    _restoreColor(e.trigger.index);
    _restoreColor(e.other.index);
  }

  void _applyHighlight(int slotA, int slotB) {
    final aIsBall = _ballSlots.contains(slotA);
    final bIsBall = _ballSlots.contains(slotB);
    if (aIsBall && !bIsBall) _rd.color.setSlot(slotA, Colors.white);
    if (bIsBall && !aIsBall) _rd.color.setSlot(slotB, Colors.white);
  }

  void _restoreColor(int slot) {
    if (!_ballSlots.contains(slot)) return;
    _rd.color.setSlot(slot, Color(_bd.originalColor.getSlot(slot)));
  }
}

// ---------------------------------------------------------------------------
// ECS — cleanup system
// ---------------------------------------------------------------------------

class _EcsCleanupSystem extends WorldSystem with FixedTickable {
  late final _bd = define(_BallData.new);
  late final _td = define(TransformData.new);

  @override
  Future<void> onFixedUpdate(double dt) async {
    (world.query()..withAll(_bd, _td)).withEntity().forEach((r) {
      final s = r.entity.index;
      if (_td.y.getSlot(s) < _kRemoveY) {
        world.commandBuffer.removeEntity(r.entity);
      }
    });
  }
}

// ---------------------------------------------------------------------------
// ECS — zone render system
// ---------------------------------------------------------------------------

class _ZoneRenderSystem extends WorldSystem with Renderable {
  @override
  void render(Canvas canvas) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: _kZoneW,
      height: _kZoneH,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white.withAlpha(8)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white.withAlpha(40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.05,
    );
  }
}

// ---------------------------------------------------------------------------
// ECS — stats system
// ---------------------------------------------------------------------------

class _EcsStatsSystem extends WorldSystem with Tickable {
  final ValueNotifier<int> count;
  final ValueNotifier<double> fpsNotifier;

  _EcsStatsSystem(this.count, this.fpsNotifier);

  late final _bd = define(_BallData.new);
  double _elapsed = 0;

  @override
  void onUpdate(double dt) {
    _elapsed += dt;
    if (_elapsed < 0.25) return;
    _elapsed = 0;
    count.value = (world.query()..withAll(_bd)).count();
    fpsNotifier.value = fps.toDouble();
  }
}

// ---------------------------------------------------------------------------
// ECS — camera scene
// ---------------------------------------------------------------------------

class _EcsCameraScene extends StatefulGameWidget {
  final WorldController world;
  const _EcsCameraScene(this.world);

  @override
  GameState<_EcsCameraScene> createState() => _EcsCameraSceneState();
}

class _EcsCameraSceneState extends GameState<_EcsCameraScene> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues(
            (c) => c.orthographicSize = _kWorldHeight / 2,
          ),
        ),
      ],
    );
    yield World(widget.world);
  }
}

// ---------------------------------------------------------------------------
// ECS tab
// ---------------------------------------------------------------------------

class _EcsCollisionTab extends StatefulWidget {
  const _EcsCollisionTab();

  @override
  State<_EcsCollisionTab> createState() => _EcsCollisionTabState();
}

class _EcsCollisionTabState extends State<_EcsCollisionTab> {
  GameEngine? _engine;
  bool _disposed = false;
  late final WorldController _world;
  final _count = ValueNotifier<int>(0);
  final _fps = ValueNotifier<double>(0);
  final _spawnRate = ValueNotifier<double>(_kDefaultSpawn);

  @override
  void initState() {
    super.initState();
    GameEngine.create({
      TickerState.new,
      CollisionSystem.new,
      CameraSystem.new,
      ScreenSystem.new,
    }).then((engine) {
      if (_disposed) {
        engine.dispose();
        return;
      }
      setState(() => _engine = engine);
    });

    _world = WorldController();
    _world.addSystem(_BallSpawnSystem(_spawnRate));
    _world.addSystem(_GravitySystem());
    _world.addSystem(CollisionWorldSystem());
    _world.addSystem(_ColorSystem());
    _world.addSystem(TransformSystem());
    _world.addSystem(_EcsCleanupSystem());
    _world.addSystem(_ZoneRenderSystem());
    _world.addSystem(RenderSystem(const []));
    _world.addSystem(_EcsStatsSystem(_count, _fps));

    _world.commandBuffer.createEntityAll([
      TransformData.new.withInit((d, r) => d.y.set(r, _kZoneY)),
      ColliderData.new.withInit((d, r) {
        d.shapeType.set(r, ColliderShapeType.box);
        d.width.set(r, _kZoneW);
        d.height.set(r, _kZoneH);
      }),
      _ZoneTag.new,
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    _engine?.dispose();
    _world.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    if (engine == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        Game(engine: engine, child: _EcsCameraScene(_world)),
        _StatsChip(count: _count, fps: _fps),
        _SpawnRateSlider(spawnRate: _spawnRate),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// EC — components
// ---------------------------------------------------------------------------

class _ZoneMarker extends Component {}

class _BallRenderer extends Behavior with Renderable {
  final Color originalColor;
  Color displayColor;

  _BallRenderer(this.originalColor) : displayColor = originalColor;

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(
      Offset.zero,
      _kBallRadius,
      Paint()..color = displayColor,
    );
  }
}

class _ZoneRenderer extends Behavior with Renderable {
  @override
  void render(Canvas canvas) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: _kZoneW,
      height: _kZoneH,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white.withAlpha(8)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white.withAlpha(40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.05,
    );
  }
}

class _BallBehavior extends Behavior
    with Tickable, LifecycleListener, PhysicsContactListener<Collider> {
  double _vy = -2.0;
  late ObjectTransform _t;
  late _BallRenderer _r;
  final VoidCallback onOffScreen;

  _BallBehavior({required this.onOffScreen});

  @override
  void onMounted() {
    _t = gameObject.getComponent<ObjectTransform>();
    _r = gameObject.getComponent<_BallRenderer>();
  }

  @override
  void onUpdate(double dt) {
    _vy -= _kGravity * dt;
    _t.localPosition = _t.localPosition + Vector2(0, _vy * dt);
    if (_t.localPosition.y < _kRemoveY) onOffScreen();
  }

  @override
  Future<void> onOverlapEnter(PhysicsOverlap<Collider> e) async {
    if (e.other.gameObject.tryGetComponent<_ZoneMarker>() != null) {
      _r.displayColor = Colors.white;
    }
  }

  @override
  Future<void> onOverlapExit(PhysicsOverlap<Collider> e) async {
    if (e.other.gameObject.tryGetComponent<_ZoneMarker>() != null) {
      _r.displayColor = _r.originalColor;
    }
  }
}

// ---------------------------------------------------------------------------
// EC — scene
// ---------------------------------------------------------------------------

class _EcCollisionScene extends StatefulGameWidget {
  final ValueNotifier<double> spawnRate;
  final ValueNotifier<int> count;
  final ValueNotifier<double> fpsNotifier;

  const _EcCollisionScene({
    required this.spawnRate,
    required this.count,
    required this.fpsNotifier,
  });

  @override
  GameState<_EcCollisionScene> createState() => _EcCollisionSceneState();
}

class _EcCollisionSceneState extends GameState<_EcCollisionScene>
    with Tickable {
  final List<Widget> _balls = [];
  double _acc = 0;
  double _ema = 0;
  double _elapsed = 0;
  int _nextId = 0;

  void _removeBall(int id) {
    setState(() => _balls.removeWhere((w) => w.key == ValueKey(id)));
  }

  void _spawnBall() {
    final id = _nextId++;
    final color = _randomColor();
    _balls.add(
      GameObjectWidget(
        key: ValueKey(id),
        children: [
          ComponentWidget(
            ObjectTransform.new.withInitialValues(
              (c) => c.position = Vector2(
                _randRange(-_kSpawnXSpread, _kSpawnXSpread),
                _kSpawnY,
              ),
            ),
          ),
          ComponentWidget(
            CircleCollider.new.withInitialValues(
              (c) => c.radius = _kBallRadius,
            ),
          ),
          ComponentWidget(() => _BallRenderer(color)),
          ComponentWidget(() => _BallBehavior(onOffScreen: () => _removeBall(id))),
        ],
      ),
    );
  }

  @override
  void onUpdate(double dt) {
    _ema = _ema * 0.9 + (1.0 / dt) * 0.1;
    _elapsed += dt;

    _acc += widget.spawnRate.value * dt;
    var n = _acc.floor();
    if (n > 0) {
      _acc -= n;
      n = n.clamp(0, _kMaxBalls - _balls.length);
      if (n > 0) {
        setState(() {
          for (var i = 0; i < n; i++) {
            _spawnBall();
          }
        });
      }
    }

    if (_elapsed >= 0.25) {
      widget.count.value = _balls.length;
      widget.fpsNotifier.value = _ema;
      _elapsed = 0;
    }
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues(
            (c) => c.orthographicSize = _kWorldHeight / 2,
          ),
        ),
      ],
    );
    yield GameObjectWidget(
      children: [
        ComponentWidget(
          ObjectTransform.new.withInitialValues(
            (c) => c.position = Vector2(0, _kZoneY),
          ),
        ),
        ComponentWidget(
          BoxCollider.new.withInitialValues(
            (c) => c.size = Vector2(_kZoneW, _kZoneH),
          ),
        ),
        ComponentWidget(_ZoneMarker.new),
        ComponentWidget(_ZoneRenderer.new),
      ],
    );
    yield* _balls;
  }
}

// ---------------------------------------------------------------------------
// EC tab
// ---------------------------------------------------------------------------

class _EcCollisionTab extends StatefulWidget {
  const _EcCollisionTab();

  @override
  State<_EcCollisionTab> createState() => _EcCollisionTabState();
}

class _EcCollisionTabState extends State<_EcCollisionTab> {
  GameEngine? _engine;
  bool _disposed = false;
  final _count = ValueNotifier<int>(0);
  final _fps = ValueNotifier<double>(0);
  final _spawnRate = ValueNotifier<double>(_kDefaultSpawn);

  @override
  void initState() {
    super.initState();
    GameEngine.create({
      TickerState.new,
      CollisionSystem.new,
      CameraSystem.new,
      ScreenSystem.new,
    }).then((engine) {
      if (_disposed) {
        engine.dispose();
        return;
      }
      setState(() => _engine = engine);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    if (engine == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        Game(
          engine: engine,
          child: _EcCollisionScene(
            spawnRate: _spawnRate,
            count: _count,
            fpsNotifier: _fps,
          ),
        ),
        _StatsChip(count: _count, fps: _fps),
        _SpawnRateSlider(spawnRate: _spawnRate),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared UI — stats chip
// ---------------------------------------------------------------------------

class _StatsChip extends StatelessWidget {
  final ValueNotifier<int> count;
  final ValueNotifier<double> fps;

  const _StatsChip({required this.count, required this.fps});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([count, fps]),
          builder: (_, _) => Text(
            'balls: ${count.value}   fps: ${fps.value.toStringAsFixed(1)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared UI — spawn rate slider
// ---------------------------------------------------------------------------

class _SpawnRateSlider extends StatelessWidget {
  final ValueNotifier<double> spawnRate;

  const _SpawnRateSlider({required this.spawnRate});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: Colors.black54,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            const Text(
              'Spawn rate',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: spawnRate,
                builder: (_, v, _) => Slider(
                  value: v,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${v.round()}/s',
                  onChanged: (val) => spawnRate.value = val,
                ),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: spawnRate,
              builder: (_, v, _) => SizedBox(
                width: 52,
                child: Text(
                  '${v.round()}/s',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top-level demo widget
// ---------------------------------------------------------------------------

class CollisionDemo extends StatefulWidget {
  const CollisionDemo({super.key});

  @override
  State<CollisionDemo> createState() => _CollisionDemoState();
}

class _CollisionDemoState extends State<CollisionDemo> {
  int _mode = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Data-Oriented')),
              ButtonSegment(value: 1, label: Text('GameObject + Component')),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          ),
        ),
        Expanded(
          child: ClipRect(
            child: _mode == 0
                ? const _EcsCollisionTab()
                : const _EcCollisionTab(),
          ),
        ),
      ],
    );
  }
}
