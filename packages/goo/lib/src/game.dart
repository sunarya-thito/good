import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show ChangeNotifier, VoidCallback, kIsWeb;
import 'package:flutter/widgets.dart' show BuildContext, Widget;
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'package:goo/src/archetype.dart';
import 'package:goo/src/asset.dart';
import 'package:goo/src/camera_view.dart';
import 'package:goo/src/command/command.dart';
import 'package:goo/src/command/param.dart';
import 'package:goo/src/command/transport.dart';
import 'package:goo/src/event.dart';
import 'package:goo/src/event/state.dart';
import 'package:goo/src/handoff_buffer.dart';
import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/game_state.dart';
import 'package:goo/src/handle.dart';
import 'package:goo/src/input.dart';
import 'package:goo/src/input/gamepad.dart';
import 'package:goo/src/input/input_state.dart';
import 'package:goo/src/ring_buffer.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/system.dart';
import 'package:goo/src/triple_buffer.dart';

/*
GameAsset, GameState, and everything simulation-side must be called under our
game isolate. Prefer dart:ffi calloc when running on native platform.

If its on web, we don't use isolate nor ffi - start(inline: true) runs the
GameState on the calling isolate instead.
*/

// Wire tags for the two SendPort control lanes. Strings rather than ints
// because these are rare (bring-up, shutdown, enable/disable, asset decoding)
// and legibility in a stack trace beats a byte. Bulk traffic never goes near a
// SendPort - that is the ring buffer's job.
//
// Three tags used to live here and are gone: `page`, `pagegone` and
// `pagesdropped`, which announced newly allocated pages to main and negotiated
// freeing them again. Main holds no archetypes and resolves no entity, so
// there is nothing on that side for a page to be announced *to*.
const String _msgReady = 'ready';
const String _msgStopped = 'stopped';
const String _msgStop = 'stop';
const String _msgDispose = 'dispose';
// Asset decoding: the game isolate declares assets but cannot decode them (a
// decode needs Flutter), so it asks. Assets are named by their **address** -
// the index `GameAssets` assigns at declare time, which both copies agree on
// because both run the same declarations in the same order. That is already
// the integer a component row stores to point at an asset, so no second
// identity is invented for the wire.
const String _msgLoadAssets = 'loadassets';
const String _msgAssetLoaded = 'assetloaded';
const String _msgAssetsDone = 'assetsdone';
const String _msgUnloadAssets = 'unloadassets';

/// The main-isolate half of a game: **declarations live here**.
///
/// A `Game` declares what a game *is* - its systems, its commands, its
/// buffers, its state channels, its timing - and owns everything that talks
/// to the outside world: the isolate handoff, the command ring's producer
/// end, tick notifications, and the widget tree ([buildWidget]). It runs no
/// simulation itself. That is [GameState]'s job (see [createState]), and the
/// two split cleanly along the isolate boundary:
///
/// ```dart
/// class MyGame extends Game {                      // main isolate
///   late final StateChannel<int> score;            // declared here
///
///   @override
///   MyGameState createState() => MyGameState();
///
///   @override
///   void describeState(StateDescriptor d) => score = d.hasInt32();
/// }
///
/// class MyGameState extends GameState<MyGame> {    // game isolate
///   @override
///   void onMounted() => loadScene(MyScene());
///
///   void onSomething() => game.score.value = 10;   // mutated here
/// }
/// ```
///
/// # Two copies of one object
///
/// This is the one genuinely unusual thing here, and everything below depends
/// on understanding it.
///
/// [start] hands **this instance** to `Isolate.spawn` as the spawn message.
/// Dart deep-copies a plain object graph across that boundary, so what runs
/// on the game isolate is a *second* `MyGame` - same class, same overrides,
/// different identity, different heap. From that moment there are two copies
/// of one object and they do completely different jobs:
///
///  * The **game-isolate copy** is the real one. Its [state] owns the
///    `MemoryPool`, the live `SceneStruct`, and the fixed-tick loop, and it is
///    the only writer of component data and state channels anywhere in the
///    process ([GameState.isSimulating] is true).
///  * The **main-isolate copy** - the one the caller still holds after
///    `await game.start()` - is an inert *handle*. Its systems never tick;
///    its state's scene holds no rows of its own. It exists to (a) send and
///    handle commands ([describeCommands]), (b) receive tick-complete
///    notifications ([addTickListener]) and state-channel updates, (c) build
///    widgets ([buildView]), and (d) resolve `Entity` handles for reading:
///    it re-runs the same `describeScene` so it has the identical archetype
///    layout, and adopts each page the game isolate announces, so
///    `someEntity.get<Transform2D>().x[someEntity]` reads the game isolate's
///    published snapshot directly out of shared memory with no copying.
///
/// Calling a gameplay method on the handle copy does not reach the
/// simulation. Anything that must cross goes through one of exactly two
/// channels, split by volume: bulk, per-tick traffic through a shared
/// `RingBuffer` ([describeCommands], [describeBuffers]), rare control signals
/// through a `SendPort` ([enableSystem], [stop], page announcements, tick
/// pings, state-channel addresses).
///
/// The spawn message is why this class must hold no **unsendable** state when
/// [start] hands it over - but that set is much smaller than it once looked,
/// and getting it wrong in the cautious direction shaped the old design.
///
///  * A `Pointer` **is** sendable, and arrives at the *same address*. Shared
///    native memory crosses for free, which is precisely what lets this class
///    be fully described before the spawn and inherited by the copy. Proven
///    by `tool/spawn_pointer_spike.dart`; an earlier version of this doc
///    claimed the opposite and was wrong.
///  * `Type` objects and **closures** are sendable too
///    (`tool/spawn_registry_spike.dart`).
///  * A `ReceivePort`, a `Completer`, and any native handle (`dart:ui.Image`)
///    are **not**. Dart names the exact field path in the failure, which is
///    worth knowing: it is how the asset-decode gate was found.
///
/// Two things that are *not* about sendability still hold. **Statics do not
/// cross at all** - they belong to no object graph - which is why the
/// registries are captured onto this object and restored on arrival (see
/// `_captureRegistries`). And a **cached typed-data view over native memory
/// is copied by value**, silently detaching from the memory it viewed; never
/// keep one in a field (see `_StateChannelBase.reattach`).
///
/// # Isolate affinity
///
/// `Game` is deliberately **not** a `GameListener`: it lives where Flutter
/// does, and every event in this engine happens on the game isolate. It
/// cannot be `FixedTickable` - the `on GameListener` bound says so at compile
/// time - so put the tick on the [GameState], a `SceneStruct` or a
/// `GameSystem`. What `Game` does for Flutter it does through a plain method,
/// [buildView]. See `GameEvent`'s doc.
abstract class Game {
  // --- configuration ----------------------------------------------------

  /// The simulation step. Wall-clock time accumulates and is spent in whole
  /// multiples of this; systems always see exactly this much elapsed time,
  /// never a variable frame delta.
  Duration get fixedTimeStep => const Duration(microseconds: 16667); // 60 Hz

  /// Spiral-of-death guard: the most fixed steps a single
  /// [GameState.advance] will run before giving up and discarding the rest of
  /// the backlog.
  ///
  /// Without it, a machine that cannot simulate a step in less than
  /// [fixedTimeStep] falls further behind on every frame, and the loop
  /// spends longer and longer catching up - the classic accumulator
  /// failure. Dropping time is the only stable answer: the simulation runs
  /// slower than wall clock rather than locking up.
  int get maxFixedStepsPerAdvance => 5;

  /// Page size for this game's one [MemoryPool], in bytes.
  ///
  /// A page costs **3x** this in native memory - one slot per triple-buffer
  /// state - so the 64 MiB default is ~192 MiB resident per page. Override it
  /// down for a test, a headless server build, or a game whose archetypes are
  /// small enough that a full page would be mostly empty.
  ///
  /// One pool per `Game` rather than per scene: a `SceneStruct` is a
  /// declaration that may back several loaded scenes at once, so it cannot own
  /// the storage they allocate out of. See `SceneStruct.pool`.
  int get pageSize => 64 * 1024 * 1024;

  /// The most pages this game's pool will ever allocate. Exhausting it throws
  /// rather than growing without bound, so a runaway spawn loop reports itself
  /// instead of taking the machine down.
  int get maxPages => 128;

  /// Capacity of **each** command ring buffer. Sized for a burst - a UI frame
  /// that issues a few hundred orders at once must not overflow between two
  /// drains 16ms apart.
  ///
  /// Two rings are allocated with this capacity, one per direction (see
  /// `CommandTransport`), and a batch's whole wire image has to fit in one
  /// record. Nothing is allocated at all in the inline configuration, where
  /// there is no boundary to cross.
  int get commandBufferBytes => 64 * 1024;

  // --- declaration hooks ------------------------------------------------

  /// Builds this game's [GameState] - the simulation-side half. Called once
  /// per isolate, on each copy of this `Game` (see the class doc), so it must
  /// be a pure factory that constructs a fresh state, not a getter returning
  /// a stored one.
  ///
  /// Both copies run it, and both therefore run `GameState.loadScene` and
  /// `describeScene`, which is what makes archetype ids agree across the
  /// isolate boundary: ids are assigned in first-registration order (see
  /// `ArchetypeRegistry`), and the same code registering the same prefabs in
  /// the same order assigns the same ids on both sides. That agreement is
  /// what lets a spawn command name a prefab by integer, and an `Entity`
  /// handle be resolved on the isolate that did not create it.
  ///
  /// Only the copy that owns the simulation ever *ticks* its state; see
  /// [GameState.isSimulating].
  GameState createState();

  // `describeSystems` is **not** here. It is `GameState.describeSystems`.
  //
  // A system exists only on the isolate that ticks it, so the pass that
  // creates one belongs to the object that lives there. It was on this class
  // for a while after the systems themselves moved, on the argument that a
  // `Game` *mixin* had to be able to contribute a system - `Renderer2D`
  // declaring `WorldTransformSystem` and `GameRenderer2D` is what makes
  // `extends Game2D` a single opt-in for 2D rendering. That is a real
  // requirement and it is met a better way now: `Game2D.createState()` narrows
  // its return type to `GameState2D`, so a 2D game that forgets the simulation
  // half does not compile, where before it silently painted nothing.

  /// Declares every [SceneStruct] this game can load.
  ///
  /// ```dart
  /// late final MainScene mainScene;
  /// late final HudScene hudScene;
  ///
  /// @override
  /// void describeScenes(GameSceneDescriptor descriptor) {
  ///   mainScene = descriptor.has(MainScene());
  ///   hudScene = descriptor.has(HudScene());
  /// }
  /// ```
  ///
  /// Like every other declare pass this hands back the instance it was given,
  /// to keep in a `late final` field (RULES.md rule 6) - there is no separate
  /// handle type, and `descriptor.has(MainScene())` reads the same as
  /// `descriptor.has(MySystem())` and `descriptor.has(_Unit())` because it is
  /// the same idea.
  ///
  /// # What declaring buys, and what it does not
  ///
  /// Declaring a scene here **registers its archetypes and declares its
  /// assets, at boot** - before the game isolate is spawned, and before any
  /// system's `describeQuery` runs (which is why this pass comes first).
  /// `GameState.loadScene(game.mainScene)` then costs no registration at all:
  /// it allocates rows and mounts.
  ///
  /// That matters because registration is the half of loading that *cannot*
  /// happen freely at runtime - archetype ids are process-global and never
  /// recycled, so a scene registered afresh on every load would leak ids and
  /// leave every unloaded scene's archetypes in the registry for queries to
  /// keep walking. Declaring once and loading many times is what lets several
  /// instances of one `SceneStruct` be resident at the same time.
  ///
  /// **A `SceneStruct` is a declaration, not a per-instance object** - the
  /// same relationship `EntityStruct` has to `Entity`. Prefab fields on it are
  /// fine; mutable per-instance state is not, because every loaded [Scene]
  /// built from it shares this one object. Per-instance state belongs in
  /// components.
  ///
  /// Passing an *undeclared* scene to `loadScene` still works and still
  /// registers lazily, so this pass is additive rather than a new obligation.
  void describeScenes(GameSceneDescriptor descriptor) {}

  /// Declares every command this game understands, and registers the handlers
  /// that run on the **Flutter** isolate.
  ///
  /// ```dart
  /// late final Damage damage;
  /// late final SaveGame save;
  ///
  /// @override
  /// void describeCommands(CommandDescriptor descriptor) {
  ///   damage = descriptor.has(Damage());   // handled on the game isolate
  ///   save = descriptor.has(SaveGame());
  ///   descriptor.hasSink(save, _writeSaveFile);  // ...but this one here
  /// }
  /// ```
  ///
  /// **Every command is declared here, whichever isolate handles it.** Runs
  /// on both copies, in the same order, which is what makes a command's index
  /// mean the same thing on both sides - the same argument that makes
  /// archetype ids agree. `GameState.describeCommands` runs immediately after
  /// this one and may only *handle* what this pass declared; a command
  /// declared there would have an index on the game isolate and none on the
  /// Flutter one, which is the same as having none.
  ///
  /// Registering the handler *here* is what makes a command run on the
  /// Flutter isolate, so the declaration site is the whole answer to "where
  /// does this execute" and there is no second thing to keep in sync with it.
  /// Because both copies run both passes, the sending side already knows
  /// whether anything will read a command and refuses to send one nothing
  /// handles - no boot-time handshake required.
  ///
  /// # Spawning from the Flutter isolate
  ///
  /// There is no framework spawn command; the first command declared here is
  /// index 0. A HUD button that adds an enemy is the canonical case this lane
  /// exists for, and it is written as a command that says what it *means*:
  ///
  /// ```dart
  /// final class SpawnEnemy extends GameCommand<Vector2, Entity> { ... }
  ///
  /// // ...and handled in GameState.describeCommands, where the scene is:
  /// descriptor.hasHandler(game.spawnEnemy, (at) {
  ///   final enemy = sceneHandle!.addEntity(level.enemy);
  ///   level.enemy.x[enemy] = at.x;
  ///   return enemy;
  /// });
  /// ```
  ///
  /// A built-in `spawnEntity(archetypeId)` used to sit here and was deleted: an
  /// archetype id is a game-isolate identifier, so handing one to the Flutter
  /// isolate made it name something it cannot see. Naming the *intent* leaves
  /// the prefab lookup on the side that owns the memory.
  void describeCommands(CommandDescriptor descriptor) {}

