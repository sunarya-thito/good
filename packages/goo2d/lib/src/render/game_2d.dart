// `Size` clashes with dart:ui's - only the pointer types are wanted here.
import 'dart:ffi' hide Size;
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:good/good.dart';

import 'package:goo2d/src/data/world_transform.dart';
import 'package:goo2d/src/render/draw/draw_2d.dart';
import 'package:goo2d/src/render/render_2d.dart';

/// A [Game] that draws in 2D. Extend this instead of `Game` and a `GameView`
/// shows pixels.
///
/// ```dart
/// class MyGame extends Game2D {
///   @override
///   GameState createState() => MyGameState();
/// }
/// ```
///
/// That is the whole opt-in - [Renderer2D.describeSystems] brings
/// `WorldTransformSystem` and `GameRenderer2D` with it, so there is no
/// second thing to remember and no way to end up with a `Game2D` that
/// silently paints nothing.
///
/// # Why a superclass and not a declared system
///
/// This used to be `RenderSystem2D`, a `GameSystem` that listened for a
/// `BuildWidgetEvent` and wrapped the tree. That only worked because
/// `GameSystem` straddled both isolates - it had a game-isolate twin that
/// ticked and a main-isolate twin that built widgets - and straddling is
/// exactly what made "which isolate does this run on" a question you had to
/// keep answering. A system is now wholly a game-isolate thing, and the one
/// object that lives where Flutter does is `Game`, so the renderer's
/// main-isolate half belongs *on `Game`*.
///
/// The split that remains is the real one, and it is unchanged:
/// [GameRenderer2D] runs on the game isolate and fills a draw buffer;
/// this drains that buffer and paints it. Two halves, one declaration.
///
/// A future `goo3d` supplies its own `Game3D` overriding the same
/// [buildView], and `GameView` never learns that either exists.
abstract class Game2D extends Game with Renderer2D {
  /// Narrowed to [GameState2D], and that narrowing is the whole opt-in.
  ///
  /// 2D rendering is two halves on two isolates: this object declares and
  /// drains the frame buffers, and [GameRenderer2D] fills them from the game
  /// isolate. A system can only be declared where systems live, so the second
  /// half has to be named by the state - and returning a plain `GameState`
  /// here is a **compile error** rather than a game that silently paints
  /// nothing. That black screen is the exact trap this narrowing replaced:
  /// `Renderer2D` used to declare the systems itself, back when
  /// `describeSystems` was a `Game` pass.
  @override
  GameState2D createState();
}

/// The simulation half of [Game2D] - declares the two systems 2D rendering
/// cannot work without.
///
/// ```dart
/// class MyGame extends Game2D {
///   @override
///   MyState createState() => MyState();
/// }
///
/// class MyState extends GameState2D<MyGame> {
///   @override
///   void onMounted() => loadScene(Level());
/// }
/// ```
///
/// A game with its own state hierarchy mixes in [Renderer2DState] instead;
/// this class is that mixin applied to the plain base, which is what almost
/// every game wants.
abstract class GameState2D<G extends Game2D> extends GameState<G>
    with Renderer2DState<G> {}

/// Declares [WorldTransformSystem] and the renderer, for a state whose base
/// class is already something else.
mixin Renderer2DState<G extends Game2D> on GameState<G> {
  /// A game that declares its own systems overrides this and calls
  /// `super.describeSystems(descriptor)`.
  @override
  @mustCallSuper
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(WorldTransformSystem());
    descriptor.has(createRenderer());
  }

  /// The renderer to declare. Override to return a `GameRenderer2D` subclass
  /// without having to take over [describeSystems] to do it.
  ///
  /// Note the *budget* is not here: `maxSpritesPerTick` sizes native memory,
  /// so it lives on [Renderer2D], on the copy that allocates it.
  GameRenderer2D createRenderer() => GameRenderer2D();
}

