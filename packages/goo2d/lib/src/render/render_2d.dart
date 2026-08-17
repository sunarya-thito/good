import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:goo/goo.dart';
import 'package:goo2d/src/data/camera.dart';
import 'package:goo2d/src/data/world_transform.dart';
import 'package:goo2d/src/data/transform.dart';
import 'package:goo2d/src/render/draw/draw_2d.dart';
// Mutual with this file, and deliberately so: `Renderer2D` and
// `GameRenderer2D` are the two isolate-halves of one feature. The Game mixin
// declares and drains the frame buffers; this system fills them.
import 'package:goo2d/src/render/game_2d.dart';
import 'package:goo2d/src/render/texture.dart';
import 'package:meta/meta.dart';

/// A position expressed as a fraction of some size *plus* an absolute offset,
/// evaluated as `fraction * size + offset`.
///
/// Both halves at once, deliberately. "Half way across, and then 200 units
/// further" is a single sentence in every UI system worth copying (CSS
/// `calc(50% + 200px)`, Unity's `RectTransform` anchor + `anchoredPosition`,
/// Flutter's `FractionalOffset` alongside `Offset`), and a type that offered
/// only one of the two would force every caller that needs both to bake the
/// size into a constant at declare time - which is exactly the number that is
/// not known at declare time. So [fractionX]/[fractionY] scale with the size
/// this is resolved against and [offsetX]/[offsetY] do not, and the resolved
/// answer is the sum.
///
/// # This is a parameter type, never a storage type
///
/// A `DataPointer<T>` holds a `num` or a `GlobalObject` and nothing else (see
/// `goo`'s `data.dart`), so no component row anywhere stores a
/// `RelativeOffset2D`. This type exists to make *declaring* a default
/// readable (`pivot: RelativeOffset2D.center`) and to make a runtime change
/// one call instead of four (`sprite.setPivot(entity, ...)`); the storage
/// underneath is always four separate `DataPointer<double>` fields, and a
/// *read* returns those four fields individually. There is no
/// `getPivot(entity)` returning one of these, and there should not be:
/// building one per read is a heap allocation on the hot path, which RULES.md
/// rule 1 forbids outright.
class RelativeOffset2D {
  const RelativeOffset2D({
    this.fractionX = 0,
    this.fractionY = 0,
    this.offsetX = 0,
    this.offsetY = 0,
  });

  /// Multiplied by the size this is resolved against.
  final double fractionX;
  final double fractionY;

  /// Added afterwards, in world units, independent of that size.
  final double offsetX;
  final double offsetY;

  /// The middle of whatever this is resolved against - a sprite's own bounds,
  /// for a pivot. The default pivot, and what makes rotation and scale act
  /// about a sprite's centre.
  static const RelativeOffset2D center = RelativeOffset2D(
    fractionX: 0.5,
    fractionY: 0.5,
  );

  /// Top-left, with no offset - the default alignment, and the pivot that
  /// puts the transform origin on the sprite's own top-left corner.
  static const RelativeOffset2D zero = RelativeOffset2D();
}

