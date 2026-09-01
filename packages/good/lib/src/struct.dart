import 'package:meta/meta.dart';
import 'package:good/src/animation/animatable.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/coroutine/coroutine.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/data.dart';
import 'package:good/src/declare.dart';
import 'package:good/src/event.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/system.dart';

abstract interface class Component {
  /// Declares that whatever is being constructed carries the component type
  /// [T], and hands back the handle for it.
  ///
  /// Written once, in a field of the component mixin itself:
  ///
  /// ```dart
  /// mixin Health on Component {
  ///   final healthType = Component.type<Health>();
  ///
  ///   late final DataPointer<int> health;
  /// }
  /// ```
  ///
  /// Every prefab that writes `with Health` runs that initialiser, so the bit
  /// reaches the archetype's signature with nothing for the prefab to write
  /// and nothing for it to forget. `withAll(Health)` matches exactly the
  /// archetypes that mix `Health` in, and the two facts cannot drift apart
  /// because there is only one of them.
  ///
  /// The bit is [ComponentTypeRegistry.bitFor]'s, and the signature it lands
  /// in is `ArchetypeStorage.componentSignature`. `Field.float64` and
  /// `Asset.of` are the same move made for columns and for assets, and the
  /// registrar this reaches is `DeclarationContext.components`.
  ///
  /// # Refusing a combination
  ///
  /// [conflictsWith] maps each component type this one cannot share an
  /// archetype with to the sentence explaining the pair:
  ///
  /// ```dart
  /// mixin ScreenTransform2D on Component {
  ///   final screenTransform2DType = Component.type<ScreenTransform2D>(
  ///     conflictsWith: <Type, String>{
  ///       WorldTransform2D: 'They mean two different things by an offset.',
  ///     },
  ///   );
  /// }
  /// ```
  ///
  /// The pair is checked once the prefab is built, not when this runs: mixin
  /// field initialisers run in reverse `with` order, so at the moment a
  /// conflict is declared the other component may not have declared itself
  /// yet. Declaring it on either of the two is enough, and declaring it on
  /// both says the same thing twice.
  ///
  /// Throws when nothing is being constructed - a prefab built by hand, or a
  /// `late final` that runs on first read rather than during the pass that
  /// lays the archetype out.
  static ComponentType<T> type<T extends Component>({
    Map<Type, String> conflictsWith = const <Type, String>{},
  }) => ComponentType<T>._(
    T,
    DeclarationContext.components.declareComponent(T, conflictsWith),
  );

  /// Declares every asset this component needs, and keeps each returned
  /// handle in a field - the second declare-time pass, chained through mixins
  /// with `@mustCallSuper` exactly like [describeStruct].
  ///
  /// Runs before [describeStruct], not after: a declared
  /// [GameAssetInstance] is already addressed by the time it returns, so
  /// [describeStruct] can use it as a row default
  /// (`data.hasObject(playerTexture)`) without a second pass or a late
  /// patch-up.
  ///
  /// Runs on **both** isolate copies, in the same order, on every prefab a
  /// scene registers - that ordering is what assigns each asset its address,
  /// so it must never be made conditional on which copy is running. Only the
  /// *decode* is main-isolate-only; see [GameAssets].
  void describeAssets(AssetDescriptor descriptor);

  void describeStruct(DataDescriptor data);

  /// The scene the entity this component instance describes was registered
  /// with - reachable from any mixin `on Component`/`on MultiComponent`, not
  /// just from the top-level `EntityStruct` subclass, since `EntityStruct`
  /// adds nothing to `Component`'s own interface that a mixin's `on` bound
  /// could see. `EntityStruct` is the only implementation; every mixin just
  /// inherits visibility into it through this interface. Throws if the
  /// running scene isn't a [T] - see [EntityStruct]'s implementation.
  T getScene<T extends SceneStruct>();

  /// Sugar for `getScene<...>().game.getSystem<T>()` - reachable from any
  /// component mixin for the same reason as [getScene].
  T getSystem<T extends GameSystem>();
}