  /// Declares this game's **auxiliary ring buffers** - shared-memory SPSC
  /// channels, allocated on the simulating copy and handed to the other one
  /// the same way the command ring and the pool's pages already are.
  ///
  /// `goo` knows nothing about what travels through them. The command ring
  /// ([dispatchCommand]) is the framework's own, hardcoded, main -> game
  /// lane; this is the generic escape hatch for every *other* lane-2-shaped
  /// channel a layer above wants - the one that motivated it is
  /// `goo2d_render`'s per-tick draw-command buffer (game -> main), which
  /// must not put a Flutter- or renderer-specific field on this class.
  ///
  /// Each declaration returns a [BufferHandle] the declarer keeps in a field
  /// (RULES.md rule 6) - there are no buffer names and nothing to look up:
  ///
  /// ```dart
  /// late final BufferHandle drawBuffer;
  ///
  /// @override
  /// void describeBuffers(BufferDescriptor d) {
  ///   drawBuffer = d.has(capacityBytes: 64 * 1024);
  /// }
  /// ```
  ///
  /// **Direction is the declaring subsystem's business, not this class's.**
  /// A `RingBuffer` is single-producer/single-consumer: exactly one isolate
  /// may call `tryWrite` on a given buffer and exactly one may call
  /// `drainInto`. Both copies of the `Game` get a view of the same memory
  /// (see the class doc's "Two copies of one object"); which end does what
  /// is a convention between the two halves of whoever declared it.
  ///
  /// Runs on both copies, like every other `describe*` pass, so both agree
  /// on the declared set *and on its order* - which is the handle's identity
  /// on the wire. Systems may declare buffers too - see
  /// `GameSystem.describeBuffers`; declaring a system is then all a user has
  /// to do to get that system's channel wired up.
  void describeBuffers(BufferDescriptor descriptor) {}

  /// Declares this game's camera views - the places it can be drawn.
  ///
  /// ```dart
  /// late final CameraView mainCamera;
  ///
  /// @override
  /// void describeCameras(CameraDescriptor descriptor) {
  ///   mainCamera = descriptor.has();
  /// }
  /// ```
  ///
  /// Runs **before** [describeBuffers], and that ordering is what the split
  /// of responsibility rests on: `goo` knows a view exists and how big it is,
  /// while whatever draws it (`goo2d`'s renderer, a future `goo3d`'s) sizes
  /// and allocates its own per-view storage in its `describeBuffers`. This
  /// kernel never learns what a frame is.
  ///
  /// A game that declares none draws nothing and is shown with
  /// `GameView.headless` - a HUD-only or headless-plus-Flutter setup, which
  /// is a first-class shape here rather than a degenerate one.
  void describeCameras(CameraDescriptor descriptor) {}

  /// This game's declared camera views. Empty until [describeCameras] has
  /// run; both isolate copies see the same table, because it rides the deep
  /// copy like every other piece of declared state.
  final CameraViewTable cameraViews = CameraViewTable();

  /// Declares this game's **published state**: small, fixed-width values the
  /// game isolate writes and the main isolate reads straight out of shared
  /// memory.
  ///
  /// ```dart
  /// class MyGame extends Game {
  ///   late final StateChannel<int> score;
  ///
  ///   @override
  ///   void describeState(StateDescriptor descriptor) {
  ///     score = descriptor.hasInt32();
  ///   }
  /// }
  /// ```
  ///
  /// This is the "one scalar value, read by the UI" lane, and it is
  /// deliberately *not* any of the three that already exist:
  ///
  ///  * component data (lane 1) is per-entity and lives in the pool's pages;
  ///  * commands and their rings (lane 2) are bulk, and run both ways;
  ///  * `SendPort` control messages (lane 3) are rare and unordered relative
  ///    to ticks.
  ///
  /// Published state is one value, coherent per tick, with no per-read message
  /// and no string-keyed lookup: the descriptor hands back a typed
  /// [StateChannel] you keep in a `late final` field, exactly like
  /// `describeStruct`'s `DataPointer`s, `describeQuery`'s `Query`,
  /// and `describeBuffers`' `BufferHandle`.
  ///
  /// # The two hosts, and why it is a plain override
  ///
  /// Exactly two types declare state - this one and `GameSystem` - and both
  /// carry this method with an empty body, so declaring a channel is one
  /// override and nothing else. There used to be a `Publisher` mixin with a
  /// `Structured` marker interface as its bound, whose only job was to stop
  /// the mixin landing somewhere it made no sense. Guarding a set of known
  /// classes that each already have the method is ceremony that buys nothing,
  /// and the marker leaked: anything that implemented `Structured` for
  /// unrelated reasons - a `GameCommandBase`, of all things - silently became
  /// a legal `Publisher` host, despite a command having no stable declaration
  /// index for a channel to hang off.
  ///
  /// The set is two and not more for a hard reason: **a channel's storage is
  /// allocated on the main isolate, before the spawn**, and its identity
  /// across the boundary *is* its declaration index in that one pass. So only
  /// something main declares can own an index. That rules out three things,
  /// each for its own reason:
  ///
  ///  * [GameState] is *built on the game isolate*, after the allocation it
  ///    would have to be part of. It used to be a third host, back when main
  ///    ran `createState()` too. Publish from the `Game` and write through
  ///    `state.game.myChannel`.
  ///  * a `SceneStruct` is loaded after boot and possibly several times, so it
  ///    could never hold a stable index;
  ///  * a `Component` comes and goes with the scene, for the same reason.
  ///
  /// Publish scene-derived values from a `GameSystem`, which outlives the
  /// scene and is where the per-tick work already is.
  ///
  /// Runs **once**, on main, during [start], before the spawn - so the game
  /// isolate inherits the channels already numbered and already backed, and
  /// there is no second run for an index to disagree with. Both sources share
  /// **one** descriptor (see [bootStateDescriptor]), so indices never collide
  /// or renumber across sources.
  void describeState(StateDescriptor descriptor) {}

  /// Declares this game's **input actions**, and the default value every
  /// action of a given type falls back to.
  ///
  /// Runs first in the boot pass's `describeInputs` sequence, before every
  /// declared system's (see `GameSystem.describeInputs`), and all of them
  /// share one [InputDescriptor] - so a type-level default registered by any
  /// source is visible to every action, whoever declared it and in whatever
  /// order.
  ///
  /// # The shipped defaults, and why `super` is not optional
  ///
  /// The implementation here registers `false` for `bool` and
  /// `Vector2.zero()` for `Vector2`, which is what makes `TriggerBinding` and
  /// `Vec2Binding` work with no ceremony. It is [mustCallSuper] because
  /// dropping them is a *silent* failure: nothing breaks at declaration
  /// time, and the game runs until the first read of an unbound action, which
  /// then throws instead of returning `false`. An override that adds a
  /// default for its own type looks like this:
  ///
  /// ```dart
  /// @override
  /// void describeInputs(InputDescriptor input) {
  ///   super.describeInputs(input);
  ///   input.hasDefaultValue<double>(0);
  ///   throttle = input.has<double>();
  /// }
  /// ```
  ///
  /// # Where the values come from
  ///
  /// Raw key and mouse-button state is collected on the Flutter isolate (see
  /// `InputDevice`) and resolved on the game isolate, once per fixed tick.
  /// A game with no `GameView` in the widget tree has nothing feeding it, so
  /// every action reads its default forever - correct rather than broken, and
  /// spelled out in `InputDevice`'s doc.
  @mustCallSuper
  void describeInputs(InputDescriptor input) {
    input.hasDefaultValue<bool>(false);
    input.hasDefaultValue<Vector2>(Vector2.zero());
  }

  // --- state ------------------------------------------------------------
  //
  // Every field here is null/empty/false at spawn time and gets populated by
  // _boot on whichever isolate the copy landed on. That is a hard
  // requirement, not an accident: this whole object is the spawn message.

  // No system list here. `describeSystems` is declared on this class and runs
  // in [_bootGame]; the objects it produces are held by the `GameState`, on
  // the isolate that ticks them.

  final List<void Function(int tick)> _tickListeners =
      <void Function(int tick)>[];

  // Every SceneStruct declared through [describeScenes], in declaration order.
  // Holding them is what keeps their archetypes registered for the life of the
  // game rather than only for the life of one load.
  final List<SceneStruct> _declaredScenes = <SceneStruct>[];

  // Every auxiliary buffer declared through a describeBuffers pass this boot,
  // in declaration order. The handle object *is* the declaration and *is* the
  // live view: it carries its declared capacity from the moment it is
  // created on either copy, and gains its RingBuffer when the simulating copy
  // allocates or the handle copy adopts. One list, addressed by index -
  // which, because both copies run the same passes in the same order, is the
  // buffer's identity on the wire.
  final List<BufferHandle> _bufferHandles = <BufferHandle>[];

  // Handoff buffers, same story as the rings above and a separate index space.
  // Kept apart rather than in one list because they are different primitives
  // for different shapes of traffic - a queue where every record matters
  // versus a value where only the newest does.
  final List<HandoffHandle> _handoffHandles = <HandoffHandle>[];

  // Every channel declared through a `describeState` pass this
  // boot, in declaration order across both declaring sources (see
  // [bootStateDescriptor]). Same index-is-identity story as the buffers.
  final List<_ChannelSlot> _stateChannels = <_ChannelSlot>[];

  // Every input action declared through a describeInputs pass this boot, plus
  // the type-level defaults and the one raw device-state buffer they all
  // resolve against. Unlike the buffers and channels above, an action's index
  // is *not* a wire identity - what crosses the boundary is the fixed-size
  // block of raw key bits, which is the same 16 bytes whatever a game
  // declares. Both copies still run the same passes, because a system's
  // main-isolate twin has to hold the same handles its game-isolate twin
  // does. Empty at spawn time like every other field here.
  final InputRegistry _inputs = InputRegistry();

  GameState? _state;
  _StateDescriptor? _bootStates;

  // The declared command list, and the thing that carries batches of them
  // between the copies. Both are built in _boot and live as long as the Game;
  // null only before start() (and again, for the transport's rings, after
  // stop()).
  CommandRegistry? _commands;
  CommandTransport? _commandTransport;

  // The two command rings. Each is single-producer/single-consumer, so there
  // is one per direction rather than one shared lane - see CommandTransport.
  // Both are allocated by, and belong to, the copy that owns the simulation;
  // the handle copy only ever holds views. Null in the inline configuration,
  // where nothing crosses a boundary.
  RingBuffer? _commandsToGame;
  RingBuffer? _commandsToMain;
  bool _ownsCommandRings = false;

  /// This game's assets - **instance state, not a global static**.
  ///
  /// It lives here for two reasons. Architecturally, an asset's payload lives
  /// on the *main* isolate the way a draw call lives on the game isolate: main
  /// owns the decoded image or audio, the game isolate holds a payload-free
  /// declaration (its address and declared metadata) and emits draw calls that
  /// name the address, and main resolves it at draw time. Mechanically, static
  /// state does **not** cross `Isolate.spawn` - it belongs to no object graph -
  /// so a static registry has to be hand-carried and restored, while instance
  /// state on this object rides the deep copy for free.
  ///
  /// Both copies end up with their own table at identical addresses; only
  /// main's ever holds bytes. See `GameState.closeAssetGate` for why the copy
  /// must be taken before any decode begins.
  final GameAssets assets = GameAssets();

  // One flag used to answer four questions - who allocates, who frees, who
  // may write a state channel, and who ticks. They coincided only because the
  // game isolate did all four. Now that boot runs on main *before* the spawn,
  // they genuinely differ and are two flags:
  //
  //   _owns      - this copy allocated the shared native memory and frees it.
  //                Main, in the spawned configuration.
  //   _simulates - this copy runs the tick loop, and is therefore the single
  //                writer of component data and state channels. The game
  //                isolate.
  //
  // Inline sets both. Neither is public: the user-facing spelling of the
  // second is `GameState.isSimulating`, and these are here only because
  // several bring-up steps need them before or without a state.
  //
  // A `TripleBuffer` requires one *writer*, not a particular isolate, which is
  // what makes allocate-here/write-there legal at all. `InputDevice` has
  // always been the mirror image of this (game isolate allocated, main wrote).
  bool _simulates = false;
  bool _owns = false;
  bool _inline = false;
  bool _booted = false;
  int _tick = 0;

