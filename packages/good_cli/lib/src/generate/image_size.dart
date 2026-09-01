import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The pixel dimensions of an image on disk.
@immutable
class ImageSize {
  const ImageSize(this.width, this.height);

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is ImageSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

/// How many bytes of a file [readImageSize] looks at.
///
/// Every format below one JPEG puts its dimensions in the first few dozen
/// bytes. A JPEG's `SOF` marker sits after whatever EXIF, ICC profile and
/// thumbnail the camera wrote, so the walk needs room; 128 KiB covers a full
/// ICC profile and a thumbnail and still reads one block off the disk.
const int _headerBytes = 128 * 1024;

/// Reads [file]'s pixel dimensions from its header, or `null` when the bytes
/// do not describe an image this recognises.
///
/// PNG, WebP (`VP8X`, `VP8 ` and `VP8L`), GIF, BMP and JPEG. The format comes
/// from the leading bytes and not from the extension, so a `.png` holding a
/// JPEG reads correctly and a `.png` holding nothing reads as `null`.
///
/// Nothing is decoded. Each format states its canvas size in a fixed position
/// near the start of the file, so this reads a header and does arithmetic; it
/// never allocates a pixel buffer and does not depend on an image library.
ImageSize? readImageSize(File file) {
  final Uint8List bytes;
  try {
    final handle = file.openSync();
    try {
      bytes = handle.readSync(_headerBytes);
    } finally {
      handle.closeSync();
    }
  } on FileSystemException {
    return null;
  }
  return imageSizeOf(bytes);
}

/// [readImageSize] against bytes already in hand.
ImageSize? imageSizeOf(Uint8List bytes) {
  if (_startsWith(bytes, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A,
    0x0A])) {
    return _png(bytes);
  }
  if (_startsWith(bytes, const <int>[0x52, 0x49, 0x46, 0x46]) &&
      _matchesAt(bytes, 8, const <int>[0x57, 0x45, 0x42, 0x50])) {
    return _webp(bytes);
  }
  if (_startsWith(bytes, const <int>[0x47, 0x49, 0x46, 0x38])) {
    return _gif(bytes);
  }
  if (_startsWith(bytes, const <int>[0x42, 0x4D])) return _bmp(bytes);
  if (_startsWith(bytes, const <int>[0xFF, 0xD8])) return _jpeg(bytes);
  return null;
}

/// PNG: the `IHDR` chunk is required to come first, so width and height are at
/// fixed offsets 16 and 20, big-endian.
ImageSize? _png(Uint8List bytes) {
  if (bytes.length < 24) return null;
  if (!_matchesAt(bytes, 12, const <int>[0x49, 0x48, 0x44, 0x52])) return null;
  return _sized(_beUint32(bytes, 16), _beUint32(bytes, 20));
}

/// WebP: a RIFF container whose first chunk says which of three encodings the
/// file uses, each stating the canvas size differently.
ImageSize? _webp(Uint8List bytes) {
  if (bytes.length < 16) return null;
  final chunk = String.fromCharCodes(bytes.sublist(12, 16));
  switch (chunk) {
    case 'VP8X':
      // Canvas width and height are 24-bit little-endian, each stored one less
      // than the real value, after the chunk header, one flags byte and three
      // reserved bytes.
      if (bytes.length < 30) return null;
      return _sized(_leUint24(bytes, 24) + 1, _leUint24(bytes, 27) + 1);
    case 'VP8 ':
      // Lossy. The keyframe header starts at 20: three bytes of frame tag,
      // then the start code, then two 16-bit little-endian fields whose low 14
      // bits are the dimensions and whose top 2 are a scaling hint.
      if (bytes.length < 30) return null;
      if (!_matchesAt(bytes, 23, const <int>[0x9D, 0x01, 0x2A])) return null;
      return _sized(
        _leUint16(bytes, 26) & 0x3FFF,
        _leUint16(bytes, 28) & 0x3FFF,
      );
    case 'VP8L':
      // Lossless. One signature byte, then 28 bits packed little-endian:
      // 14 bits of width minus one, then 14 of height minus one.
      if (bytes.length < 25) return null;
      if (bytes[20] != 0x2F) return null;
      final packed = bytes[21] |
          (bytes[22] << 8) |
          (bytes[23] << 16) |
          (bytes[24] << 24);
      return _sized((packed & 0x3FFF) + 1, ((packed >> 14) & 0x3FFF) + 1);
    default:
      return null;
  }
}

