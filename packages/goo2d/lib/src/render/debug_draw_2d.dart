import 'dart:math' as math;
import 'dart:typed_data';

import 'package:goo2d/src/data/camera.dart';
import 'package:goo2d/src/render/draw/draw_2d.dart';
import 'package:meta/meta.dart';

/// Whether debug draw is compiled into this build.
///
/// A compile-time constant, so `if (debugDrawEnabled)` is a branch the
/// compiler resolves and drops: the guarded block is not in the shipped
/// binary and neither is anything only it reaches. Every method on
/// [DebugDraw2D] opens with this test, `Renderer2D.describeBuffers` skips the
/// debug handoff behind it, and `GameRenderer2D` skips the debug pass behind
/// it - so a release build allocates no shape store, reserves no native slot
/// and runs no extra pass.
///
/// True in a debug build. False in profile, so a profile run measures the
/// game and not the overlay, and false in release.
///
/// The environment key overrides both: `--dart-define=goo2d.debugDraw=false`
/// takes debug draw out of a debug build, and `=true` puts it into a release
/// one. Overriding it is how the release path gets exercised without a
/// release build.
///
/// # What it does not compile out
///
/// The arguments. `debugDraw.line(a.x[e], a.y[e], tx, ty)` still reads those
/// four values in release before calling a method that returns immediately.
/// Guard the work as well as the drawing where the work is real:
///
/// ```dart
/// if (debugDrawEnabled) {
///   for (final entity in group) {
///     debugDraw.line(world.worldX[entity], world.worldY[entity], tx, ty);
///   }
/// }
/// ```
const bool debugDrawEnabled = bool.fromEnvironment(
  'goo2d.debugDraw',
  defaultValue:
      !bool.fromEnvironment('dart.vm.product') &&
      !bool.fromEnvironment('dart.vm.profile'),
);

/// Shapes a system draws over the world to show what it is thinking - a
/// steering vector, a search radius, a state name - in a debug build, and
/// nothing at all in a release one.
///
/// ```dart
/// class NavigationSystem extends GameSystem with FixedTickable {
///   @override
///   void onFixedUpdate() {
///     for (final group in agents.groups()) {
///       final world = group.get<WorldTransform2D>();
///       for (final entity in group) {
///         debugDraw.line(
///           world.worldX[entity], world.worldY[entity], targetX, targetY,
///           color: 0xFF00FFFF,
///         );
///         debugDraw.circle(targetX, targetY, radius: 0.3);
///         debugDraw.label(world.worldX[entity], world.worldY[entity], 'seek');
///       }
///     }
///   }
/// }
/// ```
///
/// Reach it as `debugDraw` from any `GameSystem` or `Component` - see
/// `DebugDrawAccessForSystems`.
///
/// # World space, pixel ink
///
/// Positions are world coordinates and go through the same `CameraProjection`
/// the sprites do, so a line lands on the thing it describes at any camera
/// position and zoom. [line]'s `thickness` and [label]'s `size` are in view
/// pixels and do not change with zoom, so ink stays legible when the camera
/// pulls back - a one-world-unit label is four pixels tall on a zoomed-out
/// map and tells you nothing.
///
/// Debug shapes are drawn **after** the whole scene, in call order, into
/// their own buffer. They do not sort against sprites and they do not spend
/// `Renderer2D.maxSpritesPerTick`: a debug line that pushed a sprite out of a
/// frame would make the tool lie about the thing being inspected. What they
/// spend is `Renderer2D.maxDebugRecordsPerTick`, which sizes both the store
/// here and the buffer that crosses to main.
///
/// # One store, one record per stroke
///
/// Every call is flattened to straight segments the moment it is made: a
/// circle becomes its `segments` chords, a label becomes its glyphs' strokes.
/// One segment is one draw record. So [line] costs 1, a 24-segment [circle]
/// costs 24, and a label costs the strokes its characters have - around four
/// per character.
///
/// The store is a fixed-capacity pair of typed lists, reused every tick. No
/// call allocates. Past capacity, calls are dropped and counted in
/// [droppedSegments].
///
/// # Shapes stay until they are replaced
///
/// The store is emptied by the first call *after* a frame consumed it, and
/// not by the frame itself. Two things follow, and both are what a debugging
/// overlay wants:
///
///  * A system drawing on a fixed tick slower than the display keeps its
///    shapes on screen between fixed ticks instead of flickering at the beat
///    frequency, and a paused game keeps showing what it drew last.
///  * Several fixed steps inside one displayed frame accumulate. A system
///    drawing an agent's path every step shows every step's path.
///
/// [clear] empties the store outright, for a system that draws only under
/// some condition and wants its shapes gone when the condition stops holding.
final class DebugDraw2D {
  /// A store of [capacity] segments. `GameRenderer2D` builds this one and
  /// sizes it from `Renderer2D.maxDebugRecordsPerTick`, so a segment that
  /// fits here has a record that fits in the buffer.
  DebugDraw2D({required int capacity}) : _store = _DebugSegments(capacity);

