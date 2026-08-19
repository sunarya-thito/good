import 'package:meta/meta.dart';
import 'package:good/src/animation/animatable.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/coroutine/coroutine.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/data.dart';
import 'package:good/src/event.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/system.dart';

abstract interface class Component {
  void describeType(ComponentDescriptor component);

  /// Declares every asset this component needs, and keeps each returned
  /// handle in a field - the third declare-time pass, chained through mixins
  /// with `@mustCallSuper` exactly like [describeType] and [describeStruct].
  ///
  /// Runs between the other two rather than after them, deliberately: a
  /// declared [GameAssetInstance] is already addressed by the time it
  /// returns, so [describeStruct] can use it as a row default
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

// NOTE: No longer carries <T>
// <T> was used to describe the type of the prefab, but it is no longer needed
// because .has on the describeType now accepts direct Type as parameter.
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
  SceneStruct get scene => _requireBound()._associatedScene;

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
  ArchetypeStorage get archetype => _requireBound()._archetype;

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

  EntityStruct _requireBound() {
    if (!_bound) {
      throw StateError(
        '$runtimeType has not been registered with a scene. Declare it in '
        'SceneStruct.describeScene via `descriptor.has($runtimeType())` before '
        'creating entities from it.',
      );
    }
    return this;
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
/// Returns nothing. It used to hand back a `ComponentType<T>` carrying an
/// `isEnabled` toggle, and that was deleted: nothing ever read it, and the
/// toggle it implemented was **archetype-wide**, which is not a coherent
/// thing to want. An archetype *is* its component set - switching a component
/// off across the whole archetype just describes a different archetype, and
/// switching it off for one entity needs a bit in every row plus a query that
/// consults it, which is a different feature entirely. Enable/disable that
/// does exist works at the level where it means something: whole systems, via
/// `Game.enableSystem`.
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
  /// the `DataPointer` fields the struct's mixins wrote into their
  /// `late final`s. Combine with the entity itself to reach data:
  /// `instance.get<Transform2D>().transformOffsetX[instance]`.
  ///
  /// One list index plus an `is` test; no allocation on the success path.
  /// Throws if this entity's archetype does not include [T] - use
  /// [tryGet] when absence is expected.
  T get<T extends Component>() {
    final prefab = ArchetypeRegistry.byId(archetypeId).prefab;
    if (prefab is T) return prefab as T;
    throw StateError(
      'Entity of archetype ${prefab.runtimeType} (id $archetypeId) does not '
      'have component $T. Use tryGet<$T>() if that is expected.',
    );
  }

  /// Which loaded scene this row belongs to, as `Scene.slot`, or -1 if its
  /// page has been freed or it was created outside any scene.
  ///
  /// Not packed into the handle - there are no spare bits (see the diagram
  /// above) - so it is read from the *page*, which carries the slot because
  /// rows of one archetype from two loaded scenes never share one. Two list
  /// indices and a field read, no allocation; the renderer and the mouse
  /// picker use it to skip scenes that are not the front one.
  int get sceneSlot =>
      ArchetypeRegistry.byId(archetypeId).pageAt(pageIndex)?.ownerSceneSlot ??
      -1;

  /// [get], but `null` instead of throwing when the archetype lacks [T] -
  /// the `OptWith<Child>()` half of a query.
  T? tryGet<T extends Component>() {
    final prefab = ArchetypeRegistry.byId(archetypeId).prefab;
    return prefab is T ? prefab as T : null;
  }

  /// This entity, seen as its [T] component:
  ///
  /// ```dart
  /// entity<Transform3D>().distanceTo(other)
  /// ```
  ///
  /// See [Accessor], which is what this returns and where a component's
  /// helpers live.
  ///
  /// `call` rather than `operator []`: an operator cannot be generic, and an
  /// operator's return type cannot depend on its argument, so
  /// `entity[Transform3D]` could only ever be typed `Null`.
  Accessor<T> call<T>() => Accessor<T>(this);
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
///   late final DataPointer<int> hp;
///
///   @override
///   void describeStruct(DataDescriptor data) {
///     super.describeStruct(data);
///     hp = data.hasInt32(100);
///   }
/// }
///
/// extension HealthAccessor on Accessor<Health> {
///   void damage(int amount) {
///     final health = get<Health>();
///     health.hp[this] = health.hp[this] - amount;
///   }
/// }
/// ```
///
/// Inside the extension `this` **is** the entity, so `get<Health>()` needs no
/// receiver and a column indexes with `this` directly. Everything on [Entity]
/// is available too - `destroy()`, `sceneSlot`, `tryGet` - and an accessor
/// can be passed anywhere an entity is wanted, because it implements [Entity].
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
extension type const Accessor<T>(Entity entity) implements Entity {}
