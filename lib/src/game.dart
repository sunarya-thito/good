import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:goo2d/goo2d.dart' hide AudioSource;
import 'package:meta/meta.dart';
import 'package:goo2d/src/ticker.dart';

/// An interface for modular systems that extend the functionality of the [GameEngine].
///
/// Systems are used to encapsulate specific game engine features (like physics,
/// audio, or input) and provide a centralized place for their state and logic.
/// They are initialized once per game instance and can be retrieved from the
/// engine using [GameEngine.getSystem].
///
/// ```dart
/// class MySystem implements GameSystem {
///   @override
///   late GameEngine game;
///   @override
///   bool get gameAttached => _attached;
///   bool _attached = false;
///   @override
///   Future<void> attach(GameEngine game) async {
///     this.game = game;
///     _attached = true;
///   }
///   @override
///   Future<void> dispose() async {}
/// }
/// ```
///
/// See also:
/// * [GameEngine], which manages and provides access to these systems.
abstract interface class GameSystem {
  /// The [GameEngine] this system is currently attached to.
  ///
  /// This property is set during initialization and provides the system
  /// with access to other engine modules and game state.
  GameEngine get game;

  /// Whether the system is currently attached to a [GameEngine].
  ///
  /// This should return true after [attach] has been called and before
  /// [dispose] is completed.
  bool get gameAttached;

  /// Attaches the system to a [GameEngine] and performs any async setup.
  ///
  /// Called by [GameEngine.create] or [GameEngine.addSystem]. Systems that
  /// need to spawn isolates, initialize native libraries, or load resources
  /// do so here instead of in a separate static initializer.
  ///
  /// * [game]: The engine instance to attach to.
  Future<void> attach(GameEngine game);

  /// Disposes of the system and its resources.
  ///
  /// Called by [GameEngine.removeSystem] or [GameEngine.dispose]. Tears down
  /// all static state so the system can be reinitialized later via [attach].
  Future<void> dispose();
}

typedef GameSystemFactory<T extends GameSystem> = T Function();

/// Extensions for [GameSystemFactory] to support declarative unregistration.
///
/// These operators enable a powerful syntax for removing default engine
/// systems during initialization by using the unary minus or tilde operators
/// on their factory functions.
///
/// ```dart
/// final engine = GameEngine(
///   systems: {
///     ...GameEngine.defaultSystems,
///     -InputSystem.new, // Declaratively unregister the default input system
///   },
/// );
/// ```
extension GameSystemFactoryExtension<T extends GameSystem>
    on GameSystemFactory<T> {
  /// Unregisters a system of type [T] from the engine's default systems.
  ///
  /// This operator allows for a concise syntax when customizing the
  /// engine's system list.
  GameSystemFactory<T> operator -() => _nullFactory<T>;

  /// Alias for the unary minus operator.
  ///
  /// Provides an alternative syntax for unregistering systems, which can be
  /// useful depending on personal preference or code style.
  GameSystemFactory<T> operator ~() => _nullFactory<T>;
}

T _nullFactory<T extends GameSystem>() => throw _Unregister<T>();

class _Unregister<T extends GameSystem> {
  bool isInstance(GameSystem s) => s is T;
}

/// The central coordinator for all Goo2D engine systems and state.
///
/// The [GameEngine] manages the lifecycle of various [GameSystem]s and
/// provides a centralized access point for core features like input,
/// physics, and time management. It uses a modular architecture where
/// features are registered as systems, allowing for a flexible and
/// extensible engine core.
///
/// ```dart
/// class MySystem implements GameSystem {
///   @override
///   late final GameEngine game;
///   @override
///   bool get gameAttached => _attached;
///   bool _attached = false;
///   @override
///   Future<void> attach(GameEngine game) async {
///     this.game = game;
///     _attached = true;
///   }
///   @override
///   Future<void> dispose() async {}
/// }
///
/// void main() async {
///   final engine = await GameEngine.create({
///     ...GameEngine.defaultSystems,
///     -InputSystem.new, // Remove default input system
///     MySystem.new,     // Add custom system
///   });
///   runApp(Game(engine: engine, child: MyWorld()));
/// }
/// ```
///
/// See also:
/// * [GameSystem], the base interface for engine modules.
/// * [GameProvider], for accessing the engine through the widget tree.
class GameEngine {
  /// The collection of systems included by default in a new engine instance.
  ///
  /// This set includes essential engine components like time management,
  /// input handling, physics, and rendering support.
  static const defaultSystems = {
    TickerState.new,
    InputSystem.new,
    PhysicsSystem.new,
    CameraSystem.new,
    ScreenSystem.new,
    ScreenPhysicsSystem.new,
    AudioSystem.new,
  };

