import 'package:meta/meta.dart';

import 'package:good/src/asset.dart';
import 'package:good/src/camera_view.dart';
import 'package:good/src/command/command.dart';
import 'package:good/src/command/param.dart';
import 'package:good/src/data.dart';
import 'package:good/src/event.dart';
import 'package:good/src/event/state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/random.dart';
import 'package:good/src/struct.dart';

/// What `EntityStruct.of` declares against: whoever is registering prefabs
/// right now.
///
/// Separate from [DataDescriptor] because it declares a different thing. A
/// field initialiser reaching for `Field.float64` wants a column on the
/// archetype being built; one reaching for `EntityStruct.of` wants a whole
/// archetype of its own, registered with the same scene, plus a column on the
/// archetype being built to hold its handle. One is the row; the other is the
/// scene's prefab list, the archetype registry and the row.
@internal
abstract interface class PrefabRegistrar {
  /// Registers [create]'s prefab as a child of the archetype currently being
  /// declared, and returns it. See `EntityStruct.of`, which is the only
  /// caller.
  T declareChild<T extends EntityStruct>(T Function() create);
}

/// What `Component.type` declares against: the archetype whose prefab is
/// being constructed right now.
///
/// Separate from [DataDescriptor] because a component type is not a column. A
/// column is bytes in every row; a component type is one bit in the
/// archetype's query signature, and an archetype carries at most one of each.
@internal
abstract interface class ComponentRegistrar {
  /// ORs [type]'s bit into the archetype's signature and records what it
  /// refuses to share an archetype with. Returns the bit, which is what
  /// `ComponentType` carries. See `Component.type`, the only caller.
  int declareComponent(Type type, Map<Type, String> conflictsWith);
}

/// The descriptor a field initialiser declares against, for the duration of
/// one object's construction.
///
/// A field like `final speed = Field.float64(3.0);` has no descriptor in
/// scope - it is an initialiser, so it cannot see `this`, let alone an
/// argument some later method would have been handed. So the framework puts
/// the descriptor here first and constructs the object second:
/// `SceneDescriptor.has` takes `Mote.new` and not `Mote()` for exactly that
/// reason.
///
/// # Why a stack
///
/// Declaration nests. A scene declares prefabs, and a prefab's own fields
/// declare columns, so a second context opens while the first is still
/// wanted. A single slot cleared on the way out loses the outer one, and
/// anything declared after the nested call fails - which is not hypothetical,
/// it is what a one-slot version does the moment a scene has a field after
/// its first prefab.
///
/// # Why the initialisers must be eager
///
/// `late final speed = Field.float64(3.0)` compiles and is wrong. A `late`
/// initialiser runs on the first *read*, so the offsets a struct's fields get
/// depend on the order something happened to touch them - two instances of one
/// prefab, read in different orders, lay out differently, and the render
/// isolate and the game isolate then disagree about where a column is. Field
/// initialisers here are eager, always.
@internal
abstract final class DeclarationContext {
  /// The open data contexts, innermost last. A `null` entry is a barrier -
  /// see [pushBarrier].
  static final List<DataDescriptor?> _data = <DataDescriptor?>[];

  /// Opens a context. Every push is paired with a [popData] in a `finally`,
  /// so a constructor that throws does not leave the stack dirty.
  static void pushData(DataDescriptor descriptor) => _data.add(descriptor);

  /// Closes the stack for the duration of a pass that is **not** a
  /// constructor, so a `Field.*` call inside one reports itself instead of
  /// silently declaring against whatever is underneath.
  ///
  /// Only nesting makes this necessary, and nesting is what
  /// `EntityStruct.of` introduced: a child prefab's `describeStruct` runs
  /// while its *parent's* constructor is still on the stack, so a body that
  /// wrote `Field.float64()` instead of `data.hasFloat64()` would add a
  /// column to the parent's row and read it back from the child's. Before
  /// there was anything to nest inside, the stack was simply empty there and
  /// the same call threw.
  ///
  /// Popped by [popData], which pops either kind.
  static void pushBarrier() => _data.add(null);

