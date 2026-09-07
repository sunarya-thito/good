// #389: would fusing a dispatcher's listeners into one generated closure make
// a dispatch cheaper than `EventDispatcher.call`?
//
// AOT ONLY. Compile and run:
//   dart compile exe packages/good/tool/baked_dispatch_bench.dart -o build/bdb.exe
//   build/bdb.exe
//
// A `flutter test` bench is JIT, and JIT has been wrong about this codebase by
// roughly two orders of magnitude twice. Inlining is the whole subject here,
// and JIT and AOT decide it differently, so a JIT number would answer a
// different question.
//
// # The shape being priced
//
// `_bindEvents` calls `EventBinder.bind(<EventBus>[state, ...declaredSystems])`
// once, and it is the only bind call in the engine, so the listener set is
// settled before the first dispatch. A generator could therefore emit the
// whole dispatch as one closure, built at boot and stored in a plain
// `void Function(E)` field:
//
//   final s0 = gameState.physics;            // concrete type, known when the
//   final s1 = gameState.flash;              // generator runs
//   contact.dispatcher = (event) {
//     if (s0.listensToEvents) s0.onContact(event);
//     if (s1.listensToEvents) s1.onContact(event);
//   };
//
// Against `EventDispatcher.call` that removes the list, the index, the
// `reverse` branch, the interface `listensToEvents` getter and the `_deliver`
// closure - two indirect calls per listener become none, and the `reverse`
// order is decided by the order the generator emits the calls in rather than
// by a branch taken on every listener of every dispatch.
//
// What it does not remove is one indirect call per dispatch: the engine holds
// `dispatcher` as a `void Function(E)` field and a closure call reads its
// entry point out of the object. `_roundFused` is `vm:never-inline` so that
// call site is shared by every closure this program builds, which is the state
// a real game's site is in and the state a per-row site would not be.
//
// # The rows
//
//   real     `EventDispatcher.call` as it ships - what a dispatch costs today
//   half     the same body on a class generic in the listener type only, with
//            the payload written out as a concrete type
//   mono     the same body on a class with no type parameters at all
//   walk     the same loop as a plain function, with the `_deliver` closure
//            taken out and the interface call written where it stood
//   deliver  `walk` with the closure put back
//   tear     fused closure, guard on the concrete receiver, call through a
//            captured method tear-off
//   recv     fused closure, guard and call both on the concrete receiver
//   direct   the calls written straight into the loop, no closure, no guard -
//            the ceiling, for scale
//   loop     the round with no dispatch at all: the `event.sourceEntity = i`
//            store every other row also pays
//
// The four rows between `real` and `tear` are there because the cost had to be
// located before it could be attributed. Each changes one thing against the
// one above it, and `real` minus `half` is the one that came out large: the
// same body stops costing about five nanoseconds a dispatch when the payload
// type parameter goes, and it costs those five nanoseconds at zero listeners
// too, where nothing in the loop runs at all.
//
// `tear` and `recv` differ in one thing: whether the call goes through a
// captured tear-off or straight to a method on a concrete receiver. Both hold
// the receiver at its concrete type, because a generator that can write
// `gameState.physics` knows that type. A generated accessor that yielded only
// the tear-off would have to read `listensToEvents` through the `GameListener`
// interface as well, so it can only be worse than `tear` is here.
//
// `+try` is the per-listener guard that keeps one throwing system from
// stopping the others in the same tick. If wrapping each call blocks the
// inlining the fusing is buying, that is where it shows.
//
// At zero listeners there is no closure to build, so the field is null and the
// dispatch is a load and a null test. #388 found the zero-listener path got
// cheaper when a collision became an event; it must not regress.

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

/// `CollisionListener`'s shape, cut down to the one method being timed.
mixin ContactListener on GameListener {
  void onContact(ContactEvent event);
}

/// Read by every system, printed at the end, so no dispatch is dead code.
int _sink = 0;

/// True, but not until the program runs. Assigned into every system's
/// `_enabled` so the `listensToEvents` branch is a real load rather than a
/// constant the compiler folds - `GameSystem` reads a field there too.
final bool _liveTrue = DateTime.now().microsecondsSinceEpoch > 0;

