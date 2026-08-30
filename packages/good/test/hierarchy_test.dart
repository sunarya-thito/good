import 'package:good/src/scene_handle.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/data/hierarchy.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/struct.dart';
import 'package:flutter_test/flutter_test.dart';

mixin _Name on Component {
  final tag = Field.uint16();

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Name>();
  }
}

class _Node extends EntityStruct with _Name, Child, Parent {}

class _Leaf extends EntityStruct with _Name, Child {}

class _NoChild extends EntityStruct with _Name {}

/// `Child` + `Parent` and nothing else, so the row layout test can state the
/// hierarchy's own cost rather than that plus a fixture's tag field.
class _BareNode extends EntityStruct with Child, Parent {}

// --- declared children ----------------------------------------------------

class _Barrel extends EntityStruct with _Name, Child {}

class _Tip extends EntityStruct with _Name, Child {}

class _Turret extends EntityStruct with _Name, Child, Parent {
  final barrel = EntityStruct.of(_Barrel.new);
}

/// Three declared children, which is the shape `Parent.addChild`'s
/// `readPending` comment was written about - three links spliced in one tick.
class _Rig extends EntityStruct with _Name, Parent {
  final left = EntityStruct.of(_Barrel.new);
  final middle = EntityStruct.of(_Barrel.new);
  final right = EntityStruct.of(_Barrel.new);
}

class _DeepBarrel extends EntityStruct with _Name, Child, Parent {
  final tip = EntityStruct.of(_Tip.new);
}

class _DeepTurret extends EntityStruct with _Name, Parent {
  final barrel = EntityStruct.of(_DeepBarrel.new);
}

// Declaration-time errors. Each is registered by `_oneOff` in its own scene,
// because the failure is registration and a scene only registers once.

class _SelfDeclaring extends EntityStruct with _Name, Child, Parent {
  final loop = EntityStruct.of(_SelfDeclaring.new);
}

class _DeclaresANonChild extends EntityStruct with _Name, Parent {
  final loose = EntityStruct.of(_NoChild.new);
}

class _DeclaresWithoutParent extends EntityStruct with _Name, Child {
  final barrel = EntityStruct.of(_Barrel.new);
}

/// A child whose `describeStruct` reaches for `Field.*` instead of the
/// descriptor it was handed. That body runs while its *declarer's*
/// constructor is still on the declaration stack, so without a barrier the
/// column would land on the declarer's row.
class _StrayFieldChild extends EntityStruct with _Name, Child {
  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    Field.float64();
  }
}

class _DeclaresStrayFieldChild extends EntityStruct with _Name, Parent {
  final stray = EntityStruct.of(_StrayFieldChild.new);
}

// --- the lifecycle-listener route -----------------------------------------

final List<String> _dispatchLog = <String>[];

/// The shape a `Parent.onEntityMounted` would have: a component mixin that is
/// also a lifecycle listener.
mixin _Probe on Component, EntityLifecycleListener {
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Probe>();
  }

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    _dispatchLog.add('mixin mounted');
  }

  @override
  void onEntityUnmounted(Entity entity) {
    super.onEntityUnmounted(entity);
    _dispatchLog.add('mixin unmounted');
  }
}

class _Probed extends EntityStruct with EntityLifecycleListener, _Probe {}

class _ProbedSuperLast extends EntityStruct
    with EntityLifecycleListener, _Probe {
  @override
  void onEntityMounted(Entity entity) {
    _dispatchLog.add('struct mounted');
    super.onEntityMounted(entity);
  }
}

class _ProbedNoSuper extends EntityStruct with EntityLifecycleListener, _Probe {
  @override
  void onEntityMounted(Entity entity) {
    _dispatchLog.add('struct mounted');
  }
}

class _Level extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Level();

  late final _Node node;
  late final _Leaf leaf;
  late final _NoChild noChild;
  late final _BareNode bareNode;
  late final _Turret turret;
  late final _Rig rig;
  late final _DeepTurret deepTurret;
  late final _Probed probed;
  late final _ProbedSuperLast probedSuperLast;
  late final _ProbedNoSuper probedNoSuper;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    node = descriptor.has(_Node.new);
    leaf = descriptor.has(_Leaf.new);
    noChild = descriptor.has(_NoChild.new);
    bareNode = descriptor.has(_BareNode.new);
    turret = descriptor.has(_Turret.new);
    rig = descriptor.has(_Rig.new);
    deepTurret = descriptor.has(_DeepTurret.new);
    probed = descriptor.has(_Probed.new);
    probedSuperLast = descriptor.has(_ProbedSuperLast.new);
    probedNoSuper = descriptor.has(_ProbedNoSuper.new);
  }
}