  static void popData() => _data.removeLast();

  /// The innermost open context, or a `StateError` naming the one thing that
  /// puts a caller here: constructing a struct by hand instead of letting the
  /// framework construct it.
  static DataDescriptor get data {
    final descriptor = _data.isEmpty ? null : _data.last;
    if (descriptor == null) {
      throw StateError(
        'A Field was declared with no struct being constructed. Field.* '
        'reads the descriptor the framework opens around a constructor call, '
        'so the struct has to be built by the framework:\n'
        '  descriptor.has(MyStruct.new)   // not descriptor.has(MyStruct())\n'
        'Constructing one directly - in a test fixture, or to read a field '
        'off it - runs the initialisers with nothing to declare against, '
        'which is what this is. A describeStruct body is the other way to '
        'get here: it runs after the constructor, so it declares through the '
        'DataDescriptor it is handed rather than through Field.*.',
      );
    }
    return descriptor;
  }

  /// The open component registrars, innermost last - the eighth level of the
  /// stack, and the one `Component.type` declares against. A `null` entry is
  /// a barrier, exactly as in [_data].
  ///
  /// Opened and closed in lockstep with [_data], around the same constructor
  /// call, because the two declare the two halves of one archetype: the
  /// columns a row carries and the bits its signature carries. Kept apart
  /// because [DataDescriptor] is the public row-layout surface a
  /// `describeStruct` body is handed, and a component bit is not a column.
  static final List<ComponentRegistrar?> _components = <ComponentRegistrar?>[];

  static void pushComponents(ComponentRegistrar registrar) =>
      _components.add(registrar);

  /// Closes the component stack for a pass that is not a constructor, for
  /// [pushBarrier]'s reason: a nested prefab's post-construction passes run
  /// while its declarer's constructor is still on the stack, so a
  /// `Component.type` call in one would put a bit on the declarer's
  /// signature and read it back from the child's.
  static void pushComponentBarrier() => _components.add(null);

  static void popComponents() => _components.removeLast();

  static ComponentRegistrar get components {
    final registrar = _components.isEmpty ? null : _components.last;
    if (registrar == null) {
      throw StateError(
        'A component type was declared with no struct being constructed. '
        'Component.type reads the registrar the framework opens around a '
        'constructor call, so the struct has to be built by the framework:\n'
        '  descriptor.has(MyStruct.new)   // not descriptor.has(MyStruct())\n'
        'It belongs in a field initialiser of the component mixin itself, '
        'where it is written once for every prefab that mixes the component '
        'in:\n'
        '  mixin Health on Component {\n'
        '    final healthType = Component.type<Health>();\n'
        '  }\n'
        'A `late final` initialiser lands here too: it runs on first read, '
        'after the archetype was sealed, so the bit would never reach the '
        'signature a query matches against. Field initialisers here are '
        'eager, always.',
      );
    }
    return registrar;
  }

  /// Declarations waiting for the component that owns them, innermost list
  /// last - one list per object being constructed.
  ///
  /// A multi-instance component holds several named instances of itself on
  /// one entity: several sprites, several colliders. Each instance is
  /// declared on its own field (`final body = Sprite.of(...)`) and the
  /// component also needs all of them in one list, so that a renderer can
  /// walk every sprite an entity has without knowing this prefab's field
  /// names. The list cannot be built by the field initialisers that fill it,
  /// because a mixin's own initialisers run **after** the applying class's -
  /// `class Sub extends Base with M1, M2` runs `Sub`, `M2`, `M1`, `Base` - so
  /// the prefab's `Sprite.of` calls happen while `Renderable2D` has no fields
  /// at all.
  ///
  /// So the calls land here and the component takes them:
  ///
  /// ```dart
  /// mixin Renderable2D on MultiComponent {
  ///   final List<Sprite> sprites = MultiComponent.declared<Sprite>();
  /// }
  /// ```
  ///
  /// [takeDeclared] takes by type, so a prefab mixing in three of these
  /// components hands each one its own kind and the order inside each kind is
  /// declaration order.
  ///
  /// A list per construction rather than one flat list, for the reason
  /// [_data] is a stack: `EntityStruct.of(Barrel.new)` builds a child prefab
  /// from inside its parent's field initialisers, and the child's sprites are
  /// the child's.
  static final List<List<Object>> _declared = <List<Object>>[];

