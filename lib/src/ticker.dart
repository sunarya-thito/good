import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:goo2d/src/game.dart';
import 'package:goo2d/src/event.dart';
import 'package:goo2d/src/camera.dart';

/// A mixin for components that need to be updated every frame.
///
/// [Tickable] is the most common way to implement dynamic behavior in game
/// objects. Components that implement this mixin are automatically
/// registered with the engine's update loop and receive an [onUpdate]
/// call once per frame with the elapsed time delta.
///
/// ```dart
/// class Rotator extends Component with Tickable {
///   @override
///   void onUpdate(double dt) {
///     gameObject.transform.rotation += dt;
///   }
/// }
/// ```
///
/// See also:
/// * [FixedTickable] for physics-safe, constant interval updates.
/// * [LateTickable] for updates that occur after the main tick.
mixin Tickable implements EventListener {
  /// Called every frame with the elapsed time [dt] in seconds.
  ///
  /// Use this method for frame-dependent logic such as moving characters,
  /// updating animations, or processing input. The delta time [dt]
  /// ensures that movement remains consistent regardless of the frame rate.
  ///
  /// * [dt]: The time elapsed since the last frame in seconds.
  void onUpdate(double dt);
}

/// An event that dispatches a frame update to [Tickable] listeners.
///
/// This event is used internally by the [GameEngine] to propagate the
/// frame delta to all registered components. It encapsulates the
/// [dt] value and ensures it is delivered consistently across the hierarchy.
///
/// ```dart
/// void example(double dt, GameObject object) {
///   final event = TickEvent(dt);
///   event.dispatchTo(object);
/// }
/// ```
///
/// See also:
/// * [Tickable] for the interface that receives this event.
class TickEvent extends Event<Tickable> {
  /// The time elapsed since the last frame in seconds.
  ///
  /// This value represents the fractional seconds that have passed since
  /// the previous frame. It should be used to multiply movement or
  /// animation speeds to ensure frame-rate independence.
  final double dt;

  /// Creates a [TickEvent] with the specified [dt].
  ///
  /// This constructor is used by the engine during the main update pass.
  /// It captures the precise timing provided by the Flutter ticker.
  ///
  /// * [dt]: The time delta in seconds.
  const TickEvent(this.dt);

  @override
  void dispatch(Tickable listener) {
    listener.onUpdate(dt);
  }
}

/// A mixin for components that need constant interval updates.
///
/// [FixedTickable] is primarily used for physics calculations and other
/// simulation logic that requires a stable time step. Unlike [Tickable],
/// which varies with the frame rate, fixed updates occur at a consistent
/// frequency (e.g., 60Hz) regardless of rendering performance.
///
/// ```dart
/// class PhysicsBody extends Component with FixedTickable {
///   @override
///   void onFixedUpdate(double dt) {
///     // Perform deterministic physics step
///   }
/// }
/// ```
///
/// See also:
/// * [Tickable] for standard frame-rate dependent updates.
/// * [FixedTickEvent] for the event that triggers this mixin.
mixin FixedTickable implements EventListener {
  /// Called at a constant interval with the specified [dt].
  ///
  /// Use this method for logic that must be deterministic or stable,
  /// such as resolving collisions or calculating planetary orbits. The
  /// engine may call this multiple times per frame if the rendering
  /// lags behind the simulation.
  ///
  /// * [dt]: The constant time interval in seconds.
  FutureOr<void> onFixedUpdate(double dt);
}

/// An event that dispatches a fixed interval update to [FixedTickable] listeners.
///
/// This event is triggered by the engine's physics or simulation sub-system.
/// It ensures that all components requiring deterministic updates receive
/// the same [dt] value during the simulation phase.
///
/// ```dart
/// void example(double dt, GameObject object) {
///   final event = FixedTickEvent(dt);
///   event.dispatchTo(object);
/// }
/// ```
///
/// See also:
/// * [FixedTickable] for the interface that receives this event.
class FixedTickEvent extends AsyncEvent<FixedTickable> {
  /// The constant time interval for this simulation step.
  ///
  /// This value is typically fixed (e.g., 1/60) to ensure that physics
  /// simulations remain stable and reproducible across different hardware
  /// configurations.
  final double dt;

  /// Creates a [FixedTickEvent] with the specified [dt].
  ///
  /// This constructor is utilized by the simulation sub-system to
  /// synchronize component state with the fixed-step timer.
  ///
  /// * [dt]: The simulation time step in seconds.
  const FixedTickEvent(this.dt);

  @override
  FutureOr<void> dispatch(FixedTickable listener) {
    return listener.onFixedUpdate(dt);
  }
}