  /// The instance a release build gets: no store, and every method returns on
  /// its first line. `const`, so the getter handing it out folds to a
  /// canonical object and the call site allocates nothing and looks nothing
  /// up.
  const DebugDraw2D.disabled() : _store = null;

  final _DebugSegments? _store;

  /// The colour [line], [circle] and [label] draw in when the call names
  /// none. Magenta, which no art asset is.
  static const int defaultColor = 0xFFFF00FF;

  /// The stroke width [line] and [circle] draw with when the call names none,
  /// in view pixels.
  static const double defaultThickness = 1.5;

  /// The cap height [label] draws with when the call names none, in view
  /// pixels.
  static const double defaultLabelSize = 12;

  /// Which categories draw, as a bit per category - bit *n* for shapes passed
  /// `category: n`. Every category, initially.
  ///
  /// Filtering happens at the call, so a category that is off costs one
  /// integer test and stores nothing. Turn one off to read an overlay two
  /// systems are drawing into; set it to `0` to silence the overlay without
  /// touching either system.
  ///
  /// The mask lives on the game isolate, where the shapes are produced. An
  /// app toggling it from a widget sends a command like any other write.
  int get categories => _store?.categories ?? 0;

  set categories(int value) => _store?.categories = value;

  /// How many segments the store holds for the next frame to draw.
  int get segmentCount => _store?.count ?? 0;

  /// The store's capacity in segments, which is
  /// `Renderer2D.maxDebugRecordsPerTick`. Zero in a release build.
  int get segmentCapacity => _store?.capacity ?? 0;

  /// How many segments have been dropped for want of capacity since the run
  /// started.
  ///
  /// Zero means nothing drawn has ever been lost. Anything else is how many
  /// segments are missing from the overlay, and raising
  /// `Renderer2D.maxDebugRecordsPerTick` by at least that much is the fix. A
  /// dropped shape looks like a system that never drew, so the count is what
  /// tells the two apart.
  int get droppedSegments => _store?.dropped ?? 0;

  /// Empties the store, so the next frame draws nothing until something draws
  /// again.
  void clear() {
    if (!debugDrawEnabled) return;
    _store?.count = 0;
  }

  /// Draws a straight line from world `(x0, y0)` to world `(x1, y1)`.
  ///
  /// [thickness] is in view pixels and does not change with zoom. Ends are
  /// square-cut at the exact endpoints, so a chain of lines shows a small
  /// notch at a sharp corner.
  ///
  /// Costs one draw record. A zero-length line draws nothing and still costs
  /// one segment of the store.
  void line(
    double x0,
    double y0,
    double x1,
    double y1, {
    int color = defaultColor,
    double thickness = defaultThickness,
    int category = 0,
  }) {
    if (!debugDrawEnabled) return;
    final store = _store;
    if (store == null || !store.passes(category)) return;
    store.add(x0, y0, 0, 0, x1, y1, 0, 0, color, thickness);
  }

