import 'dart:io' show ProcessInfo;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/data/renderer/data.dart';
import 'package:goo2d/src/data/renderer/system.dart';
import 'package:goo2d/src/data/transform/data.dart';
import 'package:goo2d/src/data/transform/system.dart';

// ---------------------------------------------------------------------------
// Shared constants
// ---------------------------------------------------------------------------

const _kWorldHeight = 20.0;
const _kMaxParticles = 8000;
const _kLifetime = 3.0;
const _kGravity = 5.0;
const _kDefaultSpawn = 500.0;
const _kHistoryLen = 60;

final _rng = Random();

double _randRange(double lo, double hi) => lo + _rng.nextDouble() * (hi - lo);

int _getMemoryMb() => kIsWeb ? 0 : ProcessInfo.currentRss ~/ (1024 * 1024);

// Increment-only counter shared between producer systems and _StatsSystem.
class _Counter {
  int value = 0;
}

// ---------------------------------------------------------------------------
// Sprite helpers
// ---------------------------------------------------------------------------

ui.Image _makeCircleSprite(int diameter) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final r = diameter / 2.0;
  canvas.drawCircle(
    ui.Offset(r, r),
    r - 0.5,
    ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..isAntiAlias = true,
  );
  return recorder.endRecording().toImageSync(diameter, diameter);
}

class _ImageMesh extends SpriteMesh {
  final ui.Image image;
  _ImageMesh(this.image);

  @override
  ui.Size get size => ui.Size(image.width.toDouble(), image.height.toDouble());

  @override
  GameTexture get texture =>
      throw UnsupportedError('_ImageMesh has no GameTexture');

  @override
  ui.Rect? get srcRect => null;

  @override
  SpriteMesh withTexture(GameTexture tex) =>
      throw UnsupportedError('_ImageMesh cannot be re-textured');

  @override
  SpriteMesh withSrcRect(ui.Rect? r) =>
      throw UnsupportedError('_ImageMesh cannot change srcRect');

  @override
  RenderHandle createHandle() => _ImageHandle(image);
}

class _ImageHandle extends RenderHandle {
  final ui.Image _image;
  _ImageHandle(this._image);

  @override
  void render(ui.Canvas canvas, ui.Size size, ui.Paint paint) {
    final src = ui.Rect.fromLTWH(
      0,
      0,
      _image.width.toDouble(),
      _image.height.toDouble(),
    );
    final dst = ui.Rect.fromCenter(
      center: ui.Offset.zero,
      width: size.width,
      height: size.height,
    );
    canvas.drawImageRect(
      _image,
      src,
      dst,
      ui.Paint()
        ..colorFilter = ui.ColorFilter.mode(paint.color, ui.BlendMode.modulate)
        ..blendMode = paint.blendMode
        ..filterQuality = paint.filterQuality,
    );
  }

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// ECS — particle data
// ---------------------------------------------------------------------------

class _ParticleData extends EntityData {
  late final Field<double> vx, vy, lifetime;
  late final Field<int> colorArgb;

  @override
  void describe(DataDescriptor d) {
    vx = d.newFloat32();
    vy = d.newFloat32();
    lifetime = d.newFloat32();
    colorArgb = d.newUint32();
  }
}

// ---------------------------------------------------------------------------
// ECS — spawn system
// ---------------------------------------------------------------------------

class _SpawnSystem extends WorldSystem with Tickable {
  static final Type orderBefore = _MoveSystem;
  @override
  Type? get systemBefore => orderBefore;

  final ValueNotifier<double> spawnRate;
  final _Counter spawnAcc;
  double _acc = 0;

  _SpawnSystem(this.spawnRate, this.spawnAcc);

  late final _pd = define(_ParticleData.new);

