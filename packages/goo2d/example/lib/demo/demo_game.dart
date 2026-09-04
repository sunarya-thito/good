import 'package:goo2d/goo2d.dart';

part 'demo_game.g.dart';

/// Sets how many entities the case should keep alive.
///
/// A *target*, not a delta, and that is the interesting part: the case is
/// responsible for converging on it, spawning to make up a shortfall and
/// letting expiries take it down. One command shared by every case, because
/// "hold this many" is the same request in all of them.
class SetPopulation extends ValueSink<int> {
  @override
  final value = Param.uint16();
}

/// The half of a demo case that lives on the **main** isolate: the channels
/// the harness's overlay reads, and the commands its buttons send.
///
/// Every case extends this rather than `Game2D` directly, so the harness can
/// show the same readout for all of them without knowing which case is
/// running. A case adds its own commands and channels on top; it does not
/// re-declare any of these.
abstract class DemoGame extends Game2D {
  /// Installs the collectors this library's fixtures are read through.
  ///
  /// A test installs its own first thing in `main`; a library with no `main`
  /// installs them where it is entered instead, and every case is entered by
  /// constructing its game. Each case file does the same for its own, because
  /// the table a part declares is private to the library that declares it.
  DemoGame() {
    _installDeclarations();
  }

  /// Microseconds the case's *own* systems spent in the last fixed step -
  /// whatever it chose to time, and nothing else. Published by [DemoStats]
  /// from [DemoState.caseMicros].
  final caseMicros = Channel.int32();

  /// Time inside `FixedTickable` systems, the whole fixed step, the
  /// presentation pass, one `advance` end to end, and the gap between two of
  /// them. All per *advance*, which is why [stepsPerAdvance] sits next to
  /// them - see its doc.
  ///
  /// **All measured by [DemoProfile], not by the engine.** The engine used to
  /// carry a `Stopwatch` and publish these itself; a game framework is not a
  /// profiler, so the clock moved to the only place that actually wants the
  /// numbers. Read [DemoProfile] for what each one can and cannot see from
  /// out here - two of them are bounded slightly tighter than the engine's
  /// were, and the doc says exactly where the missing slice went.
  final systemMicros = Channel.int32();
  final bestSystemMicros = Channel.int32();
  final stepMicros = Channel.int32();
  final presentMicros = Channel.int32();
  final advanceMicros = Channel.int32();
  final intervalMicros = Channel.int32();

  /// The `GameRenderer2D` share of [presentMicros] - what drawing costs, as
  /// opposed to everything else presenting.
  ///
  /// The two together are what direct a fix: presentation being expensive
  /// while this is small means the cost is in some other `Tickable`, and no
  /// amount of work on the renderer will move it.
  final renderMicros = Channel.int32();

  /// How many **fixed steps** the last `advance` ran, and the number without
  /// which none of the timings above are comparable.
  ///
  /// `advance` runs as many steps as the elapsed time affords, up to
  /// `maxFixedStepsPerAdvance`. [stepMicros] and [systemMicros] are reset once
  /// per *advance* and accumulate across every step in it, while [caseMicros]
  /// is whatever the case measured in *one* step. The moment an advance costs
  /// more than one step's wall clock, those stop sharing a denominator - a
  /// recording once read as a catastrophic super-linear blowup and was
  /// entirely this. Divide by it before comparing anything.
  final stepsPerAdvance = Channel.int32();

  /// What the case actually has, counted by the simulation rather than by the
  /// button that asked - so a batch that was refused is visible.
  final spawnedCount = Channel.int32();

  /// Sprites the renderer emitted last frame, which is not always what exists:
  /// `maxSpritesPerTick` caps the batch, and hitting the cap looks exactly
  /// like the renderer getting slower unless you can see it.
  final spritesDrawn = Channel.int32();

  late final SetPopulation setPopulation;

  /// A megabyte per page - big enough that a 20k-entity case is a handful of
  /// pages rather than hundreds, small enough that a case holding one camera
  /// does not reserve a megabyte to hold it.
  @override
  int get pageSize => 1 << 20;

  @override
  int get maxSpritesPerTick => 24000;

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    setPopulation = descriptor.has(SetPopulation.new);
  }

  @override
  DemoState createState();
}

/// The half that lives on the **game** isolate. A case implements [spawnOne]
/// and [clearAll] and is done; everything the overlay shows is already wired.
abstract class DemoState<G extends DemoGame> extends GameState2D<G> {
  /// Set by the case's own system, read by [DemoStats]. The case decides what
  /// it is timing - usually its movement loop - and nothing here interprets
  /// it beyond publishing it.
  int caseMicros = 0;

  /// Counted by the case's own system as it walks, rather than tracked by
  /// whoever asked - so what the overlay shows is what is actually alive,
  /// including entities that expired this tick.
  int spawnedCount = 0;

  /// How many entities this case should be keeping alive. The case's own
  /// system reads it and converges on it; nothing here spawns anything.
  int targetPopulation = 0;

