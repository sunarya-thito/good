import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/data/hierarchy.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';

/// The live run under test, bound the way `multi_scene_test.dart` binds it.
late Game run;

// A hierarchy edge between two loaded scenes. Two loaded instances of one
// `SceneStruct` never share a page, and a scene's pages are freed wholesale
// when it unloads, so an edge across two of them has a side that outlives the
// other - and before this was fixed, both survivors were unusable.

/// Both halves of the hierarchy on one prefab, so any of the four operations
/// can be pointed at any of these entities, plus a field to prove a row is
/// still readable after the other scene has gone.
class _Body extends EntityStruct with Child, Parent, EntityLifecycleListener {
  final mark = Field.uint16();

  @override
  void onEntityUnmounted(Entity entity) {
    super.onEntityUnmounted(entity);
    _unmounted.add(entity);
    // What the entity's parent link says at the moment it is announced. The
    // detach pass runs after every event, so this is the hierarchy as it
    // stood - not a row whose links were cut because it happened to sit in an
    // archetype the repair walk reached first.
    _parentAtUnmount[entity] = childParent.readPending(entity);
  }
}

final List<Entity> _unmounted = <Entity>[];
final Map<Entity, Entity?> _parentAtUnmount = <Entity, Entity?>{};

class _Level extends SceneStruct {
  late final _Body body;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    body = descriptor.has(_Body.new);
  }
}

class _CrossState extends GameState<_CrossGame> {}

class _CrossGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  late final _Level level;

  @override
  GameState createState() => _CrossState();

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    level = descriptor.has(_Level.new);
  }
}

