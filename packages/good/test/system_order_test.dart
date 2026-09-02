import 'package:flutter_test/flutter_test.dart';
import 'package:good/good.dart';

// Ordering, declared as a value on the system and resolved once at boot.
//
// Everything here boots a real game with `Game.startInline` and reads the
// order off `advance` - what a system's `onFixedUpdate` appends to [log] - so
// what is under test is the execution order of the tick, not the contents of
// a list some helper returned. A test that only asserted `sortSystems`
// reordered `declaredSystems` would pass on a resolve whose result nothing
// dispatches through.

/// Execution order, one entry per system per fixed tick. Cleared in setUp.
final List<String> log = <String>[];

/// What the game under test declares. Set by each test before booting, so one
/// pair of fixture classes serves every scenario instead of a `Game` subclass
/// per case.
late void Function(SystemDescriptor descriptor) declare;

class _OrderState extends GameState<_OrderGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    declare(descriptor);
  }
}

class _OrderGame extends Game {
  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _OrderState();
}

/// A system that does nothing but say when it ran.
abstract class _Logged extends GameSystem with FixedTickable {
  String get tag;

  @override
  void onFixedUpdate() => log.add(tag);
}

// --- systems that state no opinion -------------------------------------

class _Alpha extends _Logged {
  @override
  String get tag => 'alpha';
}

class _Beta extends _Logged {
  @override
  String get tag => 'beta';
}

class _Gamma extends _Logged {
  @override
  String get tag => 'gamma';
}

// --- after / before -----------------------------------------------------

class _AfterBeta extends _Logged {
  final order = Order.of().after<_Beta>();

  @override
  String get tag => 'afterBeta';
}

class _BeforeAlpha extends _Logged {
  final order = Order.of().before<_Alpha>();

  @override
  String get tag => 'beforeAlpha';
}

/// Both directions on one declaration, which is what the chaining is for.
class _BetweenAlphaAndBeta extends _Logged {
  final order = Order.of().after<_Alpha>().before<_Beta>();

  @override
  String get tag => 'between';
}

// --- a chain whose ends never name each other ---------------------------

class _ChainHead extends _Logged {
  @override
  String get tag => 'head';
}

class _ChainMiddle extends _Logged {
  final order = Order.of().after<_ChainHead>();

  @override
  String get tag => 'middle';
}

class _ChainTail extends _Logged {
  final order = Order.of().after<_ChainMiddle>();

  @override
  String get tag => 'tail';
}

// --- first / last -------------------------------------------------------

/// The `Box2DPhysicsSystem` shape: runs first, and yields to anything that
/// names it.
class _FirstOne extends _Logged {
  final order = Order.of().first();

  @override
  String get tag => 'first1';
}

class _FirstTwo extends _Logged {
  final order = Order.of().first();

  @override
  String get tag => 'first2';
}

/// The profiling-marker shape from #187: it has to run immediately before the
/// system that claims the front, and says so.
class _NamesFirstOne extends _Logged {
  final order = Order.of().before<_FirstOne>();

  @override
  String get tag => 'marker';
}

class _LastOne extends _Logged {
  final order = Order.of().last();

  @override
  String get tag => 'last1';
}

class _LastTwo extends _Logged {
  final order = Order.of().last();

  @override
  String get tag => 'last2';
}

/// Names the system that claims the back, so it must run after it.
class _NamesLastOne extends _Logged {
  final order = Order.of().after<_LastOne>();

  @override
  String get tag => 'afterLast';
}

// --- subclass matching --------------------------------------------------

class _Renderer extends _Logged {
  @override
  String get tag => 'renderer';
}

class _FancyRenderer extends _Renderer {
  @override
  String get tag => 'fancy';
}

/// Names the base class. Only the subclass is ever declared.
class _BeforeAnyRenderer extends _Logged {
  final order = Order.of().before<_Renderer>();

  @override
  String get tag => 'beforeRenderer';
}

// --- contradictions -----------------------------------------------------

class _LoopP extends _Logged {
  final order = Order.of().before<_LoopQ>();

  @override
  String get tag => 'p';
}

class _LoopQ extends _Logged {
  final order = Order.of().before<_LoopP>();

  @override
  String get tag => 'q';
}

/// Never declared by anything. Naming it is how the unsatisfiable case is
/// reached.
class _NeverDeclared extends _Logged {
  @override
  String get tag => 'never';
}

class _WantsNeverDeclared extends _Logged {
  final order = Order.of().after<_NeverDeclared>();

  @override
  String get tag => 'wants';
}

class _BothEnds extends _Logged {
  final order = Order.of().first().last();

  @override
  String get tag => 'bothEnds';
}

