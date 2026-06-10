import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:goo2d/src/game.dart';
import 'package:goo2d/src/event.dart';
import 'package:goo2d/src/pointer.dart';
import 'package:goo2d/src/transform.dart';
import 'package:goo2d/src/physics/components/collider.dart';
import 'package:goo2d/src/object.dart';

/// A mixin that marks a component as capable of drawing to a canvas.
///
/// Components implementing this mixin are automatically notified during the rendering
/// pass via the [render] method. This is the primary way to implement custom visuals
/// for game objects, such as sprites, shapes, or particle effects.
///
/// See also:
/// * [RenderEvent] for the event that triggers the render call.
mixin Renderable implements EventListener {
  /// Draws the component's visuals to the provided [canvas].
  ///
  /// This method is called once per frame for every active [Renderable] component.
  /// Use the [canvas] object to perform drawing operations like `drawRect`,
  /// `drawImage`, or `drawPath`. The canvas coordinate system is typically
  /// relative to the component's transform.
  ///
  /// * [canvas]: The canvas to draw onto.
  void render(Canvas canvas);
}

/// An event that triggers the rendering of [Renderable] components.
///
/// This event encapsulates the [Canvas] provided by Flutter's rendering pipeline
/// and dispatches it to all [Renderable] listeners on a game object. It ensures
/// that the drawing context is correctly propagated through the object hierarchy.
///
/// ```dart
/// void example(Canvas canvas, GameObject object) {
///   final event = RenderEvent(canvas);
///   event.dispatchTo(object);
/// }
/// ```
///
/// See also:
/// * [Renderable] for the interface that receives this event.
/// * [Event] for the base event class.
class RenderEvent extends Event<Renderable> {
  /// The canvas context for the current render pass.
  ///
  /// This field provides access to the low-level drawing API. It should be
  /// used within the [Renderable.render] implementation to perform visual updates.
  final Canvas canvas;

  /// Creates a new [RenderEvent] with the specified [canvas].
  ///
  /// * [canvas]: The drawing surface for this render pass.
  const RenderEvent(this.canvas);

  @override
  void dispatch(Renderable listener) {
    listener.render(canvas);
  }
}

/// A utility class defining common rendering layers for game objects.
///
/// Layers are used to organize objects into logical groups for rendering and
/// culling. For example, a camera might be configured to only render objects
/// on the [world] layer, while ignoring those on the [ui] layer.
///
/// These bitmask values allow for complex culling setups where an object can
/// belong to multiple layers simultaneously or a camera can render a subset
/// of the total scene.
///
/// ```dart
/// void example(GameObject object) {
///   object.layer = RenderLayer.world | RenderLayer.ui;
/// }
/// ```
///
/// See also:
/// * [GameObject.layer] for the property that uses these values.
class RenderLayer {
  /// No rendering layer assigned.
  ///
  /// This value is used when an object should be effectively hidden from all
  /// cameras, regardless of their culling mask configuration.
  static const int none = 0;

  /// The default layer for most game objects.
  ///
  /// This is the layer assigned to new entities by default. It ensures they
  /// are visible to standard cameras without requiring manual layer management.
  static const int defaultLayer = 1 << 0;

  /// Alias for [defaultLayer], typically used for in-game entities.
  ///
  /// This name provides semantic clarity when distinguishing between game
  /// world objects and user interface elements.
  static const int world = 1 << 0;

  /// The layer dedicated to user interface elements.
  ///
  /// UI components should be placed on this layer to separate them from the
  /// game world, allowing for specialized rendering or input handling.
  static const int ui = 1 << 1;

  /// A mask that includes all possible rendering layers.
  ///
  /// Use this value in a camera's culling mask to ensure that all objects
  /// in the scene are rendered regardless of their individual layer assignments.
  static const int all = 0xFFFFFFFF;

  RenderLayer._();
}

/// Data associated with a [GameRenderObject] when it is a child of another [GameRenderObject].
///
/// This class stores layout-related information required by the container-based
/// rendering mixins. It enables the efficient management of child render objects
/// within the game engine's custom rendering pipeline.
///
/// ```dart
/// void example() {
///   final parentData = GameParentData();
///   // Parent data is typically managed automatically by the engine
/// }
/// ```
///
/// See also:
/// * [GameRenderObject] for the class that utilizes this parent data.
class GameParentData extends ContainerBoxParentData<RenderBox> {}

