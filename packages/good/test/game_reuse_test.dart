import 'package:flutter_test/flutter_test.dart';
import 'package:good/good.dart';

/// **One `Game` instance describes one game and backs one run of it.**
///
/// This is the rule, not a limitation waiting to be lifted, and this file is
/// where it is asserted rather than left to be discovered.
///
/// Two facts hold it up and they agree. A declaration is one-shot, because
/// every one of them lands in a `late final` (RULES.md rule 6) and a `late
/// final` is assignable exactly once. And a declaration *is* its storage: the
/// `StateChannel` returned by `descriptor.hasInt32()` holds the run's
/// `TripleBuffer` directly, a `BufferHandle` its `RingBuffer`, a
/// `GameCommand` the sender that routes it - which is what keeps reading any
/// of them a plain field access on the tick path, with no per-access
/// indirection to work out which run is asking.
///
/// Making an instance reusable means separating those: declarations become
/// pure (index plus metadata) and each run gets a storage table, reached as
/// `game.score[run].value`. That trades an indirection on the engine's hottest
/// paths for a multiplicity that `MyGame()` already provides, so it is not
/// worth buying. Constructing a second instance is the answer.
///
/// What *did* move to per-run is everything that is not a declaration - the
/// roles, the ports, the tick counter, the `GameState`, the command registry -
/// which is `GameRuntime`. That split earns its keep without reuse: it is what
/// lets the runtime be the spawn message and swap its isolate roles while the
/// description arrives on the far side unchanged.

class _Thing extends EntityStruct {}

class _Level extends SceneStruct {
  late final _Thing thing;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    thing = descriptor.has(_Thing());
  }
}

class _ReuseState extends GameState<_Reuse> {
  @override
  void onMounted() => loadScene(_Level());
}

class _Reuse extends Game {
  /// A `late final` filled by a declaration pass - which is exactly what makes
  /// the pass one-shot, and what this file is about.
  late final StateChannel<int> score;

  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  void describeState(StateDescriptor descriptor) {
    score = descriptor.hasInt32();
  }

  @override
  GameState createState() => _ReuseState();
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test(
    'starting one instance twice is refused, and says what to do instead',
    () async {
      final game = _Reuse();
      final run = await Game.startInline(game);
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });

      expect(
        () => Game.startInline(game),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('has already been started'),
              contains('Construct a second instance'),
            ),
          ),
        ),
        reason:
            'the failure a user would otherwise hit is a '
            'LateInitializationError thrown from inside their own '
            'describeState, which names neither the cause nor the fix',
      );
    },
  );

  test('the refusal comes before anything is declared a second time', () async {
    final game = _Reuse();
    final run = await Game.startInline(game);
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    expect(game.stateChannelCount, 1);
    await expectLater(Game.startInline(game), throwsStateError);

    // Why this is guarded in `start` rather than left to the declaration pass
    // to throw: `describeState` appends to the declared list *before* it
    // assigns the `late final` that blows up, so the unguarded path left this
    // reading 2 - an instance permanently describing twice the storage it
    // should, with the extra channels allocated and never freed. The
    // LateInitializationError was not the damage, it was the symptom.
    expect(
      game.stateChannelCount,
      1,
      reason: 'a refused start must not have declared anything',
    );
  });

  test(
    'a game started inline is drivable; that is what start() withholds',
    () async {
      final game = await Game.startInline(_Reuse());
      addTearDown(() async {
        if (game.isRunning) await game.stop();
      });

      expect(game.state, isNotNull);
      expect(game.advance(const Duration(milliseconds: 10)), 1);
      expect(() => game.runFixedStep(), returnsNormally);
    },
  );

  test('reaching the world on a game started with start() is refused', () async {
    final game = await Game.start(_Reuse());
    addTearDown(() async {
      if (game.isRunning) await game.stop();
    });

    // The guard asks what the *caller* asked for (`GameRuntime.drivable`), not
    // how the run happens to be wired (`inline`). Those differ on exactly one
    // configuration and it is the one this test cannot execute: `Game.start`
    // runs **inline on the web**, because there are no isolates in the
    // shared-memory sense there. A guard on `inline` therefore let `game.state`
    // answer on the web and throw on native, off identical source - the
    // "compiles everywhere, works in one place" failure inverted.
    //
    // The VM cannot run the web path, so what is asserted here is the decision
    // rather than the platform: `start()` withholds the world whatever the
    // mechanism underneath it turns out to be. If this ever passes because
    // `inline` happened to be false, read the message - it names the caller,
    // not the wiring.
    for (final reach in <void Function()>[
      () => game.state,
      () => game.advance(const Duration(milliseconds: 10)),
      () => game.runFixedStep(),
    ]) {
      expect(
        reach,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('Game.startInline()'), contains('Game.start()')),
          ),
        ),
      );
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('stopping does not hand the instance back for reuse', () async {
    final game = _Reuse();
    final run = await Game.startInline(game);
    await run.stop();

    // Sequential reuse looks like the easy half - the first run's storage is
    // released, so there is nothing left to collide with - and it is refused
    // by the same rule, for the first of the two reasons alone. Declaring and
    // binding are one pass, so a second run cannot re-bind the surviving
    // declarations without re-running the user's `describeX`, and re-running
    // those is precisely what a `late final` forbids.
    expect(() => Game.startInline(game), throwsStateError);
  });
}
