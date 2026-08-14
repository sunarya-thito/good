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

    test('appending three children preserves order via the sibling chain', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final children = [for (var i = 0; i < 3; i++) level.addEntity(level.leaf)];
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

    test('removing a middle child splices it out without breaking the chain', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final children = [for (var i = 0; i < 3; i++) level.addEntity(level.leaf)];
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
    });

    test('removing the first and last child updates firstChild/lastChild', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final children = [for (var i = 0; i < 3; i++) level.addEntity(level.leaf)];
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

    test('removeChild throws for an entity that is not currently a child of self', () {
      final level = _level();
      level.pool.beginTick();
      final parentA = level.addEntity(level.node);
      final parentB = level.addEntity(level.node);
      final child = level.addEntity(level.leaf);
      level.node.addChild(parentA, child);
      level.pool.commitTick();

      expect(() => level.node.removeChild(parentB, child), throwsArgumentError);
    });
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

      expect(() => level.addEntity(level.leaf, parent: notAParent), throwsArgumentError);
    });

    test('appending several via addEntity preserves order', () {
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.node);
      final children = [for (var i = 0; i < 4; i++) level.addEntity(level.leaf, parent: parent)];
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
}