/// The four insets of a nine-slice: how far in from each edge the stretchable
/// middle region starts.
///
/// All-zero (the default, [none]) means there is nothing to slice and the
/// sprite is a single quad - which is why [isEmpty] exists as a named
/// question rather than as four inline comparisons at each call site.
class NineSliceBorder {
  const NineSliceBorder({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  /// The common case for a symmetric frame: the same inset on all four edges.
  const NineSliceBorder.all(double inset)
    : left = inset,
      top = inset,
      right = inset,
      bottom = inset;

  final double left;
  final double top;
  final double right;
  final double bottom;

  /// No slicing - a plain single quad.
  static const NineSliceBorder none = NineSliceBorder();

  /// True when every inset is zero, i.e. this sprite is a plain quad. The
  /// renderer branches on the *stored* fields rather than on an instance of
  /// this class; see [Sprite.borderLeft].
  bool get isEmpty => left == 0 && top == 0 && right == 0 && bottom == 0;
}

/// One drawable rectangle belonging to an entity - what a single
/// [SpriteDescriptor.has] call declares and returns.
///
/// An entity draws as many of these as it declared: a body plus a hat is two
/// `has()` calls, two independent sets of row fields, and two draw records.
/// That is the whole reason [Renderable2D] is a `MultiComponent` and these
/// fields do not live on the mixin itself - Dart cannot mix a mixin in twice,
/// so a second sprite has to come from a second `has()` rather than from a
/// second `with Renderable2D` (see `MultiComponent`'s own doc in `goo`, and
/// `Collider2D`/`ColliderBody`, which are the same shape for the same
/// reason).
///
/// # Why the four-field groups
///
/// [pivotFractionX]/[pivotFractionY]/[pivotOffsetX]/[pivotOffsetY] are one
/// conceptual [RelativeOffset2D] stored as four `DataPointer<double>`s, and
/// the alignment and border groups likewise. That is forced, not stylistic: a
/// `DataPointer<T>` stores a `num` or a `GlobalObject` and cannot hold a value
/// object of any kind. [setPivot]/[setAlignment]/[setNineSliceBorder] hide the
/// unpacking for writes; reads are the four fields, by design (see
/// [RelativeOffset2D]'s doc - a read that returned a fresh value object would
/// allocate per read, on the hot path).
class Sprite {
  Sprite({
    required this.texture,
    required this.filter,
    required this.color,
    required this.width,
    required this.height,
    required this.zIndex,
    required this.visible,
    required this.pivotFractionX,
    required this.pivotFractionY,
    required this.pivotOffsetX,
    required this.pivotOffsetY,
    required this.alignFractionX,
    required this.alignFractionY,
    required this.alignOffsetX,
    required this.alignOffsetY,
    required this.borderLeft,
    required this.borderTop,
    required this.borderRight,
    required this.borderBottom,
  });

  /// The image this sprite samples, or `null` for "no texture - draw the flat
  /// [color]".
  ///
  /// Nullable rather than "a 1x1 white texture everyone falls back to",
  /// because the untextured case is not a degenerate texture: it is the whole
  /// of what the pipeline draws today, and a null here is one branch rather
  /// than an asset every game is forced to declare.
  ///
  /// Stored as the asset's address (`optPacked`), which is the same
  /// integer on both isolates - see `Texture`'s own doc on why the game
  /// isolate holds an addressed-but-never-decoded copy.
  final DataPointer<TextureAsset?> texture;

  /// How this sprite samples [texture] - a [TextureFilter] index.
  ///
  /// Per sprite, not per texture, and not per game. It used to be declared on
  /// the texture key, which made sampling part of an asset's *identity*: a
  /// build step that repacked an image would have been rewriting it, and one
  /// image could not be drawn crisply in one place and smoothly in another.
  /// This is strictly wider - a game can still give every sprite sharing an
  /// image the same filter.
  ///
  /// Two bits, because there are three [TextureFilter] values and a row pays
  /// for every one of them per entity.
  final DataPointer<int> filter;

  /// Packed ARGB, the same encoding `Color.value` and `Vertices.raw`'s colour
  /// list use. A plain `uint32` rather than a `Color` object for the obvious
  /// reason - a component row never holds a Dart heap reference.
  ///
  /// With a [texture] set this is the tint; with none it is the fill.
  final DataPointer<int> color;

  /// Extent in world units, before the transform's scale. Zero on either axis
  /// (the declared default) means "nothing to draw" and is skipped, so a
  /// declared-but-unsized sprite costs one branch per tick.
  final DataPointer<double> width;
  final DataPointer<double> height;

  /// Painter's-algorithm depth. Lower draws first (further back), higher
  /// draws later (in front); equal values keep query/declaration order. See
  /// [GameRenderer2D]'s ordering section.
  final DataPointer<int> zIndex;

  /// `0`/`1`. A hidden sprite produces no draw record at all - not a
  /// transparent one. `DataPointer<int>` and not `DataPointer<bool>` because
  /// this engine has no boolean field kind; a `uint1` is the standing
  /// convention (see `ColliderBody.enable`).
  final DataPointer<int> visible;

  /// Where the transform origin sits *within this sprite's own bounds*,
  /// resolved against `(width, height)` as `fraction * size + offset`.
  ///
  /// Centred by default (`0.5, 0.5`), which is what makes rotation and scale
  /// act about the sprite's middle. `fractionX: 0, fractionY: 0` puts the
  /// origin on the top-left corner, so the sprite extends right and down from
  /// the entity's position.
  final DataPointer<double> pivotFractionX;
  final DataPointer<double> pivotFractionY;
  final DataPointer<double> pivotOffsetX;
  final DataPointer<double> pivotOffsetY;

  /// Where this sprite is anchored *relative to its parent or the viewport*,
  /// resolved against that container's size as `fraction * size + offset`.
  ///
  /// Distinct from the pivot, and the two compose: the pivot picks a point on
  /// the sprite, the alignment picks the point in the container that point is
  /// placed at. Declared and stored but **not yet applied** by
  /// [GameRenderer2D] - see that class's "Alignment" section for exactly what
  /// is missing and what would consume it.
  final DataPointer<double> alignFractionX;
  final DataPointer<double> alignFractionY;
  final DataPointer<double> alignOffsetX;
  final DataPointer<double> alignOffsetY;

  /// Nine-slice insets, all zero by default - which means "plain single
  /// quad", the only thing generated today. Quad generation for a non-empty
  /// border is a follow-up; see [GameRenderer2D]'s note.
  final DataPointer<double> borderLeft;
  final DataPointer<double> borderTop;
  final DataPointer<double> borderRight;
  final DataPointer<double> borderBottom;

  /// Writes all four pivot fields at once. The declared default (from
  /// [SpriteDescriptor.has]) already covers the common case; this is for
  /// changing a pivot at runtime without poking four fields by hand.
  void setPivot(Entity entity, RelativeOffset2D pivot) {
    pivotFractionX[entity] = pivot.fractionX;
    pivotFractionY[entity] = pivot.fractionY;
    pivotOffsetX[entity] = pivot.offsetX;
    pivotOffsetY[entity] = pivot.offsetY;
  }

  /// Writes all four alignment fields at once. See [setPivot].
  void setAlignment(Entity entity, RelativeOffset2D alignment) {
    alignFractionX[entity] = alignment.fractionX;
    alignFractionY[entity] = alignment.fractionY;
    alignOffsetX[entity] = alignment.offsetX;
    alignOffsetY[entity] = alignment.offsetY;
  }

  /// Writes all four border insets at once. See [setPivot].
  void setNineSliceBorder(Entity entity, NineSliceBorder border) {
    borderLeft[entity] = border.left;
    borderTop[entity] = border.top;
    borderRight[entity] = border.right;
    borderBottom[entity] = border.bottom;
  }
}

/// Declares one entity's sprites. One [has] call per sprite; a prefab that
/// draws a body and a hat calls it twice and keeps both handles in fields.
///
/// [has] takes a named parameter for **every** field the returned [Sprite]
/// exposes, and each one doubles as that archetype's declared row default -
/// the standing `MultiComponent` convention (`ColliderDescriptor`'s
/// `has*Collider` methods are the same shape) - so the common case needs no
/// `onEntityMounted` write at all.
class SpriteDescriptor {
  SpriteDescriptor._(this._data, this._assets, this._sprites);

  final DataDescriptor _data;

  /// The table [Sprite.texture] resolves through. Threaded in from
  /// `Renderable2D.describeStruct` rather than assumed, because an object
  /// field's address only means anything against the table that issued it -
  /// there is no shared registry to fall back on.
  final IntRepresentation<TextureAsset> _assets;
  final List<Sprite> _sprites;

  /// Declares one sprite and returns the handle to keep in a field
  /// (RULES.md rule 6 - never a name to quote again later).
  ///
  /// [pivot], [alignment] and [nineSliceBorder] arrive as value objects
  /// purely for readability at the call site; each is unpacked into its own
  /// separate `DataPointer<double>` fields here, because a row cannot store a
  /// value object (see [Sprite]'s doc). That unpacking happens once, during
  /// the declare-time `describeStruct` pass, so the value objects never touch
  /// a hot path.
  Sprite has({
    TextureAsset? texture,
    TextureFilter filter = TextureFilter.mipmap,
    int color = 0xFFFFFFFF,
    double width = 0,
    double height = 0,
    int zIndex = 0,
    bool visible = true,
    RelativeOffset2D pivot = RelativeOffset2D.center,
    RelativeOffset2D alignment = RelativeOffset2D.zero,
    NineSliceBorder nineSliceBorder = NineSliceBorder.none,
  }) {
    final sprite = Sprite(
      texture: _data.optPacked(_assets, texture),
      filter: _data.hasUint2(filter.index),
      color: _data.hasUint32(color),
      width: _data.hasFloat64(width),
      height: _data.hasFloat64(height),
      zIndex: _data.hasInt32(zIndex),
      visible: _data.hasUint1(visible ? 1 : 0),
      pivotFractionX: _data.hasFloat64(pivot.fractionX),
      pivotFractionY: _data.hasFloat64(pivot.fractionY),
      pivotOffsetX: _data.hasFloat64(pivot.offsetX),
      pivotOffsetY: _data.hasFloat64(pivot.offsetY),
      alignFractionX: _data.hasFloat64(alignment.fractionX),
      alignFractionY: _data.hasFloat64(alignment.fractionY),
      alignOffsetX: _data.hasFloat64(alignment.offsetX),
      alignOffsetY: _data.hasFloat64(alignment.offsetY),
      borderLeft: _data.hasFloat64(nineSliceBorder.left),
      borderTop: _data.hasFloat64(nineSliceBorder.top),
      borderRight: _data.hasFloat64(nineSliceBorder.right),
      borderBottom: _data.hasFloat64(nineSliceBorder.bottom),
    );
    _sprites.add(sprite);
    return sprite;
  }
}

/// The five transform fields the renderer reads, bound to whichever component
/// an archetype actually keeps them in.
///
/// A renderable with `WorldTransform2D` is drawn from its composed world
/// transform; one without is drawn from its local `Transform2D`. The two are
/// different components with differently-named fields, and the write pass
/// walks in z order across every archetype at once - so it cannot ask "which
/// one is this?" per sprite without paying for the question 20,000 times.
/// Binding the five `DataPointer`s once per archetype answers it once.
///
/// One instance per archetype, cached for the life of the run in
/// [GameRenderer2D._sourceOf] - not per group per frame, which would be an
/// allocation on the frame path (RULES.md rule 1).
class _TransformSource {
  _TransformSource.world(WorldTransform2D world)
    : x = world.worldX,
      y = world.worldY,
      rotation = world.worldRotation,
      scaleX = world.worldScaleX,
      scaleY = world.worldScaleY;

  _TransformSource.local(Transform2D local)
    : x = local.transformOffsetX,
      y = local.transformOffsetY,
      rotation = local.transformRotation,
      scaleX = local.transformScaleX,
      scaleY = local.transformScaleY;

  final DataPointer<double> x;
  final DataPointer<double> y;
  final DataPointer<double> rotation;
  final DataPointer<double> scaleX;
  final DataPointer<double> scaleY;
}

/// Marks an entity as something the renderer should draw, and carries the
/// [Sprite]s it draws as.
///
/// An entity mixing this in **must** also mix in `Transform2D` - there is no
/// meaningful place to draw something that has no position, and requiring it
/// in the query (rather than defaulting to the origin) turns "I forgot the
/// transform" into an entity that visibly never appears rather than a pile of
/// quads stacked at 0,0.
///
/// `WorldTransform2D` is **optional**, and that is the point of it being a
/// separate mixin. A renderable that has it is drawn from its composed world
/// transform; one that does not is drawn from its local `Transform2D`
/// directly, which for an entity that is never parented is the same answer -
/// exactly as `WorldTransform2D`'s own doc promises. Requiring it here used to
/// make that promise false: every drawable had to carry the mixin, so
/// `WorldTransformSystem` copied local to world for every sprite in the game
/// every fixed step, and this pass then read the copy. At 20k flat sprites
/// that copy was a third of the fixed step, spent to arrive back at the
/// numbers it started from.
///
/// A `MultiComponent`, because one entity commonly draws as several
/// rectangles (a body and a hat, a panel and its icon) that move together but
/// have their own size, colour, depth and visibility. Those per-sprite fields
/// therefore live on [Sprite], one instance per [SpriteDescriptor.has] call
/// inside [describeSprites], not on this mixin - the identical arrangement
/// `Collider2D`/`ColliderBody` uses for compound colliders, and for the
/// identical reason (`with Renderable2D, Renderable2D` is not a thing Dart
/// allows).
mixin Renderable2D on MultiComponent {
  /// Populated automatically as each [SpriteDescriptor.has] call inside
  /// [describeSprites] runs, in declaration order. This is what
  /// [GameRenderer2D] iterates - the generic path for anything that needs to
  /// walk every sprite an entity has without knowing this prefab's own field
  /// names, exactly as `Collider2D.bodies` is for colliders.
  final List<Sprite> sprites = [];

  /// A handle to this component's type, so a prefab can enable/disable the
  /// whole of its rendering without touching individual sprites.

  /// Implemented by the concrete prefab - declares this entity type's sprites
  /// via the [SpriteDescriptor] passed in.
  @mustCallSuper
  void describeSprites(SpriteDescriptor descriptor) {}

  // Registering the type here is not optional bookkeeping - it is what sets
  // this component's bit in the archetype signature, and therefore the only
  // reason `withAll(Renderable2D)` matches anything at all. Omitting it (as
  // this mixin originally did, and as `Child`/`Parent` in goo once did) leaves
  // a query silently matching *every* archetype instead of failing loudly.
  // `test/render_2d_test.dart` checks the signature bit directly rather than
  // trusting inspection.
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Renderable2D>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    describeSprites(
      SpriteDescriptor._(
        data,
        getScene<SceneStruct>().assets.of<Texture>(),
        sprites,
      ),
    );
  }
}

/// The renderer's per-tick working set: which (entity, sprite) pairs are
/// going to be drawn, and in what order.
///
/// Lives across ticks and is only ever refilled - the arrays grow to the
/// high-water mark of the scene and stay there, so a steady-state tick
/// allocates nothing here at all. The growth policy is [VertexBatch2D]'s,
/// deliberately: capacity doubles until it fits and the filled prefix is
/// copied across, which is the same amortised-growth arrangement that already
/// keeps the vertex buffers allocation-free (RULES.md rule 1).
///
/// The parallel-arrays-plus-an-index-permutation shape is what lets the sort
/// move a single `int` per swap rather than an entity, a sprite reference and
/// a key. It is also why there is no `_Candidate` class: one object per drawn
/// sprite per tick is precisely the allocation this exists to avoid.
///
/// # Why the finished geometry lives here
///
/// [_corners] and [_colorAddress] hold each plain sprite's *already-transformed*
/// quad, computed by the fill pass rather than by the write pass. That split is
/// the whole point of this class now, and it was measured into existence.
///
/// The fill pass visits rows in page order; the write pass visits the same rows
/// in z-sorted order, which for any scene that layers by distance is close to a
/// random permutation. On a phone, 20,000 rows of ~250 bytes is ~5 MB - past
/// the last-level cache - so the write pass spent its time stalled on memory.
/// A device ablation that skipped the sort entirely (`debugSkipZSort`) cut the
/// write pass from 8.96 ms to 5.18 ms, **42%**, with identical work and only
/// the order changed. The same ablation for the two trig calls moved it 0.07 ms,
/// i.e. nothing: the arithmetic was executing inside the memory stalls for free.
///
/// So the rows are now read once, sequentially, by the pass that was already
/// walking them, and what the permutation shuffles is 40 dense bytes per sprite
/// instead of a 250-byte row scattered across pages - ~800 KB at 20,000
/// sprites rather than ~5 MB, which is the difference between fitting in that
/// cache and not.
///
/// Note this deliberately *moves* cost rather than removing it: the fill pass
/// gets slower and the write pass much faster. `present` is the number that
/// went down; `walk` on its own will read higher than before.
final class _SpriteDrawQueue {
  _SpriteDrawQueue({int initialCapacity = 64})
    : _entities = List<Entity>.filled(initialCapacity, const Entity(0)),
      _sprites = List<Sprite?>.filled(initialCapacity, null),
      _sources = List<_TransformSource?>.filled(initialCapacity, null),
      _zIndices = Int32List(initialCapacity),
      _records = Int32List(initialCapacity),
      _order = Int32List(initialCapacity),
      _merge = Int32List(initialCapacity),
      _corners = Float32List(initialCapacity * _cornerStride),
      _colorAddress = Int32List(initialCapacity * _colorStride);

