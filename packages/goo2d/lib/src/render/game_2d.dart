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

  /// Reused across ticks - `RingBuffer.drainInto` appends, and allocating a
  /// fresh list 60 times a second for what is usually one record is exactly
  /// what its `drainInto`/`drain` split exists to avoid.
  final List<RingBufferRecord> _drained = <RingBufferRecord>[];

  RingBuffer? _ring;
  bool _listening = false;

  /// Drains the draw ring and pulses the repaint signal - once per tick the
  /// game isolate reports, on the main isolate.
  ///
  /// Drains unconditionally, repaints conditionally. The drain has to happen
  /// every tick even when nothing will be painted: the ring is bounded, and
  /// a consumer that only drains when it feels like painting is a producer
  /// that starts dropping frames.
  void _onTick(int tick) {
    // Reached through the declared system's own handle rather than a shared
    // buffer name: `GameRenderer2D` declares the ring in its describeBuffers,
    // both isolate copies of that system hold a handle to the same memory,
    // and this is the main-isolate copy's.
    final ring = _ring ??= tryGetSystem<GameRenderer2D>()?.drawBuffer.tryRing;
    // Null when the game declares no GameRenderer2D at all - a valid
    // headless-plus-HUD setup, just not one that paints.
    if (ring == null) return;

    _drained.clear();
    ring.drainInto(_drained);
    if (_drained.isEmpty) return;
    // ingest() reports "the newest frame in that drain is newer than the one
    // already held", so a duplicate or an unrecognised record type ends here
    // rather than in a wasted paint.
    if (!_canvas.ingest(_drained)) return;
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
    if (!_listening) {
      _listening = true;
      addTickListener(_onTick);
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

  /// Releases the tick subscription and the decoded frame.
  @override
  Future<void> stop() async {
    if (_listening) {
      _listening = false;
      removeTickListener(_onTick);
    }
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