/// False, but not until the program runs, so `walk`'s `reverse` test is a
/// branch on a value and not a constant - `EventDispatcher.reverse` is a field
/// read there.
final bool _liveFalse = DateTime.now().microsecondsSinceEpoch < 0;

/// What a caught throw costs off the fast path. Out of line so the `catch`
/// block is a jump rather than a body, which is the shape a generator would
/// emit and the shape `EventDispatcher.call` already has - it records and
/// reports after the loop.
@pragma('vm:never-inline')
void _caught(GameListener listener, Object error, StackTrace stack) {
  listener.disableAfterUncaught(error, stack);
  stdout.writeln('$listener threw: $error');
  stdout.writeln('$stack');
}

// --- the systems ------------------------------------------------------------

// One class per listener, because a game's systems are different types and a
// fused dispatcher captures one of each. Bodies differ by a constant so
// nothing merges them, and each accumulates into its own field so eight of
// them cannot fold into one add.

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

// --- the field the engine would hold ----------------------------------------

/// Stands in for the dispatcher object the fire site reads the fused closure
/// out of. The field is mutable and nullable, so the load and the null test
/// happen per dispatch exactly as they would in the engine, and a dispatcher
/// with no listeners holds null rather than a closure that does nothing.
class _Fused {
  void Function(ContactEvent)? dispatcher;
}

// --- the fused closures -----------------------------------------------------

// Built at boot, from receivers held at the concrete type a generator would
// know. Written out per listener count because that is what a generator emits:
// there is no loop over a list left to write.

void Function(ContactEvent) _tear1(_Sys0 s0, {required bool guard}) {
  final f0 = s0.onContact;
  if (guard) {
    return (event) {
      try {
        if (s0.listensToEvents) f0(event);
      } catch (error, stack) {
        _caught(s0, error, stack);
      }
    };
  }
  return (event) {
    if (s0.listensToEvents) f0(event);
  };
}

void Function(ContactEvent) _recv1(_Sys0 s0, {required bool guard}) {
  if (guard) {
    return (event) {
      try {
        if (s0.listensToEvents) s0.onContact(event);
      } catch (error, stack) {
        _caught(s0, error, stack);
      }
    };
  }
  return (event) {
    if (s0.listensToEvents) s0.onContact(event);
  };
}

void Function(ContactEvent) _tear2(_Sys0 s0, _Sys1 s1, {required bool guard}) {
  final f0 = s0.onContact;
  final f1 = s1.onContact;
  if (guard) {
    return (event) {
      try {
        if (s0.listensToEvents) f0(event);
      } catch (error, stack) {
        _caught(s0, error, stack);
      }
      try {
        if (s1.listensToEvents) f1(event);
      } catch (error, stack) {
        _caught(s1, error, stack);
      }
    };
  }
  return (event) {
    if (s0.listensToEvents) f0(event);
    if (s1.listensToEvents) f1(event);
  };
}

void Function(ContactEvent) _recv2(_Sys0 s0, _Sys1 s1, {required bool guard}) {
  if (guard) {
    return (event) {
      try {
        if (s0.listensToEvents) s0.onContact(event);
      } catch (error, stack) {
        _caught(s0, error, stack);
      }
      try {
        if (s1.listensToEvents) s1.onContact(event);
      } catch (error, stack) {
        _caught(s1, error, stack);
      }
    };
  }
  return (event) {
    if (s0.listensToEvents) s0.onContact(event);
    if (s1.listensToEvents) s1.onContact(event);
  };
}

