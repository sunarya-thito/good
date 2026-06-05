import 'dart:ui';
import 'package:flutter/material.dart' show Colors;
import 'package:meta/meta.dart';
import 'package:goo2d/src/game.dart';
import 'package:goo2d/src/component.dart';
import 'package:goo2d/src/lifecycle.dart';
import 'package:goo2d/src/transform.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

/// Specifies how a camera clears the frame buffer before rendering.
///
/// This enum determines what pixels are present in the viewport before any
/// game objects are drawn. It is essential for optimizing performance and
/// achieving specific visual effects, such as UI overlays or complex skyboxes.
enum CameraClearFlags {
  /// Clears the background using a single solid [backgroundColor].
  ///
  /// This is the most common flag for 2D games, providing a clean slate for
  /// the next frame's rendering.
  solidColor,

  /// Clears only the depth buffer, preserving previous color data.
  ///
  /// This is useful for multi-camera setups where one camera draws on top
  /// of the results of another camera without erasing its pixels.
  depth,

  /// Does not clear any buffers before rendering.
  ///
  /// This can be used for optimization when it is guaranteed that the entire
  /// screen will be overdrawn, or for intentional 'hall of mirrors' effects.
  nothing,
}

/// A component that defines the perspective and viewport for rendering the scene.
///
/// The [Camera] component is responsible for transforming [GameObject] coordinates
/// from world space to screen space. It controls which objects are visible
/// (via [cullingMask]) and how they are projected onto the display. A scene
/// can have multiple cameras, which are processed in order of their [depth].
///
/// Typically, a single camera is attached to a "Main Camera" object. For UI
/// or split-screen effects, additional cameras can be configured with
/// specific [clearFlags] and [cullingMask] settings.
///
/// ```dart
/// class MyScene extends Behavior with LifecycleListener {
///   @override
///   void onMounted() {
///     addComponent(Camera()
///       ..orthographicSize = 15.0
///       ..backgroundColor = Colors.blueGrey);
///   }
/// }
/// ```
///
/// See also:
/// * [GameObject] for the containers that hold camera components.
/// * [CameraView] for the widget that displays camera output.
class Camera extends Behavior with LifecycleListener {
  /// The vertical size of the camera's orthographic view.
  ///
  /// This value represents half of the total vertical height in world units.
  /// For example, a size of 10.0 means the camera will see 20.0 units from
  /// top to bottom. The horizontal width is calculated based on the aspect ratio.
  double orthographicSize = 10.0;

  /// The background color used when [clearFlags] is [CameraClearFlags.solidColor].
  ///
  /// This color fills the entire viewport before any scene objects are
  /// rendered. It can be transparent if the camera is intended to be
  /// layered over other UI elements or cameras.
  Color backgroundColor = Colors.transparent;

  /// The clearing strategy to use before the camera begins rendering.
  ///
  /// This determines how the frame buffer is initialized. See [CameraClearFlags]
  /// for details on the available options and their use cases.
  CameraClearFlags clearFlags = CameraClearFlags.solidColor;

  /// A bitmask that determines which layers this camera will render.
  ///
  /// Each [GameObject] has a layer assigned to it. The camera will only
  /// process objects whose layer bit is set in this mask. A value of -1
  /// indicates that all layers should be rendered.
  int cullingMask = -1;

  /// The distance to the near clipping plane.
  ///
  /// Objects closer to the camera than this distance will be clipped and
  /// not rendered. In 2D, this is typically set to a large negative value.
  double nearClipPlane = -100.0;

  /// The distance to the far clipping plane.
  ///
  /// Objects further from the camera than this distance will be clipped and
  /// not rendered. In 2D, this is typically set to a large positive value.
  double farClipPlane = 100.0;

  double _depth = 0.0;

  Matrix4? _cachedProjectionMatrix;
  Size? _cachedProjectionSize;
  double? _cachedOrthographicSize;

  Matrix4? _cachedFullMatrix;
  Matrix4? _cachedFullMatrixInverse;
  Size? _cachedFullMatrixSize;
  int? _cachedFullMatrixTransformVersion;

  /// The rendering priority of the camera.
  ///
  /// Cameras with lower depth values are rendered first. If multiple cameras
  /// cover the same screen area, the one with the highest depth will appear
  /// on top.
  double get depth => _depth;

  /// Sets the rendering priority of the camera.
  ///
  /// Updating this value will trigger a reorganization of the rendering
  /// order in the [CameraSystem]. Higher values ensure this camera renders
  /// after (and thus on top of) cameras with lower values.
  ///
  /// * [value]: The new depth priority for this camera.
  set depth(double value) {
    if (_depth == value) return;
    _depth = value;
    if (isAttached) {
      game.getSystem<CameraSystem>()?.notifyDepthChanged();
    }
  }

  @override
  void onMounted() {
    game.getSystem<CameraSystem>()?.registerCamera(this);
  }

  @override
  void onUnmounted() {
    game.getSystem<CameraSystem>()?.unregisterCamera(this);
  }

  /// The matrix that transforms coordinates from world space to camera space.
  ///
  /// This is effectively the inverse of the camera's [GameObject] transform.
  /// It is used to position the world relative to the camera's "eye".
  Matrix4 get worldToCameraMatrix {
    final transform = gameObject.tryGetComponent<ObjectTransform>();
    if (transform == null) return Matrix4.identity();
    return transform.worldInverse;
  }

