import 'package:meta/meta.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/scene.dart';
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

  DataPointer<Entity?>? _declaredIn;
  int _declaredInArchetype = -1;

  /// The column on the archetype that **declared** this prefab with
  /// `EntityStruct.of`, holding which entity of this prefab one entity of
  /// that archetype owns.
  ///
  /// The reverse of [parent], and named so the two do not read as the same
  /// thing: [parent] is a column on *this* row naming the owner; this is a
  /// column on the *owner's* row naming the entity of this prefab it holds.
  /// `null` unless something declared this prefab as its child - a prefab a
  /// scene declared has no owner to hold it.
  ///
  /// Read through `ParentAccessor.operator []`, which is where the public
  /// spelling lives, because the column belongs to the parent's row.
  @internal
  DataPointer<Entity?>? get declaredIn => _declaredIn;

  /// Which archetype [declaredIn] is a column of, or -1.
  ///
  /// A column is a byte offset into one archetype's row and means nothing in
  /// another's, and nothing stops an entity of this prefab being `addChild`ed
  /// to a parent of some unrelated archetype - it mixes in [Child], which is
  /// all `addChild` asks. So every use of [declaredIn] checks this first;
  /// without it the mismatch is an out-of-bounds read rather than an error.
  @internal
  int get declaredInArchetype => _declaredInArchetype;

  /// Records the column `EntityStruct.of` reserved for this prefab on the
  /// declaring archetype. Called once, by that registration.
  @internal
  void bindDeclaration(DataPointer<Entity?> handle, int archetypeId) {
    _declaredIn = handle;
    _declaredInArchetype = archetypeId;
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

  final List<EntityStruct> _declaredChildren = <EntityStruct>[];

  /// Every child prefab this one declared with `EntityStruct.of`, in
  /// declaration order - walked by `SceneStruct.addEntityIn` on each spawn.
  /// Internal: user code holds the prefabs `EntityStruct.of` gave it, never
  /// this.
  ///
  /// Here rather than on `EntityStruct` because holding children is what
  /// `Parent` is. A prefab with no hierarchy keeps no list.
  @internal
  List<EntityStruct> get declaredChildren => _declaredChildren;
}

/// The hierarchy's structural edits, on the entity they are about.
///
/// ```dart
/// parentEntity<Parent>().addChild(childEntity);
/// parentEntity<Parent>().removeChild(childEntity);
/// ```
///
/// Inside an accessor extension `this` **is** the entity (`Accessor<T>`
/// implements `Entity`), so a column indexes with `this` directly and
/// [Accessor.component] hands back the `Parent` it belongs to. That is why
/// neither method takes the parent as an argument any more: they used to,
/// with a comment claiming a `DataPointer` field is shared across the
/// archetype and so "there is no implicit *this entity* the way there would
/// be on a per-instance object". The fields are still shared - one prefab
/// describes one archetype - but `Accessor<Parent>` is exactly that implicit
/// this-entity, and it has existed since `a462113`.
///
/// `SceneStruct.addEntity(..., parent: ...)` is the usual caller; reach for
/// these directly only when attaching an *already-existing* entity, since
/// `addEntity` both creates the child and links it.
///
/// The four operations are deliberately separate, because they answer
/// different questions and used to be spelled with two: [addChild] attaches
/// something unparented, [adopt] moves something that already has a parent,
/// [removeChild] destroys, and `ChildAccessor.detach` unlinks and keeps the
/// entity alive.
extension ParentAccessor on Accessor<Parent> {
  /// The entity of [child] that this one owns - the other half of what
  /// `EntityStruct.of` declares.
  ///
  /// ```dart
  /// class Turret extends EntityStruct with Parent {
  ///   final barrel = EntityStruct.of(Barrel.new);
  /// }
  ///
  /// final barrelEntity = turretEntity<Parent>()[turret.barrel];
  /// ```
  ///
  /// The parent is the receiver because the column is on the parent's row:
  /// the declaration reserved it on the *declaring* archetype, so reading it
  /// through the child prefab would reach a parent's column from the far
  /// side. Read-only - the link is written once, when the parent mounts, and
  /// nothing else may point it somewhere else.
  ///
  /// [child] is a [Child] rather than an `EntityStruct`, which makes "you can
  /// only ask for something that could have been declared as a child" a
  /// compile-time fact. No type parameter is involved, so the restriction
  /// that stopped `entity[Transform3D]` (an operator's return type cannot
  /// depend on its argument) does not apply.
  ///
  /// Reads the **pending** slot, like the hierarchy's own links do. A child
  /// is allocated and written mid-tick, and a row recycled from a destroyed
  /// entity publishes its declared defaults rather than this tick's writes
  /// (issue #5) - so an ordinary read on a turret's own mount tick would hand
  /// back `Entity(0)`, a real handle naming somebody else's row. See
  /// [DataPointer.readPending] and [addChild], which reads `lastChild` the
  /// same way for the same reason.
  Entity operator [](Child child) {
    assert(_declaredHere(child));
    final owned = child.declaredIn!.readPending(this);
    if (owned == null) {
      throw StateError(
        'Entity $entity holds no ${child.runtimeType}. Either it is not an '
        'entity of the archetype that declared that child, or its row was '
        'written outside the mount that fills this link.',
      );
    }
    return owned;
  }

