## Unreleased

### Added

* **`InputDefault<T>`, and `inputDefaults` on `Game` and `GameSystem`** (#287).
  The value every action of a type falls back to, as configuration:

  ```dart
  class MyGame extends Game {
    @override
    List<InputDefault<Object?>> get inputDefaults => <InputDefault<Object?>>[
      const InputDefault<double>(0),
    ];

    final throttle = Input.of<double>();
  }
  ```

  Order still does not matter: defaults are matched to actions when the
  registry seals, once every source has spoken.

* **`CameraView.of()`**, a camera view declared on the field that holds it
  (#287):

  ```dart
  class MyGame extends Game2D {
    final minimap = CameraView.of();
  }
  ```

  It takes nothing - the field name is the identity - and hands back the view,
  addressed from zero in field order. The game it belongs to is hung on once
  the constructor returns, so `CameraView.game` answers from that point and
  `GameView` can show it. Refused outside a game's construction: the table is
  on the declaration stack for the whole of a scene's bring-up so that
  `CameraView.representation()` can read it, and a view declared there would
  have no viewport memory.

* **`RandomStream.of()`**, a random stream declared on the field that holds it
  (#287):

  ```dart
  class MyGame extends Game {
    final loot = RandomStream.of();
    final terrain = RandomStream.of();
  }
  ```

  It takes nothing and returns the stream, with no index and no seed. Both
  arrive at boot, on main, before the spawn: `Game.randomSeed` is an
  overridable getter, so it is read once every field has declared, and the
  declaration index is mixed into the seed there. Throws for a `Game` built by
  hand and for a `late final` that runs on first read, and a stream drawn from
  before its game has started says so.

* **`Game.randomStreamCount`**, how many streams this copy declared (#287).
  Sits beside `stateChannelCount` and `bufferCount`.

* **`CameraView.representation()`**, the `IntRepresentation` a camera-view
  column binds to for the scene being brought up (#287):

  ```dart
  mixin Camera on Component {
    final cameraView = Field.optPacked<CameraView>(CameraView.representation());
  }
  ```

  A row stores a view as its address, and an address only means anything
  against the table that issued it, so the column names the table. The table
  belongs to the game: `SceneStruct.initializeScene` opens it over the same
  span it opens the asset descriptor over, one of it serves every prefab the
  scene registers, and a nested prefab reaches the same object its declarer
  does. Throws outside a scene's declaration passes, and for a `late final`
  that runs on first read.

* **`Component.declared<T>()`**, the single-instance twin of
  `MultiComponent.declared` (#287). It hands back the one `T` the prefab being
  constructed declared, or null where it declared none, and refuses a second by
  count - a component holding one field would store the second nowhere. It is
  what `goo2d`'s `Text2D` takes its `TextLabel` with.

* **A component takes its declarations from the prefab's own fields.**
  `Component.declare` records one, `MultiComponent.declared<T>()` takes every
  `T` recorded so far, and the pair is what lets `goo2d` spell a sprite or a
  collider as a field (#287):

  ```dart
  mixin Renderable2D on MultiComponent {
    final List<Sprite> sprites = MultiComponent.declared<Sprite>();
  }
  ```

  The list cannot be built by the initialisers that fill it: a mixin's own
  fields run **after** the applying class's - `class Sub extends Base with M1,
  M2` runs `Sub`, `M2`, `M1`, `Base` - so a prefab's `Sprite.of` calls happen
  while `Renderable2D` has no fields at all. `DeclarationContext` holds one
  collection per object under construction, and the component takes its own
  kind out of it on the way past. A list per construction, not one flat list,
  because `EntityStruct.of(Barrel.new)` builds a child prefab inside its
  parent's field initialisers and the child's sprites are the child's.

  A declaration nothing takes fails the registration by name, so a prefab that
  declares a `Sprite` without `with Renderable2D` is told which mixin is
  missing rather than drawing nothing.

* **`Asset.representation<T>()`**, the `IntRepresentation` an asset-typed
  column binds to for the scene being brought up (#287):

  ```dart
  final skin = Field.optPacked(Asset.representation<Texture>(), texture);
  ```

  A row stores an asset as its address and an address only means anything
  against the table that issued it, so the column names the table. Reaching it
  used to mean `getScene<SceneStruct>().assets.of<Texture>()` from a
  `describeStruct` body, which is an instance call. `AssetDescriptor` vends the
  same view through `representationOf<T>()`, and `Sprite.of` is the first
  caller.

* **An asset is declarable in the field that holds it.** `Asset.of(key)` reads
  the descriptor `SceneStruct.initializeScene` opens around a scene's
  declaration passes, so a prefab names a texture where it uses it instead of
  overriding `describeAssets` and carrying the handle in a `late final` (#194):

  ```dart
  class Player extends EntityStruct with Transform2D, Renderable2D {
    final texture = Asset.of(Textures.player);
  }
  ```

  It is `AssetDescriptor.has` reached without being handed the descriptor - the
  same call making the same registration, so the scene loads exactly what it
  loaded before, and `has` stays. `Field.float64` is the same move made for
  columns.

  Idempotence carries over unchanged, and it is what stops a declaration at the
  use site multiplying the asset: two prefabs writing
  `Asset.of(Textures.player)` get the *identical* handle, one address and one
  decode.

  `DeclarationContext.assets` is the seventh level of the declaration stack and
  the only one scoped to a scene rather than to a constructor, because that is
  what an asset belongs to. One `_AssetDescriptor` serves the scene's own
  `describeAssets` and every prefab it registers, so no prefab has an asset
  list of its own and there is no attribution to get wrong - which is why this
  level has no barrier and needs none. A `SceneStruct`'s own field initialisers
  still cannot declare: a scene has no `Assets` until `initializeScene`, which
  runs after the constructor returns, the same fact `Field.*` states for
  scenes.

* **A component type's query bit can be fixed at build time.** `good_tool`
  writes `goodComponentBits` into `lib/src/component_bits.g.dart`, exported
  from `good.dart`. A game that names it - along with the tables of the other
  engine packages it uses - has those types numbered before its scenes register
  (#18):

  ```dart
  class MyGame extends Game {
    @override
    List<GeneratedComponentBits> get componentBits =>
        const <GeneratedComponentBits>[goo2dComponentBits];
  }
  ```

  Without it a bit is assigned the first time `ComponentDescriptor.has<T>()`
  names a type, so which bit a type holds follows the order the scenes happened
  to be declared in. That is why `ComponentTypeRegistry` says not to persist a
  signature, and for a registry with nothing seeded it still says so. Seeding
  pins the scanned half: under `goo2dComponentBits`, `Child` is bit 9 on every
  machine and in every run, which is what a signature needs before a client and
  a server can exchange one.

  A type no table holds takes the next free bit after the seeded ones. That is
  your own components, and it is every prefab: `EntityStruct` registers its own
  type with `has(type: runtimeType)`, and only a run knows what that is.
  Nothing a table pins moves because of it, and a game that names no table
  behaves exactly as it did.

  It costs a bit per type in every table named, whether the game mounts that
  type or not - sixteen of the sixty-four a signature holds, for `goo2d`,
  `goo3d` and `goo2d_physics_box2d` together. Name only the tables the game
  uses. Seeding more than sixty-four throws, naming every type in the seed;
  `good_tool` refuses at build time for the same reason, where it can name them
  before anything is compiled.

* **A property per column, on the accessor.** `entity<Child>().parent` reads
  the `childParent` column of that one entity, and assigning to it writes.
  `Child` and `Parent` gain five properties between them, generated by
  `good_tool` into `lib/src/accessors.g.dart` and exported from `good.dart`, so
  they arrive with the import you already have and there is nothing to run
  (#99, #300).

  A column keeps its component's prefix because two mixins declaring `x` on one
  prefab is a silent two-column bug; `Accessor<Child>` is its own type with
  nothing to collide with, so the property drops the prefix.
  `childNextSibling` is `nextSibling`. Where the column carries no prefix the
  name is left exactly as declared.

  **For code touching one entity.** `Accessor<T>` holds only the entity, so
  `component` re-resolves on every access and three property lines are three
  archetype lookups. A system walking many entities resolves the component once
  per group and indexes the column, which is what it already did; see *A
  property is for one entity, a column is for many* in the design rules. Every
  read is of the published snapshot, so nothing here answers "what did I write
  earlier in this tick" - that is still `column.readPending(entity)`.

  Your own components do not get these. The generator runs over the engine's
  own repository; a component in your game's `lib/` is not in it.

### Breaking

* **`Game.describeInputs`, `GameSystem.describeInputs` and `InputDescriptor`
  are gone** (#287). An action goes on the field that holds it and a
  type-level fallback goes in `inputDefaults`:

  | before | after |
  |---|---|
  | `late final Input<bool> fire;` plus `fire = input.has<bool>(b)` | `final fire = Input.of<bool>(b)` |
  | `input.hasDefaultValue<double>(0)` | `InputDefault<double>(0)` in `inputDefaults` |

  `Input.of` has shipped since the field form landed, so most of this is
  deleting the second spelling.

  **The engine's own three fallbacks moved out of the overridable half.**
  `bool -> false`, `Vector2 -> zero` and an empty `PointerContacts` are
  registered by boot, before any source's `inputDefaults` is read. Overriding
  the getter cannot drop them, which is what the `@mustCallSuper` on the hook
  was guarding - and that failure was silent: nothing broke at declaration
  time and the game ran until the first read of an unbound action.

  **A listener subscribed from a constructor body works on every action now.**
  It was conditional while an action could be a `late final` the hook filled
  in; a field initialiser has run by the time the constructor body does.

* **`Game.describeCameras` and `CameraDescriptor` are gone** (#287). A view is
  declared on the field that holds it:

  ```dart
  class MyGame extends Game2D {
    final minimap = CameraView.of();
  }
  ```

  | before | after |
  |---|---|
  | `late final CameraView minimap;` plus `minimap = descriptor.has()` | `final minimap = CameraView.of()` |

  **Addresses move.** Field initialisers run most-derived first and a mixin's
  run after the class applying it, where the hook ran `super` first. A game on
  `Game2D` declaring one view of its own now holds address 0 while
  `Renderer2D.defaultCamera` holds 1; under the hook it was the other way
  round. Nothing in the engine reads a literal address - a frame buffer is
  found by `view.pack()` - but a game that hard-coded 0 for the default camera
  has to stop.

  **A `Game2D` can no longer be constructed by hand.** `Renderer2D` declares
  `defaultCamera` on a field, so `MyGame()` outside `Game.start` is refused the
  same way a `Channel.*` field already refuses it.

* **`Game.cameraViews` is a getter, not a final field** (#287). It reads the
  table `Game.start` opened around the constructor. Nothing that only reads it
  changes.

* **`Game.describeRandom` and `RandomDescriptor` are gone** (#287). A stream is
  declared on the field that holds it:

  ```dart
  class MyGame extends Game {
    @override
    int get randomSeed => 777;

    final loot = RandomStream.of();
  }
  ```

  | before | after |
  |---|---|
  | `late final RandomStream loot;` plus `loot = descriptor.has()` | `final loot = RandomStream.of()` |

  Declaration order still is a stream's identity, and it is now the order the
  fields run in: a subclass's initialisers run before its superclass's, so a
  game that declared streams on both sides of a hierarchy gets a different
  numbering than the `super`-first hook produced, and therefore different
  sequences from the same seed. Nothing else moves - one class declaring its
  own streams in one place keeps the order it had.

* **`MemoryPool.getPage` and `MemoryPage.ownerArchetypeId` are gone, and
  `MemoryPool.allocatePage` no longer takes `ownerArchetypeId`** (#332, #335).
  Both were public and neither was read by the engine or by any test that
  exercised the pool through its callers.

  A pool page has no stable index any more, so there is nothing for `getPage`
  to take. Attributing a page to an archetype goes through
  `ArchetypeStorage.pageAt`, which is where `WorldCensus.of` already gets it:
  the archetype holds its own page list, so the grouping comes for free.
  `MemoryPage.ownerSceneSlot` is unchanged and still names the scene.

  | before | after |
  |---|---|
  | `pool.getPage(i)` | `storage.pageAt(i)`, per archetype |
  | `pool.allocatePage(ownerArchetypeId: id, ownerSceneSlot: s)` | `pool.allocatePage(ownerSceneSlot: s)` |
  | `page.ownerArchetypeId` | the `ArchetypeStorage` the page came from |

* **`Game.maxPages` counts pool pages that are live, not pages allocated over
  the process's life** (#335). `MemoryPool.freePage` removes the page from the
  pool instead of leaving a tombstone behind, so unloading a scene returns its
  budget and `MemoryPool.pageCount` reports what is live.

  Before this, a game that loaded and unloaded scenes for long enough reached
  the default ceiling of 128 on churn alone while holding a handful of pages,
  and the refusal read `MemoryPool exhausted: all 128 pages are allocated`
  with 127 of them freed. The refusal names live pages now, and is reachable
  only with that many held at once.

  A game that sized `maxPages` around the churn is holding a number larger
  than it needs. Nothing breaks at a larger value; it caps a live population
  now.

* **`MultiComponent.declare` is `Component.declare`** (#287). It records a
  declaration against the prefab being constructed, and nothing about that is
  multi-instance - a single-instance component records the same way and takes
  it back with `Component.declared<T>()`. Statics do not inherit in Dart, so
  the old spelling no longer resolves; rename the call.

* **`GameSceneDescriptor.has` takes the constructor, not an instance** (#287):

  ```dart
  class MyGame extends Game {
    late final MainScene mainScene;

    @override
    void describeScenes(GameSceneDescriptor descriptor) {
      super.describeScenes(descriptor);
      mainScene = descriptor.has(MainScene.new);
    }
  }
  ```

  | before | after |
  |---|---|
  | `descriptor.has(MainScene())` | `descriptor.has(MainScene.new)` |
  | `descriptor.has(MainScene(seed: 7))` | `descriptor.has(() => MainScene(seed: 7))` |

  The framework builds the scene inside `EventBinder.open`, the same as the
  other three descriptors. Two things follow. A scene declares its own events
  on a field - `final waveCleared = Event.of(...)` - so the `late final` a
  constructor body had to assign is gone. And a scene handed over already
  constructed - `descriptor.has(() => _level)` - is refused when it was built
  inside another owner's window, because its field dispatchers landed there and
  would collect that owner's whole composition.

  A scene the caller builds and passes to `GameState.loadScene` is unchanged:
  it has no window, and `EventBus.events` in its constructor body is still its
  route.

* **`Animations.describeAnimation` and `TimelineStruct.describeTrack` are
  gone** (#287). A timeline goes on the field that holds it and a track carries
  its own default:

  ```dart
  class EnemyTimeline extends TimelineStruct {
    final x = Track.of(0.0);
    final frame = Track.of(0);
  }

  class Enemy extends EntityStruct {
    final timeline = TimelineStruct.of(EnemyTimeline());
  }
  ```

  `AnimationTypeDescriptor` and `TimelineDescriptor` go with them.
  `TimelineStruct.of` takes an instance and not a constructor, because a
  timeline declares nothing outside itself; what the declaration buys it is the
  scene, and therefore the clock `TimelineAnimation.animate` samples against.
  That is settled when the prefab finishes constructing, where
  `describeAnimation` used to settle it.

  `TimelineStruct.describeAnimation` stays. A clip keys the tracks its timeline
  holds, so it names sibling fields, and a field initialiser cannot read one.

* **`describeQuery` is gone. A query is a value, so it goes on the field that
  holds it** (#287):

  ```dart
  class SwirlSystem extends GameSystem with FixedTickable {
    final motes = Query.all(Transform2D, Mote);
    final roots = Query.where().withAll(WorldTransform2D).withNone(Child).build();
    final cameras = Query.has<Camera>();
  }
  ```

  | before | after |
  |---|---|
  | `void describeQuery(QueryDescriptor d) { q = d.query().withAll(A, B).build(); }` | `final q = Query.all(A, B);` |
  | `d.has<Camera>()` | `Query.has<Camera>()` |
  | `d.query()` | `Query.where()` |

  `QueryDescriptor` and `ArchetypeQueryDescriptor` go with it. Neither was a
  registrar: a query holds masks and resolves archetypes lazily in
  `Query.groups`, so building one needs no open declaration window and the
  descriptor added nothing but a second spelling.

* **`describeState` is gone. A `Game` declares its channels in fields**
  (#287):

  ```dart
  class MyGame extends Game {
    final score = Channel.int32();
    final alive = Channel.boolean(true);
  }
  ```

  | before | after |
  |---|---|
  | `void describeState(StateDescriptor d) { score = d.hasInt32(); }` | `final score = Channel.int32();` |

  `Channel.*` reads the descriptor `Game.start` opens around the constructor,
  which is the same descriptor the hook was handed. `StateDescriptor` stays as
  the registrar behind it.

  The seal on that descriptor goes too. It refused a declaration made through a
  descriptor held past boot, and there is no way to hold one now: the window is
  open only around the constructor, so a `late final score = Channel.int32()`
  reaches an empty stack in `DeclarationContext.channels` and throws there
  instead.

* **`describeParams` is gone, on a `Command` and on a `NetMessage` both**
  (#287):

  ```dart
  class SpawnEnemy extends SinkCommand<int> {
    final flags = Param.uint2();
  }
  ```

  | before | after |
  |---|---|
  | `void describeParams(ParamDescriptor d) { flags = d.hasUint2(); }` | `final flags = Param.uint2();` |

  `CommandRegistry.declare` and `good_net`'s `NetRegistry.declare` already
  opened the layout around the constructor through `ParamLayout.open`, so the
  fields were always declared before the hook ran. `bind` now fixes the index
  and seals. `ParamDescriptor` stays as the registrar behind `Param.*`, and the
  record vocabulary is unchanged, so a build's schema hash is unchanged.

* **A component's `describeAssets` is gone. A prefab declares an asset in the
  field that holds it** (#287):

  ```dart
  class Player extends EntityStruct with Transform2D, Renderable2D {
    final texture = Asset.of(Textures.player);
  }
  ```

  | before | after |
  |---|---|
  | `void describeAssets(AssetDescriptor d) { texture = d.has(Textures.player); }` | `final texture = Asset.of(Textures.player);` |

  `Asset.of` has been the field form since #194 and makes the same
  registration into the same descriptor, so a scene's footprint, its addresses
  and its decode count are what they were.

  `SceneStruct.describeAssets` **stays**. A scene is constructed by the caller
  and has no `Assets` until `initializeScene`, so its own field initialisers
  run before there is anything to declare into.

  What this costs is `descriptor.has(() => alreadyBuiltPrefab)` for a prefab
  with assets: the window is open only for the duration of that call, so a
  prefab that declares one has to be built inside it. A prefab that needs a
  constructor argument to pick its key declares in the initializer list, where
  the argument is in scope:

  ```dart
  class Prop extends EntityStruct with Transform2D, Renderable2D {
    Prop(TextureKey skin) : texture = Asset.of(skin);

    final TextureAsset texture;
  }
  ```

  Field initialisers run before the initializer list, so a prefab written that
  way declares its columns first and its asset after them. Both isolate copies
  run the same code, so the addresses agree either way.

  `good generate`'s missing-`super` check is down to `describeStruct`. A field
  initialiser is not a chain, so there is no `super` to leave out.

  `describeEvents` followed in its own commit, once the base pairs had a route
  that does not come off the declaration stack. See its entry below.

* **`describeEvents` is gone. An owner declares its dispatchers where it is
  built** (#287):

  ```dart
  class Orc extends EntityStruct {
    final wounded = Event.of<WoundListener, int>(
      (listener, damage) => listener.onWounded(damage),
    );
  }
  ```

  | before | after |
  |---|---|
  | `void describeEvents(EventDescriptor d) { wounded = d.has((l, n) => l.onWounded(n)); }` | `final wounded = Event.of<WoundListener, int>((l, n) => l.onWounded(n));` |
  | `void describeEvents(EventDescriptor d) { ... }` on a `SceneStruct` | `MainScene() { waveSpotted = events.has((l, w) => l.onWave(w)); }` |

  `Event.of` and `Event.signal` read the window the framework opens around a
  constructor call, and a declaration on a `SceneStruct` cannot: the caller
  constructs it, so no window is open while its fields initialise. A scene has
  `this` in its constructor body, so that is where it declares its own events,
  against `EventBus.events` - the owner's own registrar, read off the object
  and never off the stack. A `SceneStruct` no longer needs a hook for events at
  all. Its assets still do - `describeAssets` stays.

  The three pairs the framework declares for every subclass -
  `SceneStruct.mountedEvent`/`unmountedEvent`,
  `EntityStruct.mountedEvent`/`unmountedEvent` and
  `GameSystem.mountEvent`/`unmountEvent` - are fields with their own
  initialisers, through `Event.inherited` and `Event.inheritedSignal`. Those
  build the dispatcher, record it, and return it: they read no window, so the
  initialiser works whichever way the subclass was built. Which owner the
  declaration belongs to is settled after every field initialiser in the
  hierarchy has run, in `GameListenerBase`'s constructor body, which takes what
  was recorded. Taking it there and not off the open window is what keeps the
  scoping - a `SceneStruct` held on a `GameState` field is constructed inside
  the state's window, and its pair still reaches that scene's composition.

  Every dispatcher now exists by the end of the constructor rather than at
  boot. `EventBinder.bind` is one pass, `collectListeners`, and a prefab built
  by hand (`_Rock()`) has a readable `mountedEvent` before any game exists.

* **A prebuilt owner handed to `descriptor.has(() => built)` is refused when it
  was built inside another owner's declaration window** (#287).

  `final _spawner = Spawner();` in a `GameState` field runs while the state's
  window is open, so an `Event.of` on a `Spawner` field declares into the
  state. Measured before this refusal: such a system collected the state,
  itself and two unrelated systems, and firing its own event reached all four.
  It boots and ticks, so it is now a `StateError` at boot naming the class.

  A prefab a fixture built with nothing open above it stays legal to hand over:
  `Event.*` throws on an empty stack, so it declared nothing anywhere else, and
  its inherited pair landed on the prefab as it always does.

* **`describeType` is gone. A component declares its own type in a field**
  (#287):

  ```dart
  mixin Health on Component {
    final healthType = Component.type<Health>();

    final healthHp = Field.int32(100);
  }
  ```

  `Component.type<T>()` ORs `T`'s bit into the archetype's signature and hands
  back a `ComponentType<T>` carrying the type and the bit. It reads the
  registrar the framework opens around a prefab's constructor, which is the
  seventh thing to read that window after `Field.*`, `EntityStruct.of` and
  `Asset.of`. `ComponentDescriptor` is gone with the hook.

  | before | after |
  |---|---|
  | `void describeType(ComponentDescriptor c) { super.describeType(c); c.has<Health>(); }` | `final healthType = Component.type<Health>();` |

  A prefab writes nothing. `EntityStruct.describeType` existed to OR in
  `has(type: runtimeType)`, and the framework now does that itself once the
  constructor returns - `runtimeType` is not reachable from a field
  initialiser, and it is the one bit in a signature that only a run can know.

  This removes the chain and the failure the chain had: a component mixin that
  overrode the hook and left out `super` contributed no bit, so
  `withAll(ThatComponent)` matched every archetype instead of none. A field
  initialiser has no `super` to leave out. `good generate` stops checking
  `describeType` for a missing `super` because there is nothing left to check.
  `describeAssets` left the same set in the entry above; `describeStruct` is
  what remains.

  Bit assignment order moves with it. Mixin field initialisers run in reverse
  `with` order and the prefab's own type is added last, where the `super` chain
  ran base-first and the prefab's type first. Within a signature this is
  invisible - a signature is an OR - and a game naming its generated tables to
  `Game.componentBits` has every scanned type numbered before any of this
  happens. A game naming none sees different numbers for the same run, which is
  the property `ComponentTypeRegistry` already says not to depend on.

  **A component can refuse to share an archetype.** `conflictsWith` maps each
  type it cannot sit beside to the sentence explaining the pair, and the pair
  is checked once the prefab is built rather than as each component declares
  itself:

  ```dart
  final screenTransform2DType = Component.type<ScreenTransform2D>(
    conflictsWith: <Type, String>{
      WorldTransform2D: 'Only one of them can be true.',
    },
  );
  ```

  `ScreenTransform2D` and `Text2D` in `goo2d` asked the same question with
  `assert(this is! Other)` inside their hook bodies, which a field initialiser
  cannot do: an initialiser has no `this`. Declaring the refusal keeps the
  check and makes it symmetric - naming it on either of the two is enough.

* **`entity<T?>()` is gone. `Entity.call` takes `T extends Component` and
  `entity.has<T>()` answers whether the component is there** (#302):

  ```dart
  if (entity.has<Transform2D>()) entity<Transform2D>().offsetX = 10;
  ```

  The nullable spelling reached `.component` and nothing else. Extension types
  are covariant in their type parameter, so `Accessor<Transform2D?>` is the
  *supertype* of `Accessor<Transform2D>`, and an extension declared
  `on Accessor<Transform2D>` needs a subtype receiver. Every generated property
  and every hand-written accessor extension - `addChild`, `detach`, `setEuler`,
  `setText`, `lookAt` - was therefore unreachable from it, and
  `entity<Parent?>().addChild(kid)` did not compile.

  | before | after |
  |---|---|
  | `entity<Transform2D?>().component` | `entity.has<Transform2D>()`, then `entity<Transform2D>().component` |
  | `entity<Transform2D?>().component != null` | `entity.has<Transform2D>()` |

  `Accessor`'s bound reverts to `T extends Component` with it. `QueryGroup` and
  `Scene` are unaffected: their calls return the component or the scene struct
  directly rather than an accessor, so `group<Transform2D?>()` and
  `scene<Level?>()` go null and short-circuit as they always did.

  `has<T>()` is declared on `Entity`, so an `Accessor` has it too - it resolves
  the archetype prefab and tests it against `T`, the same lookup `.component`
  makes, and allocates nothing. It answers for the *archetype*, so hoist it out
  of a loop over one group rather than asking per entity.

* **A component the archetype lacks is an assertion, not a `StateError`.**
  `Accessor.component` asserts, then casts (#302):

  ```
  Failed assertion: Entity of archetype Player (id 3) does not have component
  Transform2D. Use entity.has<Transform2D>() to test for it.
  ```

  A release build strips the assertion and is left with the cast, which throws
  a `TypeError` on the same rows: stripping it removes the diagnostic, not the
  failure, and no build hands back a component the entity does not have. Code
  that caught the `StateError` should ask `has<T>()` instead - neither of these
  is meant to be caught.

* **`get` and `tryGet` are gone; the receiver is called instead.**
  `Entity`, `QueryGroup` and `Scene` each had a throwing `get<T>()` and a
  nullable `tryGet<T>()`. Both are removed and the receiver's own call takes
  their place (#220):

  | before | after |
  |---|---|
  | `entity.get<Transform2D>()` | `entity<Transform2D>().component` |
  | `entity.tryGet<Transform2D>()` | `entity.has<Transform2D>()`, then `entity<Transform2D>().component` |
  | `group.get<Transform2D>()` | `group<Transform2D>()` |
  | `group.tryGet<Transform2D>()` | `group<Transform2D?>()` |
  | `scene.get<Level>()` | `scene<Level>()` |
  | `scene.tryGet<Level>()` | `scene<Level?>()` |

`QueryGroup.call` takes `T extends Component?` and `Scene.call` takes
  `T extends SceneStruct?`, so those two say absence with a nullable type
  argument; `null is T` is the whole dispatch, and it is read only on the path
  where the component or the scene turns out not to be there. `Component?` and
  not `Object?`, so `group<String>()` is still refused where the type argument
  is written. `Entity` says it with `has<T>()` instead - see the entry above.

  `Entity` returns an `Accessor<T>` and the component is reached through
  `.component`. The accessor erases to an `int` and never allocates. On
  `QueryGroup` and `Scene` the call returns the component or the scene struct
  directly, so those return `null` themselves.

  A null-aware call has no sugar - `scene?<SceneStruct>()` does not parse - so
  the one site that needs it spells `scene?.call<SceneStruct>()`.

  A group asked for a component its archetype lacks ends
  `Add it to the query (withAll) or ask for Transform2D?.`
* **A time is a `Seconds`, not a bare `double`.** Every member that took or
  returned a span of simulated time in seconds now spells it, and a bare
  `double` in its place is a compile error (#196):

  | before | after |
  |---|---|
  | `.key(3, 1.0)` | `.key(3, Seconds(1.0))` |
  | `.hold(2.0)` | `.hold(Seconds(2.0))` |
  | `animate(offset: -startedAt[e])` | `animate(offset: -Seconds(startedAt[e]))` |
  | `animate(duration: 2.0)` | `animate(duration: Seconds(2.0))` |
  | `startAnimation(clip, b, duration: 2.0)` | `startAnimation(clip, b, duration: Seconds(2.0))` |
  | `double get TimelineAnimation.length` | `Seconds get length` |
  | `double get TimelineSample.seconds` | `Seconds get elapsed` |
  | `double get GameState.time` | `Seconds get time` |
  | `YieldInstruction.advance(double seconds)` | `advance(Seconds elapsed)` |
  | `CoroutineScheduler.step(double seconds)` | `step(Seconds elapsed)` |

  `Seconds` is `extension type const Seconds(double inSeconds)`, so it erases
  to the `double` it wraps and costs nothing to pass, return or hold - which is
  what a `Duration` could not do here. `Game.fixedTimeStep` can be a `Duration`
  because it is a constant read for its microseconds; `GameState.time` is
  computed per read and `animate(offset:)` is handed a column value per entity
  per frame, so a class in either place is a heap object on the hot path.

  It carries no `implements` clause, so neither direction converts on its own:
  a bare `1.5` is not a `Seconds`, and a `Seconds` is not a `double`. Read the
  number back with `inSeconds`, or `inMicroseconds` for the unit the engine
  stores. `Seconds.ofMicroseconds`, `Seconds.ofMilliseconds` and
  `Seconds.ofDuration` construct one, `Seconds.zero` is none, and `+`, `-`,
  unary `-`, `*`, `/` and the four comparisons are declared on it.

  A coroutine's `yield` is unchanged. It goes through a dynamic element and is
  read with `is num`, and a `Seconds` **is** a `double` at run time, so both
  `yield 1.5` and `yield Seconds(1.5)` work and neither is checked.

  There is no `1.0.s` extension on `num`. An extension member is resolved
  across every extension in scope at the use site, so one shipped here becomes
  a compile error in a file that never mentioned this engine as soon as the
  project also has `flutter_animate`, `dartx` or `time`, each of which defines
  `.ms` and `.seconds` on `num`.

* **An array column names its element as an argument.** The thirty-two
  `has*Array`/`opt*Array` methods on `DataDescriptor`, their thirty-two
  mirrors on `Field`, and `hasPackedArray`/`optPackedArray` beside them are
  gone, replaced by three methods that take a `DataElement<T>` (#262):

  | before | after |
  |---|---|
  | `data.hasUint16Array(8)` | `data.hasArray(.uint16, 8)` |
  | `data.hasFloat64Array(4, 1.5)` | `data.hasArray(.float64, 4, 1.5)` |
  | `data.hasFloat64ArrayOf(4, [1.5, 2.5])` | `data.hasArrayOf(.float64, 4, [1.5, 2.5])` |
  | `data.optInt32Array(3, -42)` | `data.optArray(.int32, 3, -42)` |
  | `data.hasPackedArray(table, 3, first)` | `data.hasArray(table, 3, first)` |
  | `Field.uint16Array(8)` | `Field.array(.uint16, 8)` |
  | `Field.packedArray(table, 3, first)` | `Field.array(table, 3, first)` |

  The element is a value, so the pointer's `T` follows from it -
  `data.hasArray(.float64, 8)` is a `DataArrayPointer<double>` - and the
  fourteen widths are static constants on `DataElement`, which is what makes
  the dot shorthand above resolve. `IntRepresentation` implements
  `DataElement` directly, with nothing wrapping it, so a representation and a
  native width are the same argument. Adding a width is one constant, where
  it was three declarations across two files.

  Two things follow that are not renames. `hasArrayOf` covers **every**
  element kind, so an integer array can start its elements apart, which only
  the two float widths could do (#35). And a representation element with no
  initial value is refused where the column is declared, naming `optArray`:
  the bits an unwritten element holds are 0, which a representation is under
  no obligation to have a value for.

  There is no nested-element form. The shape compiles - a static
  `DataElement.array(element, length)` types as
  `DataArrayPointer<ArrayView<ArrayView<int>>>` on the pinned SDK - but
  nothing in #262 spells out how a nested element is *read*, and
  `DataArrayPointer`'s own doc rules out the obvious answer: an extension
  type carries one value, so it cannot know which array field produced it.
  That is what two-argument `get`/`set` exists to avoid.

* **`DefaultPointer` is `InitialPointer`, and `defaultValue` is
  `initialValue`.** The value is stamped into the prototype row at `seal` and
  memcpy'd into every row allocated afterwards; nothing consults it on a read,
  so `hp[e] = null` reads back `null` and does not restore anything (#210).

  | before | after |
  |---|---|
  | `DefaultPointer<T>` | `InitialPointer<T>` |
  | `near.defaultValue = 10` | `near.initialValue = 10` |
  | `ArchetypeField.writeDefault(row)` | `ArchetypeField.writeInitialValue(row)` |

  The two comments that existed only to deny the reading the old name invited
  are gone with it - the file-level note in `data.dart` and the
  "stamped, not consulted" paragraph. The mechanism they were guarding is
  still written down where it belongs, on `initialValue` itself.

  `Track.defaultValue` does **not** move. A track's value really is consulted
  wherever no clip keys it, which is the meaning the other name never had.

* **`ParamDescriptor` gains `hasBool`, `hasInt1`, `hasInt2`, `hasInt4` and
  `hasUint64`**, with `Param.boolean`, `Param.int1`, `Param.int2`,
  `Param.int4` and `Param.uint64` beside them (#35). A command or a network
  message could not declare a bool at all; the documented way round it was
  `hasUint1` and a `? 1 : 0` at both ends.

  A `bool` parameter is one bit, the storage `hasUint1` takes, and carries its
  own code in the layout signature - so a declaration changed from one to the
  other is a handshake mismatch rather than a value read back as the wrong
  type. The code is added at the end of `_FieldKind` and no existing
  signature moves, so a peer built before this change still handshakes with
  one built after it as long as neither declaration list changed.

  What each descriptor does *not* offer is now written where the descriptor
  is: `DataDescriptor` has no `hasString` and cannot, `ParamDescriptor` has
  no heap objects, packed values, enums or arrays, and `StateDescriptor` has
  no sub-byte widths or entity handles. Each says why in place.

* **`AudioBackend` gains `setVoiceVolume`, and `AudioBus` gains four members.**
  A backend implemented outside this repository has one method to add (#17):

  ```dart
  @override
  void setVoiceVolume(int voice, double volume) =>
      engine.setVolume(voice, volume);
  ```

  `AudioMixer` calls it for every started voice on a bus whose level moved, so
  a level changed mid-game moves the sound already playing. An implementation
  applies the number as a step and does not ramp it.

  `AudioBus` was `master` alone; it is now `master`, `music`, `effects`,
  `dialogue` and `interface`. Existing calls still compile - `AudioBus.master`
  is unchanged and is still what everything else mixes into - but a `switch`
  over `AudioBus` with no default stops being exhaustive.

  The bus a voice plays on no longer reaches a backend as a bus at all.
  `AudioMixer` multiplies the voice's bus level by the master level and hands
  the product to `play`, so a backend that meant to route on the enum has
  nothing to route: it applies `volume` and mixes nothing itself.

* **`Child` and `Parent` columns carry their component's name.** An entity's
  columns share one namespace - a component is a mixin, so two of them
  declaring the same field is an override, not an error, and since #57 made
  field initialisers eager nothing at run time notices. The row grows by both
  columns, the name resolves to whichever mixin came last in the `with`
  clause, and writes aimed at the hidden column land on its neighbour.
  `Child.parent` was the worst of it: `parent` is exactly what a user's own
  component would call a field (#133).

  | before | after |
  |---|---|
  | `Child.parent` | `Child.childParent` |
  | `Child.nextSibling` | `Child.childNextSibling` |
  | `Child.prevSibling` | `Child.childPrevSibling` |
  | `Parent.firstChild` | `Parent.parentFirstChild` |
  | `Parent.lastChild` | `Parent.parentLastChild` |

  Names only. Column order, widths and `strideBytes` are unchanged, so a
  prefab's row layout is byte for byte what it was.

  The rule this follows is now written down in
  `docs/reference/design-rules.md` and taught in the guide, so a component you
  publish for other people to mix in has something to follow.

* **`Game.start` and `Game.startInline` take a constructor, not an instance.**
  `Game.start(MyGame())` becomes `Game.start(MyGame.new)`, and the same for
  `startInline`. A game taking constructor arguments goes through a closure:
  `Game.start(() => MyGame(seed: 7))`. The old spelling does not quietly keep
  working - a `Game` has no `call`, so an instance where a `G Function()` is
  wanted is a compile error at the start line (#91).

  ```dart
  // before
  final game = MyGame();
  await Game.start(game);

  // after
  final game = await Game.start(MyGame.new);
  ```

  **Why.** A channel or an input declared on the field that holds it - see
  Added - runs its initialiser during the constructor, and the descriptor and
  the registry have to be open before it does. An initialiser cannot see
  `this`, so the framework has to be the one constructing. Same trade
  `SystemDescriptor.has` made above, `CommandDescriptor.has` in #231 and
  `SceneDescriptor.has` in #57.

  **A widget can no longer hold the game before it starts.** The shape that
  built it in a field so `dispose` always had something to stop is gone,
  because the game does not exist until the start completes. Hold the
  **future** instead and hang the teardown off that - it covers a run that has
  booted and one still booting, which the field never did. The scaffolded
  `main.dart` and the Flutter-bridge guide both move to it.

  **A closure may hand back a game built earlier, and should not.**
  `Game.start(() => _game)` compiles. Nothing was open around *that*
  construction, so `Channel.*` and `Input.of` on its fields threw when it was
  built; a game with neither boots correctly. Starting an already-started one
  is refused before anything is written to it.

* **A `Game` constructed while another declaration window is open is
  refused.** Two shapes, both of which used to boot and run wrong, and neither
  visible from the field initialiser that caused it (#91):

  - a `Game` built inside another `Game`'s field initialisers declared its
    channels and actions into the outer game's windows. Measured: the outer
    game held 2 channels and 1 action, all of them the inner game's, and the
    inner game held none while its own handle read the outer game's storage.
  - a `Game` built inside a `GameSystem`'s constructor declared its actions
    into that system's registry. Measured: the host game held the 1 action and
    the game held 0.

  Both now throw at bring-up, naming the count and the shape.

* **`SystemDescriptor.has` takes a constructor, not an instance.**
  `descriptor.has(SpinSystem())` becomes `descriptor.has(SpinSystem.new)`, at
  every system declaration. A system taking constructor arguments goes through
  a closure: `descriptor.has(() => Box2DPhysicsSystem(gravityY: -10))`. The old
  spelling does not quietly keep working - a `GameSystem` has no `call`, so an
  instance where a `T Function()` is wanted is a compile error at the
  declaration line (#91).

  ```dart
  // before
  descriptor.has(SpinSystem());

  // after
  descriptor.has(SpinSystem.new);
  ```

  **Why.** An event or an input declared on the field that holds it - see
  Added - runs its initialiser during the constructor, and the binder and the
  input registry have to be open before it does. An initialiser cannot see
  `this`, so the framework has to be the one constructing. Same trade
  `CommandDescriptor.has` made in #231 and `SceneDescriptor.has` in #57.

  **A closure may hand back a system built earlier, and should not.**
  `descriptor.has(() => _spawner)` compiles and runs, because a closure is
  free to return anything. Nothing was open around *that* construction, so a
  field declaration on it does not declare what it appears to. Where the
  system was built in a `GameState` field initialiser the failure is silent
  rather than loud: the state's own binder is open at that moment, so the
  dispatcher is created against the state and reaches the state's whole
  composition. Keep the handle `has` returns instead.

* **`CommandDescriptor.has` takes a constructor, not an instance.**
  `descriptor.has(Damage())` becomes `descriptor.has(Damage.new)`, at every
  command declaration. The old spelling does not quietly keep working: an
  instance where a `T Function()` is wanted is an implicit tear-off of the
  command's own `call`, and that is a compile error at the declaration line
  (#91).

  ```dart
  // before
  damage = descriptor.has(Damage());

  // after
  damage = descriptor.has(Damage.new);
  ```

  **Why.** A parameter declared on the field that holds it — see Added — runs
  its `Param.*` initialiser at construction, and the record layout has to be
  open before it does. An initialiser cannot see `this`, so the framework has
  to be the one constructing. This is the same trade `SceneDescriptor.has` and
  `descriptor.has(Mote.new)` made for a struct's columns in #57.

  Building a command by hand now throws instead of returning a half-declared
  object: its pointers would name offsets in a layout nothing owns. A command
  that declares no fields still constructs fine.

* **The installed asset pack is now one tier of an ordered mount table.**
  `AssetPack.install`, `AssetPack.installed` and `AssetPack.uninstall` are
  gone; `AssetMounts.mount`, `AssetMounts.unmount` and `AssetMounts.clear`
  replace them. The generated `ensureGameReady()` changes with them, so
  re-running `good generate` picks the new spelling up (#108).

  ```dart
  // before
  AssetPack.install(AssetPack(mapping: assetMapping, key: assetKeyMaterial));

  // after
  AssetMounts.mount(AssetPack(mapping: assetMapping, key: assetKeyMaterial));
  ```

  One behavioural difference to know about: `install` *replaced* the pack, and
  `mount` **stacks**. Two mounts means two tiers, and the later one shadows
  the earlier one for any logical path they both carry. That is the point —
  see Added — but code that called `install` twice to swap packs must call
  `unmount` on the first.

* **`AssetPack` takes `chunkSource` instead of `bundle`.** The parameter is an
  `AssetMount` rather than an `AssetBundle`, so a downloaded patch can keep
  its chunks in a directory while the shipped pack keeps its own in the app
  bundle. `BundleMount(bundle: b)` is the direct translation, and passing
  nothing still reads `rootBundle` (#108).

  ```dart
  AssetPack(mapping: m, key: k, chunkSource: BundleMount(bundle: myBundle));
  ```

* **`AssetPack.releaseChunks()` is `AssetPack.release()`**, the name it
  overrides on `AssetMount`. A scene boundary now releases every mounted tier
  rather than the single installed pack, which is what stops a mounted DLC
  pack from holding its chunks for the life of the process (#108).

* **A manifest entry whose chunk file is absent throws a `StateError` naming
  the mount, not the bundle's `FlutterError`.** The chunk is read through
  `AssetPack.chunkSource` now, and a mount reports "I do not carry this" by
  returning null rather than by throwing, so the pack is the one left to say
  what went wrong. `verifyChunks` still records the failure per chunk; only
  the message and the exception type change. A *missing asset* — nothing
  mounted carries it and the app bundle has no such entry — still surfaces as
  the bundle's own `FlutterError`, unchanged (#108).

* **`ParamDescriptor.hasString(int maxBytes)` is now `hasFixedString`, and
  `hasString()` takes no capacity at all.** The unadorned name went to the
  kind you should reach for first: a string whose length nobody has to guess.
  Rename the call, or drop the argument and let the value size itself.

  ```dart
  name = descriptor.hasString();          // any length, kept in the record's tail
  code = descriptor.hasFixedString(2);    // two bytes reserved inline, every record
  ```

  `hasFixedString` behaves exactly as `hasString(n)` did, overflow error
  included, and is still the right answer where the bound is real — a
  two-letter country code, a fixed-width digest. Everywhere else it reserved
  its capacity in every record whether it was used or not, and refused a value
  a byte over it (#146).

* **`ParamLayouts` has one method where it had two.** `strideOf(index)` and
  `fieldCountOf(index)` are replaced by `layoutOf(index)`, which returns the
  `ParamLayout`. A record is no longer described by one number — it has a head
  stride, a field count, and, if it declares a variable-length field, a slot
  saying where its tail length is kept — and handing back the layout keeps
  those together instead of copying each one onto whatever declared it. Only
  something implementing `ParamLayouts` itself is affected; `CommandRegistry`
  and `good_net`'s registry are the two in this repo (#146).

* **`ParamBatch.append` takes the layout instead of a stride and a field
  count**: `append(index, layout)`. Same reason (#146).

* **`ParamDescriptor`'s integer and float declarations no longer take a
  default value.** `descriptor.hasInt32(100)` used to compile and then do
  nothing: `ParamLayout` never read the argument, and there was nowhere for it
  to go. A param record carries a written-mask, and reading a field nobody
  wrote throws instead of handing back a default — zero is a real value for
  every width here, so the engine reports the omission rather than inventing
  one. Drop the argument at the call site; nothing else changes. The
  same-named methods on `DataDescriptor` and `StateDescriptor` keep their
  defaults, which are read and do apply.

* **An animation coroutine is owned by the timeline it plays, not by the
  struct that started it.** `startAnimation` used to go through
  `startCoroutine`, so `stopAllCoroutines()` on a prefab took its animations
  down along with everything else that prefab had started. It no longer does.
  Stop animations with `stopAnimations(timeline)` instead, or `stopAnimation`
  for a single handle. The regrouping is what makes stopping by timeline
  possible at all: `stopAllOf` groups by owner, and the old owner grouped
  every animation one host had started, which is nobody's idea of a group.

* **`Query` and `SingleQuery` gained members.** They are exported, so a class
  outside the engine that `implements Query` no longer satisfies it: `run` and
  `groups` each take a trailing optional `Scene`, and `inScene` is new. Widen
  the two signatures and add `inScene`. Nothing that only *calls* a query is
  affected.

* **`Query.runQuery`, `Query.get`, `Query.tryGet` and `SingleQuery.component`
  are gone.** Walk a query with `groups()` or `run()` and read through the
  `Entity` those hand you (#155).

  ```dart
  // before
  query.runQuery(() { ... });

  // after - one component resolve per archetype, which is the point
  for (final group in query.groups()) {
    final transform = group.get<Transform2D>();
    for (final entity in group) {
      transform.transformOffsetX[entity] += 1;
    }
  }

  // or, where the walk stops early
  for (final entity in query.run()) {
    entity.get<Transform2D>().transformOffsetX[entity] += 1;
  }
  ```

  `runQuery` set an internal cursor that `get`/`tryGet` read through, and the
  callback took no argument, so there was no way to obtain the `Entity` every
  component field is indexed by. It could name the archetype's component and
  read no row data at all.

  `SingleQuery` itself stays, and so does `QueryDescriptor.has<T>()` that
  builds one: it is `query().withAll(T).build()` with the component named
  once, and `groups()`, `run()` and `inScene()` work on it as on any query.

* **`GameListener.disableAfterUncaught` takes the error and stack.** Both are
  optional positional, so a call site needs no change - but a class outside
  the engine that `implements GameListener` no longer satisfies the interface
  and has to widen its override to
  `disableAfterUncaught([Object? error, StackTrace? stack])`. Anything that
  extends `GameListenerBase`, which is every listener the engine ships, is
  unaffected.

* **`MousePosition` is now `CursorPosition`.** Rename the type and you are
  done: same fields, same one-instance-per-action contract, same
  `MouseBinding` producing it. A pointer position is the one input a finger
  can produce exactly as a mouse can, and calling the thing a mouse position
  would have made touch either lie about itself or need a second type for the
  same three numbers (#129).

  ```dart
  cursor = input.has<CursorPosition>(const MouseBinding());
  ```

  **`MouseBinding` keeps its name**, and that is the point of splitting the
  two: the binding says which device produced the position, the position says
  where the pointer is. So do `MousePickingSystem`, `MouseReceiver`,
  `MouseEvent` and `MouseListener` in `goo2d` - `onMouseEnter`, `onMouseHover`
  and `onMouseExit` have no meaning for a finger, which is either down on you
  or absent, so renaming those is a design question and not a spelling one.

* **`InputBinding<T>` gains a required `T combine(T a, T b)`.** Any binding
  written outside this repo stops compiling until it implements one (#215).

  ```dart
  // on your own InputBinding<double>
  @override
  double combine(double a, double b) => b.abs() > a.abs() ? b : a;
  ```

  **What to write.** `combine` answers "what does the action read when two
  sources are both producing something", for the one value type your binding
  is over: OR for a `bool`, componentwise sum clamped to -1..1 for a
  `Vector2`, whichever is further from rest for a `double`. For a reference
  type it must write into `a` and return it rather than build a new value -
  it is called per composite per fixed tick, and the no-allocation rule
  applies to it exactly as it does to `resolve`. Copy the body from whichever
  shipped binding shares your `T`. A binding whose value can never sensibly
  merge - the way a cursor position cannot - throws, as `MouseBinding` does.

  **Why it is required and not defaulted.** A default returning `b` would
  keep every third-party binding compiling and be wrong for all of them: an
  action composing two of your bindings would silently read only the last one.
  A compile error you fix once is better than a merge rule nobody chose.

  **Why it is on the binding at all.** `CompositeBinding<T>` - see Added -
  cannot switch on `T` without knowing every value type a game will ever bind.
  Every source in a composite shares `T` by construction, so any one of them
  can supply the rule, and the composite folds with its primary's.

  Nothing inside the repo broke: `TriggerBinding`, `Vec2Binding`,
  `AxisBinding`, `StickBinding` and `MouseBinding` are the only
  implementations, and they all ship one.

* **`InputState.byteLength` is now `InputState.byteLengthFor(maxContacts)`.**
  The raw device block ends in a contact table - see Added - whose length
  comes off `Game.maxPointerContacts`, so the block no longer has one size
  for every game and a static getter could not answer for it. The static is
  gone; `byteLengthFor` takes the count, and an `InputState` instance still
  answers `byteLength` for its own block (#129).

  This is engine plumbing: `InputState`'s constructor and `InputDevice`'s are
  both `@internal`, and nothing but the registry that allocates the buffer
  ever asked how long it was.

* **`MemoryPool.adoptPage` is gone, and with it every way to hold a page this
  isolate did not allocate** (#168).

  It built a read-only `MemoryPage` over addresses another isolate published,
  so a second copy of the engine could resolve an `Entity` into the writer's
  memory. Nothing announces page addresses, and no copy but the simulating one
  holds archetypes to resolve against, so the method had no caller in any
  package.

  `ArchetypeStorage.adoptPage`, the half that appended such a page to an
  archetype's list, goes with it. It is `@internal` and was never public API.

  Every `MemoryPage` now owns its own triple buffer. `MemoryPage.dispose`
  frees it in every case, and `MemoryPage.allocate` has no borrowed-page
  branch to reject.

### Added

* **A dot shorthand for every binding, so an action names its source without
  naming its type** (#221).

  `InputBinding` now carries one static per concrete binding. Everywhere a
  binding is expected the context type is an `InputBinding<T>` or an
  `InputBinding<T>?` - `Input.of`, `Input.binding`, `InputDescriptor.has`, and
  a composite's own sources - so a dot shorthand resolves there, and the
  action's value type is inferred from the factory's return type:

  ```dart
  final fire = Input.of(.trigger(.spacebar));                    // Input<bool>
  final move = Input.of(.vec2(up: .w, down: .s, left: .a, right: .d));
  final attack = Input.of(
    .composite(.trigger(.leftMouseButton), .trigger(.spacebar)),
  );

  fire.binding = .trigger(.enter);
  ```

  | shorthand | binding |
  |---|---|
  | `.trigger(key)` | `TriggerBinding` |
  | `.vec2(up:, down:, left:, right:)` | `Vec2Binding` |
  | `.axis(axis)` | `AxisBinding` |
  | `.stick(x:, y:)` | `StickBinding` |
  | `.mouse` | `MouseBinding` |
  | `.contact` | `ContactBinding` |
  | `.composite(primary, secondary, [...])` | `CompositeBinding` |
  | `.compositeFromList(sources)` | `CompositeBinding.fromList` |

  Each is its constructor and nothing more - no defaults, no validation, no
  second way to spell an argument - so there is nothing to keep in step.

  Nothing is removed and no call site has to change. The one thing the
  shorthand cannot do is be `const`: a static method call is not a constant
  expression, so a `static const` table of bindings for a rebinding screen
  still names the concrete class, which is also where `copyWith` and
  `fromJson` live. The cost of the short form is one small object per declared
  action at boot, and nothing per tick.

  `.mouse` and `.contact` take no arguments, so they are `const` fields rather
  than methods and every reference is the same instance.

* **Per-bus audio levels, and a voice budget with a stated stealing policy**
  (#17).

  `AudioBus` carries five buses and each one carries a level, starting at 1.0.
  `AudioMixer.setLevel` writes one and applies it to the voices already
  sounding on that bus, so a slider moved mid-game moves the sound already
  playing; `levelOf` reads one back. `AudioBus.master` multiplies the other
  four, so zero there is a global mute, and a voice played on `master` itself
  is scaled by the master level once.

  ```dart
  state.audio.setLevel(AudioBus.music, 0.4);
  state.audio.setLevel(AudioBus.master, 0.0);   // mute everything
  final voice = state.audio.play(clip, AudioBus.effects);
  ```

  A level change lands as a step with no ramp, and costs one backend call per
  started voice on the bus that moved. Nothing is scaled by a bus twice, and
  no native mixing bus is involved.

* **`Game.maxVoicesPerBus` caps each bus, and a full bus stops its oldest
  voice** (#17). Sixteen by default, overridable like `Game.pageSize`, and
  read once when `GameState.audio` builds the mixer. Below one is refused.

  ```dart
  @override
  int get maxVoicesPerBus => 8;
  ```

  A bus at its budget does not refuse the next sound: `play` stops the voice
  that started first on that bus, releases its asset claim, and hands the slot
  to the new one. `AudioMixer.oldestVoiceOn` names the voice that goes next
  and `voiceCountOn` says how close a bus is. Dropping the newest is the wrong
  answer, since the newest sound is the one the player just caused; stealing
  the quietest has nothing to sort by, since `play` takes no per-voice volume
  and every voice on a bus sounds at that bus's level.

  Counting per bus is what keeps music out of an effects burst's way without a
  protected flag on it. The count is the engine's: `flutter_soloud` 4.1.7's
  `setMaxActiveVoiceCount` caps how many voices are *mixed* per buffer and not
  how many may be alive, so a cap of 4 reads back as 4 and then permits 59
  concurrent voices.

  `AudioMixer.liveVoiceCount` is unchanged and still counts every bus.

* **An on-screen analog stick, as three widgets.** A finger dragging one
  produces a continuous vector a game reads through a `StickBinding`, and
  letting go returns it to rest (#191).

  ```dart
  Stack(
    children: [
      GameView(camera: camera),
      Positioned(
        left: 0, top: 0, bottom: 0, width: 160,
        child: JoystickArea(game: game),
      ),
    ],
  )
  ```

  `JoystickArea` reads a finger anywhere in its box and centres the stick
  where the finger landed, touchpad style. `JoystickControl` reads the same
  thing from a stick fixed to its own box. `Joystick` is the visual with no
  input attached, for drawing a value already in hand. All three take a
  `track` and a `thumb` widget and paint a default disc and ring for whichever
  is left null.

  A widget names the two `VirtualAxis` values it writes and a binding names the
  two it reads, so there is no stick number to keep in step and two sticks are
  two axis pairs. The value is -1..1 with 0 at rest and +1 up, matching what
  `StickBinding` delivers, and it is proportional: half the travel reads a
  half. Past full travel it clamps to the circle, so a diagonal at the edge has
  a magnitude of 1.

  All three return the stick to rest on a cancelled pointer as well as on a
  lift, and on going away with a finger still down. A notification or an
  incoming call ends a pointer with no up event behind it, and a stick that
  waited for a lift would hold its direction until the app was restarted.

  The thumb's position drives a repaint through a `Listenable`, so a drag
  rebuilds no widgets.

* **Touch input.** A finger, a stylus, or a mouse with a button held is a
  **contact**, and `ContactBinding` reads all of them at once. The engine
  built for Android and iOS and could not read a finger (#129).

  ```dart
  contacts = descriptor.has<PointerContacts>(const ContactBinding());

  // in a fixed step
  final pressing = contacts.value;
  for (var i = 0; i < pressing.count; i++) {
    final contact = pressing[i];
    switch (contact.phase) {
      case PointerPhase.began:
        startDrag(contact.id, contact.viewSpace);
      case PointerPhase.held:
        moveDrag(contact.id, contact.viewSpace);
      case PointerPhase.ended:
      case PointerPhase.cancelled:
        endDrag(contact.id);
    }
  }
  ```

  Each contact carries an `id` stable for its whole life, a `kind`, and its
  position in window and view coordinates. The list is ordered by `id`, which
  is the order the contacts started, so `pressing[0]` is the oldest one still
  down. Both the list and the contacts in it are scratch the action owns and
  refills each tick, the same contract `Input<Vector2>.value` has.

  **`cancelled` is a phase of its own.** A notification, an incoming call, the
  app losing focus, or a widget taking the gesture all end a contact with no
  lift behind it. A game that only ends a drag on `ended` leaves the player
  steering into a wall after a phone call, and testing by hand on a desk never
  produces it. `InputDevice.releaseAll` - which `GameView` already called when
  the app stops being focused and when the last view goes away - now cancels
  every live contact for the same reason it clears held keys.

  **Raw contacts, not gestures.** Two fingers into one `GestureDetector`'s pan
  callbacks arrive as a single drag, because `DragGestureRecognizer` is
  mono-drag by construction, so a twin-stick scheme cannot be built on the
  gesture layer at all. Contacts come off the `Listener` `GameView` already
  had. `GameView` still does not claim the gesture arena, so a `GameView`
  inside a `ListView` reads a drag the list is also scrolling on; put
  interactive widgets in a `Stack` above the view, not inside it.

  Contacts cross the boundary in the raw input block, beside the key bits and
  the axes, so a tick's contacts are as coherent as the rest of its input.
  `Game.maxPointerContacts` sizes the table - ten by default, every finger on
  two hands - and a press arriving while every slot is live is dropped whole.
  It is read once, while the game is constructed, because both isolate copies
  index the table by offsets computed from it.

  A press and a lift that both land between two fixed ticks are reported once,
  with `ended`: the block is a latest-value snapshot, so the `began` tick
  never existed to be read. Fire a tap on the end, which is when a real tap
  gesture fires anyway.

  `InputDevice.pressContact`, `moveContact`, `releaseContact` and
  `cancelContact` are the write end, so a replay, a bot or a test drives
  fingers without fabricating a Flutter `PointerEvent` - the same reason
  `movePointer` exists for the cursor.

  `Game.viewOfContact` says which `CameraView` a contact landed in. That is
  per contact and not per game because two fingers can be in two views at
  once, which one cursor never is.

  A touch does **not** move `CursorPosition` and does not press a mouse
  button: a finger has no buttons and moves no cursor, and having one do so
  would teleport the cursor a mouse game aims with.

* **Audio plays.** `AudioClip` has shipped through the whole asset pipeline
  since 0.2.0 with nothing that could make a sound out of it. There is now a
  mixer: `state.audio.play(clip, AudioBus.master)` returns a `Voice`, and
  `voice.stop()` stops it (#17).

  ```dart
  class MyGame extends Game {
    @override
    AudioBackend createAudioBackend() => SoLoudAudioBackend();
  }

  // anywhere on the game isolate
  final music = state.audio.play(scene.theme, AudioBus.master);
  ```

  The mixer lives on the **game isolate** and calls the native engine
  directly. Nothing crosses the boundary to start a sound, and nothing has to:
  a `play` costs a couple of microseconds, less than a port send, and mixing
  runs on the engine's own thread - so an overrunning tick, or a game paused
  with its timer stopped, does not perturb playback.

  `good` ships no engine. `AudioBackend` is the seam and
  `package:good_audio_soloud` is the implementation, because a native audio
  engine is a plugin with a platform build and a game that ships no sound
  should not compile one. A game that declares no backend allocates nothing
  and opens no device; one that declares a backend but plays nothing does not
  either, because the device opens on the first `play`.

  Two things are in this first slice that look deferrable and are not.

  **The bus parameter.** Players treat music, effects, voice and interface as
  four separate things, and a single master volume does not decompose into
  four later without touching every call site that ever played a sound. So
  `play` takes a bus now, while `AudioBus` has one member and its level is
  fixed at 1.0.

  **The asset claim.** A playing voice takes a claim on its clip, exactly as a
  loaded scene takes one on each asset it declares - so a scene can unload
  while its music keeps playing, and the bytes survive because the voice is
  still holding them. Without it a track cannot outlive the scene that started
  it, and since there is no game-level `describeAssets`, every clip is declared
  by some scene and every scene eventually unloads.

  Deferred, and named so nobody builds on the assumption that they are here:
  looping and authored loop points, per-bus levels, fades, a voice cap and a
  stealing policy, a settings surface, and web. The cap is worth its own line
  because it looks like something a backend supplies and does not:
  flutter_soloud 4.1.7's `setMaxActiveVoiceCount(4)` reports back 4 and then
  permits 59 concurrent voices, measured on its supported public API, so the
  engine will have to count one itself.

* **`WorldCensus` counts what the game isolate holds.** Loaded scenes,
  registered archetypes and how many entities are in each, and the declared
  systems with their enabled bits. Everything in it was already known on the
  game isolate and reachable from nowhere else; what was missing was a way to
  ask (#122).

  ```dart
  // in GameState.describeCommands
  descriptor.hasReadOnlySupplier(game.census, () => WorldCensus.of(this).encode());

  // on main, whether or not the game is paused
  final census = WorldCensus.decode(await game.census());
  ```

  A census reads and answers, so it goes on the read-only lane above and
  therefore works on a stopped simulation - which is when a world is usually
  worth looking at. `encode`/`decode` is the crossing: one `hasBytes` blob,
  345 bytes for four scenes, six archetypes and eight systems, against the
  64 KiB a command ring carries.

  **Nothing takes one on its own.** There is no per-frame hook and no buffer
  that fills whether or not anyone reads it, so a running game pays nothing.
  One census costs O(archetypes + pages + scene slots + systems) and **not**
  O(entities): a page reports its rows as arithmetic over its bump cursor and
  its free set, which is what the new `MemoryPage.liveRowCount` is. Measured
  under `flutter test`, so JIT: 0.6 us at zero entities, 0.9 us at 100,000,
  and 4.9 us for a world of four scenes, six archetypes, 24 pages and 120,000
  entities. Counting the same rows by walking them is 0.01 us, 540 us and
  rising.

  **Type names are for reading, and nothing resolves by one.** An archetype is
  named by `archetypeId`, a scene by `slot` and a system by `index`; the
  `runtimeType` strings ride along so a person can tell one from another, and
  a build that minifies them will show minified ones. A component type's name
  is still not available at runtime at all.

  Taking a census on the main isolate's copy of a `GameState` throws. That
  copy registers no archetypes, loads no scenes and holds no systems, so a
  census from there would report an empty world for a reason that has nothing
  to do with the world.

* **`hasReadOnlyHandler` and `hasReadOnlySupplier` answer a game whose fixed
  tick is stopped.** A tick-delivered command is pumped from
  `GameState.runFixedStep`, so a paused game - or one at a time scale of zero -
  queued it and answered nothing until the tick came back. A pause menu asking
  the simulation for a number, or an inspector reading a world that is
  deliberately standing still, waited out the pause with no error and no
  timeout (#165).

  ```dart
  // in GameState.describeCommands
  descriptor.hasReadOnlySupplier(inspect, () => _summarise());
  ```

  The batch rides the same command ring a tick-delivered one does, and keeps
  the same reply leg - so `await` completes when the handler has run and its
  answer is back, which is what separates this from `hasControlSink`. What
  changes is where it is drained: a second inbox, emptied once per frame from
  `GameState.advance`, which runs on a frame that afforded no fixed step.

  **Two inboxes and not one.** A single arrival-ordered queue drained per frame
  would run tick-delivered handlers with no tick window open, which is the
  hazard that makes `Game.stop` a control message rather than a command. The
  price of the split is that there is no ordering *between* the lanes, only
  within each - the same trade receipt delivery already makes.

  **Read-only is a promise the caller makes, and the engine holds them to
  it.** Nothing in Dart makes a closure read-only, so the lane is declared
  around the dispatch instead. A component write, adding or destroying an
  entity, loading or unloading a scene and a `StateChannel` write each throw a
  `StateError` from here, in every build - see Fixed, #245. `hasHandler` is the
  one that may write.

  `hasReadOnlySink` and `hasReadOnlySignal` exist and always throw, the way
  `hasControlHandler` does: a handler that promises not to write and has no
  answer to send back has no effect left to have.

  Not covered: a game hidden under `pauseWhenHidden` calls `stopTimer()`, so
  nothing calls `advance` and there is no frame to drain on. Answering that
  one needs a reply leg on the control port, which is deferred.

* **`Channel.*` declares a published state channel on the field that holds
  it.** A `Game` is framework-built as of the change above, so the state
  descriptor is open while its fields initialise (#91).

  ```dart
  class MyGame extends Game {
    final score = Channel.int32();
    final health = Channel.float64(100);
    final alive = Channel.boolean(true);
  }
  ```

  One static per `StateDescriptor` method, taking the same initial value.
  `Channel` and not `State`: `State` is `package:flutter/material.dart`'s, and
  every file putting a `GameView` in a layout imports that. The name pairs
  with `StateChannel`, which is what comes back.

  The initialiser must be eager - `late final` runs on first read, long after
  the descriptor sealed and the storage was allocated, and throws out of
  `DeclarationContext.channels` rather than declaring anything.

  A `Game` and nothing else, which is not new: a channel's storage is
  allocated on main before the spawn and its identity across the boundary is
  its index in that one pass. `describeState` still works, and both forms
  compose - fields first, hook second, one numbering.

  **Declaration and resolution are two steps now.** `Channel.int32()` makes a
  channel with no index, no run and no storage and appends it to a list, which
  is all it does and all it can fail at; `Game.start` numbers the collected
  set and binds it to the run once both sources have spoken, and
  `_bootAllocate` allocates a step after that, where it always did. The
  circularity that made this necessary is that a channel wants a `GameRuntime`
  that wants the `Game` whose own fields are still initialising.

* **`Input.of` now works on a `Game` field.** The static landed for a
  `GameSystem` above; a `Game` was excluded because it was constructed by the
  caller, and `Game.start` taking a constructor is what lifts that (#91).

  ```dart
  class MyGame extends Game {
    final pause = Input.of(const TriggerBinding(.escape));
  }
  ```

  `InputDescriptor.hasDefaultValue` still has no field form anywhere - it
  hands nothing back, so there is no field to put it on - and
  `Game.describeInputs` survives for it, on the framework's own `Game` as much
  as on yours. Both forms compose on one game: fields first, hook second, and
  a type-level default the hook registers still reaches an action a field
  declared, because defaults are matched at `seal()`.

* **`Input.of` declares an input action on the field that holds it.** A
  `GameSystem` is framework-built as of the change above, so the registry is
  open while its fields initialise (#91).

  ```dart
  class PlayerSystem extends GameSystem with FixedTickable {
    final fire = Input.of(const TriggerBinding(.spacebar));
    final movement = Input.of(
      const Vec2Binding(up: .w, down: .s, left: .a, right: .d),
    );
  }
  ```

  `V` comes off the binding. An unbound action has nothing to infer from and
  says so: `Input.of<bool>()`. The initialiser must be eager - `late final`
  runs on first read, long after boot sealed the registry, and throws out of
  `DeclarationContext.inputs` rather than declaring anything.

  A system only. A `Game` is constructed by the caller and its
  `describeInputs` runs on both isolate copies, so a `Game`'s actions stay in
  the hook. `InputDescriptor.hasDefaultValue` has no field form anywhere - it
  hands nothing back, so there is no field to put it on - and `describeInputs`
  survives for it. Both forms compose on one system: fields first, hook
  second.

* **`Event.of` and `Event.signal` now work on a `GameSystem` field.** Both
  statics landed for a `GameState` and an `EntityStruct` below; a system was
  excluded because it was constructed by the caller, and the change above is
  what removes that (#91).

  `GameSystem`'s own `mountEvent` and `unmountEvent` did not move with it, the
  way `EntityStruct`'s pair did not: a base-class pair is inherited by every
  system however it was built, and a system handed over pre-built through a
  closure declares into whatever binder happens to be open above it. The
  `describeEvents` entry above is where both pairs ended up.

* **An event is declared on the field that holds it.** `Event.of` carries a
  payload and `Event.signal` carries nothing, so a `GameState` or an
  `EntityStruct` says what it dispatches where the reader is already
  looking (#91).

  ```dart
  // before
  class ArenaState extends GameState<ArenaGame> {
    late final EventDispatcher<WaveListener, int> waveCleared;

    @override
    void describeEvents(EventDescriptor descriptor) {
      super.describeEvents(descriptor);
      waveCleared = descriptor.has(
        (listener, wave) => listener.onWaveCleared(wave),
      );
    }
  }

  // after
  class ArenaState extends GameState<ArenaGame> {
    final waveCleared = Event.of<WaveListener, int>(
      (listener, wave) => listener.onWaveCleared(wave),
    );
  }
  ```

  Write the type arguments. `descriptor.has(...)` reads them off the field it
  is assigned to and an initialiser has no such context, so `L` and `E` are
  stated at the call — which is what the separate `late final` line used to
  say.

  Those two owners and no others, because those two are the ones the framework
  builds: `Game.createState` and `descriptor.has(Mote.new)`. A `SceneStruct`
  is a field of the state (`final level = MainScene();`) and a `GameSystem` is
  declared from an instance (`descriptor.has(SpinSystem())`), so nothing is
  open while their fields initialise and both keep declaring in
  `describeEvents`. The struct half has a hole worth knowing about:
  `SceneDescriptor.has` takes a closure, and `descriptor.has(() => builtEarlier)`
  hands back an object nothing was open around. Build the prefab inside the
  closure, or pass the constructor.

  `describeEvents` is not retired. An owner may declare through either or
  both; the fields' dispatchers are created during the constructor and the
  hook's straight after, and one collect pass fills them all. Which order they
  were created in does not reach delivery — a listener's position in a
  dispatcher is the order `collectListeners` offered it.

  The initialiser has to be eager. `late final waveCleared = Event.of(...)`
  runs on the first read, long after the collect pass: the dispatcher would
  exist, hold an empty list, and deliver to nobody, silently and forever. It
  throws instead.

  `EventBinder.bind` now refuses a second pass over the same owner. The
  `late final` dispatchers this replaces threw when assigned twice; a `final`
  field would not have noticed, and every listener would have received every
  event twice.

* **A command parameter is declared on the field that holds it.** `Param` has
  one static per `ParamDescriptor` method — `uint1` through `float64`,
  `entity`, `string`, `fixedString`, `bytes`, `fixedBytes` — so a command says
  what it carries where the reader is already looking (#91).

  ```dart
  // before
  class SpawnEnemy extends SinkCommand<int> {
    late final ParamPointer<int> flags;

    @override
    void describeParams(ParamDescriptor descriptor) {
      flags = descriptor.hasUint2();
    }
  }

  // after
  class SpawnEnemy extends SinkCommand<int> {
    final flags = Param.uint2();
  }
  ```

  `describeParams` is not retired, and it is no longer abstract: a command
  declaring only through fields has nothing to put in it. Override it for a
  declaration a field initialiser cannot reach. The two forms compose — the
  fields declare during the constructor and the hook runs straight after, so
  the fields take the lower bit offsets — and both reach the same record,
  which is what `good_net`'s handshake hash is now tested against.

  The initialiser has to be eager. A `ParamLayout` is a bit cursor, so
  `late final flags = Param.uint2()` would take its offset from whatever order
  something happened to read the fields in, and two builds that read them
  differently would lay the record out differently while still parsing each
  other's bytes. It throws instead: the layout the framework opens is closed
  by the time a lazy initialiser runs.

* **A query is declared on the field that holds it.** `Query.all`,
  `Query.has<T>` and `Query.where` build a query with no descriptor in hand,
  so a system says what it walks where the reader is already looking (#91).

  ```dart
  // before
  class SwirlSystem extends GameSystem with FixedTickable {
    late final Query motes;

    @override
    void describeQuery(QueryDescriptor descriptor) {
      super.describeQuery(descriptor);
      motes = descriptor.query().withAll(Transform2D, Mote).build();
    }
  }

  // after
  class SwirlSystem extends GameSystem with FixedTickable {
    final motes = Query.all(Transform2D, Mote);
  }
  ```

  `Query.where()` opens the same `QueryBuilder` `descriptor.query()` hands
  out, for the constraints `all` does not cover:

  ```dart
  final roots = Query.where()
      .withAll(WorldTransform2D, Transform2D)
      .withOptional(Child)
      .build();
  ```

  The initialiser has to be eager. `late final motes = Query.all(...)`
  compiles and runs on the first read instead of at construction, which is the
  access-order hazard the engine's declaration rules exist to keep out.

  Nothing here needs a live declaration pass, and none of it retires
  `describeQuery`: a query holds masks, and `groups()` resolves archetypes on
  the first walk and rebuilds whenever the registry grows, so one built during
  a system's construction picks up every archetype a scene registers
  afterwards. The hook still works and both forms coexist.

* **An ordered asset mount table: later shadows earlier.** `AssetMount` is one
  tier — bytes named by a logical path, or null when that tier does not carry
  it — and `AssetMounts` is the process's ordered list of them. A DLC
  directory, a mod folder, a downloaded patch and the project's own source
  tree are all expressible, and game code resolving `BundleSource('x.png')`
  cannot tell which tier answered (#108).

  ```dart
  import 'package:good/io.dart';

  AssetMounts.mount(AssetPack(mapping: assetMapping, key: assetKeyMaterial));
  AssetMounts.mount(DirectoryMount('C:/games/mygame/dlc'));  // shadows the pack
  ```

  Three implementations ship: `AssetPack` itself, `BundleMount` for a Flutter
  `AssetBundle`, and `DirectoryMount` for a folder on disk. The last one lives
  in **`package:good/io.dart`**, a second entry point that exists so
  `package:good/good.dart` stays free of `dart:io`.

  The table has a floor it does not contain: when no mount carries a path,
  `BundleSource` falls back to the app's own bundle. That is not a hedge, it
  is Android — an asset there is a compressed zip entry with no filesystem
  path, so what shipped inside the app is reachable through the bundle and
  through nothing else. It can be shadowed; it cannot be unmounted.

  `AssetSource.check` walks the same table. A mount that does not carry a path
  says so and the walk continues; `AssetAvailability.unknown` — a pack whose
  manifest does not list the asset — is remembered rather than returned, so a
  higher tier that really does carry it still answers, and the finding is
  reported only when nothing does.

* **A record field can hold a string or a list whose length is not declared up
  front.** `hasString()` and `hasBytes()` size themselves from what is written
  into them; `hasFixedString(n)` and `hasFixedBytes(n)` are the
  capacity-reserving pair beside them. Commands and `good_net` messages share
  the record layer, so both gained all four at once (#146).

  A record keeps its fixed head — every pointer still resolves to a fixed
  offset in it, so nothing about the `XPointer` pattern changes. A
  variable-length field puts an offset and a length in that head and its bytes
  in a **tail** behind it, and the record carries its own total tail length so
  a receiver can still walk a batch forwards. A declaration with no
  variable-length field is laid out exactly as before, tail slot and all
  absent.

  Two things to know before reaching for one. **A variable-length field is
  written once per record** — the tail is filled by appending, so a second
  value would have to move every field behind it, and a second write throws
  rather than rearranging the record silently. And **reading a `hasBytes`
  field hands back a view onto the batch's own bytes**, not a copy, which is
  what keeps a per-tick network message off the allocator: read what you need
  inside the call rather than keeping the list.

* **A command batch too big for the command ring is refused at `send()`.**
  Nothing is truncated and nothing is silently dropped. This is the bound a
  length-free field has instead of a declared capacity, so it now says so:
  the error names the batch's size, the ring's maximum, and
  `Game.commandBufferBytes`. It is deliberately a different error from "the
  ring is full", which is answered by waiting and this one never is.
  `RingBuffer.maxPayloadBytes` is the number behind it (#146).

* **A running animation can be stopped.** `stopAnimation(handle)` takes the
  `CoroutineFuture` that `startAnimation` returned and stops that one
  playback. `stopAnimations(timeline)` stops every coroutine playing that
  timeline - on a timeline shared by forty entities, that is all forty, which
  is the point of the grouping and worth knowing before reaching for it.

  Both complete the handle **normally**, not with an error: cancelling
  something is not a failure, and a caller awaiting the handle carries on. A
  caller that has to tell "it finished" from "someone stopped it" cannot do
  it from the handle.

  A stopped animation leaves the bound tracks holding whatever the last tick
  wrote - stop it mid-fade and the sprite stays half faded. Nothing is reset
  or restored.

* **A query can be scoped to one loaded scene.** `Query.run` and
  `Query.groups` take an optional `Scene`; `Query.inScene(scene)` binds one
  once, for a system that always works in the same scene; and
  `QueryGroup.inScene(scene)` narrows a single archetype's group. The scope
  skips at the *page* level - a `MemoryPage` records the scene it was
  allocated for - so another scene's rows are rejected without being
  touched, where the per-row `entity.sceneSlot` test this replaces pays for
  every row it throws away. Nothing changes for a call with no scene.

  A scope naming a scene that is no longer loaded **throws**, and it throws
  twice over: when the scope is applied, and again when a walk starts, since a
  `QueryGroup` and a lazy `run()` both outlive the call that made them. The
  alternative - iterating empty - reads as a system that has quietly stopped
  working, a long way from the stale handle that caused it. A `Scene` carries
  a generation counter, so a handle whose slot has since been reused by a
  different scene is refused rather than answered for.

* **A system switched off by an uncaught throw now says so in release.** The
  guard from 0.2.0 reported through `assert`, which a release build strips, so
  a shipped game went on ticking with a system quietly disabled and nothing
  said anywhere. The engine now declares a fire-and-forget command in
  `Game.describeCommands` carrying the system's name, the error and a
  truncated stack from the game isolate to the main one.

  `Game.onSystemDisabled(systemName, error, stackTrace)` is where it arrives.
  The default hands it to `FlutterError.reportError`; override it to send the
  report to a crash reporter or an in-game console instead, and do not call
  `super` unless you want both. Debug is unchanged: the assert still fires and
  is still the loud answer.

  The three strings are cut to fit fixed-width fields - 256, 1024 and 2048
  bytes - on a character boundary, and a report that cannot be sent at all is
  dropped rather than allowed to end the tick that was already going wrong.

* **A batch can be told what its carrier will take, and refuse a record over
  it at the write.** `ParamBatch(maxRecordBytes: n)` bounds one record —
  header, mask, head and tail — and a write that would carry a record past it
  throws instead of growing, naming the declaration, the size and the bound.
  `ParamBatch.startAt(i)` says where each record begins, which is what lets a
  carrier cut a long batch at record boundaries instead of refusing it (#158).

  Nothing changes for a batch built without it: `maxRecordBytes` defaults to
  `ParamBatch.unbounded`, and the command ring still checks the whole batch at
  `CommandTransport.send` as it did.

  **Why.** A `hasString()` or `hasBytes()` field has no capacity of its own, so
  the only bound left is the carrier's — and until this the record layer had no
  way to be told one. The refusal has to happen at the write because that is
  the only place the value that was too big is still in hand; a check at the
  send says a batch is too long and cannot say which of forty records made it
  so. A refused record is taken back off the batch when it is the last one, so
  that everything already queued is still sendable and no half-written record
  goes out to fail on the reading side.

* **`InputDevice.releaseAll()`** puts every key, mouse button and gamepad bit
  up in one write, and every analog axis back to rest. `GameView` calls it for
  you when the app is hidden and when the last view showing a game goes away;
  a host driving input itself - a replay, a bot, a test - can call it to reset
  the block between runs. The pointer's *position* is left alone, because
  nobody is holding the cursor down (#160).

* **An analog path: `InputAxis`, `StickBinding` and `AxisBinding`.** A stick
  half-pushed now reads about half. Until this, a stick reached a game as four
  thresholded bits composed by a `Vec2Binding`, so pushing it a third of the
  way and slamming it produced the same vector - which is what
  `input_key.dart` had been saying about itself, and what every real gamepad
  was losing (#192).

  ```dart
  move  = input.has<Vector2>(
    const StickBinding(x: .padLeftStickX, y: .padLeftStickY),
  );
  aim   = input.has<Vector2>(
    StickBinding(x: InputAxis.padRightStickX(2), y: InputAxis.padRightStickY(2)),
  );
  brake = input.has<double>(const AxisBinding(.padLeftTrigger), 0.0);
  ```

  `InputAxis` is a second vocabulary beside `InputKey` - a key is a bit in the
  raw block and an axis is a `float32` in it - carrying the four stick axes and
  two triggers per gamepad slot, plus four axes for on-screen controls that
  nothing in the engine writes. Slots work as they do for keys, `call` and all,
  and slot 0 is "any connected pad": for a bit that is the OR of every seat, and
  for an axis it is whichever seat is furthest from rest.

  Values run -1..1 with 0 at rest (0..1 for a trigger), `+1` up and `+1` right
  to match `Vec2Binding` and the world, and they are **unshaped** - no deadzone,
  no curve, no normalization. `GamepadCollector` writes the axes and the
  thresholded bits from the same event, so both readings of one physical stick
  are live at once and a game picks by picking a binding.

  Nothing existing changes. `padLeftStickUp` and the rest of the `*Stick*` keys
  are still there and still mean what they meant, `GamepadCollector.stickDeadzone`
  still shapes those bits and only those, and `Vec2Binding` is untouched.
  Whether the thresholded keys should eventually go, and who should own the
  deadzone, are open questions on #192 that this deliberately does not answer.

  Two things to know. Both bindings count as *actuated* whenever the value is
  off rest at all - there is no threshold in them, so a pad whose stick rests a
  hair off centre reads as held forever and `pressed`/`released` are not the
  edge to use there. And `double` has no type-level default, so an action bound
  with `AxisBinding` needs one of its own, as above.

  This is also what #51 asked for: an analog input declared and read as a
  `double`, allocating nothing per tick.

* **`InputDevice.setVirtualAxis`**, for an on-screen control to write an axis,
  and **`InputDevice.setGamepadAxis`** for a pad. A widget drawing a joystick
  writes `InputAxis.virtualLeftStickX` and a binding reading it cannot tell a
  thumb from a thumbstick, which is what lets a touch build and a controller
  build share one declaration (#192).


* **`CompositeBinding` binds one action to several sources.** Space *or* left
  click, the left stick *or* WASD, WASD *or* the arrow keys - one action, one
  value, one pair of edges (#215).

  ```dart
  attack = input.has<bool>(
    CompositeBinding(
      const TriggerBinding(.spacebar),
      const TriggerBinding(.leftMouseButton),
    ),
  );

  move = input.has<Vector2>(
    CompositeBinding(
      const StickBinding(x: .padLeftStickX, y: .padLeftStickY),
      const Vec2Binding(up: .w, down: .s, left: .a, right: .d),
    ),
  );
  ```

  Every source is an `InputBinding<T>` of the same `T`, so a composite is one
  binding of that type and `has<T>` is unchanged. Two to ten sources
  positionally, or `CompositeBinding.fromList` when the count is decided at
  run time - a rebinding screen rebuilding an action from what the player
  chose. The positional form is sugar over `fromList`; there is one storage
  shape.

  **The edges come out right, which is the point.** `isActuated` is "any
  source is actuated" and the action derives its edges from that one bit, so
  pressing the second source while the first is held does not re-fire
  `wasPressedThisFrame` and the release fires once, when the last source goes
  up. Declaring two actions and `||`-ing `wasPressedThisFrame` - what a game
  writes today - swings twice for one intended attack.

  **Values merge, they do not take precedence.** `resolve` folds the sources
  through `InputBinding.combine`. Precedence reads straight off the
  `primary`/`secondary` naming and loses the case this was asked for: hold `w`
  and then press `arrowRight` and the WASD source is still actuated, so it
  still supplies `(0, 1)` and the arrow does nothing. Summing gives `(1, 1)`,
  and since `Vec2Binding` does not normalise, summing two of them is exactly
  the per-direction union - `w`+`arrowUp` is `(0, 1)` and not `(0, 2)`,
  `a`+`arrowRight` cancels to `(0, 0)`. A stick at `(0.5, 0)` with `w` held
  reads `(0.5, 1)`, which respects both devices instead of discarding one.

  **It is the one binding that is not `const`.** Every source past the first
  needs somewhere to resolve into that is not the action's own storage, and
  the constructor makes those with `createStorage` - one per extra source, at
  declare time. Resolution allocates nothing. The sources themselves are still
  `const` values, which is where `const` mattered.

  **`MouseBinding` is not a source.** A device has one cursor, so "the pointer
  is at either of two places" is not a position. The constructor asserts
  against it, the wire format has no tag for it, and `MouseBinding.combine`
  throws. Mouse *buttons* are ordinary `TriggerBinding`s and compose freely -
  a composite of a key and a mouse button is one action with one edge.

  **Serialization tags each child, and only here.** `toJson` writes
  `{'kind': ..., 'binding': ...}` around every source and `fromJson`
  dispatches on the tag, the way `InputKey.fromJson` already does. The other
  five bindings' `toJson` output is exactly what it always was, so the
  "no binding registry and no framework-owned save format" line in
  `InputBinding`'s doc still holds for every one of them: a composite is the
  case that argument does not cover, because its children are heterogeneous by
  design and a restore site cannot know them statically. `T` is written at the
  call site - `CompositeBinding.fromJson<bool>(saved)` - and a child that
  decodes to the wrong value type is a `FormatException` naming both.

  Composites nest, so a saved composite of composites round-trips too.

### Fixed

* **The boot passes no longer claim `describeQuery` resolves against
  registered archetypes.** Five source comments and a paragraph of the scene
  guide gave that as the reason `describeScenes` has to run before
  `describeSystems`. The query pass reads `ComponentTypeRegistry` for one bit
  per named type and never reaches `ArchetypeRegistry`; a compiled query holds
  masks and resolves archetypes in `Query.groups` and `Query.run`, both of
  which read `ArchetypeRegistry.count` when they walk. A query therefore
  matches a scene registered long afterwards, which is what `loadScene` on an
  undeclared scene does at runtime. What orders the passes is
  `collectListeners` reaching for a system, and that is what the comments say
  now. One of the five also placed `describeScenes` before the isolate spawn,
  where it runs from `Game._bootGame`, on the game isolate (#225).

  No behaviour changed. The mechanism is pinned by four tests: three in
  `query_test.dart` and one in `describe_scenes_test.dart` covering a
  `describeQuery`-built query against a scene loaded at runtime, each
  asserting against a fixture with a non-matching archetype in it so that
  matching everything and matching nothing both fail.

* **A scene loaded from `GameState.onMounted` no longer hangs when its assets
  decode without yielding.** On a spawned run the game isolate mounts the world
  before it sends `ready`, so a `loadScene` in `onMounted` puts its
  `loadAssets` request on the wire first, and `ready` is what carries the port
  main answers over. Main handled the request with that port still null and
  sent both replies through `_toGame?.send`, which on null is a no-op with
  nothing logged: the `Completer` the `loadScene` was waiting on never
  completed, and the game went on ticking around a dead `await` with no error,
  no timeout and no stack (#260).

  Every source that ships reads a file or a bundle, and awaiting real I/O
  yields to the event loop, which is where `ready` got delivered mid-request.
  So the window was closed by the decode taking a turn. `MemorySource.load` is
  `async => bytes` and takes none — and it is the documented source for tests
  and generated content.

  A reply produced before `ready` is now held and sent on the `ready` arm, in
  the order it was made. One list per run, allocated only on a run that
  replies that early; after `ready` the path is a field read and a send. The
  boot ordering is unchanged, so `start()` still returns to a game whose world
  exists. `Game.startInline` was never affected: it decodes in place and sends
  no message.

* **A handler that runs with no tick window open can no longer change the
  world, in any build.** Two command lanes run user code outside
  `beginTick`/`commitTick`: the receipt-delivered one, dispatched from a
  control-port callback, and the read-only one, drained once per frame from
  `GameState.advance`. Both told the caller not to write and neither could
  check it (#245). Measured on a `hasControlSink` handler writing a component
  field: with asserts on and a page that had published, the one assert in
  `data_layout.dart` fired; in a release build that assert is not there, so the
  write landed in the write slot and the next `beginTick` copied the published
  bytes back over it with nothing said; on a page that had never published,
  nothing was reported in either build and the value stuck. `addEntity`, a
  `StateChannel` write and `unloadScene` reported nothing at all, and
  `unloadScene` freed the scene's native pages on the spot.

  `MemoryPool` now holds a `HandlerWindow`, and `CommandTransport` opens the
  matching one around every dispatch that runs with no tick open — one place,
  where a handler starts running, rather than one check per write path. A
  component write, adding or destroying an entity, and loading or unloading a
  scene each throw a `StateError` naming the lane. A read-only handler is held
  to a `StateChannel` as well; a receipt-delivered one is not, because
  publishing on a channel is the answer leg it has instead of a reply and the
  engine's own refusal for a control command that returns a value says to reach
  for exactly that.

  **It costs the write path nothing.** `ArchetypeStorage.rowWrite` already
  compared its cached epoch against `MemoryPool.epoch` before every field
  write; it compares against `writeEpoch` instead, which is the same number
  whenever writing is legitimate and an impossible one while a window is open.
  So a running game runs the same field load and the same branch it always did,
  and a sealed pool sends every write into the row-cache miss path that already
  existed, where the refusal lives. Nothing per entity, nothing per tick.

  **A tick window beats a handler window**, which is what keeps `stepOnce`
  working: it is itself a receipt-delivered handler and it runs a whole fixed
  step, and the writes inside that step are as legitimate as any other tick's.

  **Bootstrap is untouched.** The `|| !hasPublished` clause on the old assert
  was an escape hatch for scene bring-up, and a hole at the same time — a
  handler that happened to touch a fresh page was unguarded in every build. It
  stays, and it stops being a hole: the new refusal never asks whether a page
  has published, only whether a handler that may not write is running. Scene
  mounting is not one, so it writes exactly as it did.

  A handler that throws — including one refused here — no longer re-runs off
  the same queue entry on the next frame, and a local caller awaiting it is
  told rather than left waiting.

* **A game whose fixed tick is stopped now adopts a reply the other isolate
  has already written.** `CommandTransport.pump` had one call site on the game
  isolate, inside `runFixedStep`, so a paused game — or one at a time scale of
  zero — read nothing back out of the command ring. Main was never affected:
  its pump rides the per-tick notification, which `presentFrame` sends on
  every frame including one that ran no step, so main went on answering at
  full rate while the game side collected none of it. A system awaiting a
  main-isolate supplier from its presentation pass waited out the whole pause
  for a value main had computed several frames earlier.

  `GameState.advance` now calls `GameRuntime.adoptCommandReplies` once per
  frame, between the presentation pass and `presentFrame`. It adopts replies
  and runs no handler, so nothing new runs outside the tick window and a
  tick-delivered command still waits for a fixed step exactly as it did
  (#165).

  The other direction is unchanged: main asking a paused game something still
  waits for the tick to come back, and a game hidden under `pauseWhenHidden`
  runs no frame at all, so it adopts nothing either way.

* **`Game.simulationFps` counts frames the simulation published, not frame
  callbacks.** The meter was fed from the per-frame tick notification, which
  fires on every frame including one that ran zero fixed steps — so a paused
  game reported a healthy sixty while its tick sat still and nothing new
  reached the screen. It now counts only a frame whose tick moved, which is
  the same test `DrawCanvas2D.ingestFrame` applies before it will draw a
  batch, and `simulationFrameCount` stops climbing with it.

  It also reads **zero** once the simulation stops publishing, rather than
  freezing at the rate it last managed: the rate is now taken as of the moment
  it is asked, so the silence since the last published frame is part of the
  interval it is over. `Game.fps` is unchanged — the display half has no clock
  of its own to ask (#167).

  `worstSimulationIntervalMillis` still stamps on the main isolate when the
  tick message arrives, so on a spawned run a busy main isolate can inflate
  it. That is unchanged and now says so in its doc.

* **`Game.stop()` fails a command batch that was still queued, instead of
  dropping it.** A game-destination batch waits for the next tick window, so
  one sent and not yet ticked sits in the transport's inbox — and stopping
  cleared that list without telling anyone. The `await` on such a batch never
  returned and never threw, which on an inline run is every web build, every
  test and every headless host. It now completes with a `StateError` saying
  the batch never ran, distinct from the one an in-flight batch gets, which
  says its reply was lost (#167).

* **The two errors printed when a system is switched off name a method that
  exists.** Both said `Game.enableSystem`, which moved to `GameState` and left
  no forwarder; one of them is what `FlutterError.reportError` prints in a
  release build, so it was the engine's one working diagnostic pointing at an
  API a reader could not find. The assert now names
  `GameState.enableSystem<T>()`, and the release report says what a
  main-isolate reader can actually do about it, which is send a command whose
  handler calls it (#166).

* **A false claim in the 0.2.0 notes is corrected.** They said the four
  commands the engine now declares broke `good_net` peer compatibility. They
  did not: the handshake hash reads network messages, declared in
  `describeNetwork` on the `GameState`, and never the commands
  `describeCommands` declares on the `Game`. No behaviour changed, here or
  there. `good_net` 0.2.1 carries the same correction for the users it
  actually reached.

* **A key held when the window loses focus is released too, not only when the
  app is hidden.** #160 hung the release off this engine's definition of
  visible, which counts `inactive` - a window still on screen with nothing
  focused - as being played, so alt-tabbing mid-strafe left the character
  strafing. Measured on Windows 11 against a desktop build before changing
  anything: an unfocused window reports `inactive` and from that moment
  receives no key events at all, so the up for the held key is delivered to
  whoever took the focus and never arrives. Losing focus now releases every
  held key, mouse button and analog axis (#161).

  **The game keeps drawing and keeps stepping through all of it.** The same
  measurement counted frames across the unfocused stretch and they came at
  the rate they had before, so `inactive` stays on the visible side of
  `visibleInLifecycleState` and only the release moved. Alt-tabbing does not
  pause the game; it empties the keyboard.

  A pad is the one device this costs anything. Windows and Linux report pad
  state to an unfocused window, so a button held straight through the focus
  loss now reads released until it is let go and pressed again - the trade
  the keyboard already takes, on a device that was not obliged to take it.

* **A key held while the app is backgrounded no longer stays held forever.**
  An OS that takes focus away sends no key-up, so the block went on reporting
  the press for the rest of the run: background a game with a movement key
  down and the character kept walking, through the hide and through the
  return. Being hidden and losing the last view now both release everything
  held. Mouse buttons had it too; gamepads never did, and the rule the rest of
  the layer now follows was already written on `GamepadCollector.detach`
  (#160).

  **Nothing is re-asserted on the way back.** A key still physically held when
  the player returns sends no fresh key-down, so it reads up until they lift
  it and press again. That is the trade and it is the right way round: a false
  "not held" corrects itself on the next press, a false "held" corrects itself
  never.

* **One finger through two stacked `GameView`s is one contact again, and the
  front view is the one that gets named.** `GameView`'s `Listener` is
  `HitTestBehavior.translucent`, so a view behind another is handed the same
  pointer dispatch and wrote it to the device too. The contact table saw a
  press of an id already down, found the first slot still live, declined to
  reuse it and opened a second - two live contacts under one id, which nothing
  downstream can tell from two fingers. Measured with two views in a `Stack`
  and one tap: `#1 ended view=CameraView#1 | #1 ended view=CameraView#0` (#275).

  The cursor half is the same event arriving twice with the writes in the
  other order. Hit testing runs front to back, so the view furthest back wrote
  `pointerView` and the surface size last and claimed both: a HUD drawn in
  front resolved its picking against the world view underneath it, and
  `Game.viewWidth` read the size of a view the pointer was not in. Measured on
  a 200x150 panel over a 400x300 view, where a press inside the panel reported
  400x300.

  `InputDevice.claimPointerEvent` is the gate. `PointerEvent.original` is the
  same object for every copy a hit test makes of one dispatch, so the first
  caller of a dispatch takes it and every later one is turned away - one
  reference compare and one field, on a path that runs for every pointer move.
  Two fingers landing in the same frame are two dispatches and stay two
  contacts.

  Nothing changes for a game with one `GameView`, which is the only caller of
  its dispatch. `InputDevice.handlePointerEvent` still writes whatever it is
  given, so a replay, a bot or a test driving the device directly is
  unaffected.

## 0.2.0

Two gaps 0.1.0 admitted are closed: a column can be declared by the field that
holds it, and system order is worked out from the constraints instead of by
sorting. Several checks that used to let a mistake through now stop it.

### Breaking

* **`getScene<S>()` is now `singleScene<S>()`**, on `GameState` and on
  `GameSystem`. Rename the call; nothing else changes. It always threw once a
  second scene was resident, and several scenes at once is ordinary here — a
  level plus a HUD, a pause menu over a game — so the old name described a call
  that worked right through development and then threw on the first tick after
  something loaded a HUD. The name is the only place that precondition is
  visible at the call site. A game with more than one scene loaded reaches them
  through `loadedScenes` or the handle `loadScene` returned, and asks an entity
  which scene it belongs to with `entity.sceneSlot`. `Component.getScene`,
  which resolves the scene *that entity* was registered with, is unaffected and
  keeps its name.
* **The profiler is out of the engine.** `GameState` no longer publishes
  `lastSimulationMicros`, `lastSystemMicros`, `lastPresentationMicros` or their
  best-of rings. A game framework is not a profiler, and anything that wanted
  those numbers can time the part it cares about. The clocks that run the
  engine stay, including the two `FrameMeter`s behind `fps` and `jank`.
* **`Accessor` is bound to `Component`.** `entity<String>()` no longer
  compiles. `Accessor` also gained a `component` getter, which is what an
  extension on it reaches for on nearly every line.
* **`SingleQuery.component` is abstract.** It was a
  `throw UnimplementedError()` on the public class while the only
  implementation always supplied it.
* **`describeType`, `describeAssets`, `describeStruct`, `describeEvents` and
  `describeCommand` are `@mustCallSuper`.** An override that drops the base
  pass contributed nothing and said nothing; `EntityStruct`, `GameState` and
  `SceneStruct` all did it with `describeEvents`. For a component mixin,
  `good generate` now fails on it outright.
* **Indexing a column with an entity of another archetype throws.** The access
  path resolved a row from the page index and the row offset alone, so a column
  subscripted with the wrong entity read or overwrote whichever live row sat at
  that offset in its own storage. The message names the entity's archetype, the
  column's, and the column. Debug builds only, like the other guards below.
* **A hierarchy edge cannot cross a scene.** A scene's pages are freed
  wholesale, so an edge spanning two of them left the surviving side naming a
  freed row. `unloadScene` now unlinks the edges leaving the scene, after the
  unmount events, so a listener still reads the hierarchy as it stood.
* **Eleven per-access and per-spawn guards are asserts.** A release build no
  longer throws on them, because each was answering a question settled by the
  shape of the code and not by the running game. The two that cost most were
  the array bounds check on every element get and set, and the acyclicity walk
  on every `addChild`, `adopt` and declared-child spawn.

### Added

* **Seeded random streams.** The kernel had no randomness, so a game would
  reach for `dart:math`'s `Random()` — seeded from the clock, invisible to the
  engine, different on every machine, and impossible to retrofit once shipped
  games depend on it (#125).

  ```dart
  late final RandomStream loot;

  @override
  void describeRandom(RandomDescriptor descriptor) {
    super.describeRandom(descriptor);
    loot = descriptor.has();
  }
  ```

  Declared like every other handle and kept in a field — there are no stream
  names and nothing to look up. Streams are independent, which matters more
  than it sounds: with one shared stream a system that draws a different number
  of times shifts every draw after it, and the engine now disables a system by
  itself when one throws, so that happens without anyone editing the drawing
  code.

  `RandomStream.intFor(entity, max)` is the per-entity form, and it is a
  **hash** of the seed, the stream, the tick and the entity rather than a draw.
  So it does not depend on how many entities exist or who was asked first, and
  a scene loading or unloading cannot shift it.

  The seed is `Game.randomSeed`, an overridable member like `pageSize`. Back it
  with a final field to supply a recorded one. It is part of a save: recording
  inputs without it reproduces nothing.

  **The algorithm is written out in the engine** rather than taken from
  `dart:math`. `Random` gives no guarantee that a seed produces the same
  sequence on a different Dart SDK, so a replay could stop matching after an
  upgrade with nothing in the game having changed. SplitMix64's constants are
  now part of the engine's contract, and changing one is a breaking change to
  every recorded replay.

  Only the simulating copy may draw. A draw on the handle the main isolate
  holds throws, naming the copy.

  **This is not deterministic replay, and does not deliver it.** A replay also
  needs the player's input recorded per tick, the tick each command landed on,
  and an answer for asset loads finishing at a different moment — and control
  commands are explicitly unordered against tick-delivered ones, so their
  arrival is not reproducible either. See #63.

* **`pause`, `resume`, `setTimeScale` and `stepOnce` travel as commands.** They
  were four hand-rolled string tags on the control port; they are now ordinary
  receipt-delivered commands (#142). Nothing changes at the call site, and the
  behaviour is the same — the tests for #117 and #124 pass unmodified — but
  there is one less bespoke channel between the isolates, and the four tags are
  gone.

  Receipt-delivered because each one can stop the fixed tick. A tick-delivered
  command is pumped from `runFixedStep`, so the message that started the tick
  again would be waiting on the tick it stopped.

  **The engine now declares four commands of its own**, before anything a game
  declares, so a game's commands sit after them in the declaration order. That
  order is internal wire identity and both isolate copies agree on it, so a
  game sees no difference.

  0.2.0 shipped this paragraph claiming the shift also broke `good_net` peer
  compatibility. **It does not**, and that sentence has been corrected rather
  than removed. `good_net` hashes the messages `describeNetwork` declares on
  the `GameState`, not the commands `describeCommands` declares on the `Game`,
  so the two passes are independent - see `good_net` 0.2.1.

* **A command can be delivered when the message arrives instead of on the next
  tick.** Register the handler with `hasControlSink` or `hasControlSignal`
  instead of `hasSink`/`hasSignal` (#142).

  ```dart
  // in GameState.describeCommands
  descriptor.hasControlSink(setTimeScale, (s) => state.timeScale = s);
  ```

  A normal command is pumped from `GameState.runFixedStep`, so it arrives only
  if the tick runs. That is right for gameplay — a command-spawned entity is
  visible to every system on the tick its command lands — and useless for
  anything that *stops* the tick, because the message that starts it again
  would be waiting on the tick it stopped. A control command is carried over
  the control port and run from the port callback, with no tick involved.

  Four things are true of it that are not true of `hasSink`, all following from
  there being no tick:

  * **Its future completes on send, not on execution.** `await` means "handed
    to the port", not "done". There is no reply leg, because a reply would be
    pumped inside the tick window this exists to work without.
  * **Its handler must not write component data.** There is no open write slot
    outside a tick, so a write would be erased by the next `beginTick` with
    nothing said. A debug assert catches it.
  * **That assert has one hole**: it stays silent while a page has never
    published, which is scene bootstrap and nothing else. A running game is
    covered.
  * **No ordering against ordinary commands.** Two calls sent in order can run
    in either, since they travel by different carriers.

  `hasControlHandler` and `hasControlSupplier` exist and **always throw**. A
  receipt-delivered command cannot answer, so the names that promise a reply
  fail where they are written rather than hanging where they are called.

  `CommandDescriptor` gained these four methods. Nothing outside the engine
  implements it, so this affects no game.

* **Pause, time scale and single-step.** There was no way to pause a game, run
  it in slow motion, or advance it one tick (#124).

  ```dart
  game.setTimeScale(0.25);   // quarter speed
  game.pause();              // and stopped
  game.stepOnce();           // exactly one fixed tick
  game.resume();             // back at quarter speed
  ```

  Callable from the main isolate, because that is where a pause button lives;
  `GameState.timeScale`, `.paused` and `.stepOnce()` are the same controls on
  the simulating side. Pause and scale are separate state, so a game paused at
  half speed comes back at half speed.

  **The scale changes how often a fixed tick happens, never how big one is.**
  Every `onFixedUpdate` still represents exactly `Game.fixedTimeStep` at every
  scale — a fixed timestep means a constant step, and that guarantee is why
  anything integrating over it is stable. So there is no `dt` parameter to
  scale and none was added.

  For the same reason a `timeScale` of `0` runs **no fixed ticks at all**,
  rather than ticks with a zero-size step: nothing divides by zero and no
  system sees a step it was not written for.

  There is no `unscaledDt` to look for either, because both clocks already
  exist under other names. The fixed loop is scaled simulation time; a
  `Tickable`'s `onTick(Duration)` is real wall clock and keeps running while
  the simulation is stopped. Anything that must ignore pause and scale — a UI
  animation, a network heartbeat, an autosave timer — is a `Tickable`, which
  is where it already belonged. Presentation running while paused is also what
  lets a pause menu draw itself.

  Two edges worth knowing. A negative scale is rejected with an assert, since
  nothing here is reversible and a negative delta would corrupt the step
  arithmetic rather than rewind anything. And a *large* scale meets the
  existing `maxFixedStepsPerAdvance` guard: a frame affords at most 5 steps
  however much scaled time it earned, so scales past about 5 run the game
  slower than asked instead of faster. Raise that cap if a game genuinely
  needs fast-forward; it is deliberately unchanged here, because it is what
  stops a slow machine spiralling.

  Independent of `pauseWhenHidden`: a game paused here stays paused across
  being hidden and shown again.

* **The game reacts to the app being hidden.** Nothing in the engine knew the
  app had been backgrounded, so a game went on simulating at its fixed tick
  while nobody was looking at it — battery spent on a world off screen (#117).
  The fixed tick now stops when the app is hidden and starts again when it
  comes back. Override `Game.pauseWhenHidden` to `false` for a game that has to
  keep running unattended: a live server-authoritative session, a download, a
  timer the player expects to have advanced.

  A system hears it by mixing in `AppVisibilityListener`, which gets
  `onAppHidden()` and `onAppShown(Duration gap)`.

  **Visibility, never focus.** Flutter's five `AppLifecycleState`s collapse to
  two, and `inactive` counts as visible: a window losing focus, a phone call,
  the notification shade, the app switcher. Pausing on those is why some games
  stop when you alt-tab.

  **There is no "about to be killed" hook**, deliberately. `onAppHidden` is the
  last reliable moment and it is a real one — iOS and Android both synthesise
  `hidden` before `paused` — so a save goes there. `detached` gets no callback:
  it is also the state an app is in before it starts, a killed process never
  sends it, and no platform promises time to act on it.

  On the accumulator, one correction worth stating because it is easy to assume
  otherwise: a long absence never queued a long catch-up. `advance` already
  capped a single frame at `maxFixedStepsPerAdvance` and dropped the rest, and
  it leaves under one step behind it, so the burst a resume could produce was
  never proportional to the time away. Stopping the tick is what saves the
  battery; discarding the leftover on the way back is worth **one** step, not
  five, and that is the step this no longer spends.

* **`AudioClip` is a kernel type, and the kernel registers its decoder.** It
  was in `goo2d`, which put sound behind a 2D renderer for no reason it could
  defend: a clip is bytes and a container name, with no canvas, device or
  dimension in it. A `goo3d` project could load nothing at all as a result
  (#93). Every engine package re-exports the kernel, so `AudioClip`,
  `AudioLoader`, `AudioKey` and `AudioAsset` are named exactly where they were
  for a `goo2d` game and are now reachable from a 3D one. `Game` registers the
  decoder itself, so no game declares anything to get it. Still no playback.

* **`Game.describeAssetLoaders` registers a payload type's decoder.** It joins
  `describeState`, `describeScenes`, `describeCommands`, `describeBuffers` and
  `describeCameras`, chains through `super` the same way, and is the one of
  that family that runs on the decoding isolate only - `AssetLoaders` is a
  per-isolate static, and the game isolate holds payload-free declarations and
  never decodes. Registering a type the layer below already covers replaces it,
  so a game can substitute its own decoder for an engine one. `AssetLoaders`
  also gained `isRegistered<T>()`, which answers what `of<T>()` could only
  answer by throwing.

* **A column can be declared by the field that holds it.**
  `final speed = Field.float64(220)` replaces a `late final DataPointer<double>`
  paired with a `describeStruct` body a few lines down. Both forms work: a
  column whose default comes from `describeAssets` cannot be a field
  initialiser, since Dart will not let one field read another. Row layouts moved
  as a result, which costs only a test that named an offset.
* **A prefab can declare the children it always spawns.**
  `final barrel = EntityStruct.of(Barrel.new)` on a `Parent` spawns the barrel
  with the turret, links it underneath, and destroys it with the turret.
  Declarations nest, and a struct that declares itself is a registration error
  naming the ring.
* **A prefab can move an inherited column's default.** `DefaultPointer` carries
  `defaultValue`, writable until `seal()`, so two prefabs sharing a component no
  longer need a descriptor class and a hook that exists only to feed `has*`
  calls.
* **`hasEntity`** for a column holding an entity handle, **`hasEnum`** for an
  enum-valued column, and **`hasEntity`/`optEntity`** on `ParamDescriptor`.
* **`hasFloat32ArrayOf` and `hasFloat64ArrayOf`**, taking one default per
  element. Array defaults were a single scalar broadcast across every slot.

### Fixed

* **A system that throws no longer kills the game.** It used to, silently and
  permanently (#126). One uncaught error anywhere on the game isolate stopped
  the tick for good, while `Game.isRunning` went on answering `true` and
  `stop()` waited forever for a message from an isolate that no longer
  existed — a hung shutdown and a leaked pool, with no Dart error anywhere.
  The only trace was an engine log nothing in the app could see.

  Each listener is now guarded individually, so one bad system does not stop
  the others in the same tick, and the offending listener is disabled.

  **Debug and release differ here, and the difference is surprising enough to
  spell out.** In debug an `assert` fires and stops the game isolate — the
  loud answer, and no longer a silent one, because `Game.start` now installs
  an error port: the death reaches the main isolate, `isRunning` goes false, a
  pending `stop()` completes with the error instead of hanging, and the
  failure is reported where Flutter and the test runner already look. In
  release there is no assert: the system stays disabled and the game keeps
  running. So **the disable is release behaviour**, and
  `Game.enableSystem<MySystem>()` brings it back if the throw was transient.

  Two things that were already true and are now written down. The tick is
  **atomic** as far as any reader is concerned: the fixed-tick dispatch runs
  before the tick is committed, so a tick that throws publishes nothing, and
  the next tick copies the last published state back over the partial write. A
  failed step is **not retried**, because the accumulator is debited before the
  step runs — otherwise a deterministically throwing system would be handed the
  same step forever.

  Coroutines were already handled and are unchanged: `CoroutineScheduler`
  removes a throwing coroutine and completes its handle with the error.

  `GameListener` gains `disableAfterUncaught()`, which is how a listener says
  whether it can be switched off. `GameSystem` disables itself; the other three
  hosts do nothing, since switching off a `GameState`, `SceneStruct` or
  `EntityStruct` is not a smaller failure than the throw was.

* **An entity's heap-object slots are freed when its row goes.** A slot in the
  process-global table was the one thing a row owned that neither freeing the
  row nor dropping its page reclaimed, so a game using `hasHeapObject` and
  destroying entities grew that table for the life of the process. Both
  `destroy()` and scene unload release them now.
* **System order honours every constraint.** `compareTo` states a partial
  order, which `List.sort` is not defined for; given one it permuted the list
  and dropped an unrelated constraint elsewhere. A composer could sort ahead of
  the spawner, so an entity created during a tick was composed on the next one
  and published `(0, 0)` in between.
* **Gamepads are detached before the input buffer is freed.**

## 0.1.1

Documentation only. No code changes.

The README now opens with the column-and-row model and a code example, and
says plainly that a 2D game should depend on `goo2d` instead.

## 0.1.0

First published release. The dimension-agnostic kernel is real and tested:

* **ECS** — `Entity`, `Component`, `GameSystem`, `Query`, `GameEvent`.
* **Storage** — the native memory pool and ring buffers behind `dart:ffi`,
  with `DataDescriptor` computing struct layouts at runtime.
* **Simulation** — the fixed-tick loop, the scheduler, and `GameScene`, run on
  their own isolate.
* **Hierarchy** — `Child`/`Parent` and composed world transforms.
* **Input, assets, coroutines and timelines**, plus `GameView` for the Flutter
  side.
* **Commands** — `SinkCommand`/`SignalCommand` over the shared record layer
  (`ParamDescriptor`, `ParamPointer`, `ParamBatch`, `ParamBuffer`), which
  `good_net` reuses instead of reimplements.

Not here yet: array-typed `DataDescriptor` fields in the codegen path,
dependency-based system ordering (`compareTo` is the mechanism today), and
audio playback — `AudioClip` decodes, but there is no backend or mixer. Web is
unsupported: the kernel needs `dart:ffi` and isolates.

## 0.0.1

* Initial split from `goo2d`: dimension-agnostic ECS kernel, memory pool,
  ring buffer, scenes, fixed-tick loop, hierarchy, and generic asset
  registry. Never published.
