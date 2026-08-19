import 'package:meta/meta.dart';

import 'package:good/src/data.dart';
import 'package:good/src/struct.dart';

mixin Child on Component {
  /// The full `Entity` handle of this entity's parent, or `null` if
  /// unparented. A packed `Entity` is a 64-bit handle (archetype id + page
  /// index + row offset - see `Entity` in struct.dart), which is the width
  /// `optEntity` stores it at.
  final parent = Field.optEntity();
  final nextSibling = Field.optEntity();
  final prevSibling = Field.optEntity();

  // Every other mixin (Transform2D, and this file's own callers in
  // query_test.dart) registers itself via `component.has<Self>()` in
  // describeType - this one didn't, which meant `With<Child>()`/
  // `Without<Child>()` compiled and ran without error but silently matched
  // *everything*, since the bit they checked was never set in any
  // archetype's signature (nothing ever OR'd it in). Caught by
  // system.dart's query tests, not by inspection - see that file's tests
  // exercising `Without<Child>()` against a real archetype.
  @override
  @mustCallSuper
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Child>();
  }
}

mixin Parent on Component {
  final firstChild = Field.optEntity();
  final lastChild = Field.optEntity();

  @override
  @mustCallSuper
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Parent>();
  }

  /// Appends [child] to the end of [self]'s child list - a doubly-linked
  /// splice through [firstChild]/[lastChild] and `child`'s own
  /// `nextSibling`/`prevSibling`.
  ///
  /// Takes [self] explicitly, unlike the field accessors above that don't need
  /// it: `Parent`'s `DataPointer` fields are shared across every entity of this
  /// archetype (one prefab instance describes the whole archetype, same as
  /// every other mixin - see `ArchetypeStorage`'s doc), so there is no implicit
  /// "this entity" the way there would be on a per-instance object.
  /// `SceneStruct.addEntity(..., parent: ...)` is the usual caller; call this
  /// directly only when attaching an *already-existing* entity (addEntity both
  /// creates the child and calls this).
  ///
  /// [child] must mix in [Child] - checked at runtime (`tryGet<Child>()`)
  /// since the type system has no way to require "some component that
  /// mixes in Child" as a constraint on a bare `Entity`.
  void addChild(Entity self, Entity child) {
    final childComponent = child.tryGet<Child>();
    if (childComponent == null) {
      throw ArgumentError.value(
        child,
        'child',
        'does not mix in Child - cannot be attached to a parent',
      );
    }
    // `readPending`, not `lastChild[self]`. An ordinary read sees the last
    // *published* snapshot, so two `addChild` calls in the same tick both read
    // the same stale tail, both take the `oldLast == null` branch, and the
    // second silently overwrites the first - the parent ends up with one child
    // and the rest are orphaned with no error anywhere. Spawning a character
    // with three attachments from one command is exactly that shape. See
    // `DataPointer.readPending`.
    final oldLast = lastChild.readPending(self);
    childComponent.prevSibling[child] = oldLast;
    childComponent.nextSibling[child] = null;
    if (oldLast == null) {
      firstChild[self] = child;
    } else {
      oldLast.get<Child>().nextSibling[oldLast] = child;
    }
    lastChild[self] = child;
    childComponent.parent[child] = self;
  }

  /// Splices [child] out of [self]'s child list and clears its
  /// parent/sibling links. Throws if [child] isn't currently a child of
  /// [self] - catches both "never attached" and "attached to a different
  /// parent" instead of silently corrupting either list.
  void removeChild(Entity self, Entity child) {
    final childComponent = child.tryGet<Child>();
    // `readPending` throughout, for the same reason `addChild` needs it:
    // unlinking is a read-modify-write over the chain, and two removals in one
    // tick would both read the *published* neighbours - so the second would
    // restitch the list as it stood before the first, silently resurrecting a
    // link. See `DataPointer.readPending`.
    if (childComponent == null ||
        childComponent.parent.readPending(child) != self) {
      throw ArgumentError.value(
        child,
        'child',
        'is not currently a child of $self',
      );
    }
    final prev = childComponent.prevSibling.readPending(child);
    final next = childComponent.nextSibling.readPending(child);
    if (prev == null) {
      firstChild[self] = next;
    } else {
      prev.get<Child>().nextSibling[prev] = next;
    }
    if (next == null) {
      lastChild[self] = prev;
    } else {
      next.get<Child>().prevSibling[next] = prev;
    }
    childComponent
      ..parent[child] = null
      ..nextSibling[child] = null
      ..prevSibling[child] = null;
  }
}
