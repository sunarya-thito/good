import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:good/src/asset.dart';

/// A shipped asset pack: which chunk holds each asset, and the key to open one.
///
/// # What this is for
///
/// A release build does not ship its assets as files. `good assets pack`
/// compresses them, seals them into a handful of encrypted chunks, and records
/// which chunk holds what. This is the half that reads that back, and it is
/// mounted *once*, at startup, by the generated `ensureGameReady()`.
///
/// A development build mounts nothing, and every [BundleSource] then resolves
/// its logical path straight through the bundle - which is the whole reason the
/// path stayed logical.
///
/// # A pack is one tier, not the whole story
///
/// It is an [AssetMount], so a game can mount two: the shipped pack, and a
/// downloaded patch above it holding newer copies of some of the same logical
/// paths. Whichever was mounted last answers, and game code cannot tell.
/// [chunkSource] is itself a mount, which is what lets a patch keep its chunks
/// in a directory while the shipped pack keeps its own in the app bundle.
///
/// # Why the decryption lives here and not in a loader
///
/// An [AssetLoader] turns bytes into a `Texture` or an `AudioClip`. Whether
/// those bytes arrived loose, compressed, or through a cipher is not its
/// business, and threading it through would put a decryption branch in every
/// loader anyone ever writes. [AssetSource.load] hands back plaintext; that is
/// the whole contract.
class AssetPack extends AssetMount {
  AssetPack({
    required Map<String, String> mapping,
    required List<int> key,
    AssetMount? chunkSource,
    this.residentChunkBudget = 64 * 1024 * 1024,
  }) : _mapping = Map<String, String>.unmodifiable(mapping),
       _key = key,
       chunkSource = chunkSource ?? const BundleMount() {
    // Empty is legitimate: `good assets pack --encryption=none` produces a
    // packed but unsealed build, and whether a given chunk is encrypted is a
    // flag on that chunk, not a property of the pack. So the only thing worth
    // rejecting here is a key that is neither absent nor the right size -
    // which means the pack and the binary were built from different key files,
    // and every sealed chunk would fail its tag.
    if (key.isNotEmpty && key.length != 32) {
      throw ArgumentError(
        'An asset pack key must be 32 bytes for AES-256, or empty for an '
        'unencrypted pack; got ${key.length}. It comes from the generated '
        'asset_key.dart - a wrong length means the pack and the binary were '
        'built from different key files.',
      );
    }
  }

  final Map<String, String> _mapping;
  final List<int> _key;

  /// Where this pack's `chunk_*.dat` files are read from.
  ///
  /// A mount and not an `AssetBundle`, so a downloaded patch can keep
  /// its chunks in a directory while the shipped pack keeps its own in the app
  /// bundle. Defaults to the app bundle, which is where `good assets pack`
  /// puts them.
  final AssetMount chunkSource;

  /// How many bytes of opened chunks may stay resident.
  ///
  /// A cache with no ceiling is the failure mode to avoid here: chunks are
  /// grouped so that loading a scene touches few of them, but a game that
  /// visits every scene would otherwise end up holding its entire pack -
  /// decompressed - in memory forever. Least-recently-opened chunks are
  /// dropped once the total passes this, and [release] drops all of them at a
  /// scene boundary, which is where the engine knows a burst of loading has
  /// ended.
  final int residentChunkBudget;

  /// Opened chunks, in insertion order so the oldest can be evicted first.
  final Map<String, Map<String, Uint8List>> _open =
      <String, Map<String, Uint8List>>{};
  final Map<String, int> _openBytes = <String, int>{};
  int _residentBytes = 0;

  /// Chunks that were opened successfully at least once.
  ///
  /// The only cheap evidence [check] has. See its doc for why a real stat is
  /// not available.
  final Set<String> _verified = <String>{};

  /// In-flight opens, so twenty assets in one chunk decrypt it once rather
  /// than twenty times. Without this every one of them would start its own
  /// decode before the first finished, which is precisely the case chunking
  /// exists to make cheap.
  final Map<String, Future<Map<String, Uint8List>>> _opening =
      <String, Future<Map<String, Uint8List>>>{};

  /// Whether [logicalPath] is in this pack.
  bool contains(String logicalPath) => _mapping.containsKey(logicalPath);

  /// The chunk holding [logicalPath], or null.
  String? chunkOf(String logicalPath) => _mapping[logicalPath];

  /// Every chunk this pack ships, deduplicated.
  Iterable<String> get chunks => _mapping.values.toSet();

  @override
  String get description =>
      'an asset pack of ${chunks.length} chunk(s) in '
      '${chunkSource.description}';