  /// Appends [child] to the end of this entity's child list - a doubly-linked
  /// splice through `firstChild`/`lastChild` and `child`'s own
  /// `nextSibling`/`prevSibling`.
  ///
  /// [child] must be **unparented**. It used to splice unconditionally, which
  /// meant attaching an already-attached entity left it in two chains: its old
  /// parent still named it, its old siblings still pointed at it, and the
  /// corruption was silent. There is no legitimate caller for that now that
  /// [adopt] exists, so it is an error.
  ///
  /// [child] must mix in [Child] - checked at runtime (`tryGet<Child>()`)
  /// since the type system has no way to require "some component that
  /// mixes in Child" as a constraint on a bare `Entity`.
  void addChild(Entity child) {
    final childComponent = _requireChild(child);
    assert(_unparented(childComponent, child));
    _append(childComponent, child);
  }

  /// Rejects an entity that already hangs off some parent.
  ///
  /// The check is a column read on the write slot, paid once per [addChild]
  /// - so once per declared child on every spawn - and what it catches is a
  /// caller reaching for [addChild] where [adopt] is the operation. That is
  /// a fixed property of the calling code, so it belongs in an assert; the
  /// read is what makes leaving it in release worth avoiding.
  bool _unparented(Child childComponent, Entity child) {
    if (childComponent.parent.readPending(child) != null) {
      throw ArgumentError.value(
        child,
        'child',
        'already has a parent. Use adopt() to move it here, or detach() it '
            'first - splicing it into a second chain would leave both chains '
            'naming it.',
      );
    }
    return true;
  }

  /// Moves [child] here from wherever it is, keeping it and its subtree alive
  /// - the reparent operation.
  ///
  /// Remove-then-add used to be the way to do this, and stopped being one
  /// when [removeChild] became destructive. Unlinks [child] from its current
  /// parent's chain, if it has one, and appends it here; an already-unparented
  /// [child] makes this [addChild].
  ///
  /// Adopting into the parent it already has moves it to the end of that
  /// chain rather than doing nothing, because that is what the same two steps
  /// spelled out by hand would do.
  void adopt(Entity child) {
    final childComponent = _requireChild(child);
    final current = childComponent.parent.readPending(child);
    if (current != null) current<Parent>().unlinkChild(child);
    _append(childComponent, child);
  }

