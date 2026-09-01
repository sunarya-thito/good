// The generated component-bit table (#18): what `ComponentTypeRegistry`
// numbers when a game names its engine packages' tables, and what it refuses.
//
// The property under test is not "a bit was assigned" - the registry has
// always managed that. It is that the *same* type gets the *same* bit in two
// processes that declared their scenes in different orders, which is what a
// signature has to have before it can be sent anywhere. So most of these
// assert an index, or two numberings against each other, rather than a count.

import 'package:flutter_test/flutter_test.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';

mixin _Alpha on Component {
  final alphaValue = Field.float64();

  final alphaType = Component.type<_Alpha>();
}

mixin _Beta on Component {
  final betaValue = Field.float64();

  final betaType = Component.type<_Beta>();
}

mixin _Gamma on Component {
  final gammaValue = Field.float64();

  final gammaType = Component.type<_Gamma>();
}

/// A component in a package the scan never read - somebody's own game.
mixin _Unscanned on Component {
  final unscannedValue = Field.float64();

  final unscannedType = Component.type<_Unscanned>();
}

/// `kernel` sorts before `renderer`, so its two types take bits 0 and 1
/// whichever order the tables are handed over in.
const GeneratedComponentBits _kernel = GeneratedComponentBits(
  package: 'kernel',
  types: <Type>[_Alpha, _Beta],
);

const GeneratedComponentBits _renderer = GeneratedComponentBits(
  package: 'renderer',
  types: <Type>[_Gamma],
  dependencies: <GeneratedComponentBits>[_kernel],
);

/// Sixty-five distinct types, one more than a signature holds.
///
/// Spelled as `Map<A, B>` pairs rather than as sixty-five class declarations:
/// each instantiation is its own `Type`, which is the whole of what the ceiling
/// counts.
const List<Type> _tooMany = <Type>[
  Map<int, int>, Map<int, double>, Map<int, num>, Map<int, String>,
  Map<int, bool>, Map<int, Object>, Map<int, Symbol>, Map<int, Type>,
  Map<int, Duration>, Map<double, int>, Map<double, double>, Map<double, num>,
  Map<double, String>, Map<double, bool>, Map<double, Object>,
  Map<double, Symbol>, Map<double, Type>, Map<double, Duration>,
  Map<num, int>, Map<num, double>, Map<num, num>, Map<num, String>,
  Map<num, bool>, Map<num, Object>, Map<num, Symbol>, Map<num, Type>,
  Map<num, Duration>, Map<String, int>, Map<String, double>, Map<String, num>,
  Map<String, String>, Map<String, bool>, Map<String, Object>,
  Map<String, Symbol>, Map<String, Type>, Map<String, Duration>,
  Map<bool, int>, Map<bool, double>, Map<bool, num>, Map<bool, String>,
  Map<bool, bool>, Map<bool, Object>, Map<bool, Symbol>, Map<bool, Type>,
  Map<bool, Duration>, Map<Object, int>, Map<Object, double>, Map<Object, num>,
  Map<Object, String>, Map<Object, bool>, Map<Object, Object>,
  Map<Object, Symbol>, Map<Object, Type>, Map<Object, Duration>,
  Map<Symbol, int>, Map<Symbol, double>, Map<Symbol, num>, Map<Symbol, String>,
  Map<Symbol, bool>, Map<Symbol, Object>, Map<Symbol, Symbol>,
  Map<Symbol, Type>, Map<Symbol, Duration>, Map<Type, int>, Map<Type, double>,
];

class _Player extends EntityStruct with _Alpha, _Beta {}

class _Prop extends EntityStruct with _Alpha {}

class _Level extends SceneStruct {
  _Level();

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    descriptor.has(_Player.new);
    descriptor.has(_Prop.new);
  }
}

class _SeededState extends GameState<_SeededGame> {
  @override
  void onMounted() {
    loadScene(_Level());
  }
}

class _SeededGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  List<GeneratedComponentBits> get componentBits =>
      const <GeneratedComponentBits>[_renderer];

  @override
  GameState createState() => _SeededState();
}

/// The same game with no tables named - the behaviour every project has today.
class _UnseededGame extends _SeededGame {
  @override
  List<GeneratedComponentBits> get componentBits =>
      const <GeneratedComponentBits>[];
}

/// Every index the registry has handed out for [types].
List<int> _indices(List<Type> types) =>
    <int>[for (final type in types) ComponentTypeRegistry.indexFor(type)];

