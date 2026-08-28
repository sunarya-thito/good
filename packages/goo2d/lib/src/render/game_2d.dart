// `Size` clashes with dart:ui's - only the pointer types are wanted here.
import 'dart:ffi' hide Size;
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
// `Texture` is a Flutter widget as well as goo2d's payload type, and this
// file names the payload one.
import 'package:flutter/widgets.dart' hide Texture;
import 'package:good/good.dart';

import 'package:goo2d/src/data/world_transform.dart';
import 'package:goo2d/src/render/draw/draw_2d.dart';
import 'package:goo2d/src/render/render_2d.dart';
import 'package:goo2d/src/render/texture.dart';

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
/// That is the whole opt-in - [Renderer2DState.describeSystems] brings
/// `WorldTransformSystem` and `GameRenderer2D` with it, so there is no
/// second thing to remember and no way to end up with a `Game2D` that
/// silently paints nothing.
///
/// # Why a superclass and not a declared system
///
/// A system is wholly a game-isolate thing, and the one object that lives
/// where Flutter does is `Game`, so the renderer's main-isolate half belongs
/// *on `Game`*. Nothing here straddles the two isolates, which is what keeps
/// "which isolate does this run on" from being a question you have to keep
/// answering.
///
/// The split that remains is the real one: [GameRenderer2D] runs on the game
/// isolate and fills a draw buffer; this drains that buffer and paints it.
/// Two halves, one declaration.
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
  /// here is a **compile error**, not a game that silently paints nothing.
  /// That black screen is the exact trap this narrowing exists to prevent.
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
    descriptor.has(WorldTransformSystem.new);
    descriptor.has(createRenderer);
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
  /// Declared for the same reason [Renderer2DState.describeSystems] declares
  /// the renderer: `extends Game2D` is meant to be the whole opt-in, and a
  /// game that had to remember a second declaration before anything appeared
  /// would hit exactly the black screen that arrangement exists to prevent.
  ///
  /// A game wanting several views declares them itself and calls
  /// `super.describeCameras(descriptor)`, so this one keeps address 0.
  late final CameraView defaultCamera;

  /// Registers the texture decoder, since a 2D renderer is what makes a
  /// texture something worth decoding.
  ///
  /// On the mixin and not on [Game2D], so a game whose base class is already
  /// something else - the case this mixin exists for - gets the decoder from
  /// the same line that gets it the renderer. Putting it one level up would
  /// hand that game a renderer that draws nothing, which is the shape of the
  /// bug this registration was moved out of `DrawCanvas2D`'s constructor to
  /// stop (#123).
  @override
  @mustCallSuper
  void describeAssetLoaders(AssetLoaderRegistrar loaders) {
    super.describeAssetLoaders(loaders);
    loaders.register<Texture>(const TextureLoader());
  }

  @override
  @mustCallSuper
  void describeCameras(CameraDescriptor descriptor) {
    super.describeCameras(descriptor);
    defaultCamera = descriptor.has();
  }

  /// Draw records past this many in a single tick are dropped. A hard bound,
  /// not a growing buffer: the byte scratch and the handoff slots are both
  /// sized from it, and silently growing them mid-tick is an allocation on the
  /// hot path. Override it if a scene genuinely draws more.
  ///
  /// It counts **records**, not entities and not sprites. An entity declaring
  /// three sprites spends three of them, and a nine-sliced sprite spends one
  /// per cell it draws - nine for a full frame, three for something sliced on
  /// one axis only. `GameRenderer2D.lastRecordCount` is what a frame spent and
  /// `lastRecordsOverBudget` is what it could not fit, so raising this by the
  /// second is the direct fix for a scene that is dropping sprites.
  ///
  /// The name says sprites and the number counts records; renaming it is
  /// breaking and is #175's to make.
  ///
  /// It lives here, on the `Game`, and not on [GameRenderer2D], because it is
  /// a **sizing** knob and sizing happens on this side: [describeBuffers]
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
  /// Declared here instead of on `CameraView` itself so the kernel never
  /// learns what a frame is: `good` declares that a view exists, and whatever
  /// draws it sizes its own storage. A future `goo3d` allocates something
  /// else entirely against the same views.
  late final List<HandoffHandle> _viewFrames;

  /// The frame buffer [view] is drawn into. `GameRenderer2D` writes it on the
  /// game isolate; `_ViewSurface` reads it here.
  HandoffHandle framesFor(CameraView view) => _viewFrames[view.pack()];

  @override
  @mustCallSuper
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
  /// Lazy, not one per declared view: a game may declare a minimap it only
  /// shows on some screens, and an unshown view should cost no canvas, no
  /// vertex arrays and no ingest.
  ///
  /// Plain fields, because an instance backs one run. `Game.onStopped` is the
  /// hook that keeps a stopped game from leaving frames and a scheduler
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
  /// `notifyListeners` only marks the painter dirty; the actual paint waits
  /// for the next vsync. Hung off `Game.addTickListener`, a repaint would be
  /// scheduled whenever the game isolate's message happened to land, so a
  /// message arriving just after Flutter began a frame would wait most of a
  /// frame interval - and the renderer would have no say in it, because it
  /// would not get to choose when it was told.
  ///
  /// Sampling here instead reads the freshest frame at exactly the moment
  /// Flutter can use it. There is no queue to fall behind in: each view's
  /// handoff buffer holds that view's newest complete frame, so "we missed
  /// one" simply means the missed one was replaced.
  ///
  /// One callback for all views, not one each: they are all sampled at
  /// the same instant of the same Flutter frame, so two views of one scene
  /// cannot show it at two different ages.
  void _onFrame() {
    if (!_listening) return;
    // Re-armed first, so the loop survives anything below returning early. A
    // transient callback is one-shot, and scheduling one also requests the
    // next frame - which is what a game wants: it renders continuously and
    // does not wait for something else to dirty the tree.
    //
    // Transient, not persistent, and that is the whole reason for the choice:
    // transient callbacks run in `handleBeginFrame`, *before* build and paint.
    // A persistent one runs after `WidgetsBinding`'s own drawFrame, so the
    // pulse below would mark the painter dirty too late and land a frame
    // behind - reintroducing exactly the lag this choice exists to remove.
    _callbackId = SchedulerBinding.instance.scheduleFrameCallback(
      (_) => _onFrame(),
    );
    // No `getSystem<GameRenderer2D>()` here, and that is the point of the
    // buffers living on this object: systems live on the game isolate, so
    // asking this copy for one would find nothing. What main needs is the
    // storage, and the storage is declared here.
    for (final surface in _surfaces.values) {
      surface.sample(this);
    }
  }

  /// The `CustomPaint` showing [camera], or null when there is nothing to
  /// show yet.
  ///
  /// Null for a null [camera]: a `Game2D` handed to `GameView.headless` has
  /// no view to draw into, and contributing nothing is the honest answer, not
  /// picking a view on the caller's behalf.
  ///
  /// It does **not** ask whether a scene is loaded, and it cannot: the scenes
  /// live on the game isolate, and this copy's `GameState` is a declaration
  /// mirror that never loads one, so such a test would be true forever in the
  /// spawned configuration and the game would simply never paint.
  ///
  /// Nothing is lost by that. A surface with no frame ingested replays
  /// nothing, so a game between scenes draws an empty canvas and never a stale
  /// one. An app that wants a loading screen shows it by not building the
  /// `GameView` yet, or by stacking it in front - both of which are decisions
  /// main can actually make, off a `StateChannel` the game publishes.
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
  /// The two ends of the teardown are different: [onViewDetached]
  /// fires when nothing is *looking* at a game that is still running, and this
  /// fires when the game itself is going away. Only the second can throw the
  /// frames out, and only the second is guaranteed to happen - a game stopped
  /// while its view is still mounted never sees a detach.
  ///
  /// Before the shared buffers are unmapped, which is what makes cancelling
  /// the callback here, and not after `stop()`, load-bearing: a sampling
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
/// camera at two sizes" cost one ingest and not two.
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
    // and not read during paint. That is what keeps the window in which
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
/// Not a `ValueNotifier<int>` or a `Stream`: the payload is
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
