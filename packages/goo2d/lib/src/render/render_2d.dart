import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:goo/goo.dart';
import 'package:goo2d/src/data/camera.dart';
import 'package:goo2d/src/data/world_transform.dart';
import 'package:goo2d/src/render/draw/draw_2d.dart';
import 'package:goo2d/src/render/texture.dart';

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
  static const RelativeOffset2D center =
      RelativeOffset2D(fractionX: 0.5, fractionY: 0.5);

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
  /// Stored as the asset's registry address (`optObject`), which is the same
  /// integer on both isolates - see `Texture`'s own doc on why the game
  /// isolate holds an addressed-but-never-decoded copy.
  final DataPointer<Texture?> texture;

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
/// `onMounted` write at all.
class SpriteDescriptor {
  SpriteDescriptor._(this._data, this._sprites);

  final DataDescriptor _data;
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
    Texture? texture,
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
      texture: _data.optObject<Texture>(texture),
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

/// Marks an entity as something the renderer should draw, and carries the
/// [Sprite]s it draws as.
///
/// An entity mixing this in **must** also mix in `Transform2D` and
/// `WorldTransform2D` - there is no meaningful place to draw something that
/// has no position, and requiring it in the query (rather than defaulting to
/// the origin) turns "I forgot the transform" into an entity that visibly
/// never appears rather than a pile of quads stacked at 0,0.
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
  void describeSprites(SpriteDescriptor descriptor);

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
    describeSprites(SpriteDescriptor._(data, sprites));
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
final class _SpriteDrawQueue {
  _SpriteDrawQueue({int initialCapacity = 64})
    : _entities = List<Entity>.filled(initialCapacity, const Entity(0)),
      _sprites = List<Sprite?>.filled(initialCapacity, null),
      _zIndices = Int32List(initialCapacity),
      _records = Int32List(initialCapacity),
      _order = Int32List(initialCapacity),
      _merge = Int32List(initialCapacity);

  List<Entity> _entities;
  List<Sprite?> _sprites;
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

  /// The merge sort's second buffer. Swapped with [_order] rather than copied
  /// back - both are owned scratch of identical length, so the swap is two
  /// field writes.
  Int32List _merge;

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
  /// costing [records] draw records.
  void add(Entity entity, Sprite sprite, int zIndex, int records) {
    _ensure(_count + 1);
    _entities[_count] = entity;
    _sprites[_count] = sprite;
    _zIndices[_count] = zIndex;
    _records[_count] = records;
    _order[_count] = _count;
    _count++;
    _recordTotal += records;
  }

  /// The entity of the [i]th pair *in draw order*.
  Entity entityAt(int i) => _entities[_order[i]];

  /// The sprite of the [i]th pair *in draw order*.
  Sprite spriteAt(int i) => _sprites[_order[i]]!;

  /// How many records the [i]th pair *in draw order* writes.
  int recordsAt(int i) => _records[_order[i]];