  /// Opens a collection for the duration of one object's registration.
  /// Paired with [popDeclared] in a `finally` - `SceneDescriptor.has` is the
  /// only caller.
  static void pushDeclared() => _declared.add(<Object>[]);

  static void popDeclared() => _declared.removeLast();

  /// Records one declaration, or a `StateError` naming the one thing that
  /// puts a caller here.
  static void addDeclared(Object declaration) {
    if (_declared.isEmpty) {
      throw StateError(
        '${declaration.runtimeType} was declared with no struct being '
        'constructed. A multi-instance declaration is collected by the '
        'component that owns it while the framework constructs the prefab, '
        'so the prefab has to be built by the framework:\n'
        '  descriptor.has(MyStruct.new)   // not descriptor.has(MyStruct())\n'
        'A `late final` initialiser lands here too: it runs on first read, '
        'after the archetype was sealed, so the declaration would reach '
        'neither the row nor the component list. Field initialisers here are '
        'eager, always.',
      );
    }
    _declared.last.add(declaration);
  }

  /// Removes every declaration of type [T] made so far by the object being
  /// constructed, in declaration order.
  ///
  /// Empty rather than an error when nothing is open: a component mixin is
  /// applied to classes the framework never constructs - a test reading a
  /// field off a prefab it built by hand - and the declaration call is the
  /// half that reports that, with the sentence above.
  static List<T> takeDeclared<T extends Object>() {
    if (_declared.isEmpty) return <T>[];
    final open = _declared.last;
    final taken = <T>[];
    open.removeWhere((declaration) {
      if (declaration is! T) return false;
      taken.add(declaration);
      return true;
    });
    return taken;
  }

  /// What the object being constructed declared and no component took.
  ///
  /// Read once, after construction, by `SceneDescriptor.has` - see the error
  /// it raises, which is the only thing this is for.
  static List<Object> get undeclaredLeftovers => _declared.last;

  /// The open prefab registrations, innermost last - the second level of the
  /// stack, and the one `EntityStruct.of` declares against.
  static final List<PrefabRegistrar> _prefabs = <PrefabRegistrar>[];

  static void pushPrefabs(PrefabRegistrar registrar) => _prefabs.add(registrar);

  static void popPrefabs() => _prefabs.removeLast();

  static PrefabRegistrar get prefabs {
    if (_prefabs.isEmpty) {
      throw StateError(
        'EntityStruct.of was called with no prefab being registered. It '
        'declares an entity into whichever scope is open, and the scope it '
        'reads is opened around a prefab constructor - so it belongs in the '
        'field initialisers of an EntityStruct that a scene registers:\n'
        '  class Turret extends EntityStruct with Parent {\n'
        '    final barrel = EntityStruct.of(Barrel.new);\n'
        '  }\n'
        'A SceneStruct cannot use it yet. A scene is constructed by the user '
        'and only gets its MemoryPool at initializeScene, so its own field '
        'initialisers run before there is anything to declare into; scenes '
        'declare with `descriptor.has(Mote.new)` in describeScene.',
      );
    }
    return _prefabs.last;
  }

  /// The open parameter layouts, innermost last - the third level of the
  /// stack, and the one `Param.*` declares against.
  ///
  /// A list rather than a slot for [_data]'s reason, though the nesting it
  /// guards against is thinner here: a command's fields are pointers into a
  /// record and a record holds no other record, so in practice this is
  /// either empty or one deep. Keeping it a stack costs nothing and means
  /// "empty" is the same question at every level.
  static final List<ParamLayout> _params = <ParamLayout>[];

