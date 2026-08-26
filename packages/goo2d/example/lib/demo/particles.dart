import 'dart:math' as math;

import 'package:goo2d/goo2d.dart';

import 'package:goo2d_example/demo/demo.dart';
import 'package:goo2d_example/demo/demo_game.dart';
import 'package:goo2d_example/demo/textures.dart';

/// Turns the two write-pass ablations on and off, together.
///
/// **A measuring instrument, not a feature.** Each flag deliberately makes the
/// case render *wrongly* - that is what isolates the cost. See
/// [ParticlesState.ablations].
///
/// One command carrying a bitmask rather than two commands carrying a bool
/// each: the two flags are read together, set together from one overlay, and a
/// single round trip cannot leave the simulation holding a half-applied pair.
class SetAblations extends SinkCommand<int> {
  /// Bit 0 - skip the z sort, so the write pass walks rows in encounter order.
  static const int skipSort = 1;

  /// Bit 1 - hold every mote's rotation at zero, which makes the renderer's
  /// unrotated fast path skip both trig calls.
  static const int noRotation = 2;

  final flags = Param.uint2();

  @override
  void bufferFromParams(ParamBuffer call, int params) => flags[call] = params;

  @override
  int paramsFromBuffer(ParamBuffer call) => flags[call];
}

/// Packs HSV to the ARGB integer `Sprite.color` stores.
///
/// A plain function over ints rather than anything from `dart:ui`: a component
/// row holds a `uint32`, never a `Color` object, and the conversion happens
/// once per entity at spawn rather than per frame.
int _hsv(double hue, double saturation, double value) {
  final h = (hue % 1.0) * 6.0;
  final sector = h.floor();
  final f = h - sector;
  final p = value * (1 - saturation);
  final q = value * (1 - saturation * f);
  final t = value * (1 - saturation * (1 - f));
  final (double r, double g, double b) = switch (sector % 6) {
    0 => (value, t, p),
    1 => (q, value, p),
    2 => (p, value, t),
    3 => (p, q, value),
    4 => (t, p, value),
    _ => (value, p, q),
  };
  return 0xFF000000 |
      ((r * 255).round() << 16) |
      ((g * 255).round() << 8) |
      (b * 255).round();
}

/// One particle.
///
/// **No `WorldTransform2D` and no `Child`**, and that is the point of this
/// case rather than an oversight: a particle is never parented, so its local
/// transform *is* its world transform. Carrying the mixin anyway would put
/// every row in `WorldTransformSystem`'s query and have it copy five fields
/// per entity per fixed step so the renderer could read the copy back. The
/// renderer reads whichever transform an archetype actually has, so a flat
/// prefab costs nothing for the hierarchy it is not using. Compare against the
/// scene-graph case, which does use one.
class Mote extends EntityStruct
    with Transform2D, Renderable2D, EntityLifecycleListener {
  late final Sprite body;
  late final TextureAsset texture;

  /// Polar coordinates, kept per entity because the movement is a function of
  /// them and of time - so a tick reads four fields and writes three, and no
  /// entity has to remember where it was.
  final angle = Field.float64();
  final radius = Field.float64();
  final spin = Field.float64();

  /// Seconds this mote has left. Counted down by [SwirlSystem], which destroys
  /// it at zero - so the population churns instead of only ever growing, and
  /// spawn *and* despawn are on the hot path rather than just spawn.
  final life = Field.float64();

  /// What it started with, so the fade can be a fraction rather than needing a
  /// second clock.
  final lifespan = Field.float64();

  /// The size this mote would be at the peak of its life. Stored rather than
  /// recomputed because the fade multiplies it every tick and the value it
  /// came from is per entity.
  final baseSize = Field.float64();

  /// Plain Dart state on the prefab: it lives on the game isolate and is never
  /// shared, so it costs nothing across the boundary.
  int _spawned = 0;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    texture = descriptor.has(discTexture);
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    body = descriptor.has(width: 14, height: 14, texture: texture);
  }

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    final i = _spawned++;
    // A lifetime between 1.6s and 4.4s, spread by the same low-discrepancy
    // trick as everything else here so a batch spawned together does not all
    // expire together and pulse the population.
    final span = 1.6 + 2.8 * ((i * 0.7548776662466927) % 1.0);
    life[entity] = span;
    lifespan[entity] = span;
    // A golden-angle spiral for the *angle*, so consecutive spawns land
    // nowhere near each other and the field reads as one object from the first
    // batch rather than a growing arc.
    final t = i * 2.39996322972865332; // 2*pi / phi^2
    // The radius stays inside a **fixed** disc, and that is the whole
    // difference between "spawning does something" and "the counter goes up".
    // A radius that grew with the index put everything past the first few
    // hundred entities off-screen, so every batch after the first changed a
    // number and nothing else. Drawn from a low-discrepancy sequence instead,
    // with `sqrt` so the points are even by *area* rather than crowding the
    // middle - so more entities means a visibly denser galaxy, in frame.
    final u = (i * 0.6180339887498949) % 1.0;
    final r = 70 + 380 * math.sqrt(u);
    angle[entity] = t;
    radius[entity] = r;
    // Inner particles orbit faster - differential rotation, which is what
    // makes the whole thing wind into arms instead of turning as a disc.
    spin[entity] = 1.6 / (1 + r * 0.006);
    // Written, never read-then-written, on the creation tick: a read here sees
    // the previous tick's published snapshot rather than what was just
    // stamped. See data_layout.dart's note on `_readRow`.
    transformOffsetX[entity] = math.cos(t) * r;
    transformOffsetY[entity] = math.sin(t) * r;
    // The same expression [SwirlSystem] uses, at this mote's starting angle -
    // see `Critter.onEntityMounted` for what leaving it defaulted looks like.
    transformRotation[entity] = -t * 2;
    // Bigger and brighter near the middle, so depth reads even when the disc
    // is dense. Starts at zero width - the first tick fades it in.
    baseSize[entity] = 4.0 + 9.0 * (1 - math.sqrt(u));
    body
      ..width[entity] = 0
      ..height[entity] = 0
      ..color[entity] = _hsv(0.52 + u * 0.30, 0.55 + u * 0.35, 1.0)
      // Layered back to front by distance, so the crowded middle draws over
      // the sparse edge instead of flickering between orderings.
      ..zIndex[entity] = 4000 - r.round();
  }
}