  /// Floats per queued sprite in [_corners]: four `(x, y)` corners in winding
  /// order, already transformed into view space.
  static const int _cornerStride = 8;

  /// Ints per queued sprite in [_colorAddress]: packed ARGB, then the texture
  /// address, then the texture filter. Kept adjacent so the write pass reads
  /// all three in one access.
  static const int _colorStride = 3;

  List<Entity> _entities;
  List<Sprite?> _sprites;

  /// Where the queued entity's transform is read from, carried from the fill
  /// pass rather than re-derived in the write pass.
  ///
  /// It is a per-*archetype* answer, so the fill pass knows it once per group;
  /// the write pass walks in z order across every archetype at once and would
  /// otherwise have to ask per sprite - a registry lookup plus a subtype test
  /// against a type variable, for an answer the other pass already had. One
  /// reference per queued sprite, in an array reused like every other here.
  List<_TransformSource?> _sources;
  Int32List _zIndices;

  /// How many draw records this pair will write: 1 for a plain sprite, 9 for a
  /// nine-sliced one.
  ///
  /// Decided during the fill pass and *stored* rather than re-derived in the
  /// write pass, because the fill pass is what spends the record budget
  /// against it. Two passes each deciding "is this sliced?" from the same rows
  /// would agree today - presentation runs after the tick commits, so nothing
  /// mutates underneath them - but the byte scratch is sized from the budget
  /// the first pass computed, so any future disagreement would be a buffer
  /// overrun rather than a wrong picture. One `int` per queued sprite removes
  /// the question.
  Int32List _records;

  /// Slot indices in draw order. Sorted in place by [sortByZ]; before that it
  /// is the identity permutation, i.e. encounter order.
  Int32List _order;

  /// The sort's second buffer. Swapped with [_order] rather than copied back -
  /// both are owned scratch of identical length, so the swap is two field
  /// writes. Used by both sorts.
  Int32List _merge;

  /// Four already-transformed `(x, y)` corners per queued sprite, in winding
  /// order - see the class doc for why the geometry is computed by the fill
  /// pass and parked here.
  ///
  /// `Float32List`, not `Float64List`, and that is exact rather than lossy:
  /// the wire format's corners are `float32`, so the old code computed in
  /// double and narrowed once at `setFloat32`. Narrowing here instead puts the
  /// single rounding step in a different place and produces the identical bits,
  /// because reading a `float32` back out widens exactly. It also halves what
  /// the permutation has to drag through the cache, which is the entire point.
  ///
  /// **Only written for sprites that draw as one quad.** A nine-sliced sprite
  /// has nine records with their own per-cell UVs and cannot be reduced to four
  /// corners, so its slots here are left holding whatever a previous tick put
  /// there. Nothing reads them: the write pass branches on [recordsAt] first.
  Float32List _corners;

  /// Packed ARGB then texture address per queued sprite. See [_corners] for
  /// which sprites these are filled for.
  Int32List _colorAddress;

  /// The bucket array for the counting sort - one slot per distinct `zIndex`
  /// value in `[_zMin, _zMax]`. Grown to the high-water mark like every other
  /// buffer here and never shrunk, so a steady-state tick allocates nothing.
  Int32List _counts = Int32List(0);

  /// The smallest and largest `zIndex` queued this tick, tracked in [add]
  /// because that is the one place every key is already in a register. What
  /// [sortByZ] needs them for is the *range*, which is what decides whether a
  /// counting sort is affordable.
  ///
  /// Only meaningful while `_count > 0`; [add] seeds both from the first key
  /// rather than starting from the int extremes, so a scene whose z values are
  /// all equal reports a range of 1 rather than the whole int64 line.
  int _zMin = 0;
  int _zMax = 0;

  int _count = 0;

  /// Total draw records the queued pairs will write - the sum of [_records].
  /// What the byte scratch has to be sized for, as opposed to [length], which
  /// counts sprites.
  int _recordTotal = 0;

  /// How many pairs are queued. Also the length of the sorted prefix.
  int get length => _count;

  /// How many draw records those pairs amount to. A plain sprite contributes
  /// 1; a nine-sliced one contributes 9.
  int get recordCount => _recordTotal;

  void reset() {
    _count = 0;
    _recordTotal = 0;
  }

  /// Queues one (entity, sprite) pair to be drawn at depth [zIndex],
  /// costing [records] draw records, and returns its **slot** - the index the
  /// parallel arrays store it at, which is also its encounter position.
  ///
  /// The slot is what [setQuad] takes. It is deliberately not the draw
  /// position: nothing knows that until [sortByZ] has run, and the fill pass
  /// has to be able to write a sprite's geometry the moment it computes it.
  int add(
    Entity entity,
    Sprite sprite,
    _TransformSource source,
    int zIndex,
    int records,
  ) {
    _ensure(_count + 1);
    // Seeded from the first key rather than from the int extremes, so an empty
    // range is 1 and not the whole number line - see [_zMin].
    if (_count == 0) {
      _zMin = zIndex;
      _zMax = zIndex;
    } else if (zIndex < _zMin) {
      _zMin = zIndex;
    } else if (zIndex > _zMax) {
      _zMax = zIndex;
    }
    _entities[_count] = entity;
    _sprites[_count] = sprite;
    _sources[_count] = source;
    _zIndices[_count] = zIndex;
    _records[_count] = records;
    _order[_count] = _count;
    _recordTotal += records;
    return _count++;
  }

  /// Stores one plain sprite's finished, view-space quad against [slot].
  ///
  /// Corners are in winding order - `(x0,y0)` and `(x2,y2)` opposite - matching
  /// what `DrawSpriteData2D.writeQuad` expects, because [writeQuadAt] hands
  /// them straight to it.
  void setQuad(
    int slot,
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    int color,
    int textureAddress,
    int filter,
  ) {
    final c = slot * _cornerStride;
    final corners = _corners;
    corners[c] = x0;
    corners[c + 1] = y0;
    corners[c + 2] = x1;
    corners[c + 3] = y1;
    corners[c + 4] = x2;
    corners[c + 5] = y2;
    corners[c + 6] = x3;
    corners[c + 7] = y3;
    final k = slot * _colorStride;
    _colorAddress[k] = color;
    _colorAddress[k + 1] = textureAddress;
    _colorAddress[k + 2] = filter;
  }