  /// Destroys [child] and everything under it.
  ///
  /// Not a detach: the child goes away, its subtree goes with it, and its
  /// rows are freed. `Entity.destroy()` is what runs, so the unmount events
  /// fire and the rows are released in the order that method documents.
  /// [Child.detach] is the operation that unlinks and keeps the entity alive,
  /// and [adopt] the one that moves it somewhere else.
  ///
  /// Throws if [child] isn't currently a child of this entity - which catches
  /// both "never attached" and "attached to a different parent", and is the
  /// whole reason this is not simply `child.destroy()`. Destroying somebody
  /// else's child through this parent would report success for work it did
  /// not do.
  void removeChild(Entity child) {
    final childComponent = _requireChild(child);
    // `readPending`, for the same reason the splice needs it: a chain edited
    // earlier this tick is only visible in the write slot.
    if (childComponent.parent.readPending(child) != entity) {
      throw ArgumentError.value(
        child,
        'child',
        'is not currently a child of $entity',
      );
    }
    child.destroy();
  }

  /// Splices [child] out of this entity's child list and clears its
  /// parent/sibling links, leaving it alive and unparented.
  ///
  /// The shared half of [adopt], [Child.detach] and `Entity.destroy()`.
  /// Internal because unlinking on its own is one of those three from the
  /// caller's side, never a thing to do by itself: an entity left unlinked
  /// and unclaimed is reachable only through a handle nobody is holding.
  @internal
  void unlinkChild(Entity child) {
    final childComponent = _requireChild(child);
    final self = component;
    // `readPending` throughout, for the same reason the splice needs it:
    // unlinking is a read-modify-write over the chain, and two removals in one
    // tick would both read the *published* neighbours - so the second would
    // restitch the list as it stood before the first, silently resurrecting a
    // link. See `DataPointer.readPending`.
    final prev = childComponent.prevSibling.readPending(child);
    final next = childComponent.nextSibling.readPending(child);
    if (prev == null) {
      self.firstChild[this] = next;
    } else {
      prev.get<Child>().nextSibling[prev] = next;
    }
    if (next == null) {
      self.lastChild[this] = prev;
    } else {
      next.get<Child>().prevSibling[next] = prev;
    }
    childComponent
      ..parent[child] = null
      ..nextSibling[child] = null
      ..prevSibling[child] = null;
    // A declared child also fills a named slot on this row, and unlinking it
    // has to empty that too. Left alone, `parent<Parent>()[barrel]` keeps
    // answering with a row that is about to be freed and recycled - a stale
    // link that reads as valid, which is the defect shape this repo keeps
    // finding, made worse by `Entity` carrying no generation counter.
    //
    // The archetype check is the same one the read does, for the same reason:
    // this column belongs to the declaring archetype and addresses something
    // else on another's row.
    if (childComponent.declaredInArchetype == archetypeId) {
      childComponent.declaredIn![this] = null;
    }
  }

  /// Rejects a declared-child slot that this entity's row does not carry.
  ///
  /// Both cases are declaration mistakes - a prefab nothing declared as a
  /// child, or one declared by some other archetype - so both are settled
  /// the first time the line runs and neither can start being true in a
  /// shipped build. `assert(_declaredHere(child))` at the one call site
  /// keeps them out of release, where this is a column read.
  ///
  /// The second case is the declared-child spelling of the general rule that
  /// `data_layout`'s row guard now states for every column: a column is a
  /// byte offset into one archetype's row and means nothing in another's.
  bool _declaredHere(Child child) {
    if (child.declaredIn == null) {
      throw StateError(
        '${child.runtimeType} was not declared as a child of anything, so no '
        'entity holds one. `EntityStruct.of(...)` in a prefab\'s field '
        'initialisers declares a child; the same call in a scene declares a '
        'scene entity, and a scene entity is spawned with '
        '`scene.addEntity(prefab)` rather than held by a parent.',
      );
    }
    if (child.declaredInArchetype != archetypeId) {
      throw StateError(
        'Entity $entity is of archetype '
        '${ArchetypeRegistry.byId(archetypeId).prefab.runtimeType}, which did '
        'not declare ${child.runtimeType}. The declaration reserved a column '
        'on the declaring archetype\'s row, and that offset addresses '
        'something else here.',
      );
    }
    return true;
  }

