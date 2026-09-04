import 'package:meta/meta.dart';
import 'package:good/src/animation/animatable.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/coroutine/coroutine.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/data.dart';
import 'package:good/src/event.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/scannable.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/system.dart';

abstract interface class Component implements Scannable {
  void describeType(ComponentDescriptor component);

  /// Declares every asset this component needs, and keeps each returned
  /// handle in a field - the third declare-time pass, chained through mixins
  /// with `@mustCallSuper` exactly like [describeType] and [describeStruct].
  ///
  /// Runs between the other two, not after them: a declared [Asset] is
  /// already addressed by the time it returns, so [describeStruct] can use it
  /// as a row default (`data.optPacked(assets.of<Texture>(), playerTexture)`)
  /// without a second pass or a late patch-up. A column named by its key
  /// instead - `data.hasAsset(key)` - needs no ordering at all.
  ///
  /// Runs on **both** isolate copies, in the same order, on every prefab a
  /// scene registers - that ordering is what assigns each asset its address,
  /// so it must never be made conditional on which copy is running. Only the
  /// *decode* is main-isolate-only; see [Assets].
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
/// single-instance one does - each instance is its own value held by its own
/// field, and one more field is one more instance's worth of columns.
/// `goo2d`'s `Sprite` is that shape: `Sprite.of(...)` is a
/// [CompositeDeclaration], so a field initialiser produces the whole group
/// and the scene lays it out where the field sits.
/// `Collider2D.describeCollider` is the older arrangement - a dedicated hook
/// called from `describeStruct` - and is what a [CompositeDeclaration]
/// replaces. Both markers are pure - no members of their own beyond what
/// [Component] already declares.
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

// NOTE: No longer carries <T>
// <T> was used to describe the type of the prefab, but it is no longer needed
// because .has on the describeType now accepts direct Type as parameter.
abstract class EntityStruct extends GameListenerBase
    with EventBus, Coroutines, Animations
    implements MultiComponent, ScannableField {
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
  ///
  /// These two were the last pair in the engine still declared from the hook,
  /// and the reason they were is gone. `SceneDescriptor.has` takes a
  /// `T Function()` and a closure may hand back an object that already
  /// existed - `descriptor.has(() => _prefab)` is how a fixture keeps a
  /// reference to the prefab it is about to register - so no binder was open
  /// around that construction and a dispatcher on a field here would have
  /// thrown for every one of them. Nothing is open around a declaration now:
  /// `Event.of` builds the dispatcher, and `EventBinder.bind` reads it off
  /// whatever object it was given. `archetype_test`'s `_Rock().archetype`,
  /// an `EntityStruct` with no scene at all, is unaffected for the same
  /// reason - a dispatcher nobody bound holds no listeners and says so.
  final mountedEvent = Event.of<EntityLifecycleListener, Entity>(
    (listener, entity) => listener.onEntityMounted(entity),
  );

  /// An entity of this struct is going away, because `Entity.destroy()` was
  /// called on it or because the scene holding it is being unloaded - both
  /// paths fire this. Its row is still readable during dispatch.
  final unmountedEvent = Event.of<EntityLifecycleListener, Entity>(
    (listener, entity) => listener.onEntityUnmounted(entity),
  );

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
  /// `describeType`/`describeStruct` passes run against [storage]. Not
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

  @override
  @mustCallSuper
  void describeType(ComponentDescriptor component) {
    component.has(type: runtimeType);
  }

  /// No-op base of the `describeAssets` chain - a prefab with no assets
  /// overrides nothing, and one with assets calls `super.describeAssets(...)`
  /// first, exactly as with [describeType]/[describeStruct].
  @override
  @mustCallSuper
  void describeAssets(AssetDescriptor descriptor) {}

  // helps find the length of the game object
  @override
  @mustCallSuper
  void describeStruct(DataDescriptor data) {}

}

/// Declares which component *types* an archetype carries - one `has<T>()` per
/// type, each ORing that type's bit into the archetype's signature, which is
/// the whole of what a query matches on.
///
/// Returns nothing, and there is no per-component enable toggle to reach for.
/// An archetype *is* its component set: switching a component off across the
/// whole archetype just describes a different archetype, and switching it off
/// for one entity needs a bit in every row plus a query that consults it, which
/// is a different feature entirely. The enable/disable that does exist works at
/// the level where it means something: whole systems, via
/// `GameState.enableSystem`.
abstract class ComponentDescriptor {
  void has<T extends Component>({Type? type});
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
  /// (see [ComponentDescriptor], whose own `has<T>()` is what declares the
  /// membership this reads back). Hoist it out of a loop over one group rather
  /// than asking per entity.
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
///   final healthHp = Field.int32(100);
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
