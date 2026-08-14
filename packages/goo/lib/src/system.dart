import 'package:meta/meta.dart';

import 'package:goo/src/archetype.dart';
import 'package:goo/src/event.dart';
import 'package:goo/src/event/state.dart';
import 'package:goo/src/game.dart';
import 'package:goo/src/game_state.dart';
import 'package:goo/src/input.dart';
import 'package:goo/src/struct.dart';
import 'package:goo/src/scene.dart';

/// Systems run in declaration order by default. A subclass wanting to run
/// relative to specific other systems overrides [compareTo] and type-checks
/// [other] (`if (other is PhysicsSystem) return -1;` to sort before it, `1`
/// to sort after) - simpler than a `runBefore`/`runAfter` dependency graph,
/// at a real cost: an inconsistent `compareTo` (two systems each claiming to
/// run after the other) isn't detected as a cycle, it just produces
/// whatever order the sort happens to land on. `compareTo` is invoked once
/// per pair, during `Game`'s boot pass - never on the tick hot path.
///
/// # One isolate, and a mirror
///
/// A `GameSystem` is a [GameListener] and nothing else: it lives where the
/// tick loop does. Both copies of the `Game` run the same `describeSystems`,
/// so every declared system has a twin on the main isolate, but that twin is
/// a *declaration mirror* - it holds the same handles (buffers, channels,
/// inputs, queries) so that indices agree across the boundary, and it never
/// ticks.
///
/// Systems used to straddle both isolates, receiving a `WidgetEvent` on the
/// main side so each could contribute to the widget tree. That is gone: there
/// is exactly one object that builds widgets and it is `Game.buildView`, which
/// says so with a method instead of a dispatch mechanism built for several
/// contributors to a problem that has one. See `GameEvent`'s doc.
abstract class GameSystem extends GameListenerBase
    with EventBus
    implements Comparable<GameSystem> {
  Game? _game;

  bool _enabled = true;

  /// Whether this system currently receives events.
  ///
  /// This is what `Game.enableSystem`/`disableSystem` actually toggle, and it
  /// is why a pre-collected dispatcher list is still correct: a disabled
  /// system stays in every dispatcher it was collected into and simply
  /// declines. Baking membership and reading enablement is the split - one is
  /// fixed by type at declaration, the other is genuinely runtime state.
  @override
  bool get listensToEvents => _enabled;

  @internal
  set enabled(bool value) => _enabled = value;

  @override
  int compareTo(GameSystem other) => 0; // no opinion by default

  /// Called once by `Game`'s bootstrap, immediately before
  /// [describeQuery]. Not part of the user-facing API: a system is bound by
  /// declaring it in `Game.describeSystems`, never by hand.
  @internal
  void bindGame(Game game) => _game = game;

  /// The game this system was declared in - **this isolate's copy** of it.
  Game get game {
    final game = _game;
    if (game == null) {
      throw StateError(
        '$runtimeType is not bound to a Game. Declare it in '
        'Game.describeSystems - a system constructed by hand has no scene to '
        'query and no tick to run on.',
      );
    }
    return game;
  }

  /// This copy's simulation half - the live one on the game isolate, the
  /// declaration mirror on the main-isolate handle (see `Game.state`). Null
  /// only before `Game.start()`, which a bound system cannot observe.
  GameState? get state => game.state;

  // provide a way for GameSystem to compile queries
  void describeQuery(QueryDescriptor descriptor) {}

  /// Declares this system's published state - see [Game.describeState], which
  /// carries the whole story. One of exactly three hosts that may, and the
  /// one to reach for when the value being published is derived from a
  /// *scene*: a system outlives the scene and is where the per-tick work
  /// already is, whereas a scene is loaded after boot and could never own a
  /// stable channel index.
  ///
  /// ```dart
  /// class ScoreSystem extends GameSystem with FixedTickable {
  ///   late final StateChannel<int> score;
  ///
  ///   @override
  ///   void describeState(StateDescriptor descriptor) {
  ///     score = descriptor.hasInt32();
  ///   }
  ///
  ///   @override
  ///   void onFixedUpdate() => score.value = score.value + 1;
  /// }
  /// ```
  ///
  /// Declared last in the shared boot pass, in post-sort declaration order.
  void describeState(StateDescriptor descriptor) {}

  /// Declares the auxiliary ring buffers this system needs - see
  /// [Game.describeBuffers], which this is folded into (the `Game`'s own
  /// declarations first, then every declared system's, in declaration
  /// order).
  ///
  /// A system rather than only the `Game` can declare one so that a system
  /// shipped by a *library* - `goo2d_render`'s `GameRenderer2D` and its
  /// draw-command channel is the motivating case - is wired up by the single
  /// act of declaring it in `describeSystems`. Otherwise every user would
  /// have to also know the library's capacity requirement and repeat it in
  /// their own `describeBuffers`, which is a contract nobody can keep in
  /// sync.
  ///
  /// Keep the returned [BufferHandle] in a `late final` field and write
  /// through `handle.ring`; there is deliberately no `getBuffer(name)` to
  /// look one up by (RULES.md rule 6). Both isolate twins of this system run
  /// this same pass, so both end up holding a handle to the same memory.
  void describeBuffers(BufferDescriptor descriptor) {}

  /// Declares this system's input actions - see `Game.describeInputs`, which
  /// this is folded into (the `Game`'s own pass first, then every declared
  /// system's, in declaration order, all sharing one descriptor).
  ///
  /// ```dart
  /// late final Input<Vector2> movement;
  /// late final Input<bool> triggerSkill;
  ///
  /// @override
  /// void describeInputs(InputDescriptor input) {
  ///   movement = input.has<Vector2>(const Vec2Binding(up: .w, down: .s, left: .a, right: .d));
  ///   triggerSkill = input.has<bool>(const TriggerBinding(.spacebar));
  /// }
  /// ```
  ///
  /// Keep the returned [Input] in a `late final` field; there is no
  /// `getAction(name)` to look one up by (RULES.md rule 6). Unlike
  /// `Game.describeInputs` this has no `super` to call - the framework's own
  /// declarations all live on the `Game`.
  ///
  /// Both isolate twins of this system run this pass, and only the simulating
  /// one's actions ever resolve - see `Input`'s doc.
  void describeInputs(InputDescriptor descriptor) {}

  /// A sibling system declared in the same `describeSystems`. Reaching one
  /// directly is the escape hatch for cross-system state; note it says
  /// nothing about ordering, which is declaration order and nothing else.
  T getSystem<T extends GameSystem>() => game.getSystem<T>();

  /// The running scene, as [T] - sugar for `state.getScene<T>()`. Throws if
  /// no scene is loaded (`GameState.scene` is nullable by design) or if it is
  /// some other type; read `state?.scene` directly when absence is expected.
  T getScene<T extends SceneStruct>() {
    final state = game.state;
    if (state == null) {
      throw StateError(
        '$runtimeType has no GameState yet - Game.start() has not run.',
      );
    }
    return state.getScene<T>();
  }

  // GameSystem will listen to an event and run a query
}