  /// Retrieves the [GameEngine] instance from the nearest [GameProvider].
  ///
  /// * [context]: The build context used to locate the provider.
  static GameEngine of(BuildContext context) {
    return GameProvider.of(context);
  }

  final List<GameSystem> _systems = [];
  final Map<Type, GameSystem?> _cachedSystems = {};

  GameEngine._();

  /// Creates and fully initializes a [GameEngine] with the given [systems].
  ///
  /// Each system's [GameSystem.attach] is awaited, so isolate spawning and
  /// native library initialization happen here rather than in a separate
  /// static call. The engine is ready to use when the returned [Future] completes.
  ///
  /// ```dart
  /// final engine = await GameEngine.create({
  ///   TickerState.new,
  ///   CollisionSystem.new,
  ///   CameraSystem.new,
  /// });
  /// runApp(Game(engine: engine, child: MyWorld()));
  /// ```
  static Future<GameEngine> create([
    Set<GameSystemFactory> systems = defaultSystems,
  ]) async {
    final engine = GameEngine._();
    for (final factory in systems) {
      // TODO: This part is flawed, it forces the factory to register
      // and then unregister the system if it's a _Unregister.
      try {
        final system = factory();
        engine._systems.add(system);
        await system.attach(engine);
      } catch (e) {
        if (e is _Unregister) {
          final toDispose = engine._systems
              .where((s) => e.isInstance(s))
              .toList();
          for (final s in toDispose) {
            await s.dispose();
            engine._systems.remove(s);
          }
          engine._cachedSystems.clear();
        } else {
          rethrow;
        }
      }
    }
    await GridMesh.loadShader();
    return engine;
  }

  /// Adds a single [system] to this engine at runtime and awaits its [GameSystem.attach].
  ///
  /// Use this to switch engines (e.g. from [PhysicsSystem] to `CollisionSystem`)
  /// without rebuilding the whole engine.
  Future<void> addSystem(GameSystem system) async {
    _systems.add(system);
    _cachedSystems.clear();
    await system.attach(this);
  }

  /// Removes and disposes the system of type [T].
  ///
  /// [GameSystem.dispose] is awaited so isolate teardown and static-state
  /// reset complete before the system is removed from the registry.
  Future<void> removeSystem<T extends GameSystem>() async {
    final system = getSystem<T>();
    if (system == null) return;
    await system.dispose();
    _systems.remove(system);
    _cachedSystems.clear();
  }

  /// Retrieves a registered system of type [T], or null if not present.
  T? getSystem<T extends GameSystem>() {
    if (_cachedSystems.containsKey(T)) return _cachedSystems[T] as T?;
    for (final system in _systems) {
      if (system is T) {
        _cachedSystems[T] = system;
        return system;
      }
    }
    _cachedSystems[T] = null;
    return null;
  }

  /// Returns whether a system of type [T] is currently registered.
  bool hasSystem<T extends GameSystem>() => getSystem<T>() != null;

  /// Disposes all registered systems in reverse order and clears the cache.
  Future<void> dispose() async {
    for (final system in _systems.reversed.toList()) {
      await system.dispose();
    }
    _systems.clear();
    _cachedSystems.clear();
  }

  /// The system responsible for managing time, frame counts, and the game loop.
  ///
  /// It provides high-precision delta times and coordinates the various
  /// update stages (Tick, FixedTick, LateTick) across the object hierarchy.
  TickerState get ticker {
    final tickerSystem = getSystem<TickerState>();
    assert(tickerSystem != null, 'TickerState not registered');
    return tickerSystem!;
  }

