import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:goo2d/src/game.dart';

/// The root widget for the world-space scene hierarchy.
///
/// [WorldSpace] defines the coordinate system for all game objects that exist
/// in the physical game environment. It automatically applies the main
/// camera's transformation to its children, allowing them to be positioned
/// in global world coordinates rather than screen pixels.
///
/// ```dart
/// // Internal engine usage or custom world setup:
/// void example(Widget gameHierarchy) {
///   final world = WorldSpace(
///     child: gameHierarchy,
///   );
/// }
/// ```
///
/// See also:
/// * [Game], the root engine container which uses this widget internally.
/// * [CameraSystem], which provides the transformation for the world.
class WorldSpace extends SingleChildRenderObjectWidget {
  /// Creates a [WorldSpace] container that transforms its [child].
  ///
  /// The [child] is typically a [GameObjectWidget] or a collection of
  /// entities that should respond to camera movement and zooming.
  ///
  /// * [key]: The Flutter widget key for identity.
  /// * [child]: The root of the world-space entity tree.
  const WorldSpace({super.key, super.child});

  @override
  RenderWorldSpace createRenderObject(BuildContext context) {
    return RenderWorldSpace(game: GameProvider.of(context));
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldSpace renderObject) {
    renderObject.game = GameProvider.of(context);
  }
}

/// The render object that implements world-space camera transformations.
///
/// [RenderWorldSpace] acts as a bridge between Flutter's standard 2D layout and
/// the Goo2D camera system. It intercepts the painting and hit-testing
/// phases to apply the appropriate transformation matrix, ensuring that
/// world-space coordinates are correctly projected onto the screen.
///
/// Although this class is primarily used internally by the [WorldSpace] widget,
/// it provides the technical foundation for the engine's spatial hierarchy
/// and coordinate resolution logic.
///
/// ```dart
/// void example(GameEngine game) {
///   final renderWorld = RenderWorldSpace(game: game);
///   // This is managed by the WorldSpace widget during the layout pass
/// }
/// ```
///
/// See also:
/// * [WorldSpace], the widget that creates this render object.
/// * [GameEngine], which provides the camera system and screen metrics.
class RenderWorldSpace extends RenderProxyBox {
  /// The game engine instance used to retrieve camera and screen state.
  ///
  /// This reference allows the render object to access the current 
  /// [CameraSystem] and [ScreenState] to calculate the final projection 
  /// matrix for each frame.
  GameEngine game;

  /// Creates a [RenderWorld] tied to the specified [game] engine.
  ///
  /// * [game]: The active engine instance managing the simulation.
  RenderWorldSpace({required this.game});

  Matrix4? _getTransform() {
    final cameras = game.getSystem<CameraSystem>();
    if (cameras == null || !cameras.isReady) return null;
    final camera = cameras.main;

    final screenSize = game.screen.screenSize;
    if (screenSize == Size.zero ||
        screenSize.width == 0 ||
        screenSize.height == 0) {
      return null;
    }

    return camera.getFullMatrix(screenSize);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;

    final transform = _getTransform();
    if (transform == null) {
      super.paint(context, offset);
      return;
    }

    final cameraSystem = game.getSystem<CameraSystem>();
    if (cameraSystem?.isSecondaryPass ?? false) {
      // Manual transformation for non-standard rendering passes
      // (e.g. shadow maps or post-processing buffers).
      context.canvas.save();
      context.canvas.translate(offset.dx, offset.dy);
      context.canvas.transform(transform.storage);
      context.paintChild(child!, Offset.zero);
      context.canvas.restore();
    } else {
      // Standard Flutter transform push, allowing for hardware
      // acceleration and layer optimization.
      if (cameraSystem != null) {
        cameraSystem.currentRenderCamera = cameraSystem.main;
      }
      try {
        final composedTransform =
            Matrix4.translationValues(offset.dx, offset.dy, 0)
              ..multiply(transform);
        context.pushTransform(needsCompositing, Offset.zero, composedTransform, (
          context,
          offset,
        ) {
          context.paintChild(child!, offset);
        });
      } finally {
        if (cameraSystem != null) {
          cameraSystem.currentRenderCamera = null;
        }
      }
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // We bypass our own bounds check so the world-root doesn't
    // clip its children. This allows objects to be interactive even
    // if they are partially outside the initial render box boundaries,
    // which is common in sprawling 2D environments.
    if (hitTestChildren(result, position: position) || hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (child == null) return false;

    final transform = _getTransform();
    if (transform == null) {
      return super.hitTestChildren(result, position: position);
    }

    // Unprojects the screen-space pointer position into the world-space
    // child coordinate system using the inverse camera matrix.
    return result.addWithPaintTransform(
      transform: transform,
      position: position,
      hitTest: (result, transformedPosition) {
        return child!.hitTest(result, position: transformedPosition);
      },
    );
  }
}
