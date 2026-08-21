import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:good/good.dart';

/// The live run under test.
late Game run;

// Coroutines: `sync*` bodies resumed from inside the tick window.
//
// The design claim this file exists to hold up is in `Coroutine`'s doc: an
// `async*` body cannot be used here, because it resumes on a microtask and
// every component write it makes after a yield would land outside
// beginTick/commitTick and be discarded. The last group proves that directly
// rather than taking it on faith.

class _Mover extends EntityStruct {
  final marker = Field.int32();

  /// Waits, then writes. The write is the whole point: it has to land.
  Iterable stamp(Entity self, int value) sync* {
    yield null;
    marker[self] = value;
  }
}

class _Scene extends SceneStruct {
  late final _Mover mover;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    mover = descriptor.has(_Mover.new);
  }
}

class _State extends GameState<_Game> {
  @override
  void onMounted() => loadScene(_Scene());
}

class _Game extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 100);

  @override
  GameState createState() => _State();
}

/// A tenth of a second, matching [_Game.fixedTimeStep] exactly, so `advance`
/// affords exactly one step per call and the tests read as "one tick".
const Duration _step = Duration(milliseconds: 100);

Future<_Game> _boot() async {
  final game = await Game.startInline(_Game());
  addTearDown(() async {
    if (game.isRunning) await game.stop();
  });
  return game;
}