  /// The system responsible for processing and dispatching user input.
  ///
  /// It centralizes the state of keys, pointers, and gamepads, ensuring
  /// that input events are synchronized with the game's update loop.
  InputSystem get input {
    final inputSystem = getSystem<InputSystem>();
    assert(inputSystem != null, 'InputSystem not registered');
    return inputSystem!;
  }

  /// The system responsible for simulating physical interactions.
  ///
  /// If registered, it manages collision detection and rigid body
  /// simulations using the underlying physics engine.
  PhysicsSystem? get physics => getSystem<PhysicsSystem>();

  /// The system responsible for managing and sorting game cameras.
  ///
  /// It allows for multi-camera setups, recursive rendering passes, and
  /// depth-based sorting of viewport configurations.
  CameraSystem get cameras {
    final camerasSystem = getSystem<CameraSystem>();
    assert(camerasSystem != null, 'CameraSystem not registered');
    return camerasSystem!;
  }

  /// The system responsible for providing screen metrics and boundaries.
  ///
  /// Use this to respond to window resizing or to calculate coordinates
  /// relative to the game's display area.
  ScreenSystem get screen {
    final screenSystem = getSystem<ScreenSystem>();
    assert(screenSystem != null, 'ScreenSystem not registered');
    return screenSystem!;
  }

  /// The system responsible for high-performance screen boundary physics.
  ///
  /// It provides specialized collision logic for keeping objects within
  /// the visible game area without the overhead of full rigid body physics.
  ScreenPhysicsSystem? get screenPhysics => getSystem<ScreenPhysicsSystem>();

  /// The system responsible for playing and managing game audio.
  ///
  /// It provides a high-level API for sound effects, music, and spatial
  /// audio using the SoLoud backend.
  AudioSystem? get audio => getSystem<AudioSystem>();
}

/// The system responsible for managing time, frame counts, and the game loop.
///
/// [TickerState] tracks the delta time between frames, maintains a fixed
/// update frequency for physics, and provides a stream of frame completion
/// signals. It is the heartbeat of the Goo2D engine.
///
/// ```dart
/// final ticker = TickerState();
/// print('Time: ${ticker.time}');
/// await ticker.nextFrame;
/// ```
///
/// See also:
/// * [GameLoop], the widget that drives this ticker.
/// * [YieldInstruction], for time-based synchronization in coroutines.
class TickerState implements GameSystem, CoroutineClock {
  @override
  late final GameEngine game;

  @override
  bool get gameAttached => _attached;
  bool _attached = false;

  @override
  Future<void> attach(GameEngine game) async {
    this.game = game;
    _attached = true;
  }

  List<GameObject?> _rootSlots = List.filled(64, null);
  int _rootSlotCap = 64;

  /// The collection of root game objects managed by this ticker.
  ///
  /// Root objects are those without a parent in the game object hierarchy.
  /// They serve as the entry points for broadcasting update events.
  Iterable<GameObject> get rootObjects =>
      _rootSlots.sublist(0, _rootSlotCap).whereType<GameObject>();

  @internal
  void registerRootObject(GameObject object) {
    for (var i = 0; i < _rootSlotCap; i++) {
      if (_rootSlots[i] == object) return;
    }
    for (var i = 0; i < _rootSlotCap; i++) {
      if (_rootSlots[i] == null) {
        _rootSlots[i] = object;
        return;
      }
    }
    final newCap = _rootSlotCap * 2;
    final newSlots = List<GameObject?>.filled(newCap, null);
    for (var i = 0; i < _rootSlotCap; i++) {
      newSlots[i] = _rootSlots[i];
    }
    newSlots[_rootSlotCap] = object;
    _rootSlots = newSlots;
    _rootSlotCap = newCap;
  }

  @internal
  void unregisterRootObject(GameObject object) {
    for (var i = 0; i < _rootSlotCap; i++) {
      if (_rootSlots[i] == object) {
        _rootSlots[i] = null;
        return;
      }
    }
  }

