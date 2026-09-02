// flutter_test exports an unrelated EventDispatcher (its pointer-event test
// harness), so the engine's has to win here by name - same reason as
// event_scope_test.dart.
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;

import 'package:good/src/archetype.dart';
import 'package:good/src/data/hierarchy.dart';
import 'package:good/src/event.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';

// Declaring an event on the field that holds it, beside declaring it from a
// constructor body against `EventBus.events`.
//
// The two forms have to be the same declaration. `Event.of` reads the window
// the framework opens around the constructor call; `events` reads the owner.
// For an owner the framework builds, those are one binder, and this file pins
// that they are: same owners, same composition, same delivery, whichever way
// each dispatcher was declared.
//
// The second form is what a `SceneStruct` declares through, and what the two
// base pairs on `EntityStruct` and `GameSystem` are declared through, since
// neither can assume a window.

/// The listener half. Writes into a shared log so *order* is observable and
/// not just membership.
mixin _Noted on GameListener {
  String get noted;

  static final List<String> log = <String>[];

  void onNoted(String event) => _Noted.log.add('$event:$noted');
}

class _NotedSystem extends GameSystem with _Noted {
  @override
  String get noted => 'system';
}

class _UnitA extends EntityStruct with _Noted {
  @override
  String get noted => 'unitA';
}

class _UnitB extends EntityStruct with _Noted {
  @override
  String get noted => 'unitB';

  /// A prefab declaring on its own field, which works because the scene below
  /// registers it with a constructor the framework calls.
  final own = Event.signal<_Noted>((listener) => listener.onNoted('own'));
}

class _NotedScene extends SceneStruct with _Noted {
  @override
  String get noted => 'scene';

  late final _UnitA a;
  late final _UnitB b;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    a = descriptor.has(_UnitA.new);
    b = descriptor.has(_UnitB.new);
  }
}

/// Every dispatcher on a field.
class _FieldState extends GameState<_FieldGame> with _Noted {
  @override
  String get noted => 'state';

  final alpha = Event.of<_Noted, String>(
    (listener, event) => listener.onNoted(event),
  );

  final beta = Event.of<_Noted, String>(
    (listener, event) => listener.onNoted(event),
    reverse: true,
  );

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_NotedSystem.new);
  }
}

/// The same two dispatchers, both from the constructor body.
class _BodyState extends GameState<_BodyGame> with _Noted {
  _BodyState() {
    alpha = events.has((listener, event) => listener.onNoted(event));
    beta = events.has(
      (listener, event) => listener.onNoted(event),
      reverse: true,
    );
  }

  @override
  String get noted => 'state';

  late final EventDispatcher<_Noted, String> alpha;
  late final EventDispatcher<_Noted, String> beta;

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_NotedSystem.new);
  }
}

/// One of each, on one owner: `alpha` on a field, `beta` in the body.
class _MixedState extends GameState<_MixedGame> with _Noted {
  _MixedState() {
    beta = events.has((listener, event) => listener.onNoted(event));
  }

  @override
  String get noted => 'state';

  final alpha = Event.of<_Noted, String>(
    (listener, event) => listener.onNoted(event),
  );

  late final EventDispatcher<_Noted, String> beta;

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_NotedSystem.new);
  }
}

/// A scene the state holds in a field, so it is constructed while the state's
/// own declaration window is open. Its base pair still has to reach this
/// scene and its prefabs, not the state's whole composition.
class _HeldScene extends SceneStruct with _Noted {
  @override
  String get noted => 'heldScene';

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    descriptor.has(_UnitA.new);
  }
}

/// Two more `SceneLifecycleListener`s, in the state's composition rather than
/// the scene's - so they are in the scene's list only if the pair landed on
/// the state. Two, so that a pair landing on the state collects a different
/// number from a pair landing on the scene.
class _SceneEarA extends GameSystem with SceneLifecycleListener {}

class _SceneEarB extends GameSystem with SceneLifecycleListener {}

class _HeldState extends GameState<_HeldGame> with _Noted {
  @override
  String get noted => 'state';

