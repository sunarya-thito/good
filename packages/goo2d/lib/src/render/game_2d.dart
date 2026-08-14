// `Size` clashes with dart:ui's - only the pointer types are wanted here.
import 'dart:ffi' hide Size;
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:goo/goo.dart';

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
abstract class Game2D extends Game with Renderer2D {}

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
  /// Declares the two systems 2D rendering cannot work without:
  /// [WorldTransformSystem], which resolves where everything is, and
  /// [createRenderer]'s system, which turns that into a frame.
  ///
  /// Declaring them here rather than leaving them to the game is the answer
  /// to a trap this design had: `extends Game2D` and
  /// `descriptor.has(GameRenderer2D())` were two separate opt-ins for one
  /// feature, and forgetting the second produced a black screen with nothing
  /// to see in a stack trace. (The example app in this repo had exactly that
  /// bug.) One opt-in now: the superclass paints, and it brings what it needs
  /// to paint with it.
  ///
  /// A game that declares its own systems overrides this and calls
  /// `super.describeSystems(descriptor)` - the `@mustCallSuper` on `Game`'s
  /// own declaration is what makes forgetting that an analyzer error rather
  /// than another black screen.
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(WorldTransformSystem());
    descriptor.has(createRenderer());
  }

  /// The renderer to declare. Override to return a `GameRenderer2D` subclass
  /// - raising `maxSpritesPerTick`, say - without having to take over
  /// [describeSystems] to do it.
  GameRenderer2D createRenderer() => GameRenderer2D();

  // `late` so the initializer may read `this.assets` - a plain field
  // initializer cannot.
  late final DrawCanvas2D _canvas = DrawCanvas2D(assets: assets);
  final _FrameSignal _frames = _FrameSignal();

  HandoffBuffer? _frameBuffer;

  /// Whether the persistent frame callback has been installed. Separate from
  /// [_listening] because Flutter has no `removePersistentFrameCallback` - the
  /// callback is installed once and disarmed, never taken off.
  bool _registered = false;

  /// Whether that callback should do anything. False after [stop], so a game
  /// that is torn down while its widget is still mounted stops touching
  /// storage that has been freed.
  bool _listening = false;

  /// Samples the newest published frame and pulses the repaint signal - once
  /// per **Flutter frame**, on the main isolate.
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
  /// Flutter can use it. There is no queue to fall behind in: the handoff
  /// buffer holds the newest complete frame, so "we missed one" simply means
  /// the missed one was replaced.
  void _onFrame(Duration _) {
    if (!_listening) return;
    // Reached through the declared system's own handle rather than a shared
    // buffer name: `GameRenderer2D` declares it in describeBuffers, both
    // isolate copies of that system hold a handle to the same memory, and this
    // is the main-isolate copy's.
    final buffer =
        _frameBuffer ??= tryGetSystem<GameRenderer2D>()?.drawFrames.tryBuffer;
    // Null when the game declares no GameRenderer2D at all - a valid
    // headless-plus-HUD setup, just not one that paints.
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
    if (!_canvas.ingestFrame(
      ByteData.sublistView(slot.asTypedList(buffer.readUsedBytes)),
      buffer.readUsedBytes,
    )) {
      return;
    }
    _frames.pulse();
  }

  /// The `CustomPaint` that shows the game, or null when there is nothing to
  /// show yet.
  ///
  /// Null while there is no scene: `GameState.scene` is nullable by design (a
  /// game between scenes, or brought up before its first load), and the
  /// honest response is to contribute nothing rather than paint a stale
  /// frame. `GameView` lays out nothing for a null, so an app that puts a
  /// loading screen behind the view sees it.
  @override
  Widget? buildView(BuildContext context) {
    if (state?.scene == null) return null;

    // Subscribing here rather than in `start()`: this is the first point at
    // which the game is known to be both running and actually on screen.
    // Guarded so a rebuild does not stack listeners.
    _listening = true;
    if (!_registered) {
      _registered = true;
      SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: _GameViewPainter(_canvas, _frames),
        size: Size.infinite,
        isComplex: true,
        willChange: true,
      ),
    );
  }

  /// Disarms the frame callback and releases the decoded frame.
  @override
  Future<void> stop() async {
    // Disarmed, not removed: Flutter has no removePersistentFrameCallback. The
    // callback stays installed for the life of the binding and does nothing.
    _listening = false;
    _frameBuffer = null;
    _canvas.dispose();
    _frames.dispose();
    await super.stop();
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
  const _GameViewPainter(this.canvas, Listenable repaint) : super(repaint: repaint);

  final DrawCanvas2D canvas;

  @override
  void paint(Canvas target, Size size) => canvas.replay(target);

  /// Always false: repaints come from the `repaint` `Listenable` handed to
  /// the constructor, and the painter's own identity says nothing about
  /// whether the frame moved.
  @override
  bool shouldRepaint(_GameViewPainter oldDelegate) => false;
}