/// A custom [RenderBox] that bridges the game engine with Flutter's rendering system.
///
/// [GameRenderObject] is responsible for translating the game object hierarchy into
/// Flutter's layout and paint phases. It uses the attached [GameObject] to
/// determine the size, transform, and visual content of the entity during rendering.
///
/// ```dart
/// void example(GameObject object) {
///   final renderObject = GameRenderObject(object);
///   // The render object is typically managed by a GameWidget
/// }
/// ```
///
/// See also:
/// * [GameObject] for the entity that provides the data for this render object.
class GameRenderObject extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, GameParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, GameParentData>
    implements MouseTrackerAnnotation {
  /// The game object associated with this render object.
  ///
  /// This field provides the render object with access to the entity's components
  /// and hierarchy, enabling it to retrieve layout and paint information. It
  /// acts as the bridge between Flutter's render tree and the game's logic.
  GameObject object;

  /// Creates a new [GameRenderObject] for the specified [object].
  ///
  /// This constructor initializes the render object with its corresponding
  /// game entity. The [object] must be valid and remains the source of truth
  /// for the render object's lifecycle.
  ///
  /// * [object]: The game object that this render object will represent in the
  /// Flutter rendering tree.
  GameRenderObject(this.object);

  @override
  PointerEnterEventListener? get onEnter =>
      (event) => object.broadcastEvent(GamePointerEnterEvent(event));

  @override
  PointerExitEventListener? get onExit =>
      (event) => object.broadcastEvent(GamePointerExitEvent(event));

  @override
  MouseCursor get cursor => MouseCursor.defer;

  @override
  bool get validForMouseTracker => true;

  @override
  void setupParentData(covariant RenderObject child) {
    if (child.parentData is! GameParentData) {
      child.parentData = GameParentData();
    }
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final transform = object.tryGetComponent<ObjectTransform>();
    if (transform != null) {
      return transform.getSize(constraints);
    }
    return constraints.constrain(Size.infinite);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return object.tryGetComponent<ObjectTransform>()?.computeMaxIntrinsicHeight(
          width,
        ) ??
        0;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return object.tryGetComponent<ObjectTransform>()?.computeMaxIntrinsicWidth(
          height,
        ) ??
        0;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return object.tryGetComponent<ObjectTransform>()?.computeMinIntrinsicHeight(
          width,
        ) ??
        0;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return object.tryGetComponent<ObjectTransform>()?.computeMinIntrinsicWidth(
          height,
        ) ??
        0;
  }

  @override
  void performLayout() {
    final transform = object.tryGetComponent<ObjectTransform>();
    final objectSize =
        transform?.getSize(constraints) ?? constraints.constrain(Size.infinite);
    final childConstraints =
        transform?.getChildConstraints(constraints) ?? constraints.loosen();

    RenderObject? child = firstChild;
    while (child != null) {
      child.layout(childConstraints);
      child = (child.parentData as GameParentData).nextSibling;
    }
    size = objectSize.isInfinite ? Size.zero : objectSize;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final cameraSystem = object.game.getSystem<CameraSystem>();
    final camera = cameraSystem?.currentRenderCamera;
    if (camera != null && (object.layer & camera.cullingMask) == 0) {
      return;
    }

    final optionalTransform = object.tryGetComponent<ObjectTransform>();

    if (optionalTransform != null) {
      final screenSize = object.game.screen.screenSize;
      final paintMatrix = optionalTransform.getPaintMatrix(
        object.game,
        screenSize,
      );

      if (cameraSystem?.isSecondaryPass ?? false || !needsCompositing) {
        context.canvas.save();
        context.canvas.translate(offset.dx, offset.dy);
        context.canvas.transform(paintMatrix.storage);

        RenderEvent(context.canvas).dispatchTo(object);
        defaultPaint(context, Offset.zero);
        context.canvas.restore();
      } else {
        layer = context.pushTransform(
          needsCompositing,
          offset,
          paintMatrix,
          (context, offset) {
            RenderEvent(context.canvas).dispatchTo(object);
            defaultPaint(context, offset);
          },
        );
      }
    } else {
      context.canvas.save();
      context.canvas.translate(offset.dx, offset.dy);
      RenderEvent(context.canvas).dispatchTo(object);
      context.canvas.restore();
      defaultPaint(context, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final optionalTransform = object.tryGetComponent<ObjectTransform>();
    if (optionalTransform != null) {
      final screenSize = object.game.screen.screenSize;
      final paintMatrix = optionalTransform.getPaintMatrix(
        object.game,
        screenSize,
      );
      return result.addWithPaintTransform(
        transform: paintMatrix,
        position: position,
        hitTest: (BoxHitTestResult result, Offset? transformedPosition) {
          if (transformedPosition == null) return false;
          final childrenHit = hitTestChildren(
            result,
            position: transformedPosition,
          );
          if (hitTestSelf(transformedPosition)) {
            result.add(BoxHitTestEntry(this, transformedPosition));
            return true;
          }
          return childrenHit;
        },
      );
    }

    final childrenHit = hitTestChildren(result, position: position);
    if (hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return childrenHit;
  }

  @override
  bool hitTestSelf(Offset position) {
    for (var component in object.getComponents<Collider>()) {
      if (component.containsPoint(position)) {
        return true;
      }
    }
    return false;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      object.broadcastEvent(GamePointerDownEvent(event));
    } else if (event is PointerUpEvent) {
      object.broadcastEvent(GamePointerUpEvent(event));
    } else if (event is PointerMoveEvent) {
      object.broadcastEvent(GamePointerMoveEvent(event));
    } else if (event is PointerCancelEvent) {
      object.broadcastEvent(GamePointerCancelEvent(event));
    } else if (event is PointerHoverEvent) {
      object.broadcastEvent(GamePointerHoverEvent(event));
    }
  }
}