  /// Writes the [i]th pair *in draw order* as one quad record, returning the
  /// next write offset. Only valid where `recordsAt(i) == 1`.
  ///
  /// This is the whole of the write pass for a plain sprite, and it touches no
  /// component row: one `_order` read, then eight contiguous floats and two
  /// contiguous ints out of the dense arrays the fill pass packed. See the
  /// class doc for the measurement that made this the shape it is.
  ///
  /// The UVs are left to `writeQuad`'s defaults, which spell exactly the
  /// whole-texture case `(0,0) (1,0) (1,1) (0,1)` this path passed explicitly
  /// before.
  int writeQuadAt(ByteData view, int offset, int i) {
    final slot = _order[i];
    final c = slot * _cornerStride;
    final k = slot * _colorStride;
    final q = _corners;
    return DrawSpriteData2D.writeQuad(
      view,
      offset,
      q[c],
      q[c + 1],
      q[c + 2],
      q[c + 3],
      q[c + 4],
      q[c + 5],
      q[c + 6],
      q[c + 7],
      _colorAddress[k],
      textureAddress: _colorAddress[k + 1],
      filter: _colorAddress[k + 2],
    );
  }

  /// The entity of the [i]th pair *in draw order*.
  Entity entityAt(int i) => _entities[_order[i]];

  /// The sprite of the [i]th pair *in draw order*.
  Sprite spriteAt(int i) => _sprites[_order[i]]!;

  /// Where the [i]th pair *in draw order* reads its transform from.
  _TransformSource sourceAt(int i) => _sources[_order[i]]!;

  /// How many records the [i]th pair *in draw order* writes.
  int recordsAt(int i) => _records[_order[i]];

  /// The widest `zIndex` span a counting sort is allowed to bucket.
  ///
  /// The counting sort costs `O(n + range)` and the merge sort `O(n log n)`,
  /// so the crossover is roughly `range < n * (log2(n) - 1)` - at 20,000
  /// sprites, a range of about 270,000. This cap is far below that and is set
  /// by *memory* instead: 65,536 buckets is a 256 KiB `Int32List` held for the
  /// life of the run, which is already generous scratch for a renderer. Beyond
  /// it the merge sort is used, so a game that spreads `zIndex` across the
  /// whole `int32` range is never worse off than it was.
  static const int _maxCountingRange = 1 << 16;

  /// Sorts the queued pairs by `zIndex` ascending, keeping equal-`zIndex`
  /// pairs in the order they were added.
  ///
  /// # Two sorts, picked on the key range
  ///
  /// `zIndex` is a **small integer**, not an arbitrary comparable, and that
  /// changes what the best available algorithm is. A comparison sort cannot
  /// beat `O(n log n)`; a counting sort over a bounded integer key is `O(n +
  /// range)` and does not compare anything at all. Scenes layer sprites into
  /// tens or a few thousand distinct depths - the Galaxy case spans about 380 -
  /// so `range` is normally far below `n` and the sort becomes linear.
  ///
  /// The merge sort below is kept, not replaced, and is used whenever the range
  /// exceeds [_maxCountingRange]. A game is free to use `zIndex` as a sparse
  /// sort key (timestamps, hashes, ids) and bucketing that would allocate
  /// megabytes to sort a handful of sprites. Picking on the measured range
  /// rather than on a declared mode means neither case has to be configured.
  ///
  /// # Both are stable, by construction rather than by luck
  ///
  /// Equal-`zIndex` sprites must keep encounter order - archetype registration
  /// order, then page order, then row order, then declaration order within a
  /// prefab - because that is the ordering this system had before `zIndex`
  /// existed and scenes depend on it. The merge takes from the *left* run on a
  /// tie (`<=`), and the left run is always the earlier-encountered one. The
  /// counting sort walks the input in encounter order and appends within each
  /// bucket, which is the same guarantee arrived at differently.
  ///
  /// # Why neither is `List.sort`
  ///
  /// Both reasons come straight from RULES.md rule 1:
  ///
  ///  * **They sort a prefix.** `List.sort` sorts a whole list, and the only
  ///    ways to hand it exactly `_count` elements are a `sublistView`
  ///    (an allocation every tick) or a growable list whose `clear()` is free
  ///    to shrink its backing store (an allocation every tick, at the SDK's
  ///    discretion). Sorting `[0, _count)` of a fixed array has neither
  ///    problem.
  ///  * **They need no comparator object.** There is no closure here at all -
  ///    not a fresh lambda per tick, not even a long-lived function reference.
  void sortByZ() {
    final n = _count;
    if (n < 2) return;
    // `_zMin`/`_zMax` are plain Dart ints, which are 64-bit, so this subtraction
    // cannot overflow even for two `int32` extremes - the reason the range is
    // computed here rather than tracked incrementally as an int32.
    final range = _zMax - _zMin + 1;
    if (range <= _maxCountingRange) {
      _countingSortByZ(n, range);
      return;
    }
    _mergeSortByZ(n);
  }

  /// Stable counting sort over `[_zMin, _zMax]`. See [sortByZ].
  void _countingSortByZ(int n, int range) {
    final counts = _ensureCounts(range);
    // Only the live prefix is cleared. The buffer is grown to a high-water
    // mark and a previous, wider frame's tail is never read this tick.
    for (var k = 0; k < range; k++) {
      counts[k] = 0;
    }
    final keys = _zIndices;
    final src = _order;
    final min = _zMin;
    for (var i = 0; i < n; i++) {
      counts[keys[src[i]] - min]++;
    }
    // Exclusive prefix sum: each bucket becomes the index its first member
    // lands at, and is then bumped as members are placed.
    var running = 0;
    for (var k = 0; k < range; k++) {
      final c = counts[k];
      counts[k] = running;
      running += c;
    }
    // Walking `src` forward and appending within each bucket is what makes
    // this stable - see [sortByZ]. Reading through `src` rather than assuming
    // the identity permutation costs one load and keeps this correct whatever
    // state a previous tick's buffer swap left `_order` in.
    final dst = _merge;
    for (var i = 0; i < n; i++) {
      final slot = src[i];
      dst[counts[keys[slot] - min]++] = slot;
    }
    _merge = _order;
    _order = dst;
  }

  /// Grows [_counts] to hold [range] buckets, doubling like every other buffer
  /// here so a steady-state tick allocates nothing.
  Int32List _ensureCounts(int range) {
    if (range <= _counts.length) return _counts;
    var next = _counts.isEmpty ? 64 : _counts.length;
    while (next < range) {
      next *= 2;
    }
    // Nothing to preserve: the bucket contents are scratch within a single
    // _countingSortByZ call.
    return _counts = Int32List(next);
  }

  /// Bottom-up stable merge sort - the fallback for a `zIndex` range too wide
  /// to bucket. See [sortByZ].
  void _mergeSortByZ(int n) {
    final keys = _zIndices;
    var src = _order;
    var dst = _merge;
    for (var width = 1; width < n; width *= 2) {
      for (var lo = 0; lo < n; lo += width * 2) {
        final mid = lo + width < n ? lo + width : n;
        final hi = lo + width * 2 < n ? lo + width * 2 : n;
        var i = lo;
        var j = mid;
        var k = lo;
        while (i < mid && j < hi) {
          dst[k++] = keys[src[i]] <= keys[src[j]] ? src[i++] : src[j++];
        }
        while (i < mid) {
          dst[k++] = src[i++];
        }
        while (j < hi) {
          dst[k++] = src[j++];
        }
      }
      final swap = src;
      src = dst;
      dst = swap;
    }
    // An odd number of passes leaves the result in `_merge`; adopt it as the
    // order rather than copying it back.
    if (!identical(src, _order)) {
      _merge = _order;
      _order = src;
    }
  }

