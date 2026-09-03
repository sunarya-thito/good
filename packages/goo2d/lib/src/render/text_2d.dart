import 'package:good/good.dart';
import 'package:goo2d/src/data/screen_transform.dart';
import 'package:goo2d/src/render/render_2d.dart';
import 'package:goo2d/src/render/texture.dart';
import 'package:meta/meta.dart';

/// A grid of glyph cells on one texture, and the three numbers that turn a
/// code unit into one of them.
///
/// Every cell is the same size, so a glyph's rectangle in the atlas is
/// `index = codeUnit - firstCodepoint` split by [columns] - arithmetic, with
/// no table to consult and nothing to look up. That is what makes text
/// layable-out on the game isolate, which has no font, no `ParagraphBuilder`
/// and no rasteriser: `ui.ParagraphBuilder` throws there and
/// `ui.loadFontFromList` kills the process, so anything that had to measure a
/// glyph would have to measure it on main and send the answer back after the
/// decode - and a label would be missing for the first frames of every run.
///
/// # Fractions, never pixels
///
/// The cell rectangle comes out of [frame] by division, exactly as
/// [SpriteFrame.grid] gets a sprite-sheet cell, so no source image dimension
/// appears anywhere and no `TextureInfo` has to arrive first. A repacked
/// atlas changes nothing here as long as the grid stays a grid.
///
/// [frame] is where the grid sits *within* the texture, so a font packed into
/// a corner of a shared atlas works - the same reason a nine-slice cuts
/// inside its own frame instead of across the whole sheet.
///
/// # One font per prefab
///
/// A `BitmapFont` is held by the component, which is one instance per
/// archetype, so it costs a label's row nothing at all: no texture address,
/// no metrics, no packing. Two fonts in one scene are two prefabs. See
/// [Text2D.textFont].
@immutable
final class BitmapFont {
  BitmapFont({
    required this.texture,
    required this.columns,
    required this.rows,
    this.firstCodepoint = 32,
    int? glyphCount,
    this.frame = SpriteFrame.full,
  }) : glyphCount = glyphCount ?? columns * rows,
       cellU = frame.width / columns,
       cellV = frame.height / rows {
    if (columns < 1 || rows < 1) {
      throw ArgumentError.value(
        columns < 1 ? columns : rows,
        columns < 1 ? 'columns' : 'rows',
        'a glyph grid needs at least one cell per axis',
      );
    }
    if (this.glyphCount < 1 || this.glyphCount > columns * rows) {
      throw ArgumentError.value(
        this.glyphCount,
        'glyphCount',
        'must fit the ${columns * rows} cells of a ${columns}x$rows grid',
      );
    }
    if (firstCodepoint < 0) {
      throw ArgumentError.value(
        firstCodepoint,
        'firstCodepoint',
        'must not be negative',
      );
    }
  }

  /// The atlas. An ordinary [TextureAsset] - a font needs no `AssetKind` of
  /// its own, no `flutter: fonts:` entry and no loader, because a bitmap font
  /// *is* a sprite sheet.
  final TextureAsset texture;

  /// Cells across the grid.
  final int columns;

  /// Cells down the grid.
  final int rows;

  /// The code unit cell 0 draws. 32 (space) by default, which is where an
  /// ASCII atlas normally starts.
  final int firstCodepoint;

  /// How many cells hold a glyph, counted from cell 0 row-major. Defaults to
  /// the whole grid; give it when the last row is only partly filled, so the
  /// empty tail is treated as "not in this font" and draws nothing.
  final int glyphCount;

  /// Where the grid sits on [texture]. The whole image by default.
  final SpriteFrame frame;

  /// One cell's width as a fraction of the texture. Divided once, here,
  /// because the renderer would otherwise divide per glyph per frame.
  final double cellU;

  /// One cell's height as a fraction of the texture. See [cellU].
  final double cellV;

  /// Which cell [codeUnit] draws, or `-1` for a code unit this font has no
  /// glyph for.
  ///
  /// Both renderer passes go through this one method, and that is the point:
  /// the fill pass charges the record budget with the number of code units
  /// this answers for and the write pass emits a quad for each one it answers
  /// for. A second copy of the test in either place is how a charge and an
  /// emission drift apart (#252).
  @pragma('vm:prefer-inline')
  int cellOf(int codeUnit) {
    final cell = codeUnit - firstCodepoint;
    return cell < 0 || cell >= glyphCount ? -1 : cell;
  }
}

