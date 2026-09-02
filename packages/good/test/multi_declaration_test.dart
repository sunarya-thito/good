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
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';

/// One instance of the `_Widgets` component, with a column of its own.
final class _Widget {
  _Widget._(this.tag, this.size);

  static _Widget of(String tag, {int size = 0}) =>
      Component.declare(_Widget._(tag, Field.int32(size)));

  final String tag;
  final DataPointer<int> size;
}

/// A single-instance kind: one per prefab, held in one field on the component
/// rather than in a list. `TextLabel` is the shipped one.
final class _Badge {
  _Badge._(this.tag);

  static _Badge of(String tag) => Component.declare(_Badge._(tag));

  final String tag;
}

mixin _Badged on Component {
  final _Badge? badge = Component.declared<_Badge>();
}

/// A second kind, so a prefab carrying both proves the take is by type.
final class _Gadget {
  _Gadget._(this.tag);

  static _Gadget of(String tag) => Component.declare(_Gadget._(tag));

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

class _OneBadge extends EntityStruct with _Badged {
  final own = _Badge.of('own');
}

/// Mixes in the component and declares nothing, so the component's field has
/// to hold null rather than fail.
class _NoBadge extends EntityStruct with _Badged {}

/// Two of a kind the component holds one of.
class _TwoBadges extends EntityStruct with _Badged {
  final first = _Badge.of('first');
  final second = _Badge.of('second');
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
  late final _OneBadge oneBadge;
  late final _NoBadge noBadge;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    two = descriptor.has(_Two.new);
    mixed = descriptor.has(_Mixed.new);
    derived = descriptor.has(_Derived.new);
    parent = descriptor.has(_Parent.new);
    oneBadge = descriptor.has(_OneBadge.new);
    noBadge = descriptor.has(_NoBadge.new);
  }
}

/// Registers the prefab that declares two of a single-instance kind.
class _TwoBadgeScene extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    descriptor.has(_TwoBadges.new);
  }
}

/// A scene the framework constructs, holding a prefab that declares.
///
/// The headless fixtures above bring a scene up by calling `initializeScene`
/// on one the test built. This one goes the whole way round:
/// `GameSceneDescriptor.has(_GameLevel.new)` runs the scene's constructor
/// inside the declaration window, and `describeScene` registers the prefab
/// from there.
class _GameLevel extends SceneStruct {
  late final _Two two;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    two = descriptor.has(_Two.new);
  }
}

/// Declares a widget from a **scene's** own field initialiser.
///
/// A scene is constructed by the framework, with an event binder open around
/// it, so `final wounded = Event.of(...)` works there. No collection is open,
/// because a collection belongs to a prefab, and this is what says so.
class _DeclaringScene extends SceneStruct {
  final stray = _Gadget.of('scene');
}

class _SeamState extends GameState<_SeamGame> {}

class _SeamGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  late final _GameLevel level;

  @override
  GameState createState() => _SeamState();

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    level = descriptor.has(_GameLevel.new);
  }
}

class _DeclaringSceneGame extends _SeamGame {
  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    descriptor.has(_DeclaringScene.new);
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

  test('a single-instance component takes the one that was declared', () {
    final level = _level();
    expect(level.oneBadge.badge, same(level.oneBadge.own));
  });

  test('a prefab that declares none leaves the component holding null', () {
    final level = _level();
    expect(
      level.noBadge.badge,
      isNull,
      reason:
          'the component has a default to fall back on, so declaring none is '
          'a prefab that wants the default and not a mistake',
    );
  });

  test('a second declaration of a single-instance kind is refused', () {
    expect(
      () {
        _TwoBadgeScene().initializeScene(MemoryPool(pageSize: 4096));
      },
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('2 _Badges'), contains('a component holds one')),
        ),
      ),
      reason:
          'the component has one field, so the second would be stored nowhere '
          '- and the leftover check cannot report it, because the take '
          'removed both',
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

  test('a prefab in a game-declared scene gets its declarations', () async {
    final game = await Game.startInline(_SeamGame.new);
    addTearDown(() async {
      if (game.isRunning) await game.stop();
    });
    expect(
      <String>[for (final w in game.level.two.widgets) w.tag],
      <String>['first', 'second'],
      reason:
          'the scene is constructed inside the declaration window and its '
          'prefab is registered from describeScene, which is a different '
          'route in than initializeScene on a scene the test built',
    );
  });

  test('a scene declaring one of its own is refused, window or not', () {
    // A scene is framework-constructed and has an event binder open, so
    // `Event.of` on a scene field works. A collection belongs to a prefab and
    // there is none open here, so this has to say so rather than land in
    // whatever is underneath.
    expect(
      Game.startInline(_DeclaringSceneGame.new),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('_Gadget'), contains('no struct being constructed')),
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