/// A stricter [Component]: opts a mixin into declaring *several* named,
/// independently-addressable instances of itself on one entity (several
/// sprites, several colliders) instead of exactly one. Dart disallows mixing
/// in the same mixin twice (`with Renderable2D, Renderable2D`), so a
/// multi-instance mixin doesn't declare its fields directly the way a
/// single-instance one does - it declares its own dedicated hook (see
/// `Renderable2D.describeSprites`/`Collider2D.describeCollider`, `goo2d`/
/// `goo2d_render`), called once from its own `describeStruct` override, and
/// every `has()`-style call inside that hook allocates one more instance's
/// worth of fields. Both markers are pure - no members of their own beyond
/// what [Component] already declares.
abstract interface class MultiComponent implements Component {}

// game object is just a structure of data, it doesn't hold the actual data it
// describes the data structure of the game object, and let the framework
// allocate memory for the game object and its components, and manage the data
// of the game object
//
// It is also a [GameListener] and an [EventBus], which is the bottom of the
// composition walk: a `GameState` offers its scenes, a `SceneStruct` offers the
// prefabs it registered, and here it stops - a prefab composes nothing further.
// That is what lets an event declared on the state reach every entity struct in
// the game, and one declared *here* reach this prefab and nothing else, which
// is the scoping that makes a per-struct mount hook possible at all.