void Function(ContactEvent) _tear8(
  _Sys0 s0,
  _Sys1 s1,
  _Sys2 s2,
  _Sys3 s3,
  _Sys4 s4,
  _Sys5 s5,
  _Sys6 s6,
  _Sys7 s7, {
  required bool guard,
}) {
  final f0 = s0.onContact;
  final f1 = s1.onContact;
  final f2 = s2.onContact;
  final f3 = s3.onContact;
  final f4 = s4.onContact;
  final f5 = s5.onContact;
  final f6 = s6.onContact;
  final f7 = s7.onContact;
  if (guard) {
    return (event) {
      try {
        if (s0.listensToEvents) f0(event);
      } catch (error, stack) {
        _caught(s0, error, stack);
      }
      try {
        if (s1.listensToEvents) f1(event);
      } catch (error, stack) {
        _caught(s1, error, stack);
      }
      try {
        if (s2.listensToEvents) f2(event);
      } catch (error, stack) {
        _caught(s2, error, stack);
      }
      try {
        if (s3.listensToEvents) f3(event);
      } catch (error, stack) {
        _caught(s3, error, stack);
      }
      try {
        if (s4.listensToEvents) f4(event);
      } catch (error, stack) {
        _caught(s4, error, stack);
      }
      try {
        if (s5.listensToEvents) f5(event);
      } catch (error, stack) {
        _caught(s5, error, stack);
      }
      try {
        if (s6.listensToEvents) f6(event);
      } catch (error, stack) {
        _caught(s6, error, stack);
      }
      try {
        if (s7.listensToEvents) f7(event);
      } catch (error, stack) {
        _caught(s7, error, stack);
      }
    };
  }
  return (event) {
    if (s0.listensToEvents) f0(event);
    if (s1.listensToEvents) f1(event);
    if (s2.listensToEvents) f2(event);
    if (s3.listensToEvents) f3(event);
    if (s4.listensToEvents) f4(event);
    if (s5.listensToEvents) f5(event);
    if (s6.listensToEvents) f6(event);
    if (s7.listensToEvents) f7(event);
  };
}

void Function(ContactEvent) _recv8(
  _Sys0 s0,
  _Sys1 s1,
  _Sys2 s2,
  _Sys3 s3,
  _Sys4 s4,
  _Sys5 s5,
  _Sys6 s6,
  _Sys7 s7, {
  required bool guard,
}) {
  if (guard) {
    return (event) {
      try {
        if (s0.listensToEvents) s0.onContact(event);
      } catch (error, stack) {
        _caught(s0, error, stack);
      }
      try {
        if (s1.listensToEvents) s1.onContact(event);
      } catch (error, stack) {
        _caught(s1, error, stack);
      }
      try {
        if (s2.listensToEvents) s2.onContact(event);
      } catch (error, stack) {
        _caught(s2, error, stack);
      }
      try {
        if (s3.listensToEvents) s3.onContact(event);
      } catch (error, stack) {
        _caught(s3, error, stack);
      }
      try {
        if (s4.listensToEvents) s4.onContact(event);
      } catch (error, stack) {
        _caught(s4, error, stack);
      }
      try {
        if (s5.listensToEvents) s5.onContact(event);
      } catch (error, stack) {
        _caught(s5, error, stack);
      }
      try {
        if (s6.listensToEvents) s6.onContact(event);
      } catch (error, stack) {
        _caught(s6, error, stack);
      }
      try {
        if (s7.listensToEvents) s7.onContact(event);
      } catch (error, stack) {
        _caught(s7, error, stack);
      }
    };
  }
  return (event) {
    if (s0.listensToEvents) s0.onContact(event);
    if (s1.listensToEvents) s1.onContact(event);
    if (s2.listensToEvents) s2.onContact(event);
    if (s3.listensToEvents) s3.onContact(event);
    if (s4.listensToEvents) s4.onContact(event);
    if (s5.listensToEvents) s5.onContact(event);
    if (s6.listensToEvents) s6.onContact(event);
    if (s7.listensToEvents) s7.onContact(event);
  };
}

// --- the rounds -------------------------------------------------------------

// Every round is `vm:never-inline`, so each has one body shared by every row
// that uses it. That is what keeps the fused call site honest: it sees every
// closure this program builds, which is the state a real game's site is in.
// It also means the `event.sourceEntity = i` store is identical across rows,
// so a difference between two of them is a difference in the dispatch.

@pragma('vm:never-inline')
void _roundFused(_Fused holder, ContactEvent event) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    final dispatch = holder.dispatcher;
    if (dispatch != null) dispatch(event);
  }
}