  final level = _HeldScene();

  /// Declared on the state, so it collects the state's composition - which is
  /// what the scene's own pair must not be.
  final sceneMounts = Event.of<SceneLifecycleListener, Scene>(
    (listener, scene) => listener.onSceneMounted(scene),
  );

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_SceneEarA.new);
    descriptor.has(_SceneEarB.new);
  }

  @override
  void onMounted() {
    loadScene(level);
  }
}

class _HeldGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  GameState createState() => _HeldState();
}

/// A prefab built by a fixture and handed to the scene already constructed -
/// `descriptor.has(() => _handed)`. Nothing was open above it, so its base
/// pair went to a registrar of its own.
class _Handed extends EntityStruct with _Noted, EntityLifecycleListener {
  @override
  String get noted => 'handed';

  final List<Entity> mounts = <Entity>[];

  @override
  void onEntityMounted(Entity entity) => mounts.add(entity);
}

/// A scene declaring its own event from its constructor body, which is the
/// route an owner the framework does not construct has.
class _BodyScene extends SceneStruct with _Noted {
  _BodyScene(this._handed) {
    swept = events.has((listener, event) => listener.onNoted(event));
  }

  final _Handed _handed;

  @override
  String get noted => 'bodyScene';

  late final EventDispatcher<_Noted, String> swept;

  late final _UnitA a;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    a = descriptor.has(_UnitA.new);
    descriptor.has(() => _handed);
  }
}

class _BodySceneGame extends Game {
  _BodySceneGame(this.handed);

  final _Handed handed;

  @override
  int get pageSize => 4096;

  late final _BodyScene level;

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    level = descriptor.has(_BodyScene(handed));
  }

  @override
  GameState createState() => _BodySceneState();
}

class _BodySceneState extends GameState<_BodySceneGame> with _Noted {
  @override
  String get noted => 'state';

  @override
  void onMounted() {
    loadScene(game.level);
  }
}

/// A system built by hand, with nothing open above it. Its inherited pair has
/// to land on its own registrar, the way a prefab's does.
class _BareSystem extends GameSystem with GameSystemLifecycleListener {
  int mounts = 0;

  @override
  void onMounted() => mounts++;
}

/// A system built in a `GameState` field initialiser and handed over through
/// a closure. Its one field dispatcher declared into the state's window.
class _Prebuilt extends GameSystem with _Noted {
  @override
  String get noted => 'prebuilt';

  final own = Event.signal<_Noted>((listener) => listener.onNoted('own'));
}

class _PrebuiltState extends GameState<_PrebuiltGame> with _Noted {
  @override
  String get noted => 'state';

  final _spawner = _Prebuilt();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(() => _spawner);
  }
}

class _PrebuiltGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  GameState createState() => _PrebuiltState();
}

/// A prefab declared from another prefab's field initialiser, so its
/// construction finishes while the declarer is still being built. Both hear
/// their own entities, so a pair that reached the wrong owner shows up as a
/// listener count.
class _NestedChild extends EntityStruct with Child, EntityLifecycleListener {
  final List<Entity> mounts = <Entity>[];

  @override
  void onEntityMounted(Entity entity) => mounts.add(entity);
}

class _NestedParent extends EntityStruct with Parent, EntityLifecycleListener {
  final child = EntityStruct.of(_NestedChild.new);

  final List<Entity> mounts = <Entity>[];

  @override
  void onEntityMounted(Entity entity) => mounts.add(entity);
}

class _NestedScene extends SceneStruct {
  late final _NestedParent parent;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    parent = descriptor.has(_NestedParent.new);
  }
}

class _NestedGame extends Game {
  @override
  int get pageSize => 4096;

  late final _NestedScene level;

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    level = descriptor.has(_NestedScene());
  }

  @override
  GameState createState() => _NestedState();
}

class _NestedState extends GameState<_NestedGame> {
  @override
  void onMounted() {
    loadScene(game.level);
  }
}

