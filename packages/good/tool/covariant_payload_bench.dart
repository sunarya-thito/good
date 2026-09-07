// #389: `EventDispatcher.call(E payload)` type-tests its argument on every
// dispatch, because `E` is a class type parameter and a class type parameter is
// covariant. Can that test be removed, and what does removing it cost?
//
// AOT ONLY. Compile and run:
//   dart compile exe packages/good/tool/covariant_payload_bench.dart -o build/cpb.exe
//   build/cpb.exe
//
// A `flutter test` bench is JIT, and JIT has been wrong about this codebase by
// roughly two orders of magnitude twice.
//
// # What the test is
//
// `EventDispatcher<L, Sub>` is a subtype of `EventDispatcher<L, Base>`, so a
// handle statically typed `EventDispatcher<L, Base>` can hold a dispatcher
// whose listeners take a `Sub`. Pushing a `Base` through it would hand a `Base`
// to something that declared it takes a `Sub`. Dart closes that hole by testing
// the argument, and `soundness` at the bottom of the run shows every shape here
// still closing it - none of them removes the test, they only move it.
//
// # Read the spread before reading the rows
//
// A row is the minimum of nine rounds inside one process. Run the binary a
// dozen times and a zero-listener row moves by about 1.2ns between runs, a
// one-listener row by about 3ns, an eight-listener row by 8-20ns. Anything
// smaller than that is not a difference this bench can see, and calling it one
// would be inventing a number. The comparisons below that matter are all either
// far outside that spread or entirely inside it, and which of the two is the
// whole result.
//
// # The mirror is the point of this bench
//
// `mirror` is `EventDispatcher.call` copied into this file, keeping the payload
// type parameter and the generic superclass the list lives in. `half` is that
// copy with the payload type written out concretely, so it has no covariant
// parameter at all. The two differ in exactly the thing #389 priced at five
// nanoseconds.
//
// They do not differ by five nanoseconds. Over twelve runs the gap is about
// 1.3ns at zero listeners against a 1.2ns spread, and about 2.5ns at one
// listener against a 3ns spread - inside the noise at every listener count.
// `mirror-ni` and `half-ni` are the same pair with `vm:never-inline` on `call`,
// because a test hoisted out of the caller's loop would show up as no test at
// all; out of line the two read within 0.05ns of each other at zero listeners.
//
// The five nanoseconds in #389's table was not the payload type parameter. That
// table read `EventDispatcher.call` at 7.31ns against a concrete-payload copy
// at 2.46ns. The 7.31 is not a property of `call`: the same source, the same
// `event.dart`, compiled with one unrelated class added to that same bench
// binary - changing nothing it measures - reads 3.2ns. Marking the shipped
// `call` `vm:never-inline` moves it by 0.4ns, so it is not inlining either.
// `EventDispatcher.call` at zero listeners has read 3.0, 3.4, 3.7 and 7.3ns in
// four binaries this spike built, and the copy that keeps the payload type
// parameter reads at the concrete-payload floor in all of them. That is stated
// rather than explained - what made that one binary's `call` cost twice what
// every other binary's does is not known, and no conclusion here rests on it.
//
// # Instantiated at more than one payload type
//
// `_pollute` builds every generic shape here at four other payload types and
// fires each once. Without it the whole program instantiates each of them
// exactly once, the compiler can prove the type arguments, and a bench for a
// type test would have no way to fail. A game has a dozen payload types, so
// that is also the honest program.
//
// # The rows
//
//   real      `EventDispatcher.call` as it ships
//   mirror    the same body, copied here, payload type parameter kept
//   mirror-ni `mirror` with `call` marked `vm:never-inline`
//   half      `mirror` with the payload type written out concretely
//   half-ni   `half` with `call` marked `vm:never-inline`
//   ext       no `call` on the class at all; `call` is an extension member, so
//             the payload type is a function type parameter and invariant, and
//             the test lands on the per-listener `deliver` call instead.
//             `d(payload)` and `d.call(payload)` both still resolve to it, so
//             it is the only shape here that keeps the call syntax and the
//             compile error together. It is also the one that costs the most:
//             the test it takes off the entry it pays once per listener, and it
//             pays it inside the guard, so a caller's wrong payload arrives as
//             the *listener* having thrown and the listener is disabled for it
//   ext-ni    `ext` with the extension member out of line
//   fn        a top-level `fire<L, E>(dispatcher, payload)` - the same
//             invariance without an extension, at the cost of the call syntax
//   fn-ni     `fn` out of line
//   mgen      `call` kept on the class with the payload type moved onto the
//             method: `void call<T extends E>(T payload)`. The bound `T extends
//             E` is checked against the instance's type arguments, so this
//             swaps a parameter test for a bound test and pays for the type
//             argument as well
//   obj       `void call(Object? payload)` with one `payload as E` at entry.
//             Not a candidate - the signature takes `Object?`, so a wrong
//             payload stops being a compile error - but it prices the "take
//             `Object?` and cast once" shape
//   field     `late final void Function(E payload) call`, a closure built in
//             the constructor. Also loses `d(payload)`: implicit invocation
//             resolves a `call` *method* and will not resolve a field
//   loop      the round with no dispatch at all: the `event.sourceEntity = i`
//             store every other row also pays