  // Game-isolate copy only.
  SendPort? _toMain;
  ReceivePort? _control;

  // Asset loads this copy has asked main to perform and is still waiting on,
  // by request id. Populated only after the spawn, which is what makes the
  // `Completer` inside each one safe to hold here: `_stopping` below is the
  // same shape for the same reason (a Completer reachable from this object at
  // spawn time would make the message unsendable).
  int _assetRequestId = 0;
  final Map<int, _AssetLoadRequest> _assetRequests = <int, _AssetLoadRequest>{};

  // Main-isolate handle copy only.
  ReceivePort? _fromGame;
  SendPort? _toGame;
  Completer<void>? _stopping;

  /// Whether [start] has run on this copy.
  bool get isRunning => _booted;

  /// Fixed ticks completed. On the handle copy this tracks the last tick
  /// number the game isolate reported, so it lags reality by one message.
  int get tick => _tick;

  /// This copy's simulation half, for the engine's own use.
  ///
  /// **There is deliberately no public `state` getter.** It existed, and it
  /// was the shape that let a caller reach the simulation from the
  /// presentation isolate: it compiled everywhere and answered usefully in one
  /// configuration, which is the worst combination. Reaching the world is
  /// `InlineGameHandle.state`, and that type is only ever handed to a caller
  /// who asked for the single-isolate configuration.
  @internal
  GameState? get stateOrNull => _state;

  /// How many auxiliary buffers this copy has declared - see
  /// [describeBuffers]. Both copies run the same passes, so this agrees
  /// across the isolate boundary, and a buffer's index in `0..bufferCount` is
  /// what identifies it on the wire.
  int get bufferCount => _bufferHandles.length;

  /// How many [StateChannel]s this copy has declared - see
  /// [bootStateDescriptor]. Same index-is-identity story as [bufferCount].
  int get stateChannelCount => _stateChannels.length;

  /// How many input actions this copy has declared - see [describeInputs].
  int get inputActionCount => _inputs.actionCount;

  /// Where raw device state is written, on the copy that has Flutter
  /// attached - the single copy under `start(inline: true)`, or the handle
  /// copy in the spawned configuration. Null on the game-isolate copy, which
  /// only ever reads input.
  ///
  /// [GameView] feeds this automatically. It is public because a headless
  /// host with no widget tree - a test, a replay, a bot - legitimately needs
  /// to write input, and the alternative would be a second write path that
  /// only tests use (RULES.md rule 8). Null before `start()` and after
  /// `stop()`.
  InputDevice? get inputDevice => _inputs.device;

  /// Turns connected gamepads into [inputDevice] writes. Same lifetime and
  /// same nullability as the device, for the same reasons.
  ///
  /// [GameView] attaches and detaches it with the widget, so a game that is
  /// on screen reads pads and a game that is not holds no OS subscription.
  /// Its deadzones are settable: `game.gamepads?.stickDeadzone = 0.3`.
  GamepadCollector? get gamepads => _inputs.gamepads;

  /// The `GameView`'s size in logical pixels, as of the last input
  /// resolution - or zero when there is no widget showing this game.
  ///
  /// It arrives through the input block because that is the channel that
  /// already runs Flutter-isolate -> game-isolate; it is not an input action
  /// and nothing binds to it. A renderer needs it to know where the middle of
  /// the view is (see `GameRenderer2D`'s camera handling), which is the one
  /// question about the view a simulation legitimately has.
  ///
  /// Zero is the honest answer for a headless game rather than a guessed
  /// resolution, and it is load-bearing: every consumer of these treats a
  /// zero view as "no view", which is what makes a headless test and a real
  /// window agree about everything except the centring they cannot share.
  /// The surface the **pointer** is currently in: refreshed by the `GameView`
  /// the cursor is over, and falling back to whichever view last laid out
  /// before any pointer has moved.
  ///
  /// **Not a camera viewport.** For projecting world to screen - or screen
  /// back to world - use `CameraView.viewportWidth`/`viewportHeight`, which
  /// belong to a specific view and are what `CameraProjection` centres on.
  /// These two exist because `MousePosition` reports in one surface's
  /// coordinates and a pointer is only ever in one surface at a time, which
  /// is a coherent single fact; a *viewport* is not, once there are two
  /// views.
  ///
  /// Zero is the honest answer for a headless game rather than a guessed
  /// resolution.
  double get viewWidth => _inputs.state.viewWidth;

  double get viewHeight => _inputs.state.viewHeight;

  /// The [CameraView] the pointer is currently over, or null when it is over
  /// none - no `GameView` is showing one, or the position was driven without
  /// naming a view.
  ///
  /// This is what makes picking correct with several views on screen: a
  /// pointer is over exactly one of them, and only the widget knows which, so
  /// the widget says so and the game isolate reads it here.
  CameraView? get pointerView {
    final address = _inputs.state.pointerView;
    if (address < 0 || address >= cameraViews.length) return null;
    return cameraViews[address];
  }

  /// The **one** `StateDescriptor` shared by every `describeState` pass in
  /// the current [_boot] call.
  ///
  /// One instance per boot, not one per declaring source, because a
  /// channel's identity across the isolate boundary is its declaration
  /// index: five independent descriptors would each start numbering at zero
  /// and a channel declared by a `GameSystem` would collide with one
  /// declared by the `Game`. Sharing one also means adding or removing a
  /// declaration anywhere renumbers everything after it *identically on both
  /// copies*, which is the only property that actually has to hold.
  ///
  /// Internal because it is a boot-pass detail: every call site is inside
  /// [_boot] - the two `describeState` call sites are the Game's own and each
  /// declared GameSystem's, and nothing else declares a channel at all (see
  /// [describeState]).
  @internal
  StateDescriptor get bootStateDescriptor {
    final states = _bootStates;
    if (states == null) {
      throw StateError(
        '$runtimeType is not in a boot pass - there is no StateDescriptor to '
        'declare against. describeState() runs exactly once per isolate '
        'copy, from Game.start(); a state channel cannot be declared at '
        'runtime (its storage is allocated and announced at bring-up).',
      );
    }
    return states;
  }

  // --- bring-up ---------------------------------------------------------

  /// Brings the game up.
  ///
  /// With [inline] false (the default off web) this spawns the game isolate,
  /// waits for it to report its command ring buffer, and leaves this copy as
  /// the handle described in the class doc. With [inline] true there is only
  /// ever **one** copy: the [GameState] is constructed on the calling isolate
  /// and does both jobs, with no spawn and no shared-memory handoff.
  ///
  /// [inline] defaults to [kIsWeb], because that is the whole of the
  /// platform question: web has neither isolates in the shared-memory sense
  /// nor FFI, so it runs the state inline; native always spawns. It stays a
  /// parameter rather than becoming an internal detail because a test (and a
  /// headless host) wants the inline path on native too.
  ///
  /// With [autoTick] false nothing ticks until someone calls
  /// [GameState.advance] (or [GameState.runFixedStep]) by hand - which is
  /// what makes the scheduler testable deterministically, with no timer and
  /// no wall clock involved. Note that in the spawned configuration the only
  /// code that *could* drive it by hand runs on the game isolate, so
  /// `inline: false, autoTick: false` is a game that never ticks; the knob is
  /// really for the inline path.
  ///
  /// The ordering inside the spawning path is load-bearing, and it is the
  /// **reverse** of what it once was. [_bootMain] runs *before*
  /// `Isolate.spawn`, so the object handed over is fully described - every
  /// system, buffer, channel, camera view and command, plus the native memory
  /// they point at. The spawned copy re-derives none of it; it adds the half
  /// that could only ever have been its own ([_bootGame]) and starts ticking.
  ///
  /// What may not be reachable from `this` at spawn time is the genuinely
  /// unsendable: the `ReceivePort` is created after [_bootMain] and stored in
  /// a field only *after* the spawn. A decoded asset (`dart:ui.Image`) used to
  /// need a gate here for the same reason; it does not any more, because
  /// nothing decodes until a scene is loaded and no scene is loaded until
  /// [_bootGame] runs on the far side. A `Pointer` is fine - see the class doc.
  ///
  // TODO(game-handle): this becomes `@internal`, and the user-facing entry
  // point becomes the statics `Game.start(MyGame())` -> `GameHandle<G>` and
  // `Game.startInline(MyGame())` -> `InlineGameHandle<G>` (see handle.dart,
  // which already carries both types and their implementations). A static and
  // an instance method cannot share a name in Dart, so the two cannot coexist
  // during the migration - the statics land in the same change that retargets
  // every `game.start(...)` / `game.stop()` / `game.state!` call site, and
  // `Game.state` is deleted in the same breath.
  /// Brings [game] up and hands back the main-isolate handle for it.
  ///
  /// ```dart
  /// final run = await Game.start(MyGame());
  /// final score = run.game.score;   // a StateChannel, for a widget
  /// await run.stop();
  /// ```
  ///
  /// A static rather than an instance method because a `Game` is a
  /// *description*, not a running thing: starting one produces something else,
  /// the way `runApp` does with a widget. What comes back cannot reach the
  /// simulation - see [GameHandle]. Use [startInline] when you need to.
  ///
  /// On the web this runs the single-isolate implementation, because there are
  /// no isolates in the shared-memory sense there, but still types the result
  /// as a `GameHandle` - so a web game gets the same surface as a native one
  /// rather than depending on the state happening to be reachable.
  static Future<GameHandle<G>> start<G extends Game>(
    G game, {
    bool autoTick = true,
  }) async {
    if (kIsWeb) {
      await game.bootUp(inline: true, autoTick: autoTick);
      return SingleIsolateGameHandle<G>(game, game._state!);
    }
    await game.bootUp(inline: false, autoTick: autoTick);
    return IsolateGameHandle<G>(game);
  }

  /// Brings [game] up **on the calling isolate** - one copy doing both jobs -
  /// and hands back a handle that can reach the simulation.
  ///
  /// For tests, headless hosts, replays and tools. `autoTick: false` (the
  /// default here) leaves the clock entirely to [InlineGameHandle.advance],
  /// which is what makes the scheduler testable with no timer and no wall
  /// clock involved.
  ///
  /// **At most one inline run per isolate.** Statics are per-isolate, and
  /// `ArchetypeRegistry` is one of them: a second inline run would find the
  /// first run's `ArchetypeStorage` for any prefab type they share, bound to
  /// the first run's `MemoryPool`, and spawn into its memory. Concurrent runs
  /// are supported by [start], which gives each one its own isolate - and are
  /// therefore not available on the web.
  static Future<InlineGameHandle<G>> startInline<G extends Game>(
    G game, {
    bool autoTick = false,
  }) async {
    await game.bootUp(inline: true, autoTick: autoTick);
    return SingleIsolateGameHandle<G>(game, game._state!);
  }

  // Not `@internal` yet, and only because not every call site has moved to the
  // statics above. See the TODO(game-handle) above.
  Future<void> bootUp({bool? inline, bool autoTick = true}) async {
    if (_booted) {
      throw StateError('$runtimeType is already running.');
    }
    if (inline ?? kIsWeb) {
      _booted = true;
      _inline = true;
      // No command rings: there is no boundary to cross, so a batch is run by
      // the copy that built it (see `CommandTransport`). Allocating 128 KiB of
      // native memory for two lanes that would carry nothing is the kind of
      // thing that only shows up on web, where this is the *only* path.
      //
      // Both halves, back to back, on the one copy that does both jobs.
      _bootMain(owns: true, simulates: true);
      _bootGame();
      if (autoTick) _state!.startTimer();
      return;
    }

    // Everything this copy declares, and every byte of shared memory,
    // **here, before the spawn**. It does not simulate, so it stops here: no
    // scene is registered and no world exists on this isolate at all.
    _bootMain(owns: true, simulates: false);
    _booted = true;

    final ready = Completer<void>();
    final fromGame = ReceivePort();
    // The subscription's closure - not a field - holds `ready`: a ReceivePort
    // reachable from `this` at spawn time is still unsendable, which is the
    // one part of the old ordering rule that survives.
    fromGame.listen((message) => _handleGameMessage(message, ready));

    // `this` is fully described by now, pointers and all, and that is fine:
    // `Pointer` is sendable and arrives at the same address, so the spawned
    // copy sees the same native memory with no handshake. Verified by
    // `tool/spawn_pointer_spike.dart`.
    await Isolate.spawn<List<Object>>(_gameIsolateEntryPoint, <Object>[
      this,
      fromGame.sendPort,
      autoTick,
    ]);

    _fromGame = fromGame;
    // `ready` is sent *after* the game isolate has run `_bootGame`, so by the
    // time this returns the world exists: scenes registered, entities spawned,
    // queries compiled. Only asset decoding is still in flight, and that is
    // what `loadScene`'s future is for.
    await ready.future;
  }

