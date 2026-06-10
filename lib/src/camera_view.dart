import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:goo2d/src/game.dart';
import 'package:goo2d/src/camera.dart';
import 'package:goo2d/src/object.dart';
import 'package:goo2d/src/world.dart';
import 'package:goo2d/src/render.dart';

/// A widget that renders a secondary view of the game scene using a specific camera.
///
/// This widget is used to create minimaps, picture-in-picture views, or split-screen
/// layouts. It identifies its target [Camera] via a [cameraTag], which must be
/// assigned to a [GameObject] in the current game world.
///
/// ```dart
/// Container(
///   width: 200,
///   height: 200,
///   decoration: BoxDecoration(border: Border.all(color: Colors.white)),
///   child: const CameraView(cameraTag: 'minimap'),
/// );
/// ```
///
/// See also:
/// * [Camera], which defines the transformation and culling for this view.
/// * [RenderCameraView], the underlying render object.
class CameraView extends SingleChildRenderObjectWidget {
  /// The tag identifying the [Camera] component to use for this view.
  ///
  /// The [CameraView] will look up a [GameObject] with this tag and attempt
  /// to find a [Camera] component on it. If no such camera is found or if the
  /// camera is disabled, the view will render as empty (or show its child).
  final Object cameraTag;

  /// Creates a new [CameraView] for the given [cameraTag].
  ///
  /// * [key]: The standard Flutter widget key.
  /// * [cameraTag]: The tag for the target camera.
  /// * [child]: An optional child widget to render behind/instead of the scene.
  const CameraView({super.key, required this.cameraTag, super.child});

  @override
  RenderCameraView createRenderObject(BuildContext context) {
    return RenderCameraView(
      game: GameProvider.of(context),
      cameraTag: cameraTag,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderCameraView renderObject) {
    renderObject
      ..game = GameProvider.of(context)
      ..cameraTag = cameraTag;
  }
}

/// A render object that displays a transformed view of the [RenderWorldSpace].
///
/// This render object handles the complexity of mapping screen coordinates
/// to world coordinates using a specific [Camera]. It performs a filtered
/// paint pass to ensure only objects matching the camera's culling mask
/// are rendered in this view.
///
/// ```dart
/// void setupView(GameEngine game) {
///   RenderCameraView(
///     game: game,
///     cameraTag: 'minimap',
///   );
/// }
/// ```
///
/// See also:
/// * [CameraView], the widget that manages this render object.
/// * [CameraSystem], which tracks active cameras in the engine.
class RenderCameraView extends RenderProxyBox {
  /// The current game engine instance providing access to the systems and world.
  ///
  /// This reference is used to look up the [CameraSystem] and the [RenderWorldSpace]
  /// ancestor during the painting and hit-testing phases.
  GameEngine game;

  /// The tag identifying the camera to use for rendering and hit-testing.
  ///
  /// This tag is used at runtime to find the active [Camera] component. If the
  /// camera state changes, the view will automatically reflect the new settings.
  Object cameraTag;

  /// Creates a [RenderCameraView] with the required engine and camera references.
  ///
  /// * [game]: The engine instance to associate with this view.
  /// * [cameraTag]: The tag for the target camera.
  RenderCameraView({required this.game, required this.cameraTag});

  @override
  bool get alwaysNeedsCompositing => false;