  @override
  void onUpdate(double dt) {
    _acc += spawnRate.value * dt;
    var n = _acc.floor();
    if (n <= 0) return;
    _acc -= n;

    final existing = (world.query()..withAll(_pd)).count();
    n = n.clamp(0, _kMaxParticles - existing);
    if (n <= 0) return;

    spawnAcc.value += n;

    for (var i = 0; i < n; i++) {
      final angle = _rng.nextDouble() * 2 * pi;
      final speed = _randRange(3.0, 12.0);
      final radius = _randRange(0.08, 0.25);
      final hue = _rng.nextDouble() * 360.0;
      final color = HSVColor.fromAHSV(1.0, hue, 0.9, 1.0).toColor();

      world.commandBuffer.createEntityAll([
        TransformData.new.withInit((d, r) {
          d.x.set(r, 0.0);
          d.y.set(r, 0.0);
        }),
        WorldTransformData.new.withInit((d, r) {
          d.wx.set(r, 0.0);
          d.wy.set(r, 0.0);
        }),
        _ParticleData.new.withInit((d, r) {
          d.vx.set(r, cos(angle) * speed);
          d.vy.set(r, sin(angle) * speed);
          d.lifetime.set(r, _kLifetime);
          d.colorArgb.set(r, color.toARGB32());
        }),
        RenderData.new.withInit((d, r) {
          d.size.set(r, Size(radius * 2, radius * 2));
          d.color.set(r, color);
          d.spriteIndex.set(r, 0);
        }),
      ]);
    }
  }
}

// ---------------------------------------------------------------------------
// ECS — move system
// ---------------------------------------------------------------------------

class _MoveSystem extends WorldSystem with Tickable {
  static final Type orderAfter = _SpawnSystem;
  static final Type orderBefore = TransformSystem;
  @override
  Type? get systemAfter => orderAfter;
  @override
  Type? get systemBefore => orderBefore;

  final _Counter despawnAcc;

  _MoveSystem(this.despawnAcc);

  late final _pd = define(_ParticleData.new);
  late final _td = define(TransformData.new);
  late final _rd = define(RenderData.new);

  @override
  void onUpdate(double dt) {
    (world.query()..withAll(_pd, _td, _rd)).withEntity().forEach((r) {
      final pd = _pd, td = _td, rd = _rd;
      final s = r.entity.index;

      final vy = pd.vy.getSlot(s) + _kGravity * dt;
      pd.vy.setSlot(s, vy);
      td.x.setSlot(s, td.x.getSlot(s) + pd.vx.getSlot(s) * dt);
      td.y.setSlot(s, td.y.getSlot(s) + vy * dt);

      final lt = pd.lifetime.getSlot(s) - dt;
      pd.lifetime.setSlot(s, lt);

      if (lt <= 0) {
        despawnAcc.value++;
        world.commandBuffer.removeEntity(r.entity);
      } else {
        final alpha = (255.0 * (lt / _kLifetime)).clamp(0.0, 255.0).round();
        final argb = (pd.colorArgb.getSlot(s) & 0x00FFFFFF) | (alpha << 24);
        rd.color.setSlot(s, Color(argb));
      }
    });
  }
}

// ---------------------------------------------------------------------------
// ECS — stats system
// ---------------------------------------------------------------------------

class _StatsSystem extends WorldSystem with Tickable {
  static final Type orderAfter = _MoveSystem;
  @override
  Type? get systemAfter => orderAfter;

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

  _StatsSystem(
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

  late final _pd = define(_ParticleData.new);

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

    count.value = (world.query()..withAll(_pd)).count();
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

double get _fps => fps.toDouble();

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

class _EcsParticleTab extends StatefulWidget {
  const _EcsParticleTab();

  @override
  State<_EcsParticleTab> createState() => _EcsParticleTabState();
}

class _EcsParticleTabState extends State<_EcsParticleTab> {
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
      TickerState.new,
      InputSystem.new,
      CameraSystem.new,
      ScreenSystem.new,
    }).then((engine) {
      if (_disposed) { engine.dispose(); return; }
      setState(() => _engine = engine);
    });
    final circleSprite = GameSprite(mesh: _ImageMesh(_makeCircleSprite(64)));
    final spawnAcc = _Counter();
    final despawnAcc = _Counter();
    _world = WorldController();
    _world.addSystem(_SpawnSystem(_spawnRate, spawnAcc));
    _world.addSystem(_MoveSystem(despawnAcc));
    _world.addSystem(TransformSystem());
    _world.addSystem(
      _StatsSystem(
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
    _world.addSystem(RenderSystem([circleSprite]));
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
}

// ---------------------------------------------------------------------------
// EC — particle behavior
// ---------------------------------------------------------------------------

class _ParticleBehavior extends Behavior with Tickable, LifecycleListener {
  double vx, vy;
  final Color color;
  double lifetime = _kLifetime;
  final VoidCallback onExpired;
  bool _expired = false;

  late ObjectTransform _transform;

  _ParticleBehavior({
    required this.vx,
    required this.vy,
    required this.color,
    required this.onExpired,
  });

  @override
  void onMounted() {
    _transform = gameObject.getComponent<ObjectTransform>();
  }

  @override
  void onUpdate(double dt) {
    vy += _kGravity * dt;
    final pos = _transform.localPosition;
    _transform.localPosition = Vector2(pos.x + vx * dt, pos.y + vy * dt);
    lifetime -= dt;
    if (lifetime <= 0 && !_expired) {
      _expired = true;
      onExpired();
    }
  }
}

// ---------------------------------------------------------------------------
// EC — circle renderer
// ---------------------------------------------------------------------------

class _CircleRenderer extends Behavior with Renderable {
  Color color;
  final double radius;

  _CircleRenderer({required this.color, required this.radius});

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(Offset.zero, radius, Paint()..color = color);
  }
}

// ---------------------------------------------------------------------------
// EC — particle scene
// ---------------------------------------------------------------------------

class _EcParticleScene extends StatefulGameWidget {
  final ValueNotifier<double> spawnRate;
  final void Function(
    int count,
    double fps,
    double spawnRate,
    double despawnRate,
  )
  onStats;