// Carries no type parameter naming itself. A prefab's own bit comes from
// `runtimeType`, which the framework ORs in once the object is built.
abstract class EntityStruct extends GameListenerBase
    with EventBus, Coroutines, Animations
    implements MultiComponent {
  /// An entity of **this** struct was created.
  ///
  /// Declared here, so the collect pass fills it from this prefab's own
  /// composition and nothing wider - the narrowest scope in the engine, and
  /// the reason a listener never has to ask "is this event about my
  /// archetype". One level up it would be a single list told about every
  /// entity in the game.
  ///
  /// A struct hears its own entities by mixing in `EntityLifecycleListener`,
  /// which this dispatcher then collects - there is no separate virtual. The
  /// same mixin on a `GameSystem` hears **nothing**: this is the only kind of
  /// dispatcher that delivers it, and it collects the struct. A system wanting
  /// every entity in the game mixes in `EntitySpawnListener`, which
  /// `GameState` declares - the scope is decided by which dispatcher collects
  /// the listener, not by which method it overrides.
  late final EventDispatcher<EntityLifecycleListener, Entity> mountedEvent;

  /// An entity of this struct is going away, because `Entity.destroy()` was
  /// called on it or because the scene holding it is being unloaded - both
  /// paths fire this. Its row is still readable during dispatch.
  late final EventDispatcher<EntityLifecycleListener, Entity> unmountedEvent;

  // These two stay in the hook while `GameState`'s ten moved onto their
  // fields, and the reason is that an `EntityStruct` does not have to be
  // built by the framework.
  //
  // `SceneDescriptor.has` takes a `T Function()`, and a closure may hand back
  // an object that already existed - `descriptor.has(() => _prefab)` is how a
  // fixture keeps a reference to the prefab it is about to register, and how a
  // prefab taking a constructor argument gets one. No binder is open around
  // that construction, so a dispatcher declared on a field of this class would
  // throw for every one of them. `archetype_test`'s `_Rock().archetype`
  // pins the sharper version: an `EntityStruct` with no scene at all is a
  // supported state with its own error message, and it has to stay reachable.
  //
  // A prefab the framework *does* build - `descriptor.has(Mote.new)`,
  // `EntityStruct.of(Barrel.new)` - has a binder open around it, so `Event.*`
  // on a subclass's field works and is the shape to reach for. It is only
  // this base pair, which every struct inherits however it was built, that
  // cannot assume one.
  @override
  @mustCallSuper
  void describeEvents(EventDescriptor descriptor) {
    super.describeEvents(descriptor);
    mountedEvent = descriptor.has(
      (listener, entity) => listener.onEntityMounted(entity),
    );
    unmountedEvent = descriptor.has(
      (listener, entity) => listener.onEntityUnmounted(entity),
    );
  }

  late SceneStruct _associatedScene; // <- scene holds memory pool
  late ArchetypeStorage _archetype;
  bool _bound = false;

  /// The scene this prefab was registered with, via
  /// `SceneDescriptor.has(...)` in `SceneStruct.describeScene`.
  SceneStruct get scene {
    assert(_requireBound());
    return _associatedScene;
  }

  @override
  @protected
  GameState get simulationState => scene.state;

  @override
  R getScene<R extends SceneStruct>() {
    final s = scene;
    if (s is R) return s;
    throw StateError('The running scene is ${s.runtimeType}, not $R.');
  }

  @override
  R getSystem<R extends GameSystem>() {
    final state = scene.stateOrNull;
    if (state == null) {
      throw StateError(
        '$runtimeType cannot reach a system: its Game has no GameState. '
        'Systems live on the game isolate, and a component only ever runs '
        'there - so this means Game.start() has not run.',
      );
    }
    return state.getSystem<R>();
  }

  /// This struct's layout and row storage. One per `EntityStruct`
  /// subclass, created the single time the struct is registered - see
  /// [ArchetypeStorage]'s note on why two structs with identical fields
  /// still get two archetypes.
  ArchetypeStorage get archetype {
    assert(_requireBound());
    return _archetype;
  }

  /// Packed into the top 16 bits of every `Entity` created from this
  /// prefab.
  int get archetypeId => archetype.archetypeId;

  /// Called once by `SceneDescriptor.has`, immediately before the
  /// `describeAssets`/`describeStruct` passes run against [storage]. Not
  /// part of the user-facing API: a struct is bound by registering it with
  /// a scene, never by hand.
  @internal
  void bindArchetype(SceneStruct scene, ArchetypeStorage storage) {
    if (_bound) {
      throw StateError(
        '$runtimeType is already registered with a scene. An EntityStruct '
        'instance is a prefab - one instance describes one archetype - so it '
        'can only be passed to SceneDescriptor.has() once. Create a second '
        'instance (or a second subclass) instead of re-registering this one.',
      );
    }
    _associatedScene = scene;
    _archetype = storage;
    _bound = true;
  }

  /// Rejects a prefab that was never registered with a scene.
  ///
  /// Read through [scene] and [archetype], so `addEntityIn` pays it on every
  /// spawn - hence the `assert(_requireBound())` spelling at both call
  /// sites. Whether a prefab reached `descriptor.has` is decided by
  /// `describeScene` and cannot change afterwards, so it is a question about
  /// the code, not about the running game. A release build that
  /// somehow got here still fails, on the `late` fields this guards, just
  /// without the sentence explaining what to do about it.
  bool _requireBound() {
    if (!_bound) {
      throw StateError(
        '$runtimeType has not been registered with a scene. Declare it in '
        'SceneStruct.describeScene via `descriptor.has($runtimeType.new)` '
        'before creating entities from it.',
      );
    }
    return true;
  }

  /// No-op base of the `describeAssets` chain - a prefab with no assets
  /// overrides nothing, and one with assets calls `super.describeAssets(...)`
  /// first, exactly as with [describeStruct].
  @override
  @mustCallSuper
  void describeAssets(AssetDescriptor descriptor) {}

  // helps find the length of the game object
  @override
  @mustCallSuper
  void describeStruct(DataDescriptor data) {}

  /// Declares one entity in whatever declaration scope is open, and returns
  /// its prefab.
  ///
  /// In an `EntityStruct`'s field initialisers the open scope is **this**
  /// prefab, so what is declared is a child of every entity spawned from it:
  ///
  /// ```dart
  /// class Turret extends EntityStruct with Transform2D, Parent {
  ///   final barrel = EntityStruct.of(Barrel.new);
  /// }
  /// ```
  ///
  /// Spawning a `Turret` spawns a `Barrel` and links it under the turret;
  /// `turretEntity<Parent>()[turret.barrel]` reads which one. Destroying the
  /// turret destroys the barrel with it, because a declared child is an
  /// ordinary child.
  ///
  /// # Why it takes a constructor
  ///
  /// `EntityStruct.of(Barrel.new)`, not `EntityStruct.of<Barrel>()`. Dart has
  /// no `new T()` - instantiating a type parameter is
  /// `invocation_of_non_function`, verified on 3.13 - so a type argument
  /// alone cannot build the prefab, and there is no factory registry to look
  /// one up in. The tear-off is also what `SceneDescriptor.has` has taken
  /// since #57, and for the same reason: the child's own field initialisers
  /// declare columns, so a descriptor has to be open before the object
  /// exists. A constructor with arguments goes in a closure,
  /// `EntityStruct.of(() => Barrel(bore: 5))`.
  ///
  /// # Why it returns the prefab and not a column
  ///
  /// The declaring struct is one instance for the whole archetype, so the
  /// child *entity* is per-parent-entity state and lives in a column. The
  /// prefab is not: it is the same object for every turret in the game, and
  /// it is what `barrel.someField[e]` resolves against. A single static
  /// return type cannot be the prefab in one scope and a column in another,
  /// so it is the prefab, and the column is reached by indexing it.
  ///
  /// # What is enforced, and when
  ///
  /// The bound stays `T extends EntityStruct`, because Dart has no
  /// intersection bound to write `T extends EntityStruct & Child` with - and
  /// because a scene-scope declaration is not a `Child` at all. So both
  /// hierarchy constraints are registration-time errors, raised the first
  /// time the scene is built: the declarer must mix in `Parent`, and [T] must
  /// mix in `Child`.
  ///
  /// What *is* static is the read: `ParentAccessor.operator []` takes a
  /// `Child`, so asking a parent for something that could never have been
  /// declared as a child does not compile.
  static T of<T extends EntityStruct>(T Function() create) =>
      DeclarationContext.prefabs.declareChild<T>(create);
}