  /// Opens a layout for the duration of one constructor call. Paired with
  /// [popParams] in a `finally` - see [ParamLayout.open], which is the only
  /// caller and exists so that both `good`'s command registry and
  /// `good_net`'s message registry open one the same way.
  static void pushParams(ParamLayout layout) => _params.add(layout);

  static void popParams() => _params.removeLast();

  /// The innermost open layout, or a `StateError` naming the two ways to get
  /// here: constructing the command yourself, and reaching a `Param.*` call
  /// lazily.
  static ParamLayout get params {
    if (_params.isEmpty) {
      throw StateError(
        'A Param was declared with no command or message being constructed. '
        'Param.* reads the layout the framework opens around a constructor '
        'call, so the framework has to be the one constructing:\n'
        '  descriptor.has(SpawnEnemy.new)   // not SpawnEnemy()\n'
        'A `late final` initialiser lands here too, and that is the point: '
        'it runs on first read, long after the declaration pass closed, so a '
        'parameter declared that way would take its bit offset from whatever '
        'order something happened to touch it. Field initialisers here are '
        'eager, always.',
      );
    }
    return _params.last;
  }

  /// The open event binders, innermost last - the fourth level of the stack,
  /// and the one `Event.*` declares against.
  ///
  /// A stack because the nesting is real, not for symmetry with the levels
  /// above: `EntityStruct.of(Barrel.new)` builds a child prefab from inside
  /// its parent's field initialisers, so the parent's binder is open while
  /// the child is being constructed and the child's dispatchers have to land
  /// on the child. No barrier entry - the describe passes that need one run
  /// after the constructor returns and this level is already empty by then.
  static final List<EventBinder> _events = <EventBinder>[];

  /// Opens a binder for the duration of one constructor call. Paired with
  /// [popEvents] in a `finally` - see [EventBinder.open], the only caller.
  static void pushEvents(EventBinder binder) => _events.add(binder);

  static void popEvents() => _events.removeLast();

  /// The innermost open binder, or null when nothing is being constructed.
  ///
  /// Read by `GameListenerBase`, which takes the open window as the owner's
  /// registrar and has an answer for there not being one - an owner the
  /// framework did not construct makes a registrar of its own.
  static EventBinder? get eventsOrNull =>
      _events.isEmpty ? null : _events.last;

  /// Dispatchers a base class declared on a field, waiting for the object
  /// being constructed to take them.
  ///
  /// **Not a level of the stack.** Every level above is a window a
  /// construction site opens, and a declaration in one asks "which window is
  /// innermost". `EntityStruct.mountedEvent` asks a different question -
  /// "which object is being constructed" - and the two differ whenever an
  /// owner is built inside another owner's window: a `SceneStruct` held on a
  /// `GameState` field is constructed while the state's window is open, and
  /// its pair belongs to the scene.
  ///
  /// So `Event.inherited` appends here and does nothing else. The object
  /// takes what is here from `GameListenerBase`'s constructor body, which
  /// runs after every field initialiser in the hierarchy and before any
  /// subclass constructor body - see [takeInheritedEvents].
  static final List<void Function(GameListener)> _inheritedEvents =
      <void Function(GameListener)>[];

  /// Records one declaration. `Event.inherited` and `Event.inheritedSignal`
  /// are the only callers, and the framework's three base pairs are the only
  /// callers of those.
  static void registerInheritedEvent(void Function(GameListener) offer) =>
      _inheritedEvents.add(offer);

