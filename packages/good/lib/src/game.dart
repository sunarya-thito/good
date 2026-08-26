import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show
        ChangeNotifier,
        ErrorDescription,
        FlutterError,
        FlutterErrorDetails,
        VoidCallback,
        kIsWeb;
import 'package:flutter/widgets.dart'
    show
        AppLifecycleState,
        BuildContext,
        Widget,
        WidgetsBinding,
        WidgetsBindingObserver;
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'package:good/src/archetype.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/audio/audio_clip.dart';
import 'package:good/src/camera_view.dart';
import 'package:good/src/command/command.dart';
import 'package:good/src/command/param.dart';
import 'package:good/src/command/transport.dart';
import 'package:good/src/event.dart';
import 'package:good/src/event/state.dart';
import 'package:good/src/handoff_buffer.dart';
import 'package:good/src/heap_object.dart';
import 'package:good/src/random.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/widget/frame_meter.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/input/gamepad.dart';
import 'package:good/src/input/input_state.dart';
import 'package:good/src/ring_buffer.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/system.dart';
import 'package:good/src/triple_buffer.dart';

/*
GameAsset, GameState, and everything simulation-side must be called under our
game isolate. Prefer dart:ffi calloc when running on native platform.

If its on web, we don't use isolate nor ffi - start(inline: true) runs the
GameState on the calling isolate instead.
*/

// Wire tags for the two SendPort control lanes. An enum rather than the
// `const String`s that used to be here: a string tag is resolved by name, so
// a typo compiles and misses at run time, and two tags spelled the same are a
// bug nothing reports. A value cannot collide with another value, and because
// both switches below cover every value, an arm nobody wrote is an analyzer
// error instead of a message that quietly does nothing.
//
// Enum identity survives `Isolate.spawn`: the value that arrives on the far
// side is `identical` to the declared one, which is what makes a `switch` on
// it match rather than fall through every arm. `game_isolate_test.dart` pins
// that against a real spawn rather than trusting it.
//
// Bulk traffic never goes near a SendPort - that is the ring buffer's job.
// These are the rare ones: bring-up, shutdown and asset decoding.
//
// Three tags used to live here and are gone: `page`, `pagegone` and
// `pagesdropped`, which announced newly allocated pages to main and negotiated
// freeing them again. Main holds no archetypes and resolves no entity, so
// there is nothing on that side for a page to be announced *to*. Four more
// went in #142 - visibility, pause, time scale and step-once - and are
// receipt-delivered commands now.
//
// Each survivor carries why it survived, so the next reader does not have to
// work it out again.
enum _ControlMessage {
  /// Game -> main once the far copy has booted, carrying the `SendPort`
  /// everything main sends goes through.
  ///
  /// This is what brings the lane a command would need into existence. Until
  /// it lands `_toGame` is null, so the `controlSend` closure
  /// `attachCommandRings` installs resolves its port to null and drops a
  /// control batch without a word. Its payload is a `SendPort` besides - a
  /// live VM handle, in the same category as the asset keys below: only the
  /// isolate copy moves one, bytes never will.
  ready,

  /// Game -> main once the world is down. Releases the `stop()` that asked
  /// and is what prompts [dispose] back.
  stopped,

  /// Main -> game: stop the timer and unmount the world.
  ///
  /// `GameState.unmount` takes down every loaded scene and destroys their
  /// entities, which is component-data writing. A receipt-delivered handler
  /// runs in the port callback with no tick window open, where that is the
  /// one thing it must not do. Ring delivery would need a tick, and this
  /// message exists to end them.
  stop,

  /// Main -> game after [stopped]: free the native memory and close this
  /// lane.
  ///
  /// The handler reaches `CommandTransport.shutdown` through
  /// `_disposeBuffers`, and after that `send` throws and
  /// `receiveControlBatch` returns without dispatching. It ends the delivery
  /// machinery, so it cannot be delivered by it.
  dispose,

  /// Either direction: the bytes of a receipt-delivered command batch.
  ///
  /// The carrier that let the four migrated tags become commands (#142). It
  /// cannot be one itself, for the same reason the per-tick ping cannot: it
  /// would have to be delivered by the thing it delivers.
  controlBatch,

  // Asset decoding: the game isolate declares assets but cannot decode them
  // (a decode needs Flutter), so it asks. Assets are named by their
  // **address** - the index `GameAssets` assigns at declare time, which both
  // copies agree on because both run the same declarations in the same order.
  // That is already the integer a component row stores to point at an asset,
  // so no second identity is invented for the wire.
  //
  // These four are one-way messages correlated by request id, not a
  // request/reply pair - `requestAssetLoad` completes its own `Completer` when
  // [assetsDone] arrives. So four receipt-delivered sinks would preserve the
  // semantics exactly and no reply-over-port is needed for them. What stops
  // them is the payload, in two halves worth keeping apart.
  //
  // The half that will outlast any change to the record format: [loadAssets]
  // carries `AssetKey` instances and [assetLoaded] carries an `AssetInfo`,
  // and both are open classes a game subclasses (asset.dart). A key is not
  // data. Main reaches through it to `AssetSource.load()` and
  // `AssetKey.loader`, and reads `payloadType` off its reified type argument
  // to build an `Asset<T>` that comes out correctly typed. Bytes carry
  // neither a method nor a type argument, so `Isolate.spawn`'s object copy is
  // the only thing that can move one; what it would take instead is a
  // serialization the engine does not have and every game would have to
  // implement.
  //
  // The half that is only true today: the address lists are variable-length,
  // and the param vocabulary has no field kind for a list. That is a property
  // of the vocabulary rather than of the design - a control batch is a plain
  // `Uint8List` the sender builds and hands to `controlSend`, nothing
  // ring-allocates it, and `ParamBatch.adoptIncoming` walks records forwards
  // rather than indexing them, so a param record's stride is not load-bearing
  // the way an archetype row's is. If a dynamic-length field turns up, this
  // half stops applying; the half above still stands.

  /// Game -> main: decode these addresses, whose keys ride along because main
  /// ran no `describeAssets` and has nothing to resolve an address against.
  loadAssets,

  /// Main -> game: one address finished, with the running counts and whatever
  /// decoding discovered (`AssetLoader.describe`).
  assetLoaded,

  /// Main -> game: the whole request is finished, carrying the first failure
  /// if there was one.
  assetsDone,

  /// Game -> main: drop these payloads. Fire and forget - the declaration is
  /// already gone on the asking copy.
  unloadAssets,
}

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
///   void describeState(StateDescriptor d) {
///     super.describeState(d);
///     score = d.hasInt32();
///   }
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
///    `await game.start()` - is an inert *handle*. Its systems never tick, it
///    registers no archetypes and it owns no pages. It exists to (a) send and
///    handle commands ([describeCommands]), (b) receive tick-complete
///    notifications ([addTickListener]) and state-channel updates, and (c)
///    build widgets ([buildView]). It does **not** read component data:
///    `Entity.get` on this copy throws saying so. See
///    `GameRuntime.releaseScenePages` for what a second reader would cost.
///
/// Calling a gameplay method on the handle copy does not reach the
/// simulation. Anything that must cross goes through one of exactly two
/// channels, split by volume: bulk, per-tick traffic through a shared
/// `RingBuffer` ([describeCommands], [describeBuffers]), rare control signals
/// through a `SendPort` ([stop], tick pings, state-channel addresses).
///
/// The spawn message is why this class must hold no **unsendable** state when
/// [start] hands it over - and that set is small:
///
///  * A `Pointer` **is** sendable, and arrives at the *same address*. Shared
///    native memory crosses for free, which is precisely what lets this class
///    be fully described before the spawn and inherited by the copy. Proven
///    by `tool/spawn_pointer_spike.dart`.
///  * `Type` objects and **closures** are sendable too
///    (`tool/spawn_registry_spike.dart`).
///  * A `ReceivePort`, a `Completer`, and any native handle (`dart:ui.Image`)
///    are **not**. Dart names the exact field path in the failure, which is
///    worth knowing: it is how the asset-decode gate was found.
///
/// Two things that are *not* about sendability still hold. **Statics do not
/// cross at all** - they belong to no object graph - so the registries are
/// captured onto this object and restored on arrival, in `_captureRegistries`.
/// And a **cached typed-data view over native memory is copied by value**,
/// silently detaching from the memory it viewed; never keep one in a field (see
/// `_StateChannelBase.reattach`).
///
/// # Isolate affinity
///
/// `Game` is **not** a `GameListener`: it lives where Flutter
/// does, and every event in this engine happens on the game isolate. It
/// cannot be `FixedTickable` - the `on GameListener` bound says so at compile
/// time - so put the tick on the [GameState], a `SceneStruct` or a
/// `GameSystem`. What `Game` does for Flutter it does through a plain method,
/// [buildView]. See `GameEvent`'s doc.
abstract class Game implements RandomOwner {
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
  /// slower than wall clock instead of locking up.
  int get maxFixedStepsPerAdvance => 5;

  /// Stop the fixed tick while the app is hidden. Default true.
  ///
  /// A backgrounded game that goes on simulating burns a phone's battery on a
  /// world nobody is looking at, so the safe behaviour is the default and
  /// opting out is explicit. Return false for a game that has to keep running
  /// unattended - a live server-authoritative session, a running download, a
  /// timer the player expects to have advanced while they were away.
  ///
  /// This is about *visibility*, never focus: a desktop window that merely
  /// loses focus is still visible and never reaches this. See
  /// [AppVisibilityListener].
  ///
  /// Opting out does not promise the game keeps ticking. A phone is free to
  /// suspend or kill a backgrounded process whatever this says; false only
  /// means the engine will not stop the tick itself.
  bool get pauseWhenHidden => true;

  /// Page size for this game's one [MemoryPool], in bytes.
  ///
  /// A page costs **3x** this in native memory - one slot per triple-buffer
  /// state - so the 64 MiB default is ~192 MiB resident per page. Override it
  /// down for a test, a headless server build, or a game whose archetypes are
  /// small enough that a full page would be mostly empty.
  ///
  /// One pool per `Game`, not per scene: a `SceneStruct` is a
  /// declaration that may back several loaded scenes at once, so it cannot own
  /// the storage they allocate out of. See `SceneStruct.pool`.
  int get pageSize => 64 * 1024 * 1024;

  /// The most pages this game's pool will ever allocate. The pool never grows
  /// past it - exhausting it throws, so a runaway spawn loop reports itself
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
  ///   super.describeScenes(descriptor);
  ///   mainScene = descriptor.has(MainScene());
  ///   hudScene = descriptor.has(HudScene());
  /// }
  /// ```
  ///
  /// Like every other declare pass this hands back the instance it was given,
  /// to keep in a `late final` field (the typed-handle rule) - there is no
  /// separate handle type, and `descriptor.has(MainScene())` reads the same as
  /// `descriptor.has(MySystem())` and `descriptor.has(_Unit())` because it is
  /// the same idea.
  ///
  /// # What declaring buys, and what it does not
  ///
  /// Declaring a scene here **registers its archetypes and declares its
  /// assets, at boot** - before the game isolate is spawned, and before any
  /// system's `describeQuery` runs, so this pass comes first.
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
  /// registers lazily, so this pass is additive, not a new obligation.
  @mustCallSuper
  void describeScenes(GameSceneDescriptor descriptor) {}

  /// The engine's own control commands, declared so both copies agree about
  /// them before a game declares anything of its own. See
  /// [_SetVisibleCommand] for why the four that reach the tick are
  /// receipt-delivered.
  late final _SetVisibleCommand _setVisibleCommand;
  late final _SetPausedCommand _setPausedCommand;
  late final _SetTimeScaleCommand _setTimeScaleCommand;
  late final _StepOnceCommand _stepOnceCommand;
  late final _ReportDisabledSystemCommand _reportDisabledSystemCommand;

  /// Declares every command this game understands, and registers the handlers
  /// that run on the **Flutter** isolate.
  ///
  /// ```dart
  /// late final Damage damage;
  /// late final SaveGame save;
  ///
  /// @override
  /// void describeCommands(CommandDescriptor descriptor) {
  ///   super.describeCommands(descriptor);
  ///   damage = descriptor.has(Damage.new);   // handled on the game isolate
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
  ///   final enemy = loadedScenes.single.addEntity(level.enemy);
  ///   level.enemy.x[enemy] = at.x;
  ///   return enemy;
  /// });
  /// ```
  ///
  /// The framework ships no `spawnEntity(archetypeId)` for this: an archetype
  /// id is a game-isolate identifier, so handing one to the Flutter isolate
  /// makes it name something that isolate cannot see. Naming the *intent*
  /// leaves the prefab lookup on the side that owns the memory.
  @mustCallSuper
  void describeCommands(CommandDescriptor descriptor) {
    _setVisibleCommand = descriptor.has(_SetVisibleCommand.new);
    _setPausedCommand = descriptor.has(_SetPausedCommand.new);
    _setTimeScaleCommand = descriptor.has(_SetTimeScaleCommand.new);
    _stepOnceCommand = descriptor.has(_StepOnceCommand.new);
    _reportDisabledSystemCommand = descriptor.has(
      _ReportDisabledSystemCommand.new,
    );
    descriptor.hasSink(
      _reportDisabledSystemCommand,
      _onSystemDisabledReport,
    );
  }

