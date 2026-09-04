import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/input/input_axis.dart';
import 'package:good/src/input/input_binding.dart';
import 'package:good/src/input/input_key.dart';
import 'package:good/src/input/input_state.dart';
import 'package:good/src/system.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'game_composite_input_test.g.dart';

// One action bound to several sources - #215. Driven through
// Game.startInline(...) the way game_input_test.dart and game_analog_test.dart
// are: one copy doing both jobs, no timer, runFixedStep() by hand, and
// synthetic device state written through the same InputDevice a GameView
// would write through.
//
// The cases here are the ones the merge rule was decided on. Precedence -
// "walk the sources and take the first actuated one" - passes "either source
// drives the action" and fails every test in the first group but one, which is
// what those tests are for.

late Game run;

final List<String> events = <String>[];

// --- the system under test ------------------------------------------------

/// A composite of each shape: two keyboards, an analog stick beside a
/// keyboard, a key beside a mouse button, and two axes.
class _CompositeSystem extends GameSystem {
  /// WASD or the arrow keys - the case #215 was raised with.
  final keyboards = Input.of<Vector2>(
    CompositeBinding(
      const Vec2Binding(up: .w, down: .s, left: .a, right: .d),
      const Vec2Binding(
        up: .arrowUp,
        down: .arrowDown,
        left: .arrowLeft,
        right: .arrowRight,
      ),
    ),
  );

  /// The left stick or WASD, which is the analog-or-digital case: the two
  /// sources are a `StickBinding` and a `Vec2Binding`, and both are
  /// `InputBinding<Vector2>`.
  final mixed = Input.of<Vector2>(
    CompositeBinding(
      const StickBinding(x: .virtualLeftStickX, y: .virtualLeftStickY),
      const Vec2Binding(up: .w, down: .s, left: .a, right: .d),
    ),
  );

  /// Space or left click, one action with one pair of edges.
  final attack = Input.of<bool>(
    CompositeBinding(
      const TriggerBinding(.spacebar),
      const TriggerBinding(.leftMouseButton),
    ),
  );

  /// Two axes, so the `double` rule has something to disagree about.
  final throttle = Input.of<double>(
    CompositeBinding(
      const AxisBinding(.virtualLeftStickX),
      const AxisBinding(.virtualRightStickX),
    ),
    0.0,
  );

  _CompositeSystem() {
    attack.pressed += (event) => events.add('attack pressed');
    attack.released += (event) => events.add('attack released');
    keyboards.pressed += (event) => events.add('move pressed');
    keyboards.released += (event) => events.add('move released');
  }
}

class _CompositeGameState extends GameState<_CompositeGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_CompositeSystem.new);
  }
}

class _CompositeGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _CompositeGameState();
}

/// An action declared unbound, so a composite restored from JSON has somewhere
/// to be assigned - the rebinding-screen path.
class _RestoreSystem extends GameSystem {
  final attack = Input.of<bool>();
}

class _RestoreGameState extends GameState<_RestoreGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_RestoreSystem.new);
  }
}

class _RestoreGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _RestoreGameState();
}

/// A binding written the way a game outside this repo would write one - which
/// is also what counts `createStorage` calls, so "the scratch is built at
/// declare time and never again" is observable rather than asserted.
///
/// It exists to be a third-party `InputBinding`, so it implements [combine]:
/// that member is required, and a binding that does not implement it does not
/// compile. See the Breaking entry in good's CHANGELOG.
final class _Counts {
  int storagesCreated = 0;
  int resolves = 0;
  final List<Vector2> storagesSeen = <Vector2>[];
}

final class _CountingBinding extends InputBinding<Vector2> {
  _CountingBinding(this.value);

  final Vector2 value;

  /// Counters in a held object rather than in fields, because [InputBinding]
  /// is `@immutable` and a mutable field on a subclass is a warning - which is
  /// itself part of what this fixture demonstrates about writing one.
  final _Counts counts = _Counts();

  int get storagesCreated => counts.storagesCreated;
  int get resolves => counts.resolves;
  List<Vector2> get storagesSeen => counts.storagesSeen;

