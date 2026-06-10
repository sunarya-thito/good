import 'dart:io' show ProcessInfo;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/data/renderer/data.dart';
import 'package:goo2d/src/data/renderer/system.dart';
import 'package:goo2d/src/data/transform/system.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kWorldHeight = 20.0;
const _kMaxBalls = 300;
const _kDefaultSpawn = 20.0;
const _kSpawnY = 9.0;
const _kSpawnXSpread = 1.5;
const _kPlatformY = -9.0;
const _kPlatformW = 12.0;
const _kPlatformH = 0.4;
const _kBallRadius = 0.25;
const _kRemoveY = -12.0;
const _kRemoveX = 15.0;
const _kHistoryLen = 60;

final _rng = Random();

double _randRange(double lo, double hi) => lo + _rng.nextDouble() * (hi - lo);

Color _randomColor() {
  final hue = _rng.nextDouble() * 360.0;
  return HSVColor.fromAHSV(1.0, hue, 0.9, 1.0).toColor();
}

int _getMemoryMb() => kIsWeb ? 0 : ProcessInfo.currentRss ~/ (1024 * 1024);

class _Counter {
  int value = 0;
}

// ---------------------------------------------------------------------------
// ECS — ball marker tag
// ---------------------------------------------------------------------------

class _BallTag extends EntityData {
  @override
  void describe(DataDescriptor d) {}
}

// ---------------------------------------------------------------------------
// ECS — spawn system
// ---------------------------------------------------------------------------

class _BallSpawnSystem extends WorldSystem with Tickable {
  final ValueNotifier<double> spawnRate;
  final _Counter spawnAcc;
  double _acc = 0;

  _BallSpawnSystem(this.spawnRate, this.spawnAcc);

  late final _bt = define(_BallTag.new);

  @override
  void onUpdate(double dt) {
    _acc += spawnRate.value * dt;
    var n = _acc.floor();
    if (n <= 0) return;
    _acc -= n;

    final existing = (world.query()..withAll(_bt)).count();
    final available = _kMaxBalls - existing;
    if (available <= 0) return;
    n = n.clamp(0, available);
    if (n <= 0) return;

    spawnAcc.value += n;

    for (var i = 0; i < n; i++) {
      final color = _randomColor();
      world.commandBuffer.createEntityAll([
        TransformData.new.withInit((d, r) {
          d.x.set(r, _randRange(-_kSpawnXSpread, _kSpawnXSpread));
          d.y.set(r, _kSpawnY);
        }),
        WorldTransformData.new,
        RigidbodyData.new,
        ColliderData.new.withInit((d, r) {
          d.shapeType.set(r, ColliderShapeType.circle);
          d.radius.set(r, _kBallRadius);
          d.bounciness.set(r, 0.4);
          d.friction.set(r, 0.3);
        }),
        RenderData.new.withInit((d, r) {
          d.size.set(r, const Size(_kBallRadius * 2, _kBallRadius * 2));
          d.color.set(r, color);
        }),
        _BallTag.new,
      ]);
    }
  }
}

// ---------------------------------------------------------------------------
// ECS — cleanup system
// ---------------------------------------------------------------------------

// FixedTickable (not Tickable) so cleanup only runs once per physics tick, avoiding
// duplicate removeEntity commands that would occur if a regular tick fires while a
// fixed tick is suspended at an isolate await and _iterating > 0 blocks the flush.
class _CleanupSystem extends WorldSystem with FixedTickable {
  final _Counter despawnAcc;

  _CleanupSystem(this.despawnAcc);

  late final _bt = define(_BallTag.new);
  late final _td = define(TransformData.new);

  @override
  Future<void> onFixedUpdate(double dt) async {
    (world.query()..withAll(_bt, _td)).withEntity().forEach((r) {
      final x = _td.x.get(r);
      final y = _td.y.get(r);
      if (y < _kRemoveY || x.abs() > _kRemoveX) {
        despawnAcc.value++;
        world.commandBuffer.removeEntity(r.entity);
      }
    });
  }
}