/// What [Component.type] hands back: one component type's place in the query
/// signature, held in the field that declared it.
///
/// There is no per-component enable toggle to reach for. An archetype *is* its
/// component set: switching a component off across the whole archetype just
/// describes a different archetype, and switching it off for one entity needs
/// a bit in every row plus a query that consults it, which is a different
/// feature entirely. The enable/disable that does exist works at the level
/// where it means something: whole systems, via `GameState.enableSystem`.
final class ComponentType<T extends Component> {
  const ComponentType._(this.type, this.bit);

  /// The type declared, which is [T]. Carried as a value so it can be passed
  /// to `withAll` and the rest, which take a `Type`.
  final Type type;

  /// The single-bit mask this type holds in every signature in this process -
  /// [ComponentTypeRegistry.bitFor]'s answer for [type], read once at declare
  /// time.
  ///
  /// A mask, not an index, because every use of it is an AND or an OR against
  /// `ArchetypeStorage.componentSignature`.
  final int bit;

  @override
  String toString() => 'ComponentType<$type>(bit ${bit.toRadixString(2)})';
}

/// A handle to one row of component data, packed into a single 64-bit int:
///
/// ```text
///   63          48 47          32 31                            0
///  +--------------+--------------+------------------------------+
///  | archetype id |  page index  |     row offset (bytes)       |
///  +--------------+--------------+------------------------------+
/// ```
///
/// An extension type over `int`, so passing one around, storing one in a
/// native row, or writing one into a command ring buffer costs nothing -
/// there is no object here to allocate or trace (the no-allocation rule). Every
/// accessor below is shifts and masks on that int.
///
/// The archetype id indexes the *process-global* [ArchetypeRegistry] rather
/// than anything scene-local, precisely so this handle needs to carry no
/// references - see that class's doc for why that trade was made.
///
/// The row offset is a byte offset within its page, not an address: the
/// page's backing slot rotates every tick (see `MemoryPool.beginTick`), so
/// the offset is the only thing stable across ticks. 32 bits covers any
/// page up to 4 GiB; the default page size is 64 MiB.
///
/// There is no reserved null/invalid value - `Entity(0)` is the legitimate
/// first row of archetype 0's first page. Callers needing "no entity" want
/// a nullable `Entity?`.
extension type const Entity(int value) implements int {
  static const int _archetypeShift = 48;
  static const int _pageShift = 32;
  static const int _idMask = 0xFFFF;
  static const int _rowMask = 0xFFFFFFFF;

