import 'dart:io';
import 'dart:typed_data';

import 'package:good_cli/src/generate/image_size.dart';
import 'package:test/test.dart';

import '_temp.dart';

// Every case below is bytes assembled here, not a checked-in image. A fixture
// file states its size in exactly one place - the header this parses - so a
// fixture cannot tell a reader whether 512 came out of the file or out of the
// parser reading the wrong offset. Building the header from named numbers puts
// the expected answer somewhere the parser cannot reach.

Uint8List _png(int width, int height) {
  final bytes = Uint8List(24)
    ..setRange(0, 8, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A,
      0x0A])
    ..setRange(12, 16, 'IHDR'.codeUnits);
  _beUint32(bytes, 16, width);
  _beUint32(bytes, 20, height);
  return bytes;
}

Uint8List _webpVp8x(int width, int height) {
  final bytes = Uint8List(30)
    ..setRange(0, 4, 'RIFF'.codeUnits)
    ..setRange(8, 12, 'WEBP'.codeUnits)
    ..setRange(12, 16, 'VP8X'.codeUnits);
  _leUint24(bytes, 24, width - 1);
  _leUint24(bytes, 27, height - 1);
  return bytes;
}

Uint8List _webpLossy(int width, int height) {
  final bytes = Uint8List(30)
    ..setRange(0, 4, 'RIFF'.codeUnits)
    ..setRange(8, 12, 'WEBP'.codeUnits)
    ..setRange(12, 16, 'VP8 '.codeUnits)
    ..setRange(23, 26, const <int>[0x9D, 0x01, 0x2A]);
  _leUint16(bytes, 26, width);
  _leUint16(bytes, 28, height);
  return bytes;
}

Uint8List _webpLossless(int width, int height) {
  final bytes = Uint8List(25)
    ..setRange(0, 4, 'RIFF'.codeUnits)
    ..setRange(8, 12, 'WEBP'.codeUnits)
    ..setRange(12, 16, 'VP8L'.codeUnits);
  bytes[20] = 0x2F;
  final packed = (width - 1) | ((height - 1) << 14);
  bytes[21] = packed & 0xFF;
  bytes[22] = (packed >> 8) & 0xFF;
  bytes[23] = (packed >> 16) & 0xFF;
  bytes[24] = (packed >> 24) & 0xFF;
  return bytes;
}

Uint8List _gif(int width, int height) {
  final bytes = Uint8List(13)..setRange(0, 6, 'GIF89a'.codeUnits);
  _leUint16(bytes, 6, width);
  _leUint16(bytes, 8, height);
  return bytes;
}

Uint8List _bmp(int width, int height, {int headerSize = 40}) {
  final bytes = Uint8List(54)..setRange(0, 2, 'BM'.codeUnits);
  _leUint32(bytes, 14, headerSize);
  if (headerSize == 12) {
    _leUint16(bytes, 18, width);
    _leUint16(bytes, 20, height);
  } else {
    _leUint32(bytes, 18, width);
    _leUint32(bytes, 22, height);
  }
  return bytes;
}

/// A JPEG with [padding] bytes of metadata segments before the frame header,
/// so the walk has something to walk.
Uint8List _jpeg(int width, int height, {int padding = 0}) {
  final out = <int>[0xFF, 0xD8];
  if (padding > 0) {
    out
      ..addAll(<int>[0xFF, 0xE0, (padding + 2) >> 8, (padding + 2) & 0xFF])
      ..addAll(List<int>.filled(padding, 0));
  }
  out.addAll(<int>[
    0xFF, 0xC0, 0x00, 0x11, 0x08,
    height >> 8, height & 0xFF,
    width >> 8, width & 0xFF,
  ]);
  return Uint8List.fromList(out);
}

void _beUint32(Uint8List b, int i, int v) {
  b[i] = (v >> 24) & 0xFF;
  b[i + 1] = (v >> 16) & 0xFF;
  b[i + 2] = (v >> 8) & 0xFF;
  b[i + 3] = v & 0xFF;
}

void _leUint32(Uint8List b, int i, int v) {
  b[i] = v & 0xFF;
  b[i + 1] = (v >> 8) & 0xFF;
  b[i + 2] = (v >> 16) & 0xFF;
  b[i + 3] = (v >> 24) & 0xFF;
}

void _leUint24(Uint8List b, int i, int v) {
  b[i] = v & 0xFF;
  b[i + 1] = (v >> 8) & 0xFF;
  b[i + 2] = (v >> 16) & 0xFF;
}

void _leUint16(Uint8List b, int i, int v) {
  b[i] = v & 0xFF;
  b[i + 1] = (v >> 8) & 0xFF;
}

