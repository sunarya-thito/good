import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:goo2d/goo2d.dart';
import 'package:meta/meta.dart';

/// A function signature for coroutines that execute logic over multiple frames.
///
/// Coroutines use Dart's [Stream] as a sequence of yield instructions. Each
/// yielded value (e.g., [YieldInstruction], [Future], or null) determines
/// how long the engine should wait before resuming the coroutine logic.
typedef CoroutineFunction = Stream Function();

/// A function signature for coroutines that accept initial configuration data.
///
/// This allows for reusable coroutine logic that depends on external state
/// (e.g., a fade effect that needs a target duration and opacity).
///
/// * [T]: The type of the option object passed to the coroutine.
typedef CoroutineFunctionWithOptions<T> = Stream Function(T option);

const _currentCoroutineKey = Object();

/// Accesses the [Future] of the currently executing coroutine.
///
/// This is used within a coroutine to identify its own lifecycle or to
/// wait for its completion recursively. It utilizes [Zone] values to
/// track the execution context.
///
/// Throws an assertion error if called outside of a coroutine context.
Future<void> get currentCoroutine {
  final coroutine = Zone.current[_currentCoroutineKey];
  assert(
    coroutine is CoroutineFuture,
    'Not in a coroutine. Start a coroutine with startCoroutine()',
  );
  return coroutine as CoroutineFuture;
}

@internal
class CoroutineFuture implements Future<void> {
  late Future<void> delegate;
  final Object coroutine;
  CoroutineFuture(this.coroutine);

  @override
  Stream<void> asStream() {
    return delegate.asStream();
  }

  @override
  Future<void> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) {
    return delegate.catchError(onError, test: test);
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(void value) onValue, {
    Function? onError,
  }) {
    return delegate.then(onValue, onError: onError);
  }

  @override
  Future<void> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) {
    return delegate.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<void> whenComplete(FutureOr<dynamic> Function() action) {
    return delegate.whenComplete(action);
  }
}

/// A timing source that drives coroutine frame synchronization.
///
/// [CoroutineClock] is the only timing primitive the coroutine system
/// requires. Implement this to provide a custom frame signal source.
///
/// The engine supplies [TickerSystem] as the game-context implementation.
/// A [CoroutineRunner] created without explicit clock uses a Flutter
/// scheduler-based fallback, enabling coroutines outside the game widget tree.
///
/// See also:
/// * [CoroutineRunner], which uses a [CoroutineClock] to run global coroutines.
/// * [WaitForEndOfFrame], which awaits [nextFrame] each yield.
abstract class CoroutineClock {
  /// A future that completes when the next frame has been processed.
  Future<void> get nextFrame;
}

// Flutter scheduler-based fallback clock — used by CoroutineRunner.instance
// when no game engine is active.
class _FlutterCoroutineClock implements CoroutineClock {
  static final instance = _FlutterCoroutineClock._();
  _FlutterCoroutineClock._();

  final _controller = StreamController<void>.broadcast();
  bool _frameScheduled = false;

  void _scheduleFrame() {
    if (_frameScheduled) return;
    _frameScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      _controller.add(null);
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  @override
  Future<void> get nextFrame {
    _scheduleFrame();
    return _controller.stream.first;
  }
}

/// The base class for all instructions that pause a coroutine's execution.
///
/// Yield instructions allow developers to express complex timing and
/// synchronization logic in a linear, readable way within a [Stream]-based
/// coroutine.
///
/// ```dart
/// class MyWait extends YieldInstruction {
///   @override
///   Future<void> wait(CoroutineClock clock) async {
///     // Custom wait logic using clock.nextFrame
///   }
/// }
/// ```
///
/// See also:
/// * [WaitForSeconds], for time-based pauses.
/// * [WaitForEndOfFrame], for frame-synchronization.
abstract class YieldInstruction {
  /// Internal method used by the engine to wait for the instruction's condition.
  ///
  /// * [clock]: The timing source providing frame synchronization.
  Future<void> wait(CoroutineClock clock);
}

/// A yield instruction that pauses a coroutine for a specific duration.
///
/// Use this for non-precise delays like waiting for an animation to finish
/// or staggering enemy spawns.
///
/// ```dart
/// Stream example() async* {
///   print('Wait start');
///   yield WaitForSeconds(2.5);
///   print('2.5 seconds later');
/// }
/// ```
///
/// See also:
/// * [WaitForEndOfFrame], for frame-by-frame precision.
class WaitForSeconds extends YieldInstruction {
  /// The duration to wait, in seconds.
  ///
  /// This value is used to calculate the millisecond delay passed to the
  /// underlying async timer.
  final double seconds;