  /// Hands over every declaration made since the last call, and empties the
  /// list.
  ///
  /// Called once per `GameListenerBase` construction, so what is here is
  /// exactly what the object under construction declared: a base class
  /// declares its pair from a field initialiser, and the only code that runs
  /// between that initialiser and this call is the remaining field
  /// initialisers of the framework classes below it, none of which builds
  /// another listener. A nested owner - `EntityStruct.of(Barrel.new)` in a
  /// parent's field initialiser - finishes constructing, and so empties this
  /// list, before the parent's own pair is declared.
  static List<void Function(GameListener)> takeInheritedEvents() {
    if (_inheritedEvents.isEmpty) {
      return const <void Function(GameListener)>[];
    }
    final taken = List<void Function(GameListener)>.of(_inheritedEvents);
    _inheritedEvents.clear();
    return taken;
  }

  /// The innermost open binder, or a `StateError` naming the two ways to get
  /// here: constructing the owner yourself, and reaching an `Event.*` call
  /// lazily.
  static EventBinder get events {
    if (_events.isEmpty) {
      throw StateError(
        'An Event was declared with no event owner being constructed. '
        'Event.of and Event.signal read the binder the framework opens '
        'around a constructor call, so the framework has to be the one '
        'constructing. It is for a GameState, which Game.createState hands '
        'back, and for a SceneStruct, an EntityStruct and a GameSystem, '
        'which their descriptors declare:'
        '\n  descriptor.has(MainScene.new)   // not MainScene()'
        '\n  descriptor.has(Mote.new)        // not Mote()'
        '\n  descriptor.has(SpinSystem.new)  // not SpinSystem()\n'
        'A `late final` initialiser lands here too, and that is the point: '
        'it runs on first read, long after the binder was closed, so a '
        'dispatcher declared that way would never be offered a listener and '
        'would deliver to nobody. Field initialisers here are eager, always. '
        'An owner the framework does not construct - a scene the caller '
        'builds and hands to loadScene - declares from its constructor '
        'body against EventBus.events instead.',
      );
    }
    return _events.last;
  }

  /// The open input registries, innermost last - the fifth level of the
  /// stack, and the one `Input.of` declares against.
  ///
  /// A stack for the same reason the levels above it are, though nothing
  /// nests here today: a game's constructor and a system's constructor each
  /// open one, and neither runs inside the other - a system is built on the
  /// game isolate, long after the game itself was. Keeping the shape means
  /// "empty" is the same question at every level.
  static final List<InputRegistry> _inputs = <InputRegistry>[];

  /// Opens a registry for the duration of one constructor call. Paired with
  /// [popInputs] in a `finally` - `Game.start` and `SystemDescriptor.has`
  /// are the callers.
  static void pushInputs(InputRegistry registry) => _inputs.add(registry);

  static void popInputs() => _inputs.removeLast();

  /// The innermost open registry, or a `StateError` naming the two ways to
  /// get here: constructing the owner yourself, and reaching an `Input.of`
  /// call lazily.
  static InputRegistry get inputs {
    if (_inputs.isEmpty) {
      throw StateError(
        'An Input was declared with no game or system being constructed. '
        'Input.of reads the registry the framework opens around a '
        'constructor call, so the framework has to be the one '
        'constructing:\n'
        '  Game.start(MyGame.new)             // not Game.start(MyGame())\n'
        '  descriptor.has(PlayerSystem.new)   // not PlayerSystem()\n'
        'A `late final` initialiser lands here too, and that is the point: '
        'it runs on first read, long after boot sealed the registry, so an '
        'action declared that way is refused outright by the seal. Field '
        'initialisers here are eager, always.\n'
        'A type-level fallback is the other half of input and does not come '
        'through here at all: it hands nothing back, so it is configuration - '
        'the inputDefaults getter, on a Game as much as on a system.',
      );
    }
    return _inputs.last;
  }

  /// The open command registrars, innermost last - the eleventh level of the
  /// stack, and the one `Command.of` declares against.
  ///
  /// A `Game` is the only thing that declares a command, and a `Game` is the
  /// first object the framework builds, so this is either empty or one deep -
  /// kept a stack anyway, so that "empty" is the same question at every level.
  static final List<CommandRegistrar> _commands = <CommandRegistrar>[];