// `add` is `@internal` because a game never fills a dispatcher by hand - the
// boot pass does - and this bench has to stand where the boot pass stands.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:io';

import 'package:good/src/event.dart';

/// Dispatches per timed round.
const int _iterations = 2000000;

/// Rounds per row, reported as the minimum. A round can only be inflated by
/// noise, never deflated, so the minimum is the closest a wall clock gets to
/// "how much work is this".
const int _rounds = 9;

/// `Collision2DEvent`'s shape, repointed before each dispatch so the loop
/// cannot be hoisted out from under the measurement.
class ContactEvent {
  int sourceEntity = 0;
}

/// A payload type below [ContactEvent], so `soundness` can build a dispatcher
/// at the subtype, hold it at the supertype and push the wrong thing in.
class SubContactEvent extends ContactEvent {}

/// `CollisionListener`'s shape, cut down to the one method being timed.
mixin ContactListener on GameListener {
  void onContact(ContactEvent event);
}

/// A listener whose method takes the *sub*type, so a dispatch that skipped the
/// test would reach a method that cannot accept what it was given.
mixin SubContactListener on GameListener {
  void onSubContact(SubContactEvent event);
}

/// Read by every system, printed at the end, so no dispatch is dead code.
int _sink = 0;

/// True, but not until the program runs. Assigned into every system's
/// `_enabled` so the `listensToEvents` branch is a real load rather than a
/// constant the compiler folds - `GameSystem` reads a field there too.
final bool _liveTrue = DateTime.now().microsecondsSinceEpoch > 0;

/// False, but not until the program runs, so the `reverse` test is a branch on
/// a value and not a constant - `EventDispatcher.reverse` is a field read.
final bool _liveFalse = DateTime.now().microsecondsSinceEpoch < 0;

/// What a caught throw costs off the fast path. Out of line so the `catch`
/// block is a jump rather than a body, which is the shape `EventDispatcher`
/// already has - it records and reports after the loop.
@pragma('vm:never-inline')
void _caught(GameListener listener, Object error, StackTrace stack) {
  listener.disableAfterUncaught(error, stack);
  if (_quiet) return;
  stdout.writeln('$listener threw: $error');
  stdout.writeln('$stack');
}

// --- the systems ------------------------------------------------------------

// One class per listener, because a game's systems are different types and the
// dispatch walks a list of them. Bodies differ by a constant so nothing merges
// them, and each accumulates into its own field so eight cannot fold into one.

class _Sys0 extends GameListenerBase with ContactListener {
  _Sys0(this._enabled);

  final bool _enabled;
  int seen = 0;

  @override
  bool get listensToEvents => _enabled;

  @override
  void onContact(ContactEvent event) {
    seen += event.sourceEntity + 0;
    _sink = seen;
  }
}

class _Sys1 extends GameListenerBase with ContactListener {
  _Sys1(this._enabled);

  final bool _enabled;
  int seen = 0;

  @override
  bool get listensToEvents => _enabled;

  @override
  void onContact(ContactEvent event) {
    seen += event.sourceEntity + 1;
    _sink = seen;
  }
}

class _Sys2 extends GameListenerBase with ContactListener {
  _Sys2(this._enabled);