  /// Everything the **main isolate** declares and allocates, before the spawn.
  ///
  /// The dividing line is not "what could run here" - the deep copy would let
  /// almost anything run on either side - it is **who has to hold the result**
  /// and **who has to own the memory**:
  ///
  ///  * a `StateChannel`, a `BufferHandle`, a `HandoffHandle` and a
  ///    `CameraView` are all backed by native memory that this copy allocates
  ///    and frees, and their identity on the wire is their index in one
  ///    declaration pass. Both facts point here: allocation cannot happen
  ///    before the declaration, and the game isolate must inherit the numbering
  ///    rather than re-derive it.
  ///  * `describeSystems` stays here too, and that one is worth stating because
  ///    an earlier plan had it moving. A `Game` *mixin* declares systems -
  ///    `Renderer2D.describeSystems` brings `WorldTransformSystem` and
  ///    `GameRenderer2D` with it, which is what makes `extends Game2D` the
  ///    whole opt-in - and a mixin on `Game` cannot contribute to a pass that
  ///    lives on `GameState`. Main also genuinely holds system handles:
  ///    `Renderer2D` reaches its renderer through `getSystem` every frame to
  ///    find the buffer to drain.
  ///
  /// What that leaves on the game isolate is [_bootGame]: the things that
  /// register into **process-global statics** (archetypes, component bits) and
  /// the things that only exist there at all (the loaded scenes).
  ///
  /// Split up so each body is short enough to read end to end, which is not a
  /// style preference here - this sequence is order-dependent in ways the
  /// analyzer cannot check, and it has already silently lost a pass to an edit
  /// whose anchor spanned the adjacent line. Re-read the phase you touched, in
  /// full, after touching it.
  void _bootMain({required bool owns, required bool simulates}) {
    _owns = owns;
    _simulates = simulates;

    // One StateDescriptor for the whole pass, built before anything can
    // declare against it - see [bootStateDescriptor] for why it must be
    // shared rather than one per source.
    final states = _StateDescriptor(this);
    _bootStates = states;

    // Constructed here, and *only* constructed: its `onMounted` - the pass
    // that loads scenes and so spawns a world - runs in [_bootGame], on the
    // other copy. This one is a declaration mirror, exactly like a
    // `GameSystem`'s main-side twin: it exists so that `describeCommands`
    // below can register the same command handlers in the same order on both
    // copies, and it never simulates, never mounts and never holds a scene.
    final state = createState();
    _state = state;
    state.bindGame(this, simulating: simulates);

    // --- describeState, call sites 1..2 ----------------------------------
    //
    // Resulting declaration order, which *is* channel-index order and is
    // therefore observable (an index is what crosses the wire):
    //
    //   1. the Game's own
    //   2. every declared GameSystem, in post-_sortSystems order
    //
    // Two sources and no more, and the constraint is sharper than "exists for
    // the whole run": a channel's storage is allocated here, on main, before
    // the spawn, so only something this pass runs can own an index. The
    // `GameState` used to be a third call site and is not any more - its
    // `onMounted` runs on the other copy, after this allocation. Scenes and
    // their prefabs were dropped earlier for the neighbouring reason (loaded
    // after boot, possibly repeatedly). See [describeState].
    //
    // Systems come last only because their declarations do not exist until
    // describeSystems has run.
    describeState(states);

    // Before describeBuffers, deliberately: a 2D renderer declares one frame
    // buffer *per declared view*, so the views have to exist by the time
    // anything is asked what storage it needs.
    describeCameras(GameCameraDescriptor(this, cameraViews));
    describeBuffers(_BufferDescriptor(this));
    // The framework's own shipped hasDefaultValue<bool>/<Vector2> are
    // registered here, before any system can declare an action that needs
    // them. (Not that the order actually matters for *reading* a default -
    // defaults are matched to actions at seal(), once every source has spoken
    // - but a duplicate registration should name the source that came second,
    // and that reads better when the framework's own is first.)
    _inputs.source = '$runtimeType';
    describeInputs(_inputs);

    if (owns) _bootAllocate();
    _bootFinalize(simulates);
  }

  /// Everything the **game isolate** declares, after the spawn.
  ///
  /// Two kinds of thing, and both are here for the same underlying reason -
  /// they touch state that does **not** cross `Isolate.spawn`:
  ///
  ///  * [describeScenes] registers archetypes and component bits into
  ///    `ArchetypeRegistry`/`ComponentTypeRegistry`, which are *statics*.
  ///    Statics belong to no object graph, so they do not ride the copy. They
  ///    used to be hand-carried across in a snapshot precisely because this
  ///    pass ran on main; running it here instead is what deleted that
  ///    machinery, along with main's page adoption and the un-adopt handshake.
  ///    One registrar means there is no second numbering to keep in agreement.
  ///  * `describeQuery` resolves against those archetypes, so it has to follow
  ///    them - which is why it is not up in [_bootMain] with the rest of the
  ///    per-system passes. Queries are read only by ticking systems, and only
  ///    this copy ticks.
  ///
  /// Inline runs this immediately after [_bootMain], on the one copy that does
  /// both jobs.
  void _bootGame() {
    final state = _state!;

    // Scenes before systems, and it has to be that way round: a system's
    // `describeQuery` resolves against registered archetypes, and registering
    // them is exactly what declaring a scene does.
    describeScenes(_GameSceneDescriptor(this));

    // Declared and held by the state, so the system objects only ever exist on
    // this copy.
    state.describeSystems(_SystemDescriptor(state));
    state.sortSystems();

    final queries = ArchetypeQueryDescriptor();
    final systems = state.declaredSystems;
    for (var i = 0; i < systems.length; i++) {
      final system = systems[i];
      system.bindState(state);
      system.describeQuery(queries);
      _inputs.source = '${system.runtimeType}';
      system.describeInputs(_inputs);
    }
    // Closes the input declaration window, and matches each action with the
    // type-level default that applies to it - which cannot happen any earlier
    // because the *last* system's describeInputs may be what registers it.
    //
    // On this copy only. Main declared the `Game`'s own actions in [_bootMain]
    // and never seals, because a system's declarations are not there to be
    // sealed against: an action is resolved against the raw input block by the
    // copy that ticks, and main only ever *writes* that block.
    _inputs.seal();

    // --- events: declare, then collect ---------------------------------
    //
    // Two passes, and the order is the whole design. `describeEvents` creates
    // every dispatcher; `collectListeners` then walks the composition once and
    // fills them. After this, dispatching an event is an indexed loop over a
    // list that is already correct - the walk that used to happen per event,
    // at runtime, testing every candidate, has happened exactly once.
    //
    // Runs after the scenes and systems are declared, because those are what
    // there is to collect - and on this copy only, because dispatching an
    // event is a simulation act. Main's `GameState` and system twins keep
    // their dispatchers unbound and never fire one.
    _bindEvents();

    // The world itself. `onMounted` is where a game calls `loadScene`, so this
    // is the line that brings a scene into being - all of it, on one copy.
    // There is no longer a declarative half on main to leave undone.
    state.mount();
  }

  /// Phase 2: shared memory, on the copy that owns it.
  ///
  /// Runs after **every** declaration source has spoken, which is the earliest
  /// point at which the sizes are known - and still well before the spawn, so
  /// both copies see live storage from their first tick.
  void _bootAllocate() {
    // Allocated here rather than next to the command ring in [_runOnIsolate]:
    // the declarations only exist once describeSystems has run, and this is
    // the first point at which every declaration source has been seen. It is
    // still comfortably early - _boot() finishes before the game isolate
    // sends `ready`, which is before mount() and before the tick timer
    // starts, so a buffer exists on both sides before any system could write
    // to it. The handle copy allocates nothing; it adopts (see _msgBuffer).
    {
      // The two command rings, unless this is the single-copy configuration -
      // inline crosses no boundary, so a batch is run by the copy that built
      // it and 128 KiB of native memory would carry nothing. Allocated here
      // rather than on the game isolate (where they used to live) because
      // this copy boots first now, and the addresses ride the spawn.
      if (!_inline) {
        _commandsToGame = RingBuffer(commandBufferBytes);
        _commandsToMain = RingBuffer(commandBufferBytes);
        _ownsCommandRings = true;
      }
      for (var i = 0; i < _bufferHandles.length; i++) {
        final handle = _bufferHandles[i];
        handle._ring = RingBuffer(handle.capacityBytes);
      }
      // Nothing to announce afterwards: the `Pointer`s inside cross the spawn
      // at the same addresses, so the copy inherits a working view.
      for (var i = 0; i < _handoffHandles.length; i++) {
        final handle = _handoffHandles[i];
        handle._buffer = HandoffBuffer(handle.slotBytes);
      }
      // Two floats per view, for the same reason and at the same moment: the
      // widget writes the viewport size on this side and the renderer reads
      // it on the other, so it cannot be a Dart field on an object that rode
      // the spawn.
      cameraViews.allocate();
      // Same point in the sequence, same reasoning, plus one extra step: a
      // TripleBuffer reports nothing published until its first publish()
      // (latestView() is null, hasPublished false), and a StateChannel must
      // never let a reader observe that. So the declared initial value goes
      // out immediately, here - which is also the entire single-copy
      // (inline) story, since there is no second copy to announce to and
      // this one both writes and reads its own channels.
      for (var i = 0; i < _stateChannels.length; i++) {
        _stateChannels[i].allocateAndSeed();
      }
      // And the raw input block, on the same schedule and for the same
      // reason: the copy that owns the simulation owns every shared
      // allocation, so there is one place that frees them. Input is the only
      // one whose *writer* is the other copy - see InputDevice - which
      // changes nothing about who allocates.
      _inputs.allocate();
      // Inline: this same copy is the one Flutter runs on, so it owns both
      // ends. In the spawned configuration the handle builds its device when
      // the announcement lands (see _msgInput), and this copy never has one.
      if (decodesAssets) _inputs.createDevice();
    }
  }

  /// Phase 3: commands, event binding, and closing the declaration window.
  void _bootFinalize(bool simulates) {
    final states = _bootStates!;
    final state = _state!;

    // --- describeCommands, both call sites ------------------------------
    //
    // Same index-is-identity story as the buffers and channels above, and the
    // same reason both copies run both passes: a command's position in this
    // shared declaration order is what a record's header carries and what
    // routes it back to the right command on the other side.
    //
    // The framework declares none of its own, so index 0 is the game's first
    // command. There used to be a built-in `SpawnEntityCommand` here, and it
    // was deleted rather than moved: it took an `archetypeId`, which is a
    // game-isolate identifier main has no business naming. A game that wants
    // main-triggered spawning declares a command that says what it *means*
    // ("spawn an enemy at x,y") and resolves it to a prefab in its own
    // handler, where the scene actually lives.
    final transport = CommandTransport();
    final commands = CommandRegistry(
      transport,
      simulating: simulates,
      inline: _inline,
    );
    transport.registry = commands;
    _commands = commands;
    _commandTransport = transport;

    // The Game declares (and may handle on the Flutter isolate); the
    // GameState may only handle, on the game isolate. Order matters only in
    // that declaration has to precede handling, which this guarantees.
    describeCommands(MainCommandDescriptor(commands));
    state.describeCommands(GameCommandDescriptor(commands));
    commands.seal();
    // Attaches whichever rings this copy already has. Inline has none; the
    // game isolate allocated both in _runOnIsolate before calling this; the
    // handle copy has none yet and attaches again when `ready` lands.
    _attachCommandRings();

    // The declaration window is closed. Anything holding on to the
    // descriptor past this point is trying to declare a channel at runtime,
    // which cannot work - its storage would exist on neither copy and its
    // index would not match the other side's.
    states._seal();
    // `_inputs.seal()` is deliberately *not* here: a system may still declare
    // an action, and systems are declared on the game isolate. It closes at
    // the end of [_bootGame] instead.
    _bootStates = null;
  }

  /// Binds events for the `GameState`, every declared system, and every
  /// declared scene with its prefabs.
  ///
  /// Runs after **all** the declaration passes, and that ordering is
  /// load-bearing: a prefab's `collectListeners` may offer a system into its
  /// own dispatcher (`collector.offer(getSystem<T>())`), which needs the
  /// systems to exist. `describeScenes` necessarily runs before
  /// `describeSystems` - `describeQuery` resolves against registered
  /// archetypes - so a scene cannot bind its own events at registration time
  /// and waits for this instead. `SceneStruct.bindEvents` is idempotent, so
  /// calling it here is safe whichever path already ran.
  ///
  /// Binding is per owner, and that is what scopes an event: a dispatcher only
  /// ever sees what its own owner offered.
  void _bindEvents() {
    final state = _state;
    if (state is EventBus) EventBinder.bind(state as EventBus);
    if (state != null) {
      final systems = state.declaredSystems;
      for (var i = 0; i < systems.length; i++) {
        EventBinder.bind(systems[i]);
      }
    }
    for (var i = 0; i < _declaredScenes.length; i++) {
      _declaredScenes[i].bindEvents();
    }
  }

  // There is deliberately no `_captureRegistries`/`_restoreRegistries` pair
  // here any more, and its absence is the point of this landing rather than a
  // simplification on the side.
  //
  // `ArchetypeRegistry`, `ComponentTypeRegistry`, `HeapObjectRegistry` and
  // `SceneRegistry` are statics, and statics belong to no object graph, so
  // they do not ride `Isolate.spawn`'s deep copy. While main ran
  // `describeScenes` and mounted the state, main was the copy that filled
  // them, and the spawned copy had to be handed the contents in a snapshot
  // reachable from this object. That was two homes for one fact (RULES.md
  // rule 10) held in agreement by the two copies running identical code.
  //
  // Now exactly one copy registers anything: [_bootGame] runs on the game
  // isolate, so the registries are filled where they are read and there is no
  // second numbering for the first to disagree with. Main's stay empty, which
  // is the honest description of a copy that holds no world.

