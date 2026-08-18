import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';
import 'package:goo_cli/src/assets/options.dart';
import 'package:goo_cli/src/verbosable.dart';
import 'package:meta/meta.dart';

/// One packed chunk: the assets in it, and the file it is written to.
@immutable
class Chunk {
  const Chunk({required this.name, required this.members});

  /// The output filename, `chunk_ui.dat`.
  final String name;

  /// Logical asset paths, sorted - `assets/ui/button.webp`.
  final List<String> members;
}

/// How assets were grouped, and why.
@immutable
class PackPlan {
  const PackPlan({required this.chunks, required this.grouping});

  final List<Chunk> chunks;

  /// A sentence for the report, because the grouping is currently a stand-in
  /// and a user should not have to read the source to discover that.
  final String grouping;

  int get assetCount =>
      chunks.fold(0, (total, chunk) => total + chunk.members.length);
}

/// Groups the shipped assets into chunks.
///
/// Scene-aware when [byScene] is supplied - see `_planByScene`, which is the
/// grouping the design asked for: a scene load then reads its own chunk and at
/// most a shared one.
///
/// Falls back to grouping by top-level directory when no scene information is
/// available, which happens for a project whose `lib/` declares no scenes this
/// pass could read. That fallback is arbitrary but harmless: the chunk format
/// and the runtime do not care how members were chosen, only that the manifest
/// agrees with them.
PackPlan planPack(
  List<String> assetPaths, {
  required String assetRoot,
  Map<String, Set<String>>? byScene,
}) {
  if (byScene != null && byScene.isNotEmpty) {
    return _planByScene(assetPaths, byScene);
  }
  final root = assetRoot.endsWith('/') ? assetRoot : '$assetRoot/';
  final groups = <String, List<String>>{};
  for (final path in assetPaths) {
    final relative = path.startsWith(root) ? path.substring(root.length) : path;
    final slash = relative.indexOf('/');
    final group = slash == -1 ? '' : relative.substring(0, slash);
    groups.putIfAbsent(group, () => <String>[]).add(path);
  }

  final chunks = <Chunk>[];
  for (final name in groups.keys.toList()..sort()) {
    chunks.add(
      Chunk(
        name: 'chunk_${name.isEmpty ? 'root' : name.replaceAll('/', '_')}.dat',
        members: groups[name]!..sort(),
      ),
    );
  }
  return PackPlan(
    chunks: chunks,
    grouping:
        'grouped by top-level directory (a stand-in until scene-aware '
        'grouping exists)',
  );
}

/// What packing produced.
@immutable
class PackResult {
  const PackResult({
    required this.mapping,
    required this.chunkBytes,
    required this.sourceBytes,
  });

  /// Logical asset path -> the chunk holding it. Empty in development mode,
  /// where an asset is loaded straight from the bundle and there is nothing to
  /// translate.
  final Map<String, String> mapping;

  final int chunkBytes;
  final int sourceBytes;
}

/// The bytes of one chunk, before compression and encryption.
///
/// An index followed by the payloads it points into. The index is *inside* the
/// chunk, which is the whole reason encryption is per-chunk rather than
/// per-asset: a per-asset scheme needs an index outside the ciphertext saying
/// where each asset starts and how long it is, and that index is a map of the
/// pack in plaintext. Here there is nothing outside the ciphertext but a
/// nonce.
///
/// ```text
/// uint32   entry count
/// entries: uint16 path length, path bytes, uint32 offset, uint32 length
/// payloads (concatenated, in entry order)
/// ```
@visibleForTesting
Uint8List buildChunkBody(Map<String, Uint8List> members) {
  final names = members.keys.toList()..sort();
  final header = BytesBuilder();
  final payload = BytesBuilder();

  final count = ByteData(4)..setUint32(0, names.length, Endian.little);
  header.add(count.buffer.asUint8List());

  var offset = 0;
  for (final name in names) {
    final bytes = members[name]!;
    final encoded = utf8.encode(name);
    final entry = ByteData(2)..setUint16(0, encoded.length, Endian.little);
    header
      ..add(entry.buffer.asUint8List())
      ..add(encoded);
    final position = ByteData(8)
      ..setUint32(0, offset, Endian.little)
      ..setUint32(4, bytes.length, Endian.little);
    header.add(position.buffer.asUint8List());
    payload.add(bytes);
    offset += bytes.length;
  }

  // Offsets are relative to the start of the payload section, so the reader
  // does not need to know how long the index turned out to be before it can
  // use them.
  return Uint8List.fromList(header.takeBytes() + payload.takeBytes());
}