  const _EcParticleScene({required this.spawnRate, required this.onStats});

  @override
  GameState<_EcParticleScene> createState() => _EcParticleSceneState();
}

class _EcParticleSceneState extends GameState<_EcParticleScene> with Tickable {
  final List<Widget> _particles = [];
  double _spawnAcc = 0;
  double _elapsed = 0;
  int _nextId = 0;
  int _spawnCount = 0;
  int _despawnCount = 0;

  void _removeParticle(Key key) {
    _despawnCount++;
    setState(() => _particles.removeWhere((w) => w.key == key));
  }

  @override
  void onUpdate(double dt) {
    _elapsed += dt;

    _spawnAcc += widget.spawnRate.value * dt;
    var n = _spawnAcc.floor();
    if (n > 0) {
      _spawnAcc -= n;
      n = n.clamp(0, _kMaxParticles - _particles.length);
      if (n > 0) {
        _spawnCount += n;
        final newOnes = List<Widget>.generate(n, (_) {
          final id = _nextId++;
          final key = ValueKey(id);
          final angle = _rng.nextDouble() * 2 * pi;
          final speed = _randRange(3.0, 12.0);
          final r = _randRange(0.08, 0.25);
          final hue = _rng.nextDouble() * 360.0;
          final color = HSVColor.fromAHSV(1.0, hue, 0.9, 1.0).toColor();
          return GameObjectWidget(
            key: key,
            children: [
              ComponentWidget(ObjectTransform.new),
              ComponentWidget(
                () => _ParticleBehavior(
                  vx: cos(angle) * speed,
                  vy: sin(angle) * speed,
                  color: color,
                  onExpired: () => _removeParticle(key),
                ),
              ),
              ComponentWidget(() => _CircleRenderer(color: color, radius: r)),
            ],
          );
        });
        setState(() => _particles.addAll(newOnes));
      }
    }

    if (_elapsed >= 0.25) {
      final sr = _spawnCount / _elapsed;
      final dr = _despawnCount / _elapsed;
      _spawnCount = 0;
      _despawnCount = 0;
      _elapsed = 0;
      widget.onStats(_particles.length, fps.toDouble(), sr, dr);
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
    yield* _particles;
  }
}

// ---------------------------------------------------------------------------
// EC tab
// ---------------------------------------------------------------------------

class _EcParticleTab extends StatefulWidget {
  const _EcParticleTab();

  @override
  State<_EcParticleTab> createState() => _EcParticleTabState();
}

class _EcParticleTabState extends State<_EcParticleTab> {
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
      TickerState.new,
      InputSystem.new,
      CameraSystem.new,
      ScreenSystem.new,
    }).then((engine) {
      if (_disposed) { engine.dispose(); return; }
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
          child: _EcParticleScene(spawnRate: _spawnRate, onStats: _onStats),
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
// 5 bands: FPS, memory, particle count, spawn rate, despawn rate.
// Each band draws its line graph + a text label overlaid on top.
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
        ? _kMaxParticles.toDouble()
        : (countSamples.reduce(max) * 1.2).clamp(
            100.0,
            _kMaxParticles.toDouble(),
          );
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
    _drawLabel(
      canvas,
      bands[2],
      'PARTICLES  $currentCount',
      Colors.orangeAccent,
    );
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

    // Dividers between bands
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
                  max: 2000,
                  divisions: 40,
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

class ParticlesDemo extends StatefulWidget {
  const ParticlesDemo({super.key});

  @override
  State<ParticlesDemo> createState() => _ParticlesDemoState();
}

class _ParticlesDemoState extends State<ParticlesDemo>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Data-Oriented Scope'),
            Tab(text: 'GameObject + Component'),
          ],
        ),
        Expanded(
          child: ClipRect(
            child: _tab.index == 0
                ? const _EcsParticleTab()
                : const _EcParticleTab(),
          ),
        ),
      ],
    );
  }
}
