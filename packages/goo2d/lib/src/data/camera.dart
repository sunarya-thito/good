
import 'package:goo/goo.dart';

import 'package:goo2d/src/data/world_transform.dart';
/// Marks an entity as a camera - a view origin and zoom level, nothing
/// more. Position/rotation are whatever its own `WorldTransform2D` already
/// resolves to (an entity with `Camera` must also mix in `Transform2D`/
/// `WorldTransform2D`), so there is no separate transform to keep in sync.
///
/// At most one enabled `Camera` should exist at a time. Consumers (
/// `GameRenderer2D`; `MouseBinding`'s `worldSpace`
/// conversion) use [ActiveCameraResolver] to find "the"
/// active one and warn - not throw - if a second is found, rather than
/// silently picking one with no explanation.
mixin Camera on Component {
  /// World units per screen pixel. `1` (the default) means one world unit
  /// draws as one pixel; `2` zooms in (things draw twice as large), `0.5`
  /// zooms out.
  late final DataPointer<double> zoom;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Camera>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    zoom = data.hasFloat64(1);
  }
}

/// Finds "the" active camera each time [resolve] is called - whichever
/// `Camera`-mixing entity a query returns first. Shared by every consumer
/// that needs to know where the camera is, so "use the active one, complain
/// about a second" is implemented once rather than once per consumer.
///
/// Not a `GameSystem` itself and declares no query of its own - a consuming
/// system builds the query (typically
/// `descriptor.query().withAll(Camera, WorldTransform2D).build()`) and
/// passes it in, since only the consumer knows what else it also needs the
/// result to satisfy.
class ActiveCameraResolver {
  /// Returns the first `Camera` entity [cameras] yields, or `null` if none
  /// is currently active.
  ///
  /// More than one enabled camera trips a debug-only `assert` (RULES.md
  /// rule 7 - never `print`, which is swallowed in release and invisible in
  /// a test runner's captured output). In a release build the assert
  /// compiles out and the first camera found is used, so a second camera is
  /// never fatal in production - it is a development-time mistake that
  /// should stop a debug run, not a runtime condition to tolerate silently.
  Entity? resolve(Query cameras) {
    Entity? first;
    Entity? second;
    for (final entity in cameras.run()) {
      if (first == null) {
        first = entity;
      } else {
        second = entity;
        break;
      }
    }
    assert(
      second == null,
      'more than one Camera is enabled at once ($first and $second, and '
      'possibly more). A camera defines the single view origin, so a second '
      'one has no meaning - $first, the first in query order, is what gets '
      'used. Disable the others.',
    );
    return first;
  }
}

/// The view <-> world mapping the active camera defines, resolved once and
/// then applied as many times as needed.
///
/// `GameRenderer2D` composes every quad as `view = (world - cameraOrigin) *
/// zoom`. Anything that has to go the *other* way - a cursor, a drag, a
/// tap - has to invert exactly that, and "exactly" is the operative word:
/// picking that disagreed with drawing by even a constant would mean
/// clicking next to what you can see. So the forward mapping is written
/// here once, next to the camera it belongs to, and both directions come
/// off the same three numbers.
///
/// # The camera sits in the middle of the view
///
/// `view = (world - cameraOrigin) * zoom + viewSize / 2`. The camera's world
/// position is the *centre* of what you can see, which is what Unity, Godot,
/// Unreal and every other engine mean by a camera position, and it is why a
/// follow camera needs no half-a-screen fudge factor to put its subject in
/// the middle.
///
/// With **no camera** the implicit one is at world (0, 0), so the world
/// origin is the middle of the view - the same rule, not a second one.
/// Adding a camera at the origin therefore changes nothing, which would not
/// be true if "no camera" meant a different anchor.
///
/// [viewWidth]/[viewHeight] come from `Game.viewWidth`, i.e. from the
/// Flutter isolate through the input block. A headless game reports zero and
/// the centring term vanishes - which is what makes a test that never built
/// a widget see plain world coordinates.
///
/// Holds no query of its own for the same reason [ActiveCameraResolver]
/// does not - the consumer knows what else it needs the camera to satisfy.
/// One instance per system, reused every tick: [resolve] only writes three
/// doubles, so nothing here allocates (RULES.md rule 1).
class CameraProjection {
  final ActiveCameraResolver _resolver = ActiveCameraResolver();

  /// The camera's world position, or `(0, 0)` when no camera is active.
  double originX = 0;
  double originY = 0;

  /// The camera's zoom, or `1` when no camera is active.
  double zoom = 1;

  /// Half the view, precomputed - the term that puts the camera in the
  /// middle. Zero on a game with no widget.
  double halfViewWidth = 0;
  double halfViewHeight = 0;

  /// The camera [resolve] last found, or `null` if there was none.
  Entity? camera;

  /// Re-reads the active camera out of [cameras] - typically
  /// `descriptor.query().withAll(Camera, WorldTransform2D).build()` - and
  /// the view size, typically `game.viewWidth`/`game.viewHeight`.
  ///
  /// No camera resets to the identity rather than keeping the last one:
  /// a camera that was removed should stop moving the view, not freeze it
  /// wherever it happened to be.
  void resolve(Query cameras, double viewWidth, double viewHeight) {
    halfViewWidth = viewWidth / 2;
    halfViewHeight = viewHeight / 2;
    final entity = _resolver.resolve(cameras);
    camera = entity;
    if (entity == null) {
      originX = 0;
      originY = 0;
      zoom = 1;
      return;
    }
    final world = entity.get<WorldTransform2D>();
    originX = world.worldX[entity];
    originY = world.worldY[entity];
    zoom = entity.get<Camera>().zoom[entity];
  }

  /// View-space (a `GameView` pixel, origin at its top-left) to world space.
  ///
  /// A zoom of zero maps the whole world onto one pixel, so the inverse has
  /// no answer; it reports the camera's own origin rather than an infinity
  /// that would poison every downstream comparison silently.
  double viewToWorldX(double viewX) =>
      zoom == 0 ? originX : (viewX - halfViewWidth) / zoom + originX;

  double viewToWorldY(double viewY) =>
      zoom == 0 ? originY : (viewY - halfViewHeight) / zoom + originY;

  /// World space to view space - the mapping the renderer applies (it goes
  /// through this very method), exposed so a system placing something *at* a
  /// screen position (a tooltip, a world-space marker for a HUD) uses the
  /// same one rather than its own.
  double worldToViewX(double worldX) =>
      (worldX - originX) * zoom + halfViewWidth;

  double worldToViewY(double worldY) =>
      (worldY - originY) * zoom + halfViewHeight;
}