  /// Opens a registrar for the duration of one game's constructor. Paired with
  /// [popCommands] in a `finally` - `Game._construct` is the only caller.
  static void pushCommands(CommandRegistrar registrar) =>
      _commands.add(registrar);

  static void popCommands() => _commands.removeLast();

  /// The innermost open registrar, or a `StateError` naming the two ways to
  /// get here: constructing the game yourself, and reaching a `Command.of`
  /// call lazily.
  static CommandRegistrar get commands {
    if (_commands.isEmpty) {
      throw StateError(
        'A Command was declared with no game being constructed. Command.of '
        'reads the registrar the framework opens around a constructor call, '
        'so the framework has to be the one constructing:\n'
        '  Game.start(MyGame.new)   // not Game.start(MyGame())\n'
        'A `late final` initialiser lands here too, and that is the point: it '
        'runs on first read, after boot numbered and sealed the declared '
        'list, so the command would have no index and nowhere to send to. '
        'Field initialisers here are eager, always.\n'
        'A Game is the only thing that declares a command at all - the ring a '
        'call travels through is allocated on main before the spawn, so only '
        'a declaration that runs there can own an index. A GameState and a '
        'GameSystem handle commands the Game declared, in describeCommands.',
      );
    }
    return _commands.last;
  }

  /// The open random registries, innermost last - the tenth level of the
  /// stack, and the one `RandomStream.of` declares against.
  ///
  /// A `Game` is the only thing that declares a stream, and a `Game` is the
  /// first object the framework builds, so this is either empty or one deep -
  /// kept a stack anyway, so that "empty" is the same question at every level.
  static final List<RandomRegistry> _randoms = <RandomRegistry>[];

  /// Opens a registry for the duration of one game's constructor. Paired with
  /// [popRandoms] in a `finally` - `Game._construct` is the only caller.
  static void pushRandoms(RandomRegistry registry) => _randoms.add(registry);

  static void popRandoms() => _randoms.removeLast();

  /// The innermost open registry, or a `StateError` naming the two ways to get
  /// here: constructing the game yourself, and reaching a `RandomStream.of`
  /// call lazily.
  static RandomRegistry get randoms {
    if (_randoms.isEmpty) {
      throw StateError(
        'A RandomStream was declared with no game being constructed. '
        'RandomStream.of reads the registry the framework opens around a '
        'constructor call, so the framework has to be the one constructing:\n'
        '  Game.start(MyGame.new)   // not Game.start(MyGame())\n'
        'A `late final` initialiser lands here too, and that is the point: it '
        'runs on first read, long after boot derived every declared stream '
        'from the seed, so a stream declared that way would have no seed and '
        'no index. Field initialisers here are eager, always.\n'
        'A Game is the only thing that declares a stream at all - the seed '
        'every stream is derived from is Game.randomSeed, and it is read once, '
        'on main, before the spawn. A GameSystem draws from a stream the Game '
        'declared: `state.game.loot.nextInt(6)`.',
      );
    }
    return _randoms.last;
  }

  /// How many `Game`s have finished constructing since whoever is watching
  /// last zeroed this.
  ///
  /// Not a level of the stack - a count, and the only thing here that is not
  /// a descriptor. It exists because the two windows a `Game` opens can be
  /// read by the wrong object and there is no other way to notice. A `Game`
  /// built inside another `Game`'s field initialiser declares into the outer
  /// game's descriptor and registry, and the result boots and runs: measured
  /// before the guard existed, the outer game held 2 channels and 1 action
  /// and the inner one held none of either, with the inner game's own handle
  /// reading a live value out of storage belonging to a game it is not. A
  /// `Game` built inside a `GameSystem`'s constructor does the same to that
  /// system's registry - 1 action on the host, 0 on the game.
  ///
  /// Neither is visible from inside the field initialiser. What *is* visible
  /// is that a second `Game` finished constructing before the first did, and
  /// counting is all it takes to see it. `Game`'s constructor body is the
  /// only caller; `Game.start` and `SystemDescriptor.has` save, zero and
  /// restore it around the constructor call they make.
  static int gamesConstructed = 0;