  final bool _enabled;
  int seen = 0;

  @override
  bool get listensToEvents => _enabled;

  @override
  void onContact(ContactEvent event) {
    seen += event.sourceEntity + 2;
    _sink = seen;
  }
}

class _Sys3 extends GameListenerBase with ContactListener {
  _Sys3(this._enabled);

  final bool _enabled;
  int seen = 0;

  @override
  bool get listensToEvents => _enabled;

  @override
  void onContact(ContactEvent event) {
    seen += event.sourceEntity + 3;
    _sink = seen;
  }
}

class _Sys4 extends GameListenerBase with ContactListener {
  _Sys4(this._enabled);

  final bool _enabled;
  int seen = 0;

  @override
  bool get listensToEvents => _enabled;

  @override
  void onContact(ContactEvent event) {
    seen += event.sourceEntity + 4;
    _sink = seen;
  }
}

class _Sys5 extends GameListenerBase with ContactListener {
  _Sys5(this._enabled);

  final bool _enabled;
  int seen = 0;

  @override
  bool get listensToEvents => _enabled;

  @override
  void onContact(ContactEvent event) {
    seen += event.sourceEntity + 5;
    _sink = seen;
  }
}

class _Sys6 extends GameListenerBase with ContactListener {
  _Sys6(this._enabled);

  final bool _enabled;
  int seen = 0;

  @override
  bool get listensToEvents => _enabled;

  @override
  void onContact(ContactEvent event) {
    seen += event.sourceEntity + 6;
    _sink = seen;
  }
}

class _Sys7 extends GameListenerBase with ContactListener {
  _Sys7(this._enabled);

  final bool _enabled;
  int seen = 0;

  @override
  bool get listensToEvents => _enabled;

  @override
  void onContact(ContactEvent event) {
    seen += event.sourceEntity + 7;
    _sink = seen;
  }
}

/// The listener `_pollute` hands to dispatchers built at other payload types,
/// and the one `soundness` builds its subtype dispatchers for.
class _AnySys extends GameListenerBase
    with ContactListener, SubContactListener {
  @override
  void onContact(ContactEvent event) {
    _sink += event.sourceEntity;
  }

  @override
  void onSubContact(SubContactEvent event) {
    _sink += event.sourceEntity;
  }
}

// --- the shapes -------------------------------------------------------------

/// `_ListenerSet`'s shape. Copied rather than reused because `_listeners` is
/// private to `event.dart` and an extension declared here cannot reach into
/// another library. Every shape below extends it, so none of them differs from
/// `mirror` in where the list lives.
abstract base class _Set<L extends GameListener> {
  final List<L> _listeners = <L>[];

  void add(L listener) => _listeners.add(listener);
}

/// `EventDispatcher`, copied. `real` minus `mirror` is what this file's copy
/// gets wrong, plus whatever the shipped class costs for not being local.
final class _Mirror<L extends GameListener, E> extends _Set<L> {
  _Mirror(this._deliver, {required this.reverse});

  final void Function(L listener, E payload) _deliver;
  final bool reverse;

  void call(E payload) {
    final listeners = _listeners;
    L? failed;
    Object? failure;
    StackTrace? failureStack;
    for (var n = 0; n < listeners.length; n++) {
      final listener = listeners[reverse ? listeners.length - 1 - n : n];
      if (!listener.listensToEvents) continue;
      try {
        _deliver(listener, payload);
      } catch (error, stack) {
        listener.disableAfterUncaught(error, stack);
        failed ??= listener;
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) _caught(failed!, failure, failureStack!);
  }
}

/// [_Mirror] with `call` kept out of line, so a test hoisted out of the
/// caller's loop cannot be mistaken for no test.
final class _MirrorNoInline<L extends GameListener, E> extends _Set<L> {
  _MirrorNoInline(this._deliver, {required this.reverse});

  final void Function(L listener, E payload) _deliver;
  final bool reverse;

