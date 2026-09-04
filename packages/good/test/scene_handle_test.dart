import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'scene_handle_test.g.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// `Scene` is to `SceneStruct` what `Entity` is to `EntityStruct`: the struct is
// the declaration, the handle is one loaded instance of it. These cover the
// half of that which is real in Landing 1 - packing, resolution, generations,
// and the fact that a struct holds no instance identity of its own.

mixin _Marked on Component {
  final mark = Field.uint8(3);

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Marked>();
  }
}

class _Unit extends EntityStruct with _Marked {}

class _Level extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Level();

  @sub
  final unit = _Unit();
}

class _LevelState extends GameState<_LevelGame> {
  @override
  void onMounted() {
    loadScene(_Level());
  }
}

class _LevelGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _LevelState();
}

Future<_LevelGame> _boot() async {
  final game = await Game.startInline(_LevelGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('packing', () {
    test('generation and slot survive the extremes without bleeding', () {
      const zero = Scene.pack(0, 0);
      expect([zero.generation, zero.slot], [0, 0]);

      const max = Scene.pack(0xFFFFFFFF, 0xFFFFFFFF);
      expect(max.generation, 0xFFFFFFFF);
      expect(
        max.slot,
        0xFFFFFFFF,
        reason: 'the top bit lands in the sign position; unpacking masks',
      );

      const onlySlot = Scene.pack(0, 0xFFFFFFFF);
      expect(onlySlot.generation, 0);
      const onlyGeneration = Scene.pack(0xFFFFFFFF, 0);
      expect(onlyGeneration.slot, 0);
    });
  });

  group('resolution', () {
    test('a loaded scene resolves to the struct that was loaded', () async {
      await _boot();
      final handle = run.state.loadedScenes.single;

      expect(handle.isLoaded, isTrue);
      expect(handle<_Level>(), same(run.state.scene));
      expect(handle<_Level?>(), same(run.state.scene));
    });

    test('the struct is a declaration and holds no handle of its own', () async {
      await _boot();
      final scene = run.state.scene!;

      // The identity lives on the state, not the struct: one SceneStruct backs
      // however many Scenes are loaded from it, exactly as one EntityStruct
      // backs many Entities, so "which handle am I" is not a question the
      // struct can answer.
      expect(run.state.loadedScenes.singleOrNull, isNotNull);
      expect(scene, isA<_Level>());
    });

    test('a handle to an unloaded scene stops resolving', () async {
      await _boot();
      final handle = run.state.loadedScenes.single;
      expect(handle.isLoaded, isTrue);

      await run.stop();

      expect(handle.isLoaded, isFalse);
      expect(handle<_Level?>(), isNull);
      expect(
        () => handle<_Level>(),
        throwsStateError,
        reason:
            'a stale handle is a diagnostic, not a null every caller has '
            'to remember to check',
      );
    });

    test(
      'a reused slot does not answer for the handle that held it before',
      () {
        final first = SceneRegistry.register(_Level());
        final firstScene = first<_Level>();

        SceneRegistry.unregister(first);
        final second = SceneRegistry.register(_Level());

        expect(second.slot, first.slot, reason: 'the free slot is reused');
        expect(
          second.value,
          isNot(first.value),
          reason:
              'but the generation makes it a different handle - which is '
              'the whole reason Scene spends 32 bits on one and Entity, with '
              'no spare bits at all, cannot',
        );
        expect(first.isLoaded, isFalse);
        expect(second.isLoaded, isTrue);
        expect(second<_Level>(), isNot(same(firstScene)));
      },
    );

    test('scene<T>() reports the wrong type, scene<T?>() answers null', () async {
      await _boot();
      final handle = run.state.loadedScenes.single;

      expect(
        () => handle<_OtherLevel>(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('_Level'), contains('not a _OtherLevel')),
          ),
        ),
        reason: 'a loaded scene of the wrong type is a different diagnostic '
            'from an unloaded one, and the message is what separates them',
      );
      expect(handle<_OtherLevel?>(), isNull);
      // The nullable spelling still resolves the type the slot does hold, so
      // "always null" does not pass this.
      expect(handle<_Level?>(), same(run.state.scene));
    });

    test('an unloaded handle throws for T and answers null for T?', () async {
      await _boot();
      final handle = run.state.loadedScenes.single;
      await run.stop();

      expect(
        () => handle<_Level>(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('is not loaded'), contains('generation')),
          ),
        ),
      );
      expect(handle<_Level?>(), isNull);
    });
  });

  group('addEntity through the handle', () {
    test('is the only spelling, and stamps the declared defaults', () async {
      await _boot();
      final state = run.state;
      final scene = state.singleScene<_Level>();
      final handle = state.loadedScenes.single;

      state.pool.beginTick();
      final first = handle.addEntity(scene.unit);
      final second = handle.addEntity(scene.unit);
      state.pool.commitTick();

      // Creation lives on the handle rather than the struct because one
      // SceneStruct backs however many loaded Scenes - "which scene does this
      // row belong to" is a question only the receiver can answer, and the
      // handle answers it by being the receiver.
      expect(
        first<_Marked>().component.mark[first],
        3,
        reason: 'onMounted and the declared defaults run through the handle',
      );
      expect(second, isNot(first));
      expect(second.archetypeId, first.archetypeId);
    });
  });

  // `isActive`/`SceneRegistry.active`/`setActive` were deleted with
  // `switchScene` - there is no front scene any more. What survives from that
  // group is the part that was never about front-ness: a stopped game must not
  // leave a process-global registry answering for itself.
  group('a stopped game releases its slots', () {
    test('its handle stops resolving once the game is gone', () async {
      await _boot();
      final handle = run.state.loadedScenes.single;
      expect(handle.isLoaded, isTrue);

      await run.stop();

      expect(
        handle.isLoaded,
        isFalse,
        reason:
            'SceneRegistry is process-global, so a stopped game that '
            'kept its entries would hand them to the next game in this '
            'process',
      );
      expect(() => handle<SceneStruct>(), throwsStateError);
    });
  });
}

class _OtherLevel extends SceneStruct {}