  /// The time elapsed since the last frame, in seconds.
  ///
  /// Use this to scale movement or other time-dependent logic to be
  /// independent of the frame rate.
  double deltaTime = 0.0;

  /// The constant time step used for fixed physics updates, in seconds.
  ///
  /// This ensures that physics simulations remain stable and deterministic
  /// regardless of fluctuations in the rendering frame rate.
  double fixedDeltaTime = 0.02;

  /// The total time elapsed since the engine started, in seconds.
  ///
  /// This value increments continuously on every frame and can be used for
  /// periodic effects or absolute time measurements.
  double time = 0.0;

  /// The total number of frames rendered since the engine started.
  ///
  /// This count increases by exactly one on every render pass.
  int frameCount = 0;

  final _frameController = StreamController<void>.broadcast();

  /// A future that completes when the next frame is finished processing.
  ///
  /// This is used for frame-based synchronization and custom yield
  /// instructions in coroutines.
  @override
  Future<void> get nextFrame {
    if (_frameController.isClosed) return Future.value();
    return _frameController.stream.first.catchError((e) {
      if (e is StateError) return null;
      throw e;
    });
  }

  /// Updates the internal time state.
  ///
  /// * [dt]: The delta time to add.
  void update(double dt) {
    deltaTime = dt;
    time += dt;
    frameCount++;
  }

  /// Executes a single engine tick, processing input and frame-rate dependent logic.
  ///
  /// Fixed-step physics and simulation are driven by a separate Timer via [fixedTick].
  ///
  /// * [dt]: The time elapsed since the last frame.
  void tick(double dt) {
    update(dt);
    game.getSystem<InputSystem>()?.update();

    for (var i = 0; i < _rootSlotCap; i++) {
      _rootSlots[i]?.broadcastEvent(TickEvent(dt));
    }

    game.screenPhysics?.update();

    for (var i = 0; i < _rootSlotCap; i++) {
      _rootSlots[i]?.broadcastEvent(LateTickEvent(dt));
    }

    signalFrameComplete();
  }

  /// Executes one fixed-interval simulation step.
  ///
  /// Called by the [RenderGameLoop] Timer at a constant rate (default 50Hz).
  /// Broadcasts [FixedTickEvent] to all game objects, then steps the physics system.
  Future<void> fixedTick() async {
    final event = FixedTickEvent(fixedDeltaTime);
    for (var i = 0; i < _rootSlotCap; i++) {
      final obj = _rootSlots[i];
      if (obj != null) await obj.broadcastEventAsync(event);
    }
    await game.getSystem<PhysicsSystem>()?.step();
    await game.getSystem<CollisionSystem>()?.step();
  }

  /// Signals that the current frame has finished processing.
  ///
  /// This notifies any listeners waiting on [nextFrame].
  void signalFrameComplete() {
    if (!_frameController.isClosed) {
      _frameController.add(null);
    }
  }

  @override
  Future<void> dispose() async {
    _frameController.close();
  }
}

/// The system responsible for managing and sorting game cameras.
///
/// [CameraSystem] maintains a list of all active cameras, identifies the
/// main camera for the primary render pass, and handles depth-based sorting
/// to ensure correct rendering order.
///
/// ```dart
/// final camera = Camera();
/// // Use the engine instance obtained from GameEngine.create()
/// engine.cameras.registerCamera(camera);
/// ```
///
/// See also:
/// * [Camera], the component used to define viewports.
/// * [GameRenderer], which uses this system for the paint phase.
class CameraSystem implements GameSystem {
  @override
  late final GameEngine game;

  @override
  bool get gameAttached => _attached;
  bool _attached = false;

  /// Whether the current render pass is a secondary (recursive) pass.
  ///
  /// This is used to distinguish between the main viewport rendering and
  /// specialized passes (like shadows or reflections).
  bool isSecondaryPass = false;

  /// The camera currently being used for rendering.
  ///
  /// This property is set dynamically by the [GameRenderer] during the
  /// paint phase.
  Camera? currentRenderCamera;

  Camera? _main;
  final List<Camera> _allCameras = [];