  /// Where the frame went, measured by the probes below rather than by the
  /// engine. Read by [DemoStats], which is the last thing in the advance.
  final DemoProfile profile = DemoProfile();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    // Declaration order matters for the two render probes and for nothing
    // else here: they agree about `GameRenderer2D` and have no opinion about
    // each other, so the tie between them breaks on the order they were
    // declared in. Every other probe states its position outright.
    descriptor
      ..has(_FixedPhaseStart.new)
      ..has(_FixedPhaseEnd.new)
      ..has(_PresentPhaseStart.new)
      ..has(_RenderPhaseStart.new)
      ..has(_RenderPhaseEnd.new)
      ..has(DemoStats.new);
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor.hasSink(game.setPopulation, _onSetPopulation);
  }

  void _onSetPopulation(int target) => targetPopulation = target;
}

/// One free-running clock and the stamps six probe systems leave on it.
///
/// # Why the demo owns this
///
/// The engine used to keep a `Stopwatch` in `GameState` and publish the phase
/// totals as getters. That is a profiler living in a game framework, and it
/// paid for itself only on the runs where somebody was looking. The clock
/// moved here, to the thing that actually wants the numbers - the same trade
/// `SwirlSystem` already made for its own movement loop.
///
/// # Why it takes six systems and not one
///
/// Every number here is the difference between two stamps taken in *different*
/// systems, because a system can only ever observe its own position in a
/// dispatch. `fixedTickEvent` and `tickEvent` are each a list of systems, and
/// the only way to see the edges of one from inside it is to sit at both ends:
/// [_FixedPhaseStart] sorts ahead of everything in the fixed phase and
/// [_FixedPhaseEnd] behind it, so the pair brackets exactly what the fixed
/// systems cost. [_PresentPhaseStart] and [DemoStats] do the same for
/// presentation, and [_RenderPhaseStart] / [_RenderPhaseEnd] close around
/// `GameRenderer2D` alone.
///
/// # What this cannot see, and it matters
///
/// A bracket made of systems is bounded by the systems, so [stepMicros] and
/// [advanceMicros] are both slightly *narrower* than the engine's own numbers
/// used to be. What falls outside them is `runFixedStep`'s own preamble -
/// resolving inputs, `beginTick`, the command drain, the coroutine step - plus
/// `commitTick` and `presentFrame` at the other end. That slice is engine cost
/// a game can neither see nor fix, and reading it was the one thing these
/// stopped being able to do. It does not move the "is the loop slow or merely
/// starved" reading, which is [advanceMicros] against [intervalMicros], and
/// both of those are still here.
class DemoProfile {
  /// Never reset. Every number below is a difference between two readings, so
  /// resetting it would only create a discontinuity to get wrong - and one
  /// stopwatch read is tens of nanoseconds against a step measured in
  /// hundreds of microseconds.
  final Stopwatch clock = Stopwatch()..start();

  /// Stamped by whichever phase the frame actually reached first: the fixed
  /// one normally, presentation on a frame that afforded no step at all.
  int frameStartedAt = 0;
  int stepStartedAt = 0;
  int stepEndedAt = 0;
  int presentStartedAt = 0;
  int renderStartedAt = 0;

  /// Accumulated across however many fixed steps this frame ran, then read and
  /// cleared by [DemoStats]. The engine's number covered every step in the
  /// advance too, so [DemoGame.stepsPerAdvance] divides this one the same way.
  int systemMicros = 0;

  /// Steps this frame has run so far. Doubles as "has the fixed phase been
  /// entered yet", which is what tells [_FixedPhaseStart] it is looking at the
  /// start of the frame and not the start of a catch-up step.
  ///
  /// Counted here rather than read off `GameState.lastStepCount`, which the
  /// engine assigns *after* `runPresentation` returns - so a `Tickable`
  /// reading it gets the previous frame's count.
  int steps = 0;

  int renderMicros = 0;
  int intervalMicros = 0;

  /// Rolling minimum of [systemMicros] over the last [_bestWindow] frames.
  ///
  /// **Wall clock, not CPU time.** The game isolate shares a machine with
  /// Flutter's UI and raster threads, and preemption only ever *adds* to a
  /// measurement - so the minimum over a window is the closest a stopwatch
  /// gets to "how much work is this", while the latest value is "how long did
  /// it take on this contended machine". Raising the display scale from 100%
  /// to 150% was once observed to nearly double the reported system time at a
  /// fixed entity count, with nothing about the simulation changed.
  int get bestSystemMicros {
    if (_ringCount == 0) return 0;
    var best = _ring[0];
    for (var i = 1; i < _ringCount; i++) {
      if (_ring[i] < best) best = _ring[i];
    }
    return best;
  }

  static const int _bestWindow = 180;
  final List<int> _ring = List<int>.filled(_bestWindow, 0);
  int _ringNext = 0;
  int _ringCount = 0;

