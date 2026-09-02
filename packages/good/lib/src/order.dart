import 'package:meta/meta.dart';

import 'package:good/src/declare.dart';
import 'package:good/src/system.dart';

/// Where a system runs relative to the other systems the same game declares.
///
/// Declared on a field of the system itself, like every other declaration a
/// system makes:
///
/// ```dart
/// class CameraFollowSystem extends GameSystem with FixedTickable {
///   final order = Order.of().after<Box2DPhysicsSystem>().before<Renderer>();
/// }
/// ```
///
/// The field name is not read and does not matter - `Order.of()` registers
/// against the window `SystemDescriptor.has` opens around the constructor,
/// the same window `Event.of`, `Input.of` and a `Query` field read. What the
/// field is for is holding the object alive so the expression is not dead
/// code; a system may declare several and they merge.
///
/// # Registration, then resolve
///
/// `of()` registers and resolves nothing. `after`, `before`, `first` and
/// `last` record a constraint on the object and hand it back for chaining;
/// none of them looks a system up, because at the moment a system's fields
/// initialise the systems it names may not be declared yet.
/// `GameState.sortSystems` reads every registered constraint once, after
/// `describeSystems` has returned and every system exists, and turns them
/// into the edges of the graph it sorts.
///
/// That is also why the result is reported at boot rather than at build time:
/// nothing generated can reach it. `good_tool` writes into this repository's
/// `packages/*/lib`, and what `good_cli` generates lands in a package the
/// user's project depends *on*, so neither can name a system the user
/// declares. A table keyed by a user's system has nowhere to live, and there
/// is no reflection in an AOT build to read an annotation back. A value on
/// the instance is readable wherever the system is, engine and user alike.
///
/// # A constraint, not a rank
///
/// Every constraint is an edge, and every edge is kept. Two systems that
/// disagree are a cycle and boot says so, naming the edges; a constraint
/// against a system nobody declared is reported the same way rather than
/// quietly doing nothing. Systems that state no opinion about each other keep
/// the order they were declared in.
///
/// # `first` and `last` are weak, and have to be
///
/// [first] means *before everything that states no opinion about me* - not
/// *before everything*. `Box2DPhysicsSystem` says it runs first, and a
/// profiling marker that has to run immediately before it says
/// `before<Box2DPhysicsSystem>()`. Read as absolutes those two contradict and
/// the game would not boot. Read as "first, except where something names me",
/// the marker's targeted constraint wins and the physics system still
/// precedes everything else. The same holds for [last] in reverse.
final class Order {
  Order._();

  /// Registers an ordering declaration for the system being constructed.
  ///
  /// Reads the window `SystemDescriptor.has` opens, so the system has to be
  /// one the framework builds - `descriptor.has(SpinSystem.new)`. See
  /// [DeclarationContext.addOrder] for what a caller outside one is told.
  static Order of() {
    final order = Order._();
    DeclarationContext.addOrder(order);
    return order;
  }

  final List<OrderConstraint> _constraints = <OrderConstraint>[];
  bool _first = false;
  bool _last = false;

  /// The declared constraints, in declaration order.
  @internal
  List<OrderConstraint> get constraints => _constraints;

  /// Whether [first] was declared. Weak - see the class doc.
  @internal
  bool get isFirst => _first;

  /// Whether [last] was declared. Weak - see the class doc.
  @internal
  bool get isLast => _last;

  /// This system runs after every declared system that is a [T].
  ///
  /// `is`, not an exact type match: `after<PhysicsSystem>()` is satisfied by a
  /// subclass of `PhysicsSystem`, which is what the `other is PhysicsSystem`
  /// test this replaces meant. If a game declares two of them the constraint
  /// holds against both.
  ///
  /// Boot fails if no other declared system is a [T]. That is the point of
  /// naming the type: a constraint nothing satisfies is a typo or a system
  /// somebody forgot to declare, and it has no effect at all if it is only
  /// ignored.
  Order after<T extends GameSystem>() {
    _constraints.add(OrderConstraint._(T, (system) => system is T, true));
    return this;
  }

  /// This system runs before every declared system that is a [T]. The mirror
  /// of [after], and refused on the same terms.
  Order before<T extends GameSystem>() {
    _constraints.add(OrderConstraint._(T, (system) => system is T, false));
    return this;
  }

  /// This system runs before every system that states no opinion about it.
  ///
  /// Weak on purpose - see the class doc. Two systems that both declare this
  /// do not contradict each other; they take the front in declaration order.
  Order first() {
    if (_last) {
      throw StateError(
        'Order.first() and Order.last() were both declared. A system runs '
        'in one place, and these ask for opposite ends of the list.',
      );
    }
    _first = true;
    return this;
  }

  /// This system runs after every system that states no opinion about it.
  /// The mirror of [first], and weak for the same reason.
  Order last() {
    if (_first) {
      throw StateError(
        'Order.last() and Order.first() were both declared. A system runs '
        'in one place, and these ask for opposite ends of the list.',
      );
    }
    _last = true;
    return this;
  }
}

/// One `after`/`before` constraint: what it matches, and which side of the
/// declaring system the match goes on.
///
/// [type] is kept for the diagnostics only. [matches] is what decides, and it
/// closes over the type argument, so a constraint naming a base class is
/// satisfied by a declared subclass - the `is` test in a `compareTo` override
/// behaved that way, and a `Type` key compared with `runtimeType` would not.
@internal
final class OrderConstraint {
  const OrderConstraint._(this.type, this.matches, this.isAfter);

  final Type type;
  final bool Function(GameSystem system) matches;

  /// True for `after<T>()`: the matched system runs first. False for
  /// `before<T>()`.
  final bool isAfter;

  /// How this reads in a diagnostic, from the declaring system's side.
  String describe(Object declarer) =>
      '$declarer declared Order.${isAfter ? 'after' : 'before'}<$type>()';
}