  @override
  Future<void> attach(GameEngine game) async {
    this.game = game;
    _attached = true;
  }

  /// The primary camera used for rendering the main scene.
  ///
  /// This is typically the camera with the highest depth. It is required
  /// for calculating the initial view matrix.
  Camera get main {
    if (_main == null) {
      throw StateError(
        'Main camera is not ready for this game instance. Make sure you have a GameWidget with GameTag(\'MainCamera\')',
      );
    }
    return _main!;
  }

  /// Whether at least one camera is registered and ready for rendering.
  ///
  /// Check this property before attempting to perform operations that
  /// require a valid camera configuration.
  bool get isReady => _main != null;

  /// The collection of all cameras currently registered with the system.
  ///
  /// This list is automatically sorted by depth whenever a camera's depth
  /// property is changed or a new camera is registered.
  List<Camera> get allCameras => List.unmodifiable(_allCameras);

  /// Registers a [camera] with the system.
  ///
  /// This adds the camera to the internal tracking list and triggers a
  /// resort of the camera hierarchy.
  ///
  /// * [camera]: The camera to register.
  void registerCamera(Camera camera) {
    if (!_allCameras.contains(camera)) {
      _allCameras.add(camera);
      _updateMainCamera();
    }
  }

  /// Unregisters a [camera] from the system.
  ///
  /// This removes the camera from the tracking list and updates the main
  /// camera reference if necessary.
  ///
  /// * [camera]: The camera to unregister.
  void unregisterCamera(Camera camera) {
    _allCameras.remove(camera);
    if (_main == camera) {
      _main = null;
      _updateMainCamera();
    }
  }

  /// Notifies the system that a camera's depth has changed, requiring a resort.
  ///
  /// This ensures that the rendering order remains consistent with the
  /// specified depth values.
  void notifyDepthChanged() {
    _updateMainCamera();
  }

  void _updateMainCamera() {
    if (_allCameras.isEmpty) {
      _main = null;
      return;
    }
    // Sort by depth descending, so the highest depth is at index 0.
    _allCameras.sort((a, b) => b.depth.compareTo(a.depth));
    _main = _allCameras.first;
  }

  @override
  Future<void> dispose() async {
    _allCameras.clear();
    _main = null;
  }
}

void _stopSoundHandle(SoundHandle? handle) {
  if (handle == null) return;
  if (SoLoud.instance.isInitialized &&
      SoLoud.instance.getIsValidVoiceHandle(handle)) {
    SoLoud.instance.stop(handle);
  }
}

/// Returned by [MusicTransition.transition] to represent an in-progress
/// background music transition.
///
/// Each [MusicTransition] subclass provides its own implementation that tracks
/// whatever state is needed (the fading-out handle, a deferred-start timer,
/// etc.). The [AudioSystem] stores one handle per channel and calls the
/// appropriate method when the channel is interrupted or disposed.
abstract class MusicTransitionHandle {
  /// The [SoundHandle] being established as the new audio on this channel,
  /// or `null` when transitioning to silence.
  SoundHandle? get handle;

  /// Cancels any pending deferred actions without stopping audio.
  ///
  /// Called by [AudioSystem] before a new transition starts on the same
  /// channel, preventing a stale [FadeOutInMusicTransition] timer from
  /// unpausing a handle that is already being transitioned away.
  void cancelDeferred();

  /// Stops all audio involved in this transition immediately.
  ///
  /// Called when the [BackgroundMusic] widget is disposed or its [channel]
  /// changes. Implementations should cancel deferred timers and stop both
  /// the outgoing and incoming handles.
  void stop();
}

class _NoTransitionHandle implements MusicTransitionHandle {
  @override
  final SoundHandle? handle;
  const _NoTransitionHandle(this.handle);

  @override
  void cancelDeferred() {}

  @override
  void stop() => _stopSoundHandle(handle);
}

class _CrossFadeHandle implements MusicTransitionHandle {
  @override
  final SoundHandle? handle;
  final SoundHandle? _fadingOut;

  const _CrossFadeHandle(this.handle, this._fadingOut);

  @override
  void cancelDeferred() {}