  /// Draws the outline of a circle of world [radius] around world `(x, y)`,
  /// as [segments] chords.
  ///
  /// Costs [segments] draw records. Drop [segments] for a shape drawn once
  /// per entity in a big group - twelve reads as a circle at the sizes a
  /// debug overlay uses.
  ///
  /// A radius of zero, or fewer than three segments, draws nothing and costs
  /// nothing.
  void circle(
    double x,
    double y, {
    required double radius,
    int color = defaultColor,
    double thickness = defaultThickness,
    int segments = 24,
    int category = 0,
  }) {
    if (!debugDrawEnabled) return;
    final store = _store;
    if (store == null || !store.passes(category)) return;
    if (radius == 0 || segments < 3) return;
    final step = 2 * math.pi / segments;
    var px = x + radius;
    var py = y;
    for (var i = 1; i <= segments; i++) {
      final angle = step * i;
      final nx = x + radius * math.cos(angle);
      final ny = y + radius * math.sin(angle);
      store.add(px, py, 0, 0, nx, ny, 0, 0, color, thickness);
      px = nx;
      py = ny;
    }
  }

  /// Draws [text] centred on world `(x, y)`, [size] view pixels tall.
  ///
  /// The glyphs are a stroke alphabet built into this file, so a project that
  /// has declared no font, no atlas and no asset at all still gets labels.
  /// `Text2D` is the other kind of text: a game's own, from a game's own
  /// bitmap font, sorted and scaled with the sprites around it.
  ///
  /// [size] is a cap height in view pixels and does not change with zoom, so
  /// a label stays readable however far the camera pulls back. The text is
  /// axis-aligned whatever the camera does.
  ///
  /// Printable ASCII draws; lower case draws as upper case, and anything
  /// outside `0x20..0x7E` advances and draws nothing. A character costs one
  /// draw record per stroke it has - four on average, ten for the busiest -
  /// so a twenty-character label is around eighty records.
  ///
  /// Allocates nothing beyond whatever built [text].
  void label(
    double x,
    double y,
    String text, {
    int color = defaultColor,
    double size = defaultLabelSize,
    double thickness = defaultThickness,
    int category = 0,
  }) {
    if (!debugDrawEnabled) return;
    final store = _store;
    if (store == null || !store.passes(category)) return;
    final length = text.length;
    if (length == 0 || size <= 0) return;
    // One lattice step. Glyphs are drawn on a 4-wide, 6-tall lattice, so the
    // cap height is six steps.
    final unit = size / _glyphHeight;
    final advance = (_glyphWidth + _glyphGap) * unit;
    final boxWidth = (length - 1) * advance + _glyphWidth * unit;
    // View space is y-down and the lattice is y-up, so a lattice y is
    // subtracted from the box's bottom edge.
    final bottom = size / 2;
    var left = -boxWidth / 2;
    for (var i = 0; i < length; i++) {
      final strokes = _strokesOf(text.codeUnitAt(i));
      for (var s = 0; s + 3 < strokes.length; s += 4) {
        store.add(
          x,
          y,
          left + strokes[s] * unit,
          bottom - strokes[s + 1] * unit,
          x,
          y,
          left + strokes[s + 2] * unit,
          bottom - strokes[s + 3] * unit,
          color,
          thickness,
        );
      }
      left += advance;
    }
  }

