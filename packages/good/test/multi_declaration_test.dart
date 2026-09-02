// A multi-instance component's declarations, made from the prefab's own field
// initialisers and taken by the component that owns them.
//
// The fixtures here declare `_Widget`s and `_Gadget`s rather than sprites and
// colliders, because the mechanism is in `good` and the two shipped users of
// it are in `goo2d`. A `_Widget` takes a real column, so a case that passed on
// a list but not on the row would still fail; a `_Gadget` takes none, which is
// what the last case needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/data/hierarchy.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';

/// One instance of the `_Widgets` component, with a column of its own.
final class _Widget {
  _Widget._(this.tag, this.size);

  static _Widget of(String tag, {int size = 0}) =>
      MultiComponent.declare(_Widget._(tag, Field.int32(size)));

  final String tag;
  final DataPointer<int> size;
}

/// A second kind, so a prefab carrying both proves the take is by type.
final class _Gadget {
  _Gadget._(this.tag);

  static _Gadget of(String tag) => MultiComponent.declare(_Gadget._(tag));

  final String tag;
}

mixin _Widgets on MultiComponent {
  final List<_Widget> widgets = MultiComponent.declared<_Widget>();
}

mixin _Gadgets on MultiComponent {
  final List<_Gadget> gadgets = MultiComponent.declared<_Gadget>();
}

class _Two extends EntityStruct with _Widgets {
  final first = _Widget.of('first', size: 1);
  final second = _Widget.of('second', size: 2);
}

/// Both components on one prefab, declared interleaved, so the take cannot be
/// "everything up to here".
class _Mixed extends EntityStruct with _Widgets, _Gadgets {
  final w1 = _Widget.of('w1');
  final g1 = _Gadget.of('g1');
  final w2 = _Widget.of('w2');
  final g2 = _Gadget.of('g2');
}

/// A base carrying the component, and a subclass declaring into it. The
/// subclass's initialisers run first and the mixin's last, which is the
/// ordering the whole mechanism rests on.
class _Base extends EntityStruct with _Widgets {
  final fromBase = _Widget.of('base');
}

class _Derived extends _Base {
  final fromDerived = _Widget.of('derived');
}

/// Declares a child prefab from a field initialiser, so the child is
/// constructed in the middle of this one's declarations.
class _Parent extends EntityStruct with _Widgets, Parent {
  final before = _Widget.of('before');
  final child = EntityStruct.of(_Child.new);
  final after = _Widget.of('after');
}

class _Child extends EntityStruct with _Widgets, Child {
  final own = _Widget.of('child');
}

/// Declares a widget and mixes in nothing that takes one.
class _Orphan extends EntityStruct {
  final stray = _Widget.of('stray');
}

/// Throws after declaring, so the collection has to unwind with the rest.
class _Throws extends EntityStruct with _Widgets {
  final declared = _Widget.of('declared');

  _Throws() {
    throw StateError('constructor failed after declaring');
  }
}

class _After extends EntityStruct with _Widgets {
  final mark = _Widget.of('mark', size: 5);
}

class _Level extends SceneStruct {
  late final Scene handle;

  late final _Two two;
  late final _Mixed mixed;
  late final _Derived derived;
  late final _Parent parent;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    two = descriptor.has(_Two.new);
    mixed = descriptor.has(_Mixed.new);
    derived = descriptor.has(_Derived.new);
    parent = descriptor.has(_Parent.new);
  }
}

class _OrphanScene extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    descriptor.has(_Orphan.new);
  }
}

/// Registers a prefab whose constructor throws, swallows it, and registers a
/// second one - so the second's declarations are its own only if the
/// collection unwound.
class _Broken extends SceneStruct {
  Object? thrown;
  late final _After after;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    try {
      descriptor.has(_Throws.new);
    } catch (e) {
      thrown = e;
    }
    after = descriptor.has(_After.new);
  }
}

_Level _level() {
  final level = _Level()..initializeScene(MemoryPool(pageSize: 4096));
  level.handle = SceneRegistry.register(level);
  addTearDown(level.pool.dispose);
  return level;
}

void main() {
  setUp(() {
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  tearDown(SceneRegistry.reset);

  test('the component holds every declaration, in declaration order', () {
    final level = _level();
    expect(
      <String>[for (final w in level.two.widgets) w.tag],
      <String>['first', 'second'],
    );
    expect(level.two.widgets[0], same(level.two.first));
    expect(level.two.widgets[1], same(level.two.second));
  });

  test('each declaration keeps a column of its own', () {
    final level = _level();
    final e = level.handle.addEntity(level.two);
    expect(level.two.first.size[e], 1);
    expect(level.two.second.size[e], 2);
    level.two.first.size[e] = 40;
    expect(
      level.two.second.size[e],
      2,
      reason: 'two declarations address two columns, not one',
    );
  });

  test('two components on one prefab each take only their own kind', () {
    final level = _level();
    expect(
      <String>[for (final w in level.mixed.widgets) w.tag],
      <String>['w1', 'w2'],
    );
    expect(
      <String>[for (final g in level.mixed.gadgets) g.tag],
      <String>['g1', 'g2'],
    );
  });

  test("a subclass's declarations reach the mixin below it", () {
    final level = _level();
    expect(
      <String>[for (final w in level.derived.widgets) w.tag],
      <String>['derived', 'base'],
      reason:
          'a mixin initialiser runs after the applying class\'s, so the '
          'subclass declares first and the mixin takes both',
    );
  });

  test('a declared child takes its own and leaves its declarer alone', () {
    final level = _level();
    expect(
      <String>[for (final w in level.parent.widgets) w.tag],
      <String>['before', 'after'],
    );
    expect(
      <String>[for (final w in level.parent.child.widgets) w.tag],
      <String>['child'],
    );
  });

  test('a declaration no component takes fails the registration by name', () {
    expect(
      () => _OrphanScene()..initializeScene(MemoryPool(pageSize: 4096)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('_Orphan'), contains('_Widget')),
        ),
      ),
    );
  });

  test('declaring with nothing being constructed says why', () {
    // `_Gadget` and not `_Widget`, and that is the whole point of the
    // fixture: a `_Widget` declares a column, so `Field.int32` refuses it
    // first and this guard is never the one that speaks. A declaration that
    // takes no column - a `_Gadget` here, a `TimelineStruct` in the engine -
    // reaches only this one.
    expect(
      () => _Gadget.of('loose'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('_Gadget'),
            contains('descriptor.has(MyStruct.new)'),
          ),
        ),
      ),
    );
  });

  test('a constructor that throws does not leave the collection open', () {
    final level = _Broken()..initializeScene(MemoryPool(pageSize: 4096));
    addTearDown(level.pool.dispose);
    expect(level.thrown, isA<StateError>());
    final handle = SceneRegistry.register(level);
    expect(
      <String>[for (final w in level.after.widgets) w.tag],
      <String>['mark'],
      reason:
          'the abandoned prefab declared one too, and it must not have been '
          'handed to the next one',
    );
    final e = handle.addEntity(level.after);
    expect(level.after.mark.size[e], 5);
    // The abandoned prefab's collection has to come off the stack as well as
    // stop being read: a leaked one is still "something being constructed",
    // and every later declaration outside a window would land in it silently.
    expect(
      () => _Gadget.of('loose'),
      throwsStateError,
      reason: 'the collection the abandoned prefab opened is still on the '
          'stack if this passes silently',
    );
  });
}