/// A mixin for components that need to update after the main frame tick.
///
/// [LateTickable] is useful for logic that depends on the final positions
/// or states of other objects after all [Tickable] components have finished
/// their work. This is commonly used for camera following logic to avoid
/// "jitter" caused by the camera updating before its target.
///
/// ```dart
/// class CameraFollower extends Component with LateTickable {
///   @override
///   void onLateUpdate(double dt) {
///     // Move camera to follow target's final position
///   }
/// }
/// ```
///
/// See also:
/// * [Tickable] for the primary update phase.
/// * [LateTickEvent] for the event that triggers this mixin.
mixin LateTickable implements EventListener {
  /// Called after all [Tickable.onUpdate] calls have completed.
  ///
  /// Use this method for secondary logic that requires the results of the
  /// primary update pass. It receives the same [dt] as the regular tick.
  ///
  /// * [dt]: The time elapsed since the last frame in seconds.
  void onLateUpdate(double dt);
}

/// An event that dispatches a late update to [LateTickable] listeners.
///
/// This event marks the final phase of the engine's update cycle before
/// rendering begins. It ensures that components like cameras or UI
/// overlays can sync with the most recent world state.
///
/// ```dart
/// void example(double dt, GameObject object) {
///   final event = LateTickEvent(dt);
///   event.dispatchTo(object);
/// }
/// ```
///
/// See also:
/// * [LateTickable] for the interface that receives this event.
class LateTickEvent extends Event<LateTickable> {
  /// The time elapsed since the last frame in seconds.
  ///
  /// This value matches the [dt] provided to the main [TickEvent] for
  /// the current frame, maintaining synchronization across all
  /// frame-based updates.
  final double dt;

  /// Creates a [LateTickEvent] with the specified [dt].
  ///
  /// This constructor is called by the engine immediately after the
  /// primary update pass has concluded for all active game objects.
  ///
  /// * [dt]: The time delta in seconds.
  const LateTickEvent(this.dt);

  @override
  void dispatch(LateTickable listener) {
    listener.onLateUpdate(dt);
  }
}

/// A widget that bridges Flutter's frame pipeline with the Goo2D engine.
///
/// [GameLoop] is an internal component that hosts the [RenderGameLoop]
/// render object. It is responsible for initiating the engine's update
/// cycle whenever Flutter schedules a new frame, ensuring that the game
/// world remains synchronized with the display.
///
/// ```dart
/// void example(GameEngine game) {
///   final loop = GameLoop(
///     game: game,
///     child: const SizedBox(),
///   );
/// }
/// ```
///
/// See also:
/// * [RenderGameLoop] for the underlying render object implementation.
class GameLoop extends SingleChildRenderObjectWidget {
  /// The engine instance to be updated by this loop.
  ///
  /// This instance is passed down to the [RenderGameLoop] where the
  /// actual ticker logic resides. Updating this field will trigger
  /// a reconfiguration of the underlying render object.
  final GameEngine game;

  /// Creates a [GameLoop] for the specified [game].
  ///
  /// This widget should be placed at the root of the game widget tree
  /// to ensure it correctly captures the frame ticker and propagates
  /// updates down to all game objects.
  ///
  /// * [key]: Standard Flutter widget key.
  /// * [game]: The engine to drive.
  /// * [child]: The next widget in the tree.
  const GameLoop({super.key, required this.game, required super.child});

  @override
  RenderGameLoop createRenderObject(BuildContext context) {
    return RenderGameLoop(game: game);
  }

  @override
  void updateRenderObject(BuildContext context, RenderGameLoop renderObject) {
    renderObject.game = game;
  }
}

/// The render object responsible for driving the engine's frame ticker.
///
/// [RenderGameLoop] utilizes a Flutter [Ticker] to execute the engine's
/// update phases. It also monitors the layout size of the widget and
/// synchronizes it with the [GameEngine.screen] state.
///
/// ```dart
/// void example(GameEngine game) {
///   final renderObject = RenderGameLoop(game: game);
///   // This is normally managed by GameLoop widget.
/// }
/// ```
///
/// See also:
/// * [GameLoop] for the widget that manages this render object.
class RenderGameLoop extends RenderProxyBox {
  /// The engine instance managed by this renderer.
  ///
  /// This field provides access to the engine's systems, allowing the
  /// loop to dispatch ticks to the global [TickerSystem].
  GameEngine game;

  /// Ticker used to drive the frame updates.
  Ticker? _ticker;

  Timer? _timer;

  /// The timestamp of the last processed frame.
  Duration _lastTick = Duration.zero;

  /// Whether to skip the next delta calculation (used during reassembly).
  bool _skipNextDelta = false;

