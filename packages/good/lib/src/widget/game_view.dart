import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:flutter/widgets.dart';

import 'package:good/src/camera_view.dart';
import 'package:good/src/game.dart';

/// Displays a running [Game] - and knows nothing whatsoever about how it is
/// drawn.
///
/// # Why this is in the kernel and not in a renderer package
///
/// A 2D game paints into a `CustomPaint`; a 3D game may need a native
/// surface (a `Texture` widget fed by a platform view), and something
/// headless-with-a-HUD may want neither. Those have nothing in common except
/// "a widget that shows a running game", which is exactly this class. So the
/// widget lives here, dimension-agnostic, and the drawing comes from
/// [Game.buildView] - which `Game2D` overrides with a `CustomPaint` fed by the
/// draw buffer, and a future `goo3d` would override with a native surface.
/// Neither package needs its own `GameView`.
///
/// # Push-driven, not vsync-polling
///
/// There is no ticker and no `SchedulerBinding.addPersistentFrameCallback`.
/// [Game.addTickListener] already fires on this isolate once per completed
/// fixed tick - the "the published snapshot moved" signal - so a rebuild is
/// scheduled from that and nothing polls. Note the rebuild here is of the
/// *widget*; a renderer that only needs to repaint pixels (not rebuild the
/// tree) should hang a `Listenable` off the same tick signal instead, which
/// is what `Game2D`'s painter does - see its `repaint` wiring. This widget
/// rebuilding per tick would defeat that, so it does **not** `setState` on
/// every tick: it rebuilds only when what [Game.buildView]
/// returns could have changed, which today means never automatically. The
/// tick listener exists so a subclass or a future scene-change signal has
/// somewhere to hook.
class GameView extends StatefulWidget {
  /// Shows [camera] - one of the views the game declared in
  /// [Game.describeCameras].
  ///
  /// The camera is the whole of it: a [CameraView] is issued by one game's
  /// table and knows which (`CameraView.game`), and that game is running
  /// exactly one run, so naming the view names everything this widget needs.
  ///
  /// It briefly took a run alongside the camera, back when a `Game` could
  /// have backed several at once and a view alone did not say which to show.
  /// One instance, one run settled that - and passing both was never just
  /// verbose, it was a pair that could disagree.
  const GameView({super.key, required CameraView this.camera}) : _game = null;

  /// Shows a game that declares no cameras: routes keyboard, gamepad and
  /// pointer input, and paints nothing.
  ///
  /// A headless-plus-HUD game is a first-class shape here and has no camera to
  /// name, so it says so instead of passing a null camera and hoping. This is
  /// the one case that has to name the game directly, because there is no
  /// camera to have named it. Neither constructor can express a mismatch: this
  /// one takes no camera, the other takes no game.
  const GameView.headless({super.key, required Game game})
    : camera = null,
      // A named parameter cannot start with an underscore, so `this._game`
      // is not spellable and the lint's suggestion does not compile.
      // ignore: prefer_initializing_formals
      _game = game;

  /// The view being shown, or null for [GameView.headless].
  final CameraView? camera;

  final Game? _game;