/// Reads a chunk body back. The runtime's half, here so the format has exactly
/// one definition and a round-trip test can prove it.
@visibleForTesting
Map<String, Uint8List> readChunkBody(Uint8List body) {
  final view = ByteData.sublistView(body);
  final count = view.getUint32(0, Endian.little);
  var cursor = 4;
  final entries = <String, (int, int)>{};
  for (var i = 0; i < count; i++) {
    final nameLength = view.getUint16(cursor, Endian.little);
    cursor += 2;
    final name = utf8.decode(body.sublist(cursor, cursor + nameLength));
    cursor += nameLength;
    final offset = view.getUint32(cursor, Endian.little);
    final length = view.getUint32(cursor + 4, Endian.little);
    cursor += 8;
    entries[name] = (offset, length);
  }
  final base = cursor;
  return <String, Uint8List>{
    for (final entry in entries.entries)
      entry.key: Uint8List.sublistView(
        body,
        base + entry.value.$1,
        base + entry.value.$1 + entry.value.$2,
      ),
  };
}

/// Magic and version, so a runtime reading a chunk from a future goo says so
/// rather than decrypting nonsense.
const List<int> chunkMagic = <int>[0x47, 0x4F, 0x4F, 0x43]; // 'GOOC'
const int chunkVersion = 1;

/// Header flags. A byte rather than two booleans in the code, because the
/// runtime reads this and every combination has to be expressible - notably
/// `--asset-encryption=none`, which is packed and compressed but not sealed.
const int chunkFlagCompressed = 1 << 0;
const int chunkFlagEncrypted = 1 << 1;

/// Compresses, then encrypts, one chunk body.
///
/// **That order, never the other.** Encrypted bytes are indistinguishable from
/// random and do not compress at all, so encrypt-then-compress produces a
/// larger file *and* the same security - it is pure loss. Compress first and
/// the ciphertext is as small as the plaintext could be made.
///
/// The nonce is derived from a hash of the compressed body. GCM's one
/// unforgivable failure is a repeated (key, nonce) pair, and deriving from
/// content means two different chunks cannot collide unless their bytes are
/// identical - in which case they are the same chunk and reusing the nonce
/// leaks nothing new. It also makes a pack reproducible, which a random nonce
/// would not.
Future<Uint8List> sealChunk({
  required Uint8List body,
  required List<int> key,
  required AssetCompressionLevel compression,
}) async {
  final compressed = compression == AssetCompressionLevel.none
      ? body
      : _gzip(body, compression);

  final nonce = hashing.sha256
      .convert(compressed)
      .bytes
      .sublist(0, 12); // 96-bit, the size GCM is specified for
  final algorithm = AesGcm.with256bits();
  final secret = await algorithm.encrypt(
    compressed,
    secretKey: SecretKey(key),
    nonce: nonce,
  );

  final out = BytesBuilder()
    ..add(chunkMagic)
    ..add(<int>[
      chunkVersion,
      (compression == AssetCompressionLevel.none ? 0 : chunkFlagCompressed) |
          chunkFlagEncrypted,
    ])
    ..add(nonce)
    ..add(secret.mac.bytes)
    ..add(secret.cipherText);
  return out.toBytes();
}