  /// Creates an instruction that waits for the specified [seconds].
  ///
  /// * [seconds]: The duration of the pause.
  WaitForSeconds(this.seconds);

  @override
  Future<void> wait(CoroutineClock clock) async {
    await Future.delayed(Duration(milliseconds: (seconds * 1000).toInt()));
  }
}

/// A yield instruction that pauses a coroutine until the next frame is rendered.
///
/// This is used to synchronize logic with the engine's main render loop,
/// ensuring that calculations happen once per frame.
///
/// ```dart
/// Stream example() async* {
///   while(true) {
///     yield WaitForEndOfFrame();
///     print('Next frame reached');
///   }
/// }
/// ```
///
/// See also:
/// * [WaitForSeconds], for time-based pauses.
class WaitForEndOfFrame extends YieldInstruction {
  @override
  Future<void> wait(CoroutineClock clock) async {
    await clock.nextFrame;
  }
}

/// A yield instruction that pauses until a specific condition becomes true.
///
/// This is useful for waiting for external events or state changes without
/// manually checking every frame.
///
/// ```dart
/// bool playerIsDead = false;
/// Stream example() async* {
///   yield WaitUntil(() => playerIsDead);
///   print('Game Over');
/// }
/// ```
///
/// See also:
/// * [WaitWhile], the inverse of this instruction.
class WaitUntil extends YieldInstruction {
  /// The condition to check every frame.
  ///
  /// The coroutine will remain suspended as long as this function returns
  /// false, checking it once per frame update.
  final bool Function() predicate;

  /// Creates an instruction that waits until the [predicate] returns true.
  ///
  /// * [predicate]: The condition function.
  WaitUntil(this.predicate);

  @override
  Future<void> wait(CoroutineClock clock) async {
    while (!predicate()) {
      await clock.nextFrame;
    }
  }
}

/// A yield instruction that pauses as long as a specific condition remains true.
///
/// This is used to stall a coroutine while a certain state persists (e.g.,
/// waiting for a loading screen to close).
///
/// ```dart
/// bool isLoading = true;
/// Stream example() async* {
///   yield WaitWhile(() => isLoading);
///   print('Loading complete');
/// }
/// ```
///
/// See also:
/// * [WaitUntil], which waits for a condition to become true.
class WaitWhile extends YieldInstruction {
  /// The condition to check every frame.
  ///
  /// The coroutine will remain suspended as long as this function returns
  /// true, checking it once per frame update.
  final bool Function() predicate;

  /// Creates an instruction that waits while the [predicate] returns true.
  ///
  /// * [predicate]: The condition function.
  WaitWhile(this.predicate);

