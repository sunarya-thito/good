import 'package:goo2d/goo2d.dart';

/// Sets how many entities the case should keep alive.
///
/// A *target*, not a delta, and that is the interesting part: the case is
/// responsible for converging on it, spawning to make up a shortfall and
/// letting expiries take it down. One command shared by every case, because
/// "hold this many" is the same request in all of them.
class SetPopulation extends SinkCommand<int> {
  late final ParamPointer<int> count;

  @override
  void describeParams(ParamDescriptor descriptor) {
    count = descriptor.hasUint16();
  }

  @override
  void bufferFromParams(ParamBuffer call, int params) => count[call] = params;

  @override
  int paramsFromBuffer(ParamBuffer call) => count[call];
}

/// The half of a demo case that lives on the **main** isolate: the channels
/// the harness's overlay reads, and the commands its buttons send.
///
/// Every case extends this rather than `Game2D` directly, so the harness can
/// show the same readout for all of them without knowing which case is
/// running. A case adds its own commands and channels on top; it does not
/// re-declare any of these.
abstract class DemoGame extends Game2D {
  /// Microseconds the case's *own* systems spent in the last fixed step -
  /// whatever it chose to time, and nothing else. Published by [DemoStats]
  /// from [DemoState.caseMicros].
  late final StateChannel<int> caseMicros;

  /// Time inside `FixedTickable` systems, the whole fixed step, the
  /// presentation pass, one `advance` end to end, and the gap between two of
  /// them. All per *advance*, which is why [stepsPerAdvance] sits next to
  /// them - see its doc.
  late final StateChannel<int> systemMicros;
  late final StateChannel<int> bestSystemMicros;
  late final StateChannel<int> stepMicros;
  late final StateChannel<int> presentMicros;
  late final StateChannel<int> advanceMicros;
  late final StateChannel<int> intervalMicros;

  /// [presentMicros] split into its three phases - walking renderables into
  /// the draw queue, sorting by z, writing geometry. Three unrelated costs
  /// with three unrelated fixes, so one total cannot direct any of them.
  late final StateChannel<int> presentWalkMicros;
  late final StateChannel<int> presentSortMicros;
  late final StateChannel<int> presentWriteMicros;

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
  late final StateChannel<int> stepsPerAdvance;

  /// What the case actually has, counted by the simulation rather than by the
  /// button that asked - so a batch that was refused is visible.
  late final StateChannel<int> spawnedCount;

  /// Sprites the renderer emitted last frame, which is not always what exists:
  /// `maxSpritesPerTick` caps the batch, and hitting the cap looks exactly
  /// like the renderer getting slower unless you can see it.
  late final StateChannel<int> spritesDrawn;

  late final SetPopulation setPopulation;

  /// A megabyte per page - big enough that a 20k-entity case is a handful of
  /// pages rather than hundreds, small enough that a case holding one camera
  /// does not reserve a megabyte to hold it.
  @override
  int get pageSize => 1 << 20;

  @override
  int get maxSpritesPerTick => 24000;

  @override
  void describeState(StateDescriptor descriptor) {
    caseMicros = descriptor.hasInt32();
    systemMicros = descriptor.hasInt32();
    bestSystemMicros = descriptor.hasInt32();
    stepMicros = descriptor.hasInt32();
    presentMicros = descriptor.hasInt32();
    advanceMicros = descriptor.hasInt32();
    intervalMicros = descriptor.hasInt32();
    presentWalkMicros = descriptor.hasInt32();
    presentSortMicros = descriptor.hasInt32();
    presentWriteMicros = descriptor.hasInt32();
    stepsPerAdvance = descriptor.hasInt32();
    spawnedCount = descriptor.hasInt32();
    spritesDrawn = descriptor.hasInt32();
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    setPopulation = descriptor.has(SetPopulation());
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

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(DemoStats());
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    descriptor.hasSink(game.setPopulation, _onSetPopulation);
  }

  void _onSetPopulation(int target) => targetPopulation = target;
}

/// Publishes every number the overlay shows, **after** the fixed step.
///
/// A `Tickable`, not a `FixedTickable`, and that placement is the whole point:
/// the phase totals are only complete once `fixedTickEvent` has returned, so
/// publishing them from inside a system reports a half-accumulated figure -
/// which it once did, and the resulting numbers were nonsense in a way that
/// looked plausible.
class DemoStats extends GameSystem with Tickable {
  @override
  void onTick(Duration delta) {
    final game = getGame<DemoGame>();
    final state = getState<DemoState>();
    final renderer = state.getSystem<GameRenderer2D>();
    game
      ..caseMicros.value = state.caseMicros
      ..systemMicros.value = state.lastSystemMicros
      ..bestSystemMicros.value = state.bestSystemMicros
      ..stepMicros.value = state.lastSimulationMicros
      ..presentMicros.value = state.lastPresentationMicros
      ..advanceMicros.value = state.lastAdvanceMicros
      ..intervalMicros.value = state.lastAdvanceIntervalMicros
      ..stepsPerAdvance.value = state.lastStepCount
      ..presentWalkMicros.value = renderer.lastWalkMicros
      ..presentSortMicros.value = renderer.lastSortMicros
      ..presentWriteMicros.value = renderer.lastWriteMicros
      ..spawnedCount.value = state.spawnedCount
      ..spritesDrawn.value = renderer.lastSpriteCount;
  }
}
