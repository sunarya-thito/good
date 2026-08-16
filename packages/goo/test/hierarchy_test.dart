import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/archetype.dart';
import 'package:goo/src/data.dart';
import 'package:goo/src/data/hierarchy.dart';
import 'package:goo/src/pool.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/struct.dart';
import 'package:flutter_test/flutter_test.dart';

mixin _Name on Component {
  late final DataPointer<int> tag;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Name>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    tag = data.hasUint16();
  }
}

class _Node extends EntityStruct with _Name, Child, Parent {}

class _Leaf extends EntityStruct with _Name, Child {}

class _NoChild extends EntityStruct with _Name {}

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

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    node = descriptor.has(_Node());
    leaf = descriptor.has(_Leaf());
    noChild = descriptor.has(_NoChild());
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

  group('Parent.addChild / removeChild', () {
    test('a single child becomes both firstChild and lastChild', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final child = level.addEntity(level.leaf);
      level.node.addChild(parent, child);
      level.pool.commitTick();

      expect(level.node.firstChild[parent], child);
      expect(level.node.lastChild[parent], child);
      expect(child.get<Child>().parent[child], parent);
      expect(child.get<Child>().nextSibling[child], isNull);
      expect(child.get<Child>().prevSibling[child], isNull);
    });

    // The same append, but on a tick that is **not** the page's first.
    //
    // Every other case here runs before any publish, and a read on a page that
    // has never published falls through to the write slot - so a
    // read-modify-write happens to see its own earlier writes and the chain
    // comes out right. From the second tick on it does not: reads see the last
    // published snapshot, so each `addChild` in one tick reads the same stale
    // `lastChild` and believes it is the first child there has ever been.
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
          level.node.addChild(parent, c);
        }
        level.pool.commitTick();

        expect(level.node.firstChild[parent], children[0]);
        expect(level.node.lastChild[parent], children[2]);

        final walked = <Entity>[];
        Entity? at = level.node.firstChild[parent];
        while (at != null) {
          walked.add(at);
          at = at.get<Child>().nextSibling[at];
        }
        expect(
          walked,
          children,
          reason:
              'every child added this tick has to be on the chain, not '
              'just the last one to overwrite lastChild',
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
        level.node.addChild(parent, c);
      }
      level.pool.commitTick();

      expect(level.node.firstChild[parent], children[0]);
      expect(level.node.lastChild[parent], children[2]);

      // Walk firstChild -> nextSibling and confirm it visits all three, in
      // append order.
      final walked = <Entity>[];
      Entity? cursor = level.node.firstChild[parent];
      while (cursor != null) {
        walked.add(cursor);
        cursor = cursor.get<Child>().nextSibling[cursor];
      }
      expect(walked, children);

      // And backwards via prevSibling from lastChild.
      final walkedBack = <Entity>[];
      cursor = level.node.lastChild[parent];
      while (cursor != null) {
        walkedBack.add(cursor);
        cursor = cursor.get<Child>().prevSibling[cursor];
      }
      expect(walkedBack, children.reversed.toList());
    });

    test(
      'removing a middle child splices it out without breaking the chain',
      () {
        final level = _level();
        level.pool.beginTick();
        final parent = level.addEntity(level.node);
        final children = [
          for (var i = 0; i < 3; i++) level.addEntity(level.leaf),
        ];
        for (final c in children) {
          level.node.addChild(parent, c);
        }
        level.node.removeChild(parent, children[1]);
        level.pool.commitTick();

        expect(level.node.firstChild[parent], children[0]);
        expect(level.node.lastChild[parent], children[2]);
        expect(children[0].get<Child>().nextSibling[children[0]], children[2]);
        expect(children[2].get<Child>().prevSibling[children[2]], children[0]);
        // The removed child is fully detached.
        final removed = children[1].get<Child>();
        expect(removed.parent[children[1]], isNull);
        expect(removed.nextSibling[children[1]], isNull);
        expect(removed.prevSibling[children[1]], isNull);
      },
    );

    test('removing the first and last child updates firstChild/lastChild', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final children = [
        for (var i = 0; i < 3; i++) level.addEntity(level.leaf),
      ];
      for (final c in children) {
        level.node.addChild(parent, c);
      }
      level.node.removeChild(parent, children[0]);
      level.node.removeChild(parent, children[2]);
      level.pool.commitTick();

      expect(level.node.firstChild[parent], children[1]);
      expect(level.node.lastChild[parent], children[1]);
      expect(children[1].get<Child>().nextSibling[children[1]], isNull);
      expect(children[1].get<Child>().prevSibling[children[1]], isNull);
    });

    test('removing the only child empties the list', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final child = level.addEntity(level.leaf);
      level.node.addChild(parent, child);
      level.node.removeChild(parent, child);
      level.pool.commitTick();

      expect(level.node.firstChild[parent], isNull);
      expect(level.node.lastChild[parent], isNull);
    });

    test('addChild rejects an entity that does not mix in Child', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final notAChild = level.addEntity(level.noChild);
      level.pool.commitTick();

      expect(notAChild.tryGet<Child>(), isNull);
      expect(() => level.node.addChild(parent, notAChild), throwsArgumentError);
    });

    test(
      'removeChild throws for an entity that is not currently a child of self',
      () {
        final level = _level();
        level.pool.beginTick();
        final parentA = level.addEntity(level.node);
        final parentB = level.addEntity(level.node);
        final child = level.addEntity(level.leaf);
        level.node.addChild(parentA, child);
        level.pool.commitTick();

        expect(
          () => level.node.removeChild(parentB, child),
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

      expect(level.node.firstChild[parent], child);
      expect(child.get<Child>().parent[child], parent);
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
      Entity? cursor = level.node.firstChild[parent];
      while (cursor != null) {
        walked.add(cursor);
        cursor = cursor.get<Child>().nextSibling[cursor];
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
      level.node
        ..addChild(parent, a)
        ..addChild(parent, b);
      level.pool.commitTick();

      level.pool.beginTick();
      a.destroy();
      level.pool.commitTick();

      expect(level.node.firstChild[parent], b);
      expect(level.node.lastChild[parent], b);
      expect(
        b.get<Child>().prevSibling[b],
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
      level.node
        ..addChild(root, mid)
        ..addChild(mid, leaf);
      level.pool.commitTick();

      level.pool.beginTick();
      mid.destroy();
      level.pool.commitTick();

      expect(
        level.node.firstChild[root],
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
          level.node.addChild(parent, c);
        }
        level.pool.commitTick();

        // Two removals in one tick, from the middle of the chain - the case
        // where each unlink has to see the previous one's rewiring.
        level.pool.beginTick();
        children[1].destroy();
        children[2].destroy();
        level.pool.commitTick();

        final walked = <Entity>[];
        Entity? at = level.node.firstChild[parent];
        while (at != null) {
          walked.add(at);
          at = at.get<Child>().nextSibling[at];
        }
        expect(walked, <Entity>[children[0], children[3]]);
        expect(level.node.lastChild[parent], children[3]);
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
}