  void _ensure(int capacity) {
    if (capacity <= _zIndices.length) return;
    var next = _zIndices.length;
    while (next < capacity) {
      next *= 2;
    }
    _entities = List<Entity>.filled(next, const Entity(0))
      ..setRange(0, _count, _entities);
    _sprites = List<Sprite?>.filled(next, null)..setRange(0, _count, _sprites);
    _sources = List<_TransformSource?>.filled(next, null)
      ..setRange(0, _count, _sources);
    _zIndices = Int32List(next)..setRange(0, _count, _zIndices);
    _records = Int32List(next)..setRange(0, _count, _records);
    _order = Int32List(next)..setRange(0, _count, _order);
    _corners = Float32List(next * _cornerStride)
      ..setRange(0, _count * _cornerStride, _corners);
    _colorAddress = Int32List(next * _colorStride)
      ..setRange(0, _count * _colorStride, _colorAddress);
    // Nothing to preserve here - the merge buffer is scratch within a single
    // sortByZ call.
    _merge = Int32List(next);
  }
}

/// Turns the simulation's published state into a flat draw-command buffer,
/// once per presented frame, on the game isolate.
///
/// This system is the *only* producer of draw records. It runs in the
/// presentation phase - after the fixed tick has committed - so everything it
/// reads is final for that tick by construction, rather than by a convention
/// about where it is declared. See [compareTo].
///
/// It draws nothing itself and is handed no `Canvas`. It cannot be: it lives
/// on an isolate with no Flutter engine attached. Its entire output is bytes
/// in a `RingBuffer` that `DrawCanvas2D` replays on the main isolate.
///
/// # What happens here and not on the paint side
///
/// **Hierarchy flattening happens upstream.** A `Renderable2D` that is also a
/// `Child` needs its ancestors' transforms composed in before its corners mean
/// anything in world space - and `WorldTransformSystem` did exactly that
/// during the tick, caching the result in `WorldTransform2D`. This system
/// reads it. The record that crosses the ring still carries finished
/// world-space corners, so the paint side never re-walks a hierarchy or
/// re-reads a component row.
///
/// **The transform maths is plain doubles, not a `Matrix4`.** A matrix object
/// per entity per tick is precisely the per-entity heap allocation RULES.md
/// rule 1 forbids, and a 2D affine is six numbers.
///
/// # Ordering
///
/// One draw record per visible, sized [Sprite] - not one per entity - and
/// draw order is `zIndex` ascending with a **stable** tie-break on encounter
/// order (archetype registration order, then page order, then row order, then
/// the order sprites were declared within a prefab). So equal-`zIndex`
/// sprites keep exactly the order this system produced before `zIndex`
/// existed, and a scene that never sets `zIndex` draws identically to before.
///
/// The sort is a prefix merge sort over a reusable index permutation (see
/// [_SpriteDrawQueue.sortByZ]) - no per-tick allocation, no comparator
/// closure, and stability by construction rather than by trusting a library
/// sort's unspecified behaviour.
///
/// There is still no culling. A view-frustum test needs a viewport size,
/// which is the same thing the alignment section below is missing, and it is
/// additive when that arrives (a camera rect tested against each quad's
/// bounds, between the queue fill and the write loop).
///
/// # Camera
///
/// A second query finds the active camera through [ActiveCameraResolver], and
/// its world position and `zoom` are folded into every quad's final
/// coordinates: `screen = (world - cameraOrigin) * zoom`. With no camera in
/// the scene the origin is `(0, 0)` and the zoom is `1`, which is the
/// identity - so a game that declares no camera gets byte-for-byte the output
/// this system produced before cameras existed.
///
/// # Alignment
///
/// [Sprite]'s `align*` fields are declared, defaulted and stored, and this
/// system does **not** apply them. Stating that plainly rather than leaving it
/// to be discovered: an alignment is resolved against the size of the thing
/// the sprite is anchored to - its parent's bounds, or the viewport's - and
/// neither number exists here. The viewport size is a main-isolate quantity
/// (`GameView` learns it from a `CustomPaint`'s `Size`, on the other side of
/// the ring), and a parent's bounds are its own sprites' extents, which no
/// system currently resolves and publishes. Whichever of those two lands
/// first is what will consume these fields; until then they round-trip
/// through storage and change nothing about the geometry.
///
/// # Textures
///
/// [Sprite.texture] is read and written into every record as the asset's
/// `GlobalObject` **address** - the integer both isolate copies agree on
/// because both ran the same `describeAssets` pass - alongside four UV pairs
/// covering the whole image. A null texture writes
/// [DrawSpriteData2D.noTexture] and the quad draws as its flat colour exactly
/// as it always did; there is no placeholder image and no second code path.
///
/// This system never touches a `ui.Image`, and cannot: it runs on an isolate
/// whose `Texture` instances are addressed but never decoded. `DrawCanvas2D`
/// resolves the address and builds the shader on the main isolate, which is
/// the whole reason the addressing scheme exists.
///
/// # Not yet: nine-slice
///
/// The `border*` insets are declared and stored, and this system reads none of
/// them. Every sprite emits one quad whether or not the border is non-empty;
/// generating a nine-slice's nine quads (each with its own sub-rectangle of
/// the UV square this writes whole) is the follow-up task.
class GameRenderer2D extends GameSystem
    with Tickable, GameSystemLifecycleListener {
  /// Runs in the presentation phase, after the fixed tick commits, and after
  /// `WorldTransformSystem` within it.
  ///
  /// Both halves of that are load-bearing. Being a [Tickable] rather than a
  /// `FixedTickable` is what lets it *read* `WorldTransform2D` instead of
  /// recomposing the hierarchy itself: a presentation pass sees the snapshot
  /// the tick just published, so the transforms the simulation derived are
  /// visible to it. Inside the tick they would not be - reads there see the
  /// *previous* tick's snapshot - which is why this system used to carry its
  /// own copy of the composition math. That duplication was a symptom of
  /// being in the wrong phase, not of a missing accessor; see RULES.md rule
  /// 8, and Unity DOTS's `SimulationSystemGroup`/`PresentationSystemGroup`
  /// split, which resolves the identical problem the identical way.
  ///
  /// Latency is unchanged by the move. Composing from published
  /// `Transform2D` inside tick N and reading `WorldTransform2D` published
  /// *by* tick N both depict the world as of the end of tick N-1.
  @override
  int compareTo(GameSystem other) => other is WorldTransformSystem ? 1 : 0;

  /// The [Renderer2D] half of this game - where the frame buffers live.
  ///
  /// A `GameSystem` runs wholly on the game isolate and declares no shared
  /// memory of its own: allocation happens on main, before the spawn, on the
  /// copy that owns and frees it. So the storage this system writes into is
  /// declared by the `Game` mixin that also *reads* it, and this system is
  /// handed the handle rather than owning it.
  ///
  /// The cast is what a `GameSystem` pays for reaching a `Game`-side
  /// capability. It cannot be static: `GameSystem.game` is a plain `Game`, and
  /// a renderer declared into a game with no `Renderer2D` is a real
  /// configuration mistake worth naming rather than a type error to design
  /// around.
  Renderer2D get _renderer {
    final game = this.game;
    if (game is! Renderer2D) {
      throw StateError(
        '$runtimeType is declared in a ${game.runtimeType}, which does not mix '
        'in Renderer2D - so there is nowhere for its frame buffers to live. '
        'Extend Game2D (or add `with Renderer2D`): the main-isolate half is '
        'what allocates the storage this system fills and then drains it into '
        'a GameView.',
      );
    }
    return game;
  }

  /// The frame buffer [view] is drawn into - what the main-isolate half
  /// samples. Throws for a view belonging to a different game, which is the
  /// same diagnostic its table would give.
  HandoffHandle framesFor(CameraView view) => _renderer.framesFor(view);

  /// Bytes one tick's sprite batch occupies, including its tick stamp. Comes
  /// from the `Game`, which sized the buffers from the same number.
  int get spriteBatchBytes => _renderer.spriteBatchBytes;

  // There is no ring capacity to configure any more. This used to be a
  // `RingBuffer` sized to four batches, on the theory that a main isolate
  // missing a couple of ticks should still find its frame waiting - which had
  // it exactly backwards. A queue keeps the *oldest* frames, and an old frame
  // is the one thing a renderer never wants; overflow then dropped the newest,
  // which is the wrong end. A `HandoffBuffer` holds one complete frame and the
  // one being built, so "behind" simply means the reader gets the newest
  // instead of a backlog. See `BufferDescriptor.hasHandoff`.

  late final Query _renderables;
  late final Query _cameras;

  /// One projection for the lifetime of the system - re-resolved each tick,
  /// never rebuilt, because building one per tick would be an allocation on
  /// the hot path for no reason. Shared logic rather than a local
  /// reimplementation, so "where is the camera, and where does that put a
  /// world point on screen" means exactly the same thing here as it does to
  /// `MousePickingSystem`.
  final CameraProjection _projection = CameraProjection();

  final _SpriteDrawQueue _queue = _SpriteDrawQueue();

  Uint8List? _scratch;
  ByteData? _scratchView;

  /// How many *sprites* the last [onTick] drew. Diagnostics and tests.
  ///
  /// Not the same as [lastRecordCount] once nine-slicing is in play: one
  /// sliced sprite is one sprite and nine records. This is the count of
  /// things the scene asked to draw; that one is the count of quads the
  /// buffer actually holds, and it is the buffer's number that has to stay
  /// under the budget.
  int lastSpriteCount = 0;

  /// Microseconds the last [onTick] spent in each of the three phases of the
  /// present pass, across every view it rendered.
  ///
  /// One number for "presentation" says how expensive drawing is; it does not
  /// say which of three unrelated things to do about it, and they have nothing
  /// in common:
  ///
  ///  * [lastWalkMicros] - iterating renderables and filling the draw queue.
  ///    Scales with *entities* and is component-field reads, the same cost
  ///    every system pays.
  ///  * [lastSortMicros] - `sortByZ`. Scales with `n log n` in sprites and
  ///    touches no component data at all.
  ///  * [lastWriteMicros] - turning queued sprites into geometry in the
  ///    scratch buffer. Scales with sprites and is dominated by how many bytes
  ///    a sprite costs in the wire format.
  ///
  /// Only the third is affected by changing the vertex format, only the second
  /// by changing the ordering strategy, and only the first by anything the
  /// storage layer does. Measured with one `Stopwatch` reused across all three
  /// (see [_clock]) so the instrumentation itself allocates nothing.
  int lastWalkMicros = 0;
  int lastSortMicros = 0;
  int lastWriteMicros = 0;

  /// Reused by all three phase timings, per view - a `Stopwatch` is a heap
  /// object and this runs every frame (RULES.md rule 1).
  final Stopwatch _clock = Stopwatch();

  /// How many draw records the last [onTick] wrote - quads, not sprites.
  ///
  /// This is what `maxSpritesPerTick` bounds and what `spriteBatchBytes`
  /// is sized from, so it is the number to watch when a scene starts
  /// dropping frames.
  int lastRecordCount = 0;

  /// True if the last [onTick] could not fit its batch in the ring.
  bool lastWriteDropped = false;

  /// **Diagnostic only. Setting this draws the scene in the wrong order.**
  ///
  /// Skips [_SpriteDrawQueue.sortByZ], so sprites are written in encounter
  /// order - archetype, then page, then row - instead of by depth. Anything
  /// that overlaps will layer wrongly, and this is not a rendering mode.
  ///
  /// It exists because "is the write pass slow because it walks rows in a
  /// near-random permutation?" is a question only answerable on the machine
  /// that has the problem. `tool/write_pass_bench.dart` can attribute the
  /// write pass on a desktop, where the whole pass costs ~72 ns/sprite; the
  /// device reports ~368. The gap is real, so the attribution has to be redone
  /// where the gap is, and this is the one-line ablation that does it: turn it
  /// on, read [lastWriteMicros], and the difference is what the permutation
  /// costs in cache misses.
  ///
  /// One bool read per view per frame, so leaving it here costs a shipped
  /// build nothing measurable. The matching trig ablation deliberately needs
  /// no flag at all: writing zero into every entity's rotation makes the
  /// unrotated fast path in the write loop skip both `math.cos`/`math.sin`
  /// calls, which is the same experiment with no diagnostic code in the hot
  /// loop.
  bool debugSkipZSort = false;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    // No `Child` clause at all any more, in either direction. A child entity
    // needs rendering exactly as much as a root does - the stub this replaced
    // forbade `Child` and so silently excluded every hierarchy child from
    // ever being drawn - and what used to be special about one (its transform
    // needing its ancestors composed in first) is no longer this system's
    // problem: `WorldTransformSystem` did that during the tick, and
    // `WorldTransform2D` is where the answer already is.
    //
    // Requiring `WorldTransform2D` rather than `Transform2D` is therefore the
    // real entry condition now: an entity is drawable when it has a resolved
    // world position, whether it got one as a root or through a parent chain.
    _renderables = descriptor
        .query()
        .withAll(Renderable2D, Transform2D)
        .withOptional(WorldTransform2D)
        .build();
    // The camera is queried, not configured on this system: "where the view
    // is" is a property of an entity in the scene that the simulation can move
    // like any other, not a field a presentation system owns. Requiring
    // `WorldTransform2D` on it as well means a camera parented to the player
    // works with no special case here.
    _cameras = descriptor.query().withAll(Camera, WorldTransform2D).build();
  }