Future<_CrossGame> _boot() async {
  final game = await Game.startInline(_CrossGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

/// The column writes `ParentAccessor._append` performs, spelled out with
/// nothing in front of them.
///
/// That is exactly what `addChild` *is* in a release build once the
/// same-scene assert has compiled out, and it is the only way a debug test
/// can reach the repair the unload path performs - reaching it through
/// `addChild` would trip the assert that the repair exists to back up.
/// Written for a parent with no children yet, which is all these cases need.
void _linkAcrossScenes(Entity parent, Entity child) {
  final parentComponent = parent<Parent>().component;
  final childComponent = child<Child>().component;
  childComponent
    ..childPrevSibling[child] = null
    ..childNextSibling[child] = null
    ..childParent[child] = parent;
  parentComponent
    ..parentFirstChild[parent] = child
    ..parentLastChild[parent] = child;
}

/// Live rows of [prefab] belonging to [scene], counted the way
/// `unmountEntitiesOf` walks them.
int _rowsIn(Scene scene, EntityStruct prefab) {
  final storage = prefab.archetype;
  var rows = 0;
  for (var i = 0; i < storage.pageCount; i++) {
    final page = storage.pageAt(i);
    if (page == null || page.ownerSceneSlot != scene.slot) continue;
    for (final _ in page.rowOffsets) {
      rows++;
    }
  }
  return rows;
}

Matcher _crossesScenes() => throwsA(
  isA<ArgumentError>().having(
    (e) => e.message,
    'message',
    contains('may not cross scenes'),
  ),
);

void main() {
  setUp(() {
    _unmounted.clear();
    _parentAtUnmount.clear();
  });

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  // --- the four operations, plus the spawn path ---------------------------

  test('addChild refuses a child from another scene', () async {
    final game = await _boot();
    final state = run.state;
    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);

    final parent = a.addEntity(game.level.body);
    final child = b.addEntity(game.level.body);
    expect(parent.sceneSlot, isNot(child.sceneSlot));

    expect(() => parent<Parent>().addChild(child), _crossesScenes());
  });

  test('adopt refuses to pull a child out of another scene', () async {
    final game = await _boot();
    final state = run.state;
    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);

    final here = a.addEntity(game.level.body);
    final there = b.addEntity(game.level.body);
    final child = b.addEntity(game.level.body, parent: there);

    expect(() => here<Parent>().adopt(child), _crossesScenes());
    expect(
      child<Child>().component.childParent.readPending(child),
      there,
      reason: 'and the refusal leaves the child where it was',
    );
  });

  test('removeChild refuses an entity of another scene', () async {
    final game = await _boot();
    final state = run.state;
    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);

    final parent = a.addEntity(game.level.body);
    final child = b.addEntity(game.level.body);

    // The reason this one is worth stating separately: before the check, the
    // call went through to `child.destroy()` and a scene-A parent destroyed a
    // scene-B row.
    expect(() => parent<Parent>().removeChild(child), _crossesScenes());
    expect(child<_Body>().component.mark[child], 0, reason: 'still there');
  });

  test('unlinkChild refuses an entity of another scene', () async {
    final game = await _boot();
    final state = run.state;
    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);

    final parent = a.addEntity(game.level.body);
    final child = b.addEntity(game.level.body);
    _linkAcrossScenes(parent, child);

    expect(() => parent<Parent>().unlinkChild(child), _crossesScenes());
  });

  test('addEntity refuses a parent in another loaded scene', () async {
    final game = await _boot();
    final state = run.state;
    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);

    final parent = a.addEntity(game.level.body);
    final before = _rowsIn(b, game.level.body);

    // `_declaredHere` passes here - one `SceneStruct` backs both loaded
    // instances, so comparing declarations cannot tell these two apart. Only
    // the slot can.
    //
    // Both halves of this matter, and the message is what separates them.
    // `addEntityIn` allocates the row *before* it links, so leaving the
    // rejection to `addChild` downstream would still throw - with the wrong
    // message, and one orphan row later. This asserts the spawn path refused
    // it itself.
    expect(
      () => b.addEntity(game.level.body, parent: parent),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('may not cross scenes'),
            contains('this spawn is into scene slot'),
          ),
        ),
      ),
    );
    expect(
      _rowsIn(b, game.level.body),
      before,
      reason:
          'refused before the row was allocated - caught downstream instead, '
          'the allocation has already happened and nothing frees it',
    );
  });

  // --- unload, both directions --------------------------------------------

  test('unloading the child\'s scene leaves the parent childless', () async {
    final game = await _boot();
    final state = run.state;
    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);

    final parent = a.addEntity(game.level.body);
    final child = b.addEntity(game.level.body);
    _linkAcrossScenes(parent, child);

    state.unloadScene(b);

    final parentComponent = parent<Parent>().component;
    expect(parentComponent.parentFirstChild.readPending(parent), isNull);
    expect(parentComponent.parentLastChild.readPending(parent), isNull);
    expect(
      _unmounted,
      contains(child),
      reason: 'the child still got its own unmount, in its own scene',
    );
    expect(
      _parentAtUnmount[child],
      parent,
      reason:
          'and it was announced with the link intact - the repair runs after '
          'every event, so a listener reads the hierarchy as it stood',
    );

    // The whole point. This used to throw part way down the subtree walk,
    // after firing half the events for it.
    parent.destroy();
    expect(_unmounted, contains(parent));
  });

  test('unloading the parent\'s scene leaves the child a root', () async {
    final game = await _boot();
    final state = run.state;
    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);

    final parent = a.addEntity(game.level.body);
    final child = b.addEntity(game.level.body);
    child<_Body>().component.mark[child] = 7;
    _linkAcrossScenes(parent, child);

    state.unloadScene(a);

    final childComponent = child<Child>().component;
    expect(childComponent.childParent.readPending(child), isNull);
    expect(childComponent.childPrevSibling.readPending(child), isNull);
    expect(childComponent.childNextSibling.readPending(child), isNull);
    expect(
      child<_Body>().component.mark[child],
      7,
      reason: 'alive and untouched apart from the link it lost',
    );

    // Both of these used to throw: they route through `unlinkChild`, which
    // wrote into the freed page, so the child could not be cleaned up by any
    // public means.
    child<Child>().detach();
    child.destroy();
    expect(_unmounted, contains(child));
  });

  test('a surviving grandchild keeps the subtree it owns', () async {
    final game = await _boot();
    final state = run.state;
    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);

    final parent = a.addEntity(game.level.body);
    final child = b.addEntity(game.level.body);
    final grandchild = b.addEntity(game.level.body, parent: child);
    _linkAcrossScenes(parent, child);

    state.unloadScene(a);

    expect(
      child<Child>().component.childParent.readPending(child),
      isNull,
      reason: 'the edge that crossed is cut',
    );
    expect(
      child<Parent>().component.parentFirstChild.readPending(child),
      grandchild,
      reason: 'and the subtree below the cut is left alone',
    );
  });

  test('an ordinary same-scene unload still tears its own tree down', () async {
    final game = await _boot();
    final state = run.state;
    final a = await state.loadScene(game.level);

    final parent = a.addEntity(game.level.body);
    final child = a.addEntity(game.level.body, parent: parent);

    state.unloadScene(a);

    expect(
      _unmounted,
      containsAll(<Entity>[parent, child]),
      reason: 'both announced',
    );
    expect(
      _parentAtUnmount[child],
      parent,
      reason:
          'and neither link was cut on the way out - the repair only touches '
          'edges that leave the scene',
    );
  });
}