  @override
  Vector2 createStorage() {
    counts.storagesCreated++;
    return Vector2.zero();
  }

  @override
  Vector2 resolve(InputState state, Vector2 storage) {
    counts.resolves++;
    if (!storagesSeen.any((seen) => identical(seen, storage))) {
      storagesSeen.add(storage);
    }
    storage.setFrom(value);
    return storage;
  }

  @override
  bool isActuated(InputState state) => value.x != 0 || value.y != 0;

  @override
  Vector2 combine(Vector2 a, Vector2 b) {
    a.setValues(a.x + b.x, a.y + b.y);
    return a;
  }

  @override
  Map<String, Object?> toJson() => const <String, Object?>{};
}

// --- helpers --------------------------------------------------------------

Future<T> _boot<T extends Game>(T Function() create) async {
  final game = await Game.startInline(create);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

void _pressAndStep(Game game, List<InputKey> keys) {
  for (final key in keys) {
    game.inputDevice!.press(key);
  }
  run.state.runFixedStep();
}

void _releaseAndStep(Game game, List<InputKey> keys) {
  for (final key in keys) {
    game.inputDevice!.release(key);
  }
  run.state.runFixedStep();
}

String _xy(Vector2 v) => '${v.x},${v.y}';

void main() {
  _installDeclarations();

  setUp(events.clear);

  group('the merge rule', () {
    test('w and arrowRight give the diagonal, which precedence loses', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();

      _pressAndStep(game, <InputKey>[InputKey.w, InputKey.arrowRight]);

      expect(
        _xy(system.keyboards.value),
        '1.0,1.0',
        reason:
            'both halves of the keyboard are actuated, so both contribute. '
            'Taking the first actuated source instead would answer 0.0,1.0 '
            'and the player could not move diagonally - which is the case '
            '#215 was raised with',
      );
    });

    test('w and arrowUp clamp to one, not two', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();

      _pressAndStep(game, <InputKey>[InputKey.w, InputKey.arrowUp]);

      expect(
        _xy(system.keyboards.value),
        '0.0,1.0',
        reason: 'the same direction twice is still that direction',
      );
    });

    test('a and arrowRight cancel, as they do on one keyboard', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();

      _pressAndStep(game, <InputKey>[InputKey.a, InputKey.arrowRight]);

      expect(
        _xy(system.keyboards.value),
        '0.0,0.0',
        reason:
            'a Vec2Binding whose left and right keys are both held stands '
            'still; two of them held across the composite do the same',
      );
    });

    test('a pushed stick and a held key respect both devices', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();
      game.inputDevice!.setVirtualAxis(InputAxis.virtualLeftStickX, 0.5);

      _pressAndStep(game, <InputKey>[InputKey.w]);

      expect(
        _xy(system.mixed.value),
        '0.5,1.0',
        reason:
            'the stick keeps its analog x and the key supplies y. Precedence '
            'would answer 0.5,0.0 - the stick is actuated first - and throw '
            'the keyboard away',
      );
    });

    test('the stick keeps its analog value, not a thresholded one', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();
      game.inputDevice!.setVirtualAxis(InputAxis.virtualLeftStickX, 0.25);

      run.state.runFixedStep();

      expect(system.mixed.value.x, 0.25);
    });

    test('two triggers OR', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();

      run.state.runFixedStep();
      expect(system.attack.value, isFalse, reason: 'neither is held');

      _pressAndStep(game, <InputKey>[InputKey.spacebar]);
      expect(system.attack.value, isTrue, reason: 'the first source alone');

      _releaseAndStep(game, <InputKey>[InputKey.spacebar]);
      _pressAndStep(game, <InputKey>[InputKey.leftMouseButton]);
      expect(system.attack.value, isTrue, reason: 'the second source alone');

      _pressAndStep(game, <InputKey>[InputKey.spacebar]);
      expect(system.attack.value, isTrue, reason: 'both at once');
    });

    test('two axes take whichever is further from rest', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();
      final device = game.inputDevice!;

      device.setVirtualAxis(InputAxis.virtualLeftStickX, 0.25);
      device.setVirtualAxis(InputAxis.virtualRightStickX, -0.75);
      run.state.runFixedStep();
      expect(
        system.throttle.value,
        -0.75,
        reason: 'furthest from rest, sign and all - not the sum, not the first',
      );

      device.setVirtualAxis(InputAxis.virtualLeftStickX, 0.5);
      device.setVirtualAxis(InputAxis.virtualRightStickX, 0.25);
      run.state.runFixedStep();
      expect(system.throttle.value, 0.5);
    });

    test('a source at rest dilutes nothing', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();

      game.inputDevice!.setVirtualAxis(InputAxis.virtualRightStickX, 0.75);
      run.state.runFixedStep();

      expect(system.throttle.value, 0.75);
    });
  });

  group('edges over several sources', () {
    test('a second source pressed while the first is held does not '
        're-fire', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();

      _pressAndStep(game, <InputKey>[InputKey.spacebar]);
      expect(system.attack.wasPressedThisFrame, isTrue);

      _pressAndStep(game, <InputKey>[InputKey.leftMouseButton]);
      expect(
        system.attack.wasPressedThisFrame,
        isFalse,
        reason:
            'the action never stopped being held, so there is no edge. Two '
            'actions ||-ed at the use site swing twice here',
      );
      expect(events, <String>['attack pressed']);
    });

    test('releasing one source while the other is held fires nothing', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();

      _pressAndStep(game, <InputKey>[
        InputKey.spacebar,
        InputKey.leftMouseButton,
      ]);
      _releaseAndStep(game, <InputKey>[InputKey.spacebar]);

      expect(system.attack.wasReleasedThisFrame, isFalse);
      expect(system.attack.value, isTrue);
      expect(events, <String>['attack pressed']);
    });

    test('the release fires once, when the last source goes up', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();

      _pressAndStep(game, <InputKey>[
        InputKey.spacebar,
        InputKey.leftMouseButton,
      ]);
      _releaseAndStep(game, <InputKey>[InputKey.spacebar]);
      _releaseAndStep(game, <InputKey>[InputKey.leftMouseButton]);

      expect(system.attack.wasReleasedThisFrame, isTrue);
      expect(events, <String>['attack pressed', 'attack released']);

      run.state.runFixedStep();
      expect(system.attack.wasReleasedThisFrame, isFalse);
      expect(events, <String>['attack pressed', 'attack released']);
    });

    test('a keyboard key and a mouse button are one action', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();

      _pressAndStep(game, <InputKey>[InputKey.leftMouseButton]);
      expect(system.attack.value, isTrue);
      expect(system.attack.wasPressedThisFrame, isTrue);

      _releaseAndStep(game, <InputKey>[InputKey.leftMouseButton]);
      expect(system.attack.value, isFalse);
      expect(events, <String>['attack pressed', 'attack released']);
    });

    test('a vector composite is held while any of its keys is', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();

      _pressAndStep(game, <InputKey>[InputKey.w]);
      expect(system.keyboards.wasPressedThisFrame, isTrue);

      _pressAndStep(game, <InputKey>[InputKey.arrowRight]);
      expect(system.keyboards.wasPressedThisFrame, isFalse);

      _releaseAndStep(game, <InputKey>[InputKey.w]);
      expect(system.keyboards.wasReleasedThisFrame, isFalse);

      _releaseAndStep(game, <InputKey>[InputKey.arrowRight]);
      expect(system.keyboards.wasReleasedThisFrame, isTrue);
      expect(events, <String>['move pressed', 'move released']);
    });
  });

  group('storage', () {
    // What is checked here is that resolution creates no new value objects:
    // every source writes into something that existed before the first tick.
    // That is not a byte-level allocation measurement and is not claimed as
    // one - a heap counter is not available inside `flutter test` - but it is
    // the thing the design is about, and a `resolve` that allocated a Vector2
    // or a scratch per tick fails it.
    test('every source resolves into storage made before the first '
        'tick', () async {
      final a = _CountingBinding(Vector2(1, 0));
      final b = _CountingBinding(Vector2(0, 1));
      final c = _CountingBinding(Vector2(0.5, 0));
      final composite = CompositeBinding<Vector2>(a, b, c);

      // Two scratches - one for each source past the first - built by the
      // constructor, before anything has ticked.
      expect(a.storagesCreated, 0, reason: 'the primary resolves into the '
          'action\'s own storage');
      expect(b.storagesCreated, 1);
      expect(c.storagesCreated, 1);

      final state = InputState(10);
      final storage = composite.createStorage();
      expect(
        a.storagesCreated,
        1,
        reason: 'createStorage on the composite is the primary\'s, once',
      );

      for (var tick = 0; tick < 10; tick++) {
        expect(identical(composite.resolve(state, storage), storage), isTrue);
      }

      expect(a.resolves, 10);
      expect(b.resolves, 10);
      expect(c.resolves, 10);
      expect(
        <int>[a.storagesCreated, b.storagesCreated, c.storagesCreated],
        <int>[1, 1, 1],
        reason: 'ten ticks created no storage at all',
      );
      expect(
        <int>[
          a.storagesSeen.length,
          b.storagesSeen.length,
          c.storagesSeen.length,
        ],
        <int>[1, 1, 1],
        reason: 'each source saw one storage instance across every tick',
      );
      expect(storage, Vector2(1.5, 1));
    });

    test('the action\'s value is one instance for its life', () async {
      final game = await _boot(_CompositeGame.new);
      final system = run.state.getSystem<_CompositeSystem>();

      _pressAndStep(game, <InputKey>[InputKey.w]);
      final first = system.keyboards.value;
      _pressAndStep(game, <InputKey>[InputKey.arrowRight]);

      expect(identical(system.keyboards.value, first), isTrue);
      expect(_xy(first), '1.0,1.0');
    });
  });

  group('construction', () {
    test('the positional form is the same binding as fromList', () {
      const space = TriggerBinding(.spacebar);
      const click = TriggerBinding(.leftMouseButton);

      final positional = CompositeBinding<bool>(space, click);
      final list = CompositeBinding<bool>.fromList(<InputBinding<bool>>[
        space,
        click,
      ]);

      expect(positional, list);
      expect(positional.hashCode, list.hashCode);
      expect(positional.toJson(), list.toJson());
      expect(positional.sources, <InputBinding<bool>>[space, click]);
    });

    test('ten sources fit the positional form', () {
      final composite = CompositeBinding<bool>(
        const TriggerBinding(.digit0),
        const TriggerBinding(.digit1),
        const TriggerBinding(.digit2),
        const TriggerBinding(.digit3),
        const TriggerBinding(.digit4),
        const TriggerBinding(.digit5),
        const TriggerBinding(.digit6),
        const TriggerBinding(.digit7),
        const TriggerBinding(.digit8),
        const TriggerBinding(.digit9),
      );

      expect(composite.sources, hasLength(10));
    });

    test('the sources list is copied, not aliased', () {
      final given = <InputBinding<bool>>[
        const TriggerBinding(.spacebar),
        const TriggerBinding(.enter),
      ];
      final composite = CompositeBinding<bool>.fromList(given);
      given.add(const TriggerBinding(.escape));

      expect(composite.sources, hasLength(2));
      expect(
        () => composite.sources.add(const TriggerBinding(.escape)),
        throwsUnsupportedError,
      );
    });

    test('a composite of nothing is refused', () {
      // Checked by message, not by type: with the guard removed, building the
      // scratch for -1 sources throws a RangeError, and RangeError *is* an
      // ArgumentError - so throwsArgumentError alone passes either way and
      // measures nothing.
      expect(
        () => CompositeBinding<bool>.fromList(const <InputBinding<bool>>[]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('at least one source'),
          ),
        ),
      );
    });

    test('a MouseBinding cannot be a source', () {
      expect(
        () => CompositeBinding<CursorPosition>(
          const MouseBinding(),
          const MouseBinding(),
        ),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message.toString(),
            'message',
            contains('one cursor'),
          ),
        ),
      );
    });

    test('merging two cursor positions is refused in release too', () {
      expect(
        () => const MouseBinding().combine(CursorPosition(), CursorPosition()),
        throwsUnsupportedError,
      );
    });

    test('== is by content, and differs from another composite\'s', () {
      final a = CompositeBinding<bool>(
        const TriggerBinding(.spacebar),
        const TriggerBinding(.enter),
      );
      final b = CompositeBinding<bool>(
        const TriggerBinding(.spacebar),
        const TriggerBinding(.enter),
      );
      final reordered = CompositeBinding<bool>(
        const TriggerBinding(.enter),
        const TriggerBinding(.spacebar),
      );
      final longer = CompositeBinding<bool>(
        const TriggerBinding(.spacebar),
        const TriggerBinding(.enter),
        const TriggerBinding(.escape),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(reordered));
      expect(a, isNot(longer));
      expect(a, isNot(const TriggerBinding(.spacebar)));
    });

    test('one source is legal, and reads like that source alone', () {
      final composite = CompositeBinding<bool>.fromList(
        const <InputBinding<bool>>[TriggerBinding(.spacebar)],
      );
      final state = InputState(10);

      expect(composite.isActuated(state), isFalse);
      expect(composite.resolve(state, composite.createStorage()), isFalse);
    });

    test('a composite nests inside a composite', () {
      final inner = CompositeBinding<Vector2>(
        const Vec2Binding(up: .w, down: .s, left: .a, right: .d),
        const Vec2Binding(
          up: .arrowUp,
          down: .arrowDown,
          left: .arrowLeft,
          right: .arrowRight,
        ),
      );
      final outer = CompositeBinding<Vector2>(
        const StickBinding(x: .virtualLeftStickX, y: .virtualLeftStickY),
        inner,
      );

      expect(outer.sources[1], inner);
      expect(
        outer.resolve(InputState(10), outer.createStorage()),
        Vector2.zero(),
        reason: 'nothing is held or pushed, and nothing throws on the way',
      );
    });
  });

  group('serialization', () {
    test('a composite of triggers round-trips', () {
      final binding = CompositeBinding<bool>(
        const TriggerBinding(.spacebar),
        const TriggerBinding(.leftMouseButton),
      );

      expect(CompositeBinding.fromJson<bool>(binding.toJson()), binding);
    });

    test('a stick and a Vec2Binding round-trip together', () {
      final binding = CompositeBinding<Vector2>(
        const StickBinding(x: .padLeftStickX, y: .padLeftStickY),
        const Vec2Binding(up: .w, down: .s, left: .a, right: .d),
      );

      expect(CompositeBinding.fromJson<Vector2>(binding.toJson()), binding);
    });

    test('an axis composite round-trips', () {
      final binding = CompositeBinding<double>(
        const AxisBinding(.padLeftTrigger),
        const AxisBinding(.padRightTrigger),
      );

      expect(CompositeBinding.fromJson<double>(binding.toJson()), binding);
    });

    test('a nested composite round-trips', () {
      final binding = CompositeBinding<Vector2>(
        const StickBinding(x: .padLeftStickX, y: .padLeftStickY),
        CompositeBinding<Vector2>(
          const Vec2Binding(up: .w, down: .s, left: .a, right: .d),
          const Vec2Binding(
            up: .arrowUp,
            down: .arrowDown,
            left: .arrowLeft,
            right: .arrowRight,
          ),
        ),
      );

      final restored = CompositeBinding.fromJson<Vector2>(binding.toJson());
      expect(restored, binding);
      expect(restored.sources[1], isA<CompositeBinding<Vector2>>());
    });

    test('the kind tags are the composite\'s own envelope, and the child\'s '
        'JSON is untouched', () {
      final binding = CompositeBinding<bool>(
        const TriggerBinding(.spacebar),
        const TriggerBinding(.leftMouseButton),
      );

      final json = binding.toJson();
      final sources = json['sources']! as List<Object?>;
      final first = sources.first! as Map<String, Object?>;

      expect(json.keys, <String>['sources']);
      expect(first.keys, <String>['kind', 'binding']);
      expect(first['kind'], 'trigger');
      expect(
        first['binding'],
        const TriggerBinding(.spacebar).toJson(),
        reason:
            'the child writes exactly what it always wrote - the tag is '
            'outside it',
      );
    });

    test('the five non-composite bindings write what they always wrote', () {
      expect(const TriggerBinding(.spacebar).toJson(), <String, Object?>{
        'key': <String, Object?>{'kind': 'keyboard', 'name': 'spacebar'},
      });
      expect(
        const Vec2Binding(up: .w, down: .s, left: .a, right: .d).toJson(),
        <String, Object?>{
          'up': <String, Object?>{'kind': 'keyboard', 'name': 'w'},
          'down': <String, Object?>{'kind': 'keyboard', 'name': 's'},
          'left': <String, Object?>{'kind': 'keyboard', 'name': 'a'},
          'right': <String, Object?>{'kind': 'keyboard', 'name': 'd'},
        },
      );
      expect(const AxisBinding(.padLeftTrigger).toJson(), <String, Object?>{
        'axis': <String, Object?>{
          'kind': 'gamepadAxis',
          'name': 'padLeftTrigger',
        },
      });
      expect(
        const StickBinding(x: .padLeftStickX, y: .padLeftStickY).toJson(),
        <String, Object?>{
          'x': <String, Object?>{
            'kind': 'gamepadAxis',
            'name': 'padLeftStickX',
          },
          'y': <String, Object?>{
            'kind': 'gamepadAxis',
            'name': 'padLeftStickY',
          },
        },
      );
      expect(const MouseBinding().toJson(), <String, Object?>{});
    });

    test('an unknown source kind says what it wanted', () {
      expect(
        () => CompositeBinding.fromJson<bool>(<String, Object?>{
          'sources': <Object?>[
            <String, Object?>{
              'kind': 'mouse',
              'binding': <String, Object?>{},
            },
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"mouse"'), contains('"trigger"')),
          ),
        ),
      );
    });

    test('a source of the wrong type for T is refused', () {
      final saved = CompositeBinding<double>(
        const AxisBinding(.padLeftTrigger),
        const AxisBinding(.padRightTrigger),
      ).toJson();

      expect(
        () => CompositeBinding.fromJson<bool>(saved),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('CompositeBinding<bool>'),
          ),
        ),
      );
    });

    test('a saved composite with no sources is refused', () {
      expect(
        () => CompositeBinding.fromJson<bool>(<String, Object?>{
          'sources': <Object?>[],
        }),
        throwsFormatException,
      );
      expect(
        () => CompositeBinding.fromJson<bool>(<String, Object?>{}),
        throwsFormatException,
      );
    });

    test('a restored composite drives an action', () async {
      final game = await _boot(_RestoreGame.new);
      final system = run.state.getSystem<_RestoreSystem>();
      final saved = CompositeBinding<bool>(
        const TriggerBinding(.spacebar),
        const TriggerBinding(.leftMouseButton),
      ).toJson();

      system.attack.binding = CompositeBinding.fromJson<bool>(saved);

      _pressAndStep(game, <InputKey>[InputKey.leftMouseButton]);
      expect(system.attack.value, isTrue);
      expect(system.attack.wasPressedThisFrame, isTrue);

      _pressAndStep(game, <InputKey>[InputKey.spacebar]);
      expect(system.attack.wasPressedThisFrame, isFalse);
    });

    test('toString names every source', () {
      final binding = CompositeBinding<bool>(
        const TriggerBinding(.spacebar),
        const TriggerBinding(.leftMouseButton),
      );

      expect(
        binding.toString(),
        'CompositeBinding(TriggerBinding(spacebar), '
        'TriggerBinding(leftMouseButton))',
      );
    });
  });
}
