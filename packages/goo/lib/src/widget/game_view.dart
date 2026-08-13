import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:flutter/widgets.dart';

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
  const GameView({super.key, required this.game});

  /// The **handle** copy - the one the caller still holds after
  /// `await game.start()`. Must already be running; see [createState].
  final Game game;

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> {
  @override
  void initState() {
    super.initState();
    _requireRunning();
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
    super.dispose();
  }

  @override
  void didUpdateWidget(GameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.game, widget.game)) _requireRunning();
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

  void _onPointerEvent(PointerEvent event) {
    widget.game.inputDevice?.handlePointerEvent(event);
  }

  void _requireRunning() {
    if (widget.game.isRunning) return;
    throw StateError(
      'GameView was given a ${widget.game.runtimeType} that has not started '
      'yet. Await game.start() before building a GameView: a system\'s '
      'main-isolate twin only exists once the boot pass has run, so there is '
      'nothing to build a widget from until then. It is also what keeps a '
      'closure over this State - and so over the whole widget tree - out of '
      'the object Game hands to Isolate.spawn, which would make the spawn '
      'message unsendable. See the class doc on Game.',
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
          // The view's size, reported to the device so the game isolate can
          // resolve a pointer against it (`MousePosition.viewSize`) without
          // knowing anything about the widget tree. Written on layout rather
          // than per event - a window resize is orders of magnitude rarer
          // than a pointer move - and the device only publishes when the
          // number actually changes, so a rebuild at the same size costs
          // two float comparisons.
          widget.game.inputDevice?.setViewSize(
            constraints.maxWidth,
            constraints.maxHeight,
          );
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
            child: widget.game.buildView(context) ?? const SizedBox.shrink(),
          );
        },
      );
}