  /// The plaintext bytes of [logicalPath], or null if this pack has no entry
  /// for it.
  ///
  /// Null only ever means *the manifest does not name this*, which is what
  /// lets a tier below answer instead - an asset added since the last pack is
  /// a legitimate state, not an error. A manifest entry whose chunk turns out
  /// not to hold it is corruption and throws, because falling through there
  /// would serve a stale copy from underneath a broken pack.
  @override
  Future<Uint8List?> tryRead(String logicalPath) async {
    final chunk = _mapping[logicalPath];
    if (chunk == null) return null;
    final members = await _openChunk(chunk);
    final bytes = members[logicalPath];
    if (bytes == null) {
      throw StateError(
        'The manifest says "$logicalPath" is in $chunk, but that chunk does '
        'not contain it. The manifest and the chunks were built from '
        'different runs; repack.',
      );
    }
    return bytes;
  }

  /// The plaintext bytes of [logicalPath]. Throws if this pack has no entry.
  ///
  /// The pack's own spelling, for code that already knows the asset is packed.
  /// [tryRead] is what the mount table walks.
  Future<Uint8List> read(String logicalPath) async {
    final bytes = await tryRead(logicalPath);
    if (bytes == null) {
      throw StateError(
        '"$logicalPath" is not in this asset pack. Either the pack was built '
        'from a different set of declared assets, or the generated '
        'asset_key.dart is out of date - re-run `good generate` and '
        '`good assets pack`.',
      );
    }
    return bytes;
  }

  /// What can be said about [logicalPath] without reading it.
  ///
  /// # There is no stat here, and there cannot be
  ///
  /// The design called for "manifest lookup plus one stat per chunk". On a
  /// Flutter asset bundle that is not available: a bundle entry is not a file,
  /// `AssetBundle` exposes only `load`, and loading *is* reading. So the
  /// honest answers are:
  ///
  ///  * not in the manifest -> [AssetAvailability.unknown], and that is a real
  ///    finding: the build declares an asset the pack never received.
  ///  * in the manifest, and its chunk has already been opened successfully ->
  ///    [AssetAvailability.present], free, and the common case once a scene has
  ///    loaded.
  ///  * in the manifest, chunk not yet opened -> [AssetAvailability.
  ///    unverifiable], because confirming it means decrypting a chunk.
  ///
  /// [verifyChunks] is the deep pass for a "verify game files" button, and
  /// costs one open per chunk instead of one per asset.
  @override
  Future<AssetAvailability> check(String logicalPath) async {
    final chunk = _mapping[logicalPath];
    if (chunk == null) return AssetAvailability.unknown;
    if (_verified.contains(chunk)) return AssetAvailability.present;
    return AssetAvailability.unverifiable;
  }

  /// Opens every chunk once, reporting the ones that failed.
  ///
  /// The expensive check, and the only one that can actually catch a corrupt
  /// install: GCM authenticates, so a chunk whose bytes were altered fails its
  /// tag here instead of yielding garbage to a decoder later.
  ///
  /// One open per *chunk*, so a pack of two hundred assets in six chunks costs
  /// six decrypts.
  Future<Map<String, String>> verifyChunks() async {
    final failures = <String, String>{};
    for (final chunk in chunks) {
      try {
        await _openChunk(chunk);
      } on Object catch (error) {
        failures[chunk] = '$error';
      }
    }
    return failures;
  }

  /// Drops every opened chunk.
  ///
  /// Called at a scene boundary through [AssetMounts.release]: a scene load is
  /// a burst of reads that all want the same few chunks, and the moment it
  /// finishes those chunks are dead weight - the decoded `ui.Image` is what
  /// the game needs from then on, not the compressed bytes it came from.
  @override
  void release() {
    _open.clear();
    _openBytes.clear();
    _residentBytes = 0;
  }

  Future<Map<String, Uint8List>> _openChunk(String chunk) {
    final already = _open[chunk];
    if (already != null) return Future<Map<String, Uint8List>>.value(already);
    final inFlight = _opening[chunk];
    if (inFlight != null) return inFlight;

    final future = _readChunk(chunk);
    _opening[chunk] = future;
    return future.whenComplete(() => _opening.remove(chunk));
  }

  Future<Map<String, Uint8List>> _readChunk(String chunk) async {
    final sealed = await chunkSource.tryRead(chunk);
    if (sealed == null) {
      throw StateError(
        'The manifest names $chunk but ${chunkSource.description} does not '
        'carry it. The pack was built from a different run than the files '
        'beside it, or the chunk was never shipped.',
      );
    }
    final members = readChunkBody(await openChunk(sealed: sealed, key: _key));

    var bytes = 0;
    for (final value in members.values) {
      bytes += value.length;
    }
    // Evicted before insertion, and never evicting what we are about to need:
    // a single chunk larger than the budget is kept anyway, because refusing
    // to hold it would mean it could never be read at all.
    while (_residentBytes + bytes > residentChunkBudget && _open.isNotEmpty) {
      final oldest = _open.keys.first;
      _residentBytes -= _openBytes.remove(oldest) ?? 0;
      _open.remove(oldest);
    }
    _open[chunk] = members;
    _openBytes[chunk] = bytes;
    _residentBytes += bytes;
    _verified.add(chunk);
    return members;
  }
}