/// Draws one line of text in the world, from a grid font, sorted and moved
/// with the sprites around it.
///
/// ```dart
/// class DamageNumber extends EntityStruct
///     with Transform2D, WorldTransform2D, Text2D {
///   late final TextureAsset atlas;
///
///   @override
///   int get textCapacity => 8;
///
///   @override
///   void describeAssets(AssetDescriptor descriptor) {
///     super.describeAssets(descriptor);
///     atlas = descriptor.has(fontAtlasKey);
///   }
///
///   @override
///   BitmapFont get textFont =>
///       BitmapFont(texture: atlas, columns: 16, rows: 6);
///
///   @override
///   void describeStruct(DataDescriptor data) {
///     super.describeStruct(data);
///     textCellWidth.initialValue = 8;
///     textCellHeight.initialValue = 12;
///   }
/// }
///
/// entity<Text2D>().setInt(-24);
/// ```
///
/// # World space only
///
/// A label is placed by its entity's transform and drawn through the camera,
/// so it scales, moves and rotates with everything else. There is no
/// screen-space mode here. A HUD is Flutter widgets over the `GameView` (see
/// the Flutter bridge guide), and anchoring an *entity* to the viewport is
/// `ScreenTransform2D`'s job (#132).
///
/// # A plain `Component`, and one label per entity
///
/// An entity that wants a name and a damage number wants two entities, or a
/// child. `Renderable2D` is a `MultiComponent` because a body and a hat move
/// together and there is nothing else they could be; two labels have a
/// transform each to differ by, and the sub-handle a `MultiComponent` hands
/// out is reached as `label.setText(entity, ...)`, which is the spelling
/// `design-rules.md` rejects. `entity<Text2D>().setText(...)` is the
/// accessor spelling, and it needs the component to be a plain one.
///
/// # What a label costs
///
/// The row holds [textCapacity] `uint16` code units and about fifty more
/// bytes; the font, its metrics and the atlas address are on the component,
/// which is per archetype. So a 16-character label is roughly a 220-byte row.
/// Declared as sixteen sprites it would be a 2.5 KiB row, and
/// `_SpriteDrawQueue`'s own doc records what rows that size did to the write
/// pass on a device.
///
/// Against the *record* budget a label is one candidate costing one record
/// per glyph it draws. `maxSpritesPerTick` counts records, and admission is
/// all or nothing, so a 200-glyph label either fits whole or closes the
/// budget for everything behind it. See the rendering guide.
///
/// # Out of scope, and staying that way for now
///
/// Proportional metrics, kerning, line breaking, bidi and shaping. `\n` is
/// not a line break: it is a code unit like any other, drawn if the font has
/// a cell for it and skipped if not, and it advances either way. Two lines
/// are two entities.
mixin Text2D on Component {
  /// The font this prefab's labels draw with. Override it; the default is
  /// null, and a prefab with no font draws nothing at all.
  ///
  /// Read once, during `describeStruct`, and kept in [textFontResolved].
  /// `describeStruct` runs after `describeAssets`, so a [TextureAsset] the
  /// prefab declared for itself is already populated when an override builds
  /// a font from it.
  ///
  /// An override that constructs a `BitmapFont` allocates one per read, so
  /// anything wanting a prefab's font after the archetype is described reads
  /// [textFontResolved].
  BitmapFont? get textFont => null;

  /// What [textFont] answered, stored while the archetype was described, or
  /// null for a prefab that declares no font.
  ///
  /// This is the frame path's copy: the renderer reads it once per archetype
  /// per frame and never calls [textFont].
  BitmapFont? textFontResolved;

  /// The most UTF-16 code units a label of this prefab holds, `1..65535`.
  /// Override it; the default is 32.
  ///
  /// This is storage, reserved in every row of the archetype whether or not
  /// an entity uses it, so it is `describeCollider`'s `maxPoints` and not a
  /// soft limit. [Text2DAccessor.setText] asserts on a longer string in
  /// debug and truncates in release - see there.
  int get textCapacity => 32;

  /// The label's characters, as UTF-16 code units, `textLength` of them
  /// live. Written through [Text2DAccessor.setText].
  ///
  /// `uint16` and not `uint8`: a `uint8` array cannot hold a code unit above
  /// 255, so writing one would have to either corrupt it silently or refuse
  /// text a game legitimately has. At two bytes a code unit the whole BMP
  /// stores exactly, and the font decides what draws.
  late final DataArrayPointer<int> textCodeUnits;

  /// How many of [textCodeUnits] are the label. Zero is an empty label, which
  /// draws nothing and costs no record.
  final textLength = Field.uint16(0);

  /// Packed ARGB, tinting every glyph. A plain `uint32`, never a `Color`.
  final textColor = Field.uint32(0xFFFFFFFF);

  /// One glyph cell's width in world units, before the transform's scale.
  /// Zero (the declared default) means nothing to draw, exactly as a sprite's
  /// width does.
  final textCellWidth = Field.float64(0);

  /// One glyph cell's height in world units. See [textCellWidth].
  final textCellHeight = Field.float64(0);

  /// Extra world units between one glyph's cell and the next. Negative
  /// tightens a grid whose cells carry more side bearing than you want.
  final textLetterSpacing = Field.float64(0);

  /// Painter's-algorithm depth, in the same space sprites use: a label and a
  /// sprite at the same `zIndex` are ordered by encounter, and labels are
  /// walked after sprites, so the label is in front.
  final textZIndex = Field.int32(0);

  /// Whether this label draws. False produces no record at all.
  final textVisible = Field.boolean(true);

  /// How the atlas is sampled - a [TextureFilter] index.
  ///
  /// `nearest` by default, unlike a sprite. Mipmapped or bilinear sampling at
  /// a cell edge reaches into the neighbouring cell, and in a glyph grid the
  /// neighbour is a different letter, so a smoothed atlas draws faint pieces
  /// of `b` down the side of `a`.
  final textFilter = Field.uint2(TextureFilter.nearest.index);

  /// Where the transform origin sits within the label's own box, resolved as
  /// `fraction * size + offset` against `(length * advance, cellHeight)`.
  ///
  /// **This is the alignment.** The box is as wide as the text currently in
  /// it, so `0.5` centres a label that changes length under the entity and
  /// `0` keeps its left edge there. A separate alignment enum would be a
  /// second way to say the same thing.
  final textPivotFractionX = Field.float64(0.5);

  /// The pivot's y fraction. See [textPivotFractionX].
  final textPivotFractionY = Field.float64(0.5);

  /// The pivot's absolute x offset, added after the fraction, in world units.
  final textPivotOffsetX = Field.float64(0);

  /// The pivot's absolute y offset. See [textPivotOffsetX].
  final textPivotOffsetY = Field.float64(0);

  /// How many code units [Text2DAccessor.setText] has dropped for want of
  /// [textCapacity], summed over every entity of this archetype since the run
  /// started.
  ///
  /// Overflow is a programming error and trips an assert, but an assert is
  /// compiled out of the build people ship, so the count is here as well:
  /// zero means no label has ever been cut, and anything else is how much
  /// text is missing and by how much [textCapacity] is short. Same reason
  /// `GameRenderer2D.lastRecordsOverBudget` reports instead of dropping
  /// quietly.
  int textCodeUnitsDropped = 0;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    // A label draws through the camera projection and has no screen-space
    // path, so a prefab that asked for both would render its text in world
    // space while its sprites sat in the corner of the view - art in the
    // wrong place and nothing anywhere saying why. Refused at declare time
    // instead. See `ScreenTransform2D`, and the rendering guide for what a
    // score in the corner should be.
    assert(
      this is! ScreenTransform2D,
      '$runtimeType mixes in both Text2D and ScreenTransform2D, and there is '
      'no screen-space text. A label is placed through the camera, so this '
      'entity would draw its text in the world and its sprites against the '
      'view. Put the text in a Flutter widget over the GameView, or drop '
      'ScreenTransform2D and let the label live in the world.',
    );
    component.has<Text2D>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    final capacity = textCapacity;
    if (capacity < 1 || capacity > 0xFFFF) {
      throw ArgumentError.value(
        capacity,
        'textCapacity',
        'must be between 1 and 65535 - it is storage reserved in every row',
      );
    }
    textCodeUnits = data.hasArray(.uint16, capacity);
    textFontResolved = textFont;
  }
}