  @pragma('vm:never-inline')
  void call(E payload) {
    final listeners = _listeners;
    L? failed;
    Object? failure;
    StackTrace? failureStack;
    for (var n = 0; n < listeners.length; n++) {
      final listener = listeners[reverse ? listeners.length - 1 - n : n];
      if (!listener.listensToEvents) continue;
      try {
        _deliver(listener, payload);
      } catch (error, stack) {
        listener.disableAfterUncaught(error, stack);
        failed ??= listener;
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) _caught(failed!, failure, failureStack!);
  }
}

/// [_Mirror] with the payload type written out concretely, so `call` has no
/// covariant parameter. The floor: what a dispatch would cost if the test could
/// be deleted outright rather than moved.
final class _Half<L extends GameListener> extends _Set<L> {
  _Half(this._deliver, {required this.reverse});

  final void Function(L listener, ContactEvent payload) _deliver;
  final bool reverse;

  void call(ContactEvent payload) {
    final listeners = _listeners;
    L? failed;
    Object? failure;
    StackTrace? failureStack;
    for (var n = 0; n < listeners.length; n++) {
      final listener = listeners[reverse ? listeners.length - 1 - n : n];
      if (!listener.listensToEvents) continue;
      try {
        _deliver(listener, payload);
      } catch (error, stack) {
        listener.disableAfterUncaught(error, stack);
        failed ??= listener;
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) _caught(failed!, failure, failureStack!);
  }
}

/// [_Half] out of line, to pair with [_MirrorNoInline].
final class _HalfNoInline<L extends GameListener> extends _Set<L> {
  _HalfNoInline(this._deliver, {required this.reverse});

  final void Function(L listener, ContactEvent payload) _deliver;
  final bool reverse;

  @pragma('vm:never-inline')
  void call(ContactEvent payload) {
    final listeners = _listeners;
    L? failed;
    Object? failure;
    StackTrace? failureStack;
    for (var n = 0; n < listeners.length; n++) {
      final listener = listeners[reverse ? listeners.length - 1 - n : n];
      if (!listener.listensToEvents) continue;
      try {
        _deliver(listener, payload);
      } catch (error, stack) {
        listener.disableAfterUncaught(error, stack);
        failed ??= listener;
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) _caught(failed!, failure, failureStack!);
  }
}

/// [_Mirror] with **no `call` at all**. The dispatch is the extension below, so
/// the payload type at the call is a function type parameter - invariant, and
/// inferred from the fire site's static type rather than read off the instance.
/// The test the entry stops doing lands on the per-listener `deliver` call.
final class _Ext<L extends GameListener, E> extends _Set<L> {
  _Ext(this.deliver, {required this.reverse});

  final void Function(L listener, E payload) deliver;
  final bool reverse;
}

extension _Dispatch<L extends GameListener, E> on _Ext<L, E> {
  void call(E payload) {
    final listeners = _listeners;
    L? failed;
    Object? failure;
    StackTrace? failureStack;
    for (var n = 0; n < listeners.length; n++) {
      final listener = listeners[reverse ? listeners.length - 1 - n : n];
      if (!listener.listensToEvents) continue;
      try {
        deliver(listener, payload);
      } catch (error, stack) {
        listener.disableAfterUncaught(error, stack);
        failed ??= listener;
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) _caught(failed!, failure, failureStack!);
  }

  /// `call` kept out of line, so `ext-ni` can ask whether anything the row wins
  /// is the body being inlined into a fire site that knows the static types.
  @pragma('vm:never-inline')
  void callNoInline(E payload) => call(payload);
}

/// The same invariance as [_Dispatch], reached through a top-level function
/// instead of an extension, so the call syntax can be priced separately from
/// the shape.
void _fire<L extends GameListener, E>(_Ext<L, E> dispatcher, E payload) =>
    dispatcher.call(payload);

@pragma('vm:never-inline')
void _fireNoInline<L extends GameListener, E>(
  _Ext<L, E> dispatcher,
  E payload,
) => dispatcher.call(payload);

/// `call` kept on the class, with the payload type moved off the class and onto
/// the method. `T` is a function type parameter, but its bound is not: `T
/// extends E` still has to be checked against the instance's type arguments.
final class _MGen<L extends GameListener, E> extends _Set<L> {
  _MGen(this._deliver, {required this.reverse});

  final void Function(L listener, E payload) _deliver;
  final bool reverse;

