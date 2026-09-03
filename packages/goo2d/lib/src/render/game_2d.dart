// `Size` clashes with dart:ui's - only the pointer types are wanted here.
import 'dart:ffi' hide Size;
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
// `Texture` is a Flutter widget as well as goo2d's payload type, and this
// file names the payload one.
import 'package:flutter/widgets.dart' hide Texture;
import 'package:good/good.dart';

import 'package:goo2d/src/data/world_transform.dart';
import 'package:goo2d/src/render/debug_draw_2d.dart';
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
/// That is the whole opt-in - [Renderer2DState] declares
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
  /// Composes the hierarchy every tick, so a child moves with its parent.
  ///
  /// A game declaring systems of its own declares them on its own fields.
  /// Those run **first** - a subclass's field initialisers run before the
  /// mixins it applies - so these two are last in declaration order, which
  /// puts the renderer behind whatever the game does this tick rather than in
  /// front of it. Nothing here depends on that: [GameRenderer2D] states its
  /// position against [WorldTransformSystem] outright.
  final worldTransformSystem = GameSystem.of(WorldTransformSystem.new);

  /// The renderer, built from [createRenderer] on the state that ends up
  /// holding it.
  ///
  /// [GameSystem.owned] and not [GameSystem.of], because a field initialiser
  /// has no `this` and [createRenderer] is an override point: the state
  /// arrives as an argument and the call dispatches on its runtime type, so a
  /// subclass overriding [createRenderer] still decides which renderer is
  /// declared without having to take the declaration over.
  final renderer = GameSystem.owned(
    (Renderer2DState<G> state) => state.createRenderer(),
  );

  /// The renderer to declare. Override to return a `GameRenderer2D` subclass
  /// without having to take the [renderer] declaration over to do it.
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
  /// Declared for the same reason [Renderer2DState] declares
  /// the renderer: `extends Game2D` is meant to be the whole opt-in, and a
  /// game that had to remember a second declaration before anything appeared
  /// would hit exactly the black screen that arrangement exists to prevent.
  ///
  /// A game wanting several views declares them on its own fields. Those run
  /// before this one - a subclass's initialisers run before the mixins it
  /// applies - so this is the *last* view, not address 0. Nothing indexes the
  /// table by a literal: a frame buffer is looked up by `view.pack()`.
  final defaultCamera = CameraView.of();

  /// Declares the texture decoder, since a 2D renderer is what makes a
  /// texture something worth decoding.
  ///
  /// On the mixin and not on [Game2D], so a game whose base class is already
  /// something else - the case this mixin exists for - gets the decoder from
  /// the same line that gets it the renderer. Putting it one level up would
  /// hand that game a renderer that draws nothing, which is the shape of the
  /// bug this registration was moved out of `DrawCanvas2D`'s constructor to
  /// stop (#123).
  ///
  /// A game wanting a different texture decoder declares one on a field of its
  /// own: those initialise before a mixin's, and the most derived declaration
  /// for a payload type is the one that answers - see [AssetLoader.of].
  final textureLoader = AssetLoader.of(TextureLoader.new);

  /// Draw records past this many in a single tick are dropped. A hard bound
  /// on the batch: the byte scratch and the handoff slots are both sized from
  /// it, and silently growing them mid-tick is an allocation on the hot path -
  /// the handoff slots could not grow at all, since their addresses cross to
  /// the game isolate at spawn. Override it if a scene genuinely draws more.
  ///
  /// It counts **records**, not entities and not sprites. An entity declaring
  /// three sprites spends three of them, and a nine-sliced sprite spends one
  /// per cell it draws - nine for a full frame, three for something sliced on
  /// one axis only. `GameRenderer2D.lastRecordCount` is what a frame spent and
  /// `lastRecordsOverBudget` is what it could not fit, so raising this by the
  /// second is the direct fix for a scene that is dropping sprites.
  ///
  /// **What a frame over this loses is its furthest layers.** The renderer
  /// sorts by depth and then spends the budget from the camera forward, so
  /// everything in front of some depth is drawn and nothing behind it is.
  /// Until #175 it was whichever archetype was registered last that vanished.
  ///
  /// The default reserves 3.56 MiB per declared [CameraView]. It is 16384 and
  /// not something smaller because a full-screen layer of 16 px tiles is 8228
  /// records on its own, and the previous 4096 was a number a first tilemap
  /// walked past on its first frame with nothing on screen to say so.
  ///
  /// The name says sprites and the number counts records; renaming it is
  /// breaking and nothing has been willing to pay for it yet.
  ///
  /// It lives here, on the `Game`, and not on [GameRenderer2D], because it is
  /// a **sizing** knob and sizing happens on this side: [describeBuffers]
  /// runs on main before the spawn and reserves the memory. Raising it is
  /// therefore an override on your `Game2D` subclass, not a reason to subclass
  /// the renderer.
  int get maxSpritesPerTick => 16384;

  /// Bytes one tick's sprite batch occupies, including its tick stamp.
  int get spriteBatchBytes =>
      DrawData2D.batchHeaderBytes +
      maxSpritesPerTick * DrawSpriteData2D.strideBytes;

  /// Debug draw segments past this many in a single tick are dropped, and the
  /// records they would have drawn with them.
  ///
  /// **Its own budget, spent against its own buffer.** A debug shape never
  /// competes with a sprite for `maxSpritesPerTick`: a line drawn to explain
  /// why an entity is where it is, that pushed that entity out of the frame,
  /// would make the tool lie about the thing being inspected.
  ///
  /// It counts **segments**, which is also records, because a debug shape is
  /// flattened to straight segments at the call and each one is a quad. A
  /// `line` costs 1, a 24-segment `circle` costs 24, and a `label` costs one
  /// per glyph stroke - around four per character. `DebugDraw2D.segmentCount`
  /// is what the store holds and `DebugDraw2D.droppedSegments` is what did
  /// not fit, so raising this by the second is the direct fix.
  ///
  /// The default reserves 304 KiB per declared [CameraView], in a debug build
  /// only: [describeBuffers] declares nothing at all when `debugDrawEnabled`
  /// is false, so a release build reserves none of it.
  ///
  /// It lives here for the reason [maxSpritesPerTick] does - it sizes native
  /// memory, and that is reserved on this side before the spawn.
  int get maxDebugRecordsPerTick => 4096;

  /// Bytes one tick's debug batch occupies, including its tick stamp.
  int get debugBatchBytes =>
      DrawData2D.batchHeaderBytes +
      maxDebugRecordsPerTick * DrawSpriteData2D.strideBytes;

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

  /// One debug handoff buffer per declared [CameraView], indexed by its
  /// address, or empty in a build with `debugDrawEnabled` false.
  ///
  /// Separate from [_viewFrames] and not a second section inside it: the two
  /// have separate producers, separate budgets and separate lifetimes, and a
  /// release build has to be able to not have this one at all.
  late final List<HandoffHandle> _viewDebugFrames;

  /// The frame buffer [view] is drawn into. `GameRenderer2D` writes it on the
  /// game isolate; `_ViewSurface` reads it here.
  HandoffHandle framesFor(CameraView view) => _viewFrames[view.pack()];

  /// The debug buffer [view]'s shapes are drawn into. Throws in a build with
  /// `debugDrawEnabled` false, where there is no such buffer - every caller
  /// is already behind that constant.
  HandoffHandle debugFramesFor(CameraView view) =>
      _viewDebugFrames[view.pack()];

  @override
  @mustCallSuper
  void describeBuffers(BufferDescriptor descriptor) {
    super.describeBuffers(descriptor);
    // Every `CameraView.of()` ran while the game was constructed, so
    // the views are known by the time this asks how many buffers it needs.
    _viewFrames = <HandoffHandle>[
      for (var i = 0; i < cameraViews.length; i++)
        descriptor.hasHandoff(slotBytes: spriteBatchBytes),
    ];
    // `debugDrawEnabled` is a compile-time constant, so a release build has
    // no `hasHandoff` call here to run and reserves nothing. Declaration order
    // still matches across the two copies of the `Game`, because both compile
    // the same constant.
    _viewDebugFrames = <HandoffHandle>[
      if (debugDrawEnabled)
        for (var i = 0; i < cameraViews.length; i++)
          descriptor.hasHandoff(slotBytes: debugBatchBytes),
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
  /// for the next vsync. Hung off the tick ping, a repaint would be
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
      () => _ViewSurface(
        camera,
        DrawCanvas2D(assets: assets),
        // A `const false` in release, so the second canvas, its vertex arrays
        // and the painter branch that replays them are all gone.
        debugDrawEnabled ? DrawCanvas2D(assets: assets) : null,
      ),
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
          painter: _GameViewPainter(
            surface.canvas,
            surface.debugCanvas,
            surface.frames,
          ),
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
  _ViewSurface(this.view, this.canvas, this.debugCanvas);

  final CameraView view;
  final DrawCanvas2D canvas;

  /// The debug shapes' own vertex arrays, replayed over [canvas]. Null in a
  /// build with `debugDrawEnabled` false, where there is no debug buffer to
  /// ingest from.
  ///
  /// A second [DrawCanvas2D] and not more runs on the first: the two frames
  /// arrive in separate buffers and either can be newer, so one ingest
  /// deciding for both would drop whichever landed second.
  final DrawCanvas2D? debugCanvas;

  final _FrameSignal frames = _FrameSignal();

  HandoffBuffer? _buffer;
  HandoffBuffer? _debugBuffer;

  void sample(Renderer2D renderer) {
    var landed = _sampleScene(renderer);
    if (debugDrawEnabled) landed = _sampleDebug(renderer) || landed;
    if (landed) frames.pulse();
  }

  bool _sampleScene(Renderer2D renderer) {
    final buffer = _buffer ??= renderer.framesFor(view).tryBuffer;
    if (buffer == null) return false;

    // Null means nothing new since the last look, which at 60Hz against a
    // slower tick is the ordinary case. Taking a slot is also what hands the
    // previous one back, so the writer only ever resumes because this ran.
    final slot = buffer.beginRead();
    if (slot == null) return false;

    // Decoded into the canvas's own vertex arrays here, in the frame callback,
    // and not read during paint. That is what keeps the window in which
    // the writer could interfere down to this ingest instead of a whole
    // raster - see `HandoffBuffer`.
    return canvas.ingestFrame(
      ByteData.sublistView(slot.asTypedList(buffer.readUsedBytes)),
      buffer.readUsedBytes,
    );
  }

  bool _sampleDebug(Renderer2D renderer) {
    final canvas = debugCanvas;
    if (canvas == null) return false;
    final buffer = _debugBuffer ??= renderer.debugFramesFor(view).tryBuffer;
    if (buffer == null) return false;
    final slot = buffer.beginRead();
    if (slot == null) return false;
    return canvas.ingestFrame(
      ByteData.sublistView(slot.asTypedList(buffer.readUsedBytes)),
      buffer.readUsedBytes,
    );
  }

  void dispose() {
    _buffer = null;
    _debugBuffer = null;
    canvas.dispose();
    debugCanvas?.dispose();
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
  const _GameViewPainter(this.canvas, this.debugCanvas, Listenable repaint)
    : super(repaint: repaint);

  final DrawCanvas2D canvas;

  /// The debug overlay, or null in a build with `debugDrawEnabled` false.
  final DrawCanvas2D? debugCanvas;

  /// Scene first, then the debug shapes over it. The overlay describes what
  /// the scene is doing, so a sprite drawn on top of it would hide the thing
  /// being read.
  @override
  void paint(Canvas target, Size size) {
    canvas.replay(target);
    if (debugDrawEnabled) debugCanvas?.replay(target);
  }

  /// Always false: repaints come from the `repaint` `Listenable` handed to
  /// the constructor, and the painter's own identity says nothing about
  /// whether the frame moved.
  @override
  bool shouldRepaint(_GameViewPainter oldDelegate) => false;
}