  /// Creates a [RenderGameLoop] for the specified [game].
  ///
  /// * [game]: The engine to synchronize with the ticker.
  RenderGameLoop({required this.game});

  @override
  void performLayout() {
    super.performLayout();
    game.screen.screenSize = size;
  }

  @override
  void reassemble() {
    super.reassemble();
    _skipNextDelta = true;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _ticker = Ticker(_onTick);
    _ticker!.start();
    _timer = Timer.periodic(const Duration(milliseconds: 20), _onTickFixed);
  }

  @override
  void detach() {
    _ticker?.dispose();
    _ticker = null;
    _timer?.cancel();
    _timer = null;
    super.detach();
  }

  bool _fixedTickRunning = false;

  Future<void> _onTickFixed(Timer timer) async {
    if (_fixedTickRunning) return;
    _fixedTickRunning = true;
    try {
      await game.getSystem<TickerSystem>()?.fixedTick();
    } finally {
      _fixedTickRunning = false;
    }
  }

  void _onTick(Duration elapsed) {
    if (_skipNextDelta) {
      _lastTick = elapsed;
      _skipNextDelta = false;
      return;
    }

    final delta = elapsed - _lastTick;
    final dt = delta.inMicroseconds / 1000000.0;
    _lastTick = elapsed;

    if (hasSize) {
      game.screen.screenSize = size;
    }

    game.getSystem<TickerSystem>()?.tick(dt);

    // After updating the game state, we need to ensure the renderer repaints.
    markNeedsPaint();
  }
}

/// A widget that initiates the rendering of the Goo2D world.
///
/// [GameRenderer] hosts the [RenderGameRenderer] render object, which
/// performs the actual drawing calls for the game world. It leverages
/// the [GameProvider] to access the current engine instance and
/// dispatches the render event to the main camera.
///
/// ```dart
/// const renderer = GameRenderer(
///   child: SizedBox(),
/// );
/// ```
///
/// See also:
/// * [RenderGameRenderer] for the drawing implementation.
class GameRenderer extends SingleChildRenderObjectWidget {
  /// Creates a [GameRenderer] to draw the current game world.
  ///
  /// This widget is typically placed inside a [GameLoop] to ensure
  /// that rendering occurs after the state has been updated for the
  /// current frame.
  ///
  /// * [key]: Standard Flutter widget key.
  /// * [child]: The next widget in the tree.
  const GameRenderer({super.key, required super.child});

  @override
  RenderGameRenderer createRenderObject(BuildContext context) {
    return RenderGameRenderer(game: GameProvider.of(context));
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGameRenderer renderObject,
  ) {
    renderObject.game = GameProvider.of(context);
  }
}

/// The render object that performs the low-level canvas drawing.
///
/// [RenderGameRenderer] is responsible for translating the engine's
/// internal state into Flutter canvas operations. It handles camera
/// alignment, background clearing, and initiates the recursive
/// [Renderable] dispatch pass.
///
/// ```dart
/// void example(GameEngine game) {
///   final renderObject = RenderGameRenderer(game: game);
///   // This is normally managed by GameRenderer widget.
/// }
/// ```
///
/// See also:
/// * [GameRenderer] for the widget that manages this render object.
class RenderGameRenderer extends RenderProxyBox {
  /// The engine instance providing the state for rendering.
  ///
  /// This field is updated by the parent [GameRenderer] widget whenever
  /// the inherited [GameProvider] state changes.
  GameEngine game;

  /// Creates a [RenderGameRenderer] for the specified [game].
  ///
  /// * [game]: The engine containing the world to render.
  RenderGameRenderer({required this.game});

  @override
  void performLayout() {
    super.performLayout();
    game.screen.screenSize = size;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (hasSize) {
      game.screen.screenSize = size;
    }

    final screenSize = size;
    if (screenSize.width <= 0 || screenSize.height <= 0) {
      super.paint(context, offset);
      return;
    }

    final cameras = game.getSystem<CameraSystem>();
    if (cameras == null || !cameras.isReady) {
      super.paint(context, offset);
      return;
    }

    final camera = cameras.main;
    if (!camera.gameObject.active || !camera.enabled) {
      super.paint(context, offset);
      return;
    }
    if (!camera.gameObject.active || !camera.enabled) {
      super.paint(context, offset);
      return;
    }

    if (camera.clearFlags == CameraClearFlags.solidColor) {
      final paint = Paint()..color = camera.backgroundColor;
      context.canvas.drawRect(offset & screenSize, paint);
    }

    super.paint(context, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // Default hit testing for children in screen space
    return super.hitTestChildren(result, position: position);
  }
}