  // There is no `describeBuffers` here, and there cannot be: a `GameSystem` is
  // declared and run on the game isolate, while shared memory is allocated on
  // main before the spawn. `Renderer2D.describeBuffers` declares one handoff
  // per camera view instead - on the same object that drains them into a
  // `GameView`, which is where the plan's own sorting rule puts a declaration:
  // with whoever holds the handle.

  /// Whether [sprite] on [entity] draws as nine quads rather than one.
  ///
  /// Three conditions, and all three are load-bearing:
  ///
  ///  * **Some inset is non-zero.** All-zero is the default and means "plain
  ///    quad" - the overwhelmingly common case, and the first thing checked so
  ///    it costs four field reads and nothing else.
  ///  * **There is a texture.** Slicing subdivides *image* space; with nothing
  ///    to sample, nine flat-coloured rectangles are indistinguishable from
  ///    the one they tile, so the insets are ignored rather than honoured
  ///    pointlessly.
  ///  * **That texture declared its pixel size.** The UV split needs it (see
  ///    `Texture.sourceWidth`), and it is only there if the `TextureAsset`
  ///    stated it. An undeclared size falls back to a single quad rather than
  ///    dividing by zero or guessing.
  ///
  /// Called once per candidate sprite in the fill pass and never again - the
  /// answer is stored in the queue, because the byte scratch is sized from it.
  // Scratch for one nine-sliced sprite's grid lines: four in each axis,
  // reused across sprites and ticks. Fields rather than locals so no array is
  // allocated per sprite (RULES.md rule 1) - `onTick` may hit this once per
  // sprite per frame.
  //
  // `_lx`/`_ly` are *transformed-space* offsets from the pivot (already
  // scaled); `_u`/`_v` are the matching cuts in 0..1 texture space.
  final Float64List _lx = Float64List(4);
  final Float64List _ly = Float64List(4);
  final Float64List _u = Float64List(4);
  final Float64List _v = Float64List(4);

  /// Expands one sprite into the nine quads of a nine-slice, returning the
  /// new write offset.
  ///
  /// # The layout
  ///
  /// Four grid lines per axis cut the sprite into a 3x3: two at the edges and
  /// two at the insets. The four corner cells keep their **source pixel size**
  /// no matter how large the sprite is drawn - that is the entire point, and
  /// what stops a dialog frame's rounded corners smearing when the panel
  /// grows. The two horizontal edges stretch only in x, the two vertical ones
  /// only in y, and the centre absorbs everything left over in both.
  ///
  /// Insets are in **source pixels**, and are used unchanged as world units on
  /// the destination side. That is the 1:1 texel-to-world-unit convention this
  /// renderer already draws untextured quads under; a sprite that wants its
  /// frame thicker scales the whole entity or declares bigger insets.
  ///
  /// # When the insets do not fit
  ///
  /// If `left + right` exceeds the draw width, the two are scaled down
  /// proportionally until they exactly fill it, collapsing the middle column
  /// to zero width; the same independently for the vertical axis. Proportional
  /// rather than clamped-in-order because clamping would let whichever inset
  /// was written first eat the whole axis and shrink the other to nothing,
  /// which reads as an asymmetric frame rather than as a small one. It is also
  /// what CSS `border-image` does, so the behaviour is not novel.
  ///
  /// Nothing ever inverts: every cell's extent is clamped at zero, and a
  /// zero-area cell is skipped rather than emitted, because a degenerate quad
  /// costs a record and six vertices to rasterise nothing. **The UV split is
  /// deliberately not scaled with it** - the source image is sliced where it
  /// is sliced regardless of how small the destination got, so the corners
  /// keep sampling the right pixels and only the destination compresses.
  ///
  /// # Transform
  ///
  /// The grid is laid out in the sprite's own local frame, pivot included,
  /// and only then pushed through the same rotate-and-translate the
  /// single-quad path uses - so a rotated nine-sliced panel stays a coherent
  /// rotated panel instead of nine independently-rotated tiles drifting apart.
  int _writeNineSlice(
    ByteData view,
    int offset,
    Entity entity,
    Sprite sprite,
    TextureAsset texture,
    double width,
    double height,
    double pivotX,
    double pivotY,
    double scaleX,
    double scaleY,
    double cos,
    double sin,
    double tx,
    double ty,
    int color,
    int address,
    int filter,
  ) {
    var left = sprite.borderLeft[entity];
    var right = sprite.borderRight[entity];
    var top = sprite.borderTop[entity];
    var bottom = sprite.borderBottom[entity];

    // Destination-side fit, per axis and independently - see the doc above.
    final horizontal = left + right;
    if (horizontal > width && horizontal > 0) {
      final k = width / horizontal;
      left *= k;
      right *= k;
    }
    final vertical = top + bottom;
    if (vertical > height && vertical > 0) {
      final k = height / vertical;
      top *= k;
      bottom *= k;
    }

    // Grid lines in unscaled local space (0..width from the sprite's own
    // top-left), shifted onto the pivot and scaled in one step, exactly as
    // the single-quad path derives its `lx0`/`lx1`.
    final lx = _lx;
    final ly = _ly;
    lx[0] = (0 - pivotX) * scaleX;
    lx[1] = (left - pivotX) * scaleX;
    lx[2] = (width - right - pivotX) * scaleX;
    lx[3] = (width - pivotX) * scaleX;
    ly[0] = (0 - pivotY) * scaleY;
    ly[1] = (top - pivotY) * scaleY;
    ly[2] = (height - bottom - pivotY) * scaleY;
    ly[3] = (height - pivotY) * scaleY;

    // The matching cuts in texture space, from the *declared* source size -
    // the one number the game isolate can know without decoding (see
    // `Texture.sourceWidth`). Note these use the sprite's original insets, not
    // the fitted ones above: squeezing the destination must not re-slice the
    // source.
    final info = texture.info as TextureInfo;
    final sw = info.width.toDouble();
    final sh = info.height.toDouble();
    final u = _u;
    final v = _v;
    u[0] = 0;
    u[1] = sprite.borderLeft[entity] / sw;
    u[2] = 1 - sprite.borderRight[entity] / sw;
    u[3] = 1;
    v[0] = 0;
    v[1] = sprite.borderTop[entity] / sh;
    v[2] = 1 - sprite.borderBottom[entity] / sh;
    v[3] = 1;

    for (var row = 0; row < 3; row++) {
      final y0 = ly[row];
      final y1 = ly[row + 1];
      if (y1 == y0) continue; // collapsed row - see the doc above
      final by0 = y0 * sin;
      final by1 = y1 * sin;
      final cy0 = y0 * cos;
      final cy1 = y1 * cos;
      for (var col = 0; col < 3; col++) {
        final x0 = lx[col];
        final x1 = lx[col + 1];
        if (x1 == x0) continue; // collapsed column
        final ax0 = x0 * cos;
        final ax1 = x1 * cos;
        final sy0 = x0 * sin;
        final sy1 = x1 * sin;
        offset = DrawSpriteData2D.writeQuad(
          view,
          offset,
          tx + ax0 - by0,
          ty + sy0 + cy0, // (left,  top)
          tx + ax1 - by0,
          ty + sy1 + cy0, // (right, top)
          tx + ax1 - by1,
          ty + sy1 + cy1, // (right, bottom)
          tx + ax0 - by1,
          ty + sy0 + cy1, // (left,  bottom)
          color,
          textureAddress: address,
          filter: filter,
          u0: u[col],
          v0: v[row],
          u1: u[col + 1],
          v1: v[row],
          u2: u[col + 1],
          v2: v[row + 1],
          u3: u[col],
          v3: v[row + 1],
        );
      }
    }
    return offset;
  }

