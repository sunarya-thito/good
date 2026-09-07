// What does one contact cost now that a collision is an event?
//
// AOT ONLY. Compile and run:
//   cd packages/goo2d_physics_box2d
//   dart compile exe tool/contact_dispatch_bench.dart -o build/contact_dispatch_bench.exe
//   build/contact_dispatch_bench.exe
//
// A `flutter test` bench is JIT, and JIT has been wrong about this codebase by
// roughly two orders of magnitude twice - see the project's own notes on it.
// This number decided a shape, so it has to be AOT.
//
// # What is real here and what is not
//
// The dispatcher is the real one, `EventDispatcher` out of `package:good`,
// filled the way the boot pass fills it. That is the whole subject: the change
// replaced a null check on a per-shape listener cache with a call into one of
// these, and the question is what that costs per contact.
//
// The payload and the listener mixin are stand-ins of the same shape, because
// `Collision2DEvent` and `CollisionListener` live in `goo2d`, `goo2d` depends
// on Flutter, and a package that depends on Flutter cannot be compiled to a
// standalone exe. `tool/physics_bench.dart` is split for the same reason and
// says so. Neither stand-in is where the cost is: one is four field stores, the
// other is six no-op methods.
//
// `before` is master's path, reproduced here: two owner lookups, a null check
// on the owner's cached listener, and a nested switch on sensor and phase to
// pick a method. `after` is what shipped: a listener-count check, two owner
// lookups, and a call through the dispatcher for that phase.

// The dispatcher is `package:good`'s, and reaching it without dragging in
// Flutter means importing the library that declares it rather than the barrel.
// `offer` and `add` are `@internal` because a game never fills a dispatcher by
// hand - the boot pass does - and this bench has to stand where the boot pass
// stands. `good` arrives through `goo2d` rather than as a direct dependency,
// and naming it in the pubspec to satisfy one file under tool/ would put a
// constraint in a published package for a bench nobody ships.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:good/src/event.dart';

/// Touching pairs per tick. A settled pile of a few thousand bodies is this
/// order of contacts, which is the case `dispatchStayEvents` was written about.
const int pairCount = 20000;

/// Ticks per timed round.
const int ticks = 200;

/// Reported as the minimum of this many rounds. A round can only be inflated
/// by noise, never deflated, so the minimum is the closest a wall clock gets
/// to "how much work is this".
const int rounds = 5;

void main() {
  stdout.writeln(
    'one contact through the collision path   '
    '$pairCount pairs x $ticks ticks, $rounds rounds, reporting minimum',
  );
  stdout.writeln('');
  stdout.writeln('  path      listeners   per contact');
  stdout.writeln('  ------------------------------------');

  _report('before', 0, _benchBefore(0));
  _report('before', 1, _benchBefore(1));
  _report('after', 0, _benchAfter(0));
  _report('after', 1, _benchAfter(1));

  stdout.writeln('');
  stdout.writeln('`before` is the per-shape listener cache and its null check;');
  stdout.writeln('`after` is the dispatcher. At 0 listeners `after` returns on');
  stdout.writeln('the listener count before either owner lookup, which is less');
  stdout.writeln('work than `before` did - and the stay loop, which is the only');
  stdout.writeln('O(contacts) one, is skipped whole on the same count.');
  stdout.writeln('');
  stdout.writeln('At 1 listener the gap is far more than the second delivery.');
  stdout.writeln('Most of it is `EventDispatcher.call` itself: about 15ns per');
  stdout.writeln('dispatch against about 3ns for a direct virtual call through');
  stdout.writeln('a cached listener. Adding any one of its parts to a plain');
  stdout.writeln('indexed loop - the try/catch, the listensToEvents read, the');
  stdout.writeln('captured closure - costs 1 to 2ns, so no single one of them');
  stdout.writeln('accounts for it; what costs is the method as a whole.');
  stdout.writeln('');
  stdout.writeln('That is the price of the scope. A settled pile with tens of');
  stdout.writeln('thousands of touching pairs pays it per pair per tick, which');
  stdout.writeln('is what dispatchStayEvents is for.');
  stdout.writeln('');
  stdout.writeln('sink=$_sink (printed so nothing above folds away)');
}

void _report(String path, int listeners, double nanos) {
  stdout.writeln(
    '  ${path.padRight(9)}'
    '${listeners.toString().padLeft(9)}'
    '${nanos.toStringAsFixed(2).padLeft(14)}ns',
  );
}

/// Read by the listeners, printed at the end, so no dispatch is dead code.
int _sink = 0;

// --- the stand-ins ----------------------------------------------------------

/// `Collision2DEvent`'s shape: one instance, repointed before each dispatch.
class ContactEvent {
  late Object source;
  late int sourceEntity;
  late Object target;
  late int targetEntity;

  void set(Object source, int sourceEntity, Object target, int targetEntity) {
    this.source = source;
    this.sourceEntity = sourceEntity;
    this.target = target;
    this.targetEntity = targetEntity;
  }
}

/// `CollisionListener`'s shape after the change.
mixin ContactListener on GameListener {
  void onCollisionEnter2D(ContactEvent event) {}
  void onCollisionExit2D(ContactEvent event) {}
  void onCollisionStay2D(ContactEvent event) {}
  void onTriggerEnter2D(ContactEvent event) {}
  void onTriggerExit2D(ContactEvent event) {}
  void onTriggerStay2D(ContactEvent event) {}
}