/// The painting half of [Game2D], as a mixin, for a game whose base class is
/// already something else.
///
/// # Push-driven repaint
///
/// Repaint goes through the `CustomPainter`'s `repaint` `Listenable`, not
/// `setState`: when a frame lands nothing about the widget *tree* changes,
/// only the pixels. `shouldRepaint` is therefore always false - the
/// `Listenable` is the only thing that ever schedules a paint. `paint`
/// itself does nothing but [DrawCanvas2D.replay]: no query, no hierarchy
/// walk, no allocation. All of that already happened on the game isolate.
mixin Renderer2D on Game {
  /// The view a 2D game draws into when it declares none of its own -
  /// `GameView(camera: game.defaultCamera)` is the zero-configuration path.
  ///
  /// Declared for the same reason [describeSystems] declares the renderer:
  /// `extends Game2D` is meant to be the whole opt-in, and a game that had to
  /// remember a second declaration before anything appeared would hit exactly
  /// the black screen that arrangement exists to prevent.
  ///
  /// A game wanting several views declares them itself and calls
  /// `super.describeCameras(descriptor)`, so this one keeps address 0.
  late final CameraView defaultCamera;

  @override
  void describeCameras(CameraDescriptor descriptor) {
    super.describeCameras(descriptor);
    defaultCamera = descriptor.has();
  }

  /// Sprites past this many in a single tick are dropped. A hard bound rather
  /// than a growing buffer on purpose: the byte scratch and the handoff slots
  /// are both sized from it, and silently growing them mid-tick is an
  /// allocation on the hot path. Override it if a scene genuinely draws more.
  ///
  /// Note this counts *sprites*, not entities - an entity declaring three
  /// sprites spends three of them.
  ///
  /// It lives here, on the `Game`, rather than on [GameRenderer2D], because it
  /// is a **sizing** knob and sizing happens on this side: [describeBuffers]
  /// runs on main before the spawn and reserves the memory. Raising it is
  /// therefore an override on your `Game2D` subclass, not a reason to subclass
  /// the renderer.
  int get maxSpritesPerTick => 4096;

  /// Bytes one tick's sprite batch occupies, including its tick stamp.
  int get spriteBatchBytes =>
      DrawData2D.batchHeaderBytes +
      maxSpritesPerTick * DrawSpriteData2D.strideBytes;

  /// One handoff buffer per declared [CameraView], indexed by its address.
  ///
  /// Declared on the `Game` and not on the system that fills it, because
  /// **allocation is a main-isolate act**: the memory is `calloc`'d in
  /// `Game._bootMain` before `Isolate.spawn` and freed by this copy on stop,
  /// while the system that writes into it exists only on the game isolate. It
  /// is also this object that drains it every frame ([_onFrame]), so the
  /// handle is held by its reader.
  ///
  /// Declared here rather than on `CameraView` itself so the kernel never
  /// learns what a frame is: `good` declares that a view exists, and whatever
  /// draws it sizes its own storage. A future `goo3d` allocates something
  /// else entirely against the same views.
  late final List<HandoffHandle> _viewFrames;

  /// The frame buffer [view] is drawn into. `GameRenderer2D` writes it on the
  /// game isolate; `_ViewSurface` reads it here.
  HandoffHandle framesFor(CameraView view) => _viewFrames[view.pack()];

  @override
  void describeBuffers(BufferDescriptor descriptor) {
    super.describeBuffers(descriptor);
    // `describeCameras` runs before `describeBuffers` in `Game._bootMain`, so
    // the views are known by the time this asks how many buffers it needs.
    _viewFrames = <HandoffHandle>[
      for (var i = 0; i < cameraViews.length; i++)
        descriptor.hasHandoff(slotBytes: spriteBatchBytes),
    ];
  }

  /// One surface per [CameraView] something is showing, keyed by address.
  ///
  /// Lazy rather than one per declared view: a game may declare a minimap it
  /// only shows on some screens, and an unshown view should cost no canvas, no
  /// vertex arrays and no ingest.
  ///
  /// Plain fields, because an instance backs one run. They spent a while filed
  /// on the run through a keyed attachment map, back when a `Game` could have
  /// backed several at once; `Game.onStopped` is what replaced that, and it is
  /// the hook that keeps a stopped game from leaving frames and a scheduler
  /// callback behind.
  final Map<int, _ViewSurface> _surfaces = <int, _ViewSurface>{};

  /// Whether the frame callback should keep rescheduling itself. False once
  /// the last view is gone or the game has stopped, so a torn-down game stops
  /// touching storage that has been freed.
  bool _listening = false;

  /// The pending transient frame callback, so it can be cancelled. A
  /// self-rescheduling callback left armed keeps the scheduler awake, and a
  /// widget test fails outright on "an animation is still running".
  int? _callbackId;

  void _disarm() {
    _listening = false;
    final pending = _callbackId;
    if (pending == null) return;
    SchedulerBinding.instance.cancelFrameCallbackWithId(pending);
    _callbackId = null;
  }

  /// Samples the newest published frame **for every view being shown** and
  /// pulses that view's repaint signal - once per Flutter frame, on the main
  /// isolate.
  ///
  /// # Why a frame callback and not the tick ping
  ///
  /// This used to hang off `Game.addTickListener`, so a repaint was scheduled
  /// whenever the game isolate's message happened to land. `notifyListeners`
  /// only marks the painter dirty, though - the actual paint waits for the
  /// next vsync. A message arriving just after Flutter began a frame therefore
  /// waited most of a frame interval, and there was nothing the renderer could
  /// do about it, because it did not get to choose when it was told.
  ///
  /// Sampling here instead reads the freshest frame at exactly the moment
  /// Flutter can use it. There is no queue to fall behind in: each view's
  /// handoff buffer holds that view's newest complete frame, so "we missed
  /// one" simply means the missed one was replaced.
  ///
  /// One callback for all views rather than one each: they are all sampled at
  /// the same instant of the same Flutter frame, so two views of one scene
  /// cannot show it at two different ages.
  void _onFrame() {
    if (!_listening) return;
    // Re-armed first, so the loop survives anything below returning early. A
    // transient callback is one-shot, and scheduling one also requests the
    // next frame - which is what a game wants: it renders continuously rather
    // than waiting for something else to dirty the tree.
    //
    // Transient, not persistent, and that is the whole reason for the choice:
    // transient callbacks run in `handleBeginFrame`, *before* build and paint.
    // A persistent one runs after `WidgetsBinding`'s own drawFrame, so the
    // pulse below would mark the painter dirty too late and land a frame
    // behind - reintroducing exactly the lag this move exists to remove.
    _callbackId = SchedulerBinding.instance.scheduleFrameCallback(
      (_) => _onFrame(),
    );
    // No `getSystem<GameRenderer2D>()` here any more, and that is the point of
    // moving the buffers onto this object: systems live on the game isolate,
    // so asking this copy for one would find nothing. What main needs is the
    // storage, and the storage is declared here.
    for (final surface in _surfaces.values) {
      surface.sample(this);
    }
  }

  /// The `CustomPaint` showing [camera], or null when there is nothing to
  /// show yet.
  ///
  /// Null for a null [camera]: a `Game2D` handed to `GameView.headless` has
  /// no view to draw into, and contributing nothing is the honest answer
  /// rather than picking a view on the caller's behalf.
  ///
  /// It does **not** ask whether a scene is loaded, and that is a correction
  /// rather than a relaxation. It used to return null while `state?.scene` was
  /// null, so that an app with a loading screen behind the view saw it instead
  /// of an empty canvas. That test cannot be asked from here any more: the
  /// scenes live on the game isolate, and this copy's `GameState` is a
  /// declaration mirror that never loads one - so the condition was true
  /// forever in the spawned configuration and the game would simply never
  /// paint.
  ///
  /// Nothing is lost by dropping it. A surface with no frame ingested replays
  /// nothing, so a game between scenes still draws an empty canvas rather than
  /// a stale one. An app that wants a loading screen shows it by not building
  /// the `GameView` yet, or by stacking it in front - both of which are
  /// decisions main can actually make, off a `StateChannel` the game publishes.
  @override
  Widget? buildView(BuildContext context, CameraView? camera) {
    if (camera == null) return null;

    final surface = _surfaces.putIfAbsent(
      camera.pack(),
      () => _ViewSurface(camera, DrawCanvas2D(assets: assets)),
    );

    // `ClipRect`, because a `CustomPaint` does **not** clip its painter to its
    // own box. The batch is in world space around the camera, so anything the
    // camera does not frame is still handed to the canvas - and without this it
    // paints straight over whatever the app put beside the view. A view showing
    // what its camera sees, and only inside its own bounds, is the only
    // defensible default; a game that wants to spill past its box can stack
    // something in front of it, which is a decision main can actually make.
    return RepaintBoundary(
      child: ClipRect(
        child: CustomPaint(
          painter: _GameViewPainter(surface.canvas, surface.frames),
          size: Size.infinite,
          isComplex: true,
          willChange: true,
        ),
      ),
    );
  }

  /// Starts sampling frames, now that something is on screen to show them.
  @override
  void onViewAttached() {
    super.onViewAttached();
    if (_listening) return;
    _listening = true;
    _callbackId = SchedulerBinding.instance.scheduleFrameCallback(
      (_) => _onFrame(),
    );
  }

  /// Stops sampling: nothing is showing this game any more.
  ///
  /// Only disarms - the decoded frames stay, because the view can come back
  /// (a route pushed over the game, a tab switched away and back) and
  /// re-decoding every surface for that is waste. [onStopped] is what actually
  /// releases them.
  @override
  void onViewDetached() {
    super.onViewDetached();
    _disarm();
  }

  /// Disarms the frame callback and releases every decoded frame.
  ///
  /// The two ends of the teardown are deliberately different: [onViewDetached]
  /// fires when nothing is *looking* at a game that is still running, and this
  /// fires when the game itself is going away. Only the second can throw the
  /// frames out, and only the second is guaranteed to happen - a game stopped
  /// while its view is still mounted never sees a detach.
  ///
  /// Before the shared buffers are unmapped, which is what makes cancelling
  /// the callback here rather than after `stop()` load-bearing: a sampling
  /// callback that outlived the draw buffers would read freed memory.
  @override
  void onStopped() {
    super.onStopped();
    _disarm();
    for (final surface in _surfaces.values) {
      surface.dispose();
    }
    _surfaces.clear();
  }
}

