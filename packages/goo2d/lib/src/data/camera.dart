import 'package:good/good.dart';

import 'package:goo2d/src/data/world_transform.dart';

/// Marks an entity as a camera - a view origin and zoom level, nothing
/// more. Position/rotation are whatever its own `WorldTransform2D` already
/// resolves to (an entity with `Camera` must also mix in `Transform2D`/
/// `WorldTransform2D`), so there is no separate transform to keep in sync.
///
/// A camera occupies a [CameraView] - one of the places the game declared it
/// can be drawn - and at most one camera should occupy a given view at a time.
/// [ActiveCameraResolver] finds the camera for a view and warns (not throws)
/// if a second claims it, rather than silently picking one with no
/// explanation.
mixin Camera on Component {
  /// World units per screen pixel. `1` (the default) means one world unit
  /// draws as one pixel; `2` zooms in (things draw twice as large), `0.5`
  /// zooms out.
  late final DataPointer<double> zoom;

  /// Which declared view this camera fills, or null for a camera that is not
  /// currently shown anywhere.
  ///
  /// Set it from the game isolate with the handle the game declared:
  ///
  /// ```dart
  /// player.camera.view[entity] = game.mainCamera;
  /// ```
  ///
  /// Typed rather than an int, which is the payoff of `CameraView` being a
  /// `GlobalObject`: a stray integer does not compile here.
  late final DataPointer<CameraView?> view;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Camera>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    zoom = data.hasFloat64(1);
    // The declaring game's own view table - not a shared registry. An address
    // read out of this field means nothing except against this table.
    view = data.optPacked(getScene<SceneStruct>().cameraViews);
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
  /// Returns the `Camera` entity occupying [view], or `null` if none does.
  ///
  /// More than one enabled camera trips a debug-only `assert` rather than a
  /// `print`, which is swallowed in release and invisible in a test runner's
  /// captured output. In a release build the assert
  /// compiles out and the first camera found is used, so a second camera is
  /// never fatal in production - it is a development-time mistake that
  /// should stop a debug run, not a runtime condition to tolerate silently.
  Entity? resolve(Query cameras, CameraView view) {
    Entity? first;
    Entity? second;
    for (final entity in cameras.run()) {
      if (entity.get<Camera>().view[entity]?.pack() != view.pack()) continue;
      if (first == null) {
        first = entity;
      } else {
        second = entity;
        break;
      }
    }
    assert(
      second == null,
      'more than one Camera occupies $view ($first and $second, and possibly '
      'more). A camera defines that view\'s origin, so a second one has no '
      'meaning - $first, the first in query order, is what gets used. Point '
      'the others at a different view, or at none.',
    );
    return first;
  }
}

/// The view <-> world mapping the active camera defines, resolved once and
/// then applied as many times as needed.
///
/// `GameRenderer2D` composes every quad as `view = (world - cameraOrigin) *
/// zoom`, with y additionally negated - see "which way is up" below.
/// Anything that has to go the *other* way - a cursor, a drag, a
/// tap - has to invert exactly that, and "exactly" is the operative word:
/// picking that disagreed with drawing by even a constant would mean
/// clicking next to what you can see. So the forward mapping is written
/// here once, next to the camera it belongs to, and both directions come
/// off the same three numbers.
///
/// # Which way is up
///
/// **World +y is up.** A larger world y draws *higher* on the screen, the
/// same rule `goo3d` uses, so a system written against one dimension means
/// the same thing in the other. Flutter's canvas is y-down, so the y half of
/// the projection carries a negation the x half does not - and this is the
/// only place in the engine that negation lives. Everything downstream
/// (picking, HUD markers, the renderer's own quads) goes through these four
/// methods and inherits it.
///
/// The one thing that does *not* come for free is rotation: composing a quad
/// in view space after the flip turns a positive world rotation the wrong
/// way round, which `GameRenderer2D` compensates for where it takes the sine.
///
/// # The camera sits in the middle of the view
///
/// `view = (world - cameraOrigin) * zoom + viewSize / 2`, y negated. The
/// camera's world position is the *centre* of what you can see, which is
/// what Unity, Godot, Unreal and every other engine mean by a camera
/// position, and it is why a follow camera needs no half-a-screen fudge
/// factor to put its subject in the middle.
///
/// With **no camera** the implicit one is at world (0, 0), so the world
/// origin is the middle of the view - the same rule, not a second one.
/// Adding a camera at the origin therefore changes nothing, which would not
/// be true if "no camera" meant a different anchor.
///
/// The view size comes from the [CameraView] being drawn - the size the
/// `GameView` showing it reported on layout, through that view's own two
/// floats of shared memory. **Per view, not per game**: two `GameView`s of
/// different sizes cannot share one number, because this is what the
/// projection centres on, and a shared number would put one of the two
/// cameras off-centre.
///
/// A headless game (or a view nothing is showing) reports zero and the
/// centring term vanishes - which is what makes a test that never built a
/// widget see plain world coordinates.
///
/// Holds no query of its own for the same reason [ActiveCameraResolver]
/// does not - the consumer knows what else it needs the camera to satisfy.
/// One instance per system, reused every tick: [resolve] only writes three
/// doubles, so nothing here allocates (the no-allocation rule).
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

  /// Which loaded scene that camera belongs to, or -1 when there is no
  /// camera. A view draws the scene its camera is in, which is what replaced
  /// the deleted global "front scene": each view answers it for itself, and
  /// two views can be looking at different scenes at the same instant.
  ///
  /// -1 means "no camera, so no scoping" - the whole world draws, which is
  /// exactly what an unconfigured game already did and keeps a game that has
  /// not placed a camera yet from showing a black screen.
  int sceneSlot = -1;

  /// Re-reads the active camera out of [cameras] - typically
  /// `descriptor.query().withAll(Camera, WorldTransform2D).build()` - and
  /// the view size, typically `game.viewWidth`/`game.viewHeight`.
  ///
  /// No camera resets to the identity rather than keeping the last one:
  /// a camera that was removed should stop moving the view, not freeze it
  /// wherever it happened to be.
  void resolve(Query cameras, CameraView view) {
    // Off the view, not off the game: two `GameView`s of different sizes
    // cannot share one number, which is why this stopped being
    // `Game.viewWidth`.
    halfViewWidth = view.viewportWidth / 2;
    halfViewHeight = view.viewportHeight / 2;
    final entity = _resolver.resolve(cameras, view);
    camera = entity;
    if (entity == null) {
      originX = 0;
      originY = 0;
      zoom = 1;
      sceneSlot = -1;
      return;
    }
    sceneSlot = entity.sceneSlot;
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

  /// Negated against [viewToWorldX], because world +y is up and a
  /// `GameView` pixel's y is down: a click near the top of the view is at a
  /// *larger* world y than one near the bottom.
  double viewToWorldY(double viewY) =>
      zoom == 0 ? originY : originY - (viewY - halfViewHeight) / zoom;

  /// World space to view space - the mapping the renderer applies (it goes
  /// through this very method), exposed so a system placing something *at* a
  /// screen position (a tooltip, a world-space marker for a HUD) uses the
  /// same one rather than its own.
  double worldToViewX(double worldX) =>
      (worldX - originX) * zoom + halfViewWidth;

  /// The negation that makes world +y up. It is a sign on the whole term, so
  /// it is a reflection about the view's horizontal midline and not a shift:
  /// the camera's own y still lands exactly on [halfViewHeight].
  double worldToViewY(double worldY) =>
      (originY - worldY) * zoom + halfViewHeight;
}