/// Reading and writing one entity's label.
extension Text2DAccessor on Accessor<Text2D> {
  /// Replaces this label with [value], keeping its first `textCapacity` code
  /// units if it is longer.
  ///
  /// **Overflow is a programming error.** The capacity is declared on the
  /// prefab, so a string that does not fit means the prefab reserved too
  /// little, and a debug run stops here saying so. A release build has no
  /// assert to stop it, keeps what fits, and adds the rest to
  /// [Text2D.textCodeUnitsDropped] - a label with its tail missing is a
  /// better shipped frame than a crash, and the count is what says it
  /// happened.
  ///
  /// The assert fires *after* the write, so both builds leave the same row
  /// behind and the debug one additionally stops. An assert that also decided
  /// what got stored would make the row a debug run leaves differ from the
  /// row a shipped one does, which is the one thing a diagnostic must not do.
  ///
  /// Allocates nothing beyond whatever built [value]. For a number that
  /// changes every frame, [setInt] builds no string at all.
  void setText(String value) {
    final text = component;
    final units = text.textCodeUnits;
    final capacity = units.length;
    final length = value.length;
    final kept = length < capacity ? length : capacity;
    for (var i = 0; i < kept; i++) {
      units.set(this, i, value.codeUnitAt(i));
    }
    text.textLength[this] = kept;
    if (length > kept) {
      text.textCodeUnitsDropped += length - kept;
      assert(
        false,
        'a label of $capacity code units cannot hold "$value" ($length). '
        'Raise textCapacity on the prefab - it is storage reserved per row. '
        'A release build keeps the first $capacity and counts the rest in '
        'Text2D.textCodeUnitsDropped.',
      );
    }
  }