  /// Projects every stored segment through [projection] and packs it into
  /// [batch] as one untextured quad each, starting at [offset]. Returns how
  /// many records were written.
  ///
  /// Culled per segment against the viewport, on the circle enclosing the
  /// quad, so an overlay drawn for the whole world costs the buffer only what
  /// the camera can see.
  ///
  /// Never writes more records than the store's capacity, which is what the
  /// batch was sized from.
  @internal
  int writeBatch(ByteData batch, int offset, CameraProjection projection) {
    final store = _store;
    if (store == null) return 0;
    final points = store.points;
    final widths = store.widths;
    final colors = store.colors;
    final count = store.count;
    var written = 0;
    var at = offset;
    for (var i = 0; i < count; i++) {
      final p = i * _DebugSegments.pointStride;
      final vx0 = projection.worldToViewX(points[p]) + points[p + 2];
      final vy0 = projection.worldToViewY(points[p + 1]) + points[p + 3];
      final vx1 = projection.worldToViewX(points[p + 4]) + points[p + 6];
      final vy1 = projection.worldToViewY(points[p + 5]) + points[p + 7];
      final dx = vx1 - vx0;
      final dy = vy1 - vy0;
      final lengthSquared = dx * dx + dy * dy;
      // A zero-length segment has no direction to take a normal from, so
      // there is no quad to write.
      if (lengthSquared == 0) continue;
      final length = math.sqrt(lengthSquared);
      final half = widths[i] / 2;
      final nx = -dy / length * half;
      final ny = dx / length * half;
      final reach = length / 2 + half;
      if (!projection.showsCircle(
        (vx0 + vx1) / 2,
        (vy0 + vy1) / 2,
        reach * reach,
      )) {
        continue;
      }
      at = DrawSpriteData2D.writeQuad(
        batch,
        at,
        vx0 + nx,
        vy0 + ny,
        vx1 + nx,
        vy1 + ny,
        vx1 - nx,
        vy1 - ny,
        vx0 - nx,
        vy0 - ny,
        colors[i],
      );
      written++;
    }
    return written;
  }

  /// Marks the store as drawn. The next call to [line], [circle] or [label]
  /// empties it before storing anything - see the class doc.
  @internal
  void markConsumed() => _store?.consumed = true;
}

/// The segment store: two world endpoints, a view-pixel offset on each, a
/// stroke width and a colour, in fixed-capacity typed lists written over
/// every tick.
///
/// The two coordinate systems on one endpoint are what lets a world-space
/// line and a screen-sized label be the same kind of thing. A line puts its
/// geometry in the world pair and zeroes the offsets; a label puts its anchor
/// in the world pair and the glyph stroke in the offsets, so the camera
/// positions it and nothing scales it.
final class _DebugSegments {
  _DebugSegments(this.capacity)
    : points = Float32List(capacity * pointStride),
      widths = Float32List(capacity),
      colors = Int32List(capacity);

  /// Floats per segment: world `(x, y)` then view-pixel `(x, y)`, for each of
  /// the two ends.
  static const int pointStride = 8;

  final int capacity;
  final Float32List points;
  final Float32List widths;
  final Int32List colors;

  int count = 0;
  int dropped = 0;
  int categories = -1;

  /// Whether a frame has drawn what is in here. The next [add] empties the
  /// store when it has.
  bool consumed = true;

  bool passes(int category) {
    assert(
      category >= 0 && category < 32,
      'a debug draw category is a bit index 0..31, not $category',
    );
    return categories & (1 << category) != 0;
  }

  void add(
    double wx0,
    double wy0,
    double ox0,
    double oy0,
    double wx1,
    double wy1,
    double ox1,
    double oy1,
    int color,
    double thickness,
  ) {
    if (consumed) {
      count = 0;
      consumed = false;
    }
    if (count == capacity) {
      dropped++;
      return;
    }
    final p = count * pointStride;
    points[p] = wx0;
    points[p + 1] = wy0;
    points[p + 2] = ox0;
    points[p + 3] = oy0;
    points[p + 4] = wx1;
    points[p + 5] = wy1;
    points[p + 6] = ox1;
    points[p + 7] = oy1;
    widths[count] = thickness;
    colors[count] = color;
    count++;
  }
}

/// Lattice columns a glyph spans: `x` runs `0..4`.
const int _glyphWidth = 4;

/// Lattice rows from baseline to cap height: `y` runs `0..6`, and `-1` is the
/// descender row a comma and an underscore reach into.
const int _glyphHeight = 6;

/// Lattice steps between one glyph's box and the next.
const int _glyphGap = 1;