  /// Points the transport at whichever of this copy's rings exist.
  ///
  /// Each ring has one producer and one consumer, and which end this copy
  /// holds follows from whether it simulates - the game isolate consumes what
  /// main sends and produces what main consumes, and the handle copy is the
  /// mirror image. Called twice on the handle copy (once from [_boot] with
  /// nothing to attach, once when `ready` lands with the addresses) so that
  /// there is one place that knows the direction.
  void _attachCommandRings() {
    final transport = _commandTransport;
    if (transport == null) return;
    transport.inbound = _simulates ? _commandsToGame : _commandsToMain;
    transport.outbound = _simulates ? _commandsToMain : _commandsToGame;
  }

  // --- what GameState reaches back for ----------------------------------
  //
  // The simulation half lives in another library, so the handful of things
  // its tick loop needs are `@internal` accessors rather than private
  // fields - the same escape-hatch shape `SceneStruct.bindGame` and
  // `EntityStruct.bindArchetype` already use. Each is a plain field read: no
  // copying, no allocation, safe to call once per system per tick.

  /// Whether this copy runs on the isolate that can decode assets.
  ///
  /// **Not the same question as [GameState.isSimulating]**, and that is the
  /// whole reason it exists. Decoding needs Flutter and `dart:ui`, which live
  /// on the main isolate; simulating happens wherever the tick loop is. The
  /// three configurations answer differently:
  ///
  ///  * inline (`start(inline: true)`, and every web build): one copy, on the
  ///    main isolate, doing both jobs - true.
  ///  * spawned, this is the handle copy: main isolate, does not simulate -
  ///    true.
  ///  * spawned, this is the game isolate copy: simulates, has no Flutter
  ///    engine attached - false.
  ///
  /// `GameState.loadScene` reads this to decide whether to actually pull
  /// bytes. It never gates *declaring* on it: an asset is declared on both
  /// copies in the same order or its address means two different things on
  /// the two sides. See `GameAssets`.
  @internal
  bool get decodesAssets => _inline || !_simulates;

  /// Every scene declared in [describeScenes], in declaration order - what
  /// `GameState.collectListeners` walks to reach the prefabs beneath them.
  @internal
  List<SceneStruct> get declaredScenes => _declaredScenes;

  /// Takes in whatever the other copy has sent since the last call and runs
  /// what is due - see `CommandTransport.pump`.
  ///
  /// Called from `GameState.runFixedStep`, inside the tick window and before
  /// any system, which is what makes a command-spawned entity visible to
  /// every system on the tick its command lands. The main isolate pumps on
  /// its own schedule (each tick notification), where nothing is tick-bound.
  @internal
  void pumpCommands() => _commandTransport?.pump();

  /// Called by [GameState.runFixedStep] at the top of every fixed step:
  /// re-reads the raw device snapshot and updates every declared action from
  /// it.
  ///
  /// **Before commands and before any system runs**, deliberately. A tick is
  /// supposed to see one coherent picture of the world, and input is part of
  /// that picture: resolving lazily on first read would let two systems in
  /// the same tick disagree about whether a key was down, and resolving per
  /// system would make `wasPressedThisFrame` mean "since this system last
  /// ran" rather than "this tick".
  @internal
  void resolveInputs() => _inputs.resolve();

  /// Called by [GameState.runFixedStep] once a fixed step is fully committed:
  /// bumps the tick counter and gets the news out - announcing any newly
  /// allocated page first, so the handle can resolve entities living in it
  /// before it is told the tick they appeared on is done.
  @internal
  void completeTick() => _tick++;

  /// Announces the finished frame to the main isolate: adopts any new pages,
  /// then pings the tick listeners.
  ///
  /// **Called after the presentation pass, not at the end of the fixed
  /// tick.** That ordering is load-bearing. The tick ping is what a consumer
  /// hangs its drain off - `RenderSystem2D` drains the draw ring on it - and
  /// the draw ring is filled by `GameRenderer2D` during *presentation*,
  /// which runs after `commitTick`. Firing this inside `runFixedStep` (where
  /// it used to live, back when the renderer was a `FixedTickable`) would
  /// signal "a frame is ready" before the frame had been written, so every
  /// drain would come up one frame stale - and the very first one empty.
  ///
  /// Split from [completeTick] rather than merged into it because the tick
  /// *counter* has to advance before presentation runs: the renderer stamps
  /// its batch with `game.tick`, and that has to name the tick it depicts.
  @internal
  void presentFrame() {
    final toMain = _toMain;
    if (toMain == null) {
      // Inline path: no port to hop, notify directly.
      _notifyTickListeners(_tick);
      return;
    }
    // A bare int: the cheapest thing a SendPort can carry, and all a
    // repaint trigger needs.
    //
    // It used to be preceded by an announcement of every page allocated since
    // the last tick, so main could adopt a read-only view and resolve entities
    // living in it. Main does not read entities any more - it holds no
    // archetypes to adopt into - so there is nothing to announce. What reaches
    // it is what a presentation isolate actually needs: state channels, the
    // draw buffers, and this ping.
    toMain.send(_tick);
  }

  void _notifyTickListeners(int tick) {
    // Before the listeners, not after: a widget repaints off one of these
    // callbacks, and it must see state already reconciled for this tick
    // rather than a value one tick behind whatever it is about to draw.
    _pollStateChannels();
    for (var i = 0; i < _tickListeners.length; i++) {
      _tickListeners[i](tick);
    }
  }

  /// Notifies the listeners of every declared channel whose value actually
  /// moved since this copy last looked.
  ///
  /// This is the main isolate's half of `StateChannel`'s two-speed
  /// notification (see that class's doc): the simulating copy notifies
  /// synchronously inside the write, because the writer is right there; this
  /// copy cannot know a write happened until the tick message lands, so it
  /// reconciles here. Driven off the tick-completed path rather than a timer
  /// of its own, deliberately: "the published snapshot moved" is exactly the
  /// signal [addTickListener] already carries, and a channel checking on any
  /// other schedule would report changes at a moment when the rest of the
  /// world a listener can read is from a different tick. Called from
  /// [_notifyTickListeners] rather than registered through [addTickListener]
  /// so it cannot be removed by [removeTickListener] and does not appear in
  /// the user's listener list - [addTickListener]'s public contract is
  /// untouched.
  ///
  /// Costs one null check per declared channel on a copy that declared none,
  /// which is the overwhelmingly common case.
  void _pollStateChannels() {
    for (var i = 0; i < _stateChannels.length; i++) {
      _stateChannels[i].pollChanged();
    }
  }

  // --- commands ---------------------------------------------------------

  /// A batch to build several calls into, sent and answered as one message.
  ///
  /// ```dart
  /// final batch = game.createCommandBatch();
  /// final hit = batch.execute(game.damage, (amount: 25, crit: true));
  /// batch.sink(game.log, 'first blood');
  /// final results = await batch.send();
  /// print(hit[results]);
  /// ```
  ///
  /// A bare `await game.damage(...)` is a batch of one, so this is not
  /// something a caller has to reach for - it is what to reach for when the
  /// round trip is what costs. Fifty calls in one batch is one ring record,
  /// one wake-up and one reply; fifty sends are fifty of each.
  ///
  /// Deliberately here rather than on a command: `damage.newBatch()` reads as
  /// "a batch of damage commands", and a batch is nothing of the kind - it is
  /// a mixed sequence, and mixing is most of the point. It comes from the
  /// thing that owns the channel, which is the game.
  ///
  /// Every call in one batch has to be handled on the same isolate, since a
  /// batch is one message with one reply; adding a call bound for the other
  /// side throws at the line that adds it.
  CommandBatch createCommandBatch() => _requireCommands().createCommandBatch();

  CommandRegistry _requireCommands() {
    final commands = _commands;
    if (commands == null) {
      throw StateError(
        '$runtimeType has not been started, so its commands have not been '
        'declared yet - describeCommands runs during start().',
      );
    }
    return commands;
  }

  // --- systems ----------------------------------------------------------
  //
  // Systems live on the `GameState`, on the game isolate, and nothing about
  // them exists on the presentation copy. `describeSystems` is still declared
  // *here* - a `Game` mixin has to be able to contribute one, which is what
  // makes `extends Game2D` the whole opt-in for 2D rendering - but it is
  // *invoked* from [_bootGame], so the objects it creates only ever come into
  // being over there.
  //
  // `enableSystem`/`disableSystem` used to live here and are gone with them,
  // along with their `_msgEnable`/`_msgDisable` control messages. Main cannot
  // name a system by declaration index when it has no declarations; a game
  // that wants a main-triggered pause declares a command that says so and
  // calls `GameState.disableSystem<T>()` in the handler, where the systems
  // actually are. Same shape, and the same argument, as the deleted
  // `SpawnEntityCommand`.

  // `Game.getSystem<T>()` and `tryGetSystem<T>()` used to live here and are
  // **deleted**, not forwarded. A forwarder would compile on the main isolate
  // and read as if it worked - which is exactly the mistake worth making
  // unavailable rather than diagnosable. Systems are reached through
  // `GameState.getSystem`, from code that already runs where they do.

  // `Game.loadScene` is **deleted**. It was a stub that only ever threw
  // `UnimplementedError`, left standing while scene transitions were being
  // designed - and the design settled somewhere it does not belong.
  //
  // Loading a scene registers archetypes, spawns entities and takes asset
  // claims. All three are simulation acts, and this copy has no world to
  // perform them against. `GameState.loadScene` is the only spelling. A game
  // that wants a *main-triggered* transition declares a command that says what
  // it means ("show the map screen") and calls `loadScene` in the handler,
  // which runs on the game isolate - exactly the shape that replaced the
  // deleted `SpawnEntityCommand`, and for the same reason: main should not be
  // able to name a thing it cannot see.

  // --- widgets ----------------------------------------------------------

  /// What a [GameView] shows. Null - the default - draws nothing.
  ///
  /// This is the **entire** Flutter-facing surface of a game, and it is a
  /// method rather than an event because there is exactly one thing that can
  /// answer it. An earlier design fired a `BuildWidgetEvent` at every
  /// declared system so each could wrap the tree; that was a dispatch
  /// mechanism built for several contributors to a problem that has one, and
  /// it forced `GameSystem` to straddle both isolates to be a listener at
  /// all. Now systems live entirely on the game isolate and `Game` alone
  /// builds.
  ///
  /// Renderers arrive by *subclass*, not by declaration: `Game2D` (in
  /// `goo2d`) overrides this with a `CustomPaint` fed by the draw buffer, so
  /// a 2D game writes `extends Game2D` and gets pixels. A future `goo3d`
  /// overrides it with a native surface instead, and `GameView` never
  /// changes.
  ///
  /// Null rather than an empty `SizedBox` so that "this game draws nothing"
  /// is a state a caller can *see*: a headless game with a Flutter-side HUD
  /// is a real configuration, and [GameView] lays out nothing at all for it
  /// rather than an invisible box that still takes part in layout.
  /// [camera] is the view being shown, or null when the game is displayed
  /// through `GameView.headless` - a game that declares no cameras. A
  /// renderer contributes nothing for a null rather than picking a view on
  /// the caller's behalf.
  /// [run] is which live game is being shown. A `Game` is a prefab and can
  /// back several runs at once, so "the surfaces this view draws into" is a
  /// property of the run, not of the description - a renderer keeps them in
  /// `run.attachment`.
  Widget? buildView(
    BuildContext context,
    GameHandle run,
    CameraView? camera,
  ) =>
      null;

  // The mounted-view refcount used to be an `int _mountedViews` field here,
  // with `attachView`/`detachView`/`hasView` around it. It could not stay: two
  // runs of one prefab would have shared one count, so the second run's first
  // view would not have looked like a first view and nothing would have armed
  // for it. It lives on `GameHandle` now, and the hooks below are handed the
  // run whose view count changed.

  /// The first [GameView] showing this game has been mounted.
  ///
  /// This, not [buildView], is where a renderer starts whatever runs per
  /// Flutter frame. `buildView` is called *during build*, and starting a
  /// frame callback there means a side effect fires on every rebuild and
  /// never fires at all for a game whose view is built once and then only
  /// repainted - the registration would be both duplicated and mistimed.
  void onViewAttached(GameHandle run) {}

  /// The last [GameView] showing this game has been disposed.
  ///
  /// Anything armed in [onViewAttached] must be disarmed here rather than
  /// left to [stop]: the widget can go while the game runs on, and a
  /// self-rescheduling frame callback left behind keeps the scheduler awake
  /// forever - which a widget test reports as "an animation is still running
  /// even after the widget tree was disposed".
  void onViewDetached(GameHandle run) {}

  // --- tick notification ------------------------------------------------

  /// Registers [listener] to be called on the **main** isolate once per
  /// completed fixed tick, with the tick number.
  ///
  /// This is the hook a renderer hangs a repaint off - the "frame is ready,
  /// the published snapshot moved" signal, so nothing has to poll. Kept as a
  /// plain callback list rather than a `Stream` on purpose: a broadcast
  /// stream allocates per event and schedules a microtask per listener, 60
  /// times a second, for a notification whose entire payload is one int.
  ///
  /// Register only *after* [start], on the copy that is not simulating. Not
  /// for sendability - a closure crosses `Isolate.spawn` perfectly well - but
  /// because a listener registered beforehand would be *copied*, leaving the
  /// game isolate holding a duplicate that fires on a heap the caller cannot
  /// see. Tick notification is a main-isolate concern; see [presentFrame].
  void addTickListener(void Function(int tick) listener) {
    _tickListeners.add(listener);
  }

