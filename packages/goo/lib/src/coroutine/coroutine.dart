import 'dart:async';

import 'package:meta/meta.dart';

import 'package:goo/src/game_state.dart';

/// A resumable piece of gameplay logic, written as a `sync*` generator.
///
/// ```dart
/// Iterable entrance(Entity self) sync* {
///   yield 0.5;                    // wait half a simulated second
///   opacity[self] = 1.0;
///   yield null;                   // wait one fixed step
///   yield WaitUntil(() => landed);
///   playSound(self);
/// }
/// ```
///
/// # Why `sync*` and not `async*`
///
/// This looked like `Stream<FutureOr<double?>> Function()` first, which is the
/// obvious Dart spelling and is **wrong here** for a reason that has nothing to
/// do with style. An `async*` generator resumes on a *microtask*, and this
/// engine requires every component write to land between `MemoryPool.beginTick`
/// and `commitTick` - `data_layout.dart` asserts it, because `beginTick` copies
/// the last published snapshot over the write slot and would silently discard
/// anything written outside that window.
///
/// A coroutine exists to write component data after waiting. Under `async*`
/// every one of those writes lands on a microtask after `commitTick` and is
/// therefore thrown away: silently in release, on an assert in debug. Not
/// intermittently - every time, for every write after the first `yield`.
///
/// `sync*` resumes synchronously, so [CoroutineScheduler.step] can drive it
/// from inside the tick window and the writes land where they must. It is also
/// what Unity's `IEnumerator` has always been, for what is probably the same
/// reason.
///
/// # What a yield may be
///
///  * `null` - resume on the next fixed step.
///  * a `num` - resume after that many **simulated** seconds, accumulated from
///    `Game.fixedTimeStep`. Simulated rather than wall-clock, so a coroutine
///    replays identically; `Future.delayed` would not.
///  * a [YieldInstruction] - resume when it says so, polled once per step.
///  * another `Iterable` - run it to completion first, then carry on. Nesting
///    is a plain stack, so a coroutine can be composed of coroutines without
///    either knowing about the other.
///
/// Anything else is a programming error and throws, rather than being silently
/// treated as "next frame".
///
/// The element type is left off deliberately. A coroutine yields a mixed bag by
/// design - a null, a number, an instruction, another coroutine - so there is
/// no element type worth writing, and `Iterable` is both shorter and more
/// honest than pinning it to `Object?`.
typedef Coroutine = Iterable Function();

/// A [Coroutine] that takes one argument, so a caller can start the same body
/// for several entities without a closure per start.
typedef CoroutineWithParam<T> = Iterable Function(T param);

/// Something a coroutine waits on, polled once per fixed step.
///
/// Polled rather than callback-driven, and that follows from the same
/// constraint as `sync*`: resumption has to happen inside the tick window, so
/// "tell me when you are ready" cannot be a `Future.then` that fires whenever
/// it likes. Once per step, on the simulation's own clock, is the only shape
/// that keeps a coroutine's writes legal.
abstract class YieldInstruction {
  /// Called once per fixed step with the simulated time that passed. Returns
  /// true when the wait is over; the coroutine resumes on that same step.
  bool advance(double seconds);
}

/// Waits until [condition] first returns true, checked once per fixed step.
final class WaitUntil implements YieldInstruction {
  WaitUntil(this.condition);

  final bool Function() condition;

  @override
  bool advance(double seconds) => condition();
}

/// Waits while [condition] keeps returning true - the mirror of [WaitUntil],
/// spelled out rather than left to the caller to negate, because
/// `WaitUntil(() => !busy)` reads worse than `WaitWhile(() => busy)`.
final class WaitWhile implements YieldInstruction {
  WaitWhile(this.condition);

  final bool Function() condition;

  @override
  bool advance(double seconds) => !condition();
}