/// The strokes [DebugDraw2D.label] draws [codeUnit] with, or an empty list
/// for a character this alphabet has no shape for.
///
/// Lower case folds to upper case: the alphabet is half the strokes that way,
/// and a debug label is read, not typeset.
List<int> _strokesOf(int codeUnit) {
  var code = codeUnit;
  if (code >= 0x61 && code <= 0x7A) code -= 0x20;
  if (code < 0x20 || code > 0x7E) return const <int>[];
  return _glyphs[code - 0x20];
}

/// One entry per code point `0x20..0x7E`, each a flat list of `x0, y0, x1, y1`
/// lattice coordinates - four numbers per stroke.
///
/// Straight strokes only: a curve is its chords, and a debug label at twelve
/// pixels shows no difference. The lower-case entries are empty because
/// [_strokesOf] folds them away before indexing.
const List<List<int>> _glyphs = <List<int>>[
  <int>[], // 0x20 space
  <int>[2, 6, 2, 2, 2, 1, 2, 0], // !
  <int>[1, 6, 1, 4, 3, 6, 3, 4], // "
  <int>[1, 6, 1, 0, 3, 6, 3, 0, 0, 4, 4, 4, 0, 2, 4, 2], // #
  <int>[
    2, 6, 2, 0, 4, 5, 3, 6, 3, 6, 1, 6, 1, 6, 0, 5, 0, 5, 4, 2, //
    4, 2, 4, 1, 4, 1, 3, 0, 3, 0, 1, 0, 1, 0, 0, 1,
  ], // $
  <int>[
    0, 0, 4, 6, 0, 5, 1, 5, 1, 5, 1, 6, 1, 6, 0, 6, 0, 6, 0, 5, //
    3, 0, 4, 0, 4, 0, 4, 1, 4, 1, 3, 1, 3, 1, 3, 0,
  ], // %
  <int>[
    4, 0, 1, 4, 1, 4, 1, 5, 1, 5, 2, 6, 2, 6, 3, 5, 3, 5, 0, 2, //
    0, 2, 0, 1, 0, 1, 1, 0, 1, 0, 3, 0, 3, 0, 4, 1,
  ], // &
  <int>[2, 6, 2, 4], // '
  <int>[3, 6, 1, 4, 1, 4, 1, 2, 1, 2, 3, 0], // (
  <int>[1, 6, 3, 4, 3, 4, 3, 2, 3, 2, 1, 0], // )
  <int>[2, 5, 2, 1, 0, 4, 4, 2, 0, 2, 4, 4], // *
  <int>[2, 5, 2, 1, 0, 3, 4, 3], // +
  <int>[2, 1, 1, -1], // ,
  <int>[0, 3, 4, 3], // -
  <int>[2, 0, 2, 1], // .
  <int>[0, 0, 4, 6], // /
  <int>[
    1, 6, 3, 6, 3, 6, 4, 5, 4, 5, 4, 1, 4, 1, 3, 0, 3, 0, 1, 0, //
    1, 0, 0, 1, 0, 1, 0, 5, 0, 5, 1, 6, 1, 1, 3, 5,
  ], // 0
  <int>[1, 5, 2, 6, 2, 6, 2, 0, 1, 0, 3, 0], // 1
  <int>[
    0, 5, 1, 6, 1, 6, 3, 6, 3, 6, 4, 5, 4, 5, 4, 4, 4, 4, 0, 0, //
    0, 0, 4, 0,
  ], // 2
  <int>[
    0, 6, 4, 6, 4, 6, 2, 3, 2, 3, 4, 2, 4, 2, 4, 1, 4, 1, 3, 0, //
    3, 0, 1, 0, 1, 0, 0, 1,
  ], // 3
  <int>[3, 0, 3, 6, 3, 6, 0, 2, 0, 2, 4, 2], // 4
  <int>[
    4, 6, 1, 6, 1, 6, 0, 3, 0, 3, 3, 3, 3, 3, 4, 2, 4, 2, 4, 1, //
    4, 1, 3, 0, 3, 0, 1, 0, 1, 0, 0, 1,
  ], // 5
  <int>[
    3, 6, 1, 5, 1, 5, 0, 3, 0, 3, 0, 1, 0, 1, 1, 0, 1, 0, 3, 0, //
    3, 0, 4, 1, 4, 1, 4, 2, 4, 2, 3, 3, 3, 3, 0, 3,
  ], // 6
  <int>[0, 6, 4, 6, 4, 6, 1, 0], // 7
  <int>[
    1, 6, 3, 6, 3, 6, 4, 5, 4, 5, 4, 1, 4, 1, 3, 0, 3, 0, 1, 0, //
    1, 0, 0, 1, 0, 1, 0, 5, 0, 5, 1, 6, 1, 3, 3, 3,
  ], // 8
  <int>[
    1, 0, 3, 1, 3, 1, 4, 3, 4, 3, 4, 5, 4, 5, 3, 6, 3, 6, 1, 6, //
    1, 6, 0, 5, 0, 5, 0, 4, 0, 4, 1, 3, 1, 3, 4, 3,
  ], // 9
  <int>[2, 4, 2, 5, 2, 1, 2, 2], // :
  <int>[2, 4, 2, 5, 2, 2, 1, 0], // ;
  <int>[4, 6, 0, 3, 0, 3, 4, 0], // <
  <int>[0, 4, 4, 4, 0, 2, 4, 2], // =
  <int>[0, 6, 4, 3, 4, 3, 0, 0], // >
  <int>[
    0, 5, 1, 6, 1, 6, 3, 6, 3, 6, 4, 5, 4, 5, 4, 4, 4, 4, 2, 3, //
    2, 3, 2, 2, 2, 1, 2, 0,
  ], // ?
  <int>[
    3, 2, 2, 2, 2, 2, 2, 4, 2, 4, 3, 4, 3, 4, 3, 1, 3, 1, 1, 0, //
    1, 0, 0, 2, 0, 2, 0, 4, 0, 4, 1, 6, 1, 6, 3, 6, 3, 6, 4, 4,
  ], // @
  <int>[0, 0, 2, 6, 2, 6, 4, 0, 1, 2, 3, 2], // A
  <int>[
    0, 0, 0, 6, 0, 6, 3, 6, 3, 6, 4, 5, 4, 5, 3, 3, 3, 3, 0, 3, //
    3, 3, 4, 2, 4, 2, 3, 0, 3, 0, 0, 0,
  ], // B
  <int>[
    4, 5, 3, 6, 3, 6, 1, 6, 1, 6, 0, 5, 0, 5, 0, 1, 0, 1, 1, 0, //
    1, 0, 3, 0, 3, 0, 4, 1,
  ], // C
  <int>[
    0, 0, 0, 6, 0, 6, 3, 6, 3, 6, 4, 5, 4, 5, 4, 1, 4, 1, 3, 0, //
    3, 0, 0, 0,
  ], // D
  <int>[4, 6, 0, 6, 0, 6, 0, 0, 0, 0, 4, 0, 0, 3, 3, 3], // E
  <int>[4, 6, 0, 6, 0, 6, 0, 0, 0, 3, 3, 3], // F
  <int>[
    4, 5, 3, 6, 3, 6, 1, 6, 1, 6, 0, 5, 0, 5, 0, 1, 0, 1, 1, 0, //
    1, 0, 3, 0, 3, 0, 4, 1, 4, 1, 4, 3, 4, 3, 2, 3,
  ], // G
  <int>[0, 0, 0, 6, 4, 0, 4, 6, 0, 3, 4, 3], // H
  <int>[1, 6, 3, 6, 2, 6, 2, 0, 1, 0, 3, 0], // I
  <int>[3, 6, 3, 1, 3, 1, 2, 0, 2, 0, 1, 0, 1, 0, 0, 1], // J
  <int>[0, 0, 0, 6, 4, 6, 0, 3, 0, 3, 4, 0], // K
  <int>[0, 6, 0, 0, 0, 0, 4, 0], // L
  <int>[0, 0, 0, 6, 0, 6, 2, 3, 2, 3, 4, 6, 4, 6, 4, 0], // M
  <int>[0, 0, 0, 6, 0, 6, 4, 0, 4, 0, 4, 6], // N
  <int>[
    1, 6, 3, 6, 3, 6, 4, 5, 4, 5, 4, 1, 4, 1, 3, 0, 3, 0, 1, 0, //
    1, 0, 0, 1, 0, 1, 0, 5, 0, 5, 1, 6,
  ], // O
  <int>[
    0, 0, 0, 6, 0, 6, 3, 6, 3, 6, 4, 5, 4, 5, 4, 4, 4, 4, 3, 3, //
    3, 3, 0, 3,
  ], // P
  <int>[
    1, 6, 3, 6, 3, 6, 4, 5, 4, 5, 4, 1, 4, 1, 3, 0, 3, 0, 1, 0, //
    1, 0, 0, 1, 0, 1, 0, 5, 0, 5, 1, 6, 2, 1, 4, -1,
  ], // Q
  <int>[
    0, 0, 0, 6, 0, 6, 3, 6, 3, 6, 4, 5, 4, 5, 4, 4, 4, 4, 3, 3, //
    3, 3, 0, 3, 2, 3, 4, 0,
  ], // R
  <int>[
    4, 5, 3, 6, 3, 6, 1, 6, 1, 6, 0, 5, 0, 5, 4, 2, 4, 2, 4, 1, //
    4, 1, 3, 0, 3, 0, 1, 0, 1, 0, 0, 1,
  ], // S
  <int>[0, 6, 4, 6, 2, 6, 2, 0], // T
  <int>[0, 6, 0, 1, 0, 1, 1, 0, 1, 0, 3, 0, 3, 0, 4, 1, 4, 1, 4, 6], // U
  <int>[0, 6, 2, 0, 2, 0, 4, 6], // V
  <int>[0, 6, 1, 0, 1, 0, 2, 3, 2, 3, 3, 0, 3, 0, 4, 6], // W
  <int>[0, 0, 4, 6, 0, 6, 4, 0], // X
  <int>[0, 6, 2, 3, 4, 6, 2, 3, 2, 3, 2, 0], // Y
  <int>[0, 6, 4, 6, 4, 6, 0, 0, 0, 0, 4, 0], // Z
  <int>[3, 6, 1, 6, 1, 6, 1, 0, 1, 0, 3, 0], // [
  <int>[0, 6, 4, 0], // \
  <int>[1, 6, 3, 6, 3, 6, 3, 0, 3, 0, 1, 0], // ]
  <int>[0, 4, 2, 6, 2, 6, 4, 4], // ^
  <int>[0, -1, 4, -1], // _
  <int>[1, 6, 3, 5], // `
  <int>[], // a
  <int>[], // b
  <int>[], // c
  <int>[], // d
  <int>[], // e
  <int>[], // f
  <int>[], // g
  <int>[], // h
  <int>[], // i
  <int>[], // j
  <int>[], // k
  <int>[], // l
  <int>[], // m
  <int>[], // n
  <int>[], // o
  <int>[], // p
  <int>[], // q
  <int>[], // r
  <int>[], // s
  <int>[], // t
  <int>[], // u
  <int>[], // v
  <int>[], // w
  <int>[], // x
  <int>[], // y
  <int>[], // z
  <int>[
    3, 6, 2, 5, 2, 5, 2, 4, 2, 4, 1, 3, 1, 3, 2, 2, 2, 2, 2, 1, //
    2, 1, 3, 0,
  ], // {
  <int>[2, 6, 2, -1], // |
  <int>[
    1, 6, 2, 5, 2, 5, 2, 4, 2, 4, 3, 3, 3, 3, 2, 2, 2, 2, 2, 1, //
    2, 1, 1, 0,
  ], // }
  <int>[0, 3, 1, 4, 1, 4, 3, 2, 3, 2, 4, 3], // ~
];