void main() {
  group('imageSizeOf', () {
    test('reads a PNG IHDR', () {
      expect(imageSizeOf(_png(512, 256)), const ImageSize(512, 256));
    });

    test('reads all three WebP encodings', () {
      // Asymmetric on purpose: a parser that swapped width for height, or
      // read the same field twice, passes on 64x64 and fails here.
      expect(
        imageSizeOf(_webpVp8x(64, 32)),
        const ImageSize(64, 32),
        reason: 'VP8X stores each side minus one, 24-bit little-endian',
      );
      expect(imageSizeOf(_webpLossy(300, 120)), const ImageSize(300, 120));
      expect(imageSizeOf(_webpLossless(1024, 7)), const ImageSize(1024, 7));
    });

    test('a lossy WebP ignores the two scaling bits above the size', () {
      // The upper 2 bits of each 16-bit field are a horizontal/vertical scale
      // hint, not part of the dimension. A parser reading the whole field
      // reports 16385 here.
      final bytes = _webpLossy(1, 1);
      bytes[27] |= 0xC0;
      bytes[29] |= 0xC0;
      expect(imageSizeOf(bytes), const ImageSize(1, 1));
    });

    test('reads a GIF logical screen descriptor', () {
      expect(imageSizeOf(_gif(48, 96)), const ImageSize(48, 96));
    });

    test('reads both BMP header generations', () {
      expect(imageSizeOf(_bmp(200, 100)), const ImageSize(200, 100));
      expect(
        imageSizeOf(_bmp(20, 10, headerSize: 12)),
        const ImageSize(20, 10),
        reason: 'BITMAPCOREHEADER states 16-bit dimensions, not 32-bit',
      );
    });

    test('a top-down BMP is not a negative image', () {
      final bytes = _bmp(200, 100);
      _leUint32(bytes, 22, 0x100000000 - 100);
      expect(imageSizeOf(bytes), const ImageSize(200, 100));
    });

    test('reads a JPEG frame header past its metadata', () {
      expect(imageSizeOf(_jpeg(640, 480)), const ImageSize(640, 480));
      expect(
        imageSizeOf(_jpeg(640, 480, padding: 4000)),
        const ImageSize(640, 480),
        reason:
            'the frame header follows whatever EXIF and ICC the camera wrote, '
            'so the segment chain has to be walked and not indexed into',
      );
    });

    test('a JPEG states height before width', () {
      expect(imageSizeOf(_jpeg(1, 2)), const ImageSize(1, 2));
    });

    test('bytes that are not an image read as null', () {
      expect(imageSizeOf(Uint8List.fromList('not an image'.codeUnits)), isNull);
      expect(imageSizeOf(Uint8List(0)), isNull);
    });

    test('a header cut short reads as null, not as a wrong number', () {
      // Cut one byte short of the last byte each format's size field occupies,
      // which is not the same as one byte short of the fixture: a GIF states
      // its size in ten bytes and a BMP fixture here is fifty-four long, so
      // trimming the tail would leave both parsers reading a whole answer.
      final shortOfTheSize = <String, Uint8List>{
        'PNG': _png(512, 256).sublist(0, 23),
        'WebP VP8X': _webpVp8x(64, 32).sublist(0, 29),
        'WebP VP8 ': _webpLossy(300, 120).sublist(0, 29),
        'WebP VP8L': _webpLossless(1024, 7).sublist(0, 24),
        'GIF': _gif(48, 96).sublist(0, 9),
        'BMP': _bmp(200, 100).sublist(0, 25),
        'JPEG': _jpeg(640, 480).sublist(0, 10),
      };
      shortOfTheSize.forEach((format, bytes) {
        expect(
          imageSizeOf(bytes),
          isNull,
          reason:
              '$format truncated one byte short of its size field would '
              'otherwise read a number out of bytes that are not there, and '
              'that number becomes a divisor',
        );
      });
    });

    test('a zeroed dimension is not a size', () {
      // It would go on to be a `SpriteFrame.pixels` divisor. Reporting null
      // makes `good generate` name the file instead.
      expect(imageSizeOf(_png(0, 256)), isNull);
      expect(imageSizeOf(_gif(48, 0)), isNull);
    });

    test('the extension does not decide the format', () {
      final dir = testTempDir('good_cli_image_size');
      final file = File('${dir.path}/lying.png')
        ..writeAsBytesSync(_gif(48, 96));
      expect(readImageSize(file), const ImageSize(48, 96));
    });
  });

  group('readImageSize', () {
    test('a file that is not there reads as null', () {
      final dir = testTempDir('good_cli_image_size');
      expect(readImageSize(File('${dir.path}/absent.png')), isNull);
    });

    test('reads the same answer off disk as out of memory', () {
      final dir = testTempDir('good_cli_image_size');
      final file = File('${dir.path}/sheet.webp')
        ..writeAsBytesSync(_webpVp8x(512, 256));
      expect(readImageSize(file), const ImageSize(512, 256));
    });
  });
}