  /// The game being shown: whoever declared [camera], or the one handed to
  /// [GameView.headless]. Must already be running; see [createState].
  Game get game => _game ?? camera!.game;

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> {
  @override
  void initState() {
    super.initState();
    _requireRunning();
    // Before the keyboard, so a renderer that arms a frame callback here is
    // running by the time the first build asks it for a widget.
    widget.game.attachView();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    // Gamepads for the same reason, and with the same lifetime: a game
    // nobody is looking at has no business holding an OS subscription open.
    // Unlike the keyboard this one is per game rather than global, so two
    // GameViews on one game share it - attaching twice is a no-op.
    widget.game.gamepads?.attach();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    // Dropped rather than awaited: dispose cannot be async, and the detach's
    // own work (clearing held bits, cancelling the subscription) does not
    // need to have finished before the widget goes.
    widget.game.gamepads?.detach();
    widget.game.detachView();
    super.dispose();
  }

  @override
  void didUpdateWidget(GameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.game, widget.game)) return;
    _requireRunning();
    // Attach before detaching, so swapping between two views of the *same*
    // game never dips the count to zero and tears down what is about to be
    // rebuilt.
    widget.game.attachView();
    oldWidget.game.detachView();
  }

  /// Forwards every key event to the game's [InputDevice], and reports it
  /// **unhandled** so nothing else in the app stops receiving keys.
  ///
  /// Registered on `HardwareKeyboard` and not through a `Focus` node wrapping
  /// the child: a game is not a text field, and requiring the view to hold
  /// focus would mean WASD silently dying the
  /// moment any button or overlay took it. The cost is that a `GameView`
  /// which is on screen but "not in front" still sees keys - and two
  /// `GameView`s on one game both forward the same event, which is harmless
  /// because the device stores held-state bits and setting a bit twice is
  /// setting it once.
  ///
  /// Null-safe on the device: on the game-isolate copy (which never builds
  /// widgets) and before `start()` there is nothing to write to, and that is
  /// not an error - see `InputDevice`.
  bool _onKeyEvent(KeyEvent event) {
    widget.game.inputDevice?.handleKeyEvent(event);
    return false;
  }

  /// Forwards the pointer **with the view it is over** - a mouse, a finger and
  /// a stylus all through this one path.
  ///
  /// `localPosition` is already relative to this widget, so the coordinates
  /// were always view-local; what was missing was *which* view, and with two
  /// `GameView`s on screen that is the difference between picking against the
  /// thing under the cursor and picking against whatever view happened to be
  /// declared first.
  void _onPointerEvent(PointerEvent event) {
    final device = widget.game.inputDevice;
    if (device == null) return;
    // Only the front-most view the pointer passed through writes it. The
    // `Listener` below is translucent, so a `GameView` behind another one is
    // handed the same dispatch, and a second write of it is a second contact
    // under one id and a view address claimed by whichever view was hit last.
    // Hit test order is front to back, so the first caller here is the view
    // the pointer visibly landed in - and the size written just below has to
    // be behind the same gate, or the view behind names the surface.
    if (!device.claimPointerEvent(event)) return;
    final camera = widget.camera;
    if (camera != null) {
      // The size of *this* view, refreshed as the pointer enters it, so
      // `CursorPosition.viewSize` describes the view the cursor is actually in
      // rather than whichever `GameView` laid out last. Costs two float
      // comparisons while the pointer stays put - `setViewSize` publishes only
      // on change - and it is what makes the number mean something with two
      // views of different sizes on screen.
      device.setViewSize(camera.viewportWidth, camera.viewportHeight);
    }
    device.handlePointerEvent(event, viewAddress: camera?.pack() ?? -1);
  }

  void _requireRunning() {
    if (widget.game.isRunning) return;
    throw StateError(
      'GameView was given a ${widget.game.runtimeType} run that has not '
      'started yet. Await Game.start() before building a GameView: the '
      'main-isolate half a game paints from - its camera views and their frame '
      'buffers - is declared and allocated by the boot pass, so there is '
      'nothing to build a widget from until then. It is also what keeps a '
      'closure over this State - and so over the whole widget tree - out of '
      'the object Game.start hands to Isolate.spawn, which would make the '
      'spawn message unsendable. See the class doc on Game.',
    );
  }

  /// Delegates the entire tree to [Game.buildView]. A game that overrides
  /// nothing gets a zero-sized box - the honest answer for a game with no
  /// renderer, instead of a crash or a blank-but-sized placeholder pretending
  /// something is there.
  ///
  /// The [Listener] is how every pointer reaches the game: the mouse as a
  /// cursor position and button bits, and fingers and styluses as contacts.
  /// Keys come in through `HardwareKeyboard`, which needs no widget.
  ///
  /// A raw [Listener] and not a gesture recognizer. `RenderPointerListener` is
  /// not a `GestureArenaMember`, so it takes whatever the hit test routes to
  /// it - which means a `GameView` inside a `ListView` reads a drag the list
  /// is also scrolling on. Claiming the arena instead would silence every
  /// Flutter gesture widget below this one, and in this engine a HUD is a
  /// descendant, since `buildView` fires `BuildWidgetEvent` and each
  /// `BuildWidgetListener` wraps what was built. Put interactive widgets in a
  /// `Stack` above the view, and read contacts for the game.
  /// `translucent`, so wrapping the game costs nothing in hit testing:
  /// whatever the game built still gets its own hits, and an empty game still
  /// reports button state.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // The pointer surface size. For a game with **no camera view** this
      // builder is the only writer, so it writes on every layout. With a
      // camera it is [_onPointerEvent] that writes, from the view the event
      // arrived on - and it has to be that one, because every `GameView` on
      // screen runs this builder on every rebuild, so a plain write here
      // would let whichever laid out last overwrite whichever the pointer is
      // actually in. That is a real bug, and it is what made the first
      // attempt at per-view `viewSize` report the wrong number.
      //
      // `seedViewSize` is the layout-time write that cannot cause it: it
      // does nothing once a pointer event has claimed the size. Until one
      // does, there is no view to overwrite - and on a game played with a
      // keyboard or a pad, where none ever will, it is the only writer there
      // is, so resizes keep landing instead of leaving a stale first frame.
      final device = widget.game.inputDevice;
      if (widget.camera == null) {
        device?.setViewSize(constraints.maxWidth, constraints.maxHeight);
      } else {
        device?.seedViewSize(constraints.maxWidth, constraints.maxHeight);
      }
      // The size of the view being shown, which is what its camera
      // projection centres on. Per view rather than per game: two
      // GameViews of different sizes cannot share one number, which is
      // the whole reason this is not just `Game.viewWidth`.
      widget.camera?.setViewport(constraints.maxWidth, constraints.maxHeight);
      return Listener(
        behavior: HitTestBehavior.translucent,
        // `hover` as well: a mouse that moves with no button held still
        // moves the cursor, and a game that only tracked drags would
        // have a pointer that froze whenever nothing was pressed.
        onPointerHover: _onPointerEvent,
        onPointerDown: _onPointerEvent,
        // Move as well as down/up: Flutter reports a *second* button
        // pressed during a drag as a move with a wider button mask, not
        // as another down event, so a down/up-only wiring would miss it.
        onPointerMove: _onPointerEvent,
        onPointerUp: _onPointerEvent,
        onPointerCancel: _onPointerEvent,
        child:
            widget.game.buildView(context, widget.camera) ??
            const SizedBox.shrink(),
      );
    },
  );
}
