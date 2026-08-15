import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:flutter/widgets.dart';

import 'package:goo/src/camera_view.dart';
import 'package:goo/src/game.dart';

/// Displays a running [Game] - and knows nothing whatsoever about how it is
/// drawn.
///
/// # Why this is in the kernel and not in a renderer package
///
/// A 2D game paints into a `CustomPaint`; a 3D game may need a native
/// surface (a `Texture` widget fed by a platform view), and something
/// headless-with-a-HUD may want neither. Those have nothing in common except
/// "a widget that shows a running game", which is exactly this class. So the
/// widget lives here, dimension-agnostic, and the actual drawing is
/// contributed by whatever systems the game declared: `buildWidget` fires a
/// [BuildWidgetEvent] and each `BuildWidgetListener` system wraps what has
/// been built so far. `goo2d`'s `RenderSystem2D` wraps it in a `CustomPaint`;
/// a future `goo3d` would wrap it in something else entirely, and neither
/// package needs its own `GameView`.
///
/// # Push-driven, not vsync-polling
///
/// There is no ticker and no `SchedulerBinding.addPersistentFrameCallback`.
/// [Game.addTickListener] already fires on this isolate once per completed
/// fixed tick - the "the published snapshot moved" signal - so a rebuild is
/// scheduled from that and nothing polls. Note the rebuild here is of the
/// *widget*; a renderer that only needs to repaint pixels (not rebuild the
/// tree) should hang a `Listenable` off the same tick signal instead, which
/// is what `RenderSystem2D` does - see its `repaint` wiring. This widget
/// rebuilding per tick would defeat that, so it deliberately does **not**
/// `setState` on every tick: it rebuilds only when the *set of contributed
/// widgets* could have changed, which today means never automatically. The
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
  /// name, so it says so rather than passing a null camera and hoping. This is
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
  /// Registered on `HardwareKeyboard` rather than through a `Focus` node
  /// wrapping the child, deliberately: a game is not a text field, and
  /// requiring the view to hold focus would mean WASD silently dying the
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

  /// Forwards the pointer **with the view it is over**.
  ///
  /// `localPosition` is already relative to this widget, so the coordinates
  /// were always view-local; what was missing was *which* view, and with two
  /// `GameView`s on screen that is the difference between picking against the
  /// thing under the cursor and picking against whatever view happened to be
  /// declared first.
  void _onPointerEvent(PointerEvent event) {
    final device = widget.game.inputDevice;
    if (device == null) return;
    final camera = widget.camera;
    if (camera != null) {
      // The size of *this* view, refreshed as the pointer enters it, so
      // `MousePosition.viewSize` describes the view the cursor is actually in
      // rather than whichever `GameView` laid out last. Costs two float
      // comparisons while the pointer stays put - `setViewSize` publishes only
      // on change - and it is what makes the number mean something with two
      // views of different sizes on screen.
      device.setViewSize(camera.viewportWidth, camera.viewportHeight);
    }
    device.handlePointerEvent(event, viewAddress: camera?.address ?? -1);
  }

  void _requireRunning() {
    if (widget.game.isRunning) return;
    throw StateError(
      'GameView was given a ${widget.game.runtimeType} run that has not '
      'started yet. Await Game.start() before building a GameView: a system\'s '
      'main-isolate twin only exists once the boot pass has run, so there is '
      'nothing to build a widget from until then. It is also what keeps a '
      'closure over this State - and so over the whole widget tree - out of '
      'the object Game.start hands to Isolate.spawn, which would make the '
      'spawn message unsendable. See the class doc on Game.',
    );
  }

  /// Delegates the entire tree to the game's declared systems. If none of
  /// them is a `BuildWidgetListener`, this is an empty box - the honest
  /// answer for a game with no renderer declared, rather than a crash or a
  /// blank-but-sized placeholder pretending something is there.
  ///
  /// The [Listener] is how mouse *buttons* reach the game (keys come in
  /// through `HardwareKeyboard`, which needs no widget). `translucent`, so
  /// wrapping the game costs nothing in hit testing: whatever the systems
  /// built still gets its own hits, and an empty game still reports button
  /// state. Mouse *position* is deliberately not read here - that is a
  /// follow-up (`MouseBinding`), and it needs a coordinate space this widget
  /// does not currently define.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // The pointer surface size, for a game with **no camera view** to
      // hold one. With a camera it is written by [_onPointerEvent]
      // instead, from the view the event arrived on - and it has to be
      // exactly one of the two, not both: every `GameView` on screen runs
      // this builder on every rebuild, so a layout-time write would let
      // whichever laid out last overwrite whichever the pointer is
      // actually in. That is a real bug, and it is what made the first
      // attempt at per-view `viewSize` report the wrong number.
      if (widget.camera == null) {
        widget.game.inputDevice?.setViewSize(
          constraints.maxWidth,
          constraints.maxHeight,
        );
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