abstract class Query {
  T get<T extends Component>();
  T? tryGet<T extends Component>();

  /// Whether an archetype with this signature (see
  /// `ArchetypeStorage.componentSignature`) satisfies this query. What
  /// [run]/[runQuery] filter archetypes with before walking any rows -
  /// public because it is the whole of a query's matching semantics, and
  /// testing it directly beats inferring it from iteration results.
  bool matches(int signature);

  // TODO: is closure the best way to run a query?
  void runQuery(void Function() runner);
  // should we do this instead?
  Iterable<Entity> run();
  // and then, have get and tryGet to be
  // if (gameObject is Transformable) // do stuff
}

abstract class SingleQuery<T extends Component> implements Query {
  T get component => throw UnimplementedError();
}

abstract class QueryDescriptor {
  SingleQuery<T> has<T extends Component>();

  /// Opens a query. Chain [QueryBuilder.withAll]/[QueryBuilder.withNone]/
  /// [QueryBuilder.withAny]/[QueryBuilder.withOptional] onto it and finish
  /// with [QueryBuilder.build]:
  ///
  /// ```dart
  /// renderables = descriptor
  ///     .query()
  ///     .withAll(Renderable2D, Transform2D)
  ///     .withOptional(Child)
  ///     .build();
  /// ```
  QueryBuilder query();
}

/// Builds one query out of three constraints over the archetype signature
/// bitset (`ArchetypeStorage.componentSignature`, see archetype.dart):
/// every type in [withAll] present, every type in [withNone] absent, and at
/// least one type from each [withAny] group present.
///
/// Matching is therefore two masked compares plus one per `withAny` group -
/// no per-entity type tests, no closures, no allocation (see
/// `_CompiledQuery.matches`). The previous sum-of-products `&`/`|` form was
/// strictly more expressive on paper, but nothing in the engine ever used a
/// real disjunction of conjunctions, and its `matches` allocated a closure
/// per call (`clauses.any((c) => ...)`) on the hottest path there is -
/// RULES.md rules 1, 2 and 5.
///
/// Components are named as bare `Type` objects rather than type arguments
/// (`withAll(Transform2D)`, not `With<Transform2D>()`) so one flat call can
/// name any number of them. The cost, stated plainly: the analyzer no
/// longer checks that what you pass is a `Component`, so `withAll(String)`
/// compiles. `_QueryBuilder._add` asserts against that in debug builds,
/// which is as much as can be recovered once the type argument is gone.
abstract class QueryBuilder {
  /// Every listed component must be present. Repeatable; each call ORs into
  /// the same required mask.
  QueryBuilder withAll(Type a,
      [Type? b, Type? c, Type? d, Type? e, Type? f, Type? g, Type? h, Type? i, Type? j]);