/// `CollisionListener`'s shape before it - a plain object the prefab was.
class LegacyListener {
  void onCollisionEnter2D(ContactEvent event) {}
  void onCollisionExit2D(ContactEvent event) {}
  void onCollisionStay2D(ContactEvent event) => _sink++;
  void onTriggerEnter2D(ContactEvent event) {}
  void onTriggerExit2D(ContactEvent event) {}
  void onTriggerStay2D(ContactEvent event) => _sink++;
}

class Watcher extends GameListenerBase with ContactListener {
  @override
  void onCollisionStay2D(ContactEvent event) => _sink++;

  @override
  void onTriggerStay2D(ContactEvent event) => _sink++;
}

/// The `_ShapeOwner` master had.
class LegacyOwner {
  LegacyOwner(this.entity, this.body, this.listener);

  final int entity;
  final Object body;
  final LegacyListener? listener;
}

/// The `_ShapeOwner` that shipped.
class Owner {
  Owner(this.entity, this.body);

  final int entity;
  final Object body;
}

enum Phase { enter, exit, stay }

// --- before -----------------------------------------------------------------

double _benchBefore(int listeners) {
  final listener = listeners == 0 ? null : LegacyListener();
  // Two owners per pair, as Box2D reports two shapes. One of them carries the
  // listener when there is one, which is the crate-on-floor case: the floor's
  // prefab mixed in nothing and was skipped on the null check.
  final owners = <LegacyOwner?>[
    for (var i = 0; i < pairCount * 2; i++)
      LegacyOwner(i, const Object(), i.isEven ? listener : null),
  ];
  final event = ContactEvent();

  double best = double.infinity;
  for (var round = 0; round < rounds; round++) {
    final clock = Stopwatch()..start();
    for (var tick = 0; tick < ticks; tick++) {
      for (var i = 0; i < pairCount; i++) {
        final a = owners[i * 2];
        final b = owners[i * 2 + 1];
        if (a == null || b == null) continue;
        _deliverBefore(a, b, event, i.isEven, Phase.stay);
        _deliverBefore(b, a, event, i.isEven, Phase.stay);
      }
    }
    clock.stop();
    final nanos = clock.elapsedMicroseconds * 1000 / (ticks * pairCount);
    if (nanos < best) best = nanos;
  }
  return best;
}

void _deliverBefore(
  LegacyOwner source,
  LegacyOwner target,
  ContactEvent event,
  bool sensor,
  Phase phase,
) {
  final listener = source.listener;
  if (listener == null) return;

  event.set(source.body, source.entity, target.body, target.entity);

  if (sensor) {
    switch (phase) {
      case Phase.enter:
        listener.onTriggerEnter2D(event);
      case Phase.exit:
        listener.onTriggerExit2D(event);
      case Phase.stay:
        listener.onTriggerStay2D(event);
    }
  } else {
    switch (phase) {
      case Phase.enter:
        listener.onCollisionEnter2D(event);
      case Phase.exit:
        listener.onCollisionExit2D(event);
      case Phase.stay:
        listener.onCollisionStay2D(event);
    }
  }
}

// --- after ------------------------------------------------------------------

double _benchAfter(int listeners) {
  final collisionStay = Event.of<ContactListener, ContactEvent>(
    (listener, event) => listener.onCollisionStay2D(event),
  );
  final triggerStay = Event.of<ContactListener, ContactEvent>(
    (listener, event) => listener.onTriggerStay2D(event),
  );
  for (var i = 0; i < listeners; i++) {
    final watcher = Watcher();
    collisionStay.offer(watcher);
    triggerStay.offer(watcher);
  }

  final owners = <Owner?>[
    for (var i = 0; i < pairCount * 2; i++) Owner(i, const Object()),
  ];
  final event = ContactEvent();

  double best = double.infinity;
  for (var round = 0; round < rounds; round++) {
    final clock = Stopwatch()..start();
    for (var tick = 0; tick < ticks; tick++) {
      // `_dispatchStay` hoists a count check above this loop and skips the
      // whole thing at zero listeners. That is not done here, deliberately:
      // hoisting it would time an empty loop and the 0-listener row would
      // describe nothing. What is timed is `_dispatchPair` per contact, which
      // is what the enter and exit paths pay per drained event whatever the
      // stay loop does.
      for (var i = 0; i < pairCount; i++) {
        _dispatchPairAfter(
          owners,
          i,
          i.isEven ? triggerStay : collisionStay,
          event,
        );
      }
    }
    clock.stop();
    final nanos = clock.elapsedMicroseconds * 1000 / (ticks * pairCount);
    if (nanos < best) best = nanos;
  }
  return best;
}

void _dispatchPairAfter(
  List<Owner?> owners,
  int pair,
  EventDispatcher<ContactListener, ContactEvent> dispatcher,
  ContactEvent event,
) {
  if (dispatcher.listenerCount == 0) return;

  final a = owners[pair * 2];
  final b = owners[pair * 2 + 1];
  if (a == null || b == null) return;

  event.set(a.body, a.entity, b.body, b.entity);
  dispatcher(event);
  event.set(b.body, b.entity, a.body, a.entity);
  dispatcher(event);
}