  /// Sorts the queued pairs by `zIndex` ascending, keeping equal-`zIndex`
  /// pairs in the order they were added.
  ///
  /// A hand-written bottom-up merge sort rather than `List.sort`, for two
  /// reasons that both come straight from RULES.md rule 1:
  ///
  ///  * **It sorts a prefix.** `List.sort` sorts a whole list, and the only
  ///    ways to hand it exactly `_count` elements are a `sublistView`
  ///    (an allocation every tick) or a growable list whose `clear()` is free
  ///    to shrink its backing store (an allocation every tick, at the SDK's
  ///    discretion). Sorting `[0, _count)` of a fixed array has neither
  ///    problem.
  ///  * **It needs no comparator object.** There is no closure here at all -
  ///    not a fresh lambda per tick, not even a long-lived function reference
  ///    - because the comparison is inlined into the merge.
  ///
  /// Stability is structural, not incidental: `<=` takes from the left run
  /// whenever the keys tie, and the left run is always the
  /// earlier-encountered one. That is what preserves query order among
  /// equal-`zIndex` sprites, which is the ordering this system had before
  /// `zIndex` existed at all.
  void sortByZ() {
    final n = _count;
    if (n < 2) return;
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
    _zIndices = Int32List(next)..setRange(0, _count, _zIndices);
    _records = Int32List(next)..setRange(0, _count, _records);
    _order = Int32List(next)..setRange(0, _count, _order);
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
class GameRenderer2D extends GameSystem with Tickable {
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

  /// The auxiliary buffer this system declares and writes into, and that
  /// `GameView` reads on the other side.
  ///
  /// A [BufferHandle] rather than a name (RULES.md rule 6): the *same* field
  /// on the *same* declared system resolves it on both isolates, because both
  /// copies of the `Game` run this system's `describeBuffers`. A consumer
  /// reaches it through `game.getSystem<GameRenderer2D>().drawBuffer` - a
  /// typed path the analyzer checks, where the old `getBuffer('...')` was a
  /// string two packages had to agree on.
  late final HandoffHandle drawFrames;

  /// Sprites past this many in a single tick are dropped. A hard bound rather
  /// than a growing buffer on purpose: the byte scratch and the ring are both
  /// sized from it, and silently growing them mid-tick is an allocation on the
  /// hot path. Override it if a scene genuinely draws more.
  ///
  /// Note this counts *sprites*, not entities - an entity declaring three
  /// sprites spends three of them.
  int get maxSpritesPerTick => 4096;

  /// Bytes one tick's sprite batch occupies, including its tick stamp.
  int get spriteBatchBytes =>
      DrawData2D.batchHeaderBytes + maxSpritesPerTick * DrawSpriteData2D.strideBytes;

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

  /// How many draw records the last [onTick] wrote - quads, not sprites.
  ///
  /// This is what `maxSpritesPerTick` bounds and what `spriteBatchBytes`
  /// is sized from, so it is the number to watch when a scene starts
  /// dropping frames.
  int lastRecordCount = 0;

  /// True if the last [onTick] could not fit its batch in the ring.
  bool lastWriteDropped = false;

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
    _renderables = descriptor.query().withAll(Renderable2D, WorldTransform2D).build();
    // The camera is queried, not configured on this system: "where the view
    // is" is a property of an entity in the scene that the simulation can move
    // like any other, not a field a presentation system owns. Requiring
    // `WorldTransform2D` on it as well means a camera parented to the player
    // works with no special case here.
    _cameras = descriptor.query().withAll(Camera, WorldTransform2D).build();
  }

  @override
  void describeBuffers(BufferDescriptor descriptor) {
    super.describeBuffers(descriptor);
    drawFrames = descriptor.hasHandoff(slotBytes: spriteBatchBytes);
  }

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
    Texture texture,
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
    final sw = texture.sourceWidth.toDouble();
    final sh = texture.sourceHeight.toDouble();
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
          tx + ax0 - by0, ty + sy0 + cy0, // (left,  top)
          tx + ax1 - by0, ty + sy1 + cy0, // (right, top)
          tx + ax1 - by1, ty + sy1 + cy1, // (right, bottom)
          tx + ax0 - by1, ty + sy0 + cy1, // (left,  bottom)
          color,
          textureAddress: address,
          u0: u[col], v0: v[row],
          u1: u[col + 1], v1: v[row],
          u2: u[col + 1], v2: v[row + 1],
          u3: u[col], v3: v[row + 1],
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
    return texture != null && texture.hasSourceSize;
  }

  @override
  void onTick(Duration delta) {
    // Asked *before* any work is done, and that ordering is the point. Null
    // means main has not taken the last frame yet, so there is nowhere safe to
    // write - and rather than build a frame and throw it away, the whole pass
    // is skipped. The simulation is unaffected; only the drawing stops, and
    // only while nobody is looking. This is what stops a 200Hz tick building
    // and discarding two frames out of every three against a 60Hz display.
    final frames = drawFrames.tryBuffer;
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

    // Presentation runs after `commitTick`, which is also after `Game.tick`
    // was bumped - so the tick whose state this batch depicts is the current
    // one, not one past it. Deriving the stamp instead of keeping a counter
    // means a disabled-then-reenabled renderer cannot drift out of step with
    // the simulation it is depicting.
    DrawData2D.writeBatchTick(view, game.tick);

    // Through `CameraProjection` rather than reading the camera's fields
    // here, so this and `MousePickingSystem` cannot end up applying two
    // slightly different mappings - picking that disagreed with drawing by a
    // constant would mean clicking next to what you can see. No camera is
    // not an error: the projection resolves to the identity plus centring.
    final projection = _projection..resolve(_cameras, game.viewWidth, game.viewHeight);
    final zoom = projection.zoom;

    // Pass one: collect what is going to be drawn. Nothing is written to the
    // byte scratch yet, because the order is not known until every candidate
    // has been seen.
    final queue = _queue..reset();
    // A *record* budget, not a sprite count. A nine-sliced sprite writes nine
    // records, so counting sprites would let nine times the declared maximum
    // through and overrun the byte scratch, which is sized from this same
    // number times the record stride. Counting records keeps the two honest
    // against each other whatever mix of sliced and plain sprites shows up.
    final limit = maxSpritesPerTick;
    // Which scene is front, resolved once per frame rather than per entity.
    // `switchScene` is informational - every loaded scene keeps ticking - and
    // this is the framework honouring it: a preloaded level simulates in the
    // background without being painted over the one the player is looking at.
    // -1 when nothing is loaded, which matches nothing.
    final activeSlot = SceneRegistry.active?.slot ?? -1;
    outer:
    for (final entity in _renderables.run()) {
      if (entity.sceneSlot != activeSlot) continue;
      final renderable = entity.get<Renderable2D>();
      final sprites = renderable.sprites;
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
        if (sprite.width[entity] == 0 || sprite.height[entity] == 0) continue;
        final records = _isNineSliced(entity, sprite) ? 9 : 1;
        // Checked against this sprite's own cost, not against a fixed 1, so a
        // nine-sliced sprite is admitted only if all nine of its records fit.
        // Admitting it partially would write past the scratch.
        if (queue.recordCount + records > limit) break outer;
        queue.add(entity, sprite, sprite.zIndex[entity], records);
      }
    }
    queue.sortByZ();