  @override
  void performLayout() {
    size = constraints.constrain(
      constraints.isTight ? constraints.biggest : const Size(150, 150),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 10000;
  @override
  double computeMinIntrinsicHeight(double width) => 0;
  @override
  double computeMaxIntrinsicHeight(double width) => 10000;

  @override
  void paint(PaintingContext context, Offset offset) {
    final cameraSystem = game.getSystem<CameraSystem>();
    if (cameraSystem?.isSecondaryPass ?? false) {
      super.paint(context, offset);
      return;
    }

    final camera = tagRegistry[cameraTag]?.firstOrNull?.tryGetComponent<Camera>();
    if (camera == null || !camera.gameObject.active || !camera.enabled) {
      super.paint(context, offset);
      return;
    }

    final screenSize = game.screen.screenSize;
    if (screenSize == Size.zero) {
      super.paint(context, offset);
      return;
    }

    if (camera.clearFlags == CameraClearFlags.solidColor) {
      final paint = Paint()..color = camera.backgroundColor;
      context.canvas.drawRect(offset & size, paint);
    }

    // 1. Calculate the full transformation for the secondary view
    final viewMatrix = camera.worldToCameraMatrix;

    // Use the local size directly for the projection and viewport mapping.
    // This ensures that the minimap covers the expected orthographic area
    // regardless of the main window's aspect ratio.
    final projMatrix = camera.projectionMatrix(size);
    final viewportMatrix = Matrix4.identity()
      ..translateByDouble(size.width / 2, size.height / 2, 0.0, 1.0)
      ..scaleByDouble(size.width / 2, -size.height / 2, 1.0, 1.0);

    final fullCameraMatrix = viewportMatrix * projMatrix * viewMatrix;

    // 2. Find the RenderWorldSpace ancestor
    RenderWorldSpace? world;
    RenderObject? current = parent;
    while (current != null) {
      if (current is RenderWorldSpace) {
        world = current;
        break;
      }
      current = current.parent;
    }

    if (world == null) {
      debugPrint('goo2d: Minimap could NOT find RenderWorldSpace ancestor!');
    }

    if (world != null && world.child != null) {
      if (cameraSystem != null) {
        cameraSystem.isSecondaryPass = true;
        cameraSystem.currentRenderCamera = camera;
      }
      try {
        context.canvas.save();
        context.canvas.clipRect(offset & size);
        context.canvas.translate(offset.dx, offset.dy);
        context.canvas.transform(fullCameraMatrix.storage);

        _paintFiltered(context, Offset.zero, world.child!);
        context.canvas.restore();
      } finally {
        if (cameraSystem != null) {
          cameraSystem.isSecondaryPass = false;
          cameraSystem.currentRenderCamera = null;
        }
      }
    }

    super.paint(context, offset);
  }

  /// Performs a filtered paint pass starting from the given render node.
  ///
  /// This method ensures that the [RenderCameraView] itself is not rendered
  /// recursively and applies the camera's culling mask to [GameRenderObject] nodes.
  ///
  /// * [context]: The context for painting.
  /// * [offset]: The offset for the current node.
  /// * [node]: The render object node to paint.
  void _paintFiltered(
    PaintingContext context,
    Offset offset,
    RenderObject node,
  ) {
    if (node == this) return;

    if (_isAncestorOf(node, this)) {
      node.visitChildren((child) {
        Offset childOffset = offset;
        if (child.parentData is BoxParentData) {
          childOffset += (child.parentData as BoxParentData).offset;
        }
        _paintFiltered(context, childOffset, child);
      });
    } else {
      if (node is GameRenderObject) {
        final camera = tagRegistry[cameraTag]?.firstOrNull?.tryGetComponent<Camera>();
        if (camera != null && (node.object.layer & camera.cullingMask) == 0) {
          return;
        }
      }
      context.paintChild(node, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final cameraSystem = game.getSystem<CameraSystem>();
    if (cameraSystem?.isSecondaryPass ?? false) return false;

    final camera = tagRegistry[cameraTag]?.firstOrNull?.tryGetComponent<Camera>();
    if (camera == null || !camera.gameObject.active || !camera.enabled) {
      return super.hitTestChildren(result, position: position);
    }

    final screenSize = game.screen.screenSize;
    if (screenSize == Size.zero) return false;

    if (cameraSystem != null) {
      cameraSystem.isSecondaryPass = true;
    }
    try {
      final viewMatrix = camera.worldToCameraMatrix;
      final projMatrix = camera.projectionMatrix(screenSize);

      final viewportMatrix = Matrix4.identity()
        ..translateByDouble(
          screenSize.width / 2,
          screenSize.height / 2,
          0.0,
          1.0,
        )
        ..scaleByDouble(screenSize.width / 2, -screenSize.height / 2, 1.0, 1.0);

      // Local scaling to fit the RenderBox size
      final localScaleX = size.width / screenSize.width;
      final localScaleY = size.height / screenSize.height;
      final localScaleMatrix = Matrix4.identity()
        ..scaleByDouble(localScaleX, localScaleY, 1.0, 1.0);

      final fullCameraMatrix =
          localScaleMatrix * viewportMatrix * projMatrix * viewMatrix;

      RenderWorldSpace? world;
      RenderObject? current = parent;
      while (current != null) {
        if (current is RenderWorldSpace) {
          world = current;
          break;
        }
        current = current.parent;
      }

      final List<RenderBox> worldRoots = [];
      if (world != null && world.child != null) {
        void findWorldRoots(RenderObject node) {
          if (node is GameRenderObject) {
            if (_isAncestorOf(node, this)) return;
            worldRoots.add(node);
          } else {
            node.visitChildren(findWorldRoots);
          }
        }

        findWorldRoots(world.child!);
      }

      if (worldRoots.isNotEmpty) {
        return result.addWithPaintTransform(
          transform: fullCameraMatrix,
          position: position,
          hitTest: (result, transformedPosition) {
            for (final root in worldRoots) {
              if (root.hitTest(result, position: transformedPosition)) {
                return true;
              }
            }
            return false;
          },
        );
      }

      return super.hitTestChildren(result, position: position);
    } finally {
      if (cameraSystem != null) {
        cameraSystem.isSecondaryPass = false;
      }
    }
  }

  /// Checks if a [RenderObject] is an ancestor of another.
  ///
  /// This is used during painting to determine if we need to continue
  /// traversing down the render tree or if we can paint a node directly.
  ///
  /// * [ancestor]: The potential ancestor node.
  /// * [node]: The potential descendant node.
  bool _isAncestorOf(RenderObject ancestor, RenderObject node) {
    RenderObject? current = node;
    while (current != null) {
      if (current == ancestor) return true;
      current = current.parent;
    }
    return false;
  }
}
