// Where do `GameRenderer2D`'s write-pass nanoseconds actually go, in an **AOT**
// build?
//
//   cd packages/goo2d
//   dart compile exe tool/write_pass_bench.dart -o build/write_pass_bench.exe
//   ./build/write_pass_bench.exe
//
// # Why AOT, emphatically
//
// A device recording of the Galaxy case at 20,000 sprites put the write pass at
// 8.30 ms of a 23.66 ms frame - about 415 ns per sprite, the single largest item
// in the frame. The first attempt to explain it ran under `flutter test`, which
// is JIT, and got two of its three answers wrong by an order of magnitude:
//
//   * it priced `writeQuad`'s 18 `ByteData` stores at ~111 ns per sprite. In AOT
//     they cost **0.8 ns** more than raw typed-list stores, because a
//     constant-`Endian.little` store folds into a plain one. A planned wire
//     format change evaporated on that number alone.
//   * it priced z-sorted row access at ~69 ns per sprite at 20,000. In AOT, at
//     the row stride this engine actually uses, it is ~2 ns until the working
//     set outgrows the last-level cache.
//
// The engine ships AOT. JIT numbers from this pass are not evidence.
//
// # What is modelled
//
// The layout, not the engine - the arrangement `goo/tool/column_dispatch_bench
// .dart` established. Rows of a fixed stride in a `Float64List`, 13 `float64`
// columns read per row (what the write pass touches per sprite: width, height,
// rotation, x, y, four pivot fields, two scales, texture, colour), then the
// corner arithmetic and the 72-byte record store.
//
// A `Float64List` rather than `calloc`'d native memory because `package:ffi` is
// not a dependency here and nothing under test needs it: this measures the
// memory hierarchy's response to an access *order* and the cost of some
// arithmetic, and a contiguous Dart typed array answers both exactly as a
// native block does. The absolute nanoseconds carry a bounds check the engine's
// `Pointer.fromAddress` path does not; the differences between stages do not.
//
// # The stages, and how each can fail
//
//   readSeq   13 column reads, page order            (what the walk pass does)
//   readZ     the same reads, z-sorted order         (what the write pass does)
//   +trig     and the two math.cos/math.sin calls
//   +quad     and the full 72-byte writeQuad record
//   +quadRaw  the same, through Float32List/Int32List instead of ByteData
//
// Each stage adds exactly one thing, so a stage's cost is its delta from the
// one above. Every stage can report *no* difference from its predecessor, and
// two of them did exactly that, which is the only reason this file is worth
// keeping: `readZ - readSeq` says whether access order matters, and
// `+quadRaw - +quad` says whether the wire format's accessor choice matters.
// The z order is built from the demo's own `zIndex` expression rather than
// from a shuffle, so it reports what that scene really does rather than a
// worst case chosen to make a point.
//
// The `shuffled` column in the order sweep at the bottom is the true random
// permutation, kept as the scale against which "z order is nearly sequential"
// can be judged.
import 'dart:math' as math;
import 'dart:typed_data';

const int _reps = 20;
const int _rounds = 5;

/// Sprite counts to sweep. 20,000 is the case being explained; the others make
/// the curve visible - a miss-bound cost climbs as the working set outgrows
/// each cache level, a compute-bound one stays flat.
const List<int> _counts = <int>[5000, 20000, 40000];

/// The row stride the stage ladder runs at, in bytes. A `Mote` row is roughly
/// this: five `Transform2D` doubles, six of its own, and an eighteen-field
/// `Sprite`.
const int _moteStrideBytes = 256;

/// Strides for the order sweep. 64 is a lean row, 512 a fat one; the cost of a
/// miss is a whole cache line whatever fraction of it is read, so a fat row and
/// a lean one must diverge or misses are not what is being measured.
const List<int> _strideSweep = <int>[64, 256, 512];

const int _columns = 13;
const int _quadStrideBytes = 72;

double _sink = 0;

/// Element indices of the columns within a row, spread across it rather than
/// packed at the front - the transform fields and the sprite fields sit in
/// different parts of a real row, so a row straddles more than one cache line
/// even when only 13 of its fields are wanted.
Int32List _columnIndices(int strideDoubles) {
  final indices = Int32List(_columns);
  for (var c = 0; c < _columns; c++) {
    indices[c] = (c * (strideDoubles - 1)) ~/ (_columns - 1);
  }
  return indices;
}

@pragma('vm:never-inline')
double _read(
  Float64List data,
  int stride,
  Int32List order,
  Int32List at,
  int n,
) {
  var acc = 0.0;
  for (var i = 0; i < n; i++) {
    final row = order[i] * stride;
    for (var c = 0; c < _columns; c++) {
      acc += data[row + at[c]];
    }
  }
  return acc;
}

@pragma('vm:never-inline')
double _readTrig(
  Float64List data,
  int stride,
  Int32List order,
  Int32List at,
  int n,
) {
  var acc = 0.0;
  for (var i = 0; i < n; i++) {
    final row = order[i] * stride;
    final rotation = data[row + at[2]];
    acc += math.cos(rotation) + math.sin(rotation);
    for (var c = 0; c < _columns; c++) {
      acc += data[row + at[c]];
    }
  }
  return acc;
}