/// Undoes [sealChunk]. Lives here so there is one definition of the format,
/// and so a round-trip is testable without the engine.
Future<Uint8List> openChunk({
  required Uint8List sealed,
  required List<int> key,
}) async {
  for (var i = 0; i < chunkMagic.length; i++) {
    if (sealed[i] != chunkMagic[i]) {
      throw const FormatException('Not a goo asset chunk.');
    }
  }
  final version = sealed[4];
  if (version != chunkVersion) {
    throw FormatException(
      'Asset chunk is version $version; this build understands $chunkVersion.',
    );
  }
  final flags = sealed[5];
  final compressed = flags & chunkFlagCompressed != 0;
  final encrypted = flags & chunkFlagEncrypted != 0;
  final nonce = sealed.sublist(6, 18);
  final mac = sealed.sublist(18, 34);
  final payload = sealed.sublist(34);

  final List<int> clear;
  if (encrypted) {
    final algorithm = AesGcm.with256bits();
    // Decryption verifies the tag, so a corrupted chunk fails here by name
    // rather than yielding garbage further down - which is why the startup
    // readiness check does not need to hash anything.
    clear = await algorithm.decrypt(
      SecretBox(payload, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(key),
    );
  } else {
    clear = payload;
  }
  return compressed
      ? Uint8List.fromList(GZipDecoder().decodeBytes(clear))
      : Uint8List.fromList(clear);
}

int _gzipLevel(AssetCompressionLevel level) => switch (level) {
  AssetCompressionLevel.none => 0,
  AssetCompressionLevel.fast => 1,
  AssetCompressionLevel.normal => 6,
  AssetCompressionLevel.best => 9,
};

/// Gzip, with the header's modification time zeroed.
///
/// # Why zero it
///
/// `GZipEncoder` writes the current clock into bytes 4-7 of its header, so two
/// runs over identical input produce chunks that differ - and because the
/// nonce is a hash of the compressed bytes, *every* byte after the header
/// differs too. A build tool whose output changes when nothing changed defeats
/// any check that asks whether a rebuild produced anything new, and it makes
/// the chunks impossible to pin in a test.
///
/// Not a format change. The field is advisory, every decoder ignores it, and
/// zero is what it means to have no timestamp - so the reader in `goo` needs
/// no matching change and [chunkVersion] stays where it is.
Uint8List _gzip(Uint8List body, AssetCompressionLevel compression) {
  final out = Uint8List.fromList(
    GZipEncoder().encode(body, level: _gzipLevel(compression))!,
  );
  // Guarded rather than assumed: if a future `archive` stops emitting a gzip
  // header here, silently zeroing four bytes of a payload would corrupt every
  // chunk, and doing nothing is the safe half of that choice.
  if (out.length >= 8 && out[0] == 0x1F && out[1] == 0x8B) {
    out.fillRange(4, 8, 0);
  }
  return out;
}

/// Packs [plan] out of [assetDir] into [outputDir].
///
/// Development mode writes nothing and returns an empty mapping: the assets
/// are already loose in the bundle, and the shortest path from a changed file
/// to seeing it is not to touch them at all.
Future<PackResult> packAssets({
  required PackPlan plan,
  required Directory assetDir,
  required Directory outputDir,
  required AssetMode mode,
  required AssetEncryption encryption,
  required AssetCompressionLevel compression,
  required List<int> key,
  required String assetRoot,
  required String chunkRoot,
  required VerboseOutput out,
  required VerboseOutput verbose,
}) async {
  if (mode == AssetMode.development) {
    out.println(
      'Development mode: assets stay loose, unencrypted and uncompressed.',
    );
    return const PackResult(
      mapping: <String, String>{},
      chunkBytes: 0,
      sourceBytes: 0,
    );
  }
  if (encryption == AssetEncryption.aes && key.length != 32) {
    throw ArgumentError(
      'AES-256 needs a 32-byte key; got ${key.length}. The key comes from '
      'lib/goo.generated/asset_key.dart - run `goo generate` if it is missing.',
    );
  }

  final root = assetRoot.endsWith('/') ? assetRoot : '$assetRoot/';
  // Where the chunks *ship*, which is not where the assets came from: they are
  // written to their own directory so a rebuild does not scan them as assets.
  // The mapping is a bundle path the runtime looks up at load, so getting this
  // wrong is a build that packs correctly and then cannot find a single chunk.
  final chunksRoot = chunkRoot.endsWith('/') ? chunkRoot : '$chunkRoot/';
  final mapping = <String, String>{};
  var chunkBytes = 0;
  var sourceBytes = 0;

  outputDir.createSync(recursive: true);
  for (final chunk in plan.chunks) {
    final members = <String, Uint8List>{};
    for (final logical in chunk.members) {
      final relative = logical.startsWith(root)
          ? logical.substring(root.length)
          : logical;
      final file = File('${assetDir.path}/$relative');
      if (!file.existsSync()) {
        throw ArgumentError(
          'Declared asset "$logical" is not at ${file.path}. Run '
          '`goo assets compact` first, or fix the pubspec.',
        );
      }
      final bytes = file.readAsBytesSync();
      sourceBytes += bytes.length;
      members[logical] = bytes;
      mapping[logical] = '$chunksRoot${chunk.name}';
    }

    final body = buildChunkBody(members);
    final sealed = encryption == AssetEncryption.aes
        ? await sealChunk(body: body, key: key, compression: compression)
        : _sealUnencrypted(body, compression);
    File('${outputDir.path}/${chunk.name}').writeAsBytesSync(sealed);
    chunkBytes += sealed.length;
    verbose.printf('%s: %s asset(s), %s bytes\n', [
      chunk.name,
      chunk.members.length,
      sealed.length,
    ]);
  }

  return PackResult(
    mapping: mapping,
    chunkBytes: chunkBytes,
    sourceBytes: sourceBytes,
  );
}

/// A chunk with the same framing but no cipher - `--asset-encryption=none`.
///
/// Same header so the runtime has one parser, with the nonce and mac zeroed
/// and the version byte's neighbour saying it is not encrypted. Worth having
/// because "packed but auditable" is a legitimate thing to want, and because
/// it isolates a packing bug from a crypto one.
Uint8List _sealUnencrypted(Uint8List body, AssetCompressionLevel compression) {
  final compressed = compression == AssetCompressionLevel.none
      ? body
      : _gzip(body, compression);
  return (BytesBuilder()
        ..add(chunkMagic)
        ..add(<int>[
          chunkVersion,
          compression == AssetCompressionLevel.none ? 0 : chunkFlagCompressed,
        ])
        ..add(List<int>.filled(12, 0))
        ..add(List<int>.filled(16, 0))
        ..add(compressed))
      .toBytes();
}

/// Groups by the scene that uses an asset - the real thing the directory
/// grouping stood in for.
///
/// # The rule, and why it is this one
///
/// An asset used by exactly one scene goes in that scene's chunk. Anything used
/// by two or more, or by none that this pass could attribute, goes in a shared
/// chunk. So loading a scene reads its own chunk plus at most the shared one.
///
/// The alternative - a chunk per distinct *set* of scenes, so `{A,B}` gets its
/// own - reads fewer bytes and is what a web bundler does. It is not worth it
/// here: the number of chunks grows toward 2^scenes, a game with thirty scenes
/// would ship hundreds of tiny files, and the thing being optimised is a
/// handful of reads at a loading screen.
///
/// An asset attributed to no scene still ships. It may be loaded by code this
/// pass cannot read, and a grouping that dropped it would produce a build that
/// simply fails - far worse than one that reads an extra chunk.
PackPlan _planByScene(
  List<String> assetPaths,
  Map<String, Set<String>> byScene,
) {
  final users = <String, List<String>>{
    for (final path in assetPaths) path: <String>[],
  };
  for (final entry in byScene.entries) {
    for (final path in entry.value) {
      users[path]?.add(entry.key);
    }
  }

  final groups = <String, List<String>>{};
  for (final path in assetPaths) {
    final scenes = users[path]!..sort();
    final group = scenes.length == 1 ? _sceneChunk(scenes.single) : 'shared';
    groups.putIfAbsent(group, () => <String>[]).add(path);
  }

  final chunks = <Chunk>[
    for (final name in groups.keys.toList()..sort())
      Chunk(name: 'chunk_$name.dat', members: groups[name]!..sort()),
  ];
  final shared = groups['shared']?.length ?? 0;
  return PackPlan(
    chunks: chunks,
    grouping:
        'grouped by scene (${byScene.length} scene(s); $shared asset(s) '
        'shared or unattributed)',
  );
}

/// A scene's chunk name, reduced to something a filesystem is happy with.
String _sceneChunk(String scene) {
  final cleaned = scene.replaceAll(RegExp('[^A-Za-z0-9]'), '').toLowerCase();
  return cleaned.isEmpty ? 'scene' : cleaned;
}