  void call<T extends E>(T payload) {
    final listeners = _listeners;
    L? failed;
    Object? failure;
    StackTrace? failureStack;
    for (var n = 0; n < listeners.length; n++) {
      final listener = listeners[reverse ? listeners.length - 1 - n : n];
      if (!listener.listensToEvents) continue;
      try {
        _deliver(listener, payload);
      } catch (error, stack) {
        listener.disableAfterUncaught(error, stack);
        failed ??= listener;
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) _caught(failed!, failure, failureStack!);
  }
}

/// `call(Object? payload)` with the cast written by hand, once, at entry. Not a
/// candidate - the signature takes `Object?`, so `dispatcher(anything)`
/// compiles - but it prices the "take `Object?` and cast where the type is
/// static" shape.
final class _Obj<L extends GameListener, E> extends _Set<L> {
  _Obj(this._deliver, {required this.reverse});

  final void Function(L listener, E payload) _deliver;
  final bool reverse;

  void call(Object? payload) {
    final typed = payload as E;
    final listeners = _listeners;
    L? failed;
    Object? failure;
    StackTrace? failureStack;
    for (var n = 0; n < listeners.length; n++) {
      final listener = listeners[reverse ? listeners.length - 1 - n : n];
      if (!listener.listensToEvents) continue;
      try {
        _deliver(listener, typed);
      } catch (error, stack) {
        listener.disableAfterUncaught(error, stack);
        failed ??= listener;
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) _caught(failed!, failure, failureStack!);
  }
}

/// `call` as a closure in a field, built once in the constructor. A closure's
/// parameter type is a function type parameter, so the entry is invariant the
/// same way the extension's is - at the cost of one closure per dispatcher and
/// of `dispatcher(payload)`, which resolves a `call` *method* and does not
/// resolve a field.
final class _Field<L extends GameListener, E> extends _Set<L> {
  _Field(this._deliver, {required this.reverse}) {
    call = (E payload) {
      final listeners = _listeners;
      L? failed;
      Object? failure;
      StackTrace? failureStack;
      for (var n = 0; n < listeners.length; n++) {
        final listener = listeners[reverse ? listeners.length - 1 - n : n];
        if (!listener.listensToEvents) continue;
        try {
          _deliver(listener, payload);
        } catch (error, stack) {
          listener.disableAfterUncaught(error, stack);
          failed ??= listener;
          failure ??= error;
          failureStack ??= stack;
        }
      }
      if (failure != null) _caught(failed!, failure, failureStack!);
    };
  }

  final void Function(L listener, E payload) _deliver;
  final bool reverse;
  late final void Function(E payload) call;
}

// --- the rounds -------------------------------------------------------------

// Every round is `vm:never-inline` and takes its dispatcher as a parameter, so
// no round can see the instance's type arguments - which is the state a real
// fire site is in, reading a dispatcher off a field. The
// `event.sourceEntity = i` store is identical across rounds, so a difference
// between two of them is a difference in the dispatch.

@pragma('vm:never-inline')
void _roundReal(
  EventDispatcher<ContactListener, ContactEvent> dispatcher,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    dispatcher(event);
  }
}

@pragma('vm:never-inline')
void _roundMirror(
  _Mirror<ContactListener, ContactEvent> dispatcher,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    dispatcher(event);
  }
}

@pragma('vm:never-inline')
void _roundMirrorNoInline(
  _MirrorNoInline<ContactListener, ContactEvent> dispatcher,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    dispatcher(event);
  }
}

@pragma('vm:never-inline')
void _roundHalf(_Half<ContactListener> dispatcher, ContactEvent event) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    dispatcher(event);
  }
}

@pragma('vm:never-inline')
void _roundHalfNoInline(
  _HalfNoInline<ContactListener> dispatcher,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    dispatcher(event);
  }
}

@pragma('vm:never-inline')
void _roundExt(
  _Ext<ContactListener, ContactEvent> dispatcher,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    dispatcher(event);
  }
}

@pragma('vm:never-inline')
void _roundExtNoInline(
  _Ext<ContactListener, ContactEvent> dispatcher,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    dispatcher.callNoInline(event);
  }
}

@pragma('vm:never-inline')
void _roundFn(
  _Ext<ContactListener, ContactEvent> dispatcher,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    _fire(dispatcher, event);
  }
}

@pragma('vm:never-inline')
void _roundFnNoInline(
  _Ext<ContactListener, ContactEvent> dispatcher,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    _fireNoInline(dispatcher, event);
  }
}