  /// The matrix that transforms coordinates from camera space to world space.
  ///
  /// This corresponds to the world matrix of the camera's [GameObject].
  /// It can be used to determine where a point in front of the camera lies
  /// in the global scene.
  Matrix4 get cameraToWorldMatrix {
    final transform = gameObject.tryGetComponent<ObjectTransform>();
    if (transform == null) return Matrix4.identity();
    return transform.worldMatrix;
  }

  /// Calculates the projection matrix for a given screen size.
  ///
  /// This matrix maps camera-space coordinates to normalized device
  /// coordinates (NDC). It accounts for the [orthographicSize] and the
  /// clipping planes. The result is cached to avoid redundant calculations.
  ///
  /// * [screenSize]: The current dimensions of the rendering surface.
  Matrix4 projectionMatrix(Size screenSize) {
    if (_cachedProjectionMatrix != null &&
        _cachedProjectionSize == screenSize &&
        _cachedOrthographicSize == orthographicSize) {
      return _cachedProjectionMatrix!;
    }

    final aspect = screenSize.width / screenSize.height;
    final halfHeight = orthographicSize;
    final halfWidth = halfHeight * aspect;
    final r = Matrix4.identity();
    setOrthographicMatrix(
      r,
      -halfWidth,
      halfWidth,
      -halfHeight,
      halfHeight,
      nearClipPlane,
      farClipPlane,
    );

    _cachedProjectionMatrix = r;
    _cachedProjectionSize = screenSize;
    _cachedOrthographicSize = orthographicSize;

    return r;
  }

  @internal
  /// Computes the combined projection and view matrix.
  ///
  /// * [screenSize]: The current dimensions of the rendering surface.
  Matrix4 getFullMatrix(Size screenSize) {
    final transform = gameObject.tryGetComponent<ObjectTransform>();
    final transformVersion = transform?.version ?? -1;

    if (_cachedFullMatrix != null &&
        _cachedFullMatrixSize == screenSize &&
        _cachedFullMatrixTransformVersion == transformVersion &&
        _cachedOrthographicSize == orthographicSize) {
      return _cachedFullMatrix!;
    }

    final viewMatrix = transform == null
        ? Matrix4.identity()
        : transform.worldInverse;
    final projMatrix = projectionMatrix(screenSize);

    final viewportMatrix = Matrix4.identity()
      ..translateByDouble(screenSize.width / 2, screenSize.height / 2, 0.0, 1.0)
      ..scaleByDouble(screenSize.width / 2, -screenSize.height / 2, 1.0, 1.0);

    _cachedFullMatrix = viewportMatrix * projMatrix * viewMatrix;
    _cachedFullMatrixInverse = null; // Clear inverse cache
    _cachedFullMatrixSize = screenSize;
    _cachedFullMatrixTransformVersion = transformVersion;

    return _cachedFullMatrix!;
  }

  @internal
  /// Computes the inverse of the full transformation matrix.
  ///
  /// * [screenSize]: The current dimensions of the rendering surface.
  Matrix4 getFullMatrixInverse(Size screenSize) {
    if (_cachedFullMatrixInverse != null &&
        _cachedFullMatrixSize == screenSize &&
        _cachedFullMatrixTransformVersion ==
            (gameObject.tryGetComponent<ObjectTransform>()?.version ?? -1) &&
        _cachedOrthographicSize == orthographicSize) {
      return _cachedFullMatrixInverse!;
    }

    final full = getFullMatrix(screenSize);
    _cachedFullMatrixInverse = Matrix4.inverted(full);
    return _cachedFullMatrixInverse!;
  }

  /// Transforms a point from world space to pixel-perfect screen space.
  ///
  /// This method applies the full projection and view transformation to
  /// determine where a specific world position appears on the physical
  /// display, given the provided [screenSize].
  ///
  /// * [worldPoint]: The global coordinate to transform.
  /// * [screenSize]: The current dimensions of the rendering surface.
  Vector2 worldToScreenPoint(Vector2 worldPoint, Size screenSize) {
    final fullMatrix = getFullMatrix(screenSize);
    final worldVec = Vector4(worldPoint.x, worldPoint.y, 0.0, 1.0);
    final screenVec = fullMatrix.transform(worldVec);

    return Vector2(screenVec.x / screenVec.w, screenVec.y / screenVec.w);
  }

  /// Transforms a point from screen space (pixels) back to world space.
  ///
  /// This is commonly used for input handling, such as determining which
  /// game object was clicked. It uses the inverse of the camera's full
  /// transformation matrix to project screen coordinates into the scene.
  ///
  /// * [screenPoint]: The pixel coordinate on the display.
  /// * [screenSize]: The current dimensions of the rendering surface.
  Vector2 screenToWorldPoint(Vector2 screenPoint, Size screenSize) {
    final invMatrix = getFullMatrixInverse(screenSize);
    final screenVec = Vector4(screenPoint.x, screenPoint.y, 0.0, 1.0);
    final worldVec = invMatrix.transform(screenVec);

    return Vector2(worldVec.x / worldVec.w, worldVec.y / worldVec.w);
  }
}