  /// Writes [value] as decimal digits, with no `String` in between.
  ///
  /// A damage number, a score and a countdown all change every frame, and
  /// `'$value'` on that path is a heap allocation per entity per frame. This
  /// writes the digits straight into the row.
  ///
  /// Truncates and counts exactly like [setText], and from the *left*, so a
  /// number too long for its capacity keeps its sign and leading digits.
  void setInt(int value) {
    final text = component;
    final units = text.textCodeUnits;
    final capacity = units.length;
    // Counted before anything is written, because the digits come out
    // backwards and the leading ones are the ones worth keeping.
    var digits = 1;
    // `~/ 10` and not `abs()`: the most negative int has no positive form, so
    // negating it first would overflow back to itself.
    for (var rest = value ~/ 10; rest != 0; rest = rest ~/ 10) {
      digits++;
    }
    final length = value < 0 ? digits + 1 : digits;
    final kept = length < capacity ? length : capacity;
    var write = length - 1;
    var rest = value;
    for (var i = 0; i < digits; i++) {
      // Dart truncates towards zero, so a negative value yields negative
      // remainders; negate the digit instead of the number.
      final digit = rest.remainder(10);
      rest = rest ~/ 10;
      if (write < kept) {
        units.set(this, write, 0x30 + (digit < 0 ? -digit : digit));
      }
      write--;
    }
    if (value < 0 && kept > 0) units.set(this, 0, 0x2D);
    text.textLength[this] = kept;
    if (length > kept) {
      text.textCodeUnitsDropped += length - kept;
      // After the write, for the reason [setText] gives.
      assert(
        false,
        'a label of $capacity code units cannot hold $value ($length). Raise '
        'textCapacity on the prefab. A release build keeps the first '
        '$capacity and counts the rest in Text2D.textCodeUnitsDropped.',
      );
    }
  }

  /// The label, as a `String`.
  ///
  /// Builds one, so it is for tests, tools and save files - not for a system
  /// walking a group every tick.
  String get text {
    final component = this.component;
    final units = component.textCodeUnits;
    final length = component.textLength[this];
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.writeCharCode(units.get(this, i));
    }
    return buffer.toString();
  }

  /// How many code units the label currently holds.
  int get textLength => component.textLength[this];
}