  @override
  void stop() {
    _stopSoundHandle(_fadingOut);
    _stopSoundHandle(handle);
  }
}

class _FadeOutInHandle implements MusicTransitionHandle {
  @override
  final SoundHandle? handle;
  final SoundHandle? _fadingOut;
  Timer? _timer;

  _FadeOutInHandle(this.handle, this._fadingOut, this._timer);

  @override
  void cancelDeferred() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void stop() {
    cancelDeferred();
    _stopSoundHandle(_fadingOut);
    _stopSoundHandle(handle);
  }
}

/// Controls how background music transitions between tracks on a channel.
///
/// Implementations define the blend behaviour for three cases:
/// - **Starting** ([oldHandle] is `null`): begin the first track.
/// - **Stopping** ([newHandle] is `null`): fade to silence.
/// - **Changing** (both non-null): crossfade or sequence the two tracks.
///
/// [AudioSystem.transitionMusic] starts [newHandle] paused at volume 0 before
/// calling [transition], so each implementation is responsible for unpausing
/// and adjusting volume at the appropriate time.
///
/// ```dart
/// BackgroundMusic(
///   audio: MyAudio.theme,
///   transition: CrossFadeMusicTransition(duration: 2.0),
/// )
/// ```
abstract class MusicTransition {
  const MusicTransition();
  const factory MusicTransition.noTransition() = NoMusicTransition;

  /// Applies the transition from [oldHandle] to [newHandle] and returns a
  /// [MusicTransitionHandle] that manages the resulting state.
  MusicTransitionHandle transition(
    SoundHandle? oldHandle,
    SoundHandle? newHandle,
  );
}

/// Stops the current track instantly and starts the next with no overlap.
class NoMusicTransition implements MusicTransition {
  const NoMusicTransition();

  @override
  MusicTransitionHandle transition(
    SoundHandle? oldHandle,
    SoundHandle? newHandle,
  ) {
    _stopSoundHandle(oldHandle);
    if (newHandle != null) {
      SoLoud.instance.setVolume(newHandle, 1.0);
      SoLoud.instance.setPause(newHandle, false);
    }
    return _NoTransitionHandle(newHandle);
  }
}

/// Simultaneously fades out the current track and fades in the next.
class CrossFadeMusicTransition implements MusicTransition {
  final double duration;
  const CrossFadeMusicTransition({this.duration = 1.0});

  @override
  MusicTransitionHandle transition(
    SoundHandle? oldHandle,
    SoundHandle? newHandle,
  ) {
    final d = Duration(milliseconds: (duration * 1000).round());
    if (oldHandle != null && SoLoud.instance.getIsValidVoiceHandle(oldHandle)) {
      SoLoud.instance.fadeVolume(oldHandle, 0.0, d);
      SoLoud.instance.scheduleStop(oldHandle, d);
    }
    if (newHandle != null) {
      SoLoud.instance.setPause(newHandle, false);
      SoLoud.instance.fadeVolume(newHandle, 1.0, d);
    }
    return _CrossFadeHandle(newHandle, oldHandle);
  }
}

/// Fades out the current track completely, then fades in the next.
///
/// Each phase takes [duration] / 2 seconds, so the total transition is [duration].
class FadeOutInMusicTransition implements MusicTransition {
  final double duration;
  const FadeOutInMusicTransition({this.duration = 1.0});

  @override
  MusicTransitionHandle transition(
    SoundHandle? oldHandle,
    SoundHandle? newHandle,
  ) {
    final half = Duration(milliseconds: (duration * 500).round());
    if (oldHandle != null && SoLoud.instance.getIsValidVoiceHandle(oldHandle)) {
      SoLoud.instance.fadeVolume(oldHandle, 0.0, half);
      SoLoud.instance.scheduleStop(oldHandle, half);
    }
    Timer? timer;
    if (newHandle != null) {
      timer = Timer(half, () {
        if (SoLoud.instance.getIsValidVoiceHandle(newHandle)) {
          SoLoud.instance.setPause(newHandle, false);
          SoLoud.instance.fadeVolume(newHandle, 1.0, half);
        }
      });
    }
    return _FadeOutInHandle(newHandle, oldHandle, timer);
  }
}

