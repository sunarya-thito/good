import 'dart:math' as math;

// `RenderProxyBox`, `PaintingContext` and `PipelineOwner` are the render
// layer's, and `widgets.dart` re-exports neither of the last two.
import 'package:flutter/rendering.dart'
    show Matrix4, PaintingContext, PipelineOwner, RenderBox, RenderProxyBox;
import 'package:flutter/widgets.dart';

import 'package:good/src/game.dart';
import 'package:good/src/input/input_axis.dart';

/// How much of the stick's box the default thumb covers, across.
const double _thumbFraction = 0.42;

/// The default colour of both painters below - a mid grey carrying its own
/// alpha, so the stick reads on light art and on dark art without a theme.
/// `package:flutter/widgets.dart` has no colour scheme to ask, and reaching for
/// one would put a Material dependency in the kernel.
const Color _defaultColor = Color(0x99808080);

/// The stick's visual, with no input attached: a round track and a thumb
/// displaced across it.
///
/// Draws a value somebody else holds. [JoystickArea] and [JoystickControl] are
/// the two that read a finger; this one is for drawing a stick from a value
/// already in hand - mirroring a connected pad's thumbstick on screen, or a
/// replay's recorded input.
///
/// ```dart
/// SizedBox.square(
///   dimension: 120,
///   child: Joystick(thumbOffset: Offset(stick.value.x, stick.value.y)),
/// )
/// ```
///
/// # [thumbOffset] is -1..1, with 0 at rest and +1 up
///
/// The same convention `StickBinding` delivers and `InputAxis` documents, so a
/// value read out of an action can be handed straight here. **+1 on the y is
/// up**, which is the world's own axis and the opposite of Flutter's screen y;
/// the flip happens in this widget's painting and nowhere a caller can see.
///
/// A length above 1 is drawn where it lands, outside the track. The two
/// interactive widgets clamp to the circle before they get here, and a pad's
/// diagonal corner does not.
///
/// # Size comes from the parent
///
/// The stick fills the box it is given and its radius is half the shorter
/// side, so it needs a bounded one - a `SizedBox`, a `Positioned` with a width
/// and a height, or an `AspectRatio`. An unbounded box asserts.
///
/// # [track] and [thumb] replace the painters whole
///
/// Either one given is drawn in place of the default for that part: [track]
/// filling the box, [thumb] as a square of [_thumbFraction] of it, centred and
/// then displaced. [color] shapes only the defaults, so a caller supplying both
/// widgets has no use for it.
class Joystick extends StatefulWidget {
  /// Draws a stick with its thumb at [thumbOffset].
  const Joystick({
    super.key,
    this.thumbOffset = Offset.zero,
    this.color = _defaultColor,
    this.track,
    this.thumb,
  });

  /// Where the thumb sits, -1..1 per axis with 0 at rest and +1 up. See the
  /// class doc.
  final Offset thumbOffset;

  /// What the default track and thumb are painted in. Ignored for a part that
  /// [track] or [thumb] replaces.
  final Color color;

  /// Drawn filling the box, behind the thumb. Null for the default ring.
  final Widget? track;

  /// Drawn centred and displaced by [thumbOffset]. Null for the default disc.
  final Widget? thumb;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  final _StickValue _value = _StickValue();

  @override
  void initState() {
    super.initState();
    _value.set(widget.thumbOffset.dx, widget.thumbOffset.dy);
  }