/// Registers one prefab in a scene of its own, for the cases where
/// *registration itself* is what has to fail.
void _register<T extends EntityStruct>(T Function() create) {
  final scene = _OneOff(create);
  final pool = MemoryPool(pageSize: 4096);
  addTearDown(pool.dispose);
  scene.initializeScene(pool);
}

class _OneOff<T extends EntityStruct> extends SceneStruct {
  _OneOff(this._create);

  final T Function() _create;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    descriptor.has(_create);
  }
}

_Level _level() {
  final level = _Level()..initializeScene(MemoryPool(pageSize: 4096));
  level.handle = SceneRegistry.register(level);
  addTearDown(level.pool.dispose);
  return level;
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('row layout', () {
    test('the five hierarchy handles cost one flag byte between them', () {
      // Every entity in a hierarchy carries this archetype, so the flag
      // bytes are paid per entity. `Child`'s three `optEntity` fields and
      // `Parent`'s two each declare a 1-bit presence flag before a 64-bit
      // handle, and the handle's byte-alignment rounding skips the rest of
      // the flag's byte - so each one used to take nine bytes and strand
      // seven bits, five bytes of flags for five bits of information.
      // `ArchetypeStorage.declareFlagBit` gives the later flags those
      // stranded bits: 45 bytes becomes 41.
      //
      // The two mixins matter here. They are declared separately and know
      // nothing of each other, so no ordering they could choose for their
      // own fields would pack flags across the pair - only recycling at the
      // allocator does.
      final level = _level();
      expect(level.bareNode.archetype.bitLength, (1 + 7) + 5 * 64);
      expect(level.bareNode.archetype.strideBytes, 41);

      // Sharing a byte only helps if the flags stay independent, so write
      // every combination that could alias: set all five, then clear them
      // one at a time and check the rest survive.
      level.pool.beginTick();
      final a = level.addEntity(level.node);
      final b = level.addEntity(level.node);
      final c = level.addEntity(level.node);
      a<Parent>().addChild(b);
      a<Parent>().addChild(c);
      level.pool.commitTick();

      expect(level.node.parentFirstChild[a], b);
      expect(level.node.parentLastChild[a], c);
      expect(level.node.childParent[b], a);
      expect(level.node.childNextSibling[b], c);
      expect(level.node.childPrevSibling[c], b);
      expect(level.node.childParent[a], isNull);
      expect(level.node.childNextSibling[a], isNull);

      level.pool.beginTick();
      b<Child>().detach();
      level.pool.commitTick();

      // b's three flags cleared; a's two and c's links are in the same byte
      // of their own rows and must be untouched.
      expect(level.node.childParent[b], isNull);
      expect(level.node.childNextSibling[b], isNull);
      expect(level.node.childPrevSibling[b], isNull);
      expect(level.node.parentFirstChild[a], c);
      expect(level.node.parentLastChild[a], c);
      expect(level.node.childParent[c], a);
    });
  });

  group('Parent.addChild / Child.detach', () {
    test('a single child becomes both the first and the last child', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final child = level.addEntity(level.leaf);
      parent<Parent>().addChild(child);
      level.pool.commitTick();

      expect(level.node.parentFirstChild[parent], child);
      expect(level.node.parentLastChild[parent], child);
      expect(child<Child>().component.childParent[child], parent);
      expect(child<Child>().component.childNextSibling[child], isNull);
      expect(child<Child>().component.childPrevSibling[child], isNull);
    });

    // The same append, but on a tick that is **not** the page's first.
    //
    // Every other case here runs before any publish, and a read on a page that
    // has never published falls through to the write slot - so a
    // read-modify-write happens to see its own earlier writes and the chain
    // comes out right. From the second tick on it does not: reads see the last
    // published snapshot, so each `addChild` in one tick reads the same stale
    // `parentLastChild` and believes it is the first child there has ever been.
    // Spawning a character with three attachments in one command is exactly
    // this, and it silently kept only the last one.
    test(
      'appending three children in one tick works after the first publish',
      () {
        final level = _level();
        level.pool.beginTick();
        final parent = level.addEntity(level.node);
        level.pool.commitTick();

        level.pool.beginTick();
        final children = [
          for (var i = 0; i < 3; i++) level.addEntity(level.leaf),
        ];
        for (final c in children) {
          parent<Parent>().addChild(c);
        }
        level.pool.commitTick();

        expect(level.node.parentFirstChild[parent], children[0]);
        expect(level.node.parentLastChild[parent], children[2]);

        final walked = <Entity>[];
        Entity? at = level.node.parentFirstChild[parent];
        while (at != null) {
          walked.add(at);
          at = at<Child>().component.childNextSibling[at];
        }
        expect(
          walked,
          children,
          reason:
              'every child added this tick has to be on the chain, not '
              'just the last one to overwrite parentLastChild',
        );
      },
    );

    test('appending three children preserves order via the sibling chain', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final children = [
        for (var i = 0; i < 3; i++) level.addEntity(level.leaf),
      ];
      for (final c in children) {
        parent<Parent>().addChild(c);
      }
      level.pool.commitTick();

      expect(level.node.parentFirstChild[parent], children[0]);
      expect(level.node.parentLastChild[parent], children[2]);

      // Walk parentFirstChild -> childNextSibling and confirm it visits all
      // three, in append order.
      final walked = <Entity>[];
      Entity? cursor = level.node.parentFirstChild[parent];
      while (cursor != null) {
        walked.add(cursor);
        cursor = cursor<Child>().component.childNextSibling[cursor];
      }
      expect(walked, children);

      // And backwards via childPrevSibling from parentLastChild.
      final walkedBack = <Entity>[];
      cursor = level.node.parentLastChild[parent];
      while (cursor != null) {
        walkedBack.add(cursor);
        cursor = cursor<Child>().component.childPrevSibling[cursor];
      }
      expect(walkedBack, children.reversed.toList());
    });

    test(
      'detaching a middle child splices it out without breaking the chain',
      () {
        final level = _level();
        level.pool.beginTick();
        final parent = level.addEntity(level.node);
        final children = [
          for (var i = 0; i < 3; i++) level.addEntity(level.leaf),
        ];
        for (final c in children) {
          parent<Parent>().addChild(c);
        }
        children[1]<Child>().detach();
        level.pool.commitTick();

        expect(level.node.parentFirstChild[parent], children[0]);
        expect(level.node.parentLastChild[parent], children[2]);
        expect(
          children[0]<Child>().component.childNextSibling[children[0]],
          children[2],
        );
        expect(
          children[2]<Child>().component.childPrevSibling[children[2]],
          children[0],
        );
        // The detached child is fully unlinked, and still alive - which is
        // the whole difference between this and removeChild.
        final removed = children[1]<Child>().component;
        expect(removed.childParent[children[1]], isNull);
        expect(removed.childNextSibling[children[1]], isNull);
        expect(removed.childPrevSibling[children[1]], isNull);
      },
    );

    test('detaching the first and last child updates both ends', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final children = [
        for (var i = 0; i < 3; i++) level.addEntity(level.leaf),
      ];
      for (final c in children) {
        parent<Parent>().addChild(c);
      }
      children[0]<Child>().detach();
      children[2]<Child>().detach();
      level.pool.commitTick();

      expect(level.node.parentFirstChild[parent], children[1]);
      expect(level.node.parentLastChild[parent], children[1]);
      expect(children[1]<Child>().component.childNextSibling[children[1]], isNull);
      expect(children[1]<Child>().component.childPrevSibling[children[1]], isNull);
    });

    test('detaching the only child empties the list', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final child = level.addEntity(level.leaf);
      parent<Parent>().addChild(child);
      child<Child>().detach();
      level.pool.commitTick();

      expect(level.node.parentFirstChild[parent], isNull);
      expect(level.node.parentLastChild[parent], isNull);
    });

    test('addChild rejects an entity that does not mix in Child', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final notAChild = level.addEntity(level.noChild);
      level.pool.commitTick();

      expect(notAChild<Child?>().component, isNull);
      expect(() => parent<Parent>().addChild(notAChild), throwsArgumentError);
    });

    test(
      'removeChild throws for an entity that is not currently a child of self',
      () {
        final level = _level();
        level.pool.beginTick();
        final parentA = level.addEntity(level.node);
        final parentB = level.addEntity(level.node);
        final child = level.addEntity(level.leaf);
        parentA<Parent>().addChild(child);
        level.pool.commitTick();

        expect(
          () => parentB<Parent>().removeChild(child),
          throwsArgumentError,
        );
      },
    );
  });

  group('SceneStruct.addEntity with a parent', () {
    test('creates the entity and attaches it in one call', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final child = level.addEntity(level.leaf, parent: parent);
      level.pool.commitTick();

      expect(level.node.parentFirstChild[parent], child);
      expect(child<Child>().component.childParent[child], parent);
    });

    test('rejects a parent entity that does not mix in Parent', () {
      final level = _level();
      level.pool.beginTick();
      final notAParent = level.addEntity(level.leaf); // _Leaf has no Parent
      level.pool.commitTick();

      expect(
        () => level.addEntity(level.leaf, parent: notAParent),
        throwsArgumentError,
      );
    });

    test('appending several via addEntity preserves order', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final children = [
        for (var i = 0; i < 4; i++) level.addEntity(level.leaf, parent: parent),
      ];
      level.pool.commitTick();

      final walked = <Entity>[];
      Entity? cursor = level.node.parentFirstChild[parent];
      while (cursor != null) {
        walked.add(cursor);
        cursor = cursor<Child>().component.childNextSibling[cursor];
      }
      expect(walked, children);
    });
  });
  // Per-entity destruction, the counterpart to `Scene.addEntity`. Until this
  // existed the only way an entity could go away was unloading its whole
  // scene, so anything with a lifetime shorter than the level had nowhere to
  // go.
  group('Scene.removeEntity', () {
    test('unlinks the entity from its parent chain', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final a = level.addEntity(level.leaf);
      final b = level.addEntity(level.leaf);
      parent<Parent>()
        ..addChild(a)
        ..addChild(b);
      level.pool.commitTick();

      level.pool.beginTick();
      a.destroy();
      level.pool.commitTick();

      expect(level.node.parentFirstChild[parent], b);
      expect(level.node.parentLastChild[parent], b);
      expect(
        b<Child>().component.childPrevSibling[b],
        isNull,
        reason: 'b is now the only child, so it has no previous sibling',
      );
    });

    test('destroys the whole subtree, not just the entity named', () {
      final level = _level();
      level.pool.beginTick();
      final root = level.addEntity(level.node);
      final mid = level.addEntity(level.node);
      final leaf = level.addEntity(level.leaf);
      root<Parent>().addChild(mid);
      mid<Parent>().addChild(leaf);
      level.pool.commitTick();

      level.pool.beginTick();
      mid.destroy();
      level.pool.commitTick();

      expect(
        level.node.parentFirstChild[root],
        isNull,
        reason: 'root has no children left',
      );
      // Both freed rows are available again, which is the observable proof
      // the leaf went with its parent rather than being stranded live.
      level.pool.beginTick();
      final reused = <Entity>[
        level.addEntity(level.node),
        level.addEntity(level.leaf),
      ];
      level.pool.commitTick();
      expect(
        reused,
        containsAll(<Entity>[mid, leaf]),
        reason:
            'a freed row is recycled by the next allocation of its '
            'archetype - which is also why a handle must not outlive what '
            'it named',
      );
    });

    test(
      'removing several children in one tick keeps the chain consistent',
      () {
        final level = _level();
        level.pool.beginTick();
        final parent = level.addEntity(level.node);
        final children = [
          for (var i = 0; i < 4; i++) level.addEntity(level.leaf),
        ];
        for (final c in children) {
          parent<Parent>().addChild(c);
        }
        level.pool.commitTick();

        // Two removals in one tick, from the middle of the chain - the case
        // where each unlink has to see the previous one's rewiring.
        level.pool.beginTick();
        children[1].destroy();
        children[2].destroy();
        level.pool.commitTick();

        final walked = <Entity>[];
        Entity? at = level.node.parentFirstChild[parent];
        while (at != null) {
          walked.add(at);
          at = at<Child>().component.childNextSibling[at];
        }
        expect(walked, <Entity>[children[0], children[3]]);
        expect(level.node.parentLastChild[parent], children[3]);
      },
    );
  });
  group('Entity.scene', () {
    test('an entity names the scene it lives in, and refuses once freed', () {
      final level = _level();
      level.pool.beginTick();
      final entity = level.addEntity(level.leaf);
      level.pool.commitTick();

      // Read off the entity's own page, not fetched from anything more
      // general - which is what makes `entity.scene` an answer rather than an
      // assumption.
      expect(entity.scene, level.handle);

      // Deliberately *not* asserted after `destroy()`: a freed row leaves its
      // page in place, so the slot still resolves and `scene` still answers.
      // It cannot say otherwise - an Entity carries no generation - and an
      // accessor that guessed here would be worse than one that admits the
      // limit. Unloading the scene is the case it can speak for.
      SceneRegistry.unregister(level.handle);
      expect(() => entity.scene, throwsStateError);
    });
  });

  // What `EntityStruct.of` declares: a child of every entity of the declaring
  // prefab, spawned and linked at mount and destroyed with its parent.
  group('EntityStruct.of', () {
    test('spawning the parent spawns and links the declared child', () {
      final level = _level();
      level.pool.beginTick();
      final turret = level.addEntity(level.turret);
      level.pool.commitTick();

      final barrel = turret<Parent>()[level.turret.barrel];
      expect(level.turret.parentFirstChild[turret], barrel);
      expect(level.turret.parentLastChild[turret], barrel);
      expect(barrel<Child>().component.childParent[barrel], turret);
      expect(
        barrel<_Barrel?>().component,
        isNotNull,
        reason: 'the child is an entity of the declared prefab',
      );
    });

    // The hazard `Parent.addChild`'s `readPending` comment was written about,
    // reached by declaration rather than by three calls at a call site: three
    // links spliced into one chain inside a single tick. Through an ordinary
    // read it keeps one child and orphans two, with no error anywhere.
    test('a prefab declaring three children keeps all three', () {
      final level = _level();
      level.pool.beginTick();
      final rig = level.addEntity(level.rig);
      level.pool.commitTick();

      final left = rig<Parent>()[level.rig.left];
      final middle = rig<Parent>()[level.rig.middle];
      final right = rig<Parent>()[level.rig.right];
      expect(<Entity>{left, middle, right}, hasLength(3));

      final walked = <Entity>[];
      Entity? cursor = level.rig.parentFirstChild[rig];
      while (cursor != null) {
        walked.add(cursor);
        cursor = cursor<Child>().component.childNextSibling[cursor];
      }
      expect(
        walked,
        <Entity>[left, middle, right],
        reason:
            'declaration order is chain order, and none of the three '
            'overwrote another',
      );
      expect(level.rig.parentLastChild[rig], right);
    });

    test('declared children nest to whatever depth is declared', () {
      final level = _level();
      level.pool.beginTick();
      final turret = level.addEntity(level.deepTurret);
      level.pool.commitTick();

      final barrel = turret<Parent>()[level.deepTurret.barrel];
      final tip = barrel<Parent>()[level.deepTurret.barrel.tip];
      expect(barrel<Child>().component.childParent[barrel], turret);
      expect(tip<Child>().component.childParent[tip], barrel);
    });

    test('destroying the parent takes its declared children with it', () {
      final level = _level();
      level.pool.beginTick();
      final turret = level.addEntity(level.deepTurret);
      final barrel = turret<Parent>()[level.deepTurret.barrel];
      final tip = barrel<Parent>()[level.deepTurret.barrel.tip];
      level.pool.commitTick();

      level.pool.beginTick();
      turret.destroy();
      level.pool.commitTick();

      // Every row of the subtree is available again, which is the observable
      // proof nothing was promoted to a root and left alive. Spawning one
      // more `deepTurret` allocates exactly the same three rows in the same
      // order, so the handles come back numerically equal - which is also
      // why a handle must not outlive what it named.
      level.pool.beginTick();
      final again = level.addEntity(level.deepTurret);
      final againBarrel = again<Parent>()[level.deepTurret.barrel];
      final againTip = againBarrel<Parent>()[level.deepTurret.barrel.tip];
      level.pool.commitTick();
      expect(<Entity>[again, againBarrel, againTip], <Entity>[
        turret,
        barrel,
        tip,
      ]);
    });

    test('detaching a declared child empties the slot that named it', () {
      final level = _level();
      level.pool.beginTick();
      final turret = level.addEntity(level.turret);
      final barrel = turret<Parent>()[level.turret.barrel];
      level.pool.commitTick();

      level.pool.beginTick();
      barrel<Child>().detach();
      level.pool.commitTick();

      // A declared child is an ordinary child, so detaching it is allowed -
      // and the slot must stop naming it, because the row is now free to be
      // destroyed and recycled under a handle nothing can tell is stale.
      expect(() => turret<Parent>()[level.turret.barrel], throwsStateError);
      expect(level.turret.parentFirstChild[turret], isNull);
    });

    test(
      'asking a parent of another archetype for a child it never declared '
      'throws rather than reading a foreign offset',
      () {
        final level = _level();
        level.pool.beginTick();
        final node = level.addEntity(level.node);
        level.pool.commitTick();

        expect(() => node<Parent>()[level.turret.barrel], throwsStateError);
      },
    );

    test(
      'asking for a prefab nothing declared as a child throws rather than '
      'reading a column that does not exist',
      () {
        // `_Leaf` mixes in Child, so it type-checks as an argument, but no
        // prefab ever declared it with `EntityStruct.of` - so there is no
        // column on anybody's row holding one, and `declaredIn` is null.
        final level = _level();
        level.pool.beginTick();
        final node = level.addEntity(level.node);
        level.pool.commitTick();

        expect(level.leaf.declaredIn, isNull);
        expect(() => node<Parent>()[level.leaf], throwsStateError);
      },
    );

    // Issue #5: a row allocated mid-tick gets the right value in its write
    // slot while the published snapshot keeps the defaults, so an ordinary
    // read on the spawn tick is stale on any *recycled* row. Mounting a
    // declared child is exactly that - allocate, then write two rows - which
    // is why the read goes through `readPending`.
    test('a declared child is readable on its own mount tick, on a recycled '
        'row', () {
      final level = _level();
      level.pool.beginTick();
      final first = level.addEntity(level.turret);
      level.pool.commitTick();

      level.pool.beginTick();
      first.destroy();
      level.pool.commitTick();

      level.pool.beginTick();
      final second = level.addEntity(level.turret);
      expect(second, first, reason: 'the row was recycled, which is #5 case');
      final slot = level.turret.barrel.declaredIn!;
      expect(
        slot[second],
        isNull,
        reason:
            'the published snapshot still holds the default - this is #5, '
            'and it reproduces here',
      );
      expect(
        second<Parent>()[level.turret.barrel],
        slot.readPending(second),
        reason: 'the pending slot has the write this tick made',
      );
      level.pool.commitTick();

      expect(slot[second], isNotNull, reason: 'published on commit');
    });

    test('declaring the declaring struct is a registration error', () {
      expect(
        () => _register(_SelfDeclaring.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('_SelfDeclaring'), contains('->')),
          ),
        ),
      );
    });

    test('declaring a struct that does not mix in Child is rejected', () {
      expect(() => _register(_DeclaresANonChild.new), throwsArgumentError);
    });

    test('declaring children without mixing in Parent is rejected', () {
      expect(
        () => _register(_DeclaresWithoutParent.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('does not mix in Parent'),
          ),
        ),
      );
    });

    // Registration nests now, so "no open declaration context" stopped being
    // the same thing as "an empty stack". Without the barrier this declares a
    // column on the *declarer's* row and reads it back from the child's.
    test('a child reaching for Field.* in describeStruct still reports itself',
        () {
      expect(() => _register(_DeclaresStrayFieldChild.new), throwsStateError);
    });

    test('EntityStruct.of outside a registration reports itself', () {
      expect(() => EntityStruct.of(_Barrel.new), throwsStateError);
    });
  });

  group('addChild, adopt and cycles', () {
    test('addChild refuses an entity that already has a parent', () {
      final level = _level();
      level.pool.beginTick();
      final a = level.addEntity(level.node);
      final b = level.addEntity(level.node);
      final child = level.addEntity(level.leaf);
      a<Parent>().addChild(child);
      level.pool.commitTick();

      level.pool.beginTick();
      expect(() => b<Parent>().addChild(child), throwsArgumentError);
      level.pool.commitTick();
    });

    test('adopt moves a child from one parent to another', () {
      final level = _level();
      level.pool.beginTick();
      final a = level.addEntity(level.node);
      final b = level.addEntity(level.node);
      final child = level.addEntity(level.leaf);
      a<Parent>().addChild(child);
      level.pool.commitTick();

      level.pool.beginTick();
      b<Parent>().adopt(child);
      level.pool.commitTick();

      expect(level.node.parentFirstChild[a], isNull);
      expect(level.node.parentFirstChild[b], child);
      expect(level.leaf.childParent[child], b);
    });

    test('an entity cannot be its own parent', () {
      final level = _level();
      level.pool.beginTick();
      final a = level.addEntity(level.node);
      expect(() => a<Parent>().addChild(a), throwsArgumentError);
      level.pool.commitTick();
    });

    // Rejected where the loop would be made, not caught later by a depth cap
    // in a consumer: `Entity.destroy()` recurses a subtree with no cap and
    // would simply not terminate.
    test('adopting an ancestor into its own descendant is refused', () {
      final level = _level();
      level.pool.beginTick();
      final root = level.addEntity(level.node);
      final mid = level.addEntity(level.node);
      final leaf = level.addEntity(level.node);
      root<Parent>().addChild(mid);
      mid<Parent>().addChild(leaf);
      level.pool.commitTick();

      level.pool.beginTick();
      expect(
        () => leaf<Parent>().adopt(root),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('ancestor'),
          ),
        ),
      );
      level.pool.commitTick();
    });

    test('removeChild destroys the child and its subtree', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final child = level.addEntity(level.node);
      final grandchild = level.addEntity(level.leaf);
      parent<Parent>().addChild(child);
      child<Parent>().addChild(grandchild);
      level.pool.commitTick();

      level.pool.beginTick();
      parent<Parent>().removeChild(child);
      level.pool.commitTick();

      expect(level.node.parentFirstChild[parent], isNull);
      level.pool.beginTick();
      final reused = <Entity>[
        level.addEntity(level.node),
        level.addEntity(level.leaf),
      ];
      level.pool.commitTick();
      expect(
        reused,
        containsAll(<Entity>[child, grandchild]),
        reason:
            'both rows came back, so the subtree was destroyed rather '
            'than detached',
      );
    });

    test('removeChild refuses an entity that is another parent child', () {
      final level = _level();
      level.pool.beginTick();
      final a = level.addEntity(level.node);
      final b = level.addEntity(level.node);
      final child = level.addEntity(level.leaf);
      a<Parent>().addChild(child);
      level.pool.commitTick();

      level.pool.beginTick();
      expect(() => b<Parent>().removeChild(child), throwsArgumentError);
      level.pool.commitTick();
    });
  });

  // Why mounting declared children is a walk in `addEntityIn` and not an
  // `onEntityMounted` on `Parent`. The dispatch does reach a component mixin -
  // that half works - but the two cases below it do not, and the teardown half
  // is worse: `unmountEntitiesOf` fires the same dispatcher for every row of
  // an unloading scene, so a destroy cascade there would free rows the unload
  // is already freeing.
  group('the lifecycle-listener route', () {
    setUp(_dispatchLog.clear);

    test('a Component mixin does receive the entity lifecycle dispatch', () {
      final level = _level();
      level.pool.beginTick();
      level.addEntity(level.probed);
      level.pool.commitTick();
      expect(_dispatchLog, <String>['mixin mounted']);
    });

    test('a struct override decides when the mixin hook runs', () {
      final level = _level();
      level.pool.beginTick();
      level.addEntity(level.probedSuperLast);
      level.pool.commitTick();
      expect(_dispatchLog, <String>['struct mounted', 'mixin mounted']);
    });

    test('a struct override that omits super suppresses the mixin hook', () {
      final level = _level();
      level.pool.beginTick();
      level.addEntity(level.probedNoSuper);
      level.pool.commitTick();
      expect(_dispatchLog, <String>['struct mounted']);
    });

    test('scene unload fires the unmount dispatcher for every entity', () {
      final level = _level();
      level.pool.beginTick();
      level.addEntity(level.probed);
      level.addEntity(level.probed);
      level.pool.commitTick();
      _dispatchLog.clear();
      level.unmountEntitiesOf(level.handle.slot);
      expect(_dispatchLog, <String>['mixin unmounted', 'mixin unmounted']);
    });
  });
}