  /// Files this frame's systems total into the window and clears the
  /// per-frame accumulators. Called by [DemoStats], last thing in the advance.
  void endFrame() {
    _ring[_ringNext] = systemMicros;
    _ringNext = (_ringNext + 1) % _bestWindow;
    if (_ringCount < _bestWindow) _ringCount++;
    systemMicros = 0;
    steps = 0;
  }
}

/// Sorts ahead of every other `FixedTickable`, so its stamp is the moment the
/// fixed dispatch begins.
class _FixedPhaseStart extends GameSystem with FixedTickable {
  @override
  int compareTo(GameSystem other) => -1;

  @override
  void onFixedUpdate() {
    final profile = getState<DemoState>().profile;
    final now = profile.clock.elapsedMicroseconds;
    // Only the *first* step of a frame opens the frame. A catch-up frame runs
    // several, and taking the last one's start would report an advance that
    // began after most of its own work.
    if (profile.steps == 0) profile.frameStartedAt = now;
    profile.stepStartedAt = now;
  }
}

/// Sorts behind every other `FixedTickable`, closing the bracket.
class _FixedPhaseEnd extends GameSystem with FixedTickable {
  @override
  int compareTo(GameSystem other) => 1;

  @override
  void onFixedUpdate() {
    final profile = getState<DemoState>().profile;
    final now = profile.clock.elapsedMicroseconds;
    profile.systemMicros += now - profile.stepStartedAt;
    profile.stepEndedAt = now;
    profile.steps++;
  }
}

/// Sorts ahead of every other `Tickable`. Fires once per `advance` and on
/// *every* advance, including one that afforded no fixed step - which is what
/// makes it the right place to measure the gap between two of them.
class _PresentPhaseStart extends GameSystem with Tickable {
  @override
  int compareTo(GameSystem other) => -1;

  @override
  void onTick(Duration delta) {
    final profile = getState<DemoState>().profile;
    final now = profile.clock.elapsedMicroseconds;
    // Zero on the very first frame rather than "everything since boot", which
    // would otherwise land in the overlay as a multi-second interval.
    profile.intervalMicros = profile.presentStartedAt == 0
        ? 0
        : now - profile.presentStartedAt;
    profile.presentStartedAt = now;
    // A frame the accumulator could not fill never entered the fixed phase, so
    // this is where it begins as far as anything out here can see.
    if (profile.steps == 0) profile.frameStartedAt = now;
  }
}

/// Closes around `GameRenderer2D` specifically - the pair states its position
/// relative to that one system and has no opinion about anything else, so the
/// tie between the two of them breaks on declaration order.
class _RenderPhaseStart extends GameSystem with Tickable {
  @override
  int compareTo(GameSystem other) => other is GameRenderer2D ? -1 : 0;

  @override
  void onTick(Duration delta) {
    final profile = getState<DemoState>().profile;
    profile.renderStartedAt = profile.clock.elapsedMicroseconds;
  }
}

class _RenderPhaseEnd extends GameSystem with Tickable {
  @override
  int compareTo(GameSystem other) => other is GameRenderer2D ? 1 : 0;

  @override
  void onTick(Duration delta) {
    final profile = getState<DemoState>().profile;
    profile.renderMicros =
        profile.clock.elapsedMicroseconds - profile.renderStartedAt;
  }
}

/// Publishes every number the overlay shows, and closes the presentation
/// bracket while it is there.
///
/// A `Tickable` sorting behind everything else, and that placement is the
/// whole point: the phase totals are only complete once both dispatches have
/// returned, so publishing them from inside a system reports a
/// half-accumulated figure - which it once did, and the resulting numbers were
/// nonsense in a way that looked plausible.
class DemoStats extends GameSystem with Tickable {
  @override
  int compareTo(GameSystem other) => 1;

  @override
  void onTick(Duration delta) {
    final game = getGame<DemoGame>();
    final state = getState<DemoState>();
    final renderer = state.getSystem<GameRenderer2D>();
    final profile = state.profile;
    final now = profile.clock.elapsedMicroseconds;
    game
      ..caseMicros.value = state.caseMicros
      ..systemMicros.value = profile.systemMicros
      ..bestSystemMicros.value = profile.bestSystemMicros
      // Zero on a frame that ran no step, rather than a stamp difference
      // against a `stepEndedAt` left over from the last frame that did.
      ..stepMicros.value =
          profile.steps == 0 ? 0 : profile.stepEndedAt - profile.frameStartedAt
      ..presentMicros.value = now - profile.presentStartedAt
      ..renderMicros.value = profile.renderMicros
      ..advanceMicros.value = now - profile.frameStartedAt
      ..intervalMicros.value = profile.intervalMicros
      ..stepsPerAdvance.value = profile.steps
      ..spawnedCount.value = state.spawnedCount
      ..spritesDrawn.value = renderer.lastSpriteCount;
    profile.endFrame();
  }
}