// --- mixing with the older compareTo spelling ---------------------------

class _ComparesBeforeGamma extends _Logged {
  @override
  int compareTo(GameSystem other) => other is _Gamma ? -1 : 0;

  @override
  String get tag => 'cmp';
}

Future<Game> _boot(void Function(SystemDescriptor descriptor) systems) async {
  declare = systems;
  final game = await Game.startInline(_OrderGame.new);
  addTearDown(() async {
    if (game.isRunning) await game.stop();
  });
  game.state.advance(const Duration(milliseconds: 10));
  return game;
}

Future<Object> _bootError(
  void Function(SystemDescriptor descriptor) systems,
) async {
  declare = systems;
  try {
    final game = await Game.startInline(_OrderGame.new);
    addTearDown(() async {
      if (game.isRunning) await game.stop();
    });
  } catch (error) {
    return error;
  }
  fail('the boot was expected to fail and did not');
}

void main() {
  setUp(log.clear);

  group('after and before', () {
    test('after<T> runs the declaring system later, despite declaring '
        'first', () async {
      await _boot((descriptor) {
        descriptor.has(_AfterBeta.new);
        descriptor.has(_Beta.new);
      });
      expect(log, ['beta', 'afterBeta']);
    });

    test('before<T> runs the declaring system earlier, despite declaring '
        'last', () async {
      await _boot((descriptor) {
        descriptor.has(_Alpha.new);
        descriptor.has(_BeforeAlpha.new);
      });
      expect(log, ['beforeAlpha', 'alpha']);
    });

    test('one declaration states both directions', () async {
      await _boot((descriptor) {
        descriptor.has(_Beta.new);
        descriptor.has(_BetweenAlphaAndBeta.new);
        descriptor.has(_Alpha.new);
      });
      expect(
        log,
        ['alpha', 'between', 'beta'],
        reason:
            'declaration order is Beta, between, Alpha and both constraints '
            'cross it',
      );
    });

    test('a chain holds without its ends naming each other', () async {
      // The transitive case: head -> middle -> tail is stated pairwise and
      // head -> tail never is. A resolve that only honoured stated pairs
      // would be free to put tail first, since nothing mentions the two of
      // them together.
      await _boot((descriptor) {
        descriptor.has(_ChainTail.new);
        descriptor.has(_ChainMiddle.new);
        descriptor.has(_ChainHead.new);
      });
      expect(log, ['head', 'middle', 'tail']);
    });

    test('after<T> is satisfied by a declared subclass', () async {
      await _boot((descriptor) {
        descriptor.has(_FancyRenderer.new);
        descriptor.has(_BeforeAnyRenderer.new);
      });
      expect(
        log,
        ['beforeRenderer', 'fancy'],
        reason:
            'the constraint names _Renderer and only _FancyRenderer is '
            'declared - the match is an `is` test, which is what the '
            '`other is Renderer` compareTo override it replaces meant',
      );
    });

    test('systems that state no opinion keep declaration order', () async {
      await _boot((descriptor) {
        descriptor.has(_Gamma.new);
        descriptor.has(_Alpha.new);
        descriptor.has(_AfterBeta.new);
        descriptor.has(_Beta.new);
      });
      expect(
        log,
        ['gamma', 'alpha', 'beta', 'afterBeta'],
        reason:
            'Gamma and Alpha state nothing and stay where they were '
            'declared; only the one constraint moves anything',
      );
    });
  });

  group('first and last are weak', () {
    test('first() runs before everything, despite declaring last', () async {
      await _boot((descriptor) {
        descriptor.has(_Alpha.new);
        descriptor.has(_Beta.new);
        descriptor.has(_FirstOne.new);
      });
      expect(log, ['first1', 'alpha', 'beta']);
    });

    test('last() runs after everything, despite declaring first', () async {
      await _boot((descriptor) {
        descriptor.has(_LastOne.new);
        descriptor.has(_Alpha.new);
        descriptor.has(_Beta.new);
      });
      expect(log, ['alpha', 'beta', 'last1']);
    });

    test('two systems that both claim the front take it in declaration '
        'order', () async {
      await _boot((descriptor) {
        descriptor.has(_Alpha.new);
        descriptor.has(_FirstTwo.new);
        descriptor.has(_FirstOne.new);
      });
      expect(
        log,
        ['first2', 'first1', 'alpha'],
        reason:
            'read as absolutes the two would contradict and the boot would '
            'fail; weak means neither edge is added between them and '
            'declaration order settles the pair',
      );
    });

    test('two systems that both claim the back take it in declaration '
        'order', () async {
      await _boot((descriptor) {
        descriptor.has(_LastTwo.new);
        descriptor.has(_LastOne.new);
        descriptor.has(_Alpha.new);
      });
      expect(log, ['alpha', 'last2', 'last1']);
    });

    test('first() yields to a system that names it, declared before '
        'it', () async {
      await _boot((descriptor) {
        descriptor.has(_NamesFirstOne.new);
        descriptor.has(_FirstOne.new);
        descriptor.has(_Alpha.new);
      });
      expect(log, ['marker', 'first1', 'alpha']);
    });

    test('first() yields to a system that names it, declared after '
        'it', () async {
      // #187 in miniature, and the half `compareTo` could not do. There the
      // system claiming the front and the marker naming it are one pair, and
      // the earlier-declared of the two is asked first - so which of the two
      // opinions survived depended on which line came first in the body, and
      // a twelve-line comment in the physics demo says so. Both orders have
      // to give the same answer here.
      await _boot((descriptor) {
        descriptor.has(_FirstOne.new);
        descriptor.has(_NamesFirstOne.new);
        descriptor.has(_Alpha.new);
      });
      expect(log, ['marker', 'first1', 'alpha']);
    });

    test('last() yields to a system that names it', () async {
      await _boot((descriptor) {
        descriptor.has(_LastOne.new);
        descriptor.has(_NamesLastOne.new);
        descriptor.has(_Alpha.new);
      });
      expect(log, ['alpha', 'last1', 'afterLast']);
    });

    test('first() and last() on one declaration is refused where it is '
        'written', () async {
      // Awaited, not `expect(() => Game.startInline(...), throwsA(...))`.
      // The refusal happens in a field initialiser, inside the async body of
      // startInline, so it arrives as a rejected Future and the closure form
      // sees a function that returned normally - it passed just as happily
      // with the refusal deleted.
      final error = await _bootError(
        (descriptor) => descriptor.has(_BothEnds.new),
      );
      expect(error, isA<StateError>());
      expect(
        (error as StateError).message,
        allOf(contains('Order.first()'), contains('Order.last()')),
      );
    });
  });

  group('constraints that cannot hold', () {
    test('a constraint naming a system nobody declared fails the boot, '
        'naming both', () async {
      final error = await _bootError((descriptor) {
        descriptor.has(_Alpha.new);
        descriptor.has(_WantsNeverDeclared.new);
      });
      expect(error, isA<StateError>());
      final message = (error as StateError).message;
      expect(
        message,
        allOf(
          contains('_WantsNeverDeclared'),
          contains('_NeverDeclared'),
          contains('Order.after<_NeverDeclared>()'),
        ),
        reason:
            'the declaring system and the type it named are the two things '
            'to look at, and silently ignoring the constraint is what this '
            'API exists to stop',
      );
    });

    test('a cycle fails the boot, naming the systems on it in order and '
        'the edge that closes it', () async {
      final error = await _bootError((descriptor) {
        descriptor.has(_Alpha.new);
        descriptor.has(_LoopP.new);
        descriptor.has(_LoopQ.new);
      });
      expect(error, isA<StateError>());
      final message = (error as StateError).message;
      expect(
        message,
        allOf(
          contains('_LoopP -> _LoopQ -> _LoopP'),
          contains('_LoopP declared Order.before<_LoopQ>()'),
          contains('_LoopQ declared Order.before<_LoopP>()'),
        ),
        reason:
            'the edges are the answer - the older message listed the blocked '
            'set, which includes systems merely downstream of the cycle',
      );
      expect(
        message,
        isNot(contains('_Alpha')),
        reason:
            'Alpha states no opinion and is not on the cycle; naming it '
            'would be the report to work through by hand rather than read',
      );
    });

    test('a system that declares an order but is not built by the '
        'framework is refused', () {
      // The window `SystemDescriptor.has` opens is what `Order.of` reads, so
      // a system constructed by hand has nothing to declare into - the same
      // refusal `Event.of` and `Input.of` give, and for the same reason.
      expect(
        () => _AfterBeta(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(
              'An Order was declared with no system being '
              'constructed',
            ),
          ),
        ),
      );
    });
  });

  group('mixing with compareTo', () {
    test('a compareTo opinion and an Order constraint both hold', () async {
      await _boot((descriptor) {
        descriptor.has(_Gamma.new);
        descriptor.has(_ComparesBeforeGamma.new);
        descriptor.has(_AfterBeta.new);
        descriptor.has(_Beta.new);
      });
      expect(
        log,
        ['cmp', 'gamma', 'beta', 'afterBeta'],
        reason:
            'both spellings feed the same graph, so a game part-way through '
            'a migration resolves as one set of constraints rather than two',
      );
    });
  });
}