@pragma('vm:never-inline')
void _roundMGen(
  _MGen<ContactListener, ContactEvent> dispatcher,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    dispatcher(event);
  }
}

@pragma('vm:never-inline')
void _roundObj(
  _Obj<ContactListener, ContactEvent> dispatcher,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    dispatcher(event);
  }
}

@pragma('vm:never-inline')
void _roundField(
  _Field<ContactListener, ContactEvent> dispatcher,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    dispatcher.call(event);
  }
}

@pragma('vm:never-inline')
void _roundLoop(ContactEvent event) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    _sink = event.sourceEntity;
  }
}

// --- the harness ------------------------------------------------------------

/// Nanoseconds per dispatch, minimum of [_rounds]. [round] runs the whole inner
/// loop, so the one indirect call into it is paid per round and not per
/// dispatch.
double _bestNs(void Function() round) {
  round();
  var best = double.infinity;
  for (var r = 0; r < _rounds; r++) {
    final clock = Stopwatch()..start();
    round();
    clock.stop();
    final nanos = clock.elapsedMicroseconds * 1000 / _iterations;
    if (nanos < best) best = nanos;
  }
  return best;
}

void _row(int listeners, String label, double nanos) {
  stdout.writeln(
    '  ${listeners.toString().padLeft(9)}'
    '   ${label.padRight(16)}'
    '${nanos.toStringAsFixed(2).padLeft(8)}ns',
  );
}

/// The delivery closure `Event.of` is given, held separately so every shape
/// runs the same one.
void _deliverContact(ContactListener listener, ContactEvent event) =>
    listener.onContact(event);

T _fill<T extends _Set<ContactListener>>(
  T dispatcher,
  List<ContactListener> listeners,
) {
  for (final listener in listeners) {
    dispatcher.add(listener);
  }
  return dispatcher;
}

/// Builds every generic shape at payload types other than [ContactEvent] and
/// fires each once.
///
/// Without this the program instantiates each shape exactly once, the compiler
/// can prove what the type arguments are, and a bench for a type test would
/// have no way to fail. A game declares a dozen payload types - a `Duration`, an
/// `Entity`, a scene handle - so this is also the honest program.
void _pollute() {
  final any = _AnySys();
  _sink += _liveTrue ? 0 : 1;

  final a = Event.of<ContactListener, int>((l, p) => _sink += p)..add(any);
  final b = Event.of<ContactListener, String>((l, p) => _sink += p.length)
    ..add(any);
  final c = Event.of<ContactListener, Duration>(
    (l, p) => _sink += p.inMicroseconds,
  )..add(any);
  final d = Event.of<ContactListener, double>((l, p) => _sink += p.round())
    ..add(any);
  a(1);
  b('x');
  c(Duration.zero);
  d(1.5);

  _Mirror<ContactListener, int>((l, p) => _sink += p, reverse: _liveFalse)
    ..add(any)
    ..call(1);
  _Mirror<ContactListener, Duration>(
      (l, p) => _sink += p.inMicroseconds,
      reverse: _liveFalse,
    )
    ..add(any)
    ..call(Duration.zero);
  _MirrorNoInline<ContactListener, int>(
      (l, p) => _sink += p,
      reverse: _liveFalse,
    )
    ..add(any)
    ..call(1);
  _MirrorNoInline<ContactListener, Duration>(
      (l, p) => _sink += p.inMicroseconds,
      reverse: _liveFalse,
    )
    ..add(any)
    ..call(Duration.zero);
  _Ext<ContactListener, int>((l, p) => _sink += p, reverse: _liveFalse)
    ..add(any)
    ..call(1);
  _Ext<ContactListener, Duration>(
      (l, p) => _sink += p.inMicroseconds,
      reverse: _liveFalse,
    )
    ..add(any)
    ..call(Duration.zero);
  _MGen<ContactListener, int>((l, p) => _sink += p, reverse: _liveFalse)
    ..add(any)
    ..call(1);
  _MGen<ContactListener, Duration>(
      (l, p) => _sink += p.inMicroseconds,
      reverse: _liveFalse,
    )
    ..add(any)
    ..call(Duration.zero);
  _Obj<ContactListener, int>((l, p) => _sink += p, reverse: _liveFalse)
    ..add(any)
    ..call(1);
  _Obj<ContactListener, Duration>(
      (l, p) => _sink += p.inMicroseconds,
      reverse: _liveFalse,
    )
    ..add(any)
    ..call(Duration.zero);
  _Field<ContactListener, int>((l, p) => _sink += p, reverse: _liveFalse)
    ..add(any)
    ..call(1);
  _Field<ContactListener, Duration>(
      (l, p) => _sink += p.inMicroseconds,
      reverse: _liveFalse,
    )
    ..add(any)
    ..call(Duration.zero);
}