  @override
  void didUpdateWidget(Joystick oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value.set(widget.thumbOffset.dx, widget.thumbOffset.dy);
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _StickVisual(
    value: _value,
    color: widget.color,
    track: widget.track,
    thumb: widget.thumb,
  );
}

/// Analog input from a finger dragging **anywhere inside the area**, touchpad
/// style: the stick centres itself where the finger lands.
///
/// Placed over a `GameView` in a `Stack`, so a `Positioned` covering the left
/// half of the screen turns that half into a stick and leaves the right half
/// to the game.
///
/// ```dart
/// Stack(
///   children: [
///     GameView(camera: camera),
///     Positioned(
///       left: 0, top: 0, bottom: 0, width: 160,
///       child: JoystickArea(game: game),
///     ),
///   ],
/// )
/// ```
///
/// The game reads what the finger is doing through a `StickBinding` naming the
/// same two axes:
///
/// ```dart
/// move = input.has<Vector2>(
///   const StickBinding(x: .virtualLeftStickX, y: .virtualLeftStickY),
/// );
/// ```
///
/// # It draws nothing until it is given something to draw
///
/// With no [track] and no [thumb] the area is invisible and the game shows
/// through it, which is the touchpad case. Give it either and the stick appears
/// centred on the finger for as long as the finger is down, and goes when the
/// finger goes. A stick that is always on screen at a fixed spot is
/// [JoystickControl].
///
/// Wrap either in an `Opacity` to keep the art behind it readable.
///
/// # [radius] is the travel to full deflection
///
/// How far in logical pixels the finger moves from where it landed for the axis
/// to read 1, and half the drawn stick's width. Past it the value clamps to the
/// circle, so a diagonal at the edge reads a magnitude of 1 and not 1.41.
///
/// # It takes the whole pointer, and one at a time
///
/// Hit testing is opaque, so a finger that lands here does not also reach the
/// `GameView` underneath as a contact. The first finger down owns the stick
/// until it ends; a second one inside the same area is ignored, so two thumbs
/// cannot fight over one axis pair. Two areas naming two axis pairs are two
/// sticks and work at once.
///
/// # Safe areas are the caller's
///
/// The engine handles none. An area reaching the bottom of the screen overlaps
/// the home indicator on most phones; wrap it in a `SafeArea` when its edges
/// have to stay reachable. Do not wrap the `GameView` in one - it takes its
/// viewport from its constraints, so that letterboxes the art.
class JoystickArea extends StatelessWidget {
  /// A stick anywhere in this widget's box, writing [x] and [y] on [game].
  const JoystickArea({
    super.key,
    required this.game,
    this.x = InputAxis.virtualLeftStickX,
    this.y = InputAxis.virtualLeftStickY,
    this.radius = 64,
    this.color = _defaultColor,
    this.track,
    this.thumb,
  });

  /// The running game whose `InputDevice` this writes through. Before
  /// `Game.start` and on the game isolate there is no device, and this widget
  /// then draws and writes nothing.
  final Game game;

  /// The axis the horizontal displacement is written to, -1 left and +1 right.
  final VirtualAxis x;

  /// The axis the vertical displacement is written to, +1 up.
  final VirtualAxis y;

  /// Logical pixels of finger travel to full deflection. See the class doc.
  final double radius;

  /// What the default track and thumb are painted in.
  final Color color;

  /// The stick's track, drawn at the finger while it is down. See the class
  /// doc.
  final Widget? track;

  /// The stick's thumb, drawn at the finger while it is down.
  final Widget? thumb;

  @override
  Widget build(BuildContext context) => _StickSurface(
    game: game,
    x: x,
    y: y,
    radius: radius,
    followFinger: true,
    color: color,
    track: track,
    thumb: thumb,
  );
}

/// Analog input from a stick that stays where it is put: the same reading as
/// [JoystickArea], centred on this widget's box and drawn all the time.
///
/// ```dart
/// Stack(
///   children: [
///     GameView(camera: camera),
///     Positioned(
///       left: 40, bottom: 40, width: 120, height: 120,
///       child: JoystickControl(game: game),
///     ),
///   ],
/// )
/// ```
///
/// # Travel is half the box
///
/// The radius comes from the constraints - half the shorter side - so the box
/// the caller positions is the whole of the stick, and the thumb reaches the
/// track's edge exactly as the axis reaches 1. A box with no bounded size
/// asserts.
///
/// A drag that leaves the box keeps being read: Flutter routes a pointer to
/// whatever it landed on for the pointer's whole life, so sliding a thumb off
/// the control holds full deflection in that direction instead of dropping to
/// rest.
///
/// The [JoystickArea] notes on axes, on one finger at a time, and on safe
/// areas all apply here unchanged.
class JoystickControl extends StatelessWidget {
  /// A stick filling this widget's box, writing [x] and [y] on [game].
  const JoystickControl({
    super.key,
    required this.game,
    this.x = InputAxis.virtualLeftStickX,
    this.y = InputAxis.virtualLeftStickY,
    this.color = _defaultColor,
    this.track,
    this.thumb,
  });

  /// The running game whose `InputDevice` this writes through.
  final Game game;

  /// The axis the horizontal displacement is written to, -1 left and +1 right.
  final VirtualAxis x;

  /// The axis the vertical displacement is written to, +1 up.
  final VirtualAxis y;

  /// What the default track and thumb are painted in.
  final Color color;