  @override
  Future<void> wait(CoroutineClock clock) async {
    while (predicate()) {
      await clock.nextFrame;
    }
  }
}

void _runCoroutine(
  CoroutineFuture result,
  Stream yields,
  List<CoroutineFuture> runningCoroutines,
  CoroutineClock clock,
) {
  result.delegate = Future(() async {
    runningCoroutines.add(result);
    await runZoned(() async {
      Future<void> processYields(Stream stream) async {
        await for (final instruction in stream) {
          if (!runningCoroutines.contains(result)) break;

          switch (instruction) {
            case YieldInstruction():
              await instruction.wait(clock);
              break;
            case Future():
              await instruction;
              break;
            case Stream():
              await processYields(instruction);
              break;
            case null:
              try {
                await clock.nextFrame;
              } catch (_) {
                // Clock disposed
                return;
              }
              break;
          }
          if (!runningCoroutines.contains(result)) break;
        }
      }

      await processYields(yields);
    }, zoneValues: {_currentCoroutineKey: result});
    runningCoroutines.remove(result);
  });
}

/// Manages a set of coroutines driven by a [CoroutineClock].
///
/// [CoroutineRunner.instance] is the global singleton backed by Flutter's
/// scheduler, allowing coroutines to run anywhere in a Flutter app without
/// needing a [GameEngine]. For convenience, the top-level [startCoroutine]
/// and related functions delegate to this instance.
///
/// A custom runner with a different clock can be created for specialized use:
///
/// ```dart
/// final myRunner = CoroutineRunner(clock: myCustomClock);
/// myRunner.startCoroutine(myCoroutine);
/// ```
///
/// See also:
/// * [startCoroutine], the top-level convenience function.
/// * [CoroutineClock], the timing source interface.
class CoroutineRunner {
  /// The global singleton backed by Flutter's [SchedulerBinding].
  ///
  /// Use this (or the top-level [startCoroutine] functions) to run coroutines
  /// outside the game engine widget tree.
  static final instance = CoroutineRunner();

  /// Creates a runner using the given [clock], or Flutter's scheduler if omitted.
  CoroutineRunner({CoroutineClock? clock})
    : _clock = clock ?? _FlutterCoroutineClock.instance;

  final CoroutineClock _clock;
  final List<CoroutineFuture> _running = [];

  /// Starts a coroutine and returns a future that completes when it finishes.
  Future<void> startCoroutine(CoroutineFunction coroutine) {
    final future = CoroutineFuture(coroutine);
    _runCoroutine(future, coroutine(), _running, _clock);
    return future;
  }

  /// Starts a coroutine that accepts an [option] value.
  Future<void> startCoroutineWithOption<T>(
    CoroutineFunctionWithOptions<T> coroutine, {
    required T option,
  }) {
    final future = CoroutineFuture(coroutine);
    _runCoroutine(future, coroutine(option), _running, _clock);
    return future;
  }

  /// Stops a specific coroutine returned by [startCoroutine].
  void stopCoroutine(Future<void> coroutine) {
    if (coroutine is CoroutineFuture) {
      _running.remove(coroutine);
    }
  }

  /// Stops all running coroutines, or only those started with [coroutine].
  void stopAllCoroutines([Function? coroutine]) {
    if (coroutine != null) {
      _running.removeWhere((e) => e.coroutine == coroutine);
    } else {
      _running.clear();
    }
  }
}

/// Starts a global coroutine using Flutter's scheduler as the frame clock.
///
/// Works from any Flutter context — widgets, services, or anywhere —
/// without needing a [GameEngine]. Inside a [Component] or [GameObject],
/// prefer the instance method `startCoroutine()` for game-frame synchronization.
///
/// Returns a future that completes when the coroutine finishes or is stopped.
Future<void> startCoroutine(CoroutineFunction coroutine) =>
    CoroutineRunner.instance.startCoroutine(coroutine);

/// Starts a global coroutine that receives an [option] value.
///
/// See [startCoroutine] for details on global vs. game-context coroutines.
Future<void> startCoroutineWithOption<T>(
  CoroutineFunctionWithOptions<T> coroutine, {
  required T option,
}) => CoroutineRunner.instance.startCoroutineWithOption(
  coroutine,
  option: option,
);

/// Stops a specific global coroutine returned by [startCoroutine].
void stopCoroutine(Future<void> coroutine) =>
    CoroutineRunner.instance.stopCoroutine(coroutine);

/// Stops all global coroutines, or only those started with [coroutine].
void stopAllCoroutines([Function? coroutine]) =>
    CoroutineRunner.instance.stopAllCoroutines(coroutine);

@internal
extension CoroutineInternal on GameObject {
  void setupCoroutine(
    CoroutineFuture result,
    Stream yields,
    List<CoroutineFuture> runningCoroutines,
  ) {
    _runCoroutine(result, yields, runningCoroutines, game.ticker);
  }
}