  /// Packs the three fields above. Called from
  /// `ArchetypeStorage.allocateRow`; the shift can push bits into the sign
  /// position, which is fine because every unpack masks.
  const Entity.pack(int archetypeId, int pageIndex, int rowOffset)
    : value =
          (archetypeId << _archetypeShift) |
          (pageIndex << _pageShift) |
          rowOffset;

  int get archetypeId => (value >> _archetypeShift) & _idMask;
  int get pageIndex => (value >> _pageShift) & _idMask;
  int get rowOffset => value & _rowMask;

  /// The prefab describing this entity's archetype - the instance holding
  /// Which loaded scene this row belongs to, as `Scene.slot`, or -1 if its
  /// page has been freed or it was created outside any scene.
  ///
  /// Not packed into the handle - there are no spare bits (see the diagram
  /// above) - so it is read from the *page*, which carries the slot because
  /// rows of one archetype from two loaded scenes never share one. Two list
  /// indices and a field read, no allocation. There is no front scene for it
  /// to name; `goo2d` compares it against the slot a camera is in, so a view
  /// draws - and its pointer picks - only the scene that camera occupies.
  int get sceneSlot =>
      ArchetypeRegistry.byId(archetypeId).pageAt(pageIndex)?.ownerSceneSlot ??
      -1;

  /// This entity, seen as its [T] component:
  ///
  /// ```dart
  /// entity<Transform3D>().distanceTo(other)
  /// final local = entity<Transform2D>().component;
  /// ```
  ///
  /// Naming a component is a claim that the archetype carries it. When it does
  /// not, [Accessor.component] fails - an assertion in debug, the cast behind
  /// it in release. Ask [has] first when absence is a case you handle:
  ///
  /// ```dart
  /// if (entity.has<Transform2D>()) entity<Transform2D>().offsetX = 10;
  /// ```
  ///
  /// See [Accessor], which is what this returns and where a component's
  /// helpers live.
  @pragma('vm:prefer-inline')
  Accessor<T> call<T extends Component>() => Accessor<T>(this);

  /// Whether this entity's archetype carries [T].
  ///
  /// ```dart
  /// if (entity.has<Transform2D>()) entity<Transform2D>().offsetX = 10;
  /// ```
  ///
  /// The guard for the claim `entity<T>()` makes. It resolves exactly the way
  /// [Accessor.component] does - one list index and an `is` test against the
  /// archetype prefab - so a `true` here is the same answer `component` will
  /// give, and nothing is allocated to ask.
  ///
  /// It is a question about the *archetype*, not the row: every entity of one
  /// archetype answers the same, because an archetype is its component set
  /// (see [Component.type], which is what declares the membership this reads
  /// back). Hoist it out of a loop over one group rather than asking per
  /// entity.
  ///
  /// Reading through [T] costs a second resolve, so a guard followed by a use
  /// resolves twice. That is the price of the branch; a system that wants one
  /// resolve queries for the component instead of testing for it.
  @pragma('vm:prefer-inline')
  bool has<T extends Component>() =>
      ArchetypeRegistry.byId(archetypeId).prefab is T;
}

