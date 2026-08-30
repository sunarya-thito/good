import 'package:good/good.dart';

import 'package:goo2d/src/data/world_transform.dart';

/// Marks an entity as a camera - a view origin and zoom level, nothing
/// more. An entity with `Camera` must also mix in `Transform2D`/
/// `WorldTransform2D`, and the view centres on the position that resolves
/// to, so there is no separate transform to keep in sync.
///
/// **A camera's rotation is ignored.** [CameraProjection] reads the camera's
/// world x, its world y and [cameraZoom], and nothing else: the same
/// scene drawn through a camera at rotation 0 and through one at rotation
/// pi/2 gives identical geometry. A camera parented to something that turns
/// inherits the turn into its `worldRotation` and still draws upright. A view
/// that banks, or that locks to a subject's facing, has nothing here to build
/// on (#172).
///
/// A camera occupies a [CameraView] - one of the places the game declared it
/// can be drawn - and at most one camera should occupy a given view at a time.
/// [ActiveCameraResolver] finds the camera for a view, and a second one
/// claiming that view trips a debug-only `assert`: a debug run stops there,
/// and a release build compiles the check out and draws through whichever
/// camera the query returned first.
///
/// Setting [cameraView] to null takes a camera out of play - there is no other
/// switch that turns one off. A camera pointing at no view is resolved for no
/// view, and a view left with no camera draws through an implicit one at the
/// world origin with zoom 1.
///
/// A prefab that wants to start zoomed in overrides the column default in
/// its own `describeStruct`:
///
/// ```dart
/// class Player extends EntityStruct with Transform2D, WorldTransform2D, Camera {
///   @override
///   void describeStruct(DataDescriptor data) {
///     super.describeStruct(data);
///     cameraZoom.initialValue = 2;
///   }
/// }
/// ```
mixin Camera on Component {
  /// Screen pixels per world unit. `1` (the default) means one world unit
  /// draws as one pixel; `2` zooms in (things draw twice as large), `0.5`
  /// zooms out.
  final cameraZoom = Field.float64(1);

  /// Which declared view this camera fills, or null for a camera that is not
  /// currently shown anywhere.
  ///
  /// Set it from the game isolate with the handle the game declared:
  ///
  /// ```dart
  /// player.camera.cameraView[entity] = game.mainCamera;
  /// ```
  ///
  /// Typed, and not an int: `CameraView` is a `GlobalObject`, so a stray
  /// integer does not compile here.
  ///
  /// The one field here that still needs [describeStruct]: the view table it
  /// is declared against comes from `getScene`, an instance method a field
  /// initialiser cannot reach.
  late final DataPointer<CameraView?> cameraView;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Camera>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    // The declaring game's own view table - not a shared registry. An address
    // read out of this field means nothing except against this table.
    cameraView = data.optPacked(getScene<SceneStruct>().cameraViews);
  }
}