  void removeTickListener(void Function(int tick) listener) {
    _tickListeners.remove(listener);
  }

  // --- shutdown ---------------------------------------------------------

  /// Stops the simulation and releases the shared memory.
  ///
  /// Two phases on purpose in the spawned configuration. The game isolate
  /// stops ticking and reports `stopped`, which completes this future; only
  /// then does this copy tell it to free the pool and the ring buffer.
  /// Freeing in one step would race tick messages still in flight - the
  /// handle would be resolving entities out of pages that had just been
  /// `free`d.
  ///
  /// Internal because the user-facing spelling is `GameHandle.stop()`: a
  /// running game is stopped through the thing that started it, not through
  /// its description. Renamed off `stop` so that name is free for the static
  /// factories' counterpart on the handle.
  // Not `@internal` yet - same reason as [bootUp].
  Future<void> shutDown() async {
    if (!_booted) return;
    if (_inline) {
      _stopInline();
      return;
    }
    final toGame = _toGame;
    if (toGame == null) {
      throw StateError('$runtimeType is not connected to a game isolate.');
    }
    final stopping = Completer<void>();
    _stopping = stopping;
    toGame.send(const <Object>[_msgStop]);
    await stopping.future;
    // The game isolate has freed the native memory by now, so this copy's
    // views are dangling - drop them rather than leave a RingBuffer around
    // that would happily read freed pages.
    _disposeBuffers();
    _fromGame?.close();
    _fromGame = null;
    _booted = false;
  }

  void _stopInline() {
    final state = _state!;
    state.stopTimer();
    state.unmount();
    _disposeBuffers();
    state.pool.dispose();
    _booted = false;
  }

  /// Releases the two command rings, on the copy that allocated them, and
  /// fails anything still waiting for an answer that is not coming.
  ///
  /// Same ownership rule as everything else shared: the simulating copy owns
  /// the memory, the handle copy only drops its views. Nothing to free at all
  /// in the inline configuration, which never allocated a ring.
  void _disposeCommandRings() {
    _commandTransport?.shutdown();
    if (_ownsCommandRings) {
      _commandsToGame?.dispose();
      _commandsToMain?.dispose();
      _ownsCommandRings = false;
    }
    _commandsToGame = null;
    _commandsToMain = null;
  }

  /// Releases every auxiliary buffer this copy *allocated*. The handle copy
  /// holds views into the game isolate's memory and must only drop them -
  /// same ownership rule as the command rings and the pool's pages.
  void _disposeBuffers() {
    _disposeCommandRings();
    for (var i = 0; i < _bufferHandles.length; i++) {
      final handle = _bufferHandles[i];
      if (_owns) handle._ring?.dispose();
      handle._ring = null;
    }
    for (var i = 0; i < _handoffHandles.length; i++) {
      final handle = _handoffHandles[i];
      if (_owns) handle._buffer?.dispose();
      handle._buffer = null;
    }
    cameraViews.release(owns: _owns);
    // Same ownership rule for the state channels' triple buffers: the
    // simulating copy allocated them and frees them, the handle only drops
    // its views. The declared set (the channel objects themselves, and the
    // handles users hold in their `late final` fields) survives; only the
    // storage goes, so a read after stop() reports "not connected" rather
    // than reading freed memory.
    for (var i = 0; i < _stateChannels.length; i++) {
      _stateChannels[i].release(owned: _owns);
    }
    // Same ownership rule again for the raw input block, and the same
    // survival rule: the declared actions (and the handles users hold) stay,
    // so a read after stop() reports its default rather than reading freed
    // memory. The write end goes with the storage - there is nowhere to put
    // a keystroke once the game is down.
    _inputs.release(owned: _owns);
  }

  // --- game isolate side ------------------------------------------------

  /// Runs on the freshly-spawned copy. Everything from here on happens on
  /// the game isolate.
  ///
  /// **It re-derives nothing main already did.** Main ran every allocating
  /// declaration pass before the spawn, and this copy is a deep copy of the
  /// result - same systems, same buffers, channels, inputs and commands, and
  /// the same native memory, because `Pointer` is sendable and arrives at the
  /// same address (see `tool/spawn_pointer_spike.dart`). Agreement about those
  /// is not something two runs achieved, it is something one run made
  /// impossible to lose.
  ///
  /// What it *does* describe is [_bootGame]: the scenes, and therefore the
  /// archetypes and component bits, which live in **statics** rather than on
  /// this object and so could never have crossed. Main used to run that pass
  /// too and hand the registries over in a snapshot; it does not any more, and
  /// deleting that snapshot is what this whole arrangement bought.
  ///
  /// The other thing this copy does is take over the two roles main was
  /// holding open for it: it becomes the simulator, and it stops being the
  /// owner.
  void _runOnIsolate(SendPort toMain, bool autoTick) {
    _toMain = toMain;

    // The role swap, and the only reason these are two flags. Main allocated
    // every shared buffer and will free them; this copy runs the tick loop and
    // is therefore the single writer of component data and state channels.
    // The deep copy handed us main's values, which were right for main.
    _owns = false;
    _ownsCommandRings = false;
    _simulates = true;
    _state!.markSimulating();
    _commands!.markSimulating();
    // Rebuild every cached view over native memory. `Pointer` crosses at
    // the same address, but a `ByteData` built from one and kept in a field is
    // deep-copied *by value* - the copy would write into detached Dart heap
    // memory that main never sees. Verified in tool/spawn_inherit_spike.dart.
    for (var i = 0; i < _stateChannels.length; i++) {
      _stateChannels[i].reattach();
    }
    // Main built an InputDevice against the shared input block and the copy
    // came with us. This copy only ever *reads* input, and two live write ends
    // on one TripleBuffer is exactly what that primitive forbids - so drop it.
    _inputs.releaseDevice();
    // Point the transport at the right ends now that the roles are settled.
    _attachCommandRings();

    final control = ReceivePort();
    _control = control;
    control.listen(_handleControlMessage);

    // The half of boot that only this copy can run: scenes registered,
    // archetypes and component bits into this isolate's statics, queries
    // compiled against them, events bound, and `GameState.onMounted` - which
    // is where a game loads its first scene, so this is the line the world
    // comes into being on.
    //
    // **Before `ready`, deliberately.** `_toMain` is already set, so an asset
    // decode can round-trip from here, and main has been listening on that
    // port since before the spawn. Doing it first means `start()` returns to a
    // game whose world exists rather than to one that is about to have one -
    // there is no window in which main could send a command into an unmounted
    // state. (It used to come after, because a page allocated during spawning
    // had to be announced to main; main does not adopt pages any more, so that
    // constraint is gone with them.)
    _bootGame();

    // Nothing but the control port: the buffers, state channels, input block
    // and both command rings all arrived with the copy, already addressed.
    // The three announcement messages that used to carry them are gone.
    toMain.send(<Object>[_msgReady, control.sendPort]);

    if (autoTick) _state!.startTimer();
  }

  void _handleControlMessage(dynamic message) {
    final parts = message as List;
    final state = _state;
    switch (parts[0] as String) {
      case _msgStop:
        state?.stopTimer();
        state?.unmount();
        _toMain?.send(const <Object>[_msgStopped]);
      case _msgDispose:
        _disposeBuffers();
        state?.pool.dispose();
        _control?.close();
        _control = null;
        _toMain = null;
        _booted = false;
      case _msgAssetLoaded:
        final request = _assetRequests[parts[1] as int];
        request?.onLoaded?.call(
          parts[2] as int,
          parts[3] as int,
          parts[4] as int,
        );
      case _msgAssetsDone:
        final request = _assetRequests.remove(parts[1] as int);
        final failure = parts[2] as String?;
        if (request == null || request.done.isCompleted) break;
        if (failure == null) {
          request.done.complete();
        } else {
          // Surfaced at the `await loadScene(...)` that asked for it, which is
          // where the local decode path throws too.
          request.done.completeError(StateError(
            'asset decoding failed on the Flutter isolate - $failure',
          ));
        }
    }
  }

  // --- main isolate side ------------------------------------------------

  void _handleGameMessage(dynamic message, Completer<void> ready) {
    // A bare int is the per-tick ping; anything else is a control message.
    if (message is int) {
      _tick = message;
      // Before the listeners, for the same reason the state channels are
      // reconciled before them: this is the one moment per frame when this
      // copy looks at what the game isolate has said, and a widget rebuilding
      // off a tick callback should see a command's effects from the same
      // frame rather than the one before it. This is also where a
      // Flutter-isolate handler actually runs, and where a reply to a command
      // this copy sent completes its future.
      _commandTransport?.pump();
      _notifyTickListeners(message);
      return;
    }
    final parts = message as List;
    switch (parts[0] as String) {
      case _msgReady:
        // The control port is all `ready` carries now. Every shared buffer -
        // both command rings, the auxiliary buffers, the state channels and
        // the input block - was allocated on this copy before the spawn and
        // arrived on the other one inside the copied object, already
        // addressed. The three announcement messages that used to carry them
        // are gone, and so is the reason `start()` had to wait for them.
        _toGame = parts[1] as SendPort;
        ready.complete();
      case _msgLoadAssets:
        // Unawaited by design: this is a port callback, and the decode is
        // asynchronous. Its completion is reported back over the port rather
        // than by this future, and every failure is caught inside.
        unawaited(_handleAssetLoadRequest(parts));
      case _msgUnloadAssets:
        final addresses = (parts[1] as List).cast<int>();
        for (var i = 0; i < addresses.length; i++) {
          assets.unloadAddress(addresses[i]);
        }
      case _msgStopped:
        _toGame?.send(const <Object>[_msgDispose]);
        _toGame = null;
        _stopping?.complete();
        _stopping = null;
    }
  }

  /// Frees a scene's pages, immediately.
  ///
  /// This used to be half of an un-adopt handshake: the pages were kept alive
  /// across a `_msgPageGone`/`_msgPagesDropped` round trip so that main, which
  /// held adopted read-only views of them, could let go before the writer
  /// freed. Use-after-free is the one failure mode a shared-memory design
  /// cannot report - it just returns wrong numbers - so the deferral was worth
  /// its complexity while there was a second reader.
  ///
  /// There is not one any more. Pages are allocated, read and freed entirely
  /// on this isolate; main never adopts one, because it holds no archetypes to
  /// adopt into and never resolves an `Entity`. So the handshake, the deferred
  /// free set, and both messages are gone, and unloading is once again the
  /// straight line it reads as.
  @internal
  void releaseScenePages(int sceneSlot) {
    final pool = _state?.pool;
    if (pool == null) return;
    for (var i = 0; i < ArchetypeRegistry.count; i++) {
      ArchetypeRegistry.byId(i).releaseScene(sceneSlot, pool);
    }
  }

  // --- asset decoding across the boundary --------------------------------
  //
  // The game isolate declares assets - that is what assigns their addresses,
  // and it has to happen there because prefabs and scenes live there - but it
  // cannot *decode* one, because decoding needs Flutter. So it asks.
  //
  // Before this existed, `GameState._reconcileAssets` took its claims and
  // returned at `if (!game.decodesAssets) return;`, and nothing told main to
  // decode anything. That was invisible only because main ran `loadScene`
  // itself at boot; a `loadScene` at *runtime*, on the game isolate, declared
  // assets that were never loaded and whose payload reads then failed.

  /// Asks main to decode every asset in [addresses], completing when it has.
  ///
  /// [keys] is parallel to [addresses] and is what makes the request
  /// self-contained: main does not run `describeAssets` and therefore has no
  /// declaration of its own to resolve an address against, so the request
  /// carries both halves of the identity and main adopts the pair (see
  /// `GameAssets.adoptAt`). A `GameAsset` key is plain sendable data; the
  /// *instance* is what would not cross, because a decoded one owns a
  /// `dart:ui.Image`.
  ///
  /// [onLoaded] fires once per asset that actually needed decoding, carrying
  /// the running `completed`/`pending` counts so the caller can report
  /// progress with the same denominator the local path uses - the number of
  /// decodes actually performed, not the number of assets asked about.
  ///
  /// Returns immediately when there is no main to ask, which is the inline
  /// case: there, `decodesAssets` is true and the caller decodes in place
  /// rather than calling this at all.
  @internal
  Future<void> requestAssetLoad(
    List<int> addresses,
    List<GameAsset> keys,
    void Function(int address, int completed, int pending)? onLoaded,
  ) {
    final toMain = _toMain;
    if (toMain == null || addresses.isEmpty) return Future<void>.value();
    final id = ++_assetRequestId;
    final request = _AssetLoadRequest(onLoaded);
    _assetRequests[id] = request;
    toMain.send(<Object>[_msgLoadAssets, id, addresses, keys]);
    return request.done.future;
  }

  /// Tells main to drop the payloads for [addresses]. Fire-and-forget: the
  /// declaration is already gone on this copy, and nothing here waits on the
  /// memory the way a page free does.
  @internal
  void requestAssetUnload(List<int> addresses) {
    if (addresses.isEmpty) return;
    _toMain?.send(<Object>[_msgUnloadAssets, addresses]);
  }