  void _onSystemDisabledReport(_DisabledSystemReport params) {
    onSystemDisabled(params.systemName, params.error, params.stackTrace);
  }

  /// Called on the main isolate when a system on the game isolate threw out
  /// of an event dispatch and was switched off.
  ///
  /// The three strings are cut to fit the command that carried them, so a
  /// long message or a deep stack arrives truncated instead of not at all.
  /// [systemName] is `runtimeType.toString()` and is for reading, not for
  /// looking anything up: nothing here resolves a system by its name.
  ///
  /// The default hands it to [FlutterError.reportError], which is what makes
  /// a release build say something at all. Override to send it somewhere else
  /// - a crash reporter, an in-game console - and **do not** call `super`
  /// unless you want both. That is the whole reason this is not
  /// `@mustCallSuper`: a game routing diagnostics to its own sink is the case
  /// this exists for, not a mistake to guard against.
  ///
  /// Under `Game.startInline` - a test, a headless host, and every web build
  /// - there is no second isolate, so this runs on the game's own stack
  /// inside the dispatch guard. Throwing from here is caught and dropped, never
  /// allowed to end the tick; see `GameSystem.disableAfterUncaught`.
  void onSystemDisabled(String systemName, String error, String stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError('system $systemName threw: $error'),
        stack: stackTrace.isNotEmpty ? StackTrace.fromString(stackTrace) : null,
        library: 'good',
        context: ErrorDescription(
          'which has been switched off. It stays off until something on the '
          'game isolate calls GameState.enableSystem for it - a command '
          'handler, if the throw was transient and you want it back',
        ),
      ),
    );
  }

  /// Queues the game -> main report for a system the dispatch guard has just
  /// switched off.
  ///
  /// Fire-and-forget: this is called from inside the guard, on a tick that has
  /// already gone wrong, so it must not be able to fail.
  /// The three strings are cut to fit their fields by
  /// [_ReportDisabledSystemCommand.bufferFromParams] - one place, because an
  /// oversized write is refused and a throw from the reporting path would
  /// take out the report of the throw.
  @internal
  void reportDisabledSystem(
    String systemName,
    String error,
    String stackTrace,
  ) {
    _reportDisabledSystemCommand((
      systemName: systemName,
      error: error,
      stackTrace: stackTrace,
    ));
  }

  /// Registers the game-isolate handlers for the four commands [Game]
  /// declared above.
  ///
  /// Here and not in `GameState.describeCommands`: the commands are private to
  /// this file and stay that way - a game has no reason to reach them, and
  /// `Game.pause` is the surface it uses instead.
  ///
  /// All four are **receipt-delivered**. Every one can stop the fixed tick,
  /// and a tick-delivered handler is pumped from `runFixedStep` - so the
  /// message that started the tick again would be waiting on the tick it
  /// stopped. None of them writes component data, which is the rule that
  /// buys them that delivery; see `CommandDescriptor.hasControlSink`.
  @internal
  void describeEngineCommandHandlers(
    CommandDescriptor descriptor,
    GameState<Game> state,
  ) {
    descriptor
      ..hasControlSink<bool>(_setVisibleCommand, state.setVisible)
      ..hasControlSink<bool>(
        _setPausedCommand,
        (bool value) => state.paused = value,
      )
      ..hasControlSink<double>(
        _setTimeScaleCommand,
        (double value) => state.timeScale = value,
      )
      ..hasControlSignal(_stepOnceCommand, state.stepOnce);
  }

  /// Declares this game's **auxiliary ring buffers** - shared-memory SPSC
  /// channels, allocated on the simulating copy and handed to the other one
  /// the same way the command ring and the pool's pages already are.
  ///
  /// `good` knows nothing about what travels through them. The command ring
  /// ([dispatchCommand]) is the framework's own, hardcoded, main -> game
  /// lane; this is the generic escape hatch for every *other* lane-2-shaped
  /// channel a layer above wants - the one that motivated it is
  /// `goo2d_render`'s per-tick draw-command buffer (game -> main), which
  /// must not put a Flutter- or renderer-specific field on this class.
  ///
  /// Each declaration returns a [BufferHandle] the declarer keeps in a field
  /// (the typed-handle rule) - there are no buffer names and nothing to look
  /// up:
  ///
  /// ```dart
  /// late final BufferHandle drawBuffer;
  ///
  /// @override
  /// void describeBuffers(BufferDescriptor d) {
  ///   super.describeBuffers(d);
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
  /// Runs on both copies, before the spawn and again after it, so both agree
  /// on the declared set *and on its order* - which is the handle's identity
  /// on the wire.
  ///
  /// **A system cannot declare one**, and there is no
  /// `GameSystem.describeBuffers` to reach for. Systems are constructed on the
  /// game isolate only, which is after this pass and after the allocation it
  /// feeds, so a buffer declared there would have an index on one copy and
  /// none on the other. A library that ships a system and needs a buffer
  /// ships a `Game` mixin to declare it - `Renderer2D` does exactly that, one
  /// handoff per camera view - and the system reads the handle off the
  /// `Game`.
  @mustCallSuper
  void describeBuffers(BufferDescriptor descriptor) {}

  /// Declares this game's camera views - the places it can be drawn.
  ///
  /// ```dart
  /// late final CameraView mainCamera;
  ///
  /// @override
  /// void describeCameras(CameraDescriptor descriptor) {
  ///   super.describeCameras(descriptor);
  ///   mainCamera = descriptor.has();
  /// }
  /// ```
  ///
  /// Runs **before** [describeBuffers], and that ordering is what the split
  /// of responsibility rests on: `good` knows a view exists and how big it is,
  /// while whatever draws it (`goo2d`'s renderer, a future `goo3d`'s) sizes
  /// and allocates its own per-view storage in its `describeBuffers`. This
  /// kernel never learns what a frame is.
  ///
  /// A game that declares none draws nothing and is shown with
  /// `GameView.headless` - a HUD-only or headless-plus-Flutter setup, which
  /// is a first-class shape here, not a degenerate one.
  @mustCallSuper
  void describeCameras(CameraDescriptor descriptor) {}

  /// Registers the decoders for every payload type this game loads.
  ///
  /// ```dart
  /// @override
  /// void describeAssetLoaders(AssetLoaderRegistrar loaders) {
  ///   super.describeAssetLoaders(loaders);
  ///   loaders.register<Dialogue>(const DialogueLoader());
  /// }
  /// ```
  ///
  /// Each layer contributes its own and chains, so a game adds a decoder
  /// without knowing what the engine below it registered. Registering a type
  /// the layer below already covers replaces it, which is how a game
  /// substitutes its own decoder for an engine one - see
  /// [AssetLoaders.register].
  ///
  /// # Where this runs, and why it is not with the others
  ///
  /// On the isolate that **decodes**, once, before anything is loaded - and
  /// never on the game isolate. `AssetLoaders` is a per-isolate static map and
  /// the game isolate holds payload-free declarations, so a decoder there
  /// would answer for nothing; its own `StateError` says as much. That makes
  /// this the one `describeX` pass outside the shared declaration sequence both
  /// copies run. It is called from [_bootMain], which main runs before the
  /// spawn and which the game isolate never runs at all.
  ///
  /// # Register here, not from a constructor
  ///
  /// A decoder registered from some object's constructor exists only if that
  /// object gets built, and when it does not, the asset load fails at boot
  /// with an error naming the missing loader instead of the cause. `Texture`
  /// was registered from `DrawCanvas2D`'s constructor - a canvas is built only
  /// where Flutter is attached, and always before anything it draws is decoded
  /// - and that left the example suite red for sixty commits (#83). Audio has
  /// no canvas to hang on at all.
  @mustCallSuper
  void describeAssetLoaders(AssetLoaderRegistrar loaders) {
    // The kernel ships one payload type, so the kernel registers its decoder.
    // `AudioClip` is bytes and a container name - no canvas, no device, no
    // dimension - which is why it sits here rather than in a renderer package
    // and why a 3D game gets sound loading without goo3d declaring anything
    // (#93). Reading the bytes is all this buys: nothing here plays them.
    loaders.register<AudioClip>(const AudioLoader());
  }

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
  ///     super.describeState(descriptor);
  ///     score = descriptor.hasInt32();
  ///   }
  /// }
  /// ```
  ///
  /// This is the "one scalar value, read by the UI" lane, and it is *not* any
  /// of the three that already exist:
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
  /// # The two hosts
  ///
  /// Exactly two types declare state - this one and `GameSystem` - and both
  /// carry this method with an empty body, so declaring a channel is one
  /// override and nothing else.
  ///
  /// The set is two and not more for a hard reason: **a channel's storage is
  /// allocated on the main isolate, before the spawn**, and its identity
  /// across the boundary *is* its declaration index in that one pass. So only
  /// something main declares can own an index. That rules out three things,
  /// each for its own reason:
  ///
  ///  * [GameState] is *built on the game isolate*, after the allocation it
  ///    would have to be part of. Publish from the `Game` instead and write
  ///    through `state.game.myChannel`.
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
  @mustCallSuper
  void describeState(StateDescriptor descriptor) {}

  /// The seed every [RandomStream] this game declares is derived from.
  ///
  /// An overridable member like [pageSize] and [fixedTimeStep], and for the
  /// same reason - it is configuration a game states once. Unlike those, it
  /// often wants a *runtime* value, and a getter takes one without any extra
  /// machinery: back it with a final field and a constructor argument.
  ///
  /// ```dart
  /// class MyGame extends Game {
  ///   MyGame({this.randomSeed = 0});
  ///
  ///   @override
  ///   final int randomSeed;
  /// }
  /// ```
  ///
  /// That is what a replay needs: it supplies the seed it recorded. Reachable
  /// before `start()` and carried to the game isolate with the rest of this
  /// object, so both copies derive the same streams without anything being
  /// sent.
  ///
  /// A seed is part of a save. Recording the inputs without it reproduces
  /// nothing.
  int get randomSeed => 0;

  /// Declares this game's random streams - see [RandomStream].
  ///
  /// ```dart
  /// late final RandomStream loot;
  ///
  /// @override
  /// void describeRandom(RandomDescriptor descriptor) {
  ///   super.describeRandom(descriptor);
  ///   loot = descriptor.has();
  /// }
  /// ```
  ///
  /// Runs on main before the spawn, so the streams a game keeps in fields
  /// cross to the game isolate already built. Declaration order is a stream's
  /// identity, exactly as it is for a command.
  @mustCallSuper
  void describeRandom(RandomDescriptor descriptor) {}

  @override
  bool get randomDrawAllowed => runtimeOrNull?.state?.isSimulating ?? false;

  @override
  int get randomTick => runtimeOrNull?.state?.tick ?? 0;

  @override
  String get randomOwnerLabel => runtimeOrNull == null
      ? 'a $runtimeType that has not been started'
      : "the main isolate's copy of $runtimeType";

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
  /// every action reads its default forever - correct, not broken, and spelled
  /// out in `InputDevice`'s doc.
  @mustCallSuper
  void describeInputs(InputDescriptor input) {
    input.hasDefaultValue<bool>(false);
    input.hasDefaultValue<Vector2>(Vector2.zero());
  }

  // --- declarations -------------------------------------------------------
  //
  // What a `Game` holds, and the whole of it: the *description*. Every field
  // below is filled by a declaration pass and then never changes again.
  //
  // Nothing here belongs to a **run**. The flags saying who owns the memory
  // and who simulates, the ports, the tick counter, the `GameState`, the
  // command registry and its rings all used to live here and now live on
  // [GameRuntime], built by `Game.start`.
  //
  // One instance still backs exactly **one** run - see
  // [_requireNotYetDescribed] - so this is not about reuse. It is about which
  // object answers which question: a description is read-only once boot has
  // run, and a run is the only thing that changes. Keeping them apart is what
  // lets the *runtime* be the spawn message and swap its isolate roles,
  // while the description simply arrives on the far side identical.

  // No system list here. `describeSystems` is declared on this class and runs
  // in [GameRuntime.bootGame]; the objects it produces are held by the
  // `GameState`, on the isolate that ticks them.

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
  // declares. Which is why the two copies are allowed to disagree about what
  // is in here: main runs `Game.describeInputs` and stops, while the
  // simulating copy also runs every system's and then seals. Empty at spawn
  // time like every other field here.
  final InputRegistry _inputs = InputRegistry();

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
  final Assets assets = Assets();

  // There is no `_owns`/`_simulates`/`_booted`/`_tick` here, and no
  // `GameState`, and that absence is the point of this class.
  //
  // Every one of those is a fact about a **run**, not about a description, and
  // they now live on [GameRuntime]. The user-facing consequence is that
  // nothing a run does can be observed through the description: reading a
  // `Game` tells you what was declared, and the handle tells you what is
  // happening.
  //
  // [assets] is the exception that stays, and legitimately - it is reached
  // through `ArchetypeStorage` on the row-read path, and with one run per
  // instance its lifetime is the instance's lifetime anyway.

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
  /// [GameView] feeds this automatically. It is public because a headless host
  /// with no widget tree - a test, a replay, a bot - legitimately needs to
  /// write input, and the alternative would be a second write path that only
  /// tests use (the no-specialised-variant rule). Null before `start()` and
  /// after `stop()`.
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
  /// This is the surface the **pointer** is currently in: refreshed by the
  /// `GameView` the cursor is over. A game no cursor has entered yet - and a
  /// game played on a keyboard or a pad, where none ever will - reads the
  /// size its view laid out at instead, resizes included.
  ///
  /// **Not a camera viewport.** For projecting world to screen - or screen
  /// back to world - use `CameraView.viewportWidth`/`viewportHeight`, which
  /// belong to a specific view and are what `CameraProjection` centres on.
  /// These two exist because `CursorPosition` reports in one surface's
  /// coordinates and a pointer is only ever in one surface at a time, which is
  /// a coherent single fact; a *viewport* is not, once there are two views.
  ///
  /// A headless game reads zero here, never a guessed resolution, and that is
  /// load-bearing: every consumer of these treats a zero view as "no view",
  /// which is what makes a headless test and a real window agree about
  /// everything except the centring they cannot share.
  double get viewWidth => _inputs.state.viewWidth;

  /// [viewWidth]'s other half, with the same rules.
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
  // `bootStateDescriptor` used to live here: a getter handing out the live
  // `StateDescriptor` mid-boot, so that a second declaring source could reach
  // it without being passed it. It is **deleted**, and what deleted it was
  // running out of second sources - `GameSystem.describeState` went with the
  // systems to the game isolate, and a channel's storage is allocated on main
  // before the spawn, so there is exactly one pass that can declare one and it
  // receives the descriptor as an argument. The descriptor is now a local in
  // that pass and cannot outlive it, which is the property the getter's
  // "not in a boot pass" error was approximating.

  // --- bring-up ---------------------------------------------------------

  /// Brings [game] up and hands it straight back, running.
  ///
  /// ```dart
  /// final game = await Game.start(MyGame());
  /// game.spawnEnemy();          // a command
  /// final score = game.score;   // a StateChannel, for a widget
  /// await game.stop();
  /// ```
  ///
  /// **One object, because there is one of everything.** An instance backs
  /// exactly one run for its whole life, so "the game" and "the run" name the
  /// same thing and splitting them across two objects the caller has to hold
  /// bought nothing. The run's handle is framework-facing - a renderer
  /// receives one in [buildView] - and not something an app obtains.
  ///
  /// Static, not an instance method, so the type flows: `G` binds from
  /// the argument, which is what makes `await Game.start(MyGame())` a `MyGame`
  /// with nothing spelled out. It also keeps "start" off the surface of a
  /// `Game` that has not been started, where every other lifetime member
  /// throws.
  ///
  /// What comes back still cannot reach the simulation: [state], [advance] and
  /// [runFixedStep] all throw on a run started this way, because the world is
  /// on another heap. [startInline] is what a test or a headless host uses to
  /// get one it can drive.
  ///
  /// **One instance, one run.** Starting the same `game` twice throws, and so
  /// does starting it again after [stop]; two games means two instances. The
  /// reason is that a declaration is one-shot and holds its run's storage
  /// directly - see [_requireNotYetDescribed], which says it in full at the
  /// point it refuses.
  ///
  /// On the web this runs the single-isolate implementation, because there are
  /// no isolates in the shared-memory sense there - but it returns the same
  /// type, so a web game gets the same surface as a native one and never
  /// depends on the state happening to be reachable.
  ///
  /// With [autoTick] false nothing ticks until someone calls [advance] by hand
  /// - which is what makes the scheduler testable deterministically, with no
  /// timer and no wall clock involved. Note that in the spawned configuration
  /// the only code that *could* drive it by hand runs on the game isolate, so
  /// `autoTick: false` here is a game that never ticks; the knob is really for
  /// [startInline].
  static Future<G> start<G extends Game>(G game, {bool autoTick = true}) async {
    game._requireNotYetDescribed();
    final runtime = GameRuntime(game);
    // `drivable: false` even on the web, where this boots inline. The
    // mechanism is the platform's business; the surface is the caller's, and
    // this caller asked for a game to run rather than one to drive. See
    // `GameRuntime.drivable`.
    await runtime.boot(inline: kIsWeb, drivable: false, autoTick: autoTick);
    return game;
  }

  /// Brings [game] up **on the calling isolate** - one copy doing both jobs -
  /// and hands back a handle that can reach the simulation.
  ///
  /// For tests, headless hosts, replays and tools. `autoTick: false` (the
  /// default here) leaves the clock entirely to [advance], which is what makes
  /// the scheduler testable with no timer and no wall clock involved.
  ///
  /// The difference from [start] is not the return type - both hand back the
  /// game - it is that [state], [advance] and [runFixedStep] *work* on a run
  /// started here and throw on one started by [start].
  ///
  /// **At most one inline run per isolate**, and this bound is separate from
  /// the one-run-per-instance rule [start] describes - it binds even when the
  /// two runs are two different `Game` types. Statics are per-isolate, and
  /// `ArchetypeRegistry` is one of them: a second inline run would find the
  /// first run's `ArchetypeStorage` for any prefab type they share, bound to
  /// the first run's `MemoryPool`, and spawn into its memory. Concurrent runs
  /// need [start], which gives each one its own isolate and so its own
  /// registries - and are therefore not available on the web.
  static Future<G> startInline<G extends Game>(
    G game, {
    bool autoTick = false,
  }) async {
    game._requireNotYetDescribed();
    final runtime = GameRuntime(game);
    await runtime.boot(inline: true, drivable: true, autoTick: autoTick);
    return game;
  }

  // --- this instance's run ------------------------------------------------
  //
  // The run, reachable from the description. [GameRuntime] is set by
  // `GameRuntime.boot`, before the spawn, so **both copies have one** and each
  // has the right one for its own isolate - which is what lets the members
  // below give a different, correct answer on each side rather than a null.
  GameRuntime? _runtime;

  /// This game's run, for the framework's own use.
  @internal
  GameRuntime? get runtimeOrNull => _runtime;

  GameRuntime _requireRuntime(String member) {
    final runtime = _runtime;
    if (runtime != null) return runtime;
    throw StateError(
      '$runtimeType.$member was called on a game that has not been started. '
      '`await Game.start($runtimeType())` starts one, and hands back the same '
      'instance, running.',
    );
  }

  /// Whether this game is running.
  ///
  /// Answers on both copies, about that copy: false before [start] and after
  /// [stop].
  bool get isRunning => _runtime?.isRunning ?? false;

  /// Fixed ticks completed.
  ///
  /// On the main copy this is what the simulating copy last reported, so it
  /// lags by one port message; on the game isolate it is exact.
  /// `GameState.tick` is the same number read from the simulation side.
  int get tick => _requireRuntime('tick').tick;

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
  /// Every call in one batch has to be handled on the same isolate, since a
  /// batch is one message with one reply; adding a call bound for the other
  /// side throws at the line that adds it.
  ///
  /// Throws on a game that has not been started - there is no registry to
  /// batch into yet.
  CommandBatch createCommandBatch() =>
      _requireRuntime('createCommandBatch').createCommandBatch();

  /// Brings this game down and releases every shared allocation.
  ///
  /// In the spawned configuration this asks the game isolate to unmount and
  /// waits for it, then frees the memory this copy owns. Calling it twice is a
  /// no-op; calling it on a game that was never started throws.
  Future<void> stop() => _requireRuntime('stop').shutDown();

  /// This game has stopped, **on the presentation isolate**.
  ///
  /// The mirror of `GameState.onUnmounted`, which is the same moment on the
  /// *simulation* side, and which side a teardown belongs on follows from what
  /// it holds: a decoded frame, a `SchedulerBinding` callback or an image cache
  /// are main-isolate things and are released here; scenes, entities and pool
  /// pages are game-isolate things and are released there.
  ///
  /// Dispatched **before** anything is torn down, so the shared buffers are
  /// still mapped - a frame callback cancelled here cannot be mid-read of a
  /// draw buffer that is about to be freed.
  ///
  /// `Renderer2D` is the motivating case: it drops its decoded surfaces and
  /// unhooks its frame callback here, which is what stops a stopped game from
  /// keeping the scheduler awake forever.
  void onStopped() {}

  // --- driving the simulation from here -----------------------------------
  //
  // Only legal on an inline run, and enforced rather than documented.
  // `Game.state` existed once and was deleted for being the shape that
  // "compiles everywhere and works in one place": on a spawned run the world
  // is on another heap, and this copy's `GameState` is a declaration mirror
  // that would answer with an empty world rather than fail.
  //
  // They are back because `Game.startInline` returns the game rather than a
  // handle, so a *type* can no longer carry the distinction. The check is on
  // `GameRuntime.drivable` - which is what the caller asked for - rather than
  // on null (which would let main's declaration mirror answer) or on `inline`
  // (which would let the web answer where native throws).

  GameRuntime _requireInline(String member) {
    final runtime = _requireRuntime(member);
    if (runtime.drivable) return runtime;
    throw StateError(
      '$runtimeType.$member is only available on a game started with '
      'Game.startInline(), and this one was started with Game.start().\n'
      '\n'
      'On a spawned run the world is on another heap: this copy holds a '
      'GameState that exists only to have run the same declaration passes, '
      'with no scenes and no entities. It refuses on the web too, where '
      'Game.start() does run inline and could technically answer - because a '
      'game that reached the world here would compile and work on the web and '
      'throw on native, off the same source.\n'
      '\n'
      'Use Game.startInline() for a test or a headless host that drives the '
      'simulation by hand, or reach the world from a handler registered in '
      'GameState.describeCommands, which runs where it is.',
    );
  }

  /// The simulation half - scenes, systems, the pool, the command drain.
  ///
  /// **Inline runs only**; see [_requireInline].
  GameState get state => _requireInline('state').state!;

  /// Advances the clock by [elapsed], running as many fixed steps as it
  /// affords and then one presentation pass. Returns the number of fixed steps
  /// taken.
  ///
  /// This is the whole scheduler; the timer that `autoTick` installs does
  /// nothing but call it. Driving it by hand is not a reduced-fidelity
  /// stand-in for the real loop, it *is* the real loop.
  ///
  /// **Inline runs only**; see [_requireInline].
  int advance(Duration elapsed) =>
      _requireInline('advance').state!.advance(elapsed);

  /// Runs exactly one fixed step, whatever the clock says. For a test that
  /// wants a step, not a duration.
  ///
  /// **Inline runs only**; see [_requireInline].
  void runFixedStep() => _requireInline('runFixedStep').state!.runFixedStep();

  /// Sets how fast simulated time runs - 1 real time, 0.25 quarter speed, 0
  /// stopped. See `GameState.timeScale`, which this reaches across the
  /// isolate boundary to set.
  ///
  /// Callable from the main isolate, because that is where a pause button
  /// lives. Fire and forget: it takes effect on the game isolate's next
  /// frame, and there is nothing to await.
  ///
  /// A fixed tick is always exactly [fixedTimeStep]; this changes how often
  /// one happens, never how big it is.
  void setTimeScale(double scale) {
    assert(
      scale >= 0,
      'timeScale must not be negative (got $scale). Nothing in this engine '
      'is reversible.',
    );
    _sendControl(() => _setTimeScaleCommand(scale));
  }

  /// Stops the fixed tick without disturbing [setTimeScale], so a game paused
  /// at half speed comes back at half speed.
  ///
  /// Presentation keeps running, which is what lets a pause menu draw itself.
  /// Unrelated to [pauseWhenHidden]: a game paused here stays paused across
  /// being hidden and shown again.
  void pause() => _sendControl(() => _setPausedCommand(true));

  /// Undoes [pause]. A game that was never paused is unaffected.
  void resume() => _sendControl(() => _setPausedCommand(false));

  /// Advances exactly one fixed step, whatever the clock and scale say.
  ///
  /// For stepping a paused game - a debugger, a replay. Leaves the
  /// accumulator untouched, so unpausing afterwards resumes from where it
  /// was. See `GameState.stepOnce`.
  void stepOnce() => _sendControl(_stepOnceCommand.call);

  /// Sends one of the engine's control commands, if there is a run to send it
  /// to.
  ///
  /// The guard is what keeps these callable on a `Game` that has not started:
  /// the commands are `late final`, declared during boot, so reaching one
  /// before then would throw instead of no-op - and a pause button that throws
  /// because the game has not finished starting is not an improvement on one
  /// that does nothing.
  ///
  /// The future is dropped. A control command completes when the batch reaches
  /// the port, not when the handler has run, so there is nothing here worth
  /// waiting for.
  void _sendControl(Future<void> Function() send) {
    if (runtimeOrNull?.isRunning != true) return;
    unawaited(send());
  }

  // --- one instance, one run ----------------------------------------------
  //
  // A `Game` instance may be started **once**, and that is the design rather
  // than a limitation waiting to be lifted. Two things say so, and they agree:
  //
  //  * The declaration passes are not re-runnable, and that follows from the
  //    API's own shape rather than from any implementation choice. the typed-handle rule has every declaration land in a `late final` field
  //    (`score = descriptor.hasInt32()`), and a `late final` is assignable
  //    exactly once. A second pass throws `LateInitializationError` from
  //    inside the user's own `describeState` - and does it *after* appending a
  //    second set of channels to the declared list, so an unguarded retry
  //    leaves the instance permanently describing twice the storage it should.
  //  * A declared handle **is** its run's storage. A `StateChannel` holds the
  //    `TripleBuffer`, a `BufferHandle` the `RingBuffer`, a `GameCommand` the
  //    sender that routes it. That is what keeps every one of them a plain
  //    field read on the tick path, with no per-access indirection to resolve
  //    which run is asking - and it is only sound while there is one answer.
  //
  // Making an instance reusable means separating those: declarations become
  // pure (an index plus metadata) and every run gets its own storage table,
  // reached as `game.score[run].value`. That buys back the multiplicity at the
  // cost of an indirection on the hottest paths in the engine, and a second
  // instance is the cheaper way to get a second game.
  //
  // Restarting a *stopped* instance is refused by the same rule and for the
  // first reason alone: the storage is long gone, but declaring and binding
  // are one pass, so there is no way to re-bind without re-running the user's
  // `describeX`.
  bool _described = false;

  void _requireNotYetDescribed() {
    if (!_described) return;
    throw StateError(
      '$runtimeType has already been started. A Game instance describes one '
      'game and backs one run of it, for its whole life - starting it again, '
      'including after stop(), is not supported.\n'
      '\n'
      'Construct a second instance for a second run:\n'
      '  final run1 = await Game.start(MyGame());\n'
      '  final run2 = await Game.start(MyGame());\n'
      '\n'
      'The reason is that a declaration is one-shot and *is* its storage: '
      '`score = descriptor.hasInt32()` fills a `late final`, and the '
      'StateChannel it returns holds the run\'s TripleBuffer directly, which '
      'is what keeps reading it a plain field access on the tick path. A '
      'second run would allocate over the first run\'s pointers and both '
      'would then read the second run\'s memory - wrong answers rather than a '
      'crash, which is why this refuses up front instead.',
    );
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
  ///    before the declaration, and the game isolate must inherit the
  ///    numbering instead of re-deriving it.
  ///  * the `GameState` carrying `describeSystems` is *built* here, by
  ///    [createState] - a `GameState` mixin has to be able to contribute a
  ///    system, which is what makes `extends Game2D` (and the `GameState2D` it
  ///    forces out of `createState`) the whole opt-in for 2D rendering. But
  ///    the pass itself is **invoked** from [_bootGame] and only there, so the
  ///    system objects only ever come into being on the copy that ticks them.
  ///    Building the declarer on one side and running its pass on the other is
  ///    exactly the split this method's name describes.
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
  void _bootMain(GameRuntime runtime) {
    // One StateDescriptor for the whole pass, and a local rather than a field:
    // exactly one pass can declare a channel (its storage is allocated here,
    // before the spawn), so nothing outside this method has any business
    // reaching it, and a local cannot outlive the window it is valid in.
    final states = _StateDescriptor(runtime);

    // Constructed here, and *only* constructed: its `onMounted` - the pass
    // that loads scenes and so spawns a world - runs in [_bootGame], on the
    // other copy. This one is a declaration mirror: it exists so that
    // `describeCommands` below can register the same command handlers in the
    // same order on both copies, and it never simulates, never mounts and
    // never holds a scene. It also never gets its systems - `describeSystems`
    // is called from [_bootGame], so a `GameSystem` is one thing the mirror
    // has no counterpart for.
    final state = createState();
    runtime.state = state;
    state.bindRuntime(runtime, simulating: runtime.simulates);

    // First, and on this copy only: a decoder has to exist before anything is
    // loaded, and nothing below here loads. See [describeAssetLoaders] for why
    // this pass is not one of the two both copies run.
    describeAssetLoaders(const _LoaderRegistrar());

    // --- describeState, the only call site --------------------------------
    //
    // Declaration order here *is* channel-index order, and an index is what
    // crosses the wire, so it is observable. There is exactly one source, and
    // the constraint that makes it one is sharper than "exists for the whole
    // run": a channel's storage is allocated here, on main, before the spawn,
    // so only something this pass runs can own an index. The `GameState` and
    // each `GameSystem` were both call sites once; both went to the game
    // isolate, which is after this allocation. Scenes and their prefabs were
    // dropped earlier for the neighbouring reason (loaded after boot, possibly
    // repeatedly). See [describeState].
    describeState(states);
    // Beside describeState and for the same reason: this runs on main before
    // the spawn, so the streams ride the object graph already built and both
    // copies derive identically without a message.
    describeRandom(RandomDescriptor(this, randomSeed));

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

    // Every user-supplied declaration has now run against this instance, and
    // none of them may run again - see [_requireNotYetDescribed]. Set before
    // the allocation phase rather than after the whole boot, so a start that
    // fails part-way still refuses the retry that would double the
    // declarations.
    _described = true;

    if (runtime.owns) _bootAllocate(runtime);
    _bootFinalize(runtime, states);
  }

  /// Everything the **game isolate** declares, after the spawn.
  ///
  /// Two kinds of thing, and both are here for the same underlying reason -
  /// they touch state that does **not** cross `Isolate.spawn`:
  ///
  ///  * [describeScenes] registers archetypes and component bits into
  ///    `ArchetypeRegistry`/`ComponentTypeRegistry`, which are *statics*.
  ///    Statics belong to no object graph, so they do not ride the copy.
  ///    Running the pass here is what saves hand-carrying the registries
  ///    across in a snapshot: one registrar means there is no second numbering
  ///    to keep in agreement.
  ///  * `describeQuery` resolves against those archetypes, so it has to follow
  ///    them, so it is not up in [_bootMain] with the rest of the
  ///    per-system passes. Queries are read only by ticking systems, and only
  ///    this copy ticks.
  ///
  /// Inline runs this immediately after [_bootMain], on the one copy that does
  /// both jobs.
  void _bootGame(GameRuntime runtime) {
    final state = runtime.state!;

    // Scenes before systems, and it has to be that way round: a system's
    // `describeQuery` resolves against registered archetypes, and registering
    // them is exactly what declaring a scene does.
    describeScenes(_GameSceneDescriptor(runtime));

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
    // event is a simulation act. Main's `GameState` keeps its dispatchers
    // unbound and never fires one, and has no systems to collect into them
    // anyway.
    _bindEvents(runtime);

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
  void _bootAllocate(GameRuntime runtime) {
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
      if (!runtime.inline) {
        runtime.commandsToGame = RingBuffer(commandBufferBytes);
        runtime.commandsToMain = RingBuffer(commandBufferBytes);
        runtime.ownsCommandRings = true;
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
      if (runtime.decodesAssets) _inputs.createDevice();
    }
  }

  /// Phase 3: commands, event binding, and closing the declaration window.
  void _bootFinalize(GameRuntime runtime, _StateDescriptor states) {
    final state = runtime.state!;

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
      simulating: runtime.simulates,
      inline: runtime.inline,
    );
    transport.registry = commands;
    runtime.commands = commands;
    runtime.commandTransport = transport;

    // The Game declares (and may handle on the Flutter isolate); the
    // GameState may only handle, on the game isolate. Order matters only in
    // that declaration has to precede handling, which this guarantees.
    describeCommands(MainCommandDescriptor(commands));
    state.describeCommands(GameCommandDescriptor(commands));
    commands.seal();
    // Attaches whichever rings this copy already has. Inline has none; the
    // game isolate allocated both in _runOnIsolate before calling this; the
    // handle copy has none yet and attaches again when `ready` lands.
    runtime.attachCommandRings();

    // The declaration window is closed. Anything holding on to the
    // descriptor past this point is trying to declare a channel at runtime,
    // which cannot work - its storage would exist on neither copy and its
    // index would not match the other side's.
    states._seal();
    // `_inputs.seal()` is deliberately *not* here: a system may still declare
    // an action, and systems are declared on the game isolate. It closes at
    // the end of [_bootGame] instead.
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
  void _bindEvents(GameRuntime runtime) {
    final state = runtime.state;
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
  // `SceneRegistry` are statics, and statics belong to no object graph, so they
  // do not ride `Isolate.spawn`'s deep copy. While main ran `describeScenes`
  // and mounted the state, main was the copy that filled them, and the spawned
  // copy had to be handed the contents in a snapshot reachable from this
  // object. That was two homes for one fact (the one-fact-one-place rule) held
  // in agreement by the two copies running identical code.
  //
  // Now exactly one copy registers anything: [_bootGame] runs on the game
  // isolate, so the registries are filled where they are read and there is no
  // second numbering for the first to disagree with. Main's stay empty, which
  // is the honest description of a copy that holds no world.

  // --- what GameState reaches back for ----------------------------------
  //
  // The simulation half lives in another library, so the handful of things
  // its tick loop needs are `@internal` accessors rather than private
  // fields - the same escape-hatch shape `SceneStruct.bindState` and
  // `EntityStruct.bindArchetype` already use. Each is a plain field read: no
  // copying, no allocation, safe to call once per system per tick.

  /// Every scene declared in [describeScenes], in declaration order - what
  /// `GameState.collectListeners` walks to reach the prefabs beneath them.
  @internal
  List<SceneStruct> get declaredScenes => _declaredScenes;

  /// Called by [GameState.runFixedStep] at the top of every fixed step:
  /// re-reads the raw device snapshot and updates every declared action from
  /// it.
  ///
  /// **Before commands and before any system runs.** A tick is supposed to see
  /// one coherent picture of the world, and input is part of that picture:
  /// resolving lazily on first read would let two systems in the same tick
  /// disagree about whether a key was down, and resolving per system would
  /// make `wasPressedThisFrame` mean "since this system last ran" instead of
  /// "this tick".
  @internal
  void resolveInputs() => _inputs.resolve();

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
  /// This is the **entire** Flutter-facing surface of a game: a method, not an
  /// event, because exactly one thing can answer it. Systems live entirely on
  /// the game isolate and contribute nothing to the widget tree.
  ///
  /// Renderers arrive by *subclass*, not by declaration: `Game2D` (in
  /// `goo2d`) overrides this with a `CustomPaint` fed by the draw buffer, so
  /// a 2D game writes `extends Game2D` and gets pixels. A future `goo3d`
  /// overrides it with a native surface instead, and `GameView` never
  /// changes.
  ///
  /// Return null, not an empty `SizedBox`, so that "this game draws nothing"
  /// is a state a caller can *see*: a headless game with a Flutter-side HUD is
  /// a real configuration, and [GameView] lays out nothing at all for it - no
  /// invisible box still taking part in layout.
  ///
  /// [camera] is the view being shown, or null when the game is displayed
  /// through `GameView.headless` - a game that declares no cameras. Contribute
  /// nothing for a null; never pick a view on the caller's behalf.
  ///
  /// Whatever a renderer keeps per view - decoded frames, a scheduler
  /// registration - lives in its own fields, because an instance backs one run
  /// and there is nothing to disambiguate. [onStopped] is where it lets go.
  Widget? buildView(BuildContext context, CameraView? camera) => null;

  // --- how many GameViews are showing this game ---------------------------

  int _mountedViews = 0;

  /// Whether anything is on screen showing this game.
  ///
  /// Refcounted, not a bool, because two views on one game is a
  /// supported shape (two cameras, or one camera at two sizes), and disposing
  /// the second must not stop the first from painting.
  bool get hasView => _mountedViews > 0;

  final FrameMeter _frames = FrameMeter();
  final _VisibilityObserver _visibility = _VisibilityObserver();

  /// Frames this game has actually presented - a counter, incremented once per
  /// real frame by the engine, never derived from a delta.
  ///
  /// Counts only while something is on screen showing it: these numbers come
  /// from Flutter's own frame timings, which exist only where frames do.
  int get frameCount => _frames.frameCount;

  /// Frames presented per second, counted over a rolling window.
  ///
  /// **Not `1 / frameMillis`.** vsync sets the ceiling, so a game using 4ms of
  /// a 16.67ms budget presents 60 times a second, not 250 - [frameMillis] is
  /// how much headroom is left, this is whether it is smooth. Zero when
  /// nothing is showing the game.
  double get fps => _frames.fps;

  /// Mean build-plus-raster milliseconds per frame. The budget at 60Hz is
  /// 16.67; this is how much of it is being spent.
  double get frameMillis => _frames.millis;

  /// The most expensive single frame in the window, in milliseconds - how long
  /// the slowest one took to *make*.
  double get worstFrameMillis => _frames.worstMillis;

  /// New pictures the **simulation** published per second.
  ///
  /// This is usually the number a player would call the frame rate, and it is
  /// not [fps]. The renderer samples the newest published frame once per
  /// Flutter frame, so a display refreshing 160 times a second while the
  /// simulation publishes 25 shows 25 distinct positions - smooth screen,
  /// stuttery game. [fps] says the screen is keeping up; this says whether
  /// there is anything new on it.
  ///
  /// When this is the lower of the two, the simulation is the bottleneck and
  /// `frameMillis` will look healthy while the game feels bad.
  ///
  /// **Zero when the simulation is not publishing.** A paused game, a
  /// `timeScale` of zero and a tick that has stopped for any other reason all
  /// read zero here, and they read it while [fps] goes on reporting whatever
  /// the display is managing - which is the whole point of two numbers.
  double get simulationFps => _runtime?.simulationFps ?? 0;

  /// Simulation frames published since the run started - the counter behind
  /// [simulationFps], in the same sense [frameCount] is behind [fps].
  ///
  /// A *published* frame, not a presented one: a frame on which the tick did
  /// not move puts nothing new on screen and is not counted.
  int get simulationFrameCount => _runtime?.simulationFrames.frameCount ?? 0;

  /// The longest the simulation went without publishing a new picture, in
  /// milliseconds. The [worstFrameIntervalMillis] of the other half.
  ///
  /// **On a spawned run this is stamped on the main isolate, when the tick
  /// message arrives.** So a main isolate busy enough to leave a tick ping
  /// sitting in its port queue inflates this, and a stall it reports may
  /// belong to either half. Being a maximum is what makes that bite: one late
  /// arrival stays in the window until it rolls out, where the averaging that
  /// [simulationFps] does absorbs the same jitter. An inline run has nothing
  /// to conflate: the notification is a direct call on the isolate that
  /// published. Moving the stamp to the producer means the per-tick ping
  /// carrying one, which is a wire change this has not made (#167).
  double get worstSimulationIntervalMillis =>
      _runtime?.simulationFrames.worstIntervalMillis ?? 0;

  /// The longest the picture went without a new frame, in milliseconds - **the
  /// jank number**.
  ///
  /// [fps] is throughput and averages the window; this is pacing and does not.
  /// A high [fps] alongside a large value here is not a contradiction, it is
  /// the precise description of a game that stutters: the frames arrived, just
  /// not evenly. At a steady 60Hz this reads about 16.7.
  double get worstFrameIntervalMillis => _frames.worstIntervalMillis;

  @internal
  void attachView() {
    if (_mountedViews++ > 0) return;
    // Armed here rather than at boot, and that is what keeps a headless game
    // safe: `SchedulerBinding.instance` needs a binding, and a game with no
    // widget may be running in a tool or a plain `dart run` where there is
    // none. A view existing is proof there is one.
    _frames.arm();
    // Same reasoning as `_frames.arm()` above, and the same proof: an observer
    // needs `WidgetsBinding.instance`, and a headless game has no binding to
    // register with. A view existing is what says there is one.
    _visibility.arm(this);
    onViewAttached();
  }

  @internal
  void detachView() {
    if (--_mountedViews > 0) return;
    _frames.disarm();
    _visibility.disarm();
    // Nothing is holding a key down once there is no widget to hold it with,
    // and the events that would have said so left with the view. Behind the
    // refcount deliberately: two views on one game is a supported shape, and
    // the one still up is still being played, so releasing on the first
    // `dispose` would drop a key out from under it. `didUpdateWidget`
    // attaches before it detaches for the same reason, so swapping which
    // camera is on screen never reaches this line at all.
    inputDevice?.releaseAll();
    onViewDetached();
  }

  /// The first [GameView] showing this game has been mounted.
  ///
  /// This, not [buildView], is where a renderer starts whatever runs per
  /// Flutter frame. `buildView` is called *during build*, and starting a
  /// frame callback there means a side effect fires on every rebuild and
  /// never fires at all for a game whose view is built once and then only
  /// repainted - the registration would be both duplicated and mistimed.
  void onViewAttached() {}

  /// The last [GameView] showing this game has been disposed.
  ///
  /// Anything armed in [onViewAttached] must be disarmed here, not left to
  /// [onStopped]: the widget can go while the game runs on, and a
  /// self-rescheduling frame callback left behind keeps the scheduler awake
  /// forever - which a widget test reports as "an animation is still running
  /// even after the widget tree was disposed". [onStopped] is the other end,
  /// for a game that stops while its view is still up.
  void onViewDetached() {}

  // --- tick notification ------------------------------------------------
  //
  // `addTickListener`/`removeTickListener` used to live here and are gone with
  // the rest of the run's state. A tick listener belongs to one run - two runs
  // of one `Game` would have shared a list and fired each other's callbacks -
  // and the only engine consumer moved to a `SchedulerBinding` frame callback
  // anyway, because a repaint scheduled when a port message happens to land
  // waits most of a frame for the next vsync. `GameRuntime.addTickListener` is
  // the internal spelling that survives, for the state channels' own polling.
}

/// One **run** of a [Game]: everything that is true of a game while it is
/// going, and nothing that is true of its description.
///
/// Built by `Game.start`, one per run. A `Game` instance backs exactly one of
/// these for its whole life - see `Game._requireNotYetDescribed` for why - so
/// this is not a multiplicity mechanism. It is a **separation** one.
///
/// Splitting this from the description makes each side's job nameable: the
/// description is read-only after boot, and the runtime is the only thing that
/// changes and the only thing with two isolate-specific halves. With the roles,
/// the ports, the ring buffers and the `GameState` all hanging off the
/// description, "what does this object mean on the other isolate" has no single
/// answer.
///
/// # This, not the `Game`, is the spawn message
///
/// `Isolate.spawn` carries one of these, and the `Game` rides along inside it
/// as [game]. That direction matters: the runtime is the thing with two
/// isolate-specific halves to swap over ([runOnIsolate] takes ownership of the
/// simulation and gives up ownership of the memory), while the description is
/// identical on both sides and simply arrives.
///
/// The same rule as ever applies to what may be reachable from here at spawn
/// time: a `Pointer` is sendable and arrives at the same address, a
/// `ReceivePort` or a `Completer` is not sendable at all. [fromGame] and
/// [stopping] are therefore assigned only *after* the spawn - see [boot].
@internal
final class GameRuntime {
  GameRuntime(this.game);

  /// The description this run is running.
  final Game game;

  // One flag used to answer four questions - who allocates, who frees, who
  // may write a state channel, and who ticks. They coincided only because the
  // game isolate did all four. Now that boot runs on main *before* the spawn,
  // they genuinely differ and are two flags:
  //
  //   owns      - this copy allocated the shared native memory and frees it.
  //               Main, in the spawned configuration.
  //   simulates - this copy runs the tick loop, and is therefore the single
  //               writer of component data and state channels. The game
  //               isolate.
  //
  // Inline sets both. The user-facing spelling of the second is
  // `GameState.isSimulating`; these are here because several bring-up steps
  // need them before or without a state.
  //
  // A `TripleBuffer` requires one *writer*, not a particular isolate, which is
  // what makes allocate-here/write-there legal at all. `InputDevice` has
  // always been the mirror image of this (game isolate allocated, main wrote).
  bool simulates = false;
  bool owns = false;
  bool inline = false;
  bool booted = false;

  /// Whether `Game.state`/`advance`/`runFixedStep` are available.
  ///
  /// **Not the same question as [inline]**, and conflating them was a real
  /// bug for exactly one configuration. `Game.start` runs inline on the web,
  /// because there are no isolates in the shared-memory sense there - so a
  /// guard that asked [inline] let `game.state` work on the web and throw on
  /// native, off identical source. That is the "compiles everywhere, works in
  /// one place" shape the whole split exists to prevent, just inverted.
  ///
  /// This asks what the *caller* asked for instead: only `Game.startInline`
  /// sets it. The web still runs inline; it just does not hand out the world
  /// to code that did not ask to drive it.
  bool drivable = false;

  /// Fixed ticks completed. On the handle copy this tracks the last tick
  /// number the game isolate reported, so it lags reality by one message.
  int tick = 0;

  /// This run's simulation half - non-null on the copy that boots it, which is
  /// both copies (main builds a declaration mirror; see [Game._bootMain]).
  GameState? state;

  // The declared command list, and the thing that carries batches of them
  // between the copies. Both are built in boot and live as long as the run;
  // null only before it starts (and again, for the transport's rings, after it
  // stops).
  CommandRegistry? commands;
  CommandTransport? commandTransport;

  // The two command rings. Each is single-producer/single-consumer, so there
  // is one per direction rather than one shared lane - see CommandTransport.
  // Both are allocated by, and belong to, the copy that owns the simulation;
  // the handle copy only ever holds views. Null in the inline configuration,
  // where nothing crosses a boundary.
  RingBuffer? commandsToGame;
  RingBuffer? commandsToMain;
  bool ownsCommandRings = false;

  // Game-isolate copy only.
  SendPort? _toMain;
  ReceivePort? _control;

  // Asset loads this copy has asked main to perform and is still waiting on,
  // by request id. Populated only after the spawn, which is what makes the
  // `Completer` inside each one safe to hold here: [_stopping] is the same
  // shape for the same reason (a Completer reachable from this object at spawn
  // time would make the message unsendable).
  int _assetRequestId = 0;
  final Map<int, _AssetLoadRequest> _assetRequests = <int, _AssetLoadRequest>{};

  // Main-isolate handle copy only.
  ReceivePort? _fromGame;
  SendPort? _toGame;
  Completer<void>? _stopping;

  /// The game isolate died of an uncaught error - see [_handleIsolateDeath].
  RawReceivePort? _isolateErrors;

  final List<void Function(int tick)> _tickListeners =
      <void Function(int tick)>[];

  /// Whether this run has booted and not yet stopped.
  bool get isRunning => booted;

  /// Whether this copy runs on the isolate that can decode assets.
  ///
  /// **Not the same question as [GameState.isSimulating]**, and that is the
  /// whole reason it exists. Decoding needs Flutter and `dart:ui`, which live
  /// on the main isolate; simulating happens wherever the tick loop is. The
  /// three configurations answer differently:
  ///
  ///  * inline (`Game.startInline`, and every web build): one copy, on the
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
  bool get decodesAssets => inline || !simulates;

  // --- bring-up -----------------------------------------------------------

  /// Brings this run up.
  ///
  /// With [inline] false this spawns the game isolate, waits for it to report
  /// ready, and leaves this copy as the handle side. With [inline] true there
  /// is only ever **one** copy: the [GameState] is constructed on the calling
  /// isolate and does both jobs, with no spawn and no shared-memory handoff.
  ///
  /// The ordering inside the spawning path is load-bearing, and it is the
  /// **reverse** of what it once was. [Game._bootMain] runs *before*
  /// `Isolate.spawn`, so what is handed over is fully described - every
  /// system, buffer, channel, camera view and command, plus the native memory
  /// they point at. The spawned copy re-derives none of it; it adds the half
  /// that could only ever have been its own ([Game._bootGame]) and starts
  /// ticking.
  ///
  /// What may not be reachable from this object at spawn time is the genuinely
  /// unsendable: [_fromGame] is created after `_bootMain` and stored in a
  /// field only *after* the spawn. A decoded asset (`dart:ui.Image`) needs no
  /// gate of its own: nothing decodes until a scene is loaded, and no scene is
  /// loaded until `_bootGame` runs on the far side. A `Pointer` is fine - see
  /// [Game]'s class doc.
  Future<void> boot({
    required bool inline,
    required bool drivable,
    required bool autoTick,
  }) async {
    if (booted) {
      throw StateError('this ${game.runtimeType} run is already going.');
    }
    // Before the spawn, deliberately, so the game-isolate copy inherits the
    // back-reference and resolves it to *its own* copy of this runtime. That
    // is what lets `game.tick` and `game.isRunning` answer correctly on both
    // sides instead of being main-only. The cycle (runtime -> game -> runtime)
    // is fine: `Isolate.spawn`'s deep copy handles cycles.
    game._runtime = this;
    this.drivable = drivable;
    if (inline) {
      booted = true;
      this.inline = true;
      owns = true;
      simulates = true;
      // No command rings: there is no boundary to cross, so a batch is run by
      // the copy that built it (see `CommandTransport`). Allocating 128 KiB of
      // native memory for two lanes that would carry nothing is the kind of
      // thing that only shows up on web, where this is the *only* path.
      //
      // Both halves, back to back, on the one copy that does both jobs.
      game._bootMain(this);
      game._bootGame(this);
      if (autoTick) state!.startTimer();
      return;
    }

    // Everything this copy declares, and every byte of shared memory,
    // **here, before the spawn**. It does not simulate, so it stops here: no
    // scene is registered and no world exists on this isolate at all.
    owns = true;
    simulates = false;
    game._bootMain(this);
    booted = true;

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
    // Dart's own error port, and the only cross-isolate route this failure
    // has. `errorsAreFatal` defaults to true, so any uncaught error on the
    // game isolate kills it; without an `onError` nothing on this side is
    // ever told, which is exactly the silent stall #126 is about. There is no
    // engine channel that fits: `GameCommand` is main -> game, a
    // `StateChannel` carries only fixed-width numbers and bools, and
    // `describeBuffers` is the bulk per-tick lane.
    // The zone `start` was called in, captured because a RawReceivePort
    // callback is invoked by the VM and is not reliably bound to it. Reporting
    // through this is what puts the failure where Flutter and the test
    // runner already look.
    final zone = Zone.current;
    final isolateErrors = RawReceivePort(
      (dynamic m) => _handleIsolateDeath(m, zone),
    );
    // Assigned *after* the spawn, exactly as `_fromGame` is: this object rides
    // inside the spawn message, and a ReceivePort on it is unsendable - see
    // `Game`'s note on holding no unsendable state at handover.
    await Isolate.spawn<List<Object>>(_gameIsolateEntryPoint, <Object>[
      this,
      fromGame.sendPort,
      autoTick,
    ], onError: isolateErrors.sendPort);

    _fromGame = fromGame;
    _isolateErrors = isolateErrors;
    // `ready` is sent *after* the game isolate has run `_bootGame`, so by the
    // time this returns the world exists: scenes registered, entities spawned,
    // queries compiled. Only asset decoding is still in flight, and that is
    // what `loadScene`'s future is for.
    await ready.future;
  }

  /// Points the transport at whichever of this copy's rings exist.
  ///
  /// Each ring has one producer and one consumer, and which end this copy
  /// holds follows from whether it simulates - the game isolate consumes what
  /// main sends and produces what main consumes, and the handle copy is the
  /// mirror image. Called twice on the handle copy (once from boot with
  /// nothing to attach, once when `ready` lands with the addresses) so that
  /// there is one place that knows the direction.
  void attachCommandRings() {
    final transport = commandTransport;
    if (transport == null) return;
    transport.inbound = simulates ? commandsToGame : commandsToMain;
    transport.outbound = simulates ? commandsToMain : commandsToGame;
    // The same place, for the same reason: this is where the direction is
    // known. A receipt-delivered batch goes by port rather than by ring, so
    // it is reachable while the tick is stopped.
    transport.controlSend = (bytes) {
      final port = simulates ? _toMain : _toGame;
      port?.send(<Object?>[_ControlMessage.controlBatch, bytes]);
    };
  }

  // --- what GameState reaches back for ------------------------------------

  /// A batch to build several calls into, sent and answered as one message.
  /// See `Game.createCommandBatch`.
  CommandBatch createCommandBatch() {
    final registry = commands;
    if (registry == null) {
      throw StateError(
        '${game.runtimeType} has not been started, so its commands have not '
        'been declared yet - describeCommands runs during Game.start().',
      );
    }
    return registry.createCommandBatch();
  }

  /// Takes in whatever the other copy has sent since the last call and runs
  /// what is due - see `CommandTransport.pump`.
  ///
  /// Called from `GameState.runFixedStep`, inside the tick window and before
  /// any system, which is what makes a command-spawned entity visible to
  /// every system on the tick its command lands. The main isolate pumps on
  /// its own schedule (each tick notification), where nothing is tick-bound.
  void pumpCommands() => commandTransport?.pump();

  /// Called by [GameState.runFixedStep] once a fixed step is fully committed.
  void completeTick() => tick++;

  /// Announces the finished frame to the main isolate.
  ///
  /// **Called after the presentation pass, not at the end of the fixed
  /// tick.** That ordering is load-bearing: a `Tickable` *is* presentation,
  /// so anything a game publishes for main to see - a state channel, a draw
  /// ring - is written after `commitTick` and before this. Firing inside
  /// `runFixedStep` would announce a frame that had not been written yet, and
  /// everything reading on the signal would come up one frame stale, the very
  /// first one empty.
  ///
  /// The main-isolate half is [_notifyTickListeners], which reconciles state
  /// channels before it calls anyone. `goo2d` does not listen: it samples the
  /// newest published frame from a `SchedulerBinding` frame callback instead,
  /// for the reason `GameRenderer2D._onFrame` gives.
  ///
  /// Split from [completeTick] because the tick
  /// *counter* has to advance before presentation runs: the renderer stamps
  /// its batch with the tick, and that has to name the tick it depicts.
  void presentFrame() {
    final toMain = _toMain;
    if (toMain == null) {
      // Inline path: no port to hop, notify directly.
      _notifyTickListeners(tick);
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
    toMain.send(tick);
  }

  /// Registers [listener] to be called on the **main** isolate once per
  /// completed fixed tick.
  ///
  /// Internal, and public nowhere: the one engine consumer uses a
  /// `SchedulerBinding` frame callback instead, because a repaint scheduled
  /// when a port message happens to land waits most of a frame for the next
  /// vsync. This is for tests and for anything that genuinely needs the "the
  /// published snapshot moved" edge. A game that wants a visible tick count
  /// publishes one with `describeState`, through the lane that already exists
  /// for "a number main should see".
  void addTickListener(void Function(int tick) listener) {
    _tickListeners.add(listener);
  }

  void removeTickListener(void Function(int tick) listener) {
    _tickListeners.remove(listener);
  }

  /// Counts published simulation frames, on the main isolate.
  ///
  /// Fed from [_notifyTickListeners], which is the one place both
  /// configurations converge: the spawned copy gets here from the tick ping,
  /// the inline one straight from [presentFrame]. Timestamped from this
  /// runtime's own monotonic clock, not the engine's: these are not engine
  /// frames and have no `FrameTiming` to borrow one from.
  final FrameMeter simulationFrames = FrameMeter();
  final Stopwatch _clock = Stopwatch()..start();

  /// The tick of the last frame [simulationFrames] counted, so a frame that
  /// published nothing is not counted twice over.
  int _meteredTick = -1;

  /// [simulationFrames] read against the clock that feeds it, so a simulation
  /// that has stopped publishing reads zero, not its last healthy rate. See
  /// [FrameMeter.fpsAt].
  double get simulationFps =>
      simulationFrames.fpsAt(_clock.elapsedMicroseconds);

  void _notifyTickListeners(int tick) {
    // Only a tick that moved is a new picture. [presentFrame] runs once per
    // *frame*, including a frame that afforded zero fixed steps, and a paused
    // game goes on presenting - so counting every one of these measured frame
    // callbacks rather than published frames, and reported a healthy sixty
    // for a simulation running nothing. The renderer already reads it this
    // way: `DrawCanvas2D.ingestFrame` rejects a batch whose tick stamp is not
    // newer, so a frame that did not move the tick puts nothing new on screen
    // either.
    //
    // Compared rather than ordered, because a run that is reused starts its
    // tick over and the next frame is a new picture whichever way the number
    // went.
    if (tick != _meteredTick) {
      _meteredTick = tick;
      simulationFrames.record(_clock.elapsedMicroseconds);
    }
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
  /// This is the main isolate's half of `StateChannel`'s two-speed notification
  /// (see that class's doc): the simulating copy notifies synchronously inside
  /// the write, because the writer is right there; this copy cannot know a
  /// write happened until the tick message lands, so it reconciles here. Driven
  /// off the tick-completed path, not a timer of its own: "the published
  /// snapshot moved" is exactly the signal the tick ping already carries, and a
  /// channel checking on any other schedule would report changes at a moment
  /// when the rest of the world a listener can read is from a different tick.
  ///
  /// Costs one null check per declared channel on a copy that declared none,
  /// which is the overwhelmingly common case.
  void _pollStateChannels() {
    final channels = game._stateChannels;
    for (var i = 0; i < channels.length; i++) {
      channels[i].pollChanged();
    }
  }

  /// Frees a scene's pages, immediately.
  ///
  /// Immediate is safe only because there is one reader. Pages are allocated,
  /// read and freed entirely on this isolate, and main never adopts one - it
  /// holds no archetypes to adopt into and never resolves an `Entity`.
  ///
  /// Give main a second reader and this needs an un-adopt handshake back: the
  /// pages have to stay alive across a round trip so the reader can let go
  /// before the writer frees. Use-after-free is the one failure mode a
  /// shared-memory design cannot report - it just returns wrong numbers.
  void releaseScenePages(int sceneSlot) {
    final pool = state?.pool;
    if (pool == null) return;
    for (var i = 0; i < ArchetypeRegistry.count; i++) {
      ArchetypeRegistry.byId(i).releaseScene(sceneSlot, pool);
    }
  }

  // --- shutdown -----------------------------------------------------------

  /// The game isolate died of an uncaught error.
  ///
  /// Without this the death was **silent and unrecoverable**: the tick simply
  /// stopped, [isRunning] went on answering true, and `stop()` waited forever
  /// for a `stopped` from an isolate that no longer existed - a 30-second
  /// timeout in a test, a hung shutdown and a leaked pool in an application.
  /// The only trace was an engine-level log no Dart code could see (#126).
  ///
  /// So this marks the runtime dead first and reports second. Marking dead is
  /// what makes [isRunning] false and what lets [shutDown]'s `if (!booted)`
  /// return immediately, so a later `stop()` completes instead of hanging.
  ///
  /// A pending `stop()` is completed **with the error**, because the game did
  /// not stop cleanly and a caller that awaited a clean stop should not be
  /// told it got one. In that case this does not also rethrow: the awaiting
  /// caller is already being told, and throwing again would report one death
  /// twice. With no stop pending there is nobody to tell, so it rethrows on
  /// this isolate instead of letting the failure disappear.
  void _handleIsolateDeath(dynamic message, Zone zone) {
    // Two strings, already stringified by the sending isolate - an error
    // object cannot cross a port, so this is what Dart's own error port
    // gives and there is no richer form to ask for.
    final parts = message as List;
    final error = parts.isNotEmpty ? '${parts[0]}' : 'unknown error';
    final stack = parts.length > 1 && parts[1] != null ? '\n${parts[1]}' : '';

    if (!booted) return;
    booted = false;
    _toGame = null;
    _isolateErrors?.close();
    _isolateErrors = null;
    _fromGame?.close();
    _fromGame = null;

    final failure = StateError(
      'the ${game.runtimeType} game isolate died of an uncaught error:\n'
      '$error$stack',
    );
    final stopping = _stopping;
    if (stopping != null && !stopping.isCompleted) {
      _stopping = null;
      stopping.completeError(failure);
      return;
    }
    zone.handleUncaughtError(failure, StackTrace.current);
  }

  /// Stops the simulation and releases the shared memory.
  ///
  /// Two phases in the spawned configuration. The game isolate
  /// stops ticking and reports `stopped`, which completes this future; only
  /// then does this copy tell it to free the pool and the ring buffer.
  /// Freeing in one step would race tick messages still in flight - the
  /// handle would be resolving entities out of pages that had just been
  /// `free`d.
  ///
  /// The user-facing spelling is `Game.stop()`.
  Future<void> shutDown() async {
    if (!booted) return;
    // First, before anything is torn down. This is the presentation isolate's
    // teardown hook, and the shared buffers are still mapped here - a renderer
    // cancelling a frame callback must do it while the draw buffer it reads is
    // still alive. `GameState.onUnmounted` is the same moment on the other
    // side, and `unmount()` below is what fires it.
    game.onStopped();
    if (inline) {
      _stopInline();
      return;
    }
    final toGame = _toGame;
    if (toGame == null) {
      throw StateError(
        'this ${game.runtimeType} run is not connected to a game isolate.',
      );
    }
    final stopping = Completer<void>();
    _stopping = stopping;
    toGame.send(const <Object>[_ControlMessage.stop]);
    await stopping.future;
    // The game isolate has freed the native memory by now, so this copy's
    // views are dangling - drop them rather than leave a RingBuffer around
    // that would happily read freed pages.
    _disposeBuffers();
    _isolateErrors?.close();
    _isolateErrors = null;
    _fromGame?.close();
    _fromGame = null;
    booted = false;
    _resetGlobalRegistries();
  }

  void _stopInline() {
    final state = this.state!;
    state.stopTimer();
    state.unmount();
    _disposeBuffers();
    state.pool.dispose();
    booted = false;
    _resetGlobalRegistries();
  }

  /// Empties the process-global registries a run filled in, so the next
  /// `Game.start` in this process starts from nothing.
  ///
  /// # Why a run has to clean these up
  ///
  /// `ArchetypeRegistry`, `ComponentTypeRegistry`, `SceneRegistry` and
  /// `HeapObjectRegistry` are static, and they are static for a reason that
  /// still holds: an `Entity` and a `Scene` are bare ints carrying no
  /// references, so resolving one cannot start from an object. But static also
  /// means they outlive the run that filled them, and until this existed
  /// nothing ever emptied them outside a test's `tearDown`.
  ///
  /// The failure that follows is not subtle once you see it and impossible to
  /// read before: start game A, stop it, start game B, stop it, start game A
  /// again - and A's second run re-registers an archetype that is *already
  /// there* from its first, so it gets back the **first run's prefab**, whose
  /// asset handles belong to a `GameAssets` that was torn down two runs ago.
  /// It surfaces as "declared (address 0) but was never loaded on this
  /// isolate", pointing at the asset layer, which is not where the problem is.
  ///
  /// Safe because a run owns the isolate it simulates on: statics do not cross
  /// an `Isolate.spawn`, and one instance runs once
  /// (`_requireNotYetDescribed`). So there is never a second live run on this
  /// isolate whose registry entries this could pull out from under.
  void _resetGlobalRegistries() {
    // The run's own asset table, before the registries that name into it.
    // `reset` calls `onUnloaded` on every instance, which is what releases the
    // decoded `ui.Image`s - nothing else ever did, so each stopped run left
    // its textures alive on main and the next run decoded its own on top.
    // ignore: invalid_use_of_visible_for_testing_member
    game.assets.reset();
    // `@visibleForTesting` because a test's tearDown was the only caller there
    // has ever been. Ending a run is the other legitimate one, and it is the
    // one that makes a second run in the same process work at all.
    // ignore: invalid_use_of_visible_for_testing_member
    SceneRegistry.reset();
    // ignore: invalid_use_of_visible_for_testing_member
    ArchetypeRegistry.reset();
    // ignore: invalid_use_of_visible_for_testing_member
    ComponentTypeRegistry.reset();
    // ignore: invalid_use_of_visible_for_testing_member
    HeapObjectRegistry.reset();
  }

  /// Releases the two command rings, on the copy that allocated them, and
  /// fails anything still waiting for an answer that is not coming.
  ///
  /// Same ownership rule as everything else shared: the simulating copy owns
  /// the memory, the handle copy only drops its views. Nothing to free at all
  /// in the inline configuration, which never allocated a ring.
  void _disposeCommandRings() {
    commandTransport?.shutdown();
    if (ownsCommandRings) {
      commandsToGame?.dispose();
      commandsToMain?.dispose();
      ownsCommandRings = false;
    }
    commandsToGame = null;
    commandsToMain = null;
  }

  /// Releases every auxiliary buffer this copy *allocated*. The handle copy
  /// holds views into the game isolate's memory and must only drop them -
  /// same ownership rule as the command rings and the pool's pages.
  void _disposeBuffers() {
    _disposeCommandRings();
    final buffers = game._bufferHandles;
    for (var i = 0; i < buffers.length; i++) {
      final handle = buffers[i];
      if (owns) handle._ring?.dispose();
      handle._ring = null;
    }
    final handoffs = game._handoffHandles;
    for (var i = 0; i < handoffs.length; i++) {
      final handle = handoffs[i];
      if (owns) handle._buffer?.dispose();
      handle._buffer = null;
    }
    game.cameraViews.release(owns: owns);
    // Same ownership rule for the state channels' triple buffers: the
    // simulating copy allocated them and frees them, the handle only drops
    // its views. The declared set (the channel objects themselves, and the
    // handles users hold in their `late final` fields) survives; only the
    // storage goes, so a read after stop() reports "not connected" rather
    // than reading freed memory.
    final channels = game._stateChannels;
    for (var i = 0; i < channels.length; i++) {
      channels[i].release(owned: owns);
    }
    // Same ownership rule again for the raw input block, and the same
    // survival rule: the declared actions (and the handles users hold) stay,
    // so a read after stop() reports its default rather than reading freed
    // memory. The write end goes with the storage - there is nowhere to put
    // a keystroke once the game is down.
    game._inputs.release(owned: owns);
  }

  // --- game isolate side --------------------------------------------------

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
  /// What it *does* describe is [Game._bootGame]: the scenes, and therefore
  /// the archetypes and component bits, which live in **statics** - they
  /// belong to no object graph, so they could never have crossed. Running that
  /// pass here is what removes the need for main to snapshot the registries
  /// and hand them over.
  ///
  /// The other thing this copy does is take over the two roles main was
  /// holding open for it: it becomes the simulator, and it stops being the
  /// owner.
  void runOnIsolate(SendPort toMain, bool autoTick) {
    _toMain = toMain;

    // The role swap, and the only reason these are two flags. Main allocated
    // every shared buffer and will free them; this copy runs the tick loop and
    // is therefore the single writer of component data and state channels.
    // The deep copy handed us main's values, which were right for main.
    owns = false;
    ownsCommandRings = false;
    simulates = true;
    state!.markSimulating();
    commands!.markSimulating();
    // Rebuild every cached view over native memory. `Pointer` crosses at
    // the same address, but a `ByteData` built from one and kept in a field is
    // deep-copied *by value* - the copy would write into detached Dart heap
    // memory that main never sees. Verified in tool/spawn_inherit_spike.dart.
    final channels = game._stateChannels;
    for (var i = 0; i < channels.length; i++) {
      channels[i].reattach();
    }
    // Main built an InputDevice against the shared input block and the copy
    // came with us. This copy only ever *reads* input, and two live write ends
    // on one TripleBuffer is exactly what that primitive forbids - so drop it.
    game._inputs.releaseDevice();
    // Point the transport at the right ends now that the roles are settled.
    attachCommandRings();

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
    game._bootGame(this);

    // Nothing but the control port: the buffers, state channels, input block
    // and both command rings all arrived with the copy, already addressed.
    // The three announcement messages that used to carry them are gone.
    toMain.send(<Object>[_ControlMessage.ready, control.sendPort]);

    if (autoTick) state!.startTimer();
  }

  void _handleControlMessage(dynamic message) {
    final parts = message as List;
    final state = this.state;
    switch (parts[0] as _ControlMessage) {
      case _ControlMessage.stop:
        state?.stopTimer();
        state?.unmount();
        _toMain?.send(const <Object>[_ControlMessage.stopped]);
      case _ControlMessage.controlBatch:
        // Run here, in the port callback, with no tick involved. See
        // `CommandTransport.receiveControlBatch`.
        commandTransport?.receiveControlBatch(parts[1] as Uint8List);
      case _ControlMessage.dispose:
        _disposeBuffers();
        state?.pool.dispose();
        _control?.close();
        _control = null;
        _toMain = null;
        booted = false;
      case _ControlMessage.assetLoaded:
        // Record the shape before reporting progress, so a progress callback
        // that reaches for it already sees it.
        game.assets.adoptInfo(parts[2] as int, parts[5] as AssetInfo?);
        final request = _assetRequests[parts[1] as int];
        request?.onLoaded?.call(
          parts[2] as int,
          parts[3] as int,
          parts[4] as int,
        );
      case _ControlMessage.assetsDone:
        final request = _assetRequests.remove(parts[1] as int);
        final failure = parts[2] as String?;
        if (request == null || request.done.isCompleted) break;
        if (failure == null) {
          request.done.complete();
        } else {
          // Surfaced at the `await loadScene(...)` that asked for it, which is
          // where the local decode path throws too.
          request.done.completeError(
            StateError(
              'asset decoding failed on the Flutter isolate - $failure',
            ),
          );
        }
      // Listed rather than defaulted, so that adding a message and forgetting
      // to handle it here is an analyzer error. These four belong to main; one
      // arriving on this port means a send went the wrong way, which used to
      // be a silent no-op.
      case _ControlMessage.ready:
      case _ControlMessage.stopped:
      case _ControlMessage.loadAssets:
      case _ControlMessage.unloadAssets:
        assert(
          false,
          '${parts[0]} is handled on main, not on the game isolate.',
        );
    }
  }

  // --- main isolate side --------------------------------------------------

  void _handleGameMessage(dynamic message, Completer<void> ready) {
    // A bare int is the per-tick ping; anything else is a control message.
    if (message is int) {
      tick = message;
      // Before the listeners, for the same reason the state channels are
      // reconciled before them: this is the one moment per frame when this
      // copy looks at what the game isolate has said, and a widget rebuilding
      // off a tick callback should see a command's effects from the same
      // frame rather than the one before it. This is also where a
      // Flutter-isolate handler actually runs, and where a reply to a command
      // this copy sent completes its future.
      commandTransport?.pump();
      _notifyTickListeners(message);
      return;
    }
    final parts = message as List;
    switch (parts[0] as _ControlMessage) {
      case _ControlMessage.controlBatch:
        // Run here, in the port callback, with no tick involved. See
        // `CommandTransport.receiveControlBatch`.
        commandTransport?.receiveControlBatch(parts[1] as Uint8List);
      case _ControlMessage.ready:
        // The control port is all `ready` carries now. Every shared buffer -
        // both command rings, the auxiliary buffers, the state channels and
        // the input block - was allocated on this copy before the spawn and
        // arrived on the other one inside the copied object, already
        // addressed. The three announcement messages that used to carry them
        // are gone, and so is the reason `start()` had to wait for them.
        _toGame = parts[1] as SendPort;
        ready.complete();
      case _ControlMessage.loadAssets:
        // Unawaited by design: this is a port callback, and the decode is
        // asynchronous. Its completion is reported back over the port rather
        // than by this future, and every failure is caught inside.
        unawaited(_handleAssetLoadRequest(parts));
      case _ControlMessage.unloadAssets:
        final addresses = (parts[1] as List).cast<int>();
        for (var i = 0; i < addresses.length; i++) {
          game.assets.unloadAddress(addresses[i]);
        }
      case _ControlMessage.stopped:
        _toGame?.send(const <Object>[_ControlMessage.dispose]);
        _toGame = null;
        _stopping?.complete();
        _stopping = null;
      // The mirror of the arm in `_handleControlMessage`, and there for the
      // same reason: these four are handled on the game isolate, and one
      // arriving here means a send went the wrong way.
      case _ControlMessage.stop:
      case _ControlMessage.dispose:
      case _ControlMessage.assetLoaded:
      case _ControlMessage.assetsDone:
        assert(
          false,
          '${parts[0]} is handled on the game isolate, not on main.',
        );
    }
  }

  // --- asset decoding across the boundary ---------------------------------
  //
  // The game isolate declares assets - that is what assigns their addresses,
  // and it has to happen there because prefabs and scenes live there - but it
  // cannot *decode* one, because decoding needs Flutter. So it asks.
  //
  // Before this existed, `GameState._reconcileAssets` took its claims and
  // returned at `if (!decodesAssets) return;`, and nothing told main to decode
  // anything. That was invisible only because main ran `loadScene` itself at
  // boot; a `loadScene` at *runtime*, on the game isolate, declared assets that
  // were never loaded and whose payload reads then failed.

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
  /// case: there, [decodesAssets] is true and the caller decodes in place
  /// without calling this at all.
  Future<void> requestAssetLoad(
    List<int> addresses,
    List<AssetKey<Object?>> keys,
    void Function(int address, int completed, int pending)? onLoaded,
  ) {
    final toMain = _toMain;
    if (toMain == null || addresses.isEmpty) return Future<void>.value();
    final id = ++_assetRequestId;
    final request = _AssetLoadRequest(onLoaded);
    _assetRequests[id] = request;
    toMain.send(<Object>[_ControlMessage.loadAssets, id, addresses, keys]);
    return request.done.future;
  }

  /// Tells main to drop the payloads for [addresses]. Fire-and-forget: the
  /// declaration is already gone on this copy, and nothing here waits on the
  /// memory the way a page free does.
  void requestAssetUnload(List<int> addresses) {
    if (addresses.isEmpty) return;
    _toMain?.send(<Object>[_ControlMessage.unloadAssets, addresses]);
  }

  /// Main's half: decode what was asked for, reporting each one back.
  ///
  /// Sequential, not concurrent: it mirrors the local path exactly, and a
  /// loading screen wants a progress sequence instead of everything landing at
  /// once. `Assets.load` already collapses overlapping requests for one key.
  Future<void> _handleAssetLoadRequest(List parts) async {
    final id = parts[1] as int;
    final addresses = (parts[2] as List).cast<int>();
    final keys = (parts[3] as List).cast<AssetKey<Object?>>();
    final assets = game.assets;

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
      final asset = assets.tryGetAt(addresses[i]);
      if (asset != null && !asset.isLoaded) pending++;
    }

    var completed = 0;
    String? failure;
    for (var i = 0; i < addresses.length; i++) {
      final address = addresses[i];
      final asset = assets.tryGetAt(address);
      if (asset == null || asset.isLoaded) continue;
      try {
        await assets.loadAddress(address);
      } catch (error) {
        // Recorded and carried back rather than thrown here: this runs inside
        // a port callback, where throwing would take out the message loop and
        // strand the asker forever. The awaiting `loadScene` is the right
        // place for it to surface.
        failure ??= '${asset.debugLabel}: $error';
      }
      completed++;
      _toGame?.send(<Object?>[
        _ControlMessage.assetLoaded,
        id,
        address,
        completed,
        pending,
        // The decoded payload cannot cross - that is the whole reason this
        // request exists - but what decoding *discovered* can, and the asking
        // copy generally needs it. An image's true pixel size is the reference
        // case: the game isolate nine-slices with it and has no other way to
        // learn it. See `AssetLoader.describe`.
        asset.info,
      ]);
    }
    _toGame?.send(<Object?>[_ControlMessage.assetsDone, id, failure]);
  }
}

/// One in-flight [GameRuntime.requestAssetLoad], game-isolate side.
///
/// One object, not parallel maps keyed by request id (the one-fact-one-place
/// rule): the completer, the progress callback and the first failure all belong
/// to the same request and are only ever used together.
final class _AssetLoadRequest {
  _AssetLoadRequest(this.onLoaded);

  final void Function(int address, int completed, int pending)? onLoaded;
  final Completer<void> done = Completer<void>();
}

/// The spawned isolate's entry point. Top-level (a closure would not be
/// sendable) and trivial - all it does is hand control to the
/// copied `GameRuntime`, which is what the spawn message actually is: the
/// `Game` rides inside it, because a description has no isolate-specific half
/// to hand over and a run has two.
void _gameIsolateEntryPoint(List<Object> message) {
  final runtime = message[0] as GameRuntime;
  runtime.runOnIsolate(message[1] as SendPort, message[2] as bool);
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
  /// a value where only the newest copy matters, not a queue where every
  /// record does.
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
/// This is the typed-handle rule applied to buffers. There is no name and no
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
/// Same discipline as [BufferHandle] (the typed-handle rule): no name, no
/// registry, and both copies produce the same handles in the same order because
/// both run the same `describeBuffers` passes.
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

/// Registers a declared scene's archetypes and assets, once, at boot.
final class _GameSceneDescriptor implements GameSceneDescriptor {
  _GameSceneDescriptor(this._runtime);

  final GameRuntime _runtime;
  Game get _game => _runtime.game;

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
    final state = _runtime.state!;
    scene.bindState(state);
    if (!scene.isInitialized) {
      scene.initializeScene(
        state.pool,
        assets: _game.assets,
        cameraViews: _game.cameraViews,
      );
    }
    _game._declaredScenes.add(scene);
    return scene;
  }
}

/// Collects declared systems into the [GameState] that declares and runs them.
///
/// Records declaration order, which *is* execution order - see the class doc
/// on [Game]. Systems are keyed by `runtimeType`, not by the type argument, so
/// `descriptor.has(Transform2DSystem())` and `getSystem<Transform2DSystem>()`
/// agree without the caller having to spell the type argument twice.
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

/// Forwards `Game.describeAssetLoaders` into the per-isolate registry.
///
/// `const`, holding nothing: the registry it writes to is a static, and giving
/// the hook an object to talk to instead of the static itself is what keeps
/// the pass a declaration - see [AssetLoaderRegistrar].
final class _LoaderRegistrar implements AssetLoaderRegistrar {
  const _LoaderRegistrar();

  @override
  void register<T>(AssetLoader<T> loader) => AssetLoaders.register<T>(loader);
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
/// A non-generic interface, not `_StateChannelBase<Object?>` in the list: the
/// whole point of these operations is that they are type-erased plumbing
/// (allocate, announce, adopt, poll, free), and none of them wants to expose or
/// launder the channel's value type.
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

/// The fixed-width formats a [StateChannel] can carry - the same set
/// `DataDescriptor` offers for component fields, for the same reason: a
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
/// One class for both isolate roles, not a read-only subclass and a writable
/// one: `StateChannel` has a setter on both sides, and the split is enforced
/// by [owned] and an `assert` (the assert-not-print rule) instead of by the
/// type system. That trade buys one declared type usable from Flutter on the
/// main isolate, which is what `ValueListenable` requires. A write from there
/// is a programmer error, not something a caller should be handed two types to
/// reason about.
abstract class _StateChannelBase<T>
    with ChangeNotifier
    implements StateChannel<T>, _ChannelSlot {
  _StateChannelBase({
    required this.index,
    required this.format,
    required this.initialValue,
    required GameRuntime runtime,
    // A named parameter cannot start with an underscore, so `this._runtime` is
    // not spellable and the lint's suggestion does not compile.
    // ignore: prefer_initializing_formals
  }) : _runtime = runtime,
       _lastSeen = initialValue;

  /// Position in the shared declaration order - this channel's identity on
  /// the wire, and what diagnostics name it by.
  final int index;
  final _ChannelFormat format;
  final T initialValue;

  /// The **run** this channel's storage belongs to - held instead of two
  /// booleans, because the two questions it answers (who owns the storage, who
  /// may write) have different answers here.
  final GameRuntime _runtime;

  /// Whether this copy allocated the storage, and so must free it. Main, in
  /// the spawned configuration.
  bool get owned => _runtime.owns;

  /// Whether this copy may *write*. The simulating one - which after the boot
  /// inversion is a different copy from the one that owns the memory.
  ///
  /// A `TripleBuffer` requires one writer, not a particular isolate, so
  /// allocate-here/write-there is legal; `InputDevice` has always been the
  /// mirror image of it.
  bool get _mayWrite => _runtime.simulates;

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
  /// channel per tick, forever, for nobody (the hot-path rules). Doing it
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
    required super.runtime,
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
    required super.runtime,
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

/// One byte, not one bit: a channel is its own allocation, never a field
/// packed into a shared row, so there is nothing to save by sub-byte packing
/// and a whole byte to gain in read/write simplicity.
final class _BoolStateChannel extends _StateChannelBase<bool> {
  _BoolStateChannel({
    required super.index,
    required super.initialValue,
    required super.runtime,
  }) : super(format: _ChannelFormat.boolean);

  @override
  bool readFrom(ByteData view) => view.getUint8(0) != 0;

  @override
  void writeTo(ByteData view, bool value) => view.setUint8(0, value ? 1 : 0);
}

final class _StateDescriptor implements StateDescriptor {
  _StateDescriptor(this._runtime);

  final GameRuntime _runtime;
  Game get _game => _runtime.game;
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
      runtime: _runtime,
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
      runtime: _runtime,
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
      runtime: _runtime,
    );
    _game._stateChannels.add(channel);
    return channel;
  }
}

// --- the engine's own control commands -------------------------------------
//
// These replace four string tags on the control port (#142). Every one of them
// is **receipt-delivered**, and it has to be: each can stop the fixed tick, and
// a tick-delivered command is pumped from `runFixedStep`, so the message that
// started the tick again would be waiting on the tick it stopped.
//
// Declared by the engine in `Game.describeCommands`, before anything a game
// declares. Both copies run the same pass in the same order, so the indices
// agree the way they do for a game's own commands.

final class _SetVisibleCommand extends SinkCommand<bool> {
  final visible = Param.uint1();

  @override
  void bufferFromParams(ParamBuffer call, bool params) =>
      visible[call] = params ? 1 : 0;

  @override
  bool paramsFromBuffer(ParamBuffer call) => visible[call] == 1;
}

final class _SetPausedCommand extends SinkCommand<bool> {
  final paused = Param.uint1();

  @override
  void bufferFromParams(ParamBuffer call, bool params) =>
      paused[call] = params ? 1 : 0;

  @override
  bool paramsFromBuffer(ParamBuffer call) => paused[call] == 1;
}

final class _SetTimeScaleCommand extends SinkCommand<double> {
  final scale = Param.float64();

  @override
  void bufferFromParams(ParamBuffer call, double params) =>
      scale[call] = params;

  @override
  double paramsFromBuffer(ParamBuffer call) => scale[call];
}

final class _StepOnceCommand extends SignalCommand {}

typedef _DisabledSystemReport = ({
  String systemName,
  String error,
  String stackTrace,
});

final class _ReportDisabledSystemCommand
    extends SinkCommand<_DisabledSystemReport> {
  static const int maxSystemNameBytes = 256;
  static const int maxErrorBytes = 1024;
  static const int maxStackTraceBytes = 2048;

  // Capped on purpose, and one of the few places where that is the right
  // answer rather than the only one available. This command reports a system
  // that threw, so it travels while the game is already in trouble: a
  // length-free Param.string() would put an unbounded stack trace on the
  // command ring, and a batch too big for the ring throws at the send -
  // inside the path reporting somebody else's throw. See
  // [_truncateToUtf8Bytes].
  final systemName = Param.fixedString(maxSystemNameBytes);
  final error = Param.fixedString(maxErrorBytes);
  final stackTrace = Param.fixedString(maxStackTraceBytes);

  @override
  void bufferFromParams(ParamBuffer call, _DisabledSystemReport params) {
    systemName[call] = _truncateToUtf8Bytes(
      params.systemName,
      maxSystemNameBytes,
    );
    error[call] = _truncateToUtf8Bytes(params.error, maxErrorBytes);
    stackTrace[call] = _truncateToUtf8Bytes(
      params.stackTrace,
      maxStackTraceBytes,
    );
  }

  @override
  _DisabledSystemReport paramsFromBuffer(ParamBuffer call) => (
    systemName: systemName[call],
    error: error[call],
    stackTrace: stackTrace[call],
  );
}

/// [text] cut to at most [maxBytes] **bytes** of UTF-8, on a character
/// boundary.
///
/// The boundary matters. `Param.fixedString` reserves a byte count and refuses
/// a write that does not fit, so a cut through the middle of a multi-byte
/// character cannot simply be decoded with `allowMalformed`: the malformed
/// tail comes back as U+FFFD, which re-encodes to three bytes and can push
/// the result back over the cap - and the throw would land inside the path
/// reporting somebody else's throw. Continuation bytes are `10xxxxxx`, so
/// walking back off them finds the start of the character the cut fell
/// inside, and dropping it keeps the result under the cap.
String _truncateToUtf8Bytes(String text, int maxBytes) {
  final bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) return text;
  var end = maxBytes;
  while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
    end--;
  }
  return utf8.decode(bytes.sublist(0, end));
}

/// Whether [state] counts as the app being visible.
///
/// The five-to-two collapse, in one place so it can be tested as itself: the
/// alternative is a widget test that drives real lifecycle messages to assert
/// a `switch`, which tests the binding more than the decision.
///
/// `inactive` is the load-bearing entry. It is a window that lost focus, a
/// phone call, the notification shade, the app switcher - all of them still on
/// screen - so it is **visible**, and pausing there is the bug where a game
/// stops because you alt-tabbed. `hidden` is where every view is actually
/// gone, and iOS and Android synthesise it before `paused` so this needs no
/// per-platform branch.
@internal
bool visibleInLifecycleState(AppLifecycleState state) => switch (state) {
  AppLifecycleState.resumed || AppLifecycleState.inactive => true,
  AppLifecycleState.hidden ||
  AppLifecycleState.paused ||
  AppLifecycleState.detached => false,
};

/// Whether [state] means input can still reach the app.
///
/// Only `resumed` does. Flutter defines `inactive` as at least one view
/// visible with **none of them focused**, and a keyboard event goes to the
/// focused window alone on every platform this runs on - so from `inactive`
/// down, the up that would say a key was let go is delivered somewhere else
/// and never arrives.
///
/// Measured on Windows 11 against a real desktop build, because a widget test
/// synthesises lifecycle transitions with no window manager behind them and
/// cannot answer what the OS delivers. Taking focus away from the window
/// reports `inactive`, and from that moment the app sees no key events of any
/// kind: not the up for the key that was held, not the down or the up of a
/// key pressed while unfocused. The key it last heard a down for stays in
/// `HardwareKeyboard.physicalKeysPressed` through the refocus and for the
/// rest of the run.
///
/// The line this draws and the one [visibleInLifecycleState] draws fall in
/// different places, which is why there are two predicates. The same
/// measurement counted frames across the unfocused stretch and they kept
/// coming at the rate they had before: `inactive` is drawn and stepping, and
/// only unreachable.
@internal
bool focusedInLifecycleState(AppLifecycleState state) =>
    state == AppLifecycleState.resumed;

/// Watches `AppLifecycleState` on the main isolate and forwards **visibility**
/// to the simulating copy.
///
/// # Five states become two
///
/// `resumed` and `inactive` are visible; `hidden`, `paused` and `detached` are
/// not. The interesting line is the one between `inactive` and `hidden`, and
/// Flutter draws it exactly where a game wants it:
///
///   * `inactive` is a window that lost focus, a phone call, the notification
///     shade, the app switcher - **still on screen**. Pausing here is the bug
///     where a game stops because you alt-tabbed to look something up.
///   * `hidden` is every view gone: minimised, or about to be paused. iOS and
///     Android synthesise it *before* `paused` specifically so cross-platform
///     code needs only one handler, so this needs no per-platform branch.
///
/// `detached` counts as hidden and gets no hook of its own. See
/// [AppVisibilityListener] for why there is no "about to be killed" callback.
class _VisibilityObserver with WidgetsBindingObserver {
  Game? _game;

  void arm(Game game) {
    if (_game != null) return;
    _game = game;
    WidgetsBinding.instance.addObserver(this);
  }

  void disarm() {
    if (_game == null) return;
    WidgetsBinding.instance.removeObserver(this);
    _game = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final game = _game;
    if (game == null) return;
    final visible = visibleInLifecycleState(state);
    // Released here rather than on the far side of the command, because the
    // far side cannot do it: `InputDevice` is the Flutter-isolate write end
    // and `Game.inputDevice` is null on the copy that runs the simulation.
    // Same trigger, correct side of the boundary - and the block is published
    // by the time the visibility command lands, so the first tick that knows
    // the app went away already reads nothing held.
    //
    // Idempotent for the same reason `setVisible` has to be, and by the same
    // mechanism: `releaseAll` publishes only when a bit actually moved, so
    // the second "not visible" of a backgrounding walk costs nothing.
    //
    // Hung off focus and not off visibility, which is the one place these
    // two questions want different answers: `inactive` is a window still on
    // screen and still being drawn, and it is also a window the OS has
    // stopped delivering key events to, so the up for whatever was held goes
    // to whoever took the focus. See `focusedInLifecycleState` for the
    // measurement.
    if (!focusedInLifecycleState(state)) game.inputDevice?.releaseAll();
    // `GameState.setVisible` is idempotent, which it has to be: the walk down
    // is `inactive -> hidden -> paused` and the walk back up reverses it, so
    // "not visible" arrives twice around any real backgrounding.
    game._sendControl(() => game._setVisibleCommand(visible));
  }
}