    // Pass two: geometry, in draw order.
    var offset = DrawData2D.batchHeaderBytes;
    final count = queue.length;
    for (var i = 0; i < count; i++) {
      final entity = queue.entityAt(i);
      final sprite = queue.spriteAt(i);
      final width = sprite.width[entity];
      final height = sprite.height[entity];

      // Read, don't recompose. `WorldTransformSystem` already walked the
      // hierarchy during the tick that just committed, and these are its
      // published results - see this class's `compareTo` doc for why that is
      // both fresh enough and the reason the old private composition is gone.
      final world = entity.get<WorldTransform2D>();
      final cos = math.cos(world.worldRotation[entity]);
      final sin = math.sin(world.worldRotation[entity]);
      final tx = projection.worldToViewX(world.worldX[entity]);
      final ty = projection.worldToViewY(world.worldY[entity]);

      // The pivot is a point inside the sprite's own `width x height` bounds,
      // measured from its top-left: `fraction * size + offset`. The transform
      // origin sits on it, so the sprite's local extents run from `-pivot` to
      // `size - pivot`. The default (fraction 0.5, offset 0) gives exactly
      // `-size/2 .. +size/2` - the centred quad this system has always drawn -
      // and fraction 0 gives `0 .. size`, i.e. the origin on the top-left
      // corner.
      final pivotX = sprite.pivotFractionX[entity] * width + sprite.pivotOffsetX[entity];
      final pivotY = sprite.pivotFractionY[entity] * height + sprite.pivotOffsetY[entity];
      // Zoom folds into the scale for the same reason it folds into `tx`/`ty`
      // above: one multiply here beats a second pass over four corners.
      final scaleX = world.worldScaleX[entity] * zoom;
      final scaleY = world.worldScaleY[entity] * zoom;
      final lx0 = -pivotX * scaleX;
      final lx1 = (width - pivotX) * scaleX;
      final ly0 = -pivotY * scaleY;
      final ly1 = (height - pivotY) * scaleY;

      // Rotating the four local corners and translating, written out rather
      // than routed through a helper so the loop stays free of per-sprite
      // calls returning pairs (which would be a record, i.e. an allocation).
      // Eight products for four corners, because each corner reuses one of
      // two x-terms and one of two y-terms.
      final ax0 = lx0 * cos;
      final ax1 = lx1 * cos;
      final ay0 = lx0 * sin;
      final ay1 = lx1 * sin;
      final bx0 = ly0 * sin;
      final bx1 = ly1 * sin;
      final by0 = ly0 * cos;
      final by1 = ly1 * cos;

      // The texture reaches the record as an *address*, never as an image.
      // Reading the field resolves the row's `Uint32` back to the declared
      // `Texture` instance through `GlobalObjectRegistry` - which exists on
      // this isolate and is allocation-free - and all that is taken from it is
      // `.address`. `.image` is never touched here and could not be: this
      // isolate has no Flutter engine and every `Texture` on it is
      // declared-but-never-decoded, by design (see `Texture`'s class doc).
      //
      final texture = sprite.texture[entity];
      final color = sprite.color[entity];
      final address =
          texture == null ? DrawSpriteData2D.noTexture : texture.address;

      if (queue.recordsAt(i) == 1) {
        offset = DrawSpriteData2D.writeQuad(
          view,
          offset,
          tx + ax0 - bx0, ty + ay0 + by0, // (left,  top)
          tx + ax1 - bx0, ty + ay1 + by0, // (right, top)
          tx + ax1 - bx1, ty + ay1 + by1, // (right, bottom)
          tx + ax0 - bx1, ty + ay0 + by1, // (left,  bottom)
          color,
          textureAddress: address,
          // The whole texture, in the same corner order the positions use.
          u0: 0, v0: 0, // (left,  top)
          u1: 1, v1: 0, // (right, top)
          u2: 1, v2: 1, // (right, bottom)
          u3: 0, v3: 1, // (left,  bottom)
        );
      } else {
        offset = _writeNineSlice(
          view,
          offset,
          entity,
          sprite,
          texture!,
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
          color,
          address,
        );
      }
    }

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
    // test, then a `GlobalObjectRegistry` list index and an `is` test handing
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