/// A listener a system offers alongside itself, so the system's inherited
/// pair collects more than one candidate and its order is observable at all.
class _Ear extends GameListenerBase with GameSystemLifecycleListener {
  _Ear(this.mark);

  final String mark;

  @override
  void onMounted() => _Noted.log.add('mount:$mark');

  @override
  void onUnmounted() => _Noted.log.add('unmount:$mark');
}

class _EarSystem extends GameSystem with GameSystemLifecycleListener {
  final _Ear first = _Ear('first');
  final _Ear second = _Ear('second');

  @override
  void collectListeners(ListenerCollector collector) {
    super.collectListeners(collector);
    collector.offer(first);
    collector.offer(second);
  }

  @override
  void onMounted() => _Noted.log.add('mount:system');

  @override
  void onUnmounted() => _Noted.log.add('unmount:system');
}

class _EarState extends GameState<_EarGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_EarSystem.new);
  }
}

class _EarGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  GameState createState() => _EarState();
}

abstract class _NotedGame extends Game {
  @override
  int get pageSize => 4096;

  late final _NotedScene level;

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    level = descriptor.has(_NotedScene());
  }
}

class _FieldGame extends _NotedGame {
  @override
  GameState createState() => _FieldState();
}

class _BodyGame extends _NotedGame {
  @override
  GameState createState() => _BodyState();
}

class _MixedGame extends _NotedGame {
  @override
  GameState createState() => _MixedState();
}

/// An owner outside the engine's four hosts, so the binder can be driven by
/// hand and the collect pass observed without a boot.
class _Pair extends GameListenerBase with EventBus, _Noted {
  @override
  String get noted => 'pair';

  /// Declared first and `late`, which is the shape the engine forbids. If a
  /// `late` initialiser ran when the field was written rather than when it is
  /// read, this one would be in the binder ahead of [eager].
  late final lazy = Event.signal<_Noted>(
    (listener) => listener.onNoted('lazy'),
  );

  final eager = Event.signal<_Noted>((listener) => listener.onNoted('eager'));
}

Future<T> _bootAny<T extends Game>(T Function() create) async {
  final run = await Game.startInline(create);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return run;
}

Future<T> _boot<T extends _NotedGame>(T Function() create) async {
  final run = await Game.startInline(create);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return run;
}

