import 'package:goo/src/data.dart';
import 'package:goo/src/struct.dart';

/// Adapts a raw `DataPointer<int?>` (an `optInt64` field storing a packed
/// `Entity.value`) into a `DataPointer<Entity?>` - so `Child.parent` etc.
/// read/write real `Entity` values instead of making every call site do
/// `Entity(raw!)`/`.value` conversions by hand. Pure delegation, no
/// per-access allocation beyond what boxing an `Entity?` already costs
/// (which is nothing extra - `Entity` is a zero-cost extension type over
/// `int`, so an `Entity?` is exactly as cheap as an `int?`).
class _EntityField extends DataPointer<Entity?> {
  const _EntityField(this._raw);

  final DataPointer<int?> _raw;

  @override
  Entity? operator [](Entity entity) {
    final value = _raw[entity];
    return value == null ? null : Entity(value);
  }

  @override
  void operator []=(Entity entity, Entity? newValue) => _raw[entity] = newValue?.value;
}

mixin Child on Component {
  /// The full `Entity` handle of this entity's parent, or `null` if
  /// unparented. Stored as `optInt64` (not `optInt32`, the field's
  /// original width) because a packed `Entity` is a 64-bit handle
  /// (archetype id + page index + row offset - see `Entity` in
  /// struct.dart), not a 32-bit one; see `DataDescriptor.hasInt64`'s doc.
  late final DataPointer<Entity?> parent;
  late final DataPointer<Entity?> nextSibling;
  late final DataPointer<Entity?> prevSibling;

  // Every other mixin (Transform2D, and this file's own callers in
  // query_test.dart) registers itself via `component.has<Self>()` in
  // describeType - this one didn't, which meant `With<Child>()`/
  // `Without<Child>()` compiled and ran without error but silently matched
  // *everything*, since the bit they checked was never set in any
  // archetype's signature (nothing ever OR'd it in). Caught by
  // system.dart's query tests, not by inspection - see that file's tests
  // exercising `Without<Child>()` against a real archetype.
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Child>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    parent = _EntityField(data.optInt64());
    nextSibling = _EntityField(data.optInt64());
    prevSibling = _EntityField(data.optInt64());
  }
}

mixin Parent on Component {
  late final DataPointer<Entity?> firstChild;
  late final DataPointer<Entity?> lastChild;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Parent>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    firstChild = _EntityField(data.optInt64());
    lastChild = _EntityField(data.optInt64());
  }

  /// Appends [child] to the end of [self]'s child list - a doubly-linked
  /// splice through [firstChild]/[lastChild] and `child`'s own
  /// `nextSibling`/`prevSibling`.
  ///
  /// Takes [self] explicitly, unlike the field accessors above that don't
  /// need it: `Parent`'s `DataPointer` fields are shared across every
  /// entity of this archetype (one prefab instance describes the whole
  /// archetype, same as every other mixin - see `ArchetypeStorage`'s doc),
  /// so there is no implicit "this entity" the way there would be on a
  /// per-instance object. `SceneStruct.addEntity(..., parent: ...)` is the usual caller;
  /// call this directly only when attaching an *already-existing* entity
  /// (addEntity both creates the child and calls this).
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
    final oldLast = lastChild[self];
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
    if (childComponent == null || childComponent.parent[child] != self) {
      throw ArgumentError.value(child, 'child', 'is not currently a child of $self');
    }
    final prev = childComponent.prevSibling[child];
    final next = childComponent.nextSibling[child];
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