// ---------------------------------------------------------------------------
// ECS — stats system
// ---------------------------------------------------------------------------
double get _fps => fps.toDouble();

class _PhysicsStatsSystem extends WorldSystem with Tickable {
  final ValueNotifier<int> count;
  final ValueNotifier<double> fps;
  final ValueNotifier<List<double>> fpsHistory;
  final ValueNotifier<int> memoryMb;
  final ValueNotifier<List<double>> memHistory;
  final ValueNotifier<List<double>> countHistory;
  final ValueNotifier<double> spawnRateStat;
  final ValueNotifier<double> despawnRateStat;
  final ValueNotifier<List<double>> spawnRateHistory;
  final ValueNotifier<List<double>> despawnRateHistory;
  final _Counter spawnAcc;
  final _Counter despawnAcc;

  _PhysicsStatsSystem(
    this.count,
    this.fps,
    this.fpsHistory,
    this.memoryMb,
    this.memHistory,
    this.countHistory,
    this.spawnRateStat,
    this.despawnRateStat,
    this.spawnRateHistory,
    this.despawnRateHistory,
    this.spawnAcc,
    this.despawnAcc,
  );

  late final _bt = define(_BallTag.new);

  double _elapsed = 0;

  @override
  void onUpdate(double dt) {
    _elapsed += dt;
    if (_elapsed < 0.25) return;

    final sr = spawnAcc.value / _elapsed;
    final dr = despawnAcc.value / _elapsed;
    spawnAcc.value = 0;
    despawnAcc.value = 0;
    spawnRateStat.value = sr;
    despawnRateStat.value = dr;
    _elapsed = 0;

    count.value = (world.query()..withAll(_bt)).count();
    fps.value = _fps;

    void push(ValueNotifier<List<double>> n, double v) {
      final h = List<double>.from(n.value)..add(v);
      if (h.length > _kHistoryLen) h.removeAt(0);
      n.value = h;
    }

    push(fpsHistory, _fps);
    push(memHistory, _getMemoryMb().toDouble());
    push(countHistory, count.value.toDouble());
    push(spawnRateHistory, sr);
    push(despawnRateHistory, dr);

    memoryMb.value = _getMemoryMb();
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

class _EcsPhysicsTab extends StatefulWidget {
  const _EcsPhysicsTab();

  @override
  State<_EcsPhysicsTab> createState() => _EcsPhysicsTabState();
}

class _EcsPhysicsTabState extends State<_EcsPhysicsTab> {
  GameEngine? _engine;
  bool _disposed = false;
  late final WorldController _world;
  final _count = ValueNotifier<int>(0);
  final _fps = ValueNotifier<double>(0);
  final _fpsHistory = ValueNotifier<List<double>>([]);
  final _memoryMb = ValueNotifier<int>(0);
  final _memHistory = ValueNotifier<List<double>>([]);
  final _countHistory = ValueNotifier<List<double>>([]);
  final _spawnRateStat = ValueNotifier<double>(0);
  final _despawnRateStat = ValueNotifier<double>(0);
  final _spawnRateHistory = ValueNotifier<List<double>>([]);
  final _despawnRateHistory = ValueNotifier<List<double>>([]);
  final _spawnRate = ValueNotifier<double>(_kDefaultSpawn);

  @override
  void initState() {
    super.initState();
    GameEngine.create({
      TickerSystem.new,
      InputSystem.new,
      PhysicsSystem.new,
      CameraSystem.new,
      ScreenSystem.new,
      ScreenPhysicsSystem.new,
    }).then((engine) {
      if (_disposed) {
        engine.dispose();
        return;
      }
      setState(() => _engine = engine);
    });
    final spawnAcc = _Counter();
    final despawnAcc = _Counter();
    _world = WorldController();
    _world.addSystem(_BallSpawnSystem(_spawnRate, spawnAcc));
    _world.addSystem(PhysicsWorldSystem());
    _world.addSystem(TransformSystem());
    _world.addSystem(_CleanupSystem(despawnAcc));
    _world.addSystem(
      _PhysicsStatsSystem(
        _count,
        _fps,
        _fpsHistory,
        _memoryMb,
        _memHistory,
        _countHistory,
        _spawnRateStat,
        _despawnRateStat,
        _spawnRateHistory,
        _despawnRateHistory,
        spawnAcc,
        despawnAcc,
      ),
    );
    _world.addSystem(RenderSystem(const []));

    // Platform entity — static body, wide box collider, no _BallTag so cleanup skips it.
    _world.commandBuffer.createEntityAll([
      TransformData.new.withInit((d, r) {
        d.x.set(r, 0.0);
        d.y.set(r, _kPlatformY);
      }),
      WorldTransformData.new,
      RigidbodyData.new.withInit((d, r) {
        d.bodyType.set(r, RigidbodyType.static);
      }),
      ColliderData.new.withInit((d, r) {
        d.shapeType.set(r, ColliderShapeType.box);
        d.width.set(r, _kPlatformW);
        d.height.set(r, _kPlatformH);
        d.friction.set(r, 0.5);
        d.bounciness.set(r, 0.3);
      }),
      RenderData.new.withInit((d, r) {
        d.size.set(r, const Size(_kPlatformW, _kPlatformH));
        d.color.set(r, Colors.grey);
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    if (engine == null) return const Center(child: CircularProgressIndicator());
    return Stack(
      children: [
        Game(engine: engine, child: _EcsCameraScene(_world)),
        _StatsOverlay(
          count: _count,
          fps: _fps,
          fpsHistory: _fpsHistory,
          memoryMb: _memoryMb,
          memHistory: _memHistory,
          countHistory: _countHistory,
          spawnRateStat: _spawnRateStat,
          despawnRateStat: _despawnRateStat,
          spawnRateHistory: _spawnRateHistory,
          despawnRateHistory: _despawnRateHistory,
        ),
        _SpawnRateSlider(spawnRate: _spawnRate),
      ],
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _engine?.dispose();
    _world.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// EC — platform renderer
// ---------------------------------------------------------------------------

class _PlatformRenderer extends Behavior with Renderable {
  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: _kPlatformW,
        height: _kPlatformH,
      ),
      Paint()..color = Colors.grey,
    );
  }
}

// ---------------------------------------------------------------------------
// EC — ball renderer
// ---------------------------------------------------------------------------

class _BallRenderer extends Behavior with Renderable {
  final Color color;
  _BallRenderer(this.color);

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(Offset.zero, _kBallRadius, Paint()..color = color);
  }
}

// ---------------------------------------------------------------------------
// EC — ball behavior (off-screen detection)
// ---------------------------------------------------------------------------

class _BallBehavior extends Behavior with Tickable, LifecycleListener {
  final VoidCallback onOffScreen;
  bool _gone = false;

  late ObjectTransform _transform;

  _BallBehavior({required this.onOffScreen});

  @override
  void onMounted() {
    _transform = gameObject.getComponent<ObjectTransform>();
  }

  @override
  void onUpdate(double dt) {
    if (_gone) return;
    final pos = _transform.position;
    if (pos.y < _kRemoveY || pos.x.abs() > _kRemoveX) {
      _gone = true;
      onOffScreen();
    }
  }
}

// ---------------------------------------------------------------------------
// EC — physics scene
// ---------------------------------------------------------------------------

class _EcPhysicsScene extends StatefulGameWidget {
  final ValueNotifier<double> spawnRate;
  final void Function(
    int count,
    double fps,
    double spawnRate,
    double despawnRate,
  )
  onStats;

  const _EcPhysicsScene({required this.spawnRate, required this.onStats});

  @override
  GameState<_EcPhysicsScene> createState() => _EcPhysicsSceneState();
}

class _EcPhysicsSceneState extends GameState<_EcPhysicsScene> with Tickable {
  final List<Widget> _balls = [];
  double _spawnAcc = 0;
  double _ema = 0;
  double _elapsed = 0;
  int _nextId = 0;
  int _spawnCount = 0;
  int _despawnCount = 0;

  void _removeBall(int id) {
    _despawnCount++;
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
          ComponentWidget(Rigidbody.new),
          ComponentWidget(
            CircleCollider.new.withInitialValues(
              (c) => c
                ..radius = _kBallRadius
                ..bounciness = 0.4
                ..friction = 0.3,
            ),
          ),
          ComponentWidget(() => _BallRenderer(color)),
          ComponentWidget(
            () => _BallBehavior(onOffScreen: () => _removeBall(id)),
          ),
        ],
      ),
    );
  }

  @override
  void onUpdate(double dt) {
    _ema = _ema * 0.9 + (1.0 / dt) * 0.1;
    _elapsed += dt;

    _spawnAcc += widget.spawnRate.value * dt;
    var n = _spawnAcc.floor();
    if (n > 0) {
      _spawnAcc -= n;
      n = n.clamp(0, _kMaxBalls - _balls.length);
      if (n > 0) {
        _spawnCount += n;
        setState(() {
          for (var i = 0; i < n; i++) {
            _spawnBall();
          }
        });
      }
    }

    if (_elapsed >= 0.25) {
      final sr = _spawnCount / _elapsed;
      final dr = _despawnCount / _elapsed;
      _spawnCount = 0;
      _despawnCount = 0;
      _elapsed = 0;
      widget.onStats(_balls.length, _ema, sr, dr);
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
    // Static platform
    yield GameObjectWidget(
      children: [
        ComponentWidget(
          ObjectTransform.new.withInitialValues(
            (c) => c.position = Vector2(0, _kPlatformY),
          ),
        ),
        ComponentWidget(
          Rigidbody.new.withInitialValues(
            (c) => c.bodyType = RigidbodyType.static,
          ),
        ),
        ComponentWidget(
          BoxCollider.new.withInitialValues(
            (c) => c
              ..size = Vector2(_kPlatformW, _kPlatformH)
              ..friction = 0.5
              ..bounciness = 0.3,
          ),
        ),
        ComponentWidget(_PlatformRenderer.new),
      ],
    );
    yield* _balls;
  }
}

// ---------------------------------------------------------------------------
// EC tab
// ---------------------------------------------------------------------------

class _EcPhysicsTab extends StatefulWidget {
  const _EcPhysicsTab();

  @override
  State<_EcPhysicsTab> createState() => _EcPhysicsTabState();
}

class _EcPhysicsTabState extends State<_EcPhysicsTab> {
  GameEngine? _engine;
  bool _disposed = false;
  final _count = ValueNotifier<int>(0);
  final _fps = ValueNotifier<double>(0);
  final _fpsHistory = ValueNotifier<List<double>>([]);
  final _memoryMb = ValueNotifier<int>(0);
  final _memHistory = ValueNotifier<List<double>>([]);
  final _countHistory = ValueNotifier<List<double>>([]);
  final _spawnRateStat = ValueNotifier<double>(0);
  final _despawnRateStat = ValueNotifier<double>(0);
  final _spawnRateHistory = ValueNotifier<List<double>>([]);
  final _despawnRateHistory = ValueNotifier<List<double>>([]);
  final _spawnRate = ValueNotifier<double>(_kDefaultSpawn);

  @override
  void initState() {
    super.initState();
    GameEngine.create({
      TickerSystem.new,
      InputSystem.new,
      PhysicsSystem.new,
      CameraSystem.new,
      ScreenSystem.new,
      ScreenPhysicsSystem.new,
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

  void _push(ValueNotifier<List<double>> n, double v) {
    final h = List<double>.from(n.value)..add(v);
    if (h.length > _kHistoryLen) h.removeAt(0);
    n.value = h;
  }

  void _onStats(int count, double fps, double spawnRate, double despawnRate) {
    _count.value = count;
    _fps.value = fps;
    _spawnRateStat.value = spawnRate;
    _despawnRateStat.value = despawnRate;
    _memoryMb.value = _getMemoryMb();

    _push(_fpsHistory, fps);
    _push(_memHistory, _getMemoryMb().toDouble());
    _push(_countHistory, count.toDouble());
    _push(_spawnRateHistory, spawnRate);
    _push(_despawnRateHistory, despawnRate);
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    if (engine == null) return const Center(child: CircularProgressIndicator());
    return Stack(
      children: [
        Game(
          engine: engine,
          child: _EcPhysicsScene(spawnRate: _spawnRate, onStats: _onStats),
        ),
        _StatsOverlay(
          count: _count,
          fps: _fps,
          fpsHistory: _fpsHistory,
          memoryMb: _memoryMb,
          memHistory: _memHistory,
          countHistory: _countHistory,
          spawnRateStat: _spawnRateStat,
          despawnRateStat: _despawnRateStat,
          spawnRateHistory: _spawnRateHistory,
          despawnRateHistory: _despawnRateHistory,
        ),
        _SpawnRateSlider(spawnRate: _spawnRate),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared UI — metrics chart painter
// ---------------------------------------------------------------------------

class _MetricsChartPainter extends CustomPainter {
  final List<double> fpsSamples;
  final List<double> memSamples;
  final List<double> countSamples;
  final List<double> spawnRateSamples;
  final List<double> despawnRateSamples;
  final double currentFps;
  final int currentMem;
  final int currentCount;
  final double spawnRate;
  final double despawnRate;

  _MetricsChartPainter({
    required this.fpsSamples,
    required this.memSamples,
    required this.countSamples,
    required this.spawnRateSamples,
    required this.despawnRateSamples,
    required this.currentFps,
    required this.currentMem,
    required this.currentCount,
    required this.spawnRate,
    required this.despawnRate,
  });

  void _drawLine(
    Canvas canvas,
    Rect band,
    List<double> samples,
    double maxVal,
    Color color,
    double? refVal,
  ) {
    if (samples.length < 2) return;
    final step = band.width / (_kHistoryLen - 1);

    if (refVal != null) {
      final yRef =
          band.bottom - (refVal / maxVal).clamp(0.0, 1.0) * band.height;
      canvas.drawLine(
        Offset(band.left, yRef),
        Offset(band.right, yRef),
        Paint()
          ..color = Colors.white24
          ..strokeWidth = 0.5,
      );
    }

    final path = Path();
    final startX = band.left + (_kHistoryLen - samples.length) * step;
    for (var i = 0; i < samples.length; i++) {
      final x = startX + i * step;
      final y =
          band.bottom - (samples[i] / maxVal).clamp(0.0, 1.0) * band.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawLabel(Canvas canvas, Rect band, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          height: 1.2,
          shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: band.width - 4);
    tp.paint(canvas, Offset(band.left + 2, band.top + 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const kGap = 3.0;
    const kBands = 5;
    final bandH = (size.height - kGap * (kBands - 1)) / kBands;
    final w = size.width;

    final bands = List.generate(
      kBands,
      (i) => Rect.fromLTWH(0, i * (bandH + kGap), w, bandH),
    );

    final rateMax =
        [...spawnRateSamples, ...despawnRateSamples].fold(0.0, max) * 1.2;
    final rateScale = rateMax < 10 ? 100.0 : rateMax;

    final countMax = countSamples.isEmpty
        ? _kMaxBalls.toDouble()
        : (countSamples.reduce(max) * 1.2).clamp(10.0, _kMaxBalls.toDouble());
    final memMax = memSamples.isEmpty
        ? 100.0
        : (memSamples.reduce(max) * 1.2).clamp(50.0, double.infinity);

    _drawLine(canvas, bands[0], fpsSamples, 120.0, Colors.greenAccent, 60.0);
    _drawLine(canvas, bands[1], memSamples, memMax, Colors.cyanAccent, null);
    _drawLine(
      canvas,
      bands[2],
      countSamples,
      countMax,
      Colors.orangeAccent,
      null,
    );
    _drawLine(
      canvas,
      bands[3],
      spawnRateSamples,
      rateScale,
      Colors.yellowAccent,
      null,
    );
    _drawLine(
      canvas,
      bands[4],
      despawnRateSamples,
      rateScale,
      Colors.pinkAccent,
      null,
    );

    _drawLabel(
      canvas,
      bands[0],
      'FPS  ${currentFps.toStringAsFixed(1)}',
      Colors.greenAccent,
    );
    _drawLabel(canvas, bands[1], 'MEM  $currentMem MB', Colors.cyanAccent);
    _drawLabel(canvas, bands[2], 'BALLS  $currentCount', Colors.orangeAccent);
    _drawLabel(
      canvas,
      bands[3],
      'SPAWN  ${spawnRate.round()}/s',
      Colors.yellowAccent,
    );
    _drawLabel(
      canvas,
      bands[4],
      'DESPAWN  ${despawnRate.round()}/s',
      Colors.pinkAccent,
    );

    for (var i = 0; i < kBands - 1; i++) {
      final y = bands[i].bottom + kGap / 2;
      canvas.drawLine(
        Offset(0, y),
        Offset(w, y),
        Paint()
          ..color = Colors.white12
          ..strokeWidth = 0.5,
      );
    }
  }

  @override
  bool shouldRepaint(_MetricsChartPainter old) =>
      fpsSamples != old.fpsSamples ||
      memSamples != old.memSamples ||
      countSamples != old.countSamples ||
      spawnRateSamples != old.spawnRateSamples ||
      despawnRateSamples != old.despawnRateSamples;
}

// ---------------------------------------------------------------------------
// Shared UI — stats overlay
// ---------------------------------------------------------------------------

class _StatsOverlay extends StatelessWidget {
  final ValueNotifier<int> count;
  final ValueNotifier<double> fps;
  final ValueNotifier<List<double>> fpsHistory;
  final ValueNotifier<int> memoryMb;
  final ValueNotifier<List<double>> memHistory;
  final ValueNotifier<List<double>> countHistory;
  final ValueNotifier<double> spawnRateStat;
  final ValueNotifier<double> despawnRateStat;
  final ValueNotifier<List<double>> spawnRateHistory;
  final ValueNotifier<List<double>> despawnRateHistory;

  const _StatsOverlay({
    required this.count,
    required this.fps,
    required this.fpsHistory,
    required this.memoryMb,
    required this.memHistory,
    required this.countHistory,
    required this.spawnRateStat,
    required this.despawnRateStat,
    required this.spawnRateHistory,
    required this.despawnRateHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      right: 12,
      child: Container(
        width: 176,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            fpsHistory,
            memHistory,
            countHistory,
            spawnRateHistory,
            despawnRateHistory,
            fps,
            memoryMb,
            count,
            spawnRateStat,
            despawnRateStat,
          ]),
          builder: (_, _) => SizedBox(
            width: 164,
            height: 170,
            child: CustomPaint(
              painter: _MetricsChartPainter(
                fpsSamples: fpsHistory.value,
                memSamples: memHistory.value,
                countSamples: countHistory.value,
                spawnRateSamples: spawnRateHistory.value,
                despawnRateSamples: despawnRateHistory.value,
                currentFps: fps.value,
                currentMem: memoryMb.value,
                currentCount: count.value,
                spawnRate: spawnRateStat.value,
                despawnRate: despawnRateStat.value,
              ),
            ),
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
                width: 64,
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

class ParticlesPhysicsDemo extends StatefulWidget {
  const ParticlesPhysicsDemo({super.key});

  @override
  State<ParticlesPhysicsDemo> createState() => _ParticlesPhysicsDemoState();
}

class _ParticlesPhysicsDemoState extends State<ParticlesPhysicsDemo> {
  int _mode = 0; // 0 = ECS, 1 = EC

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
        // Only one scene is mounted at a time — type change forces full dispose + remount.
        Expanded(
          child: ClipRect(
            child: _mode == 0 ? const _EcsPhysicsTab() : const _EcPhysicsTab(),
          ),
        ),
      ],
    );
  }
}