CoroutineScheduler _sched() => run.state.coroutines;

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  setUp(() {});

  group('stepping', () {
    test('a body does not run until the first tick', () async {
      run = await _boot();
      var ran = false;
      Iterable body() sync* {
        ran = true;
        yield null;
      }

      _sched().start(null, body());
      expect(
        ran,
        isFalse,
        reason:
            'starting is legal from outside the tick window precisely '
            'because nothing runs yet - the first advance is what runs it',
      );

      run.advance(_step);
      expect(ran, isTrue);
    });

    test('`yield null` resumes on the very next step', () async {
      run = await _boot();
      final seen = <int>[];
      Iterable body() sync* {
        seen.add(1);
        yield null;
        seen.add(2);
        yield null;
        seen.add(3);
      }

      _sched().start(null, body());
      run.advance(_step);
      expect(seen, [1]);
      run.advance(_step);
      expect(seen, [1, 2]);
      run.advance(_step);
      expect(seen, [1, 2, 3]);
    });

    test('`yield 0.25` waits that many simulated seconds', () async {
      run = await _boot();
      var resumed = false;
      Iterable body() sync* {
        yield 0.25;
        resumed = true;
      }

      _sched().start(null, body());
      run.advance(_step); // runs the body, which sets the wait to 0.25
      expect(resumed, isFalse);
      run.advance(_step); // 0.15 left
      expect(resumed, isFalse);
      run.advance(_step); // 0.05 left - still waiting
      expect(
        resumed,
        isFalse,
        reason:
            'a wait never ends early: 0.25s at 10 Hz costs three waiting '
            'steps, not two. Rounding the other way would let a "quarter '
            'second" fire at 0.2s, so a tuned animation would land right on '
            'one tick rate and wrong on another',
      );
      run.advance(_step); // past 0.25
      expect(
        resumed,
        isTrue,
        reason:
            'simulated seconds, accumulated from fixedTimeStep - so this '
            'is deterministic and has nothing to do with wall clock',
      );
    });

    test('`yield 0` still gives the tick back rather than spinning', () async {
      run = await _boot();
      var iterations = 0;
      Iterable body() sync* {
        while (iterations < 3) {
          iterations++;
          yield 0;
        }
      }

      _sched().start(null, body());
      run.advance(_step);
      expect(
        iterations,
        1,
        reason:
            'a non-positive wait means "next step", not "keep going" - '
            'otherwise this loop would run to completion inside one tick, '
            'and a `while (true)` one would hang the simulation',
      );
    });
  });

  group('composition', () {
    test('a coroutine can yield another and waits for it', () async {
      run = await _boot();
      final seen = <String>[];
      Iterable inner() sync* {
        seen.add('inner-a');
        yield null;
        seen.add('inner-b');
      }

      Iterable outer() sync* {
        seen.add('outer-a');
        yield inner();
        seen.add('outer-b');
      }

      _sched().start(null, outer());
      run.advance(_step);
      expect(seen, ['outer-a', 'inner-a']);
      run.advance(_step);
      expect(
        seen,
        ['outer-a', 'inner-a', 'inner-b', 'outer-b'],
        reason:
            'the inner body finishing resumes the outer one on the same '
            'step - nesting is a stack, not a separate coroutine',
      );
    });

    test(
      'WaitUntil is polled, and costs no extra step when already true',
      () async {
        run = await _boot();
        var gate = false;
        var passed = false;
        Iterable body() sync* {
          yield WaitUntil(() => gate);
          passed = true;
        }

        _sched().start(null, body());
        run.advance(_step);
        expect(passed, isFalse);
        gate = true;
        run.advance(_step);
        expect(passed, isTrue);
      },
    );

    test(
      'a yield the scheduler cannot read fails the coroutine, not the tick',
      () async {
        run = await _boot();
        Iterable body() sync* {
          yield 'half past three';
        }

        final handle = _sched().start(null, body());
        expect(
          () => run.advance(_step),
          returnsNormally,
          reason: 'one broken coroutine must not take the simulation with it',
        );
        await expectLater(
          handle,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('means nothing'),
            ),
          ),
        );
      },
    );
  });

  group('lifetime', () {
    test('the handle completes when the body runs out', () async {
      run = await _boot();
      Iterable body() sync* {
        yield null;
      }

      final handle = _sched().start(null, body());
      var completed = false;
      unawaited(handle.then((_) => completed = true));

      run.advance(_step);
      expect(handle.isDone, isFalse);
      run.advance(_step);
      expect(handle.isDone, isTrue);
      await handle;
      expect(completed, isTrue);
    });

    test('stop() ends it without an error, and it stops writing', () async {
      run = await _boot();
      var writes = 0;
      Iterable body() sync* {
        while (true) {
          writes++;
          yield null;
        }
      }

      final handle = _sched().start(null, body());
      run.advance(_step);
      expect(writes, 1);

      handle.stop();
      run.advance(_step);
      expect(writes, 1, reason: 'stopped means stopped');
      await handle; // completes normally - cancelling is not a failure
      expect(_sched().length, 0);
    });

    test(
      'stopAllCoroutines is scoped to the prefab that started them',
      () async {
        run = await _boot();
        final scene = run.state.singleScene<_Scene>();
        final other = Object();
        Iterable body() sync* {
          while (true) {
            yield null;
          }
        }

        scene.mover.startCoroutine(body);
        scene.mover.startCoroutine(body);
        _sched().start(other, body());
        expect(_sched().length, 3);

        scene.mover.stopAllCoroutines();
        expect(
          _sched().length,
          1,
          reason: "someone else's coroutine is not this prefab's to stop",
        );
      },
    );

    test('a coroutine can stop itself from inside its own body', () async {
      run = await _boot();
      late CoroutineFuture handle;
      var after = false;
      Iterable body() sync* {
        handle.stop();
        yield null;
        after = true;
      }

      handle = _sched().start(null, body());
      run.advance(_step);
      run.advance(_step);
      expect(
        after,
        isFalse,
        reason:
            'the scheduler walks a snapshot, so removing an entry '
            'mid-step is safe rather than a concurrent-modification crash',
      );
      expect(_sched().length, 0);
    });
  });

  group('the reason this is sync* and not async*', () {
    test('a write after a yield actually lands in the row', () async {
      run = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final entity = run.state.loadedScenes.single.addEntity(scene.mover);

      scene.mover.startCoroutine(() => scene.mover.stamp(entity, 42));
      run.advance(_step); // runs up to the yield
      run.advance(_step); // resumes and writes

      expect(
        scene.mover.marker[entity],
        42,
        reason:
            'this is the whole design. `sync*` resumes inside the tick '
            'window, so the write is between beginTick and commitTick and '
            'survives; an async* body would resume on a microtask after '
            'commitTick and this would read 0',
      );
    });

    test(
      'an async* body genuinely cannot do that - shown, not assumed',
      () async {
        run = await _boot();
        final scene = run.state.singleScene<_Scene>();
        final entity = run.state.loadedScenes.single.addEntity(scene.mover);
        final pool = run.state.pool;

        // The async* equivalent of `stamp`, driven the only way a Stream can be
        // driven: by awaiting it. The await is what hands control back to the
        // event loop, and the event loop is what runs the rest *outside* any
        // tick - which is precisely what this engine forbids.
        final resumed = Completer<void>();
        Stream<void> asyncBody() async* {
          yield null;
          expect(
            pool.isTickOpen,
            isFalse,
            reason:
                'the point: by the time an async* body resumes, the tick '
                'that could have accepted its write is closed',
          );
          resumed.complete();
        }

        run.advance(_step);
        await asyncBody().drain<void>();
        await resumed.future;

        expect(
          scene.mover.marker[entity],
          0,
          reason:
              'nothing was written, because nothing could have been - '
              'which is why Coroutine is an Iterable and not a Stream',
        );
      },
    );
  });
}