/// Waits for a real `Future` - an asset load, a network reply.
///
/// The future completes whenever it likes, on a microtask; what this does is
/// record that and report it on the next fixed step, so the coroutine still
/// resumes inside the tick window. The one-step latency is the price of that
/// and is not worth removing.
///
/// An error on the future is rethrown into the coroutine's own completion, so
/// an asset that fails to load surfaces at the `await` on the handle rather
/// than hanging it forever.
final class WaitForFuture implements YieldInstruction {
  WaitForFuture(Future<void> future) {
    future.then<void>(
      (_) => _done = true,
      // ignore: avoid_types_on_closure_parameters
      onError: (Object error, StackTrace stack) {
        _done = true;
        _error = error;
        _stack = stack;
      },
    );
  }

  bool _done = false;
  Object? _error;
  StackTrace? _stack;

  @override
  bool advance(double seconds) {
    final error = _error;
    if (error != null) {
      _error = null;
      Error.throwWithStackTrace(error, _stack ?? StackTrace.current);
    }
    return _done;
  }
}

/// A started coroutine: something to await, and something to stop.
///
/// Implements `Future<void>` so `await startCoroutine(...)` reads the way a
/// caller expects, and completes when the body runs out - or completes with an
/// error when the body throws, which is what stops a bug inside a coroutine
/// from being swallowed by the scheduler.
///
/// [stop] completes it normally rather than with an error: cancelling
/// something is not a failure, and a caller who awaited it wants to carry on.
final class CoroutineFuture implements Future<void> {
  @internal
  CoroutineFuture(this._scheduler);

  final CoroutineScheduler _scheduler;
  final Completer<void> _completer = Completer<void>();

  /// Whether the body has run out, thrown, or been stopped.
  bool get isDone => _completer.isCompleted;

  /// Cancels it. Idempotent, and safe to call from inside the coroutine's own
  /// body - the scheduler walks a snapshot, so removing an entry mid-step
  /// cannot disturb the walk.
  void stop() => _scheduler.stop(this);

  @internal
  void completeNormally() {
    if (!_completer.isCompleted) _completer.complete();
  }

  @internal
  void completeWithError(Object error, StackTrace stack) {
    if (!_completer.isCompleted) _completer.completeError(error, stack);
  }

  @override
  Stream<void> asStream() => _completer.future.asStream();

  @override
  Future<void> catchError(Function onError, {bool Function(Object)? test}) =>
      _completer.future.catchError(onError, test: test);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(void value) onValue, {
    Function? onError,
  }) => _completer.future.then(onValue, onError: onError);

  @override
  Future<void> timeout(
    Duration timeLimit, {
    FutureOr<void> Function()? onTimeout,
  }) => _completer.future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<void> whenComplete(FutureOr<void> Function() action) =>
      _completer.future.whenComplete(action);
}

/// One running coroutine, and its stack of nested ones.
final class _Running {
  _Running(this.owner, this.handle, Iterable body) {
    _stack.add(body.iterator);
  }

  final Object? owner;
  final CoroutineFuture handle;

  /// Innermost last. A `yield someOtherCoroutine()` pushes; running out pops.
  final List<Iterator> _stack = <Iterator>[];

  /// Simulated seconds still to wait, for a bare `yield 1.5`. A field rather
  /// than a `WaitForSeconds` object so the overwhelmingly common wait costs no
  /// allocation at all - the exception granted for *starting* a coroutine does
  /// not need to extend to every yield inside one.
  double _wait = 0;
  YieldInstruction? _blocked;