  /// Every listed component must be absent. Repeatable.
  QueryBuilder withNone(Type a,
      [Type? b, Type? c, Type? d, Type? e, Type? f, Type? g, Type? h, Type? i, Type? j]);

  /// At least one of the listed components must be present. Each *call* is
  /// its own group and every group must be satisfied, so
  /// `.withAny(A, B).withAny(C, D)` means "(A or B) and (C or D)", not
  /// "(A or B or C or D)".
  QueryBuilder withAny(Type a,
      [Type? b, Type? c, Type? d, Type? e, Type? f, Type? g, Type? h, Type? i, Type? j]);

  /// Declares that a match *may* have these components, without requiring
  /// or forbidding them. Pure documentation - it does not narrow the query.
  /// Its role is signalling to the reader (and, later, to codegen) that the
  /// loop body branches on `entity.tryGet<T>()`; `WorldTransformSystem` is
  /// the reference usage, matching every `Transform2D` entity whether
  /// hierarchy-linked or not and testing `tryGet<Child>()` inside.
  QueryBuilder withOptional(Type a,
      [Type? b, Type? c, Type? d, Type? e, Type? f, Type? g, Type? h, Type? i, Type? j]);

  /// Compiles the constraints into a runnable [Query]. Call once - the
  /// builder is a one-shot describe-time object, not something to keep.
  Query build();
}

/// The one [QueryBuilder] implementation. Accumulates masks as it is
/// chained, then hands them to a [_CompiledQuery] at [build].
final class _QueryBuilder implements QueryBuilder {
  _QueryBuilder(this._storageOf);

  /// How a compiled query reaches the archetype table - injected rather
  /// than reached statically so the descriptor stays the only thing that
  /// knows about `ArchetypeRegistry`.
  final _ArchetypeQuery Function(int required, int forbidden, List<int> anyGroups)
      _storageOf;

  int _required = 0;
  int _forbidden = 0;

  /// One mask per `withAny` call. Almost always empty, so it starts as a
  /// shared const and only becomes a real list when something uses it -
  /// this is describe-time, but a per-query empty list for a feature nobody
  /// used is still waste worth not paying.
  List<int> _anyGroups = const <int>[];

  static int _bitOf(Type type) {
    assert(
      type != String && type != int && type != double && type != bool,
      'a query names Component types, and $type is not one. Passing a bare '
      'Type means the analyzer cannot check this for you (see QueryBuilder\'s '
      'doc) - the bit would be allocated to $type and quietly consume one of '
      'ComponentTypeRegistry\'s 64 slots.',
    );
    return ComponentTypeRegistry.bitFor(type);
  }

  /// ORs every non-null argument's bit together. Ten explicit parameters
  /// rather than a `List<Type>` at each call site: Dart has no varargs, and
  /// this keeps `withAll(A, B)` from allocating a list per call.
  static int _mask(Type a, Type? b, Type? c, Type? d, Type? e, Type? f, Type? g,
      Type? h, Type? i, Type? j) {
    var mask = _bitOf(a);
    if (b != null) mask |= _bitOf(b);
    if (c != null) mask |= _bitOf(c);
    if (d != null) mask |= _bitOf(d);
    if (e != null) mask |= _bitOf(e);
    if (f != null) mask |= _bitOf(f);
    if (g != null) mask |= _bitOf(g);
    if (h != null) mask |= _bitOf(h);
    if (i != null) mask |= _bitOf(i);
    if (j != null) mask |= _bitOf(j);
    return mask;
  }

  @override
  QueryBuilder withAll(Type a,
      [Type? b, Type? c, Type? d, Type? e, Type? f, Type? g, Type? h, Type? i, Type? j]) {
    _required |= _mask(a, b, c, d, e, f, g, h, i, j);
    return this;
  }

  @override
  QueryBuilder withNone(Type a,
      [Type? b, Type? c, Type? d, Type? e, Type? f, Type? g, Type? h, Type? i, Type? j]) {
    _forbidden |= _mask(a, b, c, d, e, f, g, h, i, j);
    return this;
  }

  @override
  QueryBuilder withAny(Type a,
      [Type? b, Type? c, Type? d, Type? e, Type? f, Type? g, Type? h, Type? i, Type? j]) {
    if (_anyGroups.isEmpty) _anyGroups = <int>[];
    _anyGroups.add(_mask(a, b, c, d, e, f, g, h, i, j));
    return this;
  }