  /// Drawn filling the box, behind the thumb.
  final Widget? track;

  /// Drawn centred and displaced by the finger.
  final Widget? thumb;

  @override
  Widget build(BuildContext context) => _StickSurface(
    game: game,
    x: x,
    y: y,
    radius: null,
    followFinger: false,
    color: color,
    track: track,
    thumb: thumb,
  );
}

/// The input half of both public controls, and the only place a finger becomes
/// a pair of axis writes.
///
/// One implementation for the two because they differ in two facts and nothing
/// else: where the stick's centre is ([followFinger]), and where its radius
/// comes from ([radius], or half the box when that is null).
class _StickSurface extends StatefulWidget {
  const _StickSurface({
    required this.game,
    required this.x,
    required this.y,
    required this.radius,
    required this.followFinger,
    required this.color,
    required this.track,
    required this.thumb,
  });

  final Game game;
  final VirtualAxis x;
  final VirtualAxis y;

  /// Travel to full deflection, or null to take half the shorter side of the
  /// box.
  final double? radius;

  /// Whether the stick centres on where the finger landed (an area) or on the
  /// box (a control).
  final bool followFinger;

  final Color color;
  final Widget? track;
  final Widget? thumb;

  @override
  State<_StickSurface> createState() => _StickSurfaceState();
}

class _StickSurfaceState extends State<_StickSurface> {
  /// The thumb's position, driven straight from the pointer stream. A
  /// `Listenable` and not a `setState`: a drag produces pointer events
  /// continuously, and this repaints the thumb without rebuilding anything.
  final _StickValue _value = _StickValue();

  /// The pointer that owns the stick, or -1 when nothing is down. Flutter's
  /// own pointer ids, so a second finger is told apart by comparison and
  /// nothing has to be allocated to track it.
  int _pointer = -1;

  /// The stick's centre in this widget's own coordinates, written at layout
  /// for a control and at touch-down for an area.
  double _originX = 0;
  double _originY = 0;

  /// Travel to full deflection, resolved for the current layout.
  double _radius = 0;

  /// Whether an area's stick is on screen. Flips twice per drag - down and up -
  /// and never while the finger moves. Always false when there is nothing to
  /// draw.
  bool _showing = false;

  bool get _hasVisual => widget.track != null || widget.thumb != null;

  @override
  void didUpdateWidget(_StickSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A rebuild that renames the axes or swaps the game leaves the old floats
    // holding whatever this widget last pushed them to, and nothing else will
    // ever write them again.
    if (identical(oldWidget.game, widget.game) &&
        oldWidget.x == widget.x &&
        oldWidget.y == widget.y) {
      return;
    }
    _restAxes(oldWidget.game, oldWidget.x, oldWidget.y);
    _pointer = -1;
    _value.set(0, 0);
    if (_showing) _showing = false;
  }

  @override
  void dispose() {
    // A finger still down when the widget goes produces no up event, which is
    // the same hole `PointerPhase.cancelled` covers for contacts: the axes
    // would keep reporting a push nobody is making. Written straight to the
    // device, since `_value` is about to be disposed and there is nothing left
    // to paint.
    if (_pointer != -1) _restAxes(widget.game, widget.x, widget.y);
    _pointer = -1;
    _value.dispose();
    super.dispose();
  }

  /// Puts one axis pair back to rest on one game. Takes both explicitly so
  /// [didUpdateWidget] can release the pair the *old* widget owned.
  void _restAxes(Game game, VirtualAxis x, VirtualAxis y) {
    final device = game.inputDevice;
    if (device == null) return;
    device.setVirtualAxis(x, 0);
    device.setVirtualAxis(y, 0);
  }

  /// Whether this state can still act on a pointer event.
  ///
  /// Flutter keeps routing a pointer to the render object it landed on for the
  /// pointer's whole life, and that outlives the widget: lifting a finger
  /// after the stick was removed from the tree arrives here with the
  /// `ChangeNotifier` below already disposed, and notifying it throws.
  bool get _live => mounted;