/// Tracks the active [MusicTransitionHandle] on a single background music channel.
class _MusicChannel {
  MusicTransitionHandle? currentTransition;
  GameAudio? currentAudio;
  Object? owner;
}

/// The system responsible for playing and managing game audio.
///
/// [AudioSystem] wraps the SoLoud engine, providing a unified interface
/// for sound playback, volume management, and resource cleanup. It tracks
/// active sound handles to ensure they are stopped when the system is
/// disposed.
///
/// ```dart
/// // AudioSystem initializes automatically during GameEngine.create().
/// engine.audio?.globalVolume = 0.5;
/// ```
///
/// See also:
/// * [AudioSource], for loading and playing sounds.
/// * [SoundHandle], for managing active playback instances.
class AudioSystem implements GameSystem {
  static bool _isInitialized = false;

  final PlaybackDevice? device;
  final bool automaticCleanup;
  final int sampleRate;
  final int bufferSize;
  final Channels channels;

  AudioSystem({
    this.device,
    this.automaticCleanup = false,
    this.sampleRate = 44100,
    this.bufferSize = 2048,
    this.channels = Channels.stereo,
  });

  final Set<SoundHandle> _handles = {};
  final Map<int, _MusicChannel> _musicChannels = {};

  /// Transitions the background music on [channel] to [newAudio].
  ///
  /// Pass `newAudio: null` to stop music on the channel. The [transition]
  /// controls how the old and new tracks blend — instant cut, crossfade, or
  /// fade-out then fade-in.
  ///
  /// Any in-progress deferred action on the channel (e.g. a [FadeOutInMusicTransition]
  /// timer) is cancelled before the new transition begins.
  void transitionMusic({
    required int channel,
    required GameAudio? newAudio,
    required MusicTransition transition,
    Object? owner,
  }) {
    if (!_isInitialized) return;
    final ch = _musicChannels.putIfAbsent(channel, _MusicChannel.new);

    if (newAudio != null && newAudio == ch.currentAudio) {
      // Transfer ownership so the old widget's dispose() won't stop the music.
      ch.owner = owner;
      return;
    }

    ch.currentTransition?.cancelDeferred();
    final oldHandle = ch.currentTransition?.handle;
    if (oldHandle != null) unregisterHandle(oldHandle);

    SoundHandle? newHandle;
    if (newAudio != null) {
      assert(
        newAudio.isLoaded,
        'BackgroundMusic: audio must be loaded before calling transitionMusic()',
      );
      newHandle = SoLoud.instance.play(
        newAudio.audioSource,
        volume: 0.0,
        looping: true,
        paused: true,
      );
      registerHandle(newHandle);
    }

    ch.currentTransition = transition.transition(oldHandle, newHandle);
    ch.currentAudio = newAudio;
    ch.owner = owner;
  }

  /// Stops music on [channel] only if [owner] still owns it.
  ///
  /// Used by [BackgroundMusic] on dispose so that a widget being removed does
  /// not stop audio that a newly-mounted widget with the same track has already
  /// taken ownership of.
  void releaseMusic({
    required int channel,
    required Object? owner,
    required MusicTransition transition,
  }) {
    final ch = _musicChannels[channel];
    if (ch == null || ch.owner != owner) return;
    transitionMusic(channel: channel, newAudio: null, transition: transition);
  }

  GameEngine? _game;

  @override
  GameEngine get game {
    assert(_game != null, 'AudioSystem is not attached to a GameEngine');
    return _game!;
  }

  @override
  bool get gameAttached => _game != null;

  @override
  Future<void> attach(GameEngine game) async {
    _game = game;
    if (!_isInitialized) {
      await SoLoud.instance.init(
        device: device,
        automaticCleanup: automaticCleanup,
        sampleRate: sampleRate,
        bufferSize: bufferSize,
        channels: channels,
      );
      _isInitialized = true;
    }
  }