  /// Called from `Game`'s constructor body, on every `Game` ever built.
  static void noteGameConstructed() => gamesConstructed++;

  /// The open state descriptors, innermost last - the sixth level of the
  /// stack, and the one `Channel.*` declares against.
  ///
  /// This one is the outermost level in practice: a `Game` is the only thing
  /// that declares a channel, and a `Game` is the first object the framework
  /// builds. Nothing nests inside it that declares another channel, so the
  /// list is either empty or one deep - kept a stack anyway, so that "empty"
  /// is the same question at every level.
  static final List<StateDescriptor> _channels = <StateDescriptor>[];

  /// Opens a descriptor for the duration of one game's constructor. Paired
  /// with [popChannels] in a `finally` - `Game.start` and `Game.startInline`
  /// are the only callers.
  static void pushChannels(StateDescriptor descriptor) =>
      _channels.add(descriptor);

  static void popChannels() => _channels.removeLast();

  /// The innermost open descriptor, or a `StateError` naming the two ways to
  /// get here: constructing the game yourself, and reaching a `Channel.*`
  /// call lazily.
  static StateDescriptor get channels {
    if (_channels.isEmpty) {
      throw StateError(
        'A Channel was declared with no game being constructed. Channel.* '
        'reads the descriptor the framework opens around a constructor call, '
        'so the framework has to be the one constructing:\n'
        '  Game.start(MyGame.new)   // not Game.start(MyGame())\n'
        'A `late final` initialiser lands here too, and that is the point: '
        'it runs on first read, long after the descriptor was sealed and the '
        'storage allocated, so a channel declared that way would have no '
        'triple buffer and no index to be known by on the other isolate. '
        'Field initialisers here are eager, always.\n'
        'A Game is the only thing that declares a channel at all - its '
        'storage is allocated on main before the spawn, so only a pass that '
        'runs there can own an index. A GameState and a GameSystem are both '
        'built on the game isolate, after that allocation; publish from the '
        'Game and write through `state.game.myChannel`.',
      );
    }
    return _channels.last;
  }

  /// The open asset descriptors, innermost last - the seventh level of the
  /// stack, and the one `Asset.of` declares against.
  ///
  /// # This level is scoped to a scene, not to a constructor
  ///
  /// Every other level here is opened around one object's constructor,
  /// because what it declares belongs to that object: a column belongs to the
  /// archetype being built, a dispatcher to the struct that owns it. An asset
  /// belongs to **neither**. `_AssetDescriptor` is built once per
  /// `SceneStruct.initializeScene` and shared by the scene's own
  /// `describeAssets` and every prefab that pass registers, so the whole
  /// scene contributes to one deduplicated list and no prefab has an asset
  /// list of its own.
  ///
  /// That is why this level has no barrier and needs none. [pushBarrier]
  /// exists because a child's `describeStruct` runs while its parent's
  /// constructor is still on [_data], so an unbracketed `Field.*` there would
  /// put a column on the parent's row and read it back from the child's.
  /// There is no equivalent mistake to make here: the descriptor a nested
  /// prefab reaches and the one its declarer reaches are the *same object*,
  /// so an asset declared at the wrong moment still lands in exactly the
  /// place `descriptor.has` would have put it. What order it lands in is
  /// still deterministic - both isolate copies run the same code - which is
  /// the only thing an address depends on.
  ///
  /// A stack rather than a slot for the reason the levels above give: scene
  /// bring-up does not nest today, and keeping the shape means "empty" is the
  /// same question at every level.
  static final List<AssetDescriptor> _assets = <AssetDescriptor>[];

  /// Opens a descriptor for the duration of one scene's declaration passes.
  /// Paired with [popAssets] in a `finally` - `SceneStruct.initializeScene`
  /// is the only caller.
  static void pushAssets(AssetDescriptor descriptor) => _assets.add(descriptor);