  void _onPointerDown(PointerDownEvent event) {
    if (!_live) return;
    // One finger owns the stick until it ends. A second one inside the same
    // area would otherwise overwrite the first's axes on every move.
    if (_pointer != -1) return;
    _pointer = event.pointer;
    if (widget.followFinger) {
      _originX = event.localPosition.dx;
      _originY = event.localPosition.dy;
      if (_hasVisual) setState(() => _showing = true);
    }
    _read(event.localPosition.dx, event.localPosition.dy);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_live || event.pointer != _pointer) return;
    _read(event.localPosition.dx, event.localPosition.dy);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_live && event.pointer == _pointer) _end();
  }

  /// A cancel is an end and not a lift. A notification, an incoming call or an
  /// ancestor winning the gesture arena takes the pointer away with no up
  /// event behind it, and a stick that waited for one would hold the direction
  /// it was pushed in until the app was restarted.
  void _onPointerCancel(PointerCancelEvent event) {
    if (_live && event.pointer == _pointer) _end();
  }

  void _end() {
    _pointer = -1;
    _write(0, 0);
    if (_showing) setState(() => _showing = false);
  }

  /// Turns a point in this widget's box into the pair of axis values, and
  /// allocates nothing doing it: two subtractions, a divide, a square root on
  /// the clamped path, and two float stores. This runs on every pointer move,
  /// which on a phone is up to the touch sampling rate.
  void _read(double localX, double localY) {
    final radius = _radius;
    if (radius <= 0) return;
    var dx = (localX - _originX) / radius;
    // Flutter's y grows downward and an axis reads +1 up, so the sign turns
    // over here - the one place in this file that knows the two disagree.
    var dy = (_originY - localY) / radius;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared > 1) {
      // Clamped to the circle and not per axis, so a corner reads a magnitude
      // of 1. A per-axis clamp would make a diagonal 1.41 times as fast as a
      // straight push.
      final scale = 1 / math.sqrt(lengthSquared);
      dx *= scale;
      dy *= scale;
    }
    _write(dx, dy);
  }

  void _write(double dx, double dy) {
    _value.set(dx, dy);
    final device = widget.game.inputDevice;
    if (device == null) return;
    // Two writes and not one, because a virtual stick is two independent
    // floats in the block - the same pair `StickBinding` names on the way out.
    // `setVirtualAxis` publishes only when the float moved.
    device.setVirtualAxis(widget.x, dx);
    device.setVirtualAxis(widget.y, dy);
  }

  @override
  Widget build(BuildContext context) => Listener(
    // Opaque: a finger that lands on a stick belongs to the stick, and must
    // not also reach the `GameView` underneath as a contact.
    behavior: HitTestBehavior.opaque,
    onPointerDown: _onPointerDown,
    onPointerMove: _onPointerMove,
    onPointerUp: _onPointerUp,
    onPointerCancel: _onPointerCancel,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final radius = widget.radius ?? constraints.biggest.shortestSide / 2;
        assert(
          radius.isFinite,
          'a ${widget.followFinger ? 'JoystickArea' : 'JoystickControl'} '
          'needs a bounded size to take its travel from - give it a SizedBox, '
          'a Positioned with a width and a height, or an AspectRatio',
        );
        _radius = radius;
        if (!widget.followFinger) {
          _originX = constraints.biggest.width / 2;
          _originY = constraints.biggest.height / 2;
        }
        final extent = radius * 2;
        if (widget.followFinger) {
          if (!_showing) return const SizedBox.expand();
          return Stack(
            fit: StackFit.expand,
            // Non-directional, so this works with no `Directionality`
            // ancestor. A `Stack` defaults to `AlignmentDirectional.topStart`
            // and asserts without one, and a game putting a HUD straight over
            // a `GameView` has no `MaterialApp` to supply it.
            alignment: Alignment.topLeft,
            children: <Widget>[
              Positioned(
                left: _originX - radius,
                top: _originY - radius,
                width: extent,
                height: extent,
                child: _StickVisual(
                  value: _value,
                  color: widget.color,
                  track: widget.track,
                  thumb: widget.thumb,
                ),
              ),
            ],
          );
        }
        return _StickVisual(
          value: _value,
          color: widget.color,
          track: widget.track,
          thumb: widget.thumb,
        );
      },
    ),
  );
}

/// The track and the thumb, laid out and painted. Pointer-transparent
/// throughout: the [Listener] above owns every hit, and a `CustomPaint` that
/// answered a hit test would take one from it.
class _StickVisual extends StatelessWidget {
  const _StickVisual({
    required this.value,
    required this.color,
    required this.track,
    required this.thumb,
  });