/// One entity seen as its [T] component - what `entity<Transform3D>()`
/// returns, and where a component's helper methods live.
///
/// A helper reached this way takes only what it is *about*, because the
/// entity it operates on is the receiver:
///
/// ```dart
/// entity<Transform3D>().setEuler(yaw: 0.5);
/// entity<Transform3D>().lookAt(0, 0, 0);
/// final gap = entity<Transform3D>().distanceTo(other);
/// ```
///
/// # Writing one for your own component
///
/// Declare an extension named after the component, on `Accessor` of it:
///
/// ```dart
/// mixin Health on Component {
///   late final DataPointer<int> healthHp;
///
///   @override
///   void describeStruct(DataDescriptor data) {
///     super.describeStruct(data);
///     healthHp = data.hasInt32(100);
///   }
/// }
///
/// extension HealthAccessor on Accessor<Health> {
///   void damage(int amount) {
///     final health = component;
///     health.healthHp[this] = health.healthHp[this] - amount;
///   }
/// }
/// ```
///
/// Inside the extension `this` **is** the entity, so a column indexes with
/// `this` directly, and [component] hands back the `Health` it belongs to.
/// Hold that in a local when you touch it more than once - each read resolves
/// the component again.
///
/// A helper taking a *second* entity reads that one through its own component
/// (`other<Health>().component`), because it may be a different archetype with
/// a different row layout. Only the receiver is guaranteed to be this one.
///
/// Everything on [Entity] is available too - `destroy()` and `sceneSlot` - and
/// an accessor can be passed anywhere an entity is wanted, because it
/// implements [Entity].
///
/// # Naming a component that may not be there
///
/// There is one spelling, and it is a claim. `Entity.has` is how the claim is
/// checked first:
///
/// ```dart
/// entity<Health>().component                  // Health - fails if absent
/// if (entity.has<Health>()) entity<Health>().damage(3);
/// ```
///
/// [T] is not nullable and cannot be: an extension declared
/// `on Accessor<Health>` does not apply to an `Accessor<Health?>` receiver,
/// because extension types are covariant in their type parameter and the
/// nullable spelling is the *supertype*. So a nullable [T] would reach
/// [component] and nothing else - not one generated property, and not one of
/// the accessor extensions this class exists to hold.
///
/// # Why the helpers go here and not on the component
///
/// Two components can want the same method name, and `Accessor<Health>` and
/// `Accessor<Transform3D>` are different types, so each can declare
/// `distanceTo` or `damage` without the two colliding in a library that
/// imports both. A helper put on the component mixin, or on [Entity] itself,
/// has no such separation.
///
/// It costs nothing: `Accessor<T>` erases to [Entity], which erases to `int`,
/// so `identical(entity<T>().entity, entity)` holds and nothing is allocated
/// to reach a helper.
extension type const Accessor<T extends Component>(Entity entity)
    implements Entity {
  /// This entity's archetype prefab, seen as [T].
  ///
  /// One list index and a cast; no allocation.
  ///
  /// An archetype without [T] is a bug at the call site, not a case to
  /// branch on, so it is an assertion. Debug names the archetype, the
  /// component and the remedy; release, with assertions stripped, is left with
  /// the cast, which throws a `TypeError` on the same rows. Stripping the
  /// assertion removes the *diagnostic*, not the failure - there is no build
  /// in which this hands back a component the entity does not have.
  ///
  /// Use [Entity.has] to test for the component instead of catching either.
  @pragma('vm:prefer-inline')
  T get component {
    // Widened to `Object` first: `prefab` is an `EntityStruct` and [T] is a
    // `Component`, and Dart will not promote between two class types neither
    // of which is a subtype of the other.
    final Object prefab = ArchetypeRegistry.byId(entity.archetypeId).prefab;
    assert(
      prefab is T,
      'Entity of archetype ${prefab.runtimeType} (id ${entity.archetypeId}) '
      'does not have component $T. Use entity.has<$T>() to test for it.',
    );
    return prefab as T;
  }
}