  static void popAssets() => _assets.removeLast();

  /// The innermost open descriptor, or a `StateError` naming the two ways to
  /// get here: declaring an asset outside a scene's bring-up, and reaching an
  /// `Asset.of` call lazily.
  static AssetDescriptor get assets {
    if (_assets.isEmpty) {
      throw StateError(
        'An Asset was declared with no scene being brought up. Asset.of '
        'reads the descriptor `SceneStruct.initializeScene` opens around a '
        "scene's declaration passes, so the declaration has to happen "
        'inside one:\n'
        '  class Player extends EntityStruct {\n'
        '    final texture = Asset.of(Textures.player);\n'
        '  }\n'
        'A prefab is constructed by that pass, so its field initialisers are '
        'inside the window. A SceneStruct is not: it is constructed by the '
        'caller and only gets its Assets at initializeScene, so its own '
        'field initialisers run before there is anything to declare into - a '
        'scene declares in describeAssets, which is handed the same '
        'descriptor. Constructing a prefab directly, to read a field off it, '
        'lands here too.\n'
        'A `late final` initialiser lands here as well, and that is the '
        'point: it runs on first read, long after the pass that had to run '
        'on both isolate copies in the same order, so an asset declared that '
        'way would be addressed on whichever copy happened to touch it '
        'first. Field initialisers here are eager, always.',
      );
    }
    return _assets.last;
  }

  /// The open camera-view tables, innermost last - the ninth level of the
  /// stack, and the one `CameraView.representation` reads.
  ///
  /// # Scoped to a scene, like [_assets]
  ///
  /// A camera-view table belongs to the game, not to the prefab that names
  /// one, so it is opened around a scene's declaration passes rather than
  /// around a constructor. `SceneStruct.initializeScene` opens both in the
  /// same `try`, and a prefab's `final cameraView =
  /// Field.optPacked(CameraView.representation())` reads this one while its
  /// `Asset.of` fields read that one.
  ///
  /// No barrier, for [_assets]'s reason: a nested prefab and its declarer
  /// reach the *same table*, so there is no wrong table to land in.
  static final List<CameraViewTable> _cameraViews = <CameraViewTable>[];

  /// Opens a table for the duration of one scene's declaration passes.
  /// Paired with [popCameraViews] in a `finally` -
  /// `SceneStruct.initializeScene` is the only caller.
  static void pushCameraViews(CameraViewTable table) => _cameraViews.add(table);

  static void popCameraViews() => _cameraViews.removeLast();

  /// The innermost open table, or a `StateError` naming the two ways to get
  /// here: declaring a camera column outside a scene's bring-up, and reaching
  /// the call lazily.
  /// The innermost open table, or null when nothing is being declared.
  ///
  /// Read by `CameraView.of`, which has its own sentence for there being no
  /// table: the one below is written for the *other* caller of this level,
  /// `CameraView.representation`, and the two are refused for different
  /// reasons at different points in a boot.
  static CameraViewTable? get cameraViewsOrNull =>
      _cameraViews.isEmpty ? null : _cameraViews.last;

  static CameraViewTable get cameraViews {
    if (_cameraViews.isEmpty) {
      throw StateError(
        'A camera view column was declared with no scene being brought up. '
        'CameraView.representation reads the table '
        '`SceneStruct.initializeScene` opens around a scene\'s declaration '
        'passes, so the declaration has to happen inside one:\n'
        '  class Eye extends EntityStruct with Transform2D, Camera {}\n'
        'A prefab is constructed by that pass, so its field initialisers are '
        'inside the window. Constructing a prefab directly, to read a field '
        'off it, lands here.\n'
        'A `late final` initialiser lands here as well: it runs on first '
        'read, after the archetype was sealed, so the column would never '
        'reach the row. Field initialisers here are eager, always.',
      );
    }
    return _cameraViews.last;
  }
}