  /// Runs this coroutine forward by [seconds]. Returns false when it is done.
  ///
  /// Resumes at most once per step even if the yielded wait was shorter than
  /// one: a coroutine that yielded `0.001` must not run a hundred times in a
  /// single tick, and one that yields inside a loop must not spin.
  ///
  /// A wait **never ends early**, so it costs `ceil(wait / fixedTimeStep)`
  /// steps and the coroutine resumes on the first step at or past it. At 10 Hz
  /// a `yield 0.25` therefore resumes after three waiting steps (0.3s), not
  /// two - rounding the other way would let a "quarter second" fire at 0.2s,
  /// which is the kind of thing that makes a tuned animation land wrong on one
  /// tick rate and right on another.
  bool step(double seconds) {
    if (_wait > 0) {
      _wait -= seconds;
      if (_wait > 0) return true;
    }
    final blocked = _blocked;
    if (blocked != null) {
      if (!blocked.advance(seconds)) return true;
      _blocked = null;
    }

    while (_stack.isNotEmpty) {
      final iterator = _stack.last;
      if (!iterator.moveNext()) {
        // This level ran out; resume whatever pushed it.
        _stack.removeLast();
        continue;
      }
      final Object? yielded = iterator.current;
      if (yielded == null) return true; // next step
      if (yielded is num) {
        // A non-positive wait is still "next step", not "keep going": a
        // `yield 0` inside a loop would otherwise never give the tick back.
        _wait = yielded.toDouble();
        return true;
      }
      if (yielded is YieldInstruction) {
        // Polled immediately, so `WaitUntil(() => true)` costs no extra step.
        if (yielded.advance(0)) continue;
        _blocked = yielded;
        return true;
      }
      if (yielded is Iterable) {
        _stack.add(yielded.iterator);
        continue;
      }
      throw StateError(
        'a coroutine yielded ${yielded.runtimeType}, which means nothing to '
        'the scheduler. Yield null (next step), a num (simulated seconds), a '
        'YieldInstruction, or another coroutine to run first.',
      );
    }
    return false;
  }
}

/// Runs every live coroutine, once per fixed step, inside the tick window.
///
/// One per `GameState` rather than one per owner: a single list is one
/// deterministic order, and "stop everything this enemy started" is a filter
/// over it rather than a second place for the same fact to live (RULES.md rule
/// 10). Owners are compared by identity and never used for anything else, so a
/// prefab, a system or a scene can all own coroutines without the scheduler
/// knowing what any of them are.
final class CoroutineScheduler {
  final List<_Running> _running = <_Running>[];

  /// Reused across steps so a tick with live coroutines allocates nothing.
  /// Walking a copy is what lets a coroutine start or stop coroutines - its
  /// own included - from inside its own body.
  final List<_Running> _stepping = <_Running>[];

  /// How many coroutines are live. Diagnostics and tests.
  int get length => _running.length;

  /// Starts [body] and returns a handle to await or stop.
  ///
  /// The body does **not** run here. It first advances on the next fixed step,
  /// which is what keeps starting a coroutine legal from anywhere - including
  /// from outside the tick window, where its first write would not have been.
  CoroutineFuture start(Object? owner, Iterable body) {
    final handle = CoroutineFuture(this);
    _running.add(_Running(owner, handle, body));
    return handle;
  }

  /// Stops one. Idempotent; completes the handle normally.
  void stop(CoroutineFuture handle) {
    for (var i = 0; i < _running.length; i++) {
      if (identical(_running[i].handle, handle)) {
        _running.removeAt(i);
        handle.completeNormally();
        return;
      }
    }
  }

  /// Stops everything [owner] started, and nothing else.
  void stopAllOf(Object? owner) {
    for (var i = _running.length - 1; i >= 0; i--) {
      if (identical(_running[i].owner, owner)) {
        _running.removeAt(i).handle.completeNormally();
      }
    }
  }

  /// Stops every coroutine in this game.
  void stopAll() {
    for (var i = 0; i < _running.length; i++) {
      _running[i].handle.completeNormally();
    }
    _running.clear();
  }