  @override
  QueryBuilder withOptional(Type a,
      [Type? b, Type? c, Type? d, Type? e, Type? f, Type? g, Type? h, Type? i, Type? j]) {
    // Computed and discarded: naming a type here still registers its bit
    // (and runs the assert above), which is the only side effect optional
    // components have. Matching is deliberately untouched.
    _mask(a, b, c, d, e, f, g, h, i, j);
    return this;
  }

  @override
  Query build() => _storageOf(_required, _forbidden, _anyGroups);
}

/// Concrete `Query`: matches archetypes against a compiled [QueryBuilder]
/// and walks their live rows.
///
/// Two iteration styles, both allocation-free per step:
///  * [run] - a lazy `Iterable<Entity>`, for a plain `for (final e in
///    query.run())` loop (see `Transform2DSystem.onFixedUpdate`). The
///    `Iterable`/`Iterator` themselves are the one allocation, made once
///    per call to `run()`, not once per entity.
///  * [runQuery] - invokes [runner] once per matching entity with an
///    internal "current entity" cursor, and [get]/[tryGet] read through
///    that cursor. No `Entity` is materialized as a loop variable at all;
///    this is the path `SingleQuery.component` (see `GameRenderer2D`'s
///    reference usage) is built on.
class _ArchetypeQuery implements Query {
  _ArchetypeQuery(this._required, this._forbidden, this._anyGroups);

  final int _required;
  final int _forbidden;

  /// One mask per `withAny` group; empty in every query the engine itself
  /// currently writes, so [matches] usually never enters the loop at all.
  final List<int> _anyGroups;

  Entity? _cursor;

  /// Whether an archetype with this signature satisfies every constraint.
  ///
  /// Two masked compares, then one per `withAny` group. Deliberately an
  /// indexed `for` and not `_anyGroups.every(...)`: this runs once per
  /// archetype per query per tick, and a closure here is exactly the
  /// hot-path allocation RULES.md rules 1/2/5 forbid - the shape that was
  /// wrong in the sum-of-products version this replaced.
  @override
  bool matches(int signature) {
    if (signature & _required != _required) return false;
    if (signature & _forbidden != 0) return false;
    for (var i = 0; i < _anyGroups.length; i++) {
      if (signature & _anyGroups[i] == 0) return false;
    }
    return true;
  }

  @override
  T get<T extends Component>() {
    final cursor = _cursor;
    if (cursor == null) {
      throw StateError(
        'Query.get<$T>() called outside a runQuery() callback - there is no '
        'current entity.',
      );
    }
    return cursor.get<T>();
  }

  @override
  T? tryGet<T extends Component>() => _cursor?.tryGet<T>();

  @override
  void runQuery(void Function() runner) {
    for (final entity in run()) {
      _cursor = entity;
      runner();
    }
    _cursor = null;
  }

  @override
  Iterable<Entity> run() sync* {
    final archetypeCount = ArchetypeRegistry.count;
    for (var archetypeId = 0; archetypeId < archetypeCount; archetypeId++) {
      final storage = ArchetypeRegistry.byId(archetypeId);
      if (!matches(storage.componentSignature)) continue;
      for (var pageIndex = 0; pageIndex < storage.pageCount; pageIndex++) {
        // Null for a page whose scene has been unloaded - the slot is
        // tombstoned rather than removed so that live `Entity.pageIndex`
        // values keep addressing the right pages, so a query has to step
        // over the holes.
        final page = storage.pageAt(pageIndex);
        if (page == null) continue;
        for (final offset in page.rowOffsets) {
          yield Entity.pack(archetypeId, pageIndex, offset);
        }
      }
    }
  }
}

/// [SingleQuery]: a [Query] pre-filtered to one required component, with
/// [component] as sugar for `get<T>()` through the [runQuery] cursor - see
/// `GameRenderer2D`'s reference usage (`renderable.runQuery(() { final r =
/// renderable.component; ... })`).
final class _ArchetypeSingleQuery<T extends Component> extends _ArchetypeQuery
    implements SingleQuery<T> {
  _ArchetypeSingleQuery()
      : super(ComponentTypeRegistry.bitFor(T), 0, const <int>[]);

  @override
  T get component => get<T>();
}

/// Concrete [QueryDescriptor] - built once per `GameSystem.describeQuery`
/// call (see `Game`'s system bootstrap, a later phase).
final class ArchetypeQueryDescriptor implements QueryDescriptor {
  @override
  SingleQuery<T> has<T extends Component>() => _ArchetypeSingleQuery<T>();

  @override
  QueryBuilder query() => _QueryBuilder(_ArchetypeQuery.new);
}