void main() {
  setUp(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('a seeded registry', () {
    test('numbers every table contiguously from zero, by package name', () {
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        _renderer,
        _kernel,
      ]);
      expect(ComponentTypeRegistry.seededCount, 3);
      expect(_indices(<Type>[_Alpha, _Beta, _Gamma]), <int>[0, 1, 2]);
    });

    test('numbers the same whichever order the tables arrive in', () {
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        _renderer,
        _kernel,
      ]);
      final first = _indices(<Type>[_Alpha, _Beta, _Gamma]);
      ComponentTypeRegistry.reset();
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        _kernel,
        _renderer,
      ]);
      expect(_indices(<Type>[_Alpha, _Beta, _Gamma]), first);
    });

    test('brings a table\'s dependencies with it', () {
      // `_renderer` alone. `_kernel` is named nowhere in this call and is what
      // `_renderer` is built on, so a game on the renderer does not have to
      // know the kernel exists to have its two types numbered.
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        _renderer,
      ]);
      expect(ComponentTypeRegistry.seededCount, 3);
      expect(_indices(<Type>[_Alpha, _Beta, _Gamma]), <int>[0, 1, 2]);
    });

    test('gives no two component types the same bit', () {
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        _renderer,
      ]);
      // Two types the table does not hold, arriving the way a game's own
      // components do.
      final all = <Type>[_Alpha, _Beta, _Gamma, _Unscanned, _Player, _Prop];
      final assigned = _indices(all);
      expect(
        assigned.toSet().length,
        all.length,
        reason: 'each of $all must hold a bit of its own: got $assigned',
      );
      // And the masks, which is what a signature is actually built out of.
      final masks = <int>[
        for (final type in all) ComponentTypeRegistry.bitFor(type),
      ];
      expect(masks.toSet().length, all.length);
      expect(masks.fold<int>(0, (a, b) => a | b).bitLength, all.length);
    });

    test('gives an unscanned type the bit after the seeded ones', () {
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        _renderer,
      ]);
      expect(ComponentTypeRegistry.indexFor(_Unscanned), 3);
      expect(ComponentTypeRegistry.indexFor(_Player), 4);
    });

    test('renumbers no scanned type when an unscanned one appears', () {
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        _renderer,
      ]);
      final before = _indices(<Type>[_Alpha, _Beta, _Gamma]);
      ComponentTypeRegistry.indexFor(_Unscanned);
      ComponentTypeRegistry.indexFor(_Player);
      // A second game in the same process installs the same tables again.
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[
        _kernel,
        _renderer,
      ]);
      expect(_indices(<Type>[_Alpha, _Beta, _Gamma]), before);
      expect(ComponentTypeRegistry.indexFor(_Unscanned), 3);
      expect(ComponentTypeRegistry.indexFor(_Player), 4);
    });
  });

  group('seeding refuses', () {
    test('after a type has already taken a bit at run time', () {
      ComponentTypeRegistry.indexFor(_Alpha);
      expect(
        () => ComponentTypeRegistry.installGenerated(
          <GeneratedComponentBits>[_renderer],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('already assigned 1 bit(s) at run time'),
              contains('_Alpha'),
            ),
          ),
        ),
      );
    });

    test('a second, different set of packages', () {
      ComponentTypeRegistry.installGenerated(<GeneratedComponentBits>[_kernel]);
      expect(
        () => ComponentTypeRegistry.installGenerated(
          <GeneratedComponentBits>[_renderer],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('already seeded from kernel'),
              contains('names kernel, renderer'),
            ),
          ),
        ),
      );
    });

    test('a type two tables both claim', () {
      const overlapping = GeneratedComponentBits(
        package: 'renderer',
        types: <Type>[_Alpha],
      );
      expect(
        () => ComponentTypeRegistry.installGenerated(
          <GeneratedComponentBits>[_kernel, overlapping],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Both kernel and renderer claim _Alpha'),
              contains('One type is one bit'),
            ),
          ),
        ),
      );
    });

    test('two tables calling themselves one package', () {
      const other = GeneratedComponentBits(
        package: 'kernel',
        types: <Type>[_Gamma],
      );
      expect(
        () => ComponentTypeRegistry.installGenerated(
          <GeneratedComponentBits>[_kernel, other],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains("both call themselves 'kernel'"),
          ),
        ),
      );
    });

    test('a seed wider than the signature, naming every type in it', () {
      final wide = GeneratedComponentBits(package: 'wide', types: _tooMany);
      expect(_tooMany.length, ComponentTypeRegistry.maxComponentTypes + 1);
      expect(
        () => ComponentTypeRegistry.installGenerated(
          <GeneratedComponentBits>[wide],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('would take 65 of the 64 bits'),
              // The last one, so the message is the whole list and not a
              // truncation of it.
              contains('Map<Type, double>'),
            ),
          ),
        ),
      );
      // And nothing was seeded on the way to failing.
      expect(ComponentTypeRegistry.seededCount, 0);
      expect(ComponentTypeRegistry.assignedCount, 0);
    });
  });

  group('a game', () {
    test('seeds the tables it names, before its scenes register', () async {
      final game = await Game.startInline(_SeededGame.new);
      addTearDown(() async {
        if (game.isRunning) await game.stop();
      });
      expect(ComponentTypeRegistry.seededCount, 3);
      expect(_indices(<Type>[_Alpha, _Beta, _Gamma]), <int>[0, 1, 2]);
      // `_Gamma` is in the table and in no prefab, which is the cost this
      // buys the stability with: a bit is spent on it either way.
      expect(
        ComponentTypeRegistry.assignedCount,
        greaterThan(ComponentTypeRegistry.seededCount),
        reason: 'the two prefab types take bits of their own',
      );
    });

    test('naming no table numbers from the scene declarations, as before',
        () async {
      final game = await Game.startInline(_UnseededGame.new);
      addTearDown(() async {
        if (game.isRunning) await game.stop();
      });
      expect(ComponentTypeRegistry.seededCount, 0);
      // `_Player` is the first prefab the scene declares, and it is
      // `class _Player extends EntityStruct with _Alpha, _Beta`. Mixin field
      // initialisers run in reverse `with` order, so `_Beta` declares itself
      // first and `_Alpha` second; the prefab's own type is added after the
      // constructor returns, because `runtimeType` is not reachable from an
      // initialiser. The numbering is therefore a fact about the source order
      // of one class, which is the whole reason it cannot be persisted.
      expect(ComponentTypeRegistry.indexFor(_Beta), 0);
      expect(ComponentTypeRegistry.indexFor(_Alpha), 1);
      expect(ComponentTypeRegistry.indexFor(_Player), 2);
      expect(ComponentTypeRegistry.indexFor(_Gamma), isNot(2));
    });
  });
}
