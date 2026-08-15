import 'package:meta/meta.dart';

import 'package:goo/src/coroutine/coroutine.dart';
import 'package:goo/src/archetype.dart';
import 'package:goo/src/pool.dart';
import 'package:goo/src/event.dart';
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
    with EventBus, Coroutines
    implements Comparable<GameSystem> {
  GameState? _state;

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

  /// Called once by the boot pass on the game isolate, immediately before
  /// [describeQuery]. Not part of the user-facing API: a system is bound by
  /// declaring it in `Game.describeSystems`, never by hand.
  @internal
  void bindState(GameState state) => _state = state;

  /// The simulation this system belongs to - scenes, sibling systems, the
  /// pool and the tick loop.
  ///
  /// **A `GameState`, not a `Game`, and that is the isolate boundary showing
  /// up in a field type** (RULES.md rule 9). A system only ever exists on the
  /// copy that simulates, so the object it holds is the one that simulates
  /// too. Holding a `Game` and asking it for a state would have compiled on
  /// the presentation isolate and found nothing there.
  GameState get state {
    final state = _state;
    if (state == null) {
      throw StateError(
        '$runtimeType is not bound to a GameState. Declare it in '
        'Game.describeSystems - a system constructed by hand has no scene to '
        'query and no tick to run on.',
      );
    }
    return state;
  }

  /// The game this system was declared in - `state.game`, for the declarations
  /// that legitimately live there (buffers, state channels, camera views).
  ///
  /// Typed as the base class, so a system that wants *its* game has to say so:
  /// prefer [getGame], which says it once and diagnoses the mismatch, over
  /// `game as MyGame` at every call site.
  Game get game => state.game;

  /// This system's game, as [T].
  ///
  /// The typed counterpart to [game], and the same shape `Entity.get<T>` and
  /// `Scene.get<T>` already use. A cast at the call site is the caller
  /// asserting something the API could have carried, and when it is wrong a
  /// bare `as` reports a `TypeError` naming two classes and no reason - this
  /// names the game that is actually running and where to look.
  T getGame<T extends Game>() {
    final game = state.game;
    if (game is T) return game;
    throw StateError(
      '$runtimeType asked for its game as $T, but this run is a '
      '${game.runtimeType}. A system reaches its own game to read what that '
      'game declared, so the two are fixed together at describe time - if '
      'they disagree, the system is declared in a different game than the one '
      'it was written for.',
    );
  }

  /// This system's state, as [T]. See [getGame] - same argument, other half.
  T getState<T extends GameState>() {
    final state = this.state;
    if (state is T) return state;
    throw StateError(
      '$runtimeType asked for its state as $T, but this run has a '
      '${state.runtimeType}. `Game.createState` decides which one a run gets, '
      'so this system is declared in a game whose state is not the one it was '
      'written against.',
    );
  }

  // provide a way for GameSystem to compile queries
  void describeQuery(QueryDescriptor descriptor) {}

  // There is no `describeState` or `describeBuffers` here, and both used to
  // exist. A `StateChannel` and a `BufferHandle` are backed by native memory
  // that the **main isolate** allocates before the spawn and frees on stop,
  // and their identity across the boundary is their index in that one
  // declaration pass. A system is not present for it: `describeSystems` runs
  // on the game isolate, so a system's declaration would have an index on one
  // copy and none on the other, which is the same thing as not having one.
  //
  // Declare them on the `Game` - which is also the side that *reads* them,
  // since a channel exists to be shown and a draw buffer exists to be drained
  // - and write through `game.myChannel` from here. `Renderer2D` is the
  // reference shape for a library doing this: the `Game` mixin declares the
  // frame buffers and `GameRenderer2D` fills them.

  /// Declares this system's input actions - see `Game.describeInputs`.
  ///
  /// Unlike the two passes deleted above this one survives, because it
  /// allocates nothing: the raw input block is a fixed size derived from
  /// `InputKey.count`, identical whatever a game declares, and an *action* is
  /// resolved against that block by the copy that ticks - which is this one.
  /// Main writes the block and never reads an action.
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
  ///
  /// Goes through the [GameState], which is where the declared systems live.
  /// There is no `Game.getSystem` to shortcut through any more - a system is a
  /// game-isolate object, and the presentation copy has none.
  T getSystem<T extends GameSystem>() => state.getSystem<T>();

  @override
  @internal
  GameState get simulationState => state;

  /// The running scene, as [T] - sugar for `state.getScene<T>()`. Throws if
  /// no scene is loaded (`GameState.scene` is nullable by design) or if it is
  /// some other type; read `state.scene` directly when absence is expected.
  T getScene<T extends SceneStruct>() => state.getScene<T>();

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

  /// The matching archetypes, one [QueryGroup] each.
  ///
  /// **The iteration to prefer**, and the reason is correctness before speed.
  /// A component instance belongs to an *archetype*, not to an entity -
  /// `entity.get<Mote>()` returns the same object for every entity of that
  /// archetype - so resolving it inside the row loop is work repeated for
  /// every row. Hoisting it out is only *correct* per archetype, though, since
  /// one query can match several; a group is that scope made explicit.
  ///
  /// ```dart
  /// for (final group in enemies.groups()) {
  ///   final enemy = group.get<Enemy>();          // once per archetype
  ///   final transform = group.get<Transform2D>();
  ///   for (final entity in group) {
  ///     transform.transformOffsetX[entity] += 1;
  ///   }
  /// }
  /// ```
  ///
  /// The returned list is rebuilt only when the set of archetypes changes -
  /// i.e. when a scene loads - so a tick iterating it allocates one list
  /// iterator, not one per entity. [run] walks the same rows through two
  /// nested `sync*` generators instead, which a profile put at ~7% of the
  /// engine's CPU.
  Iterable<QueryGroup> groups();

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
  QueryBuilder withAll(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]);

  /// Every listed component must be absent. Repeatable.
  QueryBuilder withNone(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]);

  /// At least one of the listed components must be present. Each *call* is
  /// its own group and every group must be satisfied, so
  /// `.withAny(A, B).withAny(C, D)` means "(A or B) and (C or D)", not
  /// "(A or B or C or D)".
  QueryBuilder withAny(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]);

  /// Declares that a match *may* have these components, without requiring
  /// or forbidding them. Pure documentation - it does not narrow the query.
  /// Its role is signalling to the reader (and, later, to codegen) that the
  /// loop body branches on `entity.tryGet<T>()`; `WorldTransformSystem` is
  /// the reference usage, matching every `Transform2D` entity whether
  /// hierarchy-linked or not and testing `tryGet<Child>()` inside.
  QueryBuilder withOptional(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]);

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
  final _ArchetypeQuery Function(
    int required,
    int forbidden,
    List<int> anyGroups,
  )
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
  static int _mask(
    Type a,
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ) {
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
  QueryBuilder withAll(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    _required |= _mask(a, b, c, d, e, f, g, h, i, j);
    return this;
  }

  @override
  QueryBuilder withNone(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    _forbidden |= _mask(a, b, c, d, e, f, g, h, i, j);
    return this;
  }

  @override
  QueryBuilder withAny(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    if (_anyGroups.isEmpty) _anyGroups = <int>[];
    _anyGroups.add(_mask(a, b, c, d, e, f, g, h, i, j));
    return this;
  }

  @override
  QueryBuilder withOptional(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
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

  /// Rebuilt only when the archetype set changes - i.e. when a scene loads.
  ///
  /// A `Query` outlives every tick, so the groups do too: iterating this costs
  /// one list iterator per tick rather than the per-archetype allocation a
  /// freshly-built list would.
  final List<QueryGroup> _groups = <QueryGroup>[];
  int _groupsBuiltFor = -1;

  @override
  Iterable<QueryGroup> groups() {
    final count = ArchetypeRegistry.count;
    if (_groupsBuiltFor != count) {
      _groups.clear();
      for (var archetypeId = 0; archetypeId < count; archetypeId++) {
        final storage = ArchetypeRegistry.byId(archetypeId);
        if (matches(storage.componentSignature)) {
          _groups.add(QueryGroup(storage));
        }
      }
      _groupsBuiltFor = count;
    }
    return _groups;
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

/// One matching archetype inside a [Query], and the rows it holds.
///
/// Exists so a component can be resolved **once per archetype** instead of once
/// per entity. `entity.get<Mote>()` is not a per-entity lookup pretending to be
/// cheap - it genuinely returns the same object every time, because a component
/// describes an archetype's layout and every row shares it. A profile put the
/// repeated resolution (`Entity.get`, `Entity.tryGet`, `ArchetypeRegistry.byId`)
/// at ~7% of the engine's CPU.
///
/// Hoisting it by hand is only correct when a query matches exactly one
/// archetype, which is not something a caller can see from the query. This
/// makes the scope explicit: inside a group there is exactly one archetype, so
/// [get] is both hoistable and obviously correct.
final class QueryGroup extends Iterable<Entity> {
  @internal
  QueryGroup(this.storage);

  /// The archetype this group iterates.
  final ArchetypeStorage storage;

  /// This archetype's instance of [T] - the prefab, viewed as one of the
  /// components it mixes in.
  ///
  /// Resolve it before the row loop and use it for every row.
  T get<T extends Component>() {
    // Widened to `Object` first: `prefab` is an `EntityStruct` and `T` is a
    // `Component`, and Dart will not promote between two class types neither
    // of which is a subtype of the other.
    final Object prefab = storage.prefab;
    if (prefab is T) return prefab;
    throw StateError(
      '${prefab.runtimeType} is not a $T. The query matched this archetype, '
      'so it satisfies the query\'s constraints - but $T is not among them. '
      'Add it to the query (withAll) or use tryGet.',
    );
  }

  /// [get], or null when this archetype does not have [T].
  T? tryGet<T extends Component>() {
    final Object prefab = storage.prefab;
    return prefab is T ? prefab : null;
  }

  /// A hand-written walk over this archetype's live rows.
  ///
  /// Not a `sync*` generator: those cost a `_SyncStarIterator` state machine
  /// per `moveNext`, which a profile put at ~5% of total CPU when the query
  /// ran through two of them nested (`run()` yielding through `rowOffsets`).
  @override
  Iterator<Entity> get iterator => _GroupIterator(storage);
}

final class _GroupIterator implements Iterator<Entity> {
  _GroupIterator(this._storage) : _archetypeId = _storage.archetypeId;

  final ArchetypeStorage _storage;
  final int _archetypeId;

  int _pageIndex = -1;
  MemoryPage? _page;
  int _stride = 0;
  int _limit = 0;
  int _offset = 0;
  Entity _current = Entity(0);

  @override
  Entity get current => _current;

  @override
  bool moveNext() {
    while (true) {
      final page = _page;
      if (page != null) {
        while (_offset < _limit) {
          final offset = _offset;
          _offset += _stride;
          if (page.isWalkable(offset)) {
            _current = Entity.pack(_archetypeId, _pageIndex, offset);
            return true;
          }
        }
        _page = null;
      }
      // On to the next page. Tombstoned slots (a scene unloaded) and pages
      // nothing ever allocated into are stepped over rather than ending the
      // walk - `Entity.pageIndex` indexes this list, so it is never compacted.
      _pageIndex++;
      if (_pageIndex >= _storage.pageCount) return false;
      final next = _storage.pageAt(_pageIndex);
      if (next == null) continue;
      final stride = next.strideBytes;
      if (stride == null || stride <= 0) continue;
      _page = next;
      _stride = stride;
      _limit = next.beginWalk();
      _offset = 0;
    }
  }
}
