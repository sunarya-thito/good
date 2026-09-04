import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:good/good.dart';
import 'package:goo2d/src/data/camera.dart';
import 'package:goo2d/src/data/screen_transform.dart';
import 'package:goo2d/src/data/world_transform.dart';
import 'package:goo2d/src/data/transform.dart';
import 'package:goo2d/src/render/debug_draw_2d.dart';
import 'package:goo2d/src/render/draw/draw_2d.dart';
// Mutual with this file: `Renderer2D` and `GameRenderer2D` are the two
// isolate-halves of one feature. The Game mixin declares and drains the frame
// buffers; this system fills them.
import 'package:goo2d/src/render/game_2d.dart';
import 'package:goo2d/src/render/text_2d.dart';
import 'package:goo2d/src/render/texture.dart';
import 'package:meta/meta.dart';

/// A position expressed as a fraction of some size *plus* an absolute offset,
/// evaluated as `fraction * size + offset`.
///
/// Both halves at once. "Half way across, and then 200 units further" is a
/// single sentence in every UI system worth copying (CSS `calc(50% + 200px)`,
/// Unity's `RectTransform` anchor + `anchoredPosition`, Flutter's
/// `FractionalOffset` alongside `Offset`), and a type offering only one of
/// the two would force every caller that needs both to bake the size into a
/// constant at declare time - which is exactly the number that is not known
/// then. So [fractionX]/[fractionY] scale with the size this is resolved
/// against and [offsetX]/[offsetY] do not, and the resolved answer is the sum.
///
/// # This is a parameter type, never a storage type
///
/// A `DataPointer<T>` holds a `num` or a `GlobalObject` and nothing else (see
/// `good`'s `data.dart`), so no component row anywhere stores a
/// `RelativeOffset2D`. This type exists to make *declaring* a default
/// readable (`pivot: RelativeOffset2D.center`) and to make a runtime change
/// one call instead of four (`sprite.setPivot(entity, ...)`); the storage
/// underneath is always four separate `DataPointer<double>` fields, and a
/// *read* returns those four fields individually. There is no
/// `getPivot(entity)` returning one of these, and there should not be:
/// building one per read is a heap allocation on the hot path, which the
/// no-allocation rule forbids outright.
class RelativeOffset2D {
  const RelativeOffset2D({
    this.fractionX = 0,
    this.fractionY = 0,
    this.offsetX = 0,
    this.offsetY = 0,
  });

  /// Multiplied by the width this is resolved against.
  final double fractionX;

  /// Multiplied by the height this is resolved against.
  final double fractionY;

  /// Added afterwards, in world units, independent of that size.
  final double offsetX;

  /// Added afterwards, in world units, independent of that size.
  final double offsetY;

  /// The middle of whatever this is resolved against - a sprite's own bounds,
  /// for a pivot. The default pivot, and what makes rotation and scale act
  /// about a sprite's centre.
  static const RelativeOffset2D center = RelativeOffset2D(
    fractionX: 0.5,
    fractionY: 0.5,
  );

  /// Top-left, with no offset - the pivot that puts the transform origin on
  /// the sprite's own top-left corner.
  static const RelativeOffset2D zero = RelativeOffset2D();
}

/// Which part of its texture a sprite samples - the whole thing by default,
/// or one cell of a sprite sheet, or one region of a packed atlas.
///
/// # Normalised, not pixels
///
/// The four numbers are fractions of the texture, `0..1`, and that is what lets
/// a frame be computed on the isolate that draws. A *uniform grid* needs no
/// pixel size at all: cell 5 of an 8x4 sheet is `(5/8, 0, 1/8, 1/4)` whether
/// the image is 512px or 2048px. So `GameRenderer2D`, which runs where nothing
/// is decoded and no `ui.Image` exists, can frame a sprite with no
/// cross-isolate metadata and nothing loaded.
///
/// Authoring in pixels still works - see [SpriteFrame.pixels] - the division
/// just happens once, at declare time, where the sheet's dimensions are a
/// constant the author is looking at anyway.
///
/// # It packs into the row, it is never stored in it
///
/// A component row holds the 64-bit integer [pack] produces, four `u16`s of
/// it, and a `SpriteFrame` object exists only at the authoring boundary. The
/// renderer reads the raw integer through [PackedPointer.packedAt] and does
/// the shifts itself, so drawing 20,000 framed sprites allocates nothing.
///
/// `u16` quantisation is 1/65535 of the texture: 1/16th of a pixel on a 4096px
/// sheet, and finer on anything smaller. Every atlas packer already pads
/// regions to survive bilinear sampling, so that is well inside a margin that
/// exists regardless.
@immutable
class SpriteFrame implements IntRepresentable {
  const SpriteFrame({
    required this.u,
    required this.v,
    required this.width,
    required this.height,
  });

  /// Cell [index] of a uniform [columns] x [rows] sheet, row-major.
  ///
  /// Exact whatever the image's pixel size, which is the whole argument for
  /// normalised frames - there is no source dimension in this constructor
  /// because none is needed.
  const SpriteFrame.grid({
    required int columns,
    required int rows,
    required int index,
  }) : u = (index % columns) / columns,
       v = (index ~/ columns) / rows,
       width = 1 / columns,
       height = 1 / rows;

  /// A pixel rectangle on a sheet of a stated size - for a packed atlas, or
  /// any region a grid cannot describe.
  ///
  /// The division happens here, at declare time. [sheetWidth]/[sheetHeight]
  /// are the *source image's* dimensions; nothing at draw time has to know
  /// them.
  ///
  /// Pass them from the generated `TextureSize`, which `good generate` fills
  /// from the image headers:
  ///
  /// ```dart
  /// const face = SpriteFrame.pixels(
  ///   x: 128, y: 64, width: 96, height: 32,
  ///   sheetWidth: TextureSize.uiButtonWidth,
  ///   sheetHeight: TextureSize.uiButtonHeight,
  /// );
  /// ```
  ///
  /// Those are `static const int`, so this stays a `const` expression and a
  /// re-export at a new size needs no edit here.
  const SpriteFrame.pixels({
    required int x,
    required int y,
    required int width,
    required int height,
    required int sheetWidth,
    required int sheetHeight,
  }) : u = x / sheetWidth,
       v = y / sheetHeight,
       width = width / sheetWidth,
       height = height / sheetHeight;

  /// Left edge of the region, as a fraction of the texture's width.
  final double u;

  /// Top edge of the region, as a fraction of the texture's height.
  final double v;

  /// Width of the region, as a fraction of the texture's width.
  final double width;

  /// Height of the region, as a fraction of the texture's height.
  final double height;

  /// The whole texture - the default, and what an untextured sprite carries
  /// harmlessly.
  static const SpriteFrame full = SpriteFrame(u: 0, v: 0, width: 1, height: 1);

  /// True when this frame is the whole texture, i.e. there is nothing to
  /// offset. Named, and not four inline comparisons, matching
  /// [NineSliceBorder.isEmpty].
  bool get isFull => u == 0 && v == 0 && width == 1 && height == 1;

  static const int _scale = 0xFFFF;

  /// Lane index of the frame's left edge in a packed frame.
  static const int laneU0 = 0;

  /// Lane index of the frame's top edge.
  static const int laneV0 = 1;

  /// Lane index of the frame's right edge.
  static const int laneU1 = 2;

  /// Lane index of the frame's bottom edge.
  static const int laneV1 = 3;

  static int _quantise(double fraction) {
    final scaled = (fraction * _scale).round();
    return scaled < 0
        ? 0
        : scaled > _scale
        ? _scale
        : scaled;
  }

  /// Four `u16` lanes, holding the frame's **edges** - `u0, v0, u1, v1` - not
  /// its origin and extent.
  ///
  /// Edges, and not `(u, v, width, height)`, because quantising the two
  /// independently lets their sum drift past the region: at `u = 0.5` and
  /// `width = 0.5` both round *up*, and `u + width` comes back as
  /// `1.0000152...` - a right edge outside the texture. Storing the edge
  /// quantises the number that is actually used, so `1` stays exactly `1` and a
  /// full frame round-trips bit for bit.
  ///
  /// The top lane occupies bits 48..63, so this returns a **negative** `int`
  /// whenever `v1 > 0.5` - Dart's `int` is signed. Harmless as long as nothing
  /// sign-extends on the way back, so [unpackLane] shifts with `>>>`.
  /// `Entity.pack` carries the same hazard for the same reason; see
  /// `data.dart`'s note on 64-bit fields.
  @override
  int pack() =>
      _quantise(u) |
      (_quantise(v) << 16) |
      (_quantise(u + width) << 32) |
      (_quantise(v + height) << 48);

  /// Edge [lane] of a packed frame - see [laneU0], [laneV0], [laneU1], [laneV1]
  /// - as its `0..1` fraction.
  ///
  /// Static and lane-at-a-time so the renderer can read what it needs off the
  /// raw integer without materialising a `SpriteFrame`. Unsigned shift, always:
  /// see [pack].
  static double unpackLane(int bits, int lane) =>
      ((bits >>> (lane << 4)) & _scale) / _scale;

  /// Rebuilds a frame from [pack]'s output. Authoring and diagnostics only -
  /// the draw path uses [unpackLane].
  factory SpriteFrame.unpack(int bits) {
    final u = unpackLane(bits, laneU0);
    final v = unpackLane(bits, laneV0);
    return SpriteFrame(
      u: u,
      v: v,
      width: unpackLane(bits, laneU1) - u,
      height: unpackLane(bits, laneV1) - v,
    );
  }

  @override
  String toString() =>
      'SpriteFrame(u: $u, v: $v, width: $width, height: $height)';
}

/// [SpriteFrame]'s [IntRepresentation] - and a *stateless* one.
///
/// There is no table here and nothing to look up: the integer in the row **is**
/// the frame, so unpacking is arithmetic. That is why this is `const`, why it
/// needs no declare pass, why nothing has to be kept in sync across isolates,
/// and why a frame can be computed at run time - a scrolling UV, an animation
/// stepping `index`, anything - with no declaration at all.
///
/// The encoding sits entirely behind this class. Swapping it for a table of
/// declared regions indexed by the integer - which buys exact float precision
/// and a 2-byte field instead of 8, at the cost of a declare step and of
/// runtime-computed frames - touches this file and `bitWidth`, not `Sprite`,
/// not the renderer, not any authoring code.
final class SpriteFrames implements IntRepresentation<SpriteFrame> {
  const SpriteFrames();

  /// Four `u16` lanes. See [SpriteFrame.pack] for why 64 and not 32: at
  /// `u8` per lane the quantisation step is 16px on a 4096px sheet, which is
  /// useless for a packed atlas.
  @override
  int get bitWidth => 64;

  @override
  SpriteFrame unpack(int bits) => SpriteFrame.unpack(bits);

  /// Never null: every 64-bit pattern is a valid frame. Present because
  /// [IntRepresentation] requires it, and returning null would claim a failure
  /// mode this encoding does not have.
  @override
  SpriteFrame? tryUnpack(int bits) => SpriteFrame.unpack(bits);
}

/// The four insets of a nine-slice: how far in from each edge the stretchable
/// middle region starts.
///
/// All-zero (the default, [none]) means there is nothing to slice and the
/// sprite is a single quad - so [isEmpty] exists as a named question instead
/// of four inline comparisons at each call site.
///
/// # The source cut is relative; the destination inset is not
///
/// A nine-slice is two separate statements about the same four edges:
///
///  * **where to cut the source** - a position *inside* the image, so it is
///    naturally a fraction of it. [left] and friends.
///  * **how big the corner is on screen** - the whole definition of a
///    nine-slice is that this stays fixed while the middle stretches, so it
///    cannot be a fraction of the sprite: scale the sprite and a fractional
///    corner scales with it, which is a plain stretch and not a nine-slice at
///    all. [insetLeft] and friends, in the sprite's own units.
///
/// One set of numbers doing both jobs has to assume that one sprite unit is
/// one source pixel. [pixels]'s `unitsPerPixel` states that instead of
/// implying it, and defaults to the `1` that assumption amounts to.
///
/// Making the cut relative is what frees nine-slicing from needing the image's
/// pixel size: the game isolate, which never decodes, can slice with nothing
/// loaded and no `TextureInfo` at all. Fractions are of the sprite's
/// [SpriteFrame] when it has one, so a panel packed into an atlas slices inside
/// its own region - see `GameRenderer2D`'s nine-slice pass.
@immutable
class NineSliceBorder {
  /// The general form: source cuts as fractions, destination corners in sprite
  /// units. Prefer [pixels], which derives both from the numbers an artist
  /// actually has.
  const NineSliceBorder({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
    this.insetLeft = 0,
    this.insetTop = 0,
    this.insetRight = 0,
    this.insetBottom = 0,
  });

  /// Pixel insets on a source of a stated size - the ordinary way to author
  /// one, and the only place a pixel dimension appears.
  ///
  /// Divides once, here, at declare time: [left] and friends become fractions
  /// of the source, and the destination corners become `pixels *
  /// unitsPerPixel`. Nothing at draw time needs the source size, which is the
  /// whole point.
  ///
  /// [sourceWidth]/[sourceHeight] are the texture's pixel dimensions. Pass
  /// them from the generated `TextureSize.<asset>Width` and
  /// `TextureSize.<asset>Height`, which are `static const int` and keep this a
  /// `const` expression.
  ///
  /// [unitsPerPixel] converts source pixels to the sprite's own units, and
  /// defaults to `1`.
  const NineSliceBorder.pixels({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
    required int sourceWidth,
    required int sourceHeight,
    double unitsPerPixel = 1,
  }) : left = left / sourceWidth,
       top = top / sourceHeight,
       right = right / sourceWidth,
       bottom = bottom / sourceHeight,
       insetLeft = left * unitsPerPixel,
       insetTop = top * unitsPerPixel,
       insetRight = right * unitsPerPixel,
       insetBottom = bottom * unitsPerPixel;