void _measure(int count, List<ContactListener> listeners) {
  final event = ContactEvent();
  final real = Event.of<ContactListener, ContactEvent>(_deliverContact);
  for (final listener in listeners) {
    real.add(listener);
  }
  final mirror = _fill(
    _Mirror<ContactListener, ContactEvent>(
      _deliverContact,
      reverse: _liveFalse,
    ),
    listeners,
  );
  final mirrorNoInline = _fill(
    _MirrorNoInline<ContactListener, ContactEvent>(
      _deliverContact,
      reverse: _liveFalse,
    ),
    listeners,
  );
  final half = _fill(
    _Half<ContactListener>(_deliverContact, reverse: _liveFalse),
    listeners,
  );
  final halfNoInline = _fill(
    _HalfNoInline<ContactListener>(_deliverContact, reverse: _liveFalse),
    listeners,
  );
  final ext = _fill(
    _Ext<ContactListener, ContactEvent>(_deliverContact, reverse: _liveFalse),
    listeners,
  );
  final mgen = _fill(
    _MGen<ContactListener, ContactEvent>(_deliverContact, reverse: _liveFalse),
    listeners,
  );
  final obj = _fill(
    _Obj<ContactListener, ContactEvent>(_deliverContact, reverse: _liveFalse),
    listeners,
  );
  final field = _fill(
    _Field<ContactListener, ContactEvent>(_deliverContact, reverse: _liveFalse),
    listeners,
  );

  _row(count, 'real', _bestNs(() => _roundReal(real, event)));
  _row(count, 'mirror', _bestNs(() => _roundMirror(mirror, event)));
  _row(
    count,
    'mirror-ni',
    _bestNs(() => _roundMirrorNoInline(mirrorNoInline, event)),
  );
  _row(count, 'half', _bestNs(() => _roundHalf(half, event)));
  _row(
    count,
    'half-ni',
    _bestNs(() => _roundHalfNoInline(halfNoInline, event)),
  );
  _row(count, 'ext', _bestNs(() => _roundExt(ext, event)));
  _row(count, 'ext-ni', _bestNs(() => _roundExtNoInline(ext, event)));
  _row(count, 'fn', _bestNs(() => _roundFn(ext, event)));
  _row(count, 'fn-ni', _bestNs(() => _roundFnNoInline(ext, event)));
  _row(count, 'mgen', _bestNs(() => _roundMGen(mgen, event)));
  _row(count, 'obj', _bestNs(() => _roundObj(obj, event)));
  _row(count, 'field', _bestNs(() => _roundField(field, event)));
  _row(count, 'loop', _bestNs(() => _roundLoop(event)));
  stdout.writeln('');
}

// --- what none of them may give up ------------------------------------------

/// A listener that records what reached it and what the dispatcher did to it,
/// so [_refuses] can tell the three outcomes apart.
class _Probe extends GameListenerBase with SubContactListener {
  bool disabled = false;
  int received = 0;

  @override
  bool get listensToEvents => !disabled;

  @override
  void disableAfterUncaught([Object? error, StackTrace? stack]) {
    disabled = true;
  }

  @override
  void onSubContact(SubContactEvent event) {
    received++;
    _sink += event.sourceEntity;
  }
}

