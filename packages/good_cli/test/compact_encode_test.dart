@Timeout(Duration(minutes: 2))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:good_cli/src/assets/compact.dart';
import 'package:good_cli/src/assets/ffmpeg.dart';
import 'package:good_cli/src/config.dart';
import 'package:good_cli/src/verbosable.dart';
import 'package:test/test.dart';

// What `good assets compact` produces, read back out of the file it wrote.
//
// compact_test.dart asserts the ffmpeg argument list and runs nothing. That is
// how #189 shipped: one test pinned `-pix_fmt yuva420p`, another pinned
// `-lossless 1`, both passed, and the combination encoded a chroma-subsampled
// image exactly - 2960 of 8192 bytes changed on a fixture that should have
// round-tripped untouched. A flag assertion cannot see that, so everything
// here goes through runCompaction and then decodes the output.

bool get _hasFfmpeg {
  try {
    return Process.runSync('ffmpeg', <String>['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('good_encode');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// RGBA of the texel at ([x], [y]), packed `0xRRGGBBAA`.
typedef _Texel = int Function(int x, int y);

/// 64x32 and opaque. Every texel is a different colour, and the red and green
/// ramps step by 4 and 8 so neighbouring texels never agree - a subsampling
/// encoder cannot hide in a flat region.
int _opaqueTexel(int x, int y) =>
    (((4 * x) & 0xFF) << 24) | (((8 * y) & 0xFF) << 16) | (0x20 << 8) | 0xFF;

/// 32x32 with alpha as a function of x, so one column is fully transparent,
/// one is fully opaque, and everything between is a distinct partial value.
int _alphaTexel(int x, int y) =>
    (((8 * x) & 0xFF) << 24) |
    (((8 * y) & 0xFF) << 16) |
    (0x40 << 8) |
    ((x * 8) & 0xFF);

/// Compacts a single source texture at [quality] and returns the output
/// decoded back to 8-bit RGBA, one texel every four bytes, top row first.
///
/// Goes through [planCompaction] and [runCompaction] rather than assembling a
/// command line, so the flags under test are the ones the command uses.
Future<Uint8List> _roundTrip({
  required int width,
  required int height,
  required _Texel texel,
  required int quality,
}) async {
  final project = _tempDir();
  final source = Directory('${project.path}/assets_src')
    ..createSync(recursive: true);
  final output = Directory('${project.path}/assets')
    ..createSync(recursive: true);
  File(
    '${source.path}/sheet.png',
  ).writeAsBytesSync(_rgbaPng(width, height, texel));

  final config = GoodConfig(
    assetSource: 'assets_src/',
    assetOutput: 'assets/',
    texture: TextureConfig(quality: quality),
    audio: const AudioConfig(),
  );
  final result = await runCompaction(
    plan: planCompaction(sourceDir: source, config: config),
    sourceDir: source,
    outputDir: output,
    config: config,
    ffmpeg: const Ffmpeg('ffmpeg', FfmpegOrigin.path),
    journal: compactJournal(project),
    out: _quiet,
    verbose: _quiet,
  );
  expect(result.failed, isEmpty, reason: 'the encode itself failed');
  expect(result.written, 1);

  // Decoded by ffmpeg into raw RGBA. The decoder is not what is under test -
  // the same decoder reads the PNG fixture back byte-identical - so any
  // difference here was introduced by the encode.
  final raw = '${project.path}/decoded.raw';
  final decode = Process.runSync('ffmpeg', <String>[
    '-y',
    '-loglevel',
    'error',
    '-i',
    '${output.path}/sheet.webp',
    '-pix_fmt',
    'rgba',
    '-f',
    'rawvideo',
    raw,
  ]);
  expect(
    decode.exitCode,
    0,
    reason: 'could not decode the output: ${decode.stderr}',
  );
  final bytes = File(raw).readAsBytesSync();
  expect(bytes.length, width * height * 4);
  return bytes;
}

/// Every byte of [decoded] that does not match [texel], as `(x, y).channel:
/// got for want`. Texels where [texel] is fully transparent are skipped when
/// [visibleOnly] is set.
List<String> _damage(
  Uint8List decoded,
  int width,
  int height,
  _Texel texel, {
  bool visibleOnly = false,
}) {
  const channels = <String>['r', 'g', 'b', 'a'];
  final damaged = <String>[];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final c = texel(x, y);
      final want = <int>[
        (c >>> 24) & 0xFF,
        (c >>> 16) & 0xFF,
        (c >>> 8) & 0xFF,
        c & 0xFF,
      ];
      final at = (y * width + x) * 4;
      for (var k = 0; k < 4; k++) {
        if (visibleOnly && k < 3 && want[3] == 0) continue;
        if (decoded[at + k] != want[k]) {
          damaged.add(
            '($x, $y).${channels[k]}: ${decoded[at + k]} '
            'for ${want[k]}',
          );
        }
      }
    }
  }
  return damaged;
}

String _report(List<String> damaged, int total) =>
    '${damaged.length} of $total bytes differ; '
    'first: ${damaged.take(6).join(', ')}';

void main() {
  group('a webp texture decodes back to its source (needs ffmpeg)', () {
    test('quality 100 is byte-exact', () async {
      const width = 64;
      const height = 32;
      final decoded = await _roundTrip(
        width: width,
        height: height,
        texel: _opaqueTexel,
        quality: 100,
      );
      final damaged = _damage(decoded, width, height, _opaqueTexel);
      expect(
        damaged,
        isEmpty,
        reason:
            'quality 100 is the lossless setting, so every texel has to come '
            'back as it went in. ${_report(damaged, width * height * 4)}',
      );
    }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');

    test('quality 90 damages the same fixture', () async {
      // Without this the exactness above proves nothing: a fixture that no
      // encoder could damage would pass whatever flags were emitted. This is
      // the same image through the same path, one setting lower, and it has
      // to come back changed.
      const width = 64;
      const height = 32;
      final decoded = await _roundTrip(
        width: width,
        height: height,
        texel: _opaqueTexel,
        quality: 90,
      );
      expect(
        _damage(decoded, width, height, _opaqueTexel),
        isNotEmpty,
        reason:
            'quality 90 is lossy, so a per-texel fixture must not survive it '
            'intact - if it does, the comparison above is not measuring '
            'anything',
      );
    }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');

    test(
      'quality 100 keeps every alpha value and every visible texel',
      () async {
        const width = 32;
        const height = 32;
        final decoded = await _roundTrip(
          width: width,
          height: height,
          texel: _alphaTexel,
          quality: 100,
        );
        final damaged = _damage(
          decoded,
          width,
          height,
          _alphaTexel,
          visibleOnly: true,
        );
        expect(
          damaged,
          isEmpty,
          reason:
              'a partially transparent sprite has to survive too - this is what '
              'the pixel format is chosen for. '
              '${_report(damaged, width * height * 4)}',
        );
        // RGB under a fully transparent texel is not asserted: libwebp discards
        // it in lossless mode unless `-exact 1` is set, and ffmpeg's encoder
        // wrapper exposes no such option. Nothing samples those texels.
      },
      skip: _hasFfmpeg ? null : 'ffmpeg is not installed',
    );
  });
}

/// An 8-bit RGBA PNG of [width] x [height] whose texel `(x, y)` is
/// `rgba(x, y)`, written with no row filtering.
///
/// The same technique as `_rgbaPng` in
/// `packages/goo2d/test/draw_canvas_2d_test.dart`, copied rather than shared:
/// good_cli does not depend on goo2d, and adding a package dependency - or
/// promoting a test fixture writer into either package's public API - is a
/// worse trade than forty lines. Generated rather than checked in as base64
/// for the reason #110 gave: the expectations are written in terms of the
/// function, so a reader can check them against it.
Uint8List _rgbaPng(int width, int height, _Texel rgba) {
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
  for (final byte in type) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >>> 8);
  }
  for (final byte in payload) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

final VerboseOutput _quiet = _NullOutput();

class _NullOutput implements VerboseOutput {
  @override
  void println(Object? object) {}
  @override
  void print(Object? object) {}
  @override
  void printf(String format, List<Object?> args) {}
}