/// GIF: the logical screen descriptor follows the six-byte signature, width
/// and height first, little-endian.
ImageSize? _gif(Uint8List bytes) {
  if (bytes.length < 10) return null;
  return _sized(_leUint16(bytes, 6), _leUint16(bytes, 8));
}

/// BMP: the DIB header follows the 14-byte file header, and its own first
/// field is its size, which is what says whether the dimensions are 16-bit or
/// 32-bit.
///
/// A negative height is a top-down bitmap, not a negative image, so the
/// magnitude is the answer.
ImageSize? _bmp(Uint8List bytes) {
  if (bytes.length < 26) return null;
  final headerSize = _leUint32(bytes, 14);
  if (headerSize == 12) {
    if (bytes.length < 22) return null;
    return _sized(_leUint16(bytes, 18), _leUint16(bytes, 20));
  }
  if (headerSize < 40) return null;
  return _sized(_leInt32(bytes, 18).abs(), _leInt32(bytes, 22).abs());
}

/// JPEG: no fixed offset. The dimensions live in whichever start-of-frame
/// marker the encoder used, after however much metadata came first, so the
/// segment chain is walked until one turns up.
ImageSize? _jpeg(Uint8List bytes) {
  var i = 2;
  while (i + 3 < bytes.length) {
    // Segments are byte-aligned by padding with 0xFF, so any run of them is
    // one marker prefix.
    if (bytes[i] != 0xFF) return null;
    var marker = bytes[i + 1];
    var next = i + 2;
    while (marker == 0xFF && next < bytes.length) {
      marker = bytes[next];
      next++;
    }
    // Standalone markers carry no length field: the restart markers, SOI, EOI
    // and TEM.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      i = next;
      continue;
    }
    if (next + 1 >= bytes.length) return null;
    final length = _beUint16(bytes, next);
    if (length < 2) return null;
    // Every SOF except DHT (0xC4), DAC (0xCC) and the define-restart marker
    // (0xC8) states the frame's size in the same layout.
    final isFrame = marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isFrame) {
      // Length, one byte of sample precision, then height and width, each
      // big-endian 16-bit: the last byte read is next + 6.
      if (next + 6 >= bytes.length) return null;
      return _sized(_beUint16(bytes, next + 5), _beUint16(bytes, next + 3));
    }
    // Entropy-coded data follows the start of scan and is not a segment chain,
    // so a file whose size has not turned up by here does not state one.
    if (marker == 0xDA) return null;
    i = next + length;
  }
  return null;
}

/// A size is only an answer when both sides are positive. Zero is what a
/// truncated or zeroed header reads as, and it would go on to be a divisor.
ImageSize? _sized(int width, int height) =>
    width > 0 && height > 0 ? ImageSize(width, height) : null;

bool _startsWith(Uint8List bytes, List<int> prefix) =>
    _matchesAt(bytes, 0, prefix);

bool _matchesAt(Uint8List bytes, int offset, List<int> expected) {
  if (bytes.length < offset + expected.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (bytes[offset + i] != expected[i]) return false;
  }
  return true;
}

int _beUint16(Uint8List b, int i) => (b[i] << 8) | b[i + 1];

int _beUint32(Uint8List b, int i) =>
    (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

int _leUint16(Uint8List b, int i) => b[i] | (b[i + 1] << 8);

int _leUint24(Uint8List b, int i) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16);

int _leUint32(Uint8List b, int i) =>
    b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

int _leInt32(Uint8List b, int i) {
  final value = _leUint32(b, i);
  return value >= 0x80000000 ? value - 0x100000000 : value;
}