/// `EventDispatcher.call` with the delivery closure taken out and the
/// interface call written where it stood. `real` minus `walk` is what the
/// `_deliver` hop costs; `walk` minus `recv` is the list, the index, the
/// `reverse` branch and the interface getter together.
@pragma('vm:never-inline')
void _walk(List<ContactListener> listeners, bool reverse, ContactEvent event) {
  ContactListener? failed;
  Object? failure;
  StackTrace? failureStack;
  for (var n = 0; n < listeners.length; n++) {
    final listener = listeners[reverse ? listeners.length - 1 - n : n];
    if (!listener.listensToEvents) continue;
    try {
      listener.onContact(event);
    } catch (error, stack) {
      listener.disableAfterUncaught(error, stack);
      failed ??= listener;
      failure ??= error;
      failureStack ??= stack;
    }
  }
  if (failure != null) _caught(failed!, failure, failureStack!);
}

@pragma('vm:never-inline')
void _roundWalk(
  List<ContactListener> listeners,
  bool reverse,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    _walk(listeners, reverse, event);
  }
}

/// `EventDispatcher` with the type parameters written out as the concrete
/// types this bench uses, and nothing else changed - same fields, same body,
/// same `call`. `real` minus `mono` is what `EventDispatcher.call` costs for
/// being a method on a *generic* class: the type-arguments vector its fields
/// and its `E payload` parameter are read against.
class _MonoDispatcher {
  _MonoDispatcher(this._deliver, {required this.reverse});

  final List<ContactListener> _listeners = <ContactListener>[];
  final void Function(ContactListener listener, ContactEvent payload) _deliver;
  final bool reverse;

  void add(ContactListener listener) => _listeners.add(listener);

  void call(ContactEvent payload) {
    final listeners = _listeners;
    ContactListener? failed;
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

@pragma('vm:never-inline')
void _roundMono(_MonoDispatcher dispatcher, ContactEvent event) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    dispatcher(event);
  }
}

/// `_MonoDispatcher` with the *listener* type parameter put back, bound and
/// instantiated exactly as `EventDispatcher` has it, and the
/// payload left concrete. `real` minus `half` is what the payload type
/// parameter costs on its own: `E` is a class type parameter, so `call(E
/// payload)` is covariant and the callee type-tests its argument against the
/// type-arguments vector on every dispatch. `half` minus `mono` is what the
/// rest of being generic costs.
class _HalfDispatcher<L extends GameListener> {
  _HalfDispatcher(this._deliver, {required this.reverse});

  final List<L> _listeners = <L>[];
  final void Function(L listener, ContactEvent payload) _deliver;
  final bool reverse;

  void add(L listener) => _listeners.add(listener);

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

@pragma('vm:never-inline')
void _roundHalf(
  _HalfDispatcher<ContactListener> dispatcher,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    dispatcher(event);
  }
}

/// `walk` with the delivery closure put back exactly where `EventDispatcher`
/// holds it, and nothing else changed. Still a plain function over concrete
/// types, so `real` minus `deliver` is what `call` costs for being a method on
/// a generic class rather than for anything in its body.
@pragma('vm:never-inline')
void _deliverWalk(
  List<ContactListener> listeners,
  bool reverse,
  void Function(ContactListener listener, ContactEvent payload) deliver,
  ContactEvent event,
) {
  ContactListener? failed;
  Object? failure;
  StackTrace? failureStack;
  for (var n = 0; n < listeners.length; n++) {
    final listener = listeners[reverse ? listeners.length - 1 - n : n];
    if (!listener.listensToEvents) continue;
    try {
      deliver(listener, event);
    } catch (error, stack) {
      listener.disableAfterUncaught(error, stack);
      failed ??= listener;
      failure ??= error;
      failureStack ??= stack;
    }
  }
  if (failure != null) _caught(failed!, failure, failureStack!);
}

@pragma('vm:never-inline')
void _roundDeliver(
  List<ContactListener> listeners,
  bool reverse,
  void Function(ContactListener listener, ContactEvent payload) deliver,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    _deliverWalk(listeners, reverse, deliver, event);
  }
}

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
void _roundLoop(ContactEvent event) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    _sink = event.sourceEntity;
  }
}

@pragma('vm:never-inline')
void _roundDirect1(_Sys0 s0, ContactEvent event) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    s0.onContact(event);
  }
}

@pragma('vm:never-inline')
void _roundDirect2(_Sys0 s0, _Sys1 s1, ContactEvent event) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    s0.onContact(event);
    s1.onContact(event);
  }
}

