import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/declarations.g.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/input/input_binding.dart';
import 'package:good/src/input/input_key.dart';
import 'package:good/src/scannable.dart';
import 'package:good/src/system.dart';

// One system, one `Input.of` field, booted the way a real one is - through
// `describeSystems`, which is the only route a system reaches a run by. What
// this file pins is that the run takes that action exactly once.
//
// It is worth its own file because the count is not a tidiness figure. An
// index is how the registry addresses an action, and the resolution pass
// walks the same list once per fixed tick: an action that appears in it twice
// is resolved twice per tick, and the second resolution sees the state the
// first one left. `wasPressedThisFrame` is computed from the change between
// two resolutions, so the second one finds no change and clears the edge
// before any system reads it - the press is gone by the time the tick runs,
// while `pressed` still fires once. That is a live action the polling half of
// the API cannot see.

/// The fixture. One action, and both ways of hearing it: the polled edge
/// read in `onFixedUpdate`, and the stream that fires from the resolution
/// itself. They come apart under a duplicate, which is why both are here.
class _OneActionSystem extends GameSystem
    with FixedTickable, GameSystemLifecycleListener {
  final fire = Input.of(const TriggerBinding(InputKey.spacebar));

  int ticks = 0;
  int polledPresses = 0;
  int polledReleases = 0;
  int streamedPresses = 0;
  int streamedReleases = 0;

  @override
  void onMounted() {
    super.onMounted();
    fire.pressed += (event) => streamedPresses++;
    fire.released += (event) => streamedReleases++;
  }

  @override
  void onFixedUpdate() {
    ticks++;
    if (fire.wasPressedThisFrame) polledPresses++;
    if (fire.wasReleasedThisFrame) polledReleases++;
  }
}

class _OneActionState extends GameState<_OneActionGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_OneActionSystem.new);
  }
}

class _OneActionGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  /// The registry itself, caught on its way through the game's own hook. It
  /// is one object for the whole run, so the count read after boot is the
  /// count every source ended up contributing to.
  InputRegistry? registry;

  @override
  List<GeneratedDeclarations> get declarations =>
      const <GeneratedDeclarations>[goodDeclarations, _testDeclarations];

  @override
  GameState createState() => _OneActionState();

  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    registry = input as InputRegistry;
  }
}

// --- the collectors -------------------------------------------------------
//
// Written by hand rather than generated: `good_tool` reads `lib/`, so a class
// declared in a test has no table, and `collectDeclarations` throws for one
// it cannot find. The lists are what the generator would write - the class's
// own fields in source order, then the superclass's.

List<ScannableField> _collectOneActionSystem(Object object) {
  final owner = object as _OneActionSystem;
  return <ScannableField>[owner.fire, owner.mountEvent, owner.unmountEvent];
}

List<ScannableField> _collectOneActionGame(Object object) {
  object as _OneActionGame;
  return const <ScannableField>[];
}

List<ScannableField> _collectOneActionState(Object object) {
  final owner = object as _OneActionState;
  return <ScannableField>[
    owner.fixedTickEvent,
    owner.tickEvent,
    owner.gameMountedEvent,
    owner.gameUnmountedEvent,
    owner.appHiddenEvent,
    owner.appShownEvent,
    owner.entitySpawnedEvent,
    owner.entityDespawnedEvent,
    owner.sceneLoadedEvent,
    owner.sceneUnloadedEvent,
  ];
}

const GeneratedDeclarations _testDeclarations = GeneratedDeclarations(
  package: 'good_test_system_input_declaration',
  collectors: <DeclarationCollector>[
    DeclarationCollector(_OneActionSystem, _collectOneActionSystem),
    DeclarationCollector(_OneActionGame, _collectOneActionGame),
    DeclarationCollector(_OneActionState, _collectOneActionState),
  ],
);

void main() {
  late _OneActionGame game;
  late _OneActionSystem system;

  setUp(() async {
    game = await Game.startInline(_OneActionGame.new);
    system = game.state.getSystem<_OneActionSystem>();
    addTearDown(() async {
      if (game.isRunning) await game.stop();
    });
  });

  test('a system\'s action is taken by the registry once', () {
    expect(
      game.registry!.actionCount,
      1,
      reason:
          'the game declares no action of its own and the system declares '
          'one, so the run has one. A second entry is the same object at a '
          'second index, which renumbers it and gives the per-tick '
          'resolution pass two turns at it',
    );
  });

  test('a press survives to the tick that reads it', () {
    game.inputDevice!.press(InputKey.spacebar);
    game.state.runFixedStep();

    expect(system.ticks, 1);
    expect(
      system.polledPresses,
      1,
      reason:
          'wasPressedThisFrame is the change between two resolutions. A '
          'second resolution in the same tick sees the state the first one '
          'left, finds no change, and clears the edge before the system '
          'runs',
    );
    expect(system.streamedPresses, 1);

    game.inputDevice!.release(InputKey.spacebar);
    game.state.runFixedStep();

    expect(system.ticks, 2);
    expect(system.polledReleases, 1);
    expect(system.streamedReleases, 1);
  });
}