  bool _isNineSliced(Entity entity, Sprite sprite) {
    if (sprite.borderLeft[entity] == 0 &&
        sprite.borderTop[entity] == 0 &&
        sprite.borderRight[entity] == 0 &&
        sprite.borderBottom[entity] == 0) {
      return false;
    }
    final texture = sprite.texture[entity];
    return texture != null && texture.info is TextureInfo;
  }

  @override
  void onTick(Duration delta) {
    // One pass per declared view. Each writes its own buffer, and each draws
    // the scene *its* camera is in - which is what replaced the deleted
    // global front scene. Two views can be looking at different scenes, or at
    // the same scene from different places, in the same tick.
    //
    // Totals across views, so a one-view game (the overwhelmingly common
    // case) reports exactly what it used to.
    var sprites = 0;
    var records = 0;
    var dropped = false;
    var walk = 0;
    var sort = 0;
    var write = 0;
    final views = game.cameraViews;
    for (var i = 0; i < views.length; i++) {
      _renderView(views[i], framesFor(views[i]));
      sprites += lastSpriteCount;
      records += lastRecordCount;
      dropped = dropped || lastWriteDropped;
      walk += lastWalkMicros;
      sort += lastSortMicros;
      write += lastWriteMicros;
    }
    lastSpriteCount = sprites;
    lastRecordCount = records;
    lastWriteDropped = dropped;
    lastWalkMicros = walk;
    lastSortMicros = sort;
    lastWriteMicros = write;
  }

  /// One [_TransformSource] per archetype, keyed by that archetype's
  /// `Transform2D` - a component instance is per-archetype and unique, so it
  /// is the archetype's identity without reaching for storage internals.
  ///
  /// Built on first sight of a group and kept: archetypes are declared at boot
  /// and their component instances live as long as the run, so this fills once
  /// and is a map read per group per frame after that - never per sprite, and
  /// never an allocation on the frame path.
  final Map<Transform2D, _TransformSource> _sourceCache =
      <Transform2D, _TransformSource>{};

  _TransformSource _sourceOf(QueryGroup group) {
    final local = group.get<Transform2D>();
    final cached = _sourceCache[local];
    if (cached != null) return cached;
    // `tryGet`, because `WorldTransform2D` is optional on a renderable - an
    // entity that is never parented has no composed transform to read and its
    // local one is already the answer. See [Renderable2D]'s doc.
    final world = group.tryGet<WorldTransform2D>();
    final source = world == null
        ? _TransformSource.local(local)
        : _TransformSource.world(world);
    _sourceCache[local] = source;
    return source;
  }