/// Everything the main isolate needs to show one [CameraView]: where its
/// frames arrive, the vertex arrays they are decoded into, and the signal
/// that says a new one landed.
///
/// One per *shown* view. Two `GameView`s on the same view share this one, so
/// they decode once and paint the same frame - which is what makes "the same
/// camera at two sizes" cost one ingest rather than two.
class _ViewSurface {
  _ViewSurface(this.view, this.canvas);

  final CameraView view;
  final DrawCanvas2D canvas;
  final _FrameSignal frames = _FrameSignal();

  HandoffBuffer? _buffer;

  void sample(Renderer2D renderer) {
    final buffer = _buffer ??= renderer.framesFor(view).tryBuffer;
    if (buffer == null) return;

    // Null means nothing new since the last look, which at 60Hz against a
    // slower tick is the ordinary case. Taking a slot is also what hands the
    // previous one back, so the writer only ever resumes because this ran.
    final slot = buffer.beginRead();
    if (slot == null) return;

    // Decoded into the canvas's own vertex arrays here, in the frame callback,
    // rather than read during paint. That is what keeps the window in which
    // the writer could interfere down to this ingest instead of a whole
    // raster - see `HandoffBuffer`.
    if (!canvas.ingestFrame(
      ByteData.sublistView(slot.asTypedList(buffer.readUsedBytes)),
      buffer.readUsedBytes,
    )) {
      return;
    }
    frames.pulse();
  }

  void dispose() {
    _buffer = null;
    canvas.dispose();
    frames.dispose();
  }
}

/// A `Listenable` whose only job is to say "a new frame landed".
///
/// Deliberately not a `ValueNotifier<int>` or a `Stream`: the payload is
/// nothing at all, and this fires at tick rate.
class _FrameSignal extends ChangeNotifier {
  void pulse() => notifyListeners();
}

class _GameViewPainter extends CustomPainter {
  const _GameViewPainter(this.canvas, Listenable repaint)
    : super(repaint: repaint);

  final DrawCanvas2D canvas;

  @override
  void paint(Canvas target, Size size) => canvas.replay(target);

  /// Always false: repaints come from the `repaint` `Listenable` handed to
  /// the constructor, and the painter's own identity says nothing about
  /// whether the frame moved.
  @override
  bool shouldRepaint(_GameViewPainter oldDelegate) => false;
}