void main() {
  setUp(_Noted.log.clear);

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('a field and a constructor body declare the same thing', () {
    test('the collected lists are the same size', () async {
      final run = await _boot(_FieldGame.new);
      final state = run.state as _FieldState;

      expect(
        state.alpha.listenerCount,
        5,
        reason:
            'the state, the one system, the scene and its two prefabs - the '
            'same composition walk a body-declared dispatcher gets, reached '
            'through a binder that was open during the constructor',
      );
      expect(state.beta.listenerCount, state.alpha.listenerCount);
    });

    test('delivery order is identical, forward and reverse', () async {
      final fieldRun = await _boot(_FieldGame.new);
      (fieldRun.state as _FieldState).alpha('alpha');
      (fieldRun.state as _FieldState).beta('beta');
      final fromFields = List<String>.of(_Noted.log);

      await fieldRun.stop();
      SceneRegistry.reset();
      ArchetypeRegistry.reset();
      ComponentTypeRegistry.reset();
      _Noted.log.clear();

      final bodyRun = await _boot(_BodyGame.new);
      (bodyRun.state as _BodyState).alpha('alpha');
      (bodyRun.state as _BodyState).beta('beta');

      expect(
        fromFields,
        _Noted.log,
        reason:
            'same listeners, same order, both directions. Order is the order '
            'collectListeners offered candidates in, and where a dispatcher '
            'was declared does not enter into that',
      );
      expect(
        fromFields.first,
        'alpha:state',
        reason:
            'and the log is not empty, which would make the two equal for '
            'the wrong reason',
      );
      expect(fromFields.length, 10);
    });

    test('one owner can use both forms at once', () async {
      final run = await _boot(_MixedGame.new);
      final state = run.state as _MixedState;

      expect(
        state.beta.listenerCount,
        state.alpha.listenerCount,
        reason:
            'the body appended to the binder the field declarations already '
            'filled rather than getting one of its own',
      );

      state.alpha('alpha');
      final fromField = List<String>.of(_Noted.log);
      _Noted.log.clear();
      state.beta('beta');

      expect(
        _Noted.log,
        fromField.map((entry) => entry.replaceFirst('alpha:', 'beta:')),
        reason: 'and the two lists hold the same listeners in the same order',
      );
    });

    test('a prefab declares on its own field too', () async {
      final game = await _boot(_FieldGame.new);

      expect(
        game.level.b.own.listenerCount,
        1,
        reason:
            "a prefab's dispatcher reaches that prefab and nothing else, "
            'whichever way it was declared',
      );
      game.level.b.own.call();
      expect(_Noted.log, <String>['own:unitB']);
    });
  });

  group('an owner the framework did not construct', () {
    test('keeps its base pair on a registrar of its own', () async {
      final handed = _Handed();
      final run = await _bootAny(() => _BodySceneGame(handed));

      expect(
        handed.mountedEvent.listenerCount,
        1,
        reason:
            'the prefab itself, which is an EntityLifecycleListener, and '
            'nothing else. It was built with nothing open above it and '
            'registered through a closure, so the pair came off '
            'EventBus.events rather than off any window',
      );

      final entity = run.state.loadedScenes.single.addEntity(handed);

      expect(
        handed.mounts,
        <Entity>[entity],
        reason:
            'and it delivers: the pair is declared during construction, so '
            'it is filled by the same collect pass every other dispatcher is',
      );
    });

    test('a system built with no window has its pair too', () {
      final system = _BareSystem();

      expect(
        system.mountEvent.listenerCount,
        0,
        reason:
            'constructing it did not throw and the pair is assigned. A pair '
            'read off the declaration stack would have found it empty here',
      );

      EventBinder.bind(system);

      expect(
        system.mountEvent.listenerCount,
        1,
        reason:
            'the system itself, offered by the collect pass into the '
            'registrar its own constructor declared against',
      );

      system.mountEvent();
      expect(system.mounts, 1);
    });

    test('a scene held on a state field keeps its own base pair', () async {
      final run = await _bootAny(_HeldGame.new);
      final state = run.state as _HeldState;

      expect(
        state.level.mountedEvent.listenerCount,
        1,
        reason:
            'the scene itself. It was constructed inside the state window, '
            'so a pair taken off that window would have collected the state '
            'composition - which holds a second SceneLifecycleListener',
      );

      expect(
        state.sceneMounts.listenerCount,
        2,
        reason:
            'the two systems, which are the SceneLifecycleListeners in the '
            'state composition. So the count above is one because the pair '
            'is on the scene, and not a number the state binder could have '
            'produced as well',
      );
    });

    test('a scene declares its own event from its constructor body', () async {
      final handed = _Handed();
      final run = await _bootAny(() => _BodySceneGame(handed));

      expect(
        run.level.swept.listenerCount,
        3,
        reason:
            'the scene and the two prefabs it registered. A scene has no '
            'declaration window - the caller constructs it - so events is '
            'the route, and it collects the scene composition and not the '
            'game one',
      );

      run.level.swept('swept');
      expect(_Noted.log, <String>[
        'swept:bodyScene',
        'swept:unitA',
        'swept:handed',
      ]);
    });

    test('a prefab built with no window has its pair before any boot', () {
      final rock = _Handed();

      expect(
        rock.mountedEvent.listenerCount,
        0,
        reason:
            'assigned by the constructor, so it is readable without a game. '
            'The list is empty until the collect pass runs',
      );
    });
  });

  group('an owner built inside another owner window', () {
    test('is refused rather than collecting that owner composition', () async {
      await expectLater(
        Game.startInline(_PrebuiltGame.new),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('_Prebuilt was built inside another owner'),
              contains('descriptor.has(Spawner.new)'),
            ),
          ),
        ),
        reason:
            'the field dispatcher declared into the state window while the '
            'state field initialiser ran. Measured before this refused it: '
            'it collected the state, itself and two unrelated systems',
      );
    });
  });

  group('the initialiser has to be eager', () {
    test('a late field is missing from the collected list', () {
      final pair = EventBinder.open(_Pair.new);
      EventBinder.bind(pair);

      expect(
        pair.eager.listenerCount,
        1,
        reason:
            'the eager sibling declared and was collected, so the binder was '
            'open and working during the constructor - which is what makes '
            'the throw below the closed-window guard and not some earlier '
            'failure that took the whole object down',
      );

      pair.eager.call();
      expect(
        _Noted.log,
        <String>['eager:pair'],
        reason:
            'one dispatcher delivered, and there is no second one to deliver '
            'from: `lazy` was declared first and is still not in the list',
      );

      expect(
        () => pair.lazy,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('An Event was declared'),
          ),
        ),
        reason:
            'reading it is the first time its initialiser runs, and by then '
            'the binder is closed. A dispatcher built there would hold an '
            'empty list forever and deliver to nobody',
      );

      expect(
        pair.eager.listenerCount,
        1,
        reason: 'and the failed read added nothing to the owner it failed in',
      );
    });

    test('an owner the framework did not construct says so', () {
      expect(
        _Pair.new,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('An Event was declared'),
              contains('descriptor.has(Mote.new)'),
            ),
          ),
        ),
        reason:
            'the eager field runs during the constructor, and there is no '
            'binder open around a bare `_Pair()` - the same rule Field.* and '
            'Param.* state, said in the same place',
      );
    });
  });

  group('the inherited pair belongs to the object being constructed', () {
    test('a nested prefab does not hand its pair to its declarer', () async {
      final run = await _bootAny(_NestedGame.new);
      final parent = run.level.parent;

      expect(
        parent.child.mountedEvent.listenerCount,
        1,
        reason:
            'the child alone. It is constructed from the parent field '
            'initialiser, so its pair is declared while the parent is still '
            'being built - a pair the parent then took as well would put two '
            'listeners here',
      );
      expect(
        parent.mountedEvent.listenerCount,
        1,
        reason:
            'and the parent alone, so the count above is one because the two '
            'declarations were separated and not because nothing was '
            'collected at all',
      );

      final entity = run.state.loadedScenes.single.addEntity(parent);

      expect(
        parent.mounts,
        <Entity>[entity],
        reason: 'the parent hears its own entity, and the count above is a '
            'list that delivers',
      );
      expect(
        parent.child.mounts.length,
        1,
        reason:
            'and the child hears the child entity the spawn created, once. '
            'A pair the parent had also taken would deliver it twice',
      );
      expect(
        parent.child.mounts.single,
        isNot(entity),
        reason: 'and what it heard is the child entity, not the parent one',
      );
    });

    test('the system pair is collected in declaration order, and '
        'unmount reads it backwards', () async {
      final run = await _bootAny(_EarGame.new);
      final mounted = List<String>.of(_Noted.log);

      expect(
        mounted,
        <String>['mount:system', 'mount:first', 'mount:second'],
        reason:
            'collection order: the system offers itself first and its two '
            'ears after, and mountEvent delivers in that order',
      );

      _Noted.log.clear();
      await run.stop();

      expect(
        _Noted.log,
        <String>['unmount:second', 'unmount:first', 'unmount:system'],
        reason:
            'unmountEvent carries reverse: true, so the same list is read '
            'backwards and the system is told last - after everything it '
            'offered has been. Without the flag this would be the mount '
            'order again',
      );
    });
  });

  group('binding is once', () {
    test('a second collect pass is refused rather than doubling a list', () {
      final pair = EventBinder.open(_Pair.new);
      EventBinder.bind(pair);

      expect(
        () => EventBinder.bind(pair),
        throwsStateError,
        reason:
            'the late final dispatchers this replaced threw when assigned '
            'twice. A final field would not notice, and every listener would '
            'then receive every event twice',
      );
      expect(pair.eager.listenerCount, 1);
    });
  });
}