// --- the chunk format ------------------------------------------------------
//
// Written by `good assets pack`; see `good_cli/lib/src/assets/pack.dart` for
// the producing half and the reasoning behind each choice. Two copies of a wire
// format is one too many, but the alternative is good depending on the build
// tool - which would put `package:analyzer` and an ffmpeg downloader into every
// shipped game. The format is versioned precisely so the two can be checked
// against each other; `chunkVersion` here and there must agree.

/// `GOOC`.
const List<int> chunkMagic = <int>[0x47, 0x4F, 0x4F, 0x43];
const int chunkVersion = 1;
const int chunkFlagCompressed = 1 << 0;
const int chunkFlagEncrypted = 1 << 1;

/// Header: magic(4) version(1) flags(1) nonce(12) tag(16).
const int chunkHeaderBytes = 34;

/// Unseals one chunk: authenticates, decrypts, decompresses.
Future<Uint8List> openChunk({
  required Uint8List sealed,
  required List<int> key,
}) async {
  if (sealed.length < chunkHeaderBytes) {
    throw const FormatException('Asset chunk is truncated.');
  }
  for (var i = 0; i < chunkMagic.length; i++) {
    if (sealed[i] != chunkMagic[i]) {
      throw const FormatException(
        'Not a good asset chunk - wrong magic. The bundled file is not what '
        'the manifest says it is.',
      );
    }
  }
  final version = sealed[4];
  if (version != chunkVersion) {
    throw FormatException(
      'Asset chunk is version $version; this build of good understands '
      '$chunkVersion. The pack and the binary were built from different '
      'versions of the tool.',
    );
  }
  final flags = sealed[5];
  final payload = sealed.sublist(chunkHeaderBytes);

  List<int> clear = payload;
  if (flags & chunkFlagEncrypted != 0) {
    if (key.length != 32) {
      // Checked here rather than at construction, because *this* is where the
      // answer is known: a pack can hold sealed and unsealed chunks, and only
      // the flags byte says which. A pack built with --encryption=none needs
      // no key at all.
      throw FormatException(
        'This chunk is encrypted but the pack has ${key.isEmpty ? "no key" : "a "
            "${key.length}-byte key"}. AES-256 needs 32 bytes, from the '
        'generated asset_key.dart - the pack and the binary were built from '
        'different key files.',
      );
    }
    // Decryption verifies the tag, so a chunk whose bytes were altered fails
    // here, by name, rather than handing a decoder something that merely looks
    // wrong.
    clear = await AesGcm.with256bits().decrypt(
      SecretBox(
        payload,
        nonce: sealed.sublist(6, 18),
        mac: Mac(sealed.sublist(18, 34)),
      ),
      secretKey: SecretKey(key),
    );
  }
  if (flags & chunkFlagCompressed != 0) {
    clear = GZipDecoder().decodeBytes(clear);
  }
  return clear is Uint8List ? clear : Uint8List.fromList(clear);
}

/// Splits an unsealed chunk body into its members.
///
/// ```text
/// uint32   entry count
/// entries: uint16 name length, name, uint32 offset, uint32 length
/// payloads, concatenated; offsets are relative to the payload section
/// ```
///
/// The index is *inside* the sealed body. A per-asset scheme would need it
/// outside the ciphertext, and an index of every offset and length is a map of
/// the pack in plaintext.
Map<String, Uint8List> readChunkBody(Uint8List body) {
  final view = ByteData.sublistView(body);
  final count = view.getUint32(0, Endian.little);
  var cursor = 4;
  final entries = <String, List<int>>{};
  for (var i = 0; i < count; i++) {
    final nameLength = view.getUint16(cursor, Endian.little);
    cursor += 2;
    final name = utf8.decode(body.sublist(cursor, cursor + nameLength));
    cursor += nameLength;
    entries[name] = <int>[
      view.getUint32(cursor, Endian.little),
      view.getUint32(cursor + 4, Endian.little),
    ];
    cursor += 8;
  }
  final base = cursor;
  return <String, Uint8List>{
    for (final entry in entries.entries)
      entry.key: Uint8List.sublistView(
        body,
        base + entry.value[0],
        base + entry.value[0] + entry.value[1],
      ),
  };
}