/// How [dispatch] answers a payload that is not what the dispatcher's listeners
/// take.
///
/// Every shape is built at `SubContactEvent`, held at `ContactEvent` - which
/// Dart allows, the payload type being covariant - and pushed a plain
/// `ContactEvent`. A shape that lets that through has traded the test for
/// silent corruption and is not a candidate at any speed.
///
/// The three answers are not equally good. Refusing at the entry raises the
/// caller's mistake as the caller's. Refusing per listener raises it inside the
/// per-listener guard, where the dispatcher reads it as *that listener* having
/// thrown: the listener is disabled and, in debug, `_reportUncaught` asserts
/// with its name on it. A dispatcher with no listeners does not get asked at
/// all, which is why the zero-listener block matters.
String _refuses(void Function() dispatch, List<_Probe> probes) {
  for (final probe in probes) {
    probe.disabled = false;
    probe.received = 0;
  }
  try {
    dispatch();
  } on TypeError {
    return 'refused at the entry';
  }
  if (probes.any((probe) => probe.disabled)) {
    return 'refused per listener, and the listener was disabled for it';
  }
  if (probes.any((probe) => probe.received > 0)) return 'ACCEPTED IT';
  return 'never asked - no listener';
}

/// Set while [_soundness] runs, so the reports it provokes do not print a stack
/// trace per shape. Read only by [_caught], which is out of line and off every
/// measured path.
bool _quiet = false;

void _soundness(int count) {
  final probes = <_Probe>[for (var i = 0; i < count; i++) _Probe()];
  final listeners = <SubContactListener>[...probes];
  void deliver(SubContactListener listener, SubContactEvent payload) =>
      listener.onSubContact(payload);

  final built = Event.of<SubContactListener, SubContactEvent>(deliver);
  for (final listener in listeners) {
    built.add(listener);
  }
  final EventDispatcher<SubContactListener, ContactEvent> real = built;

  final _Mirror<SubContactListener, ContactEvent> mirror =
      _Mirror<SubContactListener, SubContactEvent>(
        deliver,
        reverse: _liveFalse,
      );
  final _Ext<SubContactListener, ContactEvent> ext =
      _Ext<SubContactListener, SubContactEvent>(deliver, reverse: _liveFalse);
  final _MGen<SubContactListener, ContactEvent> mgen =
      _MGen<SubContactListener, SubContactEvent>(deliver, reverse: _liveFalse);
  final _Obj<SubContactListener, ContactEvent> obj =
      _Obj<SubContactListener, SubContactEvent>(deliver, reverse: _liveFalse);
  final _Field<SubContactListener, ContactEvent> field =
      _Field<SubContactListener, SubContactEvent>(deliver, reverse: _liveFalse);
  for (final listener in listeners) {
    mirror.add(listener);
    ext.add(listener);
    mgen.add(listener);
    obj.add(listener);
    field.add(listener);
  }

  final wrong = ContactEvent();
  _quiet = true;
  stdout.writeln('  $count listeners');
  stdout.writeln('    real    ${_refuses(() => real(wrong), probes)}');
  stdout.writeln('    mirror  ${_refuses(() => mirror(wrong), probes)}');
  stdout.writeln('    ext     ${_refuses(() => ext(wrong), probes)}');
  stdout.writeln('    fn      ${_refuses(() => _fire(ext, wrong), probes)}');
  stdout.writeln('    mgen    ${_refuses(() => mgen(wrong), probes)}');
  stdout.writeln('    obj     ${_refuses(() => obj(wrong), probes)}');
  stdout.writeln('    field   ${_refuses(() => field.call(wrong), probes)}');
  _quiet = false;
}

void main() {
  _pollute();

  stdout.writeln(
    'one dispatch, $_iterations per round, $_rounds rounds, reporting minimum',
  );
  stdout.writeln('');
  stdout.writeln('  listeners   case                  ns');

  final all = <ContactListener>[
    _Sys0(_liveTrue),
    _Sys1(_liveTrue),
    _Sys2(_liveTrue),
    _Sys3(_liveTrue),
    _Sys4(_liveTrue),
    _Sys5(_liveTrue),
    _Sys6(_liveTrue),
    _Sys7(_liveTrue),
  ];

  for (final count in <int>[0, 1, 2, 8]) {
    _measure(count, all.sublist(0, count));
  }

  stdout.writeln('soundness: a dispatcher built at the subtype, held at the');
  stdout.writeln('supertype, handed the supertype. Every shape must refuse.');
  _soundness(0);
  _soundness(1);
  stdout.writeln('');
  stdout.writeln('sink $_sink');
}
