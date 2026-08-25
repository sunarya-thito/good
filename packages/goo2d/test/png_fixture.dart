import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// The image fixtures the raster tests are written against, and the sweep that
// checks a raster against one. Shared rather than copied: a fixture is only
// worth anything if the expectation and the image are the same function, and
// two files each holding their own PNG encoder is two chances for that to stop
// being true.

/// A 2x1 PNG whose left pixel is opaque red and right pixel opaque blue - the
/// smallest image that can tell a correct UV mapping from a mirrored one, and
/// the same fixture `texture_test.dart` decodes.
final Uint8List png2x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR42mP4z8AAQv8BD/kD'
  '/Zh51wAAAAAASUVORK5CYII=',
);

/// A texel's colour as the `0xRRGGBBAA` the raster readback hands back for it,
/// which is also the order [rgbaPng] writes its bytes in - so a fixture and
/// the expectation against it are the *same function*, and neither can drift
/// from the other.
typedef Texel = int Function(int x, int y);

/// Texel `(x, y)` of the wide sheet: red carries the column, green the row,
/// blue is constant.
///
/// Every texel is a different colour, and `r` and `g` between them say which
/// one it was - so a sample landing on the wrong texel reports where it
/// actually landed rather than just "not what I wanted".
int wideTexel(int x, int y) => (x * 4) << 24 | (y * 8) << 16 | 0x20 << 8 | 0xFF;

/// Texel `(x, y)` of the small sheet, and **disjoint from [wideTexel]'s
/// range**: this one's red is always `0x20` and its blue is always `8 mod 16`,
/// while the wide sheet's blue is always `0x20`. No colour can come out of
/// both images, so reading the wrong *texture* is as visible as reading the
/// wrong texel of the right one.
int smallTexel(int x, int y) =>
    0x20 << 24 | (8 + x * 16) << 16 | (8 + y * 16) << 8 | 0xFF;

/// 64x32, every texel a different colour - see [wideTexel].
final Uint8List png64x32 = rgbaPng(64, 32, wideTexel);

/// 16x16, every texel a different colour, none of them a colour the 64x32
/// sheet can produce - see [smallTexel].
final Uint8List png16x16 = rgbaPng(16, 16, smallTexel);

/// An 8-bit RGBA PNG of [width] x [height] whose texel `(x, y)` is
/// `rgba(x, y)`, written out uncompressed-filtered and zlib'd.
///
/// Generated rather than checked in as base64 because the point of these
/// fixtures is that *each texel is identifiable*, and a 2048-texel image
/// spelled as a base64 blob states nothing a reader can check the assertions
/// against. Here the content is the function, and the function is what the
/// expectations are written in terms of.
Uint8List rgbaPng(int width, int height, Texel rgba) {
  // One filter byte per scanline, then RGBA per texel. Filter 0 (none) the
  // whole way down: this is a fixture, not a packer.
  final raw = Uint8List(height * (1 + width * 4));
  var i = 0;
  for (var y = 0; y < height; y++) {
    raw[i++] = 0;
    for (var x = 0; x < width; x++) {
      final c = rgba(x, y);
      raw[i++] = (c >>> 24) & 0xFF;
      raw[i++] = (c >>> 16) & 0xFF;
      raw[i++] = (c >>> 8) & 0xFF;
      raw[i++] = c & 0xFF;
    }
  }
  final header = Uint8List(13);
  final headerView = ByteData.sublistView(header);
  headerView.setUint32(0, width);
  headerView.setUint32(4, height);
  header[8] = 8; // bits per channel
  header[9] = 6; // colour type: truecolour with alpha
  // 10, 11 and 12 stay zero: deflate, adaptive filtering, no interlacing.
  final out = BytesBuilder();
  out.add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _pngChunk(out, 'IHDR', header);
  _pngChunk(out, 'IDAT', Uint8List.fromList(zlib.encode(raw)));
  _pngChunk(out, 'IEND', Uint8List(0));
  return out.toBytes();
}

/// One length-type-payload-CRC PNG chunk.
void _pngChunk(BytesBuilder out, String type, Uint8List payload) {
  final head = Uint8List(8);
  ByteData.sublistView(head).setUint32(0, payload.length);
  for (var i = 0; i < 4; i++) {
    head[4 + i] = type.codeUnitAt(i);
  }
  final crc = Uint8List(4);
  // The CRC covers the type and the payload, not the length.
  ByteData.sublistView(crc).setUint32(0, _crc32(head.sublist(4), payload));
  out
    ..add(head)
    ..add(payload)
    ..add(crc);
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c;
  }
  return table;
}();

int _crc32(Uint8List type, Uint8List payload) {
  var c = 0xFFFFFFFF;
  for (final part in <Uint8List>[type, payload]) {
    for (var i = 0; i < part.length; i++) {
      c = _crcTable[(c ^ part[i]) & 0xFF] ^ (c >>> 8);
    }
  }
  return c ^ 0xFFFFFFFF;
}

/// Every device pixel of the [width] x [height] rectangle at ([left], [top])
/// must be [expected] for its position *within that rectangle*.
///
/// The whole rectangle rather than a handful of sample points: with a
/// different colour per texel, a sweep says where every sample landed, and a
/// mapping that is right in the middle and wrong at an edge has nowhere to
/// hide. Only the first few mismatches are reported - a wrong shader matrix
/// misses thousands, and a thousand-line diff says nothing the first four do
/// not.
void expectRegion(
  Texel raster, {
  required int left,
  required int top,
  required int width,
  required int height,
  required Texel expected,
  required String reason,
}) {
  String hex(int argb) => '0x${argb.toRadixString(16).padLeft(8, '0')}';
  final wrong = <String>[];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final got = raster(left + x, top + y);
      final want = expected(x, y);
      if (got != want) wrong.add('($x, $y) is ${hex(got)}, want ${hex(want)}');
    }
  }
  expect(
    wrong.take(4).toList(),
    isEmpty,
    reason: '$reason\n${wrong.length} of ${width * height} texels are wrong',
  );
}