  /// Main's half: decode what was asked for, reporting each one back.
  ///
  /// Sequential rather than concurrent, deliberately - it mirrors the local
  /// path exactly, and a loading screen wants a progress sequence rather than
  /// everything landing at once. `GameAssets.load` already collapses
  /// overlapping requests for one key.
  Future<void> _handleAssetLoadRequest(List parts) async {
    final id = parts[1] as int;
    final addresses = (parts[2] as List).cast<int>();
    final keys = (parts[3] as List).cast<GameAsset>();

    // Adopt first, decode second. This copy never ran a `describeAssets` pass
    // - scenes and prefabs live on the other isolate - so until this line
    // there is nothing here for the address to name. Adopting is idempotent,
    // so an asset a previous request already brought over keeps its payload.
    for (var i = 0; i < addresses.length; i++) {
      assets.adoptAt(addresses[i], keys[i]);
    }

    // Counted up front so the denominator is the number of decodes actually
    // performed - a scene whose assets are all resident reports one 1.0 and
    // does no work, same as the local path.
    var pending = 0;
    for (var i = 0; i < addresses.length; i++) {
      final instance = assets.tryResolve<GameAssetInstance>(addresses[i]);
      if (instance != null && !instance.isLoaded) pending++;
    }

    var completed = 0;
    String? failure;
    for (var i = 0; i < addresses.length; i++) {
      final address = addresses[i];
      final instance = assets.tryResolve<GameAssetInstance>(address);
      if (instance == null || instance.isLoaded) continue;
      try {
        await assets.loadAddress(address);
      } catch (error) {
        // Recorded and carried back rather than thrown here: this runs inside
        // a port callback, where throwing would take out the message loop and
        // strand the asker forever. The awaiting `loadScene` is the right
        // place for it to surface.
        failure ??= '${instance.debugLabel}: $error';
      }
      completed++;
      _toGame?.send(<Object?>[
        _msgAssetLoaded,
        id,
        address,
        completed,
        pending,
      ]);
    }
    _toGame?.send(<Object?>[_msgAssetsDone, id, failure]);
  }
}

/// One in-flight [Game.requestAssetLoad], game-isolate side.
///
/// One object rather than parallel maps keyed by request id (RULES.md rule
/// 10): the completer, the progress callback and the first failure all belong
/// to the same request and are only ever used together.
final class _AssetLoadRequest {
  _AssetLoadRequest(this.onLoaded);

  final void Function(int address, int completed, int pending)? onLoaded;
  final Completer<void> done = Completer<void>();
}

/// The spawned isolate's entry point. Top-level (a closure would not be
/// sendable) and deliberately trivial - all it does is hand control to the
/// copied `Game`.
void _gameIsolateEntryPoint(List<Object> message) {
  final game = message[0] as Game;
  game._runOnIsolate(message[1] as SendPort, message[2] as bool);
}

/// Declares the scenes a game can load - see [Game.describeScenes].
///
/// **Distinct from `SceneDescriptor`**, and the two must not be conflated:
/// this is the `Game`-level pass that says which scenes *exist*, while
/// `SceneDescriptor` is the pass inside `SceneStruct.describeScene` that says
/// which *prefabs* a scene has. One names scenes to the game; the other names
/// entity structs to a scene.
abstract class GameSceneDescriptor {
  /// Declares [scene] and returns it, for the `late final` field to keep.
  T has<T extends SceneStruct>(T scene);
}

abstract class SystemDescriptor {
  T has<T extends GameSystem>(T system);
}

/// Declares the auxiliary ring buffers a game (or one of its systems) needs
/// - see [Game.describeBuffers]. Same one-pass declarative shape as
/// `SystemDescriptor`/`CommandDescriptor`/`SceneDescriptor`/`StateDescriptor`.
abstract class BufferDescriptor {
  /// Declares a buffer of [capacityBytes] and returns the handle to keep in
  /// a field.
  BufferHandle has({required int capacityBytes});

  /// Declares a **handoff** buffer of [slotBytes] per slot - shared memory for
  /// a value where only the newest copy matters, rather than a queue where
  /// every record does.
  ///
  /// Use [has] for a stream (commands, events, anything where dropping the
  /// third of five is a bug). Use this for a value that is completely replaced
  /// each time it is produced - a rendered frame being the case it exists for.
  /// See [HandoffBuffer] for why a ring is the wrong shape there.
  HandoffHandle hasHandoff({required int slotBytes});
}

/// A declared auxiliary ring buffer: the thing [BufferDescriptor.has] hands
/// back and the declarer keeps in a `late final` field.
///
/// This is RULES.md rule 6 applied to buffers. There is no name and no
/// registry to search: the handle carries its own declaration index, and both
/// copies of the `Game` produce the same handles in the same order because
/// both run the same `describeBuffers` passes. So `drawBuffer.ring` is a
/// field read plus a null check, the analyzer catches a typo in the field
/// name immediately, and there is no way to spell a buffer that does not
/// exist.
///
/// The handle exists from declaration; its [ring] appears when the copy that
/// owns the simulation allocates the memory, or when this copy adopts a view
/// of the other side's - both of which happen before `start()` completes.
final class BufferHandle {
  BufferHandle._(this.index, this.capacityBytes);

  /// Position in the shared declaration order - this buffer's identity on the
  /// wire, and what diagnostics name it by.
  final int index;

  /// What was asked for in [BufferDescriptor.has]. Known on both copies from
  /// declaration, before any memory exists.
  final int capacityBytes;

  RingBuffer? _ring;

  /// Whether this copy has a live view yet. False between declaration and the
  /// end of `Game.start()`, and again after `Game.stop()`.
  bool get isConnected => _ring != null;

  /// This copy's view of the buffer - the allocation itself on the simulating
  /// copy, an adopted view of that same native memory on the handle.
  ///
  /// Available from the moment `Game.start()` completes on either copy (see
  /// [Game.describeBuffers] for the ordering guarantee), so a system's first
  /// `onFixedUpdate` can resolve it without a null check.
  RingBuffer get ring {
    final ring = _ring;
    if (ring == null) {
      throw StateError(
        'Auxiliary buffer #$index ($capacityBytes bytes) is declared but not '
        'connected on this copy of the Game. Call start() (and await it) '
        'first - the simulating copy allocates the memory and announces its '
        'address, and a handle copy only has a view once that message has '
        'landed. After stop() the memory is freed and the view is dropped, '
        'which looks the same from here.',
      );
    }
    return ring;
  }

  /// [ring], but `null` instead of throwing - for a caller that is happy to
  /// sit out until the handoff completes (a widget built before
  /// `await start()` returned, say).
  RingBuffer? get tryRing => _ring;
}

/// A declared [HandoffBuffer] - what [BufferDescriptor.hasHandoff] hands back
/// and the declarer keeps in a `late final` field.
///
/// Same discipline as [BufferHandle] (RULES.md rule 6): no name, no registry,
/// and both copies produce the same handles in the same order because both run
/// the same `describeBuffers` passes.
final class HandoffHandle {
  HandoffHandle._(this.index, this.slotBytes);

  /// Position in the declaration order of handoff buffers specifically - a
  /// separate sequence from [BufferHandle.index], since they are separate
  /// lists.
  final int index;

  /// Bytes per slot, as declared. Known on both copies before any memory
  /// exists.
  final int slotBytes;

  HandoffBuffer? _buffer;

  /// Whether this copy has a live view yet. False between declaration and the
  /// end of `Game.start()`, and again after `Game.stop()`.
  bool get isConnected => _buffer != null;

  /// This copy's view of the buffer. Both copies address the same native
  /// memory: the owning copy allocates it before the spawn and the `Pointer`s
  /// inside cross at the same addresses, so there is nothing to announce.
  HandoffBuffer get buffer {
    final buffer = _buffer;
    if (buffer == null) {
      throw StateError(
        'Handoff buffer #$index ($slotBytes bytes per slot) is declared but '
        'not connected on this copy of the Game. Call start() (and await it) '
        'first; after stop() the memory is freed and the view is dropped, '
        'which looks the same from here.',
      );
    }
    return buffer;
  }

  /// [buffer], but `null` instead of throwing - for a caller happy to sit out
  /// until bring-up completes.
  HandoffBuffer? get tryBuffer => _buffer;
}

/// Records declaration order, which *is* execution order - see the class doc
/// on [Game]. Systems are keyed by `runtimeType` rather than by the type
/// argument so `descriptor.has(Transform2DSystem())` and
/// `getSystem<Transform2DSystem>()` agree without the caller having to spell
/// the type argument twice.
/// Registers a declared scene's archetypes and assets, once, at boot.
final class _GameSceneDescriptor implements GameSceneDescriptor {
  _GameSceneDescriptor(this._game);

  final Game _game;

  @override
  T has<T extends SceneStruct>(T scene) {
    for (var i = 0; i < _game._declaredScenes.length; i++) {
      if (_game._declaredScenes[i].runtimeType != scene.runtimeType) continue;
      throw StateError(
        '${scene.runtimeType} is declared twice in '
        '${_game.runtimeType}.describeScenes. One instance is one scene '
        'declaration - and it already backs as many loaded Scenes as you '
        'load, so a second instance would register a second set of '
        'archetypes for the same prefabs rather than giving you a second '
        'world.',
      );
    }
    scene.bindState(_game._state!);
    if (!scene.isInitialized) {
      scene.initializeScene(_game._state!.pool,
          assets: _game.assets, cameraViews: _game.cameraViews);
    }
    _game._declaredScenes.add(scene);
    return scene;
  }
}

/// Collects declared systems into the [GameState] that declares and runs them.
final class _SystemDescriptor implements SystemDescriptor {
  _SystemDescriptor(this._state);

  final GameState _state;

  @override
  T has<T extends GameSystem>(T system) {
    final type = system.runtimeType;
    if (_state.systemIndexOf(type) != null) {
      throw StateError(
        '$type is declared twice in ${_state.game.runtimeType}'
        '.describeSystems. One instance describes one system; declaration '
        'order is execution order, so a duplicate has no meaningful position.',
      );
    }
    return _state.addDeclaredSystem(system);
  }
}

final class _BufferDescriptor implements BufferDescriptor {
  _BufferDescriptor(this._game);

  final Game _game;

  @override
  BufferHandle has({required int capacityBytes}) {
    if (capacityBytes <= RingBuffer.headerBytes) {
      throw ArgumentError.value(
        capacityBytes,
        'capacityBytes',
        'must leave room for at least one record header '
            '(${RingBuffer.headerBytes} bytes) plus a payload',
      );
    }
    final handle = BufferHandle._(_game._bufferHandles.length, capacityBytes);
    _game._bufferHandles.add(handle);
    return handle;
  }

  @override
  HandoffHandle hasHandoff({required int slotBytes}) {
    if (slotBytes <= 0) {
      throw ArgumentError.value(slotBytes, 'slotBytes', 'must be positive');
    }
    final handle = HandoffHandle._(_game._handoffHandles.length, slotBytes);
    _game._handoffHandles.add(handle);
    return handle;
  }
}

/// Everything `Game` needs from a state channel without knowing its `T`.
///
/// A non-generic interface rather than storing `_StateChannelBase<Object?>`
/// in the list: the whole point of these operations is that they are
/// type-erased plumbing (allocate, announce, adopt, poll, free), and none of
/// them wants to expose or launder the channel's value type.
abstract class _ChannelSlot {
  int get encodedBytes;

  /// The live storage, non-null on the simulating copy from `_boot()`
  /// onwards - what [Game._announceStateChannels] reads addresses off.
  TripleBuffer? get liveBuffer;

  /// Simulating copy: allocate the triple buffer and publish the initial
  /// value.
  void allocateAndSeed();

  /// Handle copy: take a view over the simulating copy's allocation.
  void adopt({required int latestAddress, required List<int> slotAddresses});

  /// Rebuilds the cached `ByteData` views from the pointers they came from.
  ///
  /// Called once on the spawned copy. The views are built by [_attach] from
  /// `Pointer.asTypedList`, and while the `Pointer` crosses the spawn at the
  /// same address, a typed-data view stored in a field is deep-copied **by
  /// value** - so without this the spawned copy would read and write a
  /// detached Dart heap buffer that the other copy never sees. Verified in
  /// `tool/spawn_inherit_spike.dart`.
  void reattach();

  void pollChanged();

  void release({required bool owned});
}

/// The fixed-width formats a [StateChannel] can carry - deliberately the same
/// set `DataDescriptor` offers for component fields, for the same reason: a
/// channel is a fixed number of bytes in shared memory, and a width is all
/// the information needed to read and write it.
enum _ChannelFormat {
  uint8(1),
  int8(1),
  uint16(2),
  int16(2),
  uint32(4),
  int32(4),
  uint64(8),
  int64(8),
  float32(4),
  float64(8),
  boolean(1);

  const _ChannelFormat(this.bytes);

  final int bytes;
}