  Child _requireChild(Entity child) {
    final childComponent = child.tryGet<Child>();
    if (childComponent == null) {
      throw ArgumentError.value(
        child,
        'child',
        'does not mix in Child - cannot be attached to a parent',
      );
    }
    return childComponent;
  }

  /// Refuses a link that would close a loop, by walking up from the
  /// prospective parent and looking for [child].
  ///
  /// At the point of creation, which is the only place it can be answered
  /// cheaply and the only place a caller can be told. `goo2d` and `goo3d`
  /// each carry a `maxHierarchyDepth` bail-out in their world-transform walk
  /// that catches the *symptom* - in debug, in a consumer, long after the
  /// `addChild` that caused it returned successfully, and with a message that
  /// cannot tell a legitimately deep tree from a cyclic one. In release those
  /// are a bare `return`, so the transforms are silently wrong; and they only
  /// cover that one walk, while `Entity.destroy()` recurses a subtree with no
  /// cap at all and would simply not terminate.
  ///
  /// O(depth) on a structural edit, and `SceneStruct.addEntityIn` puts it on
  /// the spawn path - a fresh row's chain is one link long, but a declared
  /// child's is as deep as the declaration nests, and a burst of five
  /// thousand entities walks it five thousand times. That is why it is
  /// spelled `assert(_requireAcyclic(child))` at its one call site rather
  /// than called outright: a release build should not walk a chain to
  /// re-answer a question about the shape of the code, which is what a cycle
  /// is. It returns `true`, or throws.
  bool _requireAcyclic(Entity child) {
    var ancestor = entity;
    while (true) {
      if (ancestor == child) {
        throw ArgumentError.value(
          child,
          'child',
          entity == child
              ? 'cannot be its own parent'
              : 'is already an ancestor of $entity, so attaching it here '
                    'would close a loop in the hierarchy',
        );
      }
      final link = ancestor.tryGet<Child>();
      if (link == null) break;
      final above = link.parent.readPending(ancestor);
      if (above == null) break;
      ancestor = above;
    }
    return true;
  }

  void _append(Child childComponent, Entity child) {
    assert(_requireAcyclic(child));
    final self = component;
    // `readPending`, not `lastChild[this]`. An ordinary read sees the last
    // *published* snapshot, so two `addChild` calls in the same tick both read
    // the same stale tail, both take the `oldLast == null` branch, and the
    // second silently overwrites the first - the parent ends up with one child
    // and the rest are orphaned with no error anywhere. Spawning a character
    // with three attachments from one command is exactly that shape, and so is
    // one prefab declaring three children with `EntityStruct.of`. See
    // `DataPointer.readPending`.
    final oldLast = self.lastChild.readPending(this);
    childComponent.prevSibling[child] = oldLast;
    childComponent.nextSibling[child] = null;
    if (oldLast == null) {
      self.firstChild[this] = child;
    } else {
      oldLast.get<Child>().nextSibling[oldLast] = child;
    }
    self.lastChild[this] = child;
    childComponent.parent[child] = this;
  }
}

/// What an entity can do about the parent it hangs off.
extension ChildAccessor on Accessor<Child> {
  /// Unlinks this entity from its parent, keeping it and its subtree alive.
  ///
  /// The counterpart to `ParentAccessor.removeChild`, which destroys instead.
  /// Nothing happens if this entity has no parent.
  ///
  /// What is left is a root: alive, holding its own children, and reachable
  /// only through a handle the caller keeps. Nothing else refers to it, and an
  /// `Entity` carries no generation, so a dropped handle leaves the subtree
  /// occupying rows until its scene unloads.
  void detach() {
    final parent = component.parent.readPending(this);
    if (parent == null) return;
    parent<Parent>().unlinkChild(this);
  }
}