  /// Advances every live coroutine by [seconds] of simulated time.
  ///
  /// Called from `GameState.runFixedStep`, inside `beginTick`/`commitTick`,
  /// which is the whole point - see [Coroutine]'s doc on `sync*`.
  void step(double seconds) {
    if (_running.isEmpty) return;
    _stepping
      ..clear()
      ..addAll(_running);

    for (var i = 0; i < _stepping.length; i++) {
      final running = _stepping[i];
      if (running.handle.isDone) continue; // stopped mid-step by someone else
      bool alive;
      try {
        alive = running.step(seconds);
      } catch (error, stack) {
        _remove(running);
        // Surfaced on the handle rather than rethrown into the tick: one
        // broken coroutine must not take the simulation down with it, and a
        // caller that awaited it is the right place for the failure to land.
        running.handle.completeWithError(error, stack);
        continue;
      }
      if (!alive) {
        _remove(running);
        running.handle.completeNormally();
      }
    }
    _stepping.clear();
  }

  void _remove(_Running running) {
    for (var i = 0; i < _running.length; i++) {
      if (identical(_running[i], running)) {
        _running.removeAt(i);
        return;
      }
    }
  }
}

/// Opts an owner into starting and stopping coroutines.
///
/// ```dart
/// class Enemy extends EntityStruct with Transform2D, Coroutines {
///   void enter(Entity self) => startCoroutine(() => _enter(self));
///
///   Iterable _enter(Entity self) sync* {
///     yield 0.25;
///     transformOffsetY[self] = 0;
///   }
/// }
/// ```
///
/// **Nothing to mix in.** `EntityStruct`, `SceneStruct`, `GameSystem` and
/// `GameState` already have it - the four things that own gameplay logic on
/// the simulating copy, and exactly the four that can reach a scheduler. A
/// prefab just calls `startCoroutine(...)`.
///
/// The requirement is [simulationState], declared abstract on this mixin and
/// implemented by each host. An `on SimulationScoped` bound was tried first
/// and cannot work: an `on` clause is checked against the applying class's
/// **superclass**, and none of the four has one that supplies a `GameState` -
/// so none of them could have mixed this in, and every user would have had to
/// write `with Coroutines` themselves.
///
/// Before that it was a chain of `is` tests asking "am I a GameState? a
/// GameSystem?", which is now RULES.md rule 11: it compiled for hosts it did
/// not handle and failed at runtime, where an unimplemented mixin member fails
/// to compile.
///
/// Everything here is scoped to **this owner**: [stopAllCoroutines] stops what
/// this object started and nothing else. Note that a prefab is shared by every
/// entity of its archetype, so coroutines started for two different entities
/// have the same owner - where that distinction matters, keep the handle.
mixin Coroutines {
  /// The simulation this owner belongs to, supplied by whichever of the four
  /// hosts this was mixed into: a `GameState` is one, a `GameSystem` and a
  /// `SceneStruct` have one, and a prefab reaches one through its scene.
  ///
  /// Abstract *here*, which is the whole mechanism: a mixin's unimplemented
  /// member becomes a requirement on the class applying it, so the four hosts
  /// satisfy it and anything else fails to compile. No separate interface and
  /// no `is` chain - see the class doc.
  @protected
  GameState get simulationState;

  CoroutineScheduler get _scheduler => simulationState.coroutines;

  /// Starts [coroutine] and returns a handle to await or stop.
  ///
  /// The body first advances on the next fixed step, never here - so this is
  /// safe to call from anywhere, including from outside the tick window.
  CoroutineFuture startCoroutine(Coroutine coroutine) =>
      _scheduler.start(this, coroutine());

  /// [startCoroutine] for a body that takes an argument, so the same
  /// coroutine can be started for many entities without a closure per start.
  CoroutineFuture startCoroutineWithParam<T>(
    CoroutineWithParam<T> coroutine, {
    required T param,
  }) => _scheduler.start(this, coroutine(param));

  /// Stops one. Idempotent.
  void stopCoroutine(CoroutineFuture coroutine) => coroutine.stop();

  /// Stops every coroutine **this owner** started. Others keep running.
  void stopAllCoroutines() => _scheduler.stopAllOf(this);
}
