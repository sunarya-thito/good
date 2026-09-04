// flutter_test exports an unrelated EventDispatcher (its pointer-event test
// harness), so the engine's has to win here by name - same reason as
// event_scope_test.dart.
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;

import 'package:good/src/archetype.dart';
import 'package:good/src/event.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'event_declaration_test.g.dart';

// Declaring an event on the field that holds it.
//
// `EventBinder.bind` collects the fields first and runs `describeEvents`
// after, so a dispatcher a hook hands back cannot be kept on a field at all:
// the collect pass reads that field before the hook has assigned it. What is
// left for a hook is a dispatcher nothing holds, which cannot be fired. So
// the field is the form, and what this file pins is its composition and its
// delivery order - forward and reverse - on every owner that has events.

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

  @sub
  final a = _UnitA();
  @sub
  final b = _UnitB();
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

/// An owner outside the engine's four hosts, so the binder can be driven by
/// hand and the collect pass observed without a boot.
class _Pair extends GameListenerBase with EventBus, _Noted {
  @override
  String get noted => 'pair';

  final eager = Event.signal<_Noted>((listener) => listener.onNoted('eager'));
}

Future<T> _boot<T extends _NotedGame>(T Function() create) async {
  final run = await Game.startInline(create);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return run;
}

void main() {
  _installDeclarations();

  setUp(_Noted.log.clear);

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('a dispatcher declared on a field', () {
    test('reaches the owner composition and nothing wider', () async {
      final run = await _boot(_FieldGame.new);
      final state = run.state as _FieldState;

      expect(
        state.alpha.listenerCount,
        5,
        reason:
            'the state, the one system, the scene and its two prefabs - the '
            'composition walk `collectListeners` offered, reached through a '
            'binder filled from the constructed object',
      );
      expect(state.beta.listenerCount, state.alpha.listenerCount);
    });

    test('reverse delivery is the forward order backwards', () async {
      final run = await _boot(_FieldGame.new);
      final state = run.state as _FieldState;

      state.alpha('alpha');
      final forward = List<String>.of(_Noted.log);
      _Noted.log.clear();
      state.beta('beta');

      expect(
        forward.first,
        'alpha:state',
        reason:
            'and the log is not empty, which would make the comparison below '
            'hold for the wrong reason',
      );
      expect(forward.length, 5);
      expect(
        _Noted.log,
        forward.reversed.map((entry) => entry.replaceFirst('alpha:', 'beta:')),
        reason:
            'same listeners either way; `reverse: true` is what turns the '
            'order around, and it turns around the whole of it',
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

  group('who may declare', () {
    // Two tests stood here and both were about the binder window: one that a
    // `late` dispatcher was missing from the collected list because its
    // initialiser ran after the window closed, and one that a bare `_Pair()`
    // threw because no window was open around it. Neither has a subject any
    // more. A declaration reaches nothing where it is written, so an owner
    // nobody wrapped declares exactly what one the framework built declares,
    // and the `late` rule is a build-time refusal - see
    // `good_cli/test/scan_test.dart`'s 'a late declaration is refused'.
    test('an owner the framework did not construct declares the same', () {
      final pair = _Pair();
      EventBinder.bind(pair);

      expect(
        pair.eager.listenerCount,
        1,
        reason:
            'nothing was open around `_Pair()`, and the dispatcher its field '
            'initialiser built was read off it by bind all the same',
      );

      pair.eager.call();
      expect(_Noted.log, <String>['eager:pair']);
    });
  });

  group('binding is once', () {
    test('a second collect pass is refused rather than doubling a list', () {
      final pair = _Pair();
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