  final _StickValue value;
  final Color color;
  final Widget? track;
  final Widget? thumb;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final extent = constraints.biggest.shortestSide;
        assert(
          extent.isFinite,
          'a Joystick fills the box it is given, so it needs a bounded one - '
          'a SizedBox, a Positioned with a width and a height, or an '
          'AspectRatio',
        );
        return Stack(
          // The thumb at full deflection sits half outside the track, which is
          // where the finger is.
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: <Widget>[
            Positioned.fill(
              child: track ?? CustomPaint(painter: _TrackPainter(color)),
            ),
            _ThumbSlot(
              value: value,
              travel: extent / 2,
              child: SizedBox.square(
                dimension: extent * _thumbFraction,
                child: thumb ?? CustomPaint(painter: _ThumbPainter(color)),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Where the thumb is, as two plain doubles.
///
/// A `ChangeNotifier` and not a `ValueNotifier<Offset>`: the value changes on
/// every pointer move, and an `Offset` there is one heap object per event. Two
/// fields are none.
class _StickValue extends ChangeNotifier {
  double x = 0;
  double y = 0;

  /// Notifies only on a real change, so a finger resting still repaints
  /// nothing.
  void set(double newX, double newY) {
    if (newX == x && newY == y) return;
    x = newX;
    y = newY;
    notifyListeners();
  }
}

/// Paints its child displaced by [value], scaled by [travel].
///
/// A render object and not a `ListenableBuilder`, an `AnimatedBuilder` or a
/// `Transform` fed from `setState`: all three rebuild widgets on every pointer
/// event. This one marks itself for paint and the tree above it is untouched.
class _ThumbSlot extends SingleChildRenderObjectWidget {
  const _ThumbSlot({
    required this.value,
    required this.travel,
    required Widget super.child,
  });

  final _StickValue value;
  final double travel;

  @override
  _RenderThumbSlot createRenderObject(BuildContext context) =>
      _RenderThumbSlot(value, travel);

  @override
  void updateRenderObject(BuildContext context, _RenderThumbSlot renderObject) {
    renderObject
      ..value = value
      ..travel = travel;
  }
}

class _RenderThumbSlot extends RenderProxyBox {
  _RenderThumbSlot(this._value, this._travel);

  _StickValue _value;

  set value(_StickValue newValue) {
    if (identical(newValue, _value)) return;
    if (attached) _value.removeListener(markNeedsPaint);
    _value = newValue;
    if (attached) _value.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double _travel;

  set travel(double newTravel) {
    if (newTravel == _travel) return;
    _travel = newTravel;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _value.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _value.removeListener(markNeedsPaint);
    super.detach();
  }

  /// Keeps `localToGlobal` and anything built on it agreeing with what is on
  /// screen. Painting a child somewhere the transform does not mention leaves
  /// the framework answering for the thumb's resting place while the thumb is
  /// across the track.
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_value.x * _travel, -_value.y * _travel, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    // The y turns over here for the same reason it does in `_StickSurface`:
    // +1 on an axis is up, and up on a canvas is a smaller y.
    context.paintChild(
      child,
      offset.translate(_value.x * _travel, -_value.y * _travel),
    );
  }
}

/// The two painters' brushes, reused across every paint.
///
/// File level and mutable, because a `CustomPainter` here is `const` and
/// cannot hold one. Painting is synchronous and single-threaded, so the two
/// below are configured and spent inside one call and never overlap. A `Paint`
/// built inside `paint` is one heap object per repaint, and a stick being
/// dragged repaints every frame.
final Paint _fillBrush = Paint();
final Paint _strokeBrush = Paint()..style = PaintingStyle.stroke;

/// The default track: a filled disc with a ring around it, both in the same
/// colour and both under the caller's alpha.
class _TrackPainter extends CustomPainter {
  const _TrackPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    if (radius <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      center,
      radius,
      _fillBrush..color = color.withValues(alpha: color.a * 0.35),
    );
    final stroke = math.max(1.0, radius * 0.06);
    canvas.drawCircle(
      center,
      radius - stroke / 2,
      _strokeBrush
        ..color = color
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter oldDelegate) => oldDelegate.color != color;
}

/// The default thumb: one filled disc.
class _ThumbPainter extends CustomPainter {
  const _ThumbPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    if (radius <= 0) return;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      radius,
      _fillBrush..color = color,
    );
  }

  @override
  bool shouldRepaint(_ThumbPainter oldDelegate) => oldDelegate.color != color;
}