@pragma('vm:never-inline')
void _roundDirect8(
  _Sys0 s0,
  _Sys1 s1,
  _Sys2 s2,
  _Sys3 s3,
  _Sys4 s4,
  _Sys5 s5,
  _Sys6 s6,
  _Sys7 s7,
  ContactEvent event,
) {
  for (var i = 0; i < _iterations; i++) {
    event.sourceEntity = i;
    s0.onContact(event);
    s1.onContact(event);
    s2.onContact(event);
    s3.onContact(event);
    s4.onContact(event);
    s5.onContact(event);
    s6.onContact(event);
    s7.onContact(event);
  }
}

// --- the harness ------------------------------------------------------------

/// Nanoseconds per dispatch, minimum of [_rounds]. [round] runs the whole
/// inner loop, so the one indirect call into it is paid per round and not per
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

/// The delivery closure `Event.of` is given, held separately so `deliver` can
/// be handed the same one `real` runs.
void _deliverContact(ContactListener listener, ContactEvent event) =>
    listener.onContact(event);

_HalfDispatcher<ContactListener> _half(List<ContactListener> listeners) {
  final dispatcher = _HalfDispatcher<ContactListener>(
    _deliverContact,
    reverse: _liveFalse,
  );
  for (final listener in listeners) {
    dispatcher.add(listener);
  }
  return dispatcher;
}

_MonoDispatcher _mono(List<ContactListener> listeners) {
  final dispatcher = _MonoDispatcher(_deliverContact, reverse: _liveFalse);
  for (final listener in listeners) {
    dispatcher.add(listener);
  }
  return dispatcher;
}

EventDispatcher<ContactListener, ContactEvent> _shipped(
  List<ContactListener> listeners,
) {
  final dispatcher = Event.of<ContactListener, ContactEvent>(_deliverContact);
  for (final listener in listeners) {
    dispatcher.add(listener);
  }
  return dispatcher;
}