class Eye extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

class Galaxy extends SceneStruct {
  late final Mote mote;
  late final Eye eye;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    mote = descriptor.has(Mote.new);
    eye = descriptor.has(Eye.new);
  }

  @override
  void onSceneMounted(Scene scene) => scene.addEntity(eye);
}

/// Advances every particle along its orbit, and times itself.
///
/// Timed *inside* the system rather than around `advance()`, because `advance`
/// also runs the renderer's presentation pass and bundling the two would make
/// "the simulation is slow" and "the renderer is slow" the same number.
class SwirlSystem extends GameSystem with FixedTickable {
  final motes = Query.all(Transform2D, Mote);

  final Stopwatch _clock = Stopwatch();

  double _time = 0;

  /// A cap on how many can arrive in one step. Without it, dragging the
  /// slider from 0 to 20k would spend one whole step allocating and read as a
  /// stall rather than as a fill.
  static const int _maxSpawnPerTick = 400;

  @override
  void onFixedUpdate() {
    _clock
      ..reset()
      ..start();
    // `loadedScenes.single`, not a handle stashed on the struct: a
    // `SceneStruct` is the declaration and a `Scene` is one loaded instance of
    // it, so the struct is the wrong place to keep one. `.single` states this
    // case's assumption - one scene - and throws if that stops being true,
    // rather than quietly picking the first.
    final scene = state.loadedScenes.single;
    // Read once per tick, not per entity - see `SetAblations`. With this on,
    // every mote's rotation is held at zero, which is what makes the
    // renderer's unrotated fast path skip its two trig calls. The field is
    // still written every tick, so the ablation costs the simulation the same
    // work and only changes what the *renderer* has to do with it.
    final demo = getState<ParticlesState>();
    final flatten = demo.noRotation;
    var alive = 0;
    final dt = state.game.fixedTimeStep.inMicroseconds / 1000000.0;
    _time += dt;
    // A slow global breathe, so the field is never quite the same shape twice
    // and the eye can see that it is live rather than a still image.
    final breathe = 1.0 + 0.08 * math.sin(_time * 0.6);

    // Grouped, not `run()`: a component belongs to an archetype, so
    // `entity.get<Mote>()` would return the same object for every row. It is
    // only *correct* to hoist per archetype - one query can match several -
    // which is exactly the scope a group is.
    for (final group in motes.groups()) {
      final transform = group.get<Transform2D>();
      final mote = group.get<Mote>();
      for (final entity in group) {
        final remaining = mote.life[entity] - dt;
        if (remaining <= 0) {
          // Destroyed from inside the walk that found it. The page defers the
          // free until the walk ends, so this row stays readable for the rest
          // of this pass and is handed to the next spawn after it.
          entity.destroy();
          continue;
        }
        mote.life[entity] = remaining;
        alive++;

        final a = mote.angle[entity] + mote.spin[entity] * dt;
        final r = mote.radius[entity] * breathe;
        mote.angle[entity] = a;
        // Scale in from nothing and back out again, so a mote arriving or
        // leaving is something you see rather than a pop. `t` is 0 at both
        // ends of its life and 1 in the middle.
        final t = mote.life[entity] / mote.lifespan[entity];
        final fade = math.sin((1 - t) * math.pi);
        final size = mote.baseSize[entity] * fade;
        mote.body
          ..width[entity] = size
          ..height[entity] = size;
        transform
          ..transformOffsetX[entity] = math.cos(a) * r
          ..transformOffsetY[entity] = math.sin(a) * r
          // The sprite itself counter-rotates, so a still frame of the middle
          // is not a ring of identical discs.
          ..transformRotation[entity] = flatten ? 0 : -a * 2;
      }
    }

    // Top up to the target. Capped per tick so dragging the slider to the far
    // end is a fill you can watch rather than one frame that stalls: the whole
    // point of the slider is to see the cost move.
    final shortfall = demo.targetPopulation - alive;
    if (shortfall > 0) {
      final batch = shortfall < _maxSpawnPerTick ? shortfall : _maxSpawnPerTick;
      for (var i = 0; i < batch; i++) {
        scene.addEntity(demo.galaxy.mote);
      }
      alive += batch;
    }

    demo
      ..spawnedCount = alive
      ..caseMicros = _clock.elapsedMicroseconds;
    _clock.stop();
  }
}