  /// The common case for a symmetric frame: the same pixel inset on all four
  /// edges of a square source.
  ///
  /// [sourceSize] is that square's side in pixels -
  /// `TextureSize.<asset>Width` from the generated bindings, where the texture
  /// is one the project ships.
  const NineSliceBorder.all(
    double inset, {
    required int sourceSize,
    double unitsPerPixel = 1,
  }) : left = inset / sourceSize,
       top = inset / sourceSize,
       right = inset / sourceSize,
       bottom = inset / sourceSize,
       insetLeft = inset * unitsPerPixel,
       insetTop = inset * unitsPerPixel,
       insetRight = inset * unitsPerPixel,
       insetBottom = inset * unitsPerPixel;

  /// Where to cut the source on the left, as a fraction `0..1` of the
  /// sprite's frame.
  final double left;

  /// Where to cut the source at the top. See [left].
  final double top;

  /// Where to cut the source on the right. See [left].
  final double right;

  /// Where to cut the source at the bottom. See [left].
  final double bottom;

  /// How wide the left corner is drawn, in the sprite's own units. Fixed
  /// under resize - that is what a nine-slice *is*.
  final double insetLeft;

  /// How tall the top corner is drawn. See [insetLeft].
  final double insetTop;

  /// How wide the right corner is drawn. See [insetLeft].
  final double insetRight;

  /// How tall the bottom corner is drawn. See [insetLeft].
  final double insetBottom;

  /// No slicing - a plain single quad.
  static const NineSliceBorder none = NineSliceBorder();

  /// True when there is nothing to slice, i.e. this sprite is a plain quad.
  ///
  /// Tests the **destination** insets, because those are what decide whether
  /// there are nine rectangles to draw: a source cut with no corner to put it
  /// in produces nothing. The renderer branches on the *stored* fields, not
  /// on an instance of this class; see [Sprite.insetLeft].
  bool get isEmpty =>
      insetLeft == 0 && insetTop == 0 && insetRight == 0 && insetBottom == 0;
}