  void _renderView(CameraView cameraView, HandoffHandle handle) {
    lastSpriteCount = 0;
    lastRecordCount = 0;
    lastWalkMicros = 0;
    lastSortMicros = 0;
    lastWriteMicros = 0;
    // Asked *before* any work is done, and that ordering is the point. Null
    // means main has not taken the last frame yet, so there is nowhere safe to
    // write - and rather than build a frame and throw it away, the whole pass
    // is skipped. The simulation is unaffected; only the drawing stops, and
    // only while nobody is looking. This is what stops a 200Hz tick building
    // and discarding two frames out of every three against a 60Hz display.
    final frames = handle.tryBuffer;
    if (frames == null) return;
    final target = frames.beginWrite();
    if (target == null) {
      lastWriteDropped = true;
      return;
    }

    // The scratch is built on first use rather than at bind time: only the
    // simulating copy ever gets here, and the handle copy would otherwise
    // carry a megabyte of bytes it never touches.
    final scratch = _scratch ??= Uint8List(spriteBatchBytes);
    final view = _scratchView ??= ByteData.sublistView(scratch);

    // Presentation runs after `commitTick`, which is also after the run's tick
    // counter was bumped - so the tick whose state this batch depicts is the
    // current one, not one past it. Deriving the stamp instead of keeping a
    // counter means a disabled-then-reenabled renderer cannot drift out of
    // step with the simulation it is depicting.
    //
    // Off the state, not the `Game`: a tick belongs to a run, and a `Game` can
    // be backing several.
    DrawData2D.writeBatchTick(view, state.tick);

    // Through `CameraProjection` rather than reading the camera's fields
    // here, so this and `MousePickingSystem` cannot end up applying two
    // slightly different mappings - picking that disagreed with drawing by a
    // constant would mean clicking next to what you can see. No camera is
    // not an error: the projection resolves to the identity plus centring.
    final projection = _projection..resolve(_cameras, cameraView);
    final zoom = projection.zoom;
    // Which scene this view shows: the one its camera lives in. -1 means the
    // view has no camera, and then nothing is scoped out - an unconfigured
    // game draws its world rather than a black screen, which is the same
    // answer "no camera" already gave for the projection itself.
    final onlyScene = projection.sceneSlot;

    // Pass one: collect what is going to be drawn. Nothing is written to the
    // byte scratch yet, because the order is not known until every candidate
    // has been seen.
    final queue = _queue..reset();
    // A *record* budget, not a sprite count. A nine-sliced sprite writes nine
    // records, so counting sprites would let nine times the declared maximum
    // through and overrun the byte scratch, which is sized from this same
    // number times the record stride. Counting records keeps the two honest
    // against each other whatever mix of sliced and plain sprites shows up.
    final limit = _renderer.maxSpritesPerTick;
    // Every loaded scene renders. There used to be a front-scene filter here,
    // honouring `switchScene`; that is deleted, because "which scene do I
    // draw" is a question a *view* answers and there can be several views. A
    // game that wants a preloaded level to simulate unseen keeps its sprites
    // invisible or unloads it.
    // Grouped, so the component and its sprite list are resolved once per
    // archetype instead of once per entity - `entity.get<Renderable2D>()`
    // returned the same object for every row, and at 10k rows that showed up
    // in a profile.
    //
    // The label sits on the **group** loop, not the entity loop: `break outer`
    // below fires when the record budget is spent, and that has to stop the
    // whole pass. Left on the inner loop it would only finish this archetype
    // and start the next, quietly overrunning the budget once per group.
    _clock
      ..reset()
      ..start();
    outer:
    for (final group in _renderables.groups()) {
      final renderable = group.get<Renderable2D>();
      final sprites = renderable.sprites;
      // Resolved once per archetype and carried through the queue, so the
      // write pass never asks - see `_SpriteDrawQueue._sources`.
      final source = _sourceOf(group);
      for (final entity in group) {
        if (onlyScene >= 0 && entity.sceneSlot != onlyScene) continue;
        // An indexed loop, not `for (final sprite in sprites)`: this runs once
        // per entity per tick and a fresh iterator is a heap object (RULES.md
        // rules 1 and 5).
        for (var i = 0; i < sprites.length; i++) {
          final sprite = sprites[i];
          // Invisible sprites are dropped here, before they are ever a record -
          // not emitted transparent. A transparent quad still costs a record,
          // six vertices and a share of the batch limit, and would still occlude
          // nothing while pretending to be drawn.
          if (sprite.visible[entity] == 0) continue;
          // Read into locals rather than compared in place: the geometry below
          // needs both, and this row is only cheap to touch while the walk is
          // still on it.
          final width = sprite.width[entity];
          final height = sprite.height[entity];
          if (width == 0 || height == 0) continue;
          final records = _isNineSliced(entity, sprite) ? 9 : 1;
          // Checked against this sprite's own cost, not against a fixed 1, so a
          // nine-sliced sprite is admitted only if all nine of its records fit.
          // Admitting it partially would write past the scratch.
          if (queue.recordCount + records > limit) break outer;
          final slot = queue.add(
            entity,
            sprite,
            source,
            sprite.zIndex[entity],
            records,
          );
          // A nine-sliced sprite cannot be reduced to four corners, so it keeps
          // reading its row in the write pass. That is the rare path and it is
          // left alone deliberately; what follows is for the plain quad, which
          // is almost everything almost always.
          if (records != 1) continue;

          // The geometry, computed here rather than in the write pass, and
          // this placement is the entire optimisation - see
          // `_SpriteDrawQueue`'s class doc. Every read below lands on the row
          // this loop is already standing on, in page order. The write pass
          // reads the answer out of a dense array instead of coming back for
          // the row in z order, which on a phone was a cache miss per sprite.
          final rotation = source.rotation[entity];
          // The unrotated fast path. `math.cos(0.0)` is exactly 1.0 and
          // `math.sin(0.0)` exactly 0.0, so this is a shortcut and not an
          // approximation - the geometry is bit-identical either way.
          //
          // On the device this currently measures as free, because the trig ran
          // inside the memory stalls this restructure exists to remove. It is
          // kept because removing those stalls is exactly what makes arithmetic
          // start to matter again.
          final double cos;
          final double sin;
          if (rotation == 0) {
            cos = 1.0;
            sin = 0.0;
          } else {
            cos = math.cos(rotation);
            sin = math.sin(rotation);
          }
          final tx = projection.worldToViewX(source.x[entity]);
          final ty = projection.worldToViewY(source.y[entity]);
          // The pivot is a point inside the sprite's own `width x height`
          // bounds, measured from its top-left: `fraction * size + offset`. The
          // transform origin sits on it, so the sprite's local extents run from
          // `-pivot` to `size - pivot`. The default (fraction 0.5, offset 0)
          // gives exactly `-size/2 .. +size/2`.
          final pivotX =
              sprite.pivotFractionX[entity] * width +
              sprite.pivotOffsetX[entity];
          final pivotY =
              sprite.pivotFractionY[entity] * height +
              sprite.pivotOffsetY[entity];
          // Zoom folds into the scale for the same reason it folds into
          // `tx`/`ty`: one multiply here beats a second pass over four corners.
          final scaleX = source.scaleX[entity] * zoom;
          final scaleY = source.scaleY[entity] * zoom;
          final lx0 = -pivotX * scaleX;
          final lx1 = (width - pivotX) * scaleX;
          final ly0 = -pivotY * scaleY;
          final ly1 = (height - pivotY) * scaleY;
          // Rotating the four local corners and translating. Eight products
          // for four corners, because each corner reuses one of two x-terms and
          // one of two y-terms.
          final ax0 = lx0 * cos;
          final ax1 = lx1 * cos;
          final ay0 = lx0 * sin;
          final ay1 = lx1 * sin;
          final bx0 = ly0 * sin;
          final bx1 = ly1 * sin;
          final by0 = ly0 * cos;
          final by1 = ly1 * cos;
          // The texture reaches the record as an *address*, never an image.
          // This isolate has no Flutter engine and every `Texture` on it is
          // declared-but-never-decoded, by design.
          final texture = sprite.texture[entity];
          queue.setQuad(
            slot,
            tx + ax0 - bx0,
            ty + ay0 + by0, // (left,  top)
            tx + ax1 - bx0,
            ty + ay1 + by0, // (right, top)
            tx + ax1 - bx1,
            ty + ay1 + by1, // (right, bottom)
            tx + ax0 - bx1,
            ty + ay0 + by1, // (left,  bottom)
            sprite.color[entity],
            texture == null ? DrawSpriteData2D.noTexture : texture.pack(),
            sprite.filter[entity],
          );
        }
      }
    }
    lastWalkMicros = _clock.elapsedMicroseconds;

    _clock
      ..reset()
      ..start();
    // Timed either way, so an ablated run reports `sort` near zero and the
    // change lands visibly in `write` rather than vanishing from both.
    if (!debugSkipZSort) queue.sortByZ();
    lastSortMicros = _clock.elapsedMicroseconds;

    // Pass two: emit the records, in draw order.
    //
    // For a plain sprite this no longer computes anything and no longer reads a
    // component row - the fill pass did both while it was already standing on
    // the row, and left the finished quad in a dense array. All that happens
    // here is a permutation over 40 bytes per sprite. See `_SpriteDrawQueue`'s
    // class doc for the device measurement that forced the split.
    _clock
      ..reset()
      ..start();
    var offset = DrawData2D.batchHeaderBytes;
    final count = queue.length;
    for (var i = 0; i < count; i++) {
      if (queue.recordsAt(i) == 1) {
        offset = queue.writeQuadAt(view, offset, i);
        continue;
      }

      // The nine-slice path, deliberately left reading rows in z order. It is
      // rare - a sliced sprite is a UI frame, not a particle - and it cannot
      // use the precomputed corners, because nine cells each need their own
      // sub-rectangle of the UV square. Paying a cache miss per sliced sprite
      // is the right trade against carrying a second, wider precompute layout
      // for a case that is a handful of sprites per frame.
      final entity = queue.entityAt(i);
      final sprite = queue.spriteAt(i);
      final source = queue.sourceAt(i);
      final width = sprite.width[entity];
      final height = sprite.height[entity];
      final rotation = source.rotation[entity];
      final double cos;
      final double sin;
      if (rotation == 0) {
        cos = 1.0;
        sin = 0.0;
      } else {
        cos = math.cos(rotation);
        sin = math.sin(rotation);
      }
      final tx = projection.worldToViewX(source.x[entity]);
      final ty = projection.worldToViewY(source.y[entity]);
      final pivotX =
          sprite.pivotFractionX[entity] * width + sprite.pivotOffsetX[entity];
      final pivotY =
          sprite.pivotFractionY[entity] * height + sprite.pivotOffsetY[entity];
      final scaleX = source.scaleX[entity] * zoom;
      final scaleY = source.scaleY[entity] * zoom;
      // One read. `_isNineSliced` already established this is non-null, and
      // resolving the field twice would be two row reads for one answer.
      final texture = sprite.texture[entity]!;
      offset = _writeNineSlice(
        view,
        offset,
        entity,
        sprite,
        texture,
        width,
        height,
        pivotX,
        pivotY,
        scaleX,
        scaleY,
        cos,
        sin,
        tx,
        ty,
        sprite.color[entity],
        texture.pack(),
        sprite.filter[entity],
      );
    }

    lastWriteMicros = _clock.elapsedMicroseconds;
    lastSpriteCount = count;
    lastRecordCount = queue.recordCount;
    // One record for the whole tick - see draw_2d.dart's library doc for why
    // this is not one record per sprite.
    //
    // The allocation ledger for this method, in full: this `sublistView`, and
    // one iterator per `Query.run()` call (two of them now - renderables and
    // cameras - where there used to be one). Both are per *tick* and constant
    // in the number of entities and sprites; the same trade `Game.dispatch
    // Command` already makes. Nothing in either loop above allocates: the
    // queue reuses its arrays, the sort has no comparator object, the corner
    // maths is all local doubles, and `Entity.get` is a list index plus an
    // `is` test. The texture read has that same shape - an optional-field bit
    // test, then an asset-table list index and an `is` test handing
    // back the instance that already exists - and `writeQuad`'s named
    // arguments are statically resolved, so they compile to positional ones
    // and build no argument object.
    // Into the slot the handoff already handed over, then published. The copy
    // is the same one `RingBuffer.tryWrite` used to make, so this is not a new
    // cost - and the `asTypedList` view is one object per *frame*, matching the
    // `sublistView` it replaces. Writing the geometry straight into the slot
    // and skipping the scratch entirely is possible and is the obvious next
    // step; it needs the per-slot views cached, which needs care about the
    // spawn (a typed-data view of native memory is deep-copied by value), so
    // it is deliberately not smuggled in here.
    target.asTypedList(spriteBatchBytes).setRange(0, offset, scratch);
    frames.publish(offset);
    lastWriteDropped = false;
  }
}