/// The whole per-sprite body: reads, trig, corner arithmetic, record store -
/// through `ByteData` with `Endian.little`, exactly as `writeQuad` does today.
@pragma('vm:never-inline')
double _quadByteData(
  Float64List data,
  int stride,
  Int32List order,
  Int32List at,
  int n,
  ByteData out,
) {
  var offset = 8;
  for (var i = 0; i < n; i++) {
    final row = order[i] * stride;
    final width = data[row + at[0]];
    final height = data[row + at[1]];
    final rotation = data[row + at[2]];
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    final tx = data[row + at[3]];
    final ty = data[row + at[4]];
    final pivotX = data[row + at[5]] * width + data[row + at[6]];
    final pivotY = data[row + at[7]] * height + data[row + at[8]];
    final scaleX = data[row + at[9]];
    final scaleY = data[row + at[10]];
    final color = data[row + at[11]].toInt();
    final address = data[row + at[12]].toInt();
    final lx0 = -pivotX * scaleX;
    final lx1 = (width - pivotX) * scaleX;
    final ly0 = -pivotY * scaleY;
    final ly1 = (height - pivotY) * scaleY;
    final ax0 = lx0 * cos;
    final ax1 = lx1 * cos;
    final ay0 = lx0 * sin;
    final ay1 = lx1 * sin;
    final bx0 = ly0 * sin;
    final bx1 = ly1 * sin;
    final by0 = ly0 * cos;
    final by1 = ly1 * cos;
    out
      ..setFloat32(offset, tx + ax0 - bx0, Endian.little)
      ..setFloat32(offset + 4, ty + ay0 + by0, Endian.little)
      ..setFloat32(offset + 8, tx + ax1 - bx0, Endian.little)
      ..setFloat32(offset + 12, ty + ay1 + by0, Endian.little)
      ..setFloat32(offset + 16, tx + ax1 - bx1, Endian.little)
      ..setFloat32(offset + 20, ty + ay1 + by1, Endian.little)
      ..setFloat32(offset + 24, tx + ax0 - bx1, Endian.little)
      ..setFloat32(offset + 28, ty + ay0 + by1, Endian.little)
      ..setUint32(offset + 32, color, Endian.little)
      ..setInt32(offset + 36, address, Endian.little)
      ..setFloat32(offset + 40, 0, Endian.little)
      ..setFloat32(offset + 44, 0, Endian.little)
      ..setFloat32(offset + 48, 1, Endian.little)
      ..setFloat32(offset + 52, 0, Endian.little)
      ..setFloat32(offset + 56, 1, Endian.little)
      ..setFloat32(offset + 60, 1, Endian.little)
      ..setFloat32(offset + 64, 0, Endian.little)
      ..setFloat32(offset + 68, 1, Endian.little);
    offset += _quadStrideBytes;
  }
  return offset.toDouble();
}

/// [_quadByteData] with the record stored through typed-list views instead.
/// Byte offset 8 and stride 72 are both multiples of 4, so every field lands on
/// an exact element index in both views - which is what makes this alternative
/// available at all.
@pragma('vm:never-inline')
double _quadTypedViews(
  Float64List data,
  int stride,
  Int32List order,
  Int32List at,
  int n,
  Float32List outF,
  Int32List outI,
) {
  var w = 2;
  for (var i = 0; i < n; i++) {
    final row = order[i] * stride;
    final width = data[row + at[0]];
    final height = data[row + at[1]];
    final rotation = data[row + at[2]];
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    final tx = data[row + at[3]];
    final ty = data[row + at[4]];
    final pivotX = data[row + at[5]] * width + data[row + at[6]];
    final pivotY = data[row + at[7]] * height + data[row + at[8]];
    final scaleX = data[row + at[9]];
    final scaleY = data[row + at[10]];
    final color = data[row + at[11]].toInt();
    final address = data[row + at[12]].toInt();
    final lx0 = -pivotX * scaleX;
    final lx1 = (width - pivotX) * scaleX;
    final ly0 = -pivotY * scaleY;
    final ly1 = (height - pivotY) * scaleY;
    final ax0 = lx0 * cos;
    final ax1 = lx1 * cos;
    final ay0 = lx0 * sin;
    final ay1 = lx1 * sin;
    final bx0 = ly0 * sin;
    final bx1 = ly1 * sin;
    final by0 = ly0 * cos;
    final by1 = ly1 * cos;
    outF[w] = tx + ax0 - bx0;
    outF[w + 1] = ty + ay0 + by0;
    outF[w + 2] = tx + ax1 - bx0;
    outF[w + 3] = ty + ay1 + by0;
    outF[w + 4] = tx + ax1 - bx1;
    outF[w + 5] = ty + ay1 + by1;
    outF[w + 6] = tx + ax0 - bx1;
    outF[w + 7] = ty + ay0 + by1;
    outI[w + 8] = color;
    outI[w + 9] = address;
    outF[w + 10] = 0;
    outF[w + 11] = 0;
    outF[w + 12] = 1;
    outF[w + 13] = 0;
    outF[w + 14] = 1;
    outF[w + 15] = 1;
    outF[w + 16] = 0;
    outF[w + 17] = 1;
    w += 18;
  }
  return w.toDouble();
}