/// One drawable rectangle belonging to an entity - what a single [of] call
/// declares.
///
/// An entity draws as many of these as it declared: a body plus a hat is two
/// fields, two independent sets of row fields, and two draw records.
/// That is the whole reason [Renderable2D] is a `MultiComponent` and these
/// fields do not live on the mixin itself - Dart cannot mix a mixin in twice,
/// so a second sprite has to come from a second field and not from a
/// second `with Renderable2D` (see `MultiComponent`'s own doc in `good`, and
/// `Collider2D`/`ColliderBody`, which are the same shape for the same
/// reason).
///
/// # Why it is a `CompositeDeclaration`
///
/// A sprite is twenty columns under one name. `Sprite.of(...)` builds them
/// all from a field initialiser, and [composedDeclarations] is how the scene
/// finds them: nothing in `good` knows what a sprite is, so the columns
/// reach the row layout by the sprite handing them over in the order it was
/// written. Without that, a field holding a sprite would reserve no row
/// space for any of them.
///
/// # Why the four-field groups
///
/// [pivotFractionX]/[pivotFractionY]/[pivotOffsetX]/[pivotOffsetY] are one
/// conceptual [RelativeOffset2D] stored as four `DataPointer<double>`s, and
/// the border group likewise. That is forced, not stylistic: a
/// `DataPointer<T>` stores a `num` or a `GlobalObject` and cannot hold a value
/// object of any kind. [setPivot] and [setNineSliceBorder] hide the unpacking
/// for writes; reads are the four fields, by design (see
/// [RelativeOffset2D]'s doc - a read that returned a fresh value object would
/// allocate per read, on the hot path).
class Sprite({
  /// The image this sprite samples, or `null` for "no texture - draw the flat
  /// [color]".
  ///
  /// Nullable, and not "a 1x1 white texture everyone falls back to": the
  /// untextured case is not a degenerate texture, it is the whole of what the
  /// pipeline draws today, and a null here is one branch instead of an asset
  /// every game is forced to declare.
  ///
  /// Stored as the asset's address (`Field.optAsset`), which is the same
  /// integer on both isolates - see `Texture`'s own doc on why the game
  /// isolate holds an addressed-but-never-decoded copy. The address is
  /// resolved against the table the registering scene owns, which is why
  /// [Sprite.of] names a key and not a handle.
  required final DataPointer<TextureAsset?> texture,

  /// How this sprite samples [texture] - a [TextureFilter] index.
  ///
  /// Per sprite, not per texture, and not per game. On the texture key,
  /// sampling would be part of an asset's *identity*: a build step that
  /// repacked an image would be rewriting it, and one image could not be drawn
  /// crisply in one place and smoothly in another. Per sprite is strictly
  /// wider - you can still give every sprite sharing an image the same filter.
  ///
  /// Two bits, because there are three [TextureFilter] values and a row pays
  /// for every one of them per entity.
  required final DataPointer<int> filter,

  /// Which part of [texture] this sprite samples - see [SpriteFrame].
  ///
  /// A [PackedPointer], so the renderer can read the packed integer without
  /// building a `SpriteFrame` per sprite per frame. Write it with [setFrame],
  /// which takes the value object.
  required final PackedPointer<SpriteFrame> frame,

  /// Packed ARGB, the same encoding `Color.value` and `Vertices.raw`'s colour
  /// list use. A plain `uint32`, never a `Color` object - a component row
  /// holds no Dart heap reference.
  ///
  /// With a [texture] set this is the tint; with none it is the fill.
  required final DataPointer<int> color,

  /// Width in world units, before the transform's scale. Zero on either axis
  /// (the declared default) means "nothing to draw" and is skipped, so a
  /// declared-but-unsized sprite costs one branch per tick.
  required final DataPointer<double> width,

  /// Height in world units, before the transform's scale. See [width].
  required final DataPointer<double> height,

  /// Painter's-algorithm depth. Lower draws first (further back), higher
  /// draws later (in front); equal values keep query/declaration order. See
  /// [GameRenderer2D]'s ordering section.
  required final DataPointer<int> zIndex,

  /// Whether this sprite draws. Set it false and the sprite produces no draw
  /// record at all - not a transparent one - so it costs the one branch that
  /// skips it and nothing downstream: no sort slot, no budget, no bytes on
  /// the ring.
  required final DataPointer<bool> visible,

  /// Where the transform origin sits *within this sprite's own bounds*,
  /// resolved against `(width, height)` as `fraction * size + offset`.
  ///
  /// Centred by default (`0.5, 0.5`), which is what makes rotation and scale
  /// act about the sprite's middle. `fractionX: 0, fractionY: 0` puts the
  /// origin on the top-left corner, so the sprite extends right and down from
  /// the entity's position.
  required final DataPointer<double> pivotFractionX,

  /// The pivot's y fraction. See [pivotFractionX].
  required final DataPointer<double> pivotFractionY,

  /// The pivot's absolute x offset, added after the fraction. See
  /// [pivotFractionX].
  required final DataPointer<double> pivotOffsetX,

  /// The pivot's absolute y offset. See [pivotFractionX].
  required final DataPointer<double> pivotOffsetY,

  /// Where the nine-slice cuts the **source**, as a fraction `0..1` of this
  /// sprite's [frame]. All zero by default.
  ///
  /// `float32`, not `float64` like the geometry fields: this is a `0..1`
  /// fraction with precision to spare there, and it is four more columns on
  /// every sprite row. See [NineSliceBorder] for why the cut is relative and
  /// the inset below is not.
  required final DataPointer<double> borderLeft,

  /// Where the nine-slice cuts the source at the top. See [borderLeft].
  required final DataPointer<double> borderTop,

  /// Where the nine-slice cuts the source on the right. See [borderLeft].
  required final DataPointer<double> borderRight,

  /// Where the nine-slice cuts the source at the bottom. See [borderLeft].
  required final DataPointer<double> borderBottom,

  /// How wide the nine-slice corners are drawn, in this sprite's own units.
  /// All zero by default, which means "plain single quad".
  ///
  /// Absolute, never relative: a fraction of the sprite would scale the
  /// corners with it, which is a stretch and not a nine-slice.
  /// [GameRenderer2D] branches on these to decide whether there are nine
  /// rectangles to draw at all.
  required final DataPointer<double> insetLeft,

  /// How tall the top nine-slice corner is drawn. See [insetLeft].
  required final DataPointer<double> insetTop,

  /// How wide the right nine-slice corner is drawn. See [insetLeft].
  required final DataPointer<double> insetRight,

  /// How tall the bottom nine-slice corner is drawn. See [insetLeft].
  required final DataPointer<double> insetBottom,
}) implements CompositeDeclaration {

  /// Declares one sprite. Keep the returned handle in a field - the field
  /// *is* the declaration, and the typed handle is what everything later
  /// reads and writes through (never a name to quote again).
  ///
  /// ```dart
  /// class Player extends EntityStruct with Transform2D, Renderable2D {
  ///   final body = Sprite.of(width: 64, height: 64, color: 0xFF3355AA);
  /// }
  /// ```
  ///
  /// Every named parameter doubles as that archetype's declared row default,
  /// so the common case needs no `onEntityMounted` write at all.
  ///
  /// [width] and [height] are **world units**, not pixels, so they are not
  /// the texture's dimensions and the generated `TextureSize` constants do
  /// not go here directly. Drawing at the art's native size is
  /// `TextureSize.<asset>Width * unitsPerPixel` for whatever scale the game
  /// works in.
  ///
  /// [texture] is an [AssetKey] and not a handle, because a field
  /// initialiser has no [Assets] to resolve one against - `Field.optAsset`
  /// resolves the key against the table the registering scene owns instead.
  /// Two sprites naming one key are one asset: the scene binds by key, so
  /// they share an address and a decode.
  ///
  /// [pivot] and [nineSliceBorder] arrive as value objects purely for
  /// readability at the call site; each is unpacked into its own separate
  /// `DataPointer<double>` fields here, because a row cannot store a value
  /// object (see this class's doc). That unpacking happens once, where the
  /// field is written, so the value objects never touch a hot path.
  static Sprite of({
    TextureKey? texture,
    TextureFilter filter = TextureFilter.mipmap,
    SpriteFrame frame = SpriteFrame.full,
    int color = 0xFFFFFFFF,
    double width = 0,
    double height = 0,
    int zIndex = 0,
    bool visible = true,
    RelativeOffset2D pivot = RelativeOffset2D.center,
    NineSliceBorder nineSliceBorder = NineSliceBorder.none,
  }) => Sprite(
    texture: Field.optAsset<Texture>(texture),
    filter: Field.uint2(filter.index),
    frame: Field.packed(const SpriteFrames(), frame),
    color: Field.uint32(color),
    width: Field.float64(width),
    height: Field.float64(height),
    zIndex: Field.int32(zIndex),
    visible: Field.boolean(visible),
    pivotFractionX: Field.float64(pivot.fractionX),
    pivotFractionY: Field.float64(pivot.fractionY),
    pivotOffsetX: Field.float64(pivot.offsetX),
    pivotOffsetY: Field.float64(pivot.offsetY),
    borderLeft: Field.float32(nineSliceBorder.left),
    borderTop: Field.float32(nineSliceBorder.top),
    borderRight: Field.float32(nineSliceBorder.right),
    borderBottom: Field.float32(nineSliceBorder.bottom),
    insetLeft: Field.float64(nineSliceBorder.insetLeft),
    insetTop: Field.float64(nineSliceBorder.insetTop),
    insetRight: Field.float64(nineSliceBorder.insetRight),
    insetBottom: Field.float64(nineSliceBorder.insetBottom),
  );

  /// This sprite's twenty columns, in the order [of] built them - which is
  /// the order they take in the row.
  ///
  /// The list is walked once, while the scene lays the archetype out, and
  /// never on a frame path.
  @override
  Iterable<ScannableField> get composedDeclarations => <ScannableField>[
    texture,
    filter,
    frame,
    color,
    width,
    height,
    zIndex,
    visible,
    pivotFractionX,
    pivotFractionY,
    pivotOffsetX,
    pivotOffsetY,
    borderLeft,
    borderTop,
    borderRight,
    borderBottom,
    insetLeft,
    insetTop,
    insetRight,
    insetBottom,
  ];

  /// Writes all four pivot fields at once. The declared default (from [of])
  /// already covers the common case; this is for changing a pivot at runtime
  /// without poking four fields by hand.
  void setPivot(Entity entity, RelativeOffset2D pivot) {
    pivotFractionX[entity] = pivot.fractionX;
    pivotFractionY[entity] = pivot.fractionY;
    pivotOffsetX[entity] = pivot.offsetX;
    pivotOffsetY[entity] = pivot.offsetY;
  }

  /// Writes the sampled region. The value object never reaches a row - see
  /// [SpriteFrame].
  void setFrame(Entity entity, SpriteFrame value) => frame[entity] = value;

  /// Writes the whole nine-slice at once - both the four source cuts and the
  /// four destination insets. See [setPivot].
  ///
  /// Both halves, and from the same fields [Sprite.of] reads, because the
  /// insets are what decide whether the sprite is sliced at all (see
  /// [NineSliceBorder.isEmpty]). Writing only the cuts could neither turn
  /// slicing on for a sprite declared plain nor turn it off for one
  /// declared sliced; [NineSliceBorder.none] does the latter.
  ///
  /// Whatever conversion the two halves need from the numbers an artist
  /// actually has happens once, in [NineSliceBorder.pixels] and
  /// [NineSliceBorder.all], so declaring a border and setting one at run time
  /// cannot disagree about it.
  void setNineSliceBorder(Entity entity, NineSliceBorder border) {
    borderLeft[entity] = border.left;
    borderTop[entity] = border.top;
    borderRight[entity] = border.right;
    borderBottom[entity] = border.bottom;
    insetLeft[entity] = border.insetLeft;
    insetTop[entity] = border.insetTop;
    insetRight[entity] = border.insetRight;
    insetBottom[entity] = border.insetBottom;
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
/// allocation on the frame path (the no-allocation rule).
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

/// Where one archetype's numbers land in the view being drawn: the five terms
/// the fill pass folds into every quad, and the two that say what a
/// [Sprite]'s width and height mean.
///
/// A world entity and a screen-space one differ in exactly these seven
/// doubles and in nothing else. So the space is resolved **once per archetype
/// per view**, and the per-sprite arithmetic never asks which of the two it
/// is standing on - the same answer [_TransformSource] gives for "which
/// component holds the transform", for the same measured reason: at 20,000
/// sprites it is the question that costs, not the answer.
///
/// The world case is [CameraProjection.worldToViewX]/[CameraProjection.worldToViewY]
/// term for term, with the camera's own numbers hoisted out of the loop. It
/// is spelled as `(x - originX) * zoom + anchorX` and not as a fused
/// multiply-add so that it stays that mapping exactly, down to the bit, and
/// the renderer and `MousePickingSystem` cannot drift apart.
///
/// The screen case sets `originX`, `originY` to zero and `zoom` to one, which
/// reduces the identical expression to `x + anchorX` with no rounding of its
/// own - so both spaces go through one line of arithmetic.
///
/// Long-lived instances on [GameRenderer2D], refilled in place. One per
/// archetype per tick would be an allocation on the frame path.
final class _ViewPlacement {
  /// The camera's world position, or zero for a screen-space archetype.
  double originX = 0;
  double originY = 0;

  /// Where this archetype's own origin sits in the view: the middle of it for
  /// a world archetype, and the [ScreenAnchor]'s point for a screen one.
  double anchorX = 0;
  double anchorY = 0;

  /// The camera's zoom, or `1` for a screen-space archetype - which is the
  /// whole of "screen space ignores zoom".
  double zoom = 1;

  /// What a [Sprite.width]/[Sprite.height] is multiplied by: `1` for a length
  /// already in view units, and the view's own width or height for a fraction
  /// of it.
  double widthScale = 1;
  double heightScale = 1;

  void world(CameraProjection projection) {
    originX = projection.originX;
    originY = projection.originY;
    anchorX = projection.halfViewWidth;
    anchorY = projection.halfViewHeight;
    zoom = projection.zoom;
    widthScale = 1;
    heightScale = 1;
  }

  void screen(CameraProjection projection, ScreenTransform2D screen) {
    // The size of *this* view, off the projection that resolved it a moment
    // ago - not off the game, which holds one number for every view at once.
    // Two views showing one scene at two sizes is the reason none of this is
    // in the row.
    final viewWidth = projection.halfViewWidth * 2;
    final viewHeight = projection.halfViewHeight * 2;
    final anchor = screen.screenAnchor;
    originX = 0;
    originY = 0;
    zoom = 1;
    anchorX = anchor.fractionX * viewWidth;
    anchorY = anchor.fractionY * viewHeight;
    widthScale = screen.screenWidthAxis == ScreenAxis.fraction ? viewWidth : 1;
    heightScale = screen.screenHeightAxis == ScreenAxis.fraction
        ? viewHeight
        : 1;
  }
}

/// Marks an entity as something the renderer should draw, and carries the
/// [Sprite]s it draws as.
///
/// An entity mixing this in **must** also mix in `Transform2D` - there is no
/// meaningful place to draw something that has no position, and requiring it
/// in the query, instead of defaulting to the origin, turns "I forgot the
/// transform" into an entity that visibly never appears and not a pile of
/// quads stacked at 0,0.
///
/// `WorldTransform2D` is **optional**, and that is the point of it being a
/// separate mixin. A renderable that has it is drawn from its composed world
/// transform; one that does not is drawn from its local `Transform2D`
/// directly, which for an entity that is never parented is the same answer -
/// exactly as `WorldTransform2D`'s own doc promises. Requiring it here would
/// make that promise false: every drawable would have to carry the mixin, so
/// `WorldTransformSystem` would copy local to world for every sprite in the
/// game every fixed step, and this pass would read the copy. At 20k flat
/// sprites that copy is a third of the fixed step, spent to arrive back at
/// the numbers it started from.
///
/// A `MultiComponent`, because one entity commonly draws as several
/// rectangles (a body and a hat, a panel and its icon) that move together but
/// have their own size, colour, depth and visibility. Those per-sprite fields
/// therefore live on [Sprite], one instance per [Sprite.of] field, not on
/// this mixin - the identical arrangement `Collider2D`/`ColliderBody` uses
/// for compound colliders, and for the identical reason
/// (`with Renderable2D, Renderable2D` is not a thing Dart allows).
///
/// ```dart
/// class Player extends EntityStruct with Transform2D, Renderable2D {
///   final body = Sprite.of(width: 64, height: 64);
///   final hat = Sprite.of(width: 28, height: 12, zIndex: 1);
/// }
/// ```
mixin Renderable2D on MultiComponent {
  /// Every [Sprite] this prefab declared, in the order it declared them.
  ///
  /// This is what [GameRenderer2D] iterates - the generic path for anything
  /// that needs to walk every sprite an entity has without knowing this
  /// prefab's own field names, exactly as `Collider2D.bodies` is for
  /// colliders.
  ///
  /// Filled in [describeStruct] from the prefab's own declarations, so a
  /// sprite reaches this list by being held by a field and by nothing else -
  /// there is no register call to forget. The order is the collector's, which
  /// is the order the fields are written, which is the order the columns take
  /// in the row.
  final List<Sprite> sprites = [];

  // Registering the type here is not optional bookkeeping - it is what sets
  // this component's bit in the archetype signature, and therefore the only
  // reason `withAll(Renderable2D)` matches anything at all. Omitting it makes
  // the query match *nothing*: `ComponentTypeRegistry.bitFor` hands a type it
  // has not seen a fresh bit, so the required mask carries a bit no archetype
  // signature does and `signature & required == required` is false everywhere.
  // The renderer then draws nothing and reports no error, so the symptom is a
  // system that never runs, not a declaration that is missing.
  // `test/render_2d_test.dart` checks the signature bit directly, and does not
  // trust inspection.
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Renderable2D>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    // Read off the constructed prefab rather than handed in: a sprite is a
    // field initialiser's value now, so the only record of which sprites
    // this prefab has is the fields holding them. The same generated
    // collector the scene walked a moment ago to lay the columns out, so the
    // two cannot disagree about which sprites there are or in what order.
    //
    // Nothing takes `data` here. The columns were reserved during that walk,
    // where the field sits in the row; this pass only names them.
    sprites.addAll(collectDeclarations(this).whereType<Sprite>());
  }
}

/// The renderer's per-tick working set: which (entity, sprite) pairs are
/// going to be drawn, and in what order.
///
/// Lives across ticks and is only ever refilled - the arrays grow to the
/// high-water mark of the scene and stay there, so a steady-state tick
/// allocates nothing here at all. The growth policy is [VertexBatch2D]'s:
/// capacity doubles until it fits and the filled prefix is copied across,
/// which is the same amortised-growth arrangement that already keeps the
/// vertex buffers allocation-free (the no-allocation rule).
///
/// The parallel-arrays-plus-an-index-permutation shape is what lets the sort
/// move a single `int` per swap instead of an entity, a sprite reference and
/// a key. It is also why there is no `_Candidate` class: one object per drawn
/// sprite per tick is precisely the allocation this exists to avoid.
///
/// # Why the finished geometry lives here
///
/// [_corners] and [_colorAddress] hold each plain sprite's
/// *already-transformed* quad, computed by the fill pass and not by the write
/// pass. That split is the whole point of this class, and the numbers below
/// are why.
///
/// The fill pass visits rows in page order; the write pass visits the same rows
/// in z-sorted order, which for any scene that layers by distance is close to a
/// random permutation. On a phone, 20,000 rows of ~250 bytes is ~5 MB - past
/// the last-level cache - so the write pass spent its time stalled on memory. A
/// device ablation that skipped the sort entirely (`debugSkipZSort`) cut the
/// write pass from 8.96 ms to 5.18 ms, **42%**, with identical work and only
/// the order changed. The same ablation for the two trig calls moved it 0.07
/// ms, i.e. nothing: the arithmetic was executing inside the memory stalls for
/// free.
///
/// So the rows are read once, sequentially, by the pass that is already
/// walking them, and what the permutation shuffles is 40 dense bytes per
/// sprite instead of a 250-byte row scattered across pages - ~800 KB at
/// 20,000 sprites against ~5 MB, which is the difference between fitting in
/// that cache and not.
///
/// Note this *moves* cost instead of removing it: the fill pass
/// gets slower and the write pass much faster. `present` is the number that
/// went down; `walk` on its own will read higher than before.
final class _SpriteDrawQueue {
  _SpriteDrawQueue({int initialCapacity = 64})
    : _entities = List<Entity>.filled(initialCapacity, const Entity(0)),
      _owners = List<Object?>.filled(initialCapacity, null),
      _sources = List<_TransformSource?>.filled(initialCapacity, null),
      _zIndices = Int32List(initialCapacity),
      _records = Int32List(initialCapacity),
      _kinds = Uint8List(initialCapacity),
      _order = Int32List(initialCapacity),
      _merge = Int32List(initialCapacity),
      _corners = Float32List(initialCapacity * _cornerStride),
      _colorAddress = Int32List(initialCapacity * _colorStride),
      _frames = Int64List(initialCapacity);

  /// Floats per queued sprite in [_corners]: four `(x, y)` corners in winding
  /// order, already transformed into view space.
  static const int _cornerStride = 8;

  /// Ints per queued sprite in [_colorAddress]: packed ARGB, then the texture
  /// address, then the texture filter. Kept adjacent so the write pass reads
  /// all three in one access.
  static const int _colorStride = 3;

  List<Entity> _entities;

  /// What the queued candidate is drawn from: the [Sprite] for a quad or a
  /// nine-slice, the [Text2D] for a label. Which of the two it is follows
  /// from [_kinds], and nothing asks it any other way.
  ///
  /// One array and not one per kind, because a slot holds exactly one of
  /// them and a second parallel array would be eight bytes per queued sprite
  /// spent to avoid a cast the write pass performs at most once per
  /// candidate, on the paths that are already reading a row.
  List<Object?> _owners;

  /// Where the queued entity's transform is read from, carried from the fill
  /// pass and never re-derived in the write pass.
  ///
  /// It is a per-*archetype* answer, so the fill pass knows it once per group;
  /// the write pass walks in z order across every archetype at once and would
  /// otherwise have to ask per sprite - a registry lookup plus a subtype test
  /// against a type variable, for an answer the other pass already had. One
  /// reference per queued sprite, in an array reused like every other here.
  List<_TransformSource?> _sources;
  Int32List _zIndices;

  /// Draw records each queued candidate costs - 1 for a plain quad, one per
  /// live cell for a nine-slice, one per drawn glyph for a label.
  ///
  /// Kept per pair and not only in total because the budget is now spent
  /// after the sort: [trimToBudget] walks the sorted order from the front
  /// and has to know what each candidate costs at the position depth put it
  /// in, which is not the position the fill pass met it at. Before #175 the
  /// total was the only thing anyone asked for.
  Int32List _records;

  /// Which write path each queued candidate takes - [kindQuad], [kindSliced]
  /// or [kindText].
  ///
  /// Decided during the fill pass and *stored*, not re-derived in the write
  /// pass, because the fill pass is what spends the record budget against it.
  /// Two passes each deciding "is this sliced?" from the same rows would agree
  /// today - presentation runs after the tick commits, so nothing mutates
  /// underneath them - but the byte scratch is sized from the budget the first
  /// pass computed, so any future disagreement would be a buffer overrun and
  /// not a wrong picture.
  ///
  /// A kind and not the record count, which is what used to be here: the two
  /// stopped being the same question when the charge became the real cell
  /// count (#252). A sprite sliced on one axis can be down to a single live
  /// cell, which makes it one record *and* nine-sliced, and it still has to
  /// write through [GameRenderer2D._writeNineSlice] - that record samples a
  /// sub-rectangle of the frame, which the plain path knows nothing about.
  /// Branching on `records == 1` would have swapped its UVs for the whole
  /// frame's and drawn a stretched panel with no way to see why. The count
  /// lives in [_records] and answers a different question - what a candidate
  /// costs, not how it draws.
  Uint8List _kinds;

  /// One record, four corners the fill pass already transformed. Almost
  /// everything, almost always.
  static const int kindQuad = 0;

  /// One record per live cell of a nine-slice, geometry derived in the write
  /// pass off the row - see [GameRenderer2D._writeNineSlice].
  static const int kindSliced = 1;

  /// One record per glyph the label draws, expanded in the write pass off the
  /// run the fill pass parked in [_corners] - see [writeTextAt].
  static const int kindText = 2;

  /// Slot indices in draw order. Sorted in place by [sortByZ]; before that it
  /// is the identity permutation, i.e. encounter order.
  Int32List _order;

  /// The sort's second buffer. Swapped with [_order] instead of copied back -
  /// both are owned scratch of identical length, so the swap is two field
  /// writes. Used by both sorts.
  Int32List _merge;

  /// Four already-transformed `(x, y)` corners per queued sprite, in winding
  /// order - see the class doc for why the geometry is computed by the fill
  /// pass and parked here.
  ///
  /// `Float32List`, not `Float64List`, and that is exact, not lossy: the wire
  /// format's corners are `float32`, so the value is narrowed once whatever
  /// happens. Narrowing here puts that single rounding step in a different
  /// place and produces the identical bits, because reading a `float32` back
  /// out widens exactly. It also halves what the permutation has to drag
  /// through the cache, which is the entire point.
  ///
  /// **Not written for a nine-slice.** A sliced sprite has a record per live
  /// cell with its own UVs and cannot be reduced to four corners, so its
  /// slots here are left holding whatever a previous tick put there. Nothing
  /// reads them: the write pass branches on [kindAt] first.
  ///
  /// **A label uses the same eight floats to mean something else** - an
  /// origin and three vectors, see [setTextRun]. Eight is what a run needs
  /// too, so a label pays the same 32 bytes a sprite does and no second
  /// layout exists to keep in step.
  Float32List _corners;

  /// Packed ARGB, then texture address, then filter, per queued candidate.
  /// Filled for a quad and for a label; see [_corners].
  Int32List _colorAddress;

  /// Packed [SpriteFrame] per queued sprite. Its own `Int64List`, and not
  /// two lanes of [_colorAddress], because a frame is 64 bits and splitting it
  /// across two `int32` slots would cost a shift-and-or per sprite in both the
  /// fill and the write pass to no purpose.
  Int64List _frames;

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
  /// and not from the int extremes, so a scene whose z values are all equal
  /// reports a range of 1, not the whole int64 line.
  int _zMin = 0;
  int _zMax = 0;

  /// A slot past every slot, so a boundary never set means "no candidates on
  /// that side of it".
  static const int _noLayer = 0x7FFFFFFF;

  /// Where the world layer starts, and where the front screen layer starts -
  /// slot numbers, and therefore fill order, which is why the fill pass has
  /// to queue the three layers in the order they draw.
  ///
  /// Slots and not a flag per candidate: the layers are queued in three
  /// contiguous runs, so two integers say the same thing an array of
  /// `_count` bytes would and cost nothing to keep in step. [sortByZ] uses
  /// them to lift the layers apart after it has sorted them by depth.
  int _worldFrom = 0;
  int _frontFrom = _noLayer;

  int _count = 0;

  /// Total draw records the queued pairs would write if every one of them
  /// were drawn - accumulated by [add]. [trimToBudget] is what decides how
  /// many of them actually are.
  int _recordTotal = 0;

  /// Draw-order index the write pass starts at: the first pair the budget
  /// admitted. Zero on a frame that fits, which is every frame a game should
  /// be having.
  int _first = 0;

  /// Records [trimToBudget] discarded off the back of the sorted order.
  ///
  /// Held as the discarded count rather than the admitted one so that both
  /// this and [_first] are already correct for a frame that fits - which is
  /// what lets [trimToBudget] return on a single comparison, writing nothing.
  int _trimmedRecords = 0;

  /// How many pairs are queued, drawn or not. Also the length of the sorted
  /// prefix. The drawn ones are `[firstAdmitted, length)`.
  int get length => _count;

  /// Draw-order index of the first pair that will be written. See [_first].
  int get firstAdmitted => _first;

  /// How many draw records the write pass will emit. A plain sprite
  /// contributes 1; a nine-sliced one contributes one per live cell, up to 9;
  /// a label contributes one per glyph it draws.
  ///
  /// This is the *admitted* total, so it is what the published batch holds
  /// and what `GameRenderer2D.lastRecordCount` reports.
  int get recordCount => _recordTotal - _trimmedRecords;

  /// How many draw records the budget turned away - the exact shortfall,
  /// since every candidate was queued before the budget was spent.
  int get trimmedRecordCount => _trimmedRecords;

  void reset() {
    _count = 0;
    _recordTotal = 0;
    _first = 0;
    _trimmedRecords = 0;
    // Everything queued is world-layer until the fill pass says otherwise,
    // which is the whole of a game that has no screen-space entity in it.
    _worldFrom = 0;
    _frontFrom = _noLayer;
  }

  /// Closes the behind-the-world screen layer: everything queued from here on
  /// is a world sprite or a label.
  void beginWorldLayer() => _worldFrom = _count;

  /// Closes the world layer: everything queued from here on is drawn in front
  /// of every world sprite and every label.
  void beginFrontLayer() => _frontFrom = _count;

  /// Whether the [i]th candidate *in draw order* was placed against the view
  /// instead of against the camera.
  ///
  /// Two comparisons, and the only caller is the nine-slice write path, which
  /// has to rebuild a placement the fill pass resolved per archetype and then
  /// let go of. The plain-quad path never asks: its geometry was finished
  /// while the fill pass still knew the answer.
  bool isScreenAt(int i) {
    final slot = _order[i];
    return slot < _worldFrom || slot >= _frontFrom;
  }

  /// Spends a budget of [limit] records over the pairs queued so far, in the
  /// draw order [sortByZ] left them in, and marks everything it cannot afford
  /// as not drawn.
  ///
  /// **Walked from the front of the scene backwards.** The sorted order runs
  /// back to front, so this starts at the last pair - the nearest thing to
  /// the camera - and admits candidates until one does not fit. What a frame
  /// loses is therefore the furthest layer, which is a property of the scene,
  /// instead of whichever archetype happened to be registered last (#175).
  ///
  /// **It stops at the first candidate that does not fit** rather than
  /// skipping it for a cheaper one further back. Survivors are a contiguous
  /// slab: everything from some depth forward is drawn. Admitting a smaller
  /// sprite from behind a refused one would punch a hole in the depth order -
  /// a background tile drawn while a mid-layer one is missing - which is a
  /// worse frame, not a better one.
  ///
  /// On a frame that fits this is one comparison and no writes at all: [_first]
  /// and [_trimmedRecords] were already set to their fitting values by
  /// [reset].
  void trimToBudget(int limit) {
    if (_recordTotal <= limit) return;
    final records = _records;
    final order = _order;
    var admitted = 0;
    var i = _count;
    while (i > 0) {
      final cost = records[order[i - 1]];
      // All-or-nothing, as it was when the fill pass spent the budget: a
      // nine-sliced sprite is admitted only if every one of its records fits,
      // because admitting it partially would write past the scratch.
      if (admitted + cost > limit) break;
      admitted += cost;
      i--;
    }
    _first = i;
    _trimmedRecords = _recordTotal - admitted;
  }

  /// Queues one candidate - an (entity, [Sprite]) pair or an (entity,
  /// [Text2D]) label - to be drawn at depth [zIndex], costing [records] draw
  /// records, and returns its **slot**: the index the parallel arrays store
  /// it at, which is also its encounter position.
  ///
  /// [kind] says which write path it takes, and is not inferred from
  /// [records] - see [_kinds].
  ///
  /// The slot is what [setQuad] and [setTextRun] take. It is not the draw
  /// position: nothing knows that until [sortByZ] has run, and the fill pass
  /// has to be able to write a sprite's geometry the moment it computes it.
  int add(
    Entity entity,
    Object owner,
    _TransformSource source,
    int zIndex,
    int records, {
    required int kind,
  }) {
    _ensure(_count + 1);
    // Seeded from the first key, not the int extremes, so an empty range is
    // 1 and not the whole number line - see [_zMin].
    if (_count == 0) {
      _zMin = zIndex;
      _zMax = zIndex;
    } else if (zIndex < _zMin) {
      _zMin = zIndex;
    } else if (zIndex > _zMax) {
      _zMax = zIndex;
    }
    _entities[_count] = entity;
    _owners[_count] = owner;
    _sources[_count] = source;
    _zIndices[_count] = zIndex;
    _records[_count] = records;
    _kinds[_count] = kind;
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
    int frame,
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
    _frames[slot] = frame;
  }

  /// Writes the [i]th pair *in draw order* as one quad record, returning the
  /// next write offset. Only valid where [kindAt] is [kindQuad].
  ///
  /// This is the whole of the write pass for a plain sprite, and it touches no
  /// component row: one `_order` read, then eight contiguous floats and a few
  /// contiguous ints out of the dense arrays the fill pass packed. See the
  /// class doc for the measurement that made this the shape it is.
  ///
  /// The UVs come from the queued [SpriteFrame], unpacked lane by lane off the
  /// raw integer instead of through a `SpriteFrame` object - one per sprite
  /// per frame would be exactly the hot-path allocation the no-allocation rule
  /// forbids. A full frame yields `(0,0) (1,0) (1,1) (0,1)`.
  int writeQuadAt(ByteData view, int offset, int i) {
    final slot = _order[i];
    final c = slot * _cornerStride;
    final k = slot * _colorStride;
    final q = _corners;
    final f = _frames[slot];
    final u0 = SpriteFrame.unpackLane(f, SpriteFrame.laneU0);
    final v0 = SpriteFrame.unpackLane(f, SpriteFrame.laneV0);
    final u1 = SpriteFrame.unpackLane(f, SpriteFrame.laneU1);
    final v1 = SpriteFrame.unpackLane(f, SpriteFrame.laneV1);
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
      u0: u0,
      v0: v0,
      u1: u1,
      v1: v0,
      u2: u1,
      v2: v1,
      u3: u0,
      v3: v1,
    );
  }

  /// The entity of the [i]th candidate *in draw order*.
  Entity entityAt(int i) => _entities[_order[i]];

  /// The sprite of the [i]th candidate *in draw order*. Only valid where
  /// [kindAt] is not [kindText].
  Sprite spriteAt(int i) => _owners[_order[i]]! as Sprite;

  /// Where the [i]th candidate *in draw order* reads its transform from.
  _TransformSource sourceAt(int i) => _sources[_order[i]]!;

  /// Which write path the [i]th candidate *in draw order* takes. See
  /// [_kinds].
  int kindAt(int i) => _kinds[_order[i]];

  /// Stores one label's finished, view-space **run** against [slot] - where
  /// its first glyph's top-left corner landed, and the three vectors every
  /// glyph after that is placed by.
  ///
  /// The four numbers a glyph quad needs are all sums of these: glyph `g`'s
  /// top-left is `origin + g * advance`, and its other three corners add
  /// [cellWidthX]/[cellWidthY] and [cellHeightX]/[cellHeightY]. So the
  /// rotation, the scale, the zoom, the pivot and the projection are all
  /// spent once per label in the fill pass, while it is standing on the row,
  /// exactly as [setQuad] spends them once per sprite.
  ///
  /// Multiplying by `g` and not accumulating: an accumulated origin drifts by
  /// a rounding step per glyph, and these are `float32`.
  void setTextRun(
    int slot,
    double originX,
    double originY,
    double advanceX,
    double advanceY,
    double cellWidthX,
    double cellWidthY,
    double cellHeightX,
    double cellHeightY,
    int color,
    int textureAddress,
    int filter,
  ) {
    final c = slot * _cornerStride;
    final corners = _corners;
    corners[c] = originX;
    corners[c + 1] = originY;
    corners[c + 2] = advanceX;
    corners[c + 3] = advanceY;
    corners[c + 4] = cellWidthX;
    corners[c + 5] = cellWidthY;
    corners[c + 6] = cellHeightX;
    corners[c + 7] = cellHeightY;
    final k = slot * _colorStride;
    _colorAddress[k] = color;
    _colorAddress[k + 1] = textureAddress;
    _colorAddress[k + 2] = filter;
  }

  /// Expands the [i]th candidate *in draw order* into one quad per glyph it
  /// draws, returning the new write offset. Only valid where [kindAt] is
  /// [kindText].
  ///
  /// One candidate, N records, one z key for the group - the same shape
  /// [GameRenderer2D._writeNineSlice] has, and the reason a label is not
  /// declared as N sprites. Sixteen sprites on a row measures 2.5 KiB; the
  /// same sixteen glyphs here are 32 bytes of `uint16` on the row and sixteen
  /// records at write time.
  ///
  /// This is the one write path that still reads a row, and it has to: the
  /// characters are the row. What it does *not* re-read is any of the
  /// geometry - [setTextRun] left that finished.
  ///
  /// A code unit the font has no cell for is skipped and still advances, so a
  /// missing glyph leaves a gap where it would have been and does not shuffle
  /// the rest of the line left. The fill pass charges the budget by counting
  /// through the same [BitmapFont.cellOf], so what is skipped here was never
  /// charged there.
  int writeTextAt(ByteData view, int offset, int i) {
    final slot = _order[i];
    final entity = _entities[slot];
    final text = _owners[slot]! as Text2D;
    final font = text.textFontResolved!;
    final columns = font.columns;
    final cellU = font.cellU;
    final cellV = font.cellV;
    final atlasU = font.frame.u;
    final atlasV = font.frame.v;
    final c = slot * _cornerStride;
    final q = _corners;
    final originX = q[c];
    final originY = q[c + 1];
    final advanceX = q[c + 2];
    final advanceY = q[c + 3];
    final wx = q[c + 4];
    final wy = q[c + 5];
    final hx = q[c + 6];
    final hy = q[c + 7];
    final k = slot * _colorStride;
    final color = _colorAddress[k];
    final address = _colorAddress[k + 1];
    final filter = _colorAddress[k + 2];
    final units = text.textCodeUnits;
    final length = text.textLength[entity];
    for (var g = 0; g < length; g++) {
      final cell = font.cellOf(units.get(entity, g));
      if (cell < 0) continue;
      final x0 = originX + advanceX * g;
      final y0 = originY + advanceY * g;
      final u0 = atlasU + cellU * (cell % columns);
      final v0 = atlasV + cellV * (cell ~/ columns);
      final u1 = u0 + cellU;
      final v1 = v0 + cellV;
      offset = DrawSpriteData2D.writeQuad(
        view,
        offset,
        x0,
        y0, // (left,  top)
        x0 + wx,
        y0 + wy, // (right, top)
        x0 + wx + hx,
        y0 + wy + hy, // (right, bottom)
        x0 + hx,
        y0 + hy, // (left,  bottom)
        color,
        textureAddress: address,
        filter: filter,
        u0: u0,
        v0: v0,
        u1: u1,
        v1: v0,
        u2: u1,
        v2: v1,
        u3: u0,
        v3: v1,
      );
    }
    return offset;
  }

  /// The widest `zIndex` span a counting sort is allowed to bucket.
  ///
  /// The counting sort costs `O(n + range)` and the merge sort `O(n log n)`,
  /// so the crossover is roughly `range < n * (log2(n) - 1)` - at 20,000
  /// sprites, a range of about 270,000. This cap is far below that and is set
  /// by *memory* instead: 65,536 buckets is a 256 KiB `Int32List` held for the
  /// life of the run, which is already generous scratch for a renderer. Beyond
  /// it the merge sort is used, so a game that spreads `zIndex` across the
  /// whole `int32` range is never worse off.
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
  /// instead of on a declared mode means neither case has to be configured.
  ///
  /// # Both are stable, by construction and not by luck
  ///
  /// Equal-`zIndex` sprites must keep encounter order - archetype registration
  /// order, then page order, then row order, then declaration order within a
  /// prefab - because scenes depend on it. The merge takes from the *left* run
  /// on a tie (`<=`), and the left run is always the earlier-encountered one.
  /// The counting sort walks the input in encounter order and appends within
  /// each bucket, which is the same guarantee arrived at differently.
  ///
  /// # Why neither is `List.sort`
  ///
  /// Both reasons come straight from the no-allocation rule:
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
    // `_zMin`/`_zMax` are plain Dart ints, which are 64-bit, so this
    // subtraction cannot overflow even for two `int32` extremes, so the range
    // is computed here and not tracked incrementally as an int32.
    final range = _zMax - _zMin + 1;
    if (range <= _maxCountingRange) {
      _countingSortByZ(n, range);
    } else {
      _mergeSortByZ(n);
    }
    _splitLayers(n);
  }

  /// Pulls the three layers apart - behind the world, the world, in front of
  /// it - keeping each one in the depth order the sort just left it in.
  ///
  /// A stable partition and not a wider sort key. `zIndex` is a plain `int32`
  /// a game is free to use as a sparse key, and a HUD that had to out-rank
  /// every world sprite by z would need a value above whatever the scene
  /// happens to use: at `1 << 20` the counting sort's range test fails and
  /// the *entire* queue drops onto the merge sort, and at a "safe" 60,000 the
  /// bucket array grows to 60,001 ints and is never shrunk. Either way every
  /// world sprite pays for one HUD element. Three comparisons per candidate
  /// costs neither.
  ///
  /// A frame with only one layer in it - every frame of a game that declares
  /// no [ScreenTransform2D] - returns on two comparisons and writes nothing.
  void _splitLayers(int n) {
    final world = _worldFrom;
    final front = _frontFrom;
    if (world <= 0 && front >= n) return;
    final src = _order;
    final dst = _merge;
    var k = 0;
    for (var i = 0; i < n; i++) {
      final slot = src[i];
      if (slot < world) dst[k++] = slot;
    }
    for (var i = 0; i < n; i++) {
      final slot = src[i];
      if (slot >= world && slot < front) dst[k++] = slot;
    }
    for (var i = 0; i < n; i++) {
      final slot = src[i];
      if (slot >= front) dst[k++] = slot;
    }
    _merge = _order;
    _order = dst;
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
    // this stable - see [sortByZ]. Reading through `src` instead of assuming
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
    // order instead of copying it back.
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
    _owners = List<Object?>.filled(next, null)..setRange(0, _count, _owners);
    _sources = List<_TransformSource?>.filled(next, null)
      ..setRange(0, _count, _sources);
    _zIndices = Int32List(next)..setRange(0, _count, _zIndices);
    _records = Int32List(next)..setRange(0, _count, _records);
    _kinds = Uint8List(next)..setRange(0, _count, _kinds);
    _order = Int32List(next)..setRange(0, _count, _order);
    _corners = Float32List(next * _cornerStride)
      ..setRange(0, _count * _cornerStride, _corners);
    _colorAddress = Int32List(next * _colorStride)
      ..setRange(0, _count * _colorStride, _colorAddress);
    _frames = Int64List(next)..setRange(0, _count, _frames);
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
/// reads is final for that tick by construction, and not by a convention
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
/// per entity per tick is precisely the per-entity heap allocation the
/// no-allocation rule forbids, and a 2D affine is six numbers.
///
/// # Ordering
///
/// One draw record per visible, sized [Sprite] - not one per entity - and
/// draw order is `zIndex` ascending with a **stable** tie-break on encounter
/// order (archetype registration order, then page order, then row order, then
/// the order sprites were declared within a prefab). So a scene that never
/// sets `zIndex` draws in encounter order.
///
/// Labels sort into the same order on the same key, and are walked after
/// every sprite - so a label and a sprite at one `zIndex` puts the label in
/// front, which is the way round a name over a character wants.
///
/// The sort is a prefix merge sort over a reusable index permutation (see
/// [_SpriteDrawQueue.sortByZ]) - no per-tick allocation, no comparator
/// closure, and stability by construction, not by trusting a library sort's
/// unspecified behaviour.
///
/// # The budget
///
/// `maxSpritesPerTick` is spent **after** that sort and not during the fill,
/// so a frame that asks for more records than it can hold loses its furthest
/// layers and keeps everything in front of them. Survivors are a contiguous
/// depth slab. See [_SpriteDrawQueue.trimToBudget].
///
/// # Culling
///
/// A sprite the camera cannot see is dropped in the fill pass, before it is
/// queued, sorted, budgeted or written - so what a frame costs tracks the
/// size of the view, not the size of the world.
///
/// The test is a circle around the sprite's pivot against the viewport
/// rectangle (`CameraProjection.showsCircle`), and a circle is what it has to
/// be: the pivot is the point rotation turns about, so a radius measured
/// from it is the one bound that does not have to be recomputed per angle.
/// It over-covers: a sprite whose circle reaches the view while the sprite
/// itself does not quite is kept. That is the direction to be wrong in, since
/// a quad nobody sees costs a record and a sprite wrongly dropped is a hole in
/// the picture.
///
/// **A view with no size culls nothing.** A headless run and a view no
/// `GameView` is showing both report zero, and zero is not a small viewport -
/// see `CameraProjection.viewLeft`.
///
/// What is *not* here is the other half of #23: a dirty-flag skip that stops
/// re-transforming a static subtree at all (#25). This pass still visits every
/// renderable every tick and decides one at a time.
///
/// # Camera
///
/// A second query finds the active camera through [ActiveCameraResolver], and
/// its world position and `zoom` are folded into every quad's final
/// coordinates: `view = (world - cameraOrigin) * zoom + viewSize / 2`, with y
/// negated - the passes below place every pivot through
/// `CameraProjection.worldToViewX`/`worldToViewY`, where that mapping is
/// written out in full. With no camera in the scene the origin is
/// `(0, 0)` and the zoom is `1`, so the world origin lands in the middle of
/// the view and one world unit draws as one pixel.
///
/// # No sprite-level anchoring
///
/// A sprite is placed by its transform and its [Sprite.pivotFractionX] group,
/// and by nothing else. [Sprite] used to carry an `align*` group for
/// anchoring a sprite to its parent or to the viewport; it was stored, never
/// read, and deleted in #171. Anchoring to the view is designed in #132, and
/// it anchors through a `ScreenTransform2D` component and its own anchor
/// enum, per entity - not per sprite. That is the shape it has to have: a
/// screen-space sprite must ignore zoom, and zoom is folded into both the
/// scale and the projection on the world path this system walks, so a
/// world-space sprite carrying a viewport-fraction term could not opt out of
/// it without a branch on every row.
///
/// Anchoring to a *parent* stays unavailable for a different reason - it
/// needs the parent's bounds, and no system in `goo2d` resolves or publishes
/// extents at all.
///
/// # Textures
///
/// [Sprite.texture] is read and written into every record as the asset's
/// `GlobalObject` **address** - the integer both isolate copies agree on
/// because both ran the same `describeAssets` pass - alongside four UV pairs
/// covering the whole image. A null texture writes
/// [DrawSpriteData2D.noTexture] and the quad draws as its flat colour; there
/// is no placeholder image and no second code path.
///
/// This system never touches a `ui.Image`, and cannot: it runs on an isolate
/// whose `Texture` instances are addressed but never decoded. `DrawCanvas2D`
/// resolves the address and builds the shader on the main isolate, which is
/// the whole reason the addressing scheme exists.
///
/// # Nine-slice
///
/// A sprite whose destination insets are non-zero and which has a texture
/// emits nine records instead of one, each with its own sub-rectangle of the
/// UV square - see [_writeNineSlice], and [NineSliceBorder] for why the
/// source cut is a fraction and the destination corner is not. The nine cells
/// tile exactly the rectangle the single quad would have covered, which is
/// what lets culling and the record budget treat the sprite as one thing.
///
/// # Text
///
/// A [Text2D] label is one candidate that expands into one quad per glyph in
/// the write pass - the same arrangement nine-slice has, and for the same
/// reason: sixteen glyphs declared as sixteen sprites is a 2.5 KiB entity
/// row, and [_SpriteDrawQueue]'s own doc records what rows a tenth that size
/// did to the write pass on a device.
///
/// Layout is arithmetic over a [BitmapFont]'s grid and happens here, on the
/// game isolate, because this is the pass that walks the rows in z order and
/// main has none. Nothing here touches a font, a glyph or the rasteriser,
/// and it could not: `ui.ParagraphBuilder` throws on this isolate and
/// `ui.loadFontFromList` kills the process.
///
/// The budget counts a label by the glyphs it draws, and admission stays all
/// or nothing - so one long label that does not fit closes the budget for
/// everything behind it, which under the depth trim is the back of the
/// scene.
class GameRenderer2D extends GameSystem
    with Tickable, GameSystemLifecycleListener {
  /// Runs in the presentation phase, after the fixed tick commits, and after
  /// `WorldTransformSystem` within it.
  ///
  /// Both halves of that are load-bearing. Being a [Tickable] and not a
  /// `FixedTickable` is what lets it *read* `WorldTransform2D` instead of
  /// recomposing the hierarchy itself: a presentation pass sees the snapshot
  /// the tick just published, so the transforms the simulation derived are
  /// visible to it. Inside the tick they would not be - reads there see the
  /// *previous* tick's snapshot, and a pass in that phase ends up carrying its
  /// own copy of the composition math to work around it. That duplication is a
  /// symptom of being in the wrong phase, not of a missing accessor; see the
  /// no-specialised-variant rule, and Unity DOTS's
  /// `SimulationSystemGroup`/`PresentationSystemGroup` split, which resolves
  /// the identical problem the identical way.
  ///
  /// Latency is the same either way. Composing from published
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
  /// handed the handle instead of owning it.
  ///
  /// The cast is what a `GameSystem` pays for reaching a `Game`-side
  /// capability. It cannot be static: `GameSystem.game` is a plain `Game`, and
  /// a renderer declared into a game with no `Renderer2D` is a real
  /// configuration mistake worth naming, not a type error to design
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

  /// The debug shapes this run has drawn, and the calls that draw more.
  ///
  /// Built on first read and sized from `Renderer2D.maxDebugRecordsPerTick`,
  /// so a game that never draws a debug shape never allocates the store. In a
  /// release build [debugDrawEnabled] is false and this is the shared
  /// `DebugDraw2D.disabled` instance, which stores nothing.
  ///
  /// A system reaches it as `debugDraw`, without naming this system - see
  /// [DebugDrawAccessForSystems].
  DebugDraw2D get debugDraw {
    if (!debugDrawEnabled) return const DebugDraw2D.disabled();
    return _debugDraw ??= DebugDraw2D(
      capacity: _renderer.maxDebugRecordsPerTick,
    );
  }

  DebugDraw2D? _debugDraw;

  Uint8List? _debugScratch;
  ByteData? _debugScratchView;

  /// How many debug draw records the last [onTick] wrote, summed over views.
  ///
  /// Below `DebugDraw2D.segmentCount` by whatever the viewport culled.
  /// `DebugDraw2D.droppedSegments` is the other number: what never reached
  /// the store at all.
  int lastDebugRecordCount = 0;

  // There is no ring capacity to configure. A queue sized to a few batches
  // keeps the *oldest* frames, and an old frame is the one thing a renderer
  // never wants; overflow then drops the newest, which is the wrong end. A
  // `HandoffBuffer` holds one complete frame and the one being built, so
  // "behind" simply means the reader gets the newest instead of a backlog.
  // See `BufferDescriptor.hasHandoff`.

  // `Transform2D` is the entry condition: an entity is drawable when it has
  // somewhere to be drawn. There is no `Child` clause in either direction,
  // because a hierarchy child needs drawing exactly as much as a root does.
  //
  // `WorldTransform2D` is optional here because it is optional on the
  // entity. [_sourceOf] binds the five transform fields once per archetype -
  // to the world component where an archetype carries it, to the local one
  // where it does not - so both kinds of renderable go through this one
  // query and one write pass. See [Renderable2D] and [_TransformSource].
  //
  // A child's corners mean nothing until its ancestors are composed in, and
  // `WorldTransformSystem` finishes that during the fixed tick this pass
  // reads after. So a child carrying `WorldTransform2D` arrives with its
  // world position already resolved. A child *without* it is composed by
  // nothing - `WorldTransformSystem`'s own query requires the component - so
  // it draws at its offset from its parent, treated as a world position.
  // Parent a renderable and it wants the mixin.
  //
  // `withNone(ScreenTransform2D)` is what splits the two spaces, and it is a
  // per-archetype answer the storage layer gives for free - not a test inside
  // the loop. No archetype that predates screen space carries the bit, so
  // this clause changes nothing about what an existing game draws.
  @internal
  final renderables = Query.where()
      .withAll(Renderable2D, Transform2D)
      .withNone(ScreenTransform2D)
      .withOptional(WorldTransform2D)
      .build();

  // The other half of that split. `ScreenTransform2D` and `WorldTransform2D`
  // are mutually exclusive (see `ScreenTransform2D`), so `_sourceOf` binds a
  // screen archetype's five pointers to its local `Transform2D` without being
  // told to: there is no composed transform on the row to bind to instead.
  //
  // Walked twice per view, once per `ScreenLayer`, each pass keeping the
  // groups in its own layer. A game has a handful of screen archetypes and
  // the skipped ones cost a getter and a comparison, against a second query
  // object and a second set of boundaries to keep in step.
  @internal
  final screenRenderables = Query.where()
      .withAll(Renderable2D, Transform2D, ScreenTransform2D)
      .build();

  // Labels. The same three clauses for the same three reasons - a label needs
  // somewhere to be drawn, and it is composed by `WorldTransformSystem` where
  // the archetype carries the mixin and drawn from its local transform where
  // it does not.
  //
  // Separate from `renderables` because `Text2D` is a plain `Component` an
  // entity carries with or without `Renderable2D`: a sign is a panel sprite
  // and a label, a damage number is a label and nothing else, and neither one
  // can be expressed as a clause on the other query.
  @internal
  final labels = Query.where()
      .withAll(Text2D, Transform2D)
      .withOptional(WorldTransform2D)
      .build();

  // The camera is queried, not configured on this system: "where the view
  // is" is a property of an entity in the scene that the simulation can move
  // like any other, not a field a presentation system owns. Requiring
  // `WorldTransform2D` on it as well means a camera parented to the player
  // works with no special case here.
  @internal
  final cameras = Query.all(Camera, WorldTransform2D);

  /// One projection for the lifetime of the system - re-resolved each tick,
  /// never rebuilt, because building one per tick would be an allocation on
  /// the hot path for no reason. Shared logic, not a local
  /// reimplementation, so "where is the camera, and where does that put a
  /// world point on screen" means exactly the same thing here as it does to
  /// `MousePickingSystem`.
  final CameraProjection _projection = CameraProjection();

  /// The space the fill pass is currently reading, refilled once per
  /// archetype. See [_ViewPlacement].
  final _ViewPlacement _placement = _ViewPlacement();

  /// The same thing for the nine-slice write path, which runs after the fill
  /// pass has finished with [_placement] and rebuilds a placement per sliced
  /// sprite. Its own instance so that neither pass has to know the other left
  /// the shared one in a usable state.
  final _ViewPlacement _writePlacement = _ViewPlacement();

  final _SpriteDrawQueue _queue = _SpriteDrawQueue();

  Uint8List? _scratch;
  ByteData? _scratchView;

  /// How many *sprites* the last [onTick] drew - sprites that reached the
  /// batch, so a candidate the depth trim discarded is not among them.
  /// Diagnostics and tests.
  ///
  /// Not the same as [lastRecordCount] once nine-slicing or text is in play:
  /// one sliced sprite is one sprite and up to nine records, and a label is
  /// one and as many records as it has glyphs. This is the count of things
  /// the scene asked to draw; that one is the count of quads the buffer
  /// actually holds, and it is the buffer's number that has to stay under the
  /// budget.
  int lastSpriteCount = 0;

  /// How many draw records the last [onTick] wrote - quads, not sprites.
  ///
  /// This is what `maxSpritesPerTick` bounds and what `spriteBatchBytes`
  /// is sized from, so it is the number to watch when a scene starts
  /// dropping frames.
  ///
  /// It is the records in the published batch, exactly: a nine-sliced sprite
  /// is counted by the cells it actually draws and not by the nine it might
  /// have. Until #252 this was the *charge*, which for anything sliced on one
  /// axis was up to nine times what the batch held.
  int lastRecordCount = 0;

  /// How many draw records the last [onTick] asked for and could not fit -
  /// the shortfall against `maxSpritesPerTick`, counted in records.
  ///
  /// Zero on a frame that fit. Anything else means sprites are missing from
  /// the picture, and on screen that looks like the renderer got slower and
  /// not like anything was dropped. Raising `maxSpritesPerTick` by at
  /// least this much is the direct fix; drawing less is the other one.
  ///
  /// This is the *exact* shortfall and not a lower bound. Every visible
  /// candidate is queued before the budget is spent, so the total the scene
  /// asked for is known outright and this is that total less what was drawn:
  /// `lastRecordCount + lastRecordsOverBudget` is what the scene asked for.
  /// A reading of "at least 9" on a scene four thousand records over points
  /// at the wrong fix.
  ///
  /// **What it drops is the back of the scene.** The budget is spent after
  /// the sort, walking outwards from the camera, so a frame that cannot fit
  /// loses its furthest layers and keeps everything in front of them
  /// (#175). Until that landed it lost whichever archetype was registered
  /// last, which is not a property of the scene.
  ///
  /// Exact in the other direction too, since #252: what a refused sprite adds
  /// here is what it would have drawn. A frame of three-sliced panels used to
  /// report a shortfall against a budget that had room for all of them, so
  /// following the advice above raised a knob that was never the problem and
  /// the panels kept vanishing.
  ///
  /// Not the same failure as [lastWriteDropped] and it does not imply it. That
  /// one means main had not collected the previous frame yet and no budget
  /// would have helped; this one means the scene outgrew its buffer.
  int lastRecordsOverBudget = 0;

  /// True if the last [onTick] could not fit its batch in the ring.
  ///
  /// About the *handoff*, never about the budget - a batch that was built and
  /// had nowhere to go. [lastRecordsOverBudget] is the budget one.
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
  /// on, time this system's `onTick` from outside - `example`'s HUD and
  /// `tool/render_write_bench.dart` both do - and the difference is what the
  /// permutation costs in cache misses.
  ///
  /// One bool read per view per frame, so leaving it here costs a shipped
  /// build nothing measurable. The matching trig ablation needs
  /// no flag at all: writing zero into every entity's rotation makes the
  /// unrotated fast path in the write loop skip both `math.cos`/`math.sin`
  /// calls, which is the same experiment with no diagnostic code in the hot
  /// loop.
  bool debugSkipZSort = false;

  // There is no `describeBuffers` here, and there cannot be: a `GameSystem` is
  // declared and run on the game isolate, while shared memory is allocated on
  // main before the spawn. `Renderer2D.describeBuffers` declares one handoff
  // per camera view instead - on the same object that drains them into a
  // `GameView`, which is where the plan's own sorting rule puts a declaration:
  // with whoever holds the handle.

  // Scratch for one nine-sliced sprite's grid lines: four in each axis, reused
  // across sprites and ticks. Fields, not locals, so no array is
  // allocated per sprite (the no-allocation rule) - `onTick` may hit this once
  // per sprite per frame.
  //
  // `_lx`/`_ly` are *transformed-space* offsets from the pivot (already
  // scaled); `_u`/`_v` are the matching cuts in 0..1 texture space.
  //
  // `_lx`/`_ly` are written by both passes - the fill pass lays the grid to
  // count what the sprite costs, the write pass lays it again to emit off it
  // (see [_nineSliceGrid]). Neither reads what the other left: each fills all
  // four lanes before looking at any of them.
  final Float64List _lx = Float64List(4);
  final Float64List _ly = Float64List(4);
  final Float64List _u = Float64List(4);
  final Float64List _v = Float64List(4);

  /// Lays this sprite's nine-slice grid into [_lx] and [_ly] and returns how
  /// many of the nine cells are not collapsed - which is exactly how many
  /// records [_writeNineSlice] will emit for it.
  ///
  /// Both passes call this, and that is the point: the fill pass charges the
  /// budget with the number this returns and the write pass emits off the
  /// grid this left behind, so the charge cannot drift from the cost. It used
  /// to be a hardcoded `9`, and a sprite sliced on one axis only has a
  /// collapsed row or column by construction - so a three-sliced capsule
  /// button was charged nine records to write three, and a screen of them hit
  /// the budget three times sooner than it had any reason to (#252).
  ///
  /// Counted by comparing the grid lines the writer compares, and not from
  /// the insets directly, because the writer's test is `x1 == x0` on the
  /// *scaled, pivot-shifted* line positions. Three things fall out of that
  /// which an inset-only count gets wrong:
  ///
  ///  * A **zero scale** collapses every line onto the same point, so the
  ///    answer is 0 records and not 9. The fill pass has to skip such a
  ///    candidate outright rather than let the budget test filter it - see
  ///    its call site.
  ///  * A **negative inset** is a live cell, not a dead one. Nothing
  ///    downstream expects one, but `left != 0` is what the writer asks and
  ///    `left > 0` is not the same question.
  ///  * The middle cell survives on `width - right != left` **as floats**,
  ///    which is not `left + right < width` once the fit above has divided
  ///    and multiplied the insets back.
  int _nineSliceGrid(
    Entity entity,
    Sprite sprite,
    double width,
    double height,
    double pivotX,
    double pivotY,
    double scaleX,
    double scaleY,
  ) {
    // Destination corners, in the sprite's own units. Absolute, so they are
    // unchanged by how large the sprite is drawn - see [NineSliceBorder].
    var left = sprite.insetLeft[entity];
    var right = sprite.insetRight[entity];
    var top = sprite.insetTop[entity];
    var bottom = sprite.insetBottom[entity];

    // Destination-side fit, per axis and independently - see
    // [_writeNineSlice]'s doc.
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

    var cols = 0;
    if (lx[1] != lx[0]) cols++;
    if (lx[2] != lx[1]) cols++;
    if (lx[3] != lx[2]) cols++;
    if (cols == 0) return 0;
    var rows = 0;
    if (ly[1] != ly[0]) rows++;
    if (ly[2] != ly[1]) rows++;
    if (ly[3] != ly[2]) rows++;
    return cols * rows;
  }

  /// Expands one sprite into the quads of a nine-slice - up to nine of them,
  /// and as few as one - returning the new write offset.
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
  /// to zero width; the same independently for the vertical axis. Proportional,
  /// and not clamped-in-order, because clamping would let whichever inset
  /// was written first eat the whole axis and shrink the other to nothing,
  /// which reads as an asymmetric frame and not as a small one. It is also
  /// what CSS `border-image` does, so the behaviour is not novel.
  ///
  /// Nothing ever inverts: every cell's extent is clamped at zero, and a
  /// zero-area cell is skipped instead of emitted, because a degenerate quad
  /// costs a record and six vertices to rasterise nothing. **The UV split is
  /// not scaled with it** - the source image is sliced where it
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
    _nineSliceGrid(
      entity,
      sprite,
      width,
      height,
      pivotX,
      pivotY,
      scaleX,
      scaleY,
    );
    final lx = _lx;
    final ly = _ly;

    // The matching cuts in texture space. **No pixel dimension anywhere**, and
    // therefore no decoded image and no `TextureInfo`: the cuts are fractions,
    // so this arithmetic is available on the isolate that cannot decode, which
    // is the isolate that runs. Slicing off a *declared* source size instead
    // would put a number here that a repack can make wrong, and getting it
    // wrong mis-slices every panel.
    //
    // Note these use the border's own fractions, not the fitted destination
    // insets above: squeezing the destination must not re-slice the source.
    //
    // Cuts are placed **within the sprite's frame**, not across the whole
    // texture. A nine-sliced panel taken from an atlas has to slice inside its
    // own region; slicing the sheet would put three of its nine quads on a
    // neighbour's pixels. Collapses to the plain `0..1` case exactly when the
    // frame is full.
    final f = sprite.frame.packedAt(entity);
    final fu0 = SpriteFrame.unpackLane(f, SpriteFrame.laneU0);
    final fv0 = SpriteFrame.unpackLane(f, SpriteFrame.laneV0);
    final fu1 = SpriteFrame.unpackLane(f, SpriteFrame.laneU1);
    final fv1 = SpriteFrame.unpackLane(f, SpriteFrame.laneV1);
    final fw = fu1 - fu0;
    final fh = fv1 - fv0;
    final u = _u;
    final v = _v;
    u[0] = fu0;
    u[1] = fu0 + fw * sprite.borderLeft[entity];
    u[2] = fu1 - fw * sprite.borderRight[entity];
    u[3] = fu1;
    v[0] = fv0;
    v[1] = fv0 + fh * sprite.borderTop[entity];
    v[2] = fv1 - fh * sprite.borderBottom[entity];
    v[3] = fv1;

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
    // The *destination* insets decide this: they are what create nine
    // rectangles instead of one. A source cut with no corner to put it in
    // produces nothing - see [NineSliceBorder.isEmpty].
    if (sprite.insetLeft[entity] == 0 &&
        sprite.insetTop[entity] == 0 &&
        sprite.insetRight[entity] == 0 &&
        sprite.insetBottom[entity] == 0) {
      return false;
    }
    // A texture is still required - slicing subdivides image space, so with no
    // image there is nothing to subdivide. But its *size* is not: the cuts are
    // fractions now, so this no longer waits on a decode, and a nine-sliced
    // sprite slices correctly on the very first frame instead of falling back
    // to a single quad until its `TextureInfo` arrived.
    return sprite.texture[entity] != null;
  }

  @override
  void onTick(Duration delta) {
    // One pass per declared view. Each writes its own buffer, and each draws
    // the scene *its* camera is in - which is what replaced the deleted
    // global front scene. Two views can be looking at different scenes, or at
    // the same scene from different places, in the same tick.
    //
    // Totals across views, so a one-view game (the overwhelmingly common
    // case) reports its own numbers unchanged.
    var sprites = 0;
    var records = 0;
    var overBudget = 0;
    var dropped = false;
    var debugRecords = 0;
    final views = game.cameraViews;
    for (var i = 0; i < views.length; i++) {
      _renderView(views[i], framesFor(views[i]));
      sprites += lastSpriteCount;
      records += lastRecordCount;
      // Summed, not maxed, because each view spends its own budget
      // against its own buffer: two views each 100 records short need 200 more
      // records between them, not 100.
      overBudget += lastRecordsOverBudget;
      dropped = dropped || lastWriteDropped;
      // A `const false` in release, so this call and everything it reaches
      // are gone from the shipped binary along with the buffer it writes.
      if (debugDrawEnabled) {
        debugRecords += _renderDebugView(
          views[i],
          _renderer.debugFramesFor(views[i]),
        );
      }
    }
    if (debugDrawEnabled) {
      // After the last view, and not inside the loop: every view projects the
      // same world-space segments, so the store is what they all read and only
      // the last one is finished with it.
      _debugDraw?.markConsumed();
      lastDebugRecordCount = debugRecords;
    }
    lastSpriteCount = sprites;
    lastRecordCount = records;
    lastRecordsOverBudget = overBudget;
    lastWriteDropped = dropped;
  }

  /// Projects the debug shape store into [cameraView] and publishes it as
  /// that view's debug batch. Returns the records written.
  ///
  /// Its own pass over its own buffer, running whether or not [_renderView]
  /// found somewhere to put the scene. The two are independent by
  /// construction: debug shapes are what a system draws to explain what the
  /// scene is doing, and a frame that showed the shapes only when the scene
  /// batch also landed would go missing exactly when it is being read.
  ///
  /// It resolves the projection again instead of reusing what [_renderView]
  /// left, for the same reason - that pass may have returned before resolving
  /// anything.
  int _renderDebugView(CameraView cameraView, HandoffHandle handle) {
    final debugDraw = _debugDraw;
    // Nothing has ever drawn, so there is no store and nothing to publish.
    // The main-isolate half replays whatever it last ingested, which is also
    // nothing.
    if (debugDraw == null) return 0;
    final frames = handle.tryBuffer;
    if (frames == null) return 0;
    final target = frames.beginWrite();
    if (target == null) return 0;

    final bytes = _renderer.debugBatchBytes;
    final scratch = _debugScratch ??= Uint8List(bytes);
    final view = _debugScratchView ??= ByteData.sublistView(scratch);
    DrawData2D.writeBatchTick(view, state.tick);
    final written = debugDraw.writeBatch(
      view,
      DrawData2D.batchHeaderBytes,
      _projection..resolve(cameras, cameraView),
    );
    final offset =
        DrawData2D.batchHeaderBytes + written * DrawSpriteData2D.strideBytes;
    // Published even when it is empty. An empty batch is what replaces the
    // shapes of the frame before it, so a store that was cleared stops being
    // drawn instead of hanging on screen.
    target.asTypedList(bytes).setRange(0, offset, scratch);
    frames.publish(offset);
    return written;
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
    final local = group<Transform2D>();
    final cached = _sourceCache[local];
    if (cached != null) return cached;
    // `WorldTransform2D?`, because it is optional on a renderable - an
    // entity that is never parented has no composed transform to read and its
    // local one is already the answer. See [Renderable2D]'s doc.
    final world = group<WorldTransform2D?>();
    final source = world == null
        ? _TransformSource.local(local)
        : _TransformSource.world(world);
    _sourceCache[local] = source;
    return source;
  }

  /// Queues every visible, sized sprite [query] matches into [_queue].
  ///
  /// [layer] is null for the world query and a [ScreenLayer] for the
  /// screen-space one, where it also selects which groups this pass takes -
  /// the two screen layers are two passes over one query, because a layer
  /// belongs to an archetype and the draw order needs them contiguous.
  ///
  /// A method and not three copies of the loop: the two spaces differ in the
  /// seven doubles [_ViewPlacement] holds and in nothing else, so there is
  /// one body and it branches on the space exactly once per archetype.
  void _fillSprites(Query query, ScreenLayer? layer) {
    final projection = _projection;
    final queue = _queue;
    for (final group in query.groups()) {
      final renderable = group<Renderable2D>();
      final sprites = renderable.sprites;
      // Resolved once per archetype and carried through the queue, so the
      // write pass never asks - see `_SpriteDrawQueue._sources`.
      final source = _sourceOf(group);
      // And the *space*, resolved once per archetype for the same reason.
      // Everything below reads seven plain doubles and never asks whether it
      // is placing against the camera or against the view.
      final place = _placement;
      if (layer == null) {
        place.world(projection);
      } else {
        final screen = group<ScreenTransform2D>();
        if (screen.screenLayer != layer) continue;
        place.screen(projection, screen);
      }
      final originX = place.originX;
      final originY = place.originY;
      final anchorX = place.anchorX;
      final anchorY = place.anchorY;
      final zoom = place.zoom;
      final widthScale = place.widthScale;
      final heightScale = place.heightScale;
      for (final entity in group) {
        if (!projection.shows(entity)) continue;
        // An indexed loop, not `for (final sprite in sprites)`: this runs once
        // per entity per tick and a fresh iterator is a heap object (the
        // no-allocation and no-closure rules).
        for (var i = 0; i < sprites.length; i++) {
          final sprite = sprites[i];
          // Invisible sprites are dropped here, before they are ever a record -
          // not emitted transparent. A transparent quad still costs a record,
          // six vertices and a share of the batch limit, and would still
          // occlude nothing while pretending to be drawn.
          if (!sprite.visible[entity]) continue;
          // Read into locals, not compared in place: the geometry below
          // needs both, and this row is only cheap to touch while the walk is
          // still on it.
          // The two scales are `1` for a world archetype and for a screen
          // one sizing in view units, so this is `x * 1.0` - exact, and the
          // zero test below still means what it always meant. On a screen
          // archetype sizing by fraction they are the view's own width and
          // height, so `width: 1` fills it and `0.5` covers half of it.
          final width = sprite.width[entity] * widthScale;
          final height = sprite.height[entity] * heightScale;
          if (width == 0 || height == 0) continue;

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
          // `CameraProjection.worldToViewX`/`worldToViewY` with the camera's
          // own numbers hoisted out of the loop - the same expression, term
          // for term, so picking and drawing cannot drift apart. A screen
          // archetype supplies origin 0 and zoom 1, which reduces it to
          // `x + anchorX` and `anchorY - y` with no rounding of its own.
          final tx = (source.x[entity] - originX) * zoom + anchorX;
          final ty = (originY - source.y[entity]) * zoom + anchorY;

          // Viewport culling, and it comes *before* the budget: a record the
          // camera cannot see must not spend a place another sprite needs.
          // That is also what makes `lastRecordsOverBudget` mean "the scene
          // asked for more than it can draw" and not "the world is large".
          //
          // The bound is a circle centred on the pivot, because the pivot is
          // the point the transform origin sits on and therefore the point
          // rotation turns about. Rotation moves every corner along a circle
          // centred there, so the distance from the pivot to the furthest
          // corner does not depend on `rotation` at all, so this can be
          // decided before the angle is even read. A bound taken from
          // width and height alone is not merely a tighter answer, it is the
          // wrong shape: it is blind to the rotation, so it clips a long
          // sprite that is on screen only because it is turned.
          //
          // The four corners are `(lx0|lx1, ly0|ly1)`, so the furthest sits at
          // `sqrt(max(lx0^2, lx1^2) + max(ly0^2, ly1^2))` - and the squares
          // are the whole computation, because `showsCircle` compares against
          // the square and there is no root to take. The pivot is in those
          // four numbers already, so a sprite hung well off its own origin is
          // bounded by a circle large enough to reach it.
          //
          // Scale is in there too, sign included: a negative scale flips the
          // sprite about the pivot, and squaring is blind to which side of it
          // the corner ended up on. Zoom enters twice and consistently - it
          // shrinks the sprite through `scaleX`/`scaleY` and pulls the pivot
          // towards the middle of the view through the projection - which is
          // what brings a sprite that missed the view at zoom 1 back onto it
          // at zoom 0.5.
          //
          // Nine-slice needs nothing of its own. Its grid lines are
          // `(0 | left | width - right | width) - pivot` scaled, so the
          // outermost two *are* `lx0` and `lx1`, and the nine cells tile
          // exactly the rectangle one quad would have covered. The sprite is
          // therefore culled whole, never a cell at a time. (The interior
          // lines fall between the outer two for any non-negative inset,
          // which is the only kind a nine-slice has - a negative one is a
          // corner drawn outside the sprite's declared bounds, and nothing
          // downstream expects that either.)
          final sx0 = lx0 * lx0;
          final sx1 = lx1 * lx1;
          final sy0 = ly0 * ly0;
          final sy1 = ly1 * ly1;
          if (!projection.showsCircle(
            tx,
            ty,
            (sx0 > sx1 ? sx0 : sx1) + (sy0 > sy1 ? sy0 : sy1),
          )) {
            continue;
          }

          // The charge is what the write pass will actually emit, counted off
          // the same grid it will emit from - not a flat 9 for anything with
          // an inset on it. A three-sliced capsule button has a collapsed row
          // by construction and costs 3, and charging it 9 shut the budget
          // three times sooner than the scene needed (#252).
          final int records;
          final int kind;
          if (_isNineSliced(entity, sprite)) {
            kind = _SpriteDrawQueue.kindSliced;
            records = _nineSliceGrid(
              entity,
              sprite,
              width,
              height,
              pivotX,
              pivotY,
              scaleX,
              scaleY,
            );
            // Every cell collapsed - a scale of zero, or insets that fit
            // exactly - so there is nothing to draw. Skipped rather than
            // queued: a zero-record pair costs the budget nothing and can
            // never be the candidate the trim stops at, so queuing it would
            // add a sprite to `lastSpriteCount` that draws no part of itself.
            if (records == 0) continue;
          } else {
            kind = _SpriteDrawQueue.kindQuad;
            records = 1;
          }
          final slot = queue.add(
            entity,
            sprite,
            source,
            sprite.zIndex[entity],
            records,
            kind: kind,
          );
          // A nine-sliced sprite cannot be reduced to four corners, so it keeps
          // reading its row in the write pass. That is the rare path and it is
          // left alone; what follows is for the plain quad, which
          // is almost everything almost always.
          //
          // On the kind and not on `records != 1`: a sliced sprite down to
          // its last live cell writes one record and still has to take the
          // sliced path, because that record samples a sub-rectangle of the
          // frame.
          if (kind != _SpriteDrawQueue.kindQuad) continue;

          // The geometry, computed here and not in the write pass, and
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
            // Negated because the quad is composed in view space, which is
            // y-down, while world +y is up. Without it a positive rotation
            // turns clockwise on screen - the one thing the y-up flip does
            // not fix by itself. See `a positive rotation turns
            // counter-clockwise on screen`.
            sin = -math.sin(rotation);
          }
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
            sprite.frame.packedAt(entity),
          );
        }
      }
    }
  }

  /// Queues every visible label into [_queue], after every world sprite and
  /// before anything pinned to the view.
  ///
  /// World space only - `Text2D` refuses to sit on a `ScreenTransform2D`
  /// entity, so there is no second placement to resolve here.
  void _fillLabels() {
    final projection = _projection;
    final queue = _queue;
    final zoom = projection.zoom;
    // Labels, walked after the sprites and into the same queue, so a label
    // and a sprite at one `zIndex` put the label in front. That is the useful
    // way round - a name over a body, a damage number over an enemy - and the
    // encounter tie-break is what decides it, exactly as it decides two
    // sprites at one depth.
    //
    // A second query and not a clause on the first: `Renderable2D` and
    // `Text2D` are independent, an entity may carry either or both, and a
    // label has no `Sprite` to read a width, a frame or an inset from.
    for (final group in labels.groups()) {
      final text = group<Text2D>();
      // Per archetype, so a prefab that declared no font is skipped once for
      // every entity of it rather than once each. A font is the atlas and the
      // grid together and there is nothing to draw without one.
      final font = text.textFontResolved;
      if (font == null) continue;
      final address = font.texture.pack();
      final source = _sourceOf(group);
      final units = text.textCodeUnits;
      for (final entity in group) {
        if (!projection.shows(entity)) continue;
        if (!text.textVisible[entity]) continue;
        final length = text.textLength[entity];
        final cellWidth = text.textCellWidth[entity];
        final cellHeight = text.textCellHeight[entity];
        if (cellWidth == 0 || cellHeight == 0) continue;

        // The charge, counted through the same `cellOf` the write pass
        // expands with. A code unit the font has no cell for draws nothing
        // and is charged nothing, and the two passes cannot disagree about
        // which ones those are because there is one test and both call it.
        var records = 0;
        for (var g = 0; g < length; g++) {
          if (font.cellOf(units.get(entity, g)) >= 0) records++;
        }
        // Nothing to draw: an empty label, or one whose every character is
        // outside the font. Skipped here and not left to the budget test,
        // because `recordCount + 0 > limit` is false however closed the
        // budget already is - so a zero-record candidate would slip past a
        // trim that had stopped admitting anything and land in
        // `lastSpriteCount` drawing no part of itself (#252, for collapsed
        // slices).
        //
        // The one guard, and there is deliberately no `length == 0` shortcut
        // above it. A second test that catches a subset of this one is a
        // second thing a change can leave behind: with both present, deleting
        // either leaves every test green and the bug hides behind the
        // survivor.
        if (records == 0) continue;

        // Every character advances, in the font's cell or not, so a missing
        // glyph leaves its gap instead of pulling the rest of the line left.
        // The box is therefore as wide as the text, and the last glyph is a
        // cell and not an advance - trailing letter spacing would push the
        // pivot off the visible ink.
        final advance = cellWidth + text.textLetterSpacing[entity];
        final boxWidth = (length - 1) * advance + cellWidth;
        // The pivot is the alignment: resolved against a box as wide as the
        // text currently is, `0.5` keeps a label of any length centred on the
        // entity and `0` keeps its left edge there.
        final pivotX =
            text.textPivotFractionX[entity] * boxWidth +
            text.textPivotOffsetX[entity];
        final pivotY =
            text.textPivotFractionY[entity] * cellHeight +
            text.textPivotOffsetY[entity];
        final scaleX = source.scaleX[entity] * zoom;
        final scaleY = source.scaleY[entity] * zoom;
        final lx0 = -pivotX * scaleX;
        final lx1 = (boxWidth - pivotX) * scaleX;
        final ly0 = -pivotY * scaleY;
        final ly1 = (cellHeight - pivotY) * scaleY;
        final tx = projection.worldToViewX(source.x[entity]);
        final ty = projection.worldToViewY(source.y[entity]);
        // Culled whole, on the circle around the pivot the sprite path uses -
        // the glyphs tile exactly the box those four corners bound, so a
        // label is one thing to the culler as a nine-slice is.
        final sx0 = lx0 * lx0;
        final sx1 = lx1 * lx1;
        final sy0 = ly0 * ly0;
        final sy1 = ly1 * ly1;
        if (!projection.showsCircle(
          tx,
          ty,
          (sx0 > sx1 ? sx0 : sx1) + (sy0 > sy1 ? sy0 : sy1),
        )) {
          continue;
        }

        final rotation = source.rotation[entity];
        final double cos;
        final double sin;
        if (rotation == 0) {
          cos = 1.0;
          sin = 0.0;
        } else {
          cos = math.cos(rotation);
          // Negated for the same reason the sprite path negates it - the run
          // is composed in view space, which is y-down.
          sin = -math.sin(rotation);
        }
        // The label's own axes in view space. A local point `(x, y)` in the
        // box lands at `(tx + x*ex + y*fx, ty + x*ey + y*fy)`, which is the
        // sprite path's `lx*cos - ly*sin` with the scale folded in - so every
        // glyph is two multiplies and an add off numbers computed once here.
        final ex = scaleX * cos;
        final ey = scaleX * sin;
        final fx = -scaleY * sin;
        final fy = scaleY * cos;
        final slot = queue.add(
          entity,
          text,
          source,
          text.textZIndex[entity],
          records,
          kind: _SpriteDrawQueue.kindText,
        );
        queue.setTextRun(
          slot,
          tx - pivotX * ex - pivotY * fx,
          ty - pivotX * ey - pivotY * fy,
          advance * ex,
          advance * ey,
          cellWidth * ex,
          cellWidth * ey,
          cellHeight * fx,
          cellHeight * fy,
          text.textColor[entity],
          address,
          text.textFilter[entity],
        );
      }
    }
  }

  void _renderView(CameraView cameraView, HandoffHandle handle) {
    lastSpriteCount = 0;
    lastRecordCount = 0;
    lastRecordsOverBudget = 0;
    // Asked *before* any work is done, and that ordering is the point. Null
    // means main has not taken the last frame yet, so there is nowhere safe to
    // write - and instead of building a frame and throwing it away, the whole
    // pass is skipped. The simulation is unaffected; only the drawing stops,
    // and only while nobody is looking. This is what stops a 200Hz tick
    // building and discarding two frames out of every three against a 60Hz
    // display.
    final frames = handle.tryBuffer;
    if (frames == null) return;
    final target = frames.beginWrite();
    if (target == null) {
      lastWriteDropped = true;
      return;
    }

    // The scratch is built on first use and not at bind time: only the
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

    // Through `CameraProjection`, not by reading the camera's fields
    // here, so this and `MousePickingSystem` cannot end up applying two
    // slightly different mappings - picking that disagreed with drawing by a
    // constant would mean clicking next to what you can see. No camera is
    // not an error: the projection resolves to the identity plus centring.
    final projection = _projection..resolve(cameras, cameraView);
    // Pass one: collect what is going to be drawn. Nothing is written to the
    // byte scratch yet, because the order is not known until every candidate
    // has been seen.
    final queue = _queue..reset();
    // **The budget is not spent here.** This pass queues every visible
    // candidate the camera can see, and `_SpriteDrawQueue.trimToBudget` spends
    // the budget after the sort, when depth is known. Spending it here meant
    // spending it in encounter order - archetype registration, then page, then
    // row - so what a frame lost was whichever archetype was declared last,
    // which is not a property of the scene at all (#175).
    //
    // What that costs is the queue growing to the candidate high-water instead
    // of the budget: Dart heap, 80 bytes per queued sprite, and it never
    // crosses the isolate boundary. The native handoff and the byte scratch
    // are still sized from `maxSpritesPerTick` and the trim is what keeps the
    // write inside them.
    //
    // Culling still comes first, so what is queued is bounded by what the
    // camera sees rather than by the size of the world.
    //
    // This view draws the scene its camera is in and no other - the test is
    // `projection.shows` below. There is no global front scene: "which scene
    // do I draw" is a question a *view* answers and there can be several
    // views; a view with no camera at all scopes nothing out and draws the
    // whole world.
    //
    // Grouped, so the component and its sprite list are resolved once per
    // archetype instead of once per entity - `entity<Renderable2D>().component`
    // hands back the same object for every row, and at 10k rows that shows up
    // in a profile.
    //
    // No `break` out of these loops and no label to break to: there is no
    // longer anything to break for. Every candidate is queued.
    //
    // Three fill passes over two queries, queued in draw order: screen-space
    // backdrops, then the world, then labels, then screen-space entities
    // pinned in front. Draw order is fill order plus the depth sort within
    // each layer - see `_SpriteDrawQueue._splitLayers` for why a screen-space
    // entity is a layer and not a large `zIndex`.
    //
    // The budget still spends from the front of the scene backwards, so what
    // a frame over budget loses is its backdrop first and its pinned layer
    // last. A HUD does not vanish because twenty thousand particles were
    // queued ahead of it.
    _fillSprites(screenRenderables, ScreenLayer.behind);
    queue.beginWorldLayer();
    _fillSprites(renderables, null);
    _fillLabels();
    queue.beginFrontLayer();
    _fillSprites(screenRenderables, ScreenLayer.front);

    if (!debugSkipZSort) queue.sortByZ();
    // The budget, spent now that depth is known. On a frame that fits this is
    // a single comparison against the queued total; on one that does not, the
    // furthest layers are what it drops. See
    // `_SpriteDrawQueue.trimToBudget`.
    queue.trimToBudget(_renderer.maxSpritesPerTick);

    // Pass two: emit the records, in draw order.
    //
    // For a plain sprite this no longer computes anything and no longer reads a
    // component row - the fill pass did both while it was already standing on
    // the row, and left the finished quad in a dense array. All that happens
    // here is a permutation over 40 bytes per sprite. See `_SpriteDrawQueue`'s
    // class doc for the device measurement that forced the split.
    var offset = DrawData2D.batchHeaderBytes;
    final count = queue.length;
    // From the first pair the budget admitted, not from zero: what the trim
    // discarded is a prefix of the sorted order, so skipping it is where the
    // frame's depth slab begins.
    for (var i = queue.firstAdmitted; i < count; i++) {
      final kind = queue.kindAt(i);
      if (kind == _SpriteDrawQueue.kindQuad) {
        offset = queue.writeQuadAt(view, offset, i);
        continue;
      }
      if (kind == _SpriteDrawQueue.kindText) {
        // The label path. It reads a row too, and unavoidably: the characters
        // are on the row and they are the whole of what it draws. Its
        // geometry is not - the fill pass finished that and parked it beside
        // every plain quad's corners.
        offset = queue.writeTextAt(view, offset, i);
        continue;
      }

      // The nine-slice path, left reading rows in z order. It is
      // rare - a sliced sprite is a UI frame, not a particle - and it cannot
      // use the precomputed corners, because nine cells each need their own
      // sub-rectangle of the UV square. Paying a cache miss per sliced sprite
      // is the right trade against carrying a second, wider precompute layout
      // for a case that is a handful of sprites per frame.
      final entity = queue.entityAt(i);
      final sprite = queue.spriteAt(i);
      final source = queue.sourceAt(i);
      // The space this candidate was filled in, resolved a second time: the
      // fill pass answered it per archetype and let the answer go, and the
      // sorted order interleaves archetypes. Two comparisons for a world
      // sprite and one component lookup for a screen one - affordable here
      // for the same reason the row reads below are, since a sliced sprite is
      // a panel and not a particle.
      final place = _writePlacement;
      if (queue.isScreenAt(i)) {
        place.screen(projection, entity<ScreenTransform2D>().component);
      } else {
        place.world(projection);
      }
      final zoom = place.zoom;
      final width = sprite.width[entity] * place.widthScale;
      final height = sprite.height[entity] * place.heightScale;
      final rotation = source.rotation[entity];
      final double cos;
      final double sin;
      if (rotation == 0) {
        cos = 1.0;
        sin = 0.0;
      } else {
        cos = math.cos(rotation);
        // Negated because the quad is composed in view space, which is y-down,
        // while world +y is up. Without it a positive rotation turns clockwise
        // on screen - the one thing the y-up flip does not fix by itself. See
        // `a positive rotation turns counter-clockwise on screen`.
        sin = -math.sin(rotation);
      }
      final tx = (source.x[entity] - place.originX) * zoom + place.anchorX;
      final ty = (place.originY - source.y[entity]) * zoom + place.anchorY;
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

    lastSpriteCount = count - queue.firstAdmitted;
    lastRecordCount = queue.recordCount;
    lastRecordsOverBudget = queue.trimmedRecordCount;
    // One record for the whole tick - see draw_2d.dart's library doc for why
    // this is not one record per sprite.
    //
    // The allocation ledger for this method, in full: this `sublistView`, and
    // one iterator per `Query.run()` call (two of them - renderables and
    // cameras). Both are per *tick* and constant in the number of entities and
    // sprites; the same trade `Game.dispatchCommand` already makes. Nothing
    // in either loop above allocates: the queue reuses its arrays, the sort
    // has no comparator object, the corner maths is all local doubles, and
    // `Entity.get` is a list index plus an `is` test. The texture read has
    // that same shape - an optional-field bit test, then an asset-table list
    // index and an `is` test handing back the instance that already exists -
    // and `writeQuad`'s named arguments are statically resolved, so they
    // compile to positional ones and build no argument object.
    // Into the slot the handoff already handed over, then published. The copy
    // is one a `RingBuffer.tryWrite` would make too, so it is not a new cost -
    // and the `asTypedList` view is one object per *frame*. Writing the
    // geometry straight into the slot and skipping the scratch entirely is
    // possible and is the obvious next step; it needs the per-slot views
    // cached, which needs care about the spawn (a typed-data view of native
    // memory is deep-copied by value), so it is not smuggled in here.
    target.asTypedList(spriteBatchBytes).setRange(0, offset, scratch);
    frames.publish(offset);
    lastWriteDropped = false;
  }
}

/// The prebuilt shortcut for the debug overlay, so a system never spells out
/// `getSystem<GameRenderer2D>().debugDraw` - the standing convention for this
/// engine's own built-in systems.
///
/// ```dart
/// debugDraw.line(x0, y0, x1, y1, color: 0xFF00FFFF);
/// ```
///
/// In a release build [debugDrawEnabled] is a `const false`, so this getter
/// folds to the canonical `DebugDraw2D.disabled` instance: no system lookup,
/// no store, and every method on what it hands back returns immediately.
extension DebugDrawAccessForSystems on GameSystem {
  DebugDraw2D get debugDraw => debugDrawEnabled
      ? getSystem<GameRenderer2D>().debugDraw
      : const DebugDraw2D.disabled();
}

/// [DebugDrawAccessForSystems], for a component instead of a system.
extension DebugDrawAccess on Component {
  DebugDraw2D get debugDraw => debugDrawEnabled
      ? getSystem<GameRenderer2D>().debugDraw
      : const DebugDraw2D.disabled();
}