/// Finds "the" active camera each time [resolve] is called - whichever
/// `Camera`-mixing entity a query returns first. Shared by every consumer
/// that needs to know where the camera is, so "use the active one, complain
/// about a second" is implemented once instead of once per consumer.
///
/// Not a `GameSystem` itself and declares no query of its own - a consuming
/// system builds the query (typically
/// `descriptor.query().withAll(Camera, WorldTransform2D).build()`) and
/// passes it in, since only the consumer knows what else it also needs the
/// result to satisfy.
class ActiveCameraResolver {
  /// Returns the `Camera` entity occupying [view], or `null` if none does.
  ///
  /// More than one camera on [view] trips a debug-only `assert`. In a release
  /// build the assert compiles out and the first camera found is used, so a
  /// second camera is never fatal in production - it is a development-time
  /// mistake that should stop a debug run, not a runtime condition to
  /// tolerate silently.
  Entity? resolve(Query cameras, CameraView view) {
    Entity? first;
    Entity? second;
    for (final entity in cameras.run()) {
      if (entity.get<Camera>().cameraView[entity]?.pack() != view.pack()) {
        continue;
      }
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
/// Those three numbers are [originX], [originY] and [zoom]. **The camera's
/// own rotation is not among them** - see [Camera] - so each axis here maps
/// independently of the other: a view x comes from a world x alone.
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
/// The one thing that does *not* come for free is a drawable's own rotation:
/// composing a quad in view space after the flip turns a positive world
/// rotation the wrong way round, which `GameRenderer2D` compensates for where
/// it takes the sine.
///
/// # The camera sits in the middle of the view
///
/// `view = (world - cameraOrigin) * zoom + viewSize / 2`, y negated. The
/// camera's world position is the *centre* of what you can see, which is
/// what Unity, Godot, Unreal and every other engine mean by a camera
/// position, so a follow camera needs no half-a-screen fudge factor to put
/// its subject in the middle.
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
/// One instance per system, reused every tick: [resolve] only writes fields
/// it already owns, so nothing here allocates (the no-allocation rule).
class CameraProjection {
  final ActiveCameraResolver _resolver = ActiveCameraResolver();

  /// The camera's world x, or `0` when no camera is active.
  double originX = 0;

  /// The camera's world y, or `0` when no camera is active.
  double originY = 0;

  /// The camera's zoom, or `1` when no camera is active.
  double zoom = 1;

  /// Half the view's width, precomputed - the term that puts the camera in
  /// the middle of it. Zero on a game with no widget.
  double halfViewWidth = 0;

  /// Half the view's height. See [halfViewWidth].
  double halfViewHeight = 0;

  /// The left edge of the rectangle [showsCircle] tests against, in
  /// view-space pixels. The rectangle is the whole viewport, `(0, 0)` to
  /// `(viewportWidth, viewportHeight)`.
  ///
  /// **Infinite on all four sides when the view has no size**, which is what
  /// a headless run and a view no `GameView` is showing both report. Zero is
  /// not a degenerate rectangle to cull against - it is "nobody has said how
  /// big this is", and treating it as a rectangle would hide the entire world
  /// from every test that never built a widget, and from the first tick of
  /// every real game, before layout has run once.
  ///
  /// Infinities, and not a `bool` the test branches on: they make "no size
  /// means nothing is culled" a property of the rectangle itself, so there is
  /// no second rule for a caller to forget and no branch on the frame path.
  double viewLeft = double.negativeInfinity;

  /// The top edge of [viewLeft]'s rectangle.
  double viewTop = double.negativeInfinity;

  /// The right edge of [viewLeft]'s rectangle.
  double viewRight = double.infinity;

  /// The bottom edge of [viewLeft]'s rectangle.
  double viewBottom = double.infinity;

  /// The camera [resolve] last found, or `null` if there was none.
  Entity? camera;

  /// Which loaded scene that camera belongs to, or -1 when there is no
  /// camera. A view draws the scene its camera is in - each view answers that
  /// for itself, and two views can be looking at different scenes at the same
  /// instant. There is no global front scene.
  ///
  /// -1 means "no camera, so no scoping" - the whole world draws, which keeps
  /// a game that has not placed a camera yet from showing a black screen.
  int sceneSlot = -1;

  /// Whether this view shows [entity] at all - it is in the scene the view's
  /// camera is in, or there is no camera and nothing is scoped out.
  ///
  /// The rule lives here, not at each call site, because there are two call
  /// sites and they have to agree: `GameRenderer2D` decides what to draw with
  /// it and `PointerPickingSystem` decides what is clickable with it. Split the
  /// rule between them and a click lands on an entity that was never drawn.
  @pragma('vm:prefer-inline')
  bool shows(Entity entity) => sceneSlot < 0 || entity.sceneSlot == sceneSlot;

  /// Whether a circle centred at view-space ([viewX], [viewY]) reaches this
  /// view at all - the viewport-culling test.
  ///
  /// Separate from [shows] and not folded into it, because the two answer
  /// different questions about different things: [shows] is about an entity's
  /// *scene*, this is about one drawable's *geometry*, and an entity with
  /// several sprites gets one answer from the first and one per sprite from
  /// the second.
  ///
  /// [radiusSquared], not the radius. The caller derives the bound from
  /// squares it already has, and taking a square root here only to square it
  /// back would be one per sprite per tick on the frame path.
  ///
  /// # It is conservative, in the one direction that matters
  ///
  /// A false keep costs a quad nobody sees. A false reject is a sprite
  /// missing from the picture, which is a bug a player notices and a test
  /// suite that only checks "the far-away one vanished" does not. So
  /// everything here rounds towards keeping:
  ///
  ///  * The caller's circle encloses the drawn shape instead of tracing it.
  ///  * Touching counts - a sprite whose edge lands exactly on the viewport
  ///    border is kept.
  ///  * NaN in any of the three arguments keeps the sprite. That is why the
  ///    last line rejects on `> radiusSquared` and negates, and does not
  ///    accept on `<=`: the two differ only for NaN, where every
  ///    comparison is false and only the negated form comes out as "keep". A
  ///    transform that has gone wrong should be visibly wrong, not invisible.
  @pragma('vm:prefer-inline')
  bool showsCircle(double viewX, double viewY, double radiusSquared) {
    // Distance from the point to the rectangle, per axis: zero while the
    // point is inside the slab, and how far out it is otherwise. Squared and
    // summed, this is the closest approach of the rectangle to the circle's
    // centre, so the whole test is that against the radius.
    final dx = viewX < viewLeft
        ? viewLeft - viewX
        : viewX > viewRight
        ? viewX - viewRight
        : 0.0;
    final dy = viewY < viewTop
        ? viewTop - viewY
        : viewY > viewBottom
        ? viewY - viewBottom
        : 0.0;
    return !(dx * dx + dy * dy > radiusSquared);
  }

  /// Re-reads the active camera out of [cameras] - typically
  /// `descriptor.query().withAll(Camera, WorldTransform2D).build()` - and
  /// the view size, typically `game.viewWidth`/`game.viewHeight`.
  ///
  /// No camera resets to the identity and does not keep the last one: a
  /// camera that was removed should stop moving the view, not freeze it
  /// wherever it happened to be.
  void resolve(Query cameras, CameraView view) {
    // Off the view, not off the game: two `GameView`s of different sizes
    // cannot share one number, and this is what the projection centres on.
    final viewportWidth = view.viewportWidth;
    final viewportHeight = view.viewportHeight;
    halfViewWidth = viewportWidth / 2;
    halfViewHeight = viewportHeight / 2;
    // Both axes together, not one each: half a rectangle is not a rectangle,
    // and a view reporting a width but no height yet is mid-layout, not a
    // one-pixel-tall thing to cull against.
    if (viewportWidth > 0 && viewportHeight > 0) {
      viewLeft = 0;
      viewTop = 0;
      viewRight = viewportWidth;
      viewBottom = viewportHeight;
    } else {
      viewLeft = double.negativeInfinity;
      viewTop = double.negativeInfinity;
      viewRight = double.infinity;
      viewBottom = double.infinity;
    }
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
    zoom = entity.get<Camera>().cameraZoom[entity];
  }

  /// View-space (a `GameView` pixel, origin at its top-left) to world space.
  ///
  /// A zoom of zero maps the whole world onto one pixel, so the inverse has
  /// no answer; it reports the camera's own origin, because an infinity would
  /// silently poison every downstream comparison.
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
  /// same one and not its own.
  double worldToViewX(double worldX) =>
      (worldX - originX) * zoom + halfViewWidth;

  /// The negation that makes world +y up. It is a sign on the whole term, so
  /// it is a reflection about the view's horizontal midline and not a shift:
  /// the camera's own y still lands exactly on [halfViewHeight].
  double worldToViewY(double worldY) =>
      (originY - worldY) * zoom + halfViewHeight;
}