void main() {
  stdout.writeln(
    'one dispatch, $_iterations per round, $_rounds rounds, reporting minimum',
  );
  stdout.writeln('');
  stdout.writeln('  listeners   case                  ns');
  stdout.writeln('  ---------------------------------------');

  final event = ContactEvent();
  final s0 = _Sys0(_liveTrue);
  final s1 = _Sys1(_liveTrue);
  final s2 = _Sys2(_liveTrue);
  final s3 = _Sys3(_liveTrue);
  final s4 = _Sys4(_liveTrue);
  final s5 = _Sys5(_liveTrue);
  final s6 = _Sys6(_liveTrue);
  final s7 = _Sys7(_liveTrue);
  final holder = _Fused();

  // Zero listeners. Nothing to fuse, so the field stays null and the whole
  // dispatch is the load and the null test `_roundFused` already does.
  {
    const listeners = <ContactListener>[];
    final real = _shipped(listeners);
    holder.dispatcher = null;
    _row(0, 'real', _bestNs(() => _roundReal(real, event)));
    _row(0, 'half', _bestNs(() => _roundHalf(_half(listeners), event)));
    _row(0, 'mono', _bestNs(() => _roundMono(_mono(listeners), event)));
    _row(0, 'walk', _bestNs(() => _roundWalk(listeners, _liveFalse, event)));
    _row(
      0,
      'deliver',
      _bestNs(
        () => _roundDeliver(listeners, _liveFalse, _deliverContact, event),
      ),
    );
    _row(0, 'fused null', _bestNs(() => _roundFused(holder, event)));
    _row(0, 'loop', _bestNs(() => _roundLoop(event)));
  }

  {
    final listeners = <ContactListener>[s0];
    final real = _shipped(listeners);
    _row(1, 'real', _bestNs(() => _roundReal(real, event)));
    _row(1, 'half', _bestNs(() => _roundHalf(_half(listeners), event)));
    _row(1, 'mono', _bestNs(() => _roundMono(_mono(listeners), event)));
    _row(1, 'walk', _bestNs(() => _roundWalk(listeners, _liveFalse, event)));
    _row(
      1,
      'deliver',
      _bestNs(
        () => _roundDeliver(listeners, _liveFalse, _deliverContact, event),
      ),
    );

    holder.dispatcher = _tear1(s0, guard: false);
    _row(1, 'tear', _bestNs(() => _roundFused(holder, event)));
    holder.dispatcher = _tear1(s0, guard: true);
    _row(1, 'tear+try', _bestNs(() => _roundFused(holder, event)));
    holder.dispatcher = _recv1(s0, guard: false);
    _row(1, 'recv', _bestNs(() => _roundFused(holder, event)));
    holder.dispatcher = _recv1(s0, guard: true);
    _row(1, 'recv+try', _bestNs(() => _roundFused(holder, event)));

    _row(1, 'direct', _bestNs(() => _roundDirect1(s0, event)));
  }

  {
    final listeners = <ContactListener>[s0, s1];
    final real = _shipped(listeners);
    _row(2, 'real', _bestNs(() => _roundReal(real, event)));
    _row(2, 'half', _bestNs(() => _roundHalf(_half(listeners), event)));
    _row(2, 'mono', _bestNs(() => _roundMono(_mono(listeners), event)));
    _row(2, 'walk', _bestNs(() => _roundWalk(listeners, _liveFalse, event)));
    _row(
      2,
      'deliver',
      _bestNs(
        () => _roundDeliver(listeners, _liveFalse, _deliverContact, event),
      ),
    );

    holder.dispatcher = _tear2(s0, s1, guard: false);
    _row(2, 'tear', _bestNs(() => _roundFused(holder, event)));
    holder.dispatcher = _tear2(s0, s1, guard: true);
    _row(2, 'tear+try', _bestNs(() => _roundFused(holder, event)));
    holder.dispatcher = _recv2(s0, s1, guard: false);
    _row(2, 'recv', _bestNs(() => _roundFused(holder, event)));
    holder.dispatcher = _recv2(s0, s1, guard: true);
    _row(2, 'recv+try', _bestNs(() => _roundFused(holder, event)));

    _row(2, 'direct', _bestNs(() => _roundDirect2(s0, s1, event)));
  }

  {
    final listeners = <ContactListener>[s0, s1, s2, s3, s4, s5, s6, s7];
    final real = _shipped(listeners);
    _row(8, 'real', _bestNs(() => _roundReal(real, event)));
    _row(8, 'half', _bestNs(() => _roundHalf(_half(listeners), event)));
    _row(8, 'mono', _bestNs(() => _roundMono(_mono(listeners), event)));
    _row(8, 'walk', _bestNs(() => _roundWalk(listeners, _liveFalse, event)));
    _row(
      8,
      'deliver',
      _bestNs(
        () => _roundDeliver(listeners, _liveFalse, _deliverContact, event),
      ),
    );

    holder.dispatcher = _tear8(s0, s1, s2, s3, s4, s5, s6, s7, guard: false);
    _row(8, 'tear', _bestNs(() => _roundFused(holder, event)));
    holder.dispatcher = _tear8(s0, s1, s2, s3, s4, s5, s6, s7, guard: true);
    _row(8, 'tear+try', _bestNs(() => _roundFused(holder, event)));
    holder.dispatcher = _recv8(s0, s1, s2, s3, s4, s5, s6, s7, guard: false);
    _row(8, 'recv', _bestNs(() => _roundFused(holder, event)));
    holder.dispatcher = _recv8(s0, s1, s2, s3, s4, s5, s6, s7, guard: true);
    _row(8, 'recv+try', _bestNs(() => _roundFused(holder, event)));

    _row(
      8,
      'direct',
      _bestNs(() => _roundDirect8(s0, s1, s2, s3, s4, s5, s6, s7, event)),
    );
  }

  stdout.writeln('');
  stdout.writeln('real     EventDispatcher.call, filled the way boot fills it');
  stdout.writeln('half     the same body, generic in the listener type only');
  stdout.writeln('mono     the same body on a class with no type parameters');
  stdout.writeln('walk     the same loop with the _deliver closure taken out');
  stdout.writeln(
    'deliver  walk with the closure put back, over concrete types',
  );
  stdout.writeln('tear     fused closure, call through a captured tear-off');
  stdout.writeln('recv     fused closure, call on the concrete receiver');
  stdout.writeln('direct   calls written into the loop - the ceiling');
  stdout.writeln('loop     the store every row pays, with no dispatch');
  stdout.writeln('');
  stdout.writeln('sink=$_sink (printed so nothing above folds away)');
}