  /// Registers an active sound [handle] for tracking.
  ///
  /// This ensures that the sound is properly managed and can be stopped
  /// when the system is disposed.
  ///
  /// * [handle]: The handle to track.
  void registerHandle(SoundHandle handle) {
    _handles.add(handle);
  }

  /// Unregisters a sound [handle] from tracking.
  ///
  /// This is typically called when a sound has finished playing and no
  /// longer needs to be managed by the system.
  ///
  /// * [handle]: The handle to stop tracking.
  void unregisterHandle(SoundHandle handle) {
    _handles.remove(handle);
  }

  double _globalVolume = 1.0;

  /// The master volume level for all audio playback.
  ///
  /// This value is clamped between 0.0 (silent) and 1.0 (full volume) and
  /// affects all voices managed by the underlying SoLoud engine.
  double get globalVolume => _globalVolume;

  /// Sets the global volume level.
  ///
  /// * [value]: The new volume level (0.0 to 1.0).
  set globalVolume(double value) {
    _globalVolume = value.clamp(0.0, 1.0);
    if (_isInitialized) {
      SoLoud.instance.setGlobalVolume(_globalVolume);
    }
  }

  @override
  Future<void> dispose() async {
    for (final ch in _musicChannels.values) {
      ch.currentTransition?.stop();
    }
    _musicChannels.clear();
    if (_isInitialized) {
      for (final handle in _handles) {
        if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
          SoLoud.instance.stop(handle);
        }
      }
      SoLoud.instance.deinit();
      _isInitialized = false;
    }
    _handles.clear();
    _game = null;
  }
}

/// An [InheritedWidget] that provides a [GameEngine] to the widget tree.
///
/// This is used internally by the [Game] widget and can be used by developers
/// to access the engine instance from any descendant widget using
/// `GameEngine.of(context)`.
///
/// ```dart
/// class MyWidget extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     final engine = GameEngine.of(context);
///     return Text('Frame: ${engine.ticker.frameCount}');
///   }
/// }
/// ```
///
/// See also:
/// * [Game], the root widget that initializes the engine.
/// * [GameEngine], the central coordinator provided by this widget.
class GameProvider extends InheritedWidget {
  /// The [GameEngine] instance being provided.
  ///
  /// All child widgets can access this instance to interact with systems
  /// like input, audio, or physics.
  final GameEngine game;

  /// Creates a provider for the specified [game] engine.
  ///
  /// * [key]: The widget key.
  /// * [game]: The engine instance to provide.
  /// * [child]: The descendant widget tree.
  const GameProvider({super.key, required this.game, required super.child});

  /// Retrieves the [GameEngine] from the nearest [GameProvider] ancestor.
  ///
  /// * [context]: The build context used to locate the provider.
  static GameEngine of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<GameProvider>();
    if (provider == null) {
      throw StateError('GameProvider not found in context');
    }
    return provider.game;
  }

  @override
  bool updateShouldNotify(GameProvider oldWidget) => game != oldWidget.game;
}

/// The root widget of a Goo2D application.
///
/// Requires a fully-initialized [GameEngine] created via [GameEngine.create].
/// The engine's lifetime is owned by the caller — the widget does not dispose it.
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   final engine = await GameEngine.create();
///   runApp(Game(engine: engine, child: MyWorld()));
/// }
/// ```
///
/// See also:
/// * [GameEngine.create], the async factory that initializes all systems.
/// * [GameProvider], for accessing the engine from descendant widgets.
class Game extends StatefulWidget {
  final Widget child;

  /// A fully-initialized engine created via [GameEngine.create].
  final GameEngine engine;

  const Game({super.key, required this.engine, required this.child});

  @override
  State<Game> createState() => _GameState();
}

class _GameState extends State<Game> {
  GameEngine get _game => widget.engine;

  @override
  void reassemble() {
    super.reassemble();
    _game.ticker.signalFrameComplete();
  }

  @override
  Widget build(BuildContext context) {
    return FpsCounter(
      child: GameProvider(
        game: _game,
        child: GameLoop(
          game: _game,
          child: GameRenderer(
            child: WorldSpace(child: widget.child),
          ),
        ),
      ),
    );
  }
}