class ParticlesState extends DemoState<ParticlesGame> {
  final Galaxy galaxy = Galaxy();

  /// The [SetAblations] bitmask currently in force. Zero - both off - is the
  /// only setting that renders this case correctly.
  int ablations = 0;

  bool get skipSort => ablations & SetAblations.skipSort != 0;
  bool get noRotation => ablations & SetAblations.noRotation != 0;

  @override
  void onMounted() => loadScene(galaxy);

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(SwirlSystem());
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    // The base declares `setPopulation`'s handler; dropping this super call
    // would silently leave the population slider with nothing to talk to.
    super.describeCommands(descriptor);
    descriptor.hasSink(game.setAblations, _onSetAblations);
  }

  void _onSetAblations(int value) {
    ablations = value;
    // Reached through the system rather than kept as a second copy of the
    // flag: the renderer is the thing that acts on it, so it is the thing that
    // holds it.
    getSystem<GameRenderer2D>().debugSkipZSort = skipSort;
  }
}

class ParticlesGame extends DemoGame {
  late final SetAblations setAblations;

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    setAblations = descriptor.has(SetAblations.new);
  }

  @override
  ParticlesState createState() => ParticlesState();
}

/// A flat field of unparented sprites, which is what you have twenty thousand
/// of in a real game: particles, bullets, tiles, debris.
class ParticlesDemo extends Demo {
  ParticlesDemo();

  late final ParticlesGame _game;

  @override
  String get name => 'Galaxy';

  @override
  String get blurb =>
      'Flat sprites, no hierarchy. One archetype, one texture, one draw call.';

  @override
  DemoGame create() => _game = ParticlesGame();

  @override
  DemoGame get game => _game;

  @override
  List<DemoSlider> get sliders => <DemoSlider>[
    DemoSlider(
      'population',
      (value) => _game.setPopulation(value),
      min: 0,
      max: 20000,
      initial: 3000,
    ),
  ];

  /// The current [SetAblations] mask, kept here because a toggle only reports
  /// its own new value and the command carries both bits at once.
  int _ablations = 0;

  Future<void> _setAblation(int bit, bool on) {
    _ablations = on ? _ablations | bit : _ablations & ~bit;
    return _game.setAblations(_ablations);
  }

  /// **Both of these make the case render wrongly, on purpose.**
  ///
  /// They exist to attribute the write pass *on the device*, which is the only
  /// machine where its cost is what it is: a desktop AOT model puts the whole
  /// pass at ~72 ns/sprite and the device reports ~368, so the desktop cannot
  /// answer where the difference lives. Turn one on, read `write` off the
  /// overlay, and the drop is that component's share.
  ///
  ///  * **skip z sort** - the write pass stops walking rows in a near-random
  ///    permutation. What it costs is cache misses; overlapping sprites layer
  ///    wrongly while it is on.
  ///  * **no rotation** - every mote's rotation is held at zero, so the
  ///    renderer's unrotated fast path skips both `math.cos`/`math.sin` calls.
  ///    The galaxy stops spinning while it is on.
  ///
  /// Enabled only at rest is not a constraint here: both can be flipped with a
  /// full population live, which is the whole point - the comparison wants the
  /// same 20,000 entities either side of the switch.
  @override
  List<DemoToggle> get toggles => <DemoToggle>[
    DemoToggle(
      'ablate: skip z sort',
      false,
      (on) => _setAblation(SetAblations.skipSort, on),
    ),
    DemoToggle(
      'ablate: no rotation',
      false,
      (on) => _setAblation(SetAblations.noRotation, on),
    ),
  ];
}