/// Shared body of every channel: the declaration (index, format, initial
/// value), the cached `ByteData` views over the three slots, the read and
/// write paths, and change notification.
///
/// One class for both isolate roles rather than a read-only subclass and a
/// writable one, because `StateChannel` now *has* a setter on both sides -
/// the split is enforced by [owned] and an `assert` (RULES.md rule 7) rather
/// than by the type system. That is a deliberate trade: `ValueListenable`
/// requires one declared type usable from Flutter on the main isolate, and a
/// write from there is a programmer error rather than something a caller
/// should be handed two types to reason about.
abstract class _StateChannelBase<T>
    with ChangeNotifier
    implements StateChannel<T>, _ChannelSlot {
  _StateChannelBase({
    required this.index,
    required this.format,
    required this.initialValue,
    required Game game,
    // A named parameter cannot start with an underscore, so `this._game` is
    // not spellable and the lint's suggestion does not compile.
    // ignore: prefer_initializing_formals
  }) : _game = game,
       _lastSeen = initialValue;

  /// Position in the shared declaration order - this channel's identity on
  /// the wire, and what diagnostics name it by.
  final int index;
  final _ChannelFormat format;
  final T initialValue;

  /// The copy this channel was declared on - held rather than two booleans
  /// because the two questions it answers used to be the same question and no
  /// longer are.
  final Game _game;

  /// Whether this copy allocated the storage, and so must free it. Main, in
  /// the spawned configuration.
  bool get owned => _game._owns;

  /// Whether this copy may *write*. The simulating one - which after the boot
  /// inversion is a different copy from the one that owns the memory.
  ///
  /// A `TripleBuffer` requires one writer, not a particular isolate, so
  /// allocate-here/write-there is legal; `InputDevice` has always been the
  /// mirror image of it.
  bool get _mayWrite => _game._simulates;

  TripleBuffer? _buffer;

  // Built once, when storage is attached: one ByteData per slot, each
  // exactly encodedBytes long, wrapping that slot's native memory.
  //
  // Two jobs. It keeps both the read and the write path allocation-free -
  // `Pointer.asTypedList` plus `ByteData.sublistView` per access would be
  // two objects per read, 60 times a second, which is exactly what
  // Game._commandScratch already exists to avoid on the command path. And
  // because each view is *exactly* encodedBytes long, a write past the
  // declared width hits the view's own bounds check instead of silently
  // scribbling into whatever native memory follows.
  List<int> _slotAddresses = const <int>[];
  List<ByteData> _slotViews = const <ByteData>[];

  // The last value *this copy* saw, seeded with initialValue because that is
  // provably what the first read returns (it is published the instant storage
  // is allocated). So listeners never fire for the initial value, and never
  // fire on a tick where nothing new was published.
  T _lastSeen;

  @override
  int get encodedBytes => format.bytes;

  @override
  TripleBuffer? get liveBuffer => _buffer;

  /// Reads this channel's value out of [view], which is exactly
  /// [encodedBytes] long.
  T readFrom(ByteData view);

  /// Writes [value] into [view], which is exactly [encodedBytes] long.
  void writeTo(ByteData view, T value);

  void _attach(TripleBuffer buffer) {
    _buffer = buffer;
    final addresses = buffer.slotAddresses;
    _slotAddresses = addresses;
    _slotViews = <ByteData>[
      for (final address in addresses)
        ByteData.sublistView(
          Pointer<Uint8>.fromAddress(address).asTypedList(encodedBytes),
        ),
    ];
  }

  @override
  void adopt({required int latestAddress, required List<int> slotAddresses}) {
    _attach(
      TripleBuffer.fromAddresses(
        slotBytes: encodedBytes,
        latestAddress: latestAddress,
        slotAddresses: slotAddresses,
      ),
    );
  }

  @override
  void reattach() {
    final buffer = _buffer;
    if (buffer != null) _attach(buffer);
  }

  @override
  void allocateAndSeed() {
    assert(owned, 'only the owning copy allocates channel storage');
    _attach(TripleBuffer(encodedBytes));
    // Immediately, not on the first tick: until this lands, latestView() is
    // null and hasPublished is false, and no reader on either copy may
    // observe that state.
    _publish(initialValue);
  }

  /// The cached view for the slot [pointer] names. Three addresses, compared
  /// as ints - no map, no allocation.
  ByteData _viewFor(Pointer<Uint8> pointer) {
    final address = pointer.address;
    for (var i = 0; i < _slotAddresses.length; i++) {
      if (_slotAddresses[i] == address) return _slotViews[i];
    }
    throw StateError(
      'state channel #$index resolved a triple-buffer slot it has no view '
      'for - the channel was attached to different storage than it is being '
      'read through.',
    );
  }

  @override
  T get value {
    final buffer = _buffer;
    if (buffer == null) {
      throw StateError(
        'state channel #$index is declared but not connected on this copy of '
        'Game. Call start() (and await it) first - the simulating copy '
        'allocates the storage and announces its address, and a handle copy '
        'only has a view once that message has landed.',
      );
    }
    final slot = buffer.latestView();
    if (slot == null) {
      // Unreachable in normal operation: allocateAndSeed() publishes the
      // initial value before this channel is announced, so latestView() is
      // non-null from the moment either copy can reach it. Stated loudly
      // rather than papered over with a fallback, because a null here means
      // the seed publish was skipped - a bootstrap bug, not a missing value.
      throw StateError(
        'state channel #$index has storage but nothing published in it. The '
        'declared initial value is published as soon as the storage is '
        'allocated, so this should be unreachable.',
      );
    }
    return readFrom(_viewFor(slot));
  }

  @override
  set value(T newValue) {
    if (!_mayWrite) {
      assert(
        false,
        'state channel #\$index was written on the Game copy that does not '
        'simulate. A state channel is written by the copy that runs the tick '
        'loop (the game isolate, or the single copy under '
        'start(inline: true)) and read by both; a write from the handle the '
        'main isolate holds after start() would be invisible to the '
        'simulation. Send a GameCommand instead. See the class doc on '
        'StateChannel.',
      );
      return;
    }
    _publish(newValue);
  }

  void _publish(T newValue) {
    final buffer = _buffer;
    if (buffer == null) {
      throw StateError(
        'state channel #$index has no storage yet - written before the Game '
        'has finished booting.',
      );
    }
    // copyFromLatest: false. `true` exists for in-place partial mutation -
    // a writer that touches some fields of last tick's snapshot and leaves
    // the rest (which is how MemoryPool's pages are written). A channel write
    // is the opposite: it hands over a complete new value and writeTo is
    // contracted to write all of it, so copying the previous slot forward
    // first would be a full memcpy of every channel, every tick, whose every
    // byte is then overwritten.
    final slot = buffer.beginWrite(copyFromLatest: false);
    writeTo(_viewFor(slot), newValue);
    buffer.publish();
    // Synchronously, because the writer is right here: this is the game
    // isolate's half of the two-speed notification described on StateChannel.
    // The other copy cannot know anything happened until the tick message
    // lands, and reconciles in pollChanged().
    if (newValue == _lastSeen) return;
    _lastSeen = newValue;
    notifyListeners();
  }

  /// Re-baselines [_lastSeen] the moment anyone starts caring.
  ///
  /// Without this, [pollChanged] would have to decode this channel every
  /// single tick even when nothing listens, purely so that a listener added
  /// later had something honest to compare against - a decode per declared
  /// channel per tick, forever, for nobody (RULES.md rules 1 and 2). Doing it
  /// here instead makes the no-listener case free and gives a late-arriving
  /// listener exactly the same guarantee: it is told about changes that
  /// happen *after* it started listening, never about one that predates it.
  @override
  void addListener(VoidCallback listener) {
    if (_buffer != null) _lastSeen = value;
    super.addListener(listener);
  }

  @override
  void pollChanged() {
    // Two field reads on a channel nobody listens to, which is the
    // overwhelmingly common case. The simulating copy keeps _lastSeen fresh
    // in _publish anyway; this exists for the handle copy, which cannot know
    // a write happened until the tick message lands.
    if (_buffer == null || !hasListeners) return;
    final current = value;
    if (current == _lastSeen) return;
    _lastSeen = current;
    notifyListeners();
  }

  @override
  void release({required bool owned}) {
    if (owned) _buffer?.dispose();
    _buffer = null;
    _slotAddresses = const <int>[];
    _slotViews = const <ByteData>[];
  }
}

/// Every integer width, in one class: the format is a field, so a channel of
/// each width is one object and not one class per width.
final class _IntStateChannel extends _StateChannelBase<int> {
  _IntStateChannel({
    required super.index,
    required super.format,
    required super.initialValue,
    required super.game,
  });

  @override
  int readFrom(ByteData view) => switch (format) {
    _ChannelFormat.uint8 => view.getUint8(0),
    _ChannelFormat.int8 => view.getInt8(0),
    _ChannelFormat.uint16 => view.getUint16(0, Endian.little),
    _ChannelFormat.int16 => view.getInt16(0, Endian.little),
    _ChannelFormat.uint32 => view.getUint32(0, Endian.little),
    _ChannelFormat.int32 => view.getInt32(0, Endian.little),
    _ChannelFormat.uint64 => view.getUint64(0, Endian.little),
    _ => view.getInt64(0, Endian.little),
  };

  @override
  void writeTo(ByteData view, int value) {
    switch (format) {
      case _ChannelFormat.uint8:
        view.setUint8(0, value);
      case _ChannelFormat.int8:
        view.setInt8(0, value);
      case _ChannelFormat.uint16:
        view.setUint16(0, value, Endian.little);
      case _ChannelFormat.int16:
        view.setInt16(0, value, Endian.little);
      case _ChannelFormat.uint32:
        view.setUint32(0, value, Endian.little);
      case _ChannelFormat.int32:
        view.setInt32(0, value, Endian.little);
      case _ChannelFormat.uint64:
        view.setUint64(0, value, Endian.little);
      default:
        view.setInt64(0, value, Endian.little);
    }
  }
}

final class _DoubleStateChannel extends _StateChannelBase<double> {
  _DoubleStateChannel({
    required super.index,
    required super.format,
    required super.initialValue,
    required super.game,
  });

  @override
  double readFrom(ByteData view) => format == _ChannelFormat.float32
      ? view.getFloat32(0, Endian.little)
      : view.getFloat64(0, Endian.little);

  @override
  void writeTo(ByteData view, double value) {
    if (format == _ChannelFormat.float32) {
      view.setFloat32(0, value, Endian.little);
    } else {
      view.setFloat64(0, value, Endian.little);
    }
  }
}

/// One byte, not one bit: a channel is its own allocation rather than a field
/// packed into a shared row, so there is nothing to save by sub-byte packing
/// and a whole byte to gain in read/write simplicity.
final class _BoolStateChannel extends _StateChannelBase<bool> {
  _BoolStateChannel({
    required super.index,
    required super.initialValue,
    required super.game,
  }) : super(format: _ChannelFormat.boolean);

  @override
  bool readFrom(ByteData view) => view.getUint8(0) != 0;

  @override
  void writeTo(ByteData view, bool value) => view.setUint8(0, value ? 1 : 0);
}

final class _StateDescriptor implements StateDescriptor {
  _StateDescriptor(this._game);

  final Game _game;
  bool _sealed = false;

  void _seal() => _sealed = true;

  void _checkOpen() {
    if (_sealed) {
      throw StateError(
        'a state channel was declared after ${_game.runtimeType}\'s boot '
        'finished. State channels are declared once, up front, in '
        'describeState - their storage is allocated and announced at '
        'bring-up, and their index has to match the other isolate copy\'s.',
      );
    }
  }

  StateChannel<int> _int(_ChannelFormat format, int initial) {
    _checkOpen();
    final channel = _IntStateChannel(
      index: _game._stateChannels.length,
      format: format,
      initialValue: initial,
      game: _game,
    );
    _game._stateChannels.add(channel);
    return channel;
  }

  StateChannel<double> _float(_ChannelFormat format, double initial) {
    _checkOpen();
    final channel = _DoubleStateChannel(
      index: _game._stateChannels.length,
      format: format,
      initialValue: initial,
      game: _game,
    );
    _game._stateChannels.add(channel);
    return channel;
  }

  @override
  StateChannel<int> hasUint8([int initial = 0]) =>
      _int(_ChannelFormat.uint8, initial);

  @override
  StateChannel<int> hasInt8([int initial = 0]) =>
      _int(_ChannelFormat.int8, initial);

  @override
  StateChannel<int> hasUint16([int initial = 0]) =>
      _int(_ChannelFormat.uint16, initial);

  @override
  StateChannel<int> hasInt16([int initial = 0]) =>
      _int(_ChannelFormat.int16, initial);

  @override
  StateChannel<int> hasUint32([int initial = 0]) =>
      _int(_ChannelFormat.uint32, initial);

  @override
  StateChannel<int> hasInt32([int initial = 0]) =>
      _int(_ChannelFormat.int32, initial);

  @override
  StateChannel<int> hasUint64([int initial = 0]) =>
      _int(_ChannelFormat.uint64, initial);

  @override
  StateChannel<int> hasInt64([int initial = 0]) =>
      _int(_ChannelFormat.int64, initial);

  @override
  StateChannel<double> hasFloat32([double initial = 0]) =>
      _float(_ChannelFormat.float32, initial);

  @override
  StateChannel<double> hasFloat64([double initial = 0]) =>
      _float(_ChannelFormat.float64, initial);

  @override
  StateChannel<bool> hasBool([bool initial = false]) {
    _checkOpen();
    final channel = _BoolStateChannel(
      index: _game._stateChannels.length,
      initialValue: initial,
      game: _game,
    );
    _game._stateChannels.add(channel);
    return channel;
  }
}
