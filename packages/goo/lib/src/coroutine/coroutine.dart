import 'dart:async';

typedef Coroutine = Stream<FutureOr<double?>> Function();
typedef CoroutineWithParam<T> = Stream<FutureOr<double?>> Function(T param);
mixin Coroutines {
  // returns a custom implementation of Future that holds coroutine information
  // for [stopCoroutine] to use.
  CoroutineFuture startCoroutine(Coroutine coroutine);
  CoroutineFuture startCoroutineWithParam<T>(
    CoroutineWithParam<T> coroutine, {
    required T param,
  });
  void stopCoroutine(CoroutineFuture coroutine);
  void stopCoroutines(
    Function coroutine,
  ); // local to this mixin, does not stop all coroutines globally
  void
  stopAllCoroutines(); // local to this mixin, does not stop all coroutines globally

  void testApi() {
    final instance = startCoroutine(_myCoroutine);
    instance.stop();
    stopCoroutine(instance);
  }

  Stream<FutureOr<double?>> _myCoroutine() async* {
    yield 1.0; // wait for 1 second
    yield null; // wait for next frame
  }
}

abstract class CoroutineFuture implements Future<void> {
  Coroutine get coroutine;
  void stop();
}

abstract class YieldInstruction implements Future<double?> {}

mixin YieldInstructionDelegateFuture on YieldInstruction {
  Future<double?> get delegate;

  @override
  Stream<double?> asStream() {
    return delegate.asStream();
  }

  @override
  Future<double?> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) {
    return delegate.catchError(onError, test: test);
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(double? value) onValue, {
    Function? onError,
  }) {
    return delegate.then(onValue, onError: onError);
  }

  @override
  Future<double?> timeout(
    Duration timeLimit, {
    FutureOr<double?> Function()? onTimeout,
  }) {
    return delegate.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<double?> whenComplete(FutureOr<void> Function() action) {
    return delegate.whenComplete(action);
  }
}