double _time(int n, double Function() body) {
  for (var warm = 0; warm < 3; warm++) {
    _sink += body();
  }
  var best = double.infinity;
  for (var round = 0; round < _rounds; round++) {
    final clock = Stopwatch()..start();
    for (var rep = 0; rep < _reps; rep++) {
      _sink += body();
    }
    clock.stop();
    final ns = clock.elapsedMicroseconds * 1000.0 / (_reps * n);
    if (ns < best) best = ns;
  }
  return best;
}

/// Rows filled with plausible values, plus the three orders over them.
class _Fixture {
  _Fixture(this.n, int strideBytes) : stride = strideBytes ~/ 8 {
    at = _columnIndices(stride);
    data = Float64List(n * stride);
    for (var row = 0; row < n; row++) {
      final base = row * stride;
      for (var c = 0; c < _columns; c++) {
        data[base + at[c]] = 1.0 + (row % 17) * 0.1 + c;
      }
      // Colour and texture address are read as ints; keep them in range so
      // `toInt()` is not doing something exotic on one stage and not another.
      data[base + at[11]] = 0xFF00FF00;
      data[base + at[12]] = -1;
    }

    sequential = Int32List(n);
    for (var i = 0; i < n; i++) {
      sequential[i] = i;
    }

    // The demo's own key, verbatim: radius from a low-discrepancy sequence on
    // the spawn index, `zIndex = 4000 - radius`. Sorting by it produces the
    // permutation `GameRenderer2D` actually walks, rather than a shuffle
    // chosen to make the point.
    final keys = Int32List(n);
    for (var i = 0; i < n; i++) {
      final u = (i * 0.6180339887498949) % 1.0;
      keys[i] = 4000 - (70 + 380 * math.sqrt(u)).round();
    }
    zOrder = Int32List.fromList(sequential)..sort((a, b) => keys[a] - keys[b]);

    final random = math.Random(20260815);
    shuffled = Int32List.fromList(sequential);
    for (var i = n - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final t = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = t;
    }
  }

  final int n;
  final int stride;
  late final Int32List at;
  late final Float64List data;
  late final Int32List sequential;
  late final Int32List zOrder;
  late final Int32List shuffled;
}

String _pad(double v) => v.toStringAsFixed(1).padLeft(11);

void main() {
  final report = StringBuffer();

  // --- the stage ladder, at the real row stride --------------------------
  report
    ..writeln(
      '\nns per sprite, stride $_moteStrideBytes B '
      '(best of $_rounds x $_reps reps)\n',
    )
    ..writeln('   sprites    readSeq      readZ      +trig      +quad'
        '   +quadRaw')
    ..writeln('   ${'-' * 65}');

  for (final n in _counts) {
    final f = _Fixture(n, _moteStrideBytes);
    final bytes = Uint8List(8 + n * _quadStrideBytes);
    final view = ByteData.sublistView(bytes);
    final outF = Float32List.sublistView(bytes);
    final outI = Int32List.sublistView(bytes);

    final readSeq = _time(
      n,
      () => _read(f.data, f.stride, f.sequential, f.at, n),
    );
    final readZ = _time(n, () => _read(f.data, f.stride, f.zOrder, f.at, n));
    final trig = _time(
      n,
      () => _readTrig(f.data, f.stride, f.zOrder, f.at, n),
    );
    final quad = _time(
      n,
      () => _quadByteData(f.data, f.stride, f.zOrder, f.at, n, view),
    );
    final quadRaw = _time(
      n,
      () => _quadTypedViews(f.data, f.stride, f.zOrder, f.at, n, outF, outI),
    );

    report.writeln(
      '   ${n.toString().padLeft(7)}${_pad(readSeq)}${_pad(readZ)}'
      '${_pad(trig)}${_pad(quad)}${_pad(quadRaw)}',
    );
  }

  // --- the order question on its own, swept over stride ------------------
  report
    ..writeln('\nns per row, reads only, by access order\n')
    ..writeln('    rows  stride   sequential     z order    shuffled')
    ..writeln('   ${'-' * 51}');

  for (final n in _counts) {
    for (final strideBytes in _strideSweep) {
      final f = _Fixture(n, strideBytes);
      final seq = _time(n, () => _read(f.data, f.stride, f.sequential, f.at, n));
      final z = _time(n, () => _read(f.data, f.stride, f.zOrder, f.at, n));
      final sh = _time(n, () => _read(f.data, f.stride, f.shuffled, f.at, n));
      report.writeln(
        '   ${n.toString().padLeft(6)}${strideBytes.toString().padLeft(7)}'
        '${_pad(seq)}${_pad(z)}${_pad(sh)}',
      );
    }
  }

  // Printed so the sink is genuinely *read*. One that is only ever assigned is
  // dead by definition - to the analyzer, which says so, and potentially to
  // the optimiser, which is the reason it exists at all.
  report.writeln('\n   sink: $_sink');
  // ignore: avoid_print
  print(report);
}
