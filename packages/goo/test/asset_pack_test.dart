import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo/src/asset.dart';
import 'package:goo/src/asset_pack.dart';

// The runtime half of the asset pipeline: does a packed build resolve a
// logical path through the manifest, does a development build still go
// straight to the bundle, and is a chunk opened once rather than once per
// asset.
//
// Most chunk bytes here are built by hand rather than by running the packer,
// because goo cannot depend on goo_cli - the build tool carries an analyzer and
// an ffmpeg downloader, neither of which belongs in a shipped game.
//
// Which would leave this suite proving only that goo agrees with itself. The
// one test that does not is `reads a chunk goo_cli actually produced`: it opens
// a chunk checked in at fixtures/asset_chunk/, sealed by the real packer, that
// goo_cli's suite checks it still produces byte for byte. That fixture is the
// only thing holding the two implementations of the format together.

/// Builds a chunk the way `goo assets pack` does, minus compression and
/// encryption - flags 0, so the reader takes the plain path.
Uint8List plainChunk(Map<String, List<int>> members) {
  final names = members.keys.toList()..sort();
  final header = BytesBuilder();
  final payload = BytesBuilder();
  header.add((ByteData(4)..setUint32(0, names.length, Endian.little))
      .buffer
      .asUint8List());
  var offset = 0;
  for (final name in names) {
    final bytes = members[name]!;
    final encoded = utf8.encode(name);
    header
      ..add((ByteData(2)..setUint16(0, encoded.length, Endian.little))
          .buffer
          .asUint8List())
      ..add(encoded)
      ..add((ByteData(8)
            ..setUint32(0, offset, Endian.little)
            ..setUint32(4, bytes.length, Endian.little))
          .buffer
          .asUint8List());
    payload.add(bytes);
    offset += bytes.length;
  }
  final body = <int>[...header.takeBytes(), ...payload.takeBytes()];
  return Uint8List.fromList(<int>[
    ...chunkMagic,
    chunkVersion,
    0, // neither compressed nor encrypted
    ...List<int>.filled(12, 0), // nonce
    ...List<int>.filled(16, 0), // tag
    ...body,
  ]);
}

/// A bundle that serves prepared bytes and counts what was asked for.
///
/// The count is the point: "one chunk open for twenty assets" is a claim about
/// how many times the bundle was read, and nothing else can observe it.
class _CountingBundle extends CachingAssetBundle {
  _CountingBundle(this.entries);

  final Map<String, Uint8List> entries;
  final Map<String, int> loads = <String, int>{};

  @override
  Future<ByteData> load(String key) async {
    loads[key] = (loads[key] ?? 0) + 1;
    final bytes = entries[key];
    if (bytes == null) throw FlutterError('no asset bundled at $key');
    return ByteData.sublistView(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(AssetPack.uninstall);

  final chunk = plainChunk(<String, List<int>>{
    'assets/a.webp': utf8.encode('texture bytes'),
    'assets/b.ogg': utf8.encode('audio bytes'),
  });

  AssetPack packOf(_CountingBundle bundle) => AssetPack(
    mapping: const <String, String>{
      'assets/a.webp': 'assets/chunk_root.dat',
      'assets/b.ogg': 'assets/chunk_root.dat',
    },
    key: const <int>[],
    bundle: bundle,
  );

  group('BundleSource', () {
    test('goes straight to the bundle when no pack is installed', () async {
      final bundle = _CountingBundle(<String, Uint8List>{
        'assets/a.webp': Uint8List.fromList(utf8.encode('loose bytes')),
      });
      final bytes = await BundleSource(
        'assets/a.webp',
        bundle: bundle,
      ).load();
      expect(utf8.decode(bytes), 'loose bytes');
      expect(
        bundle.loads['assets/a.webp'],
        1,
        reason:
            'a development build must not go looking for a chunk that was '
            'never built',
      );
    });

    test('resolves through the pack when one is installed', () async {
      final bundle = _CountingBundle(<String, Uint8List>{
        'assets/chunk_root.dat': chunk,
      });
      AssetPack.install(packOf(bundle));

      // The *same* source and the same logical path as the loose case - which
      // is the whole reason the path stayed logical rather than becoming a
      // chunk offset at pack time.
      final bytes = await const BundleSource('assets/a.webp').load();
      expect(utf8.decode(bytes), 'texture bytes');
      expect(bundle.loads.containsKey('assets/a.webp'), isFalse);
    });

    test('an unpacked path still falls through to the bundle', () async {
      // A pack that does not name every asset is a legitimate state - an asset
      // added after the last pack - and must not become an error.
      final bundle = _CountingBundle(<String, Uint8List>{
        'assets/chunk_root.dat': chunk,
        'assets/late.webp': Uint8List.fromList(utf8.encode('added later')),
      });
      AssetPack.install(packOf(bundle));
      // The bundle is named here because the fall-through path is exactly the
      // one that does *not* go through the pack, so it uses whatever bundle the
      // source itself carries - rootBundle in a real app.
      final bytes = await BundleSource(
        'assets/late.webp',
        bundle: bundle,
      ).load();
      expect(utf8.decode(bytes), 'added later');
    });
  });

  group('chunk caching', () {
    test('two assets in one chunk open it once', () async {
      final bundle = _CountingBundle(<String, Uint8List>{
        'assets/chunk_root.dat': chunk,
      });
      AssetPack.install(packOf(bundle));

      await const BundleSource('assets/a.webp').load();
      await const BundleSource('assets/b.ogg').load();

      expect(
        bundle.loads['assets/chunk_root.dat'],
        1,
        reason:
            'chunking exists so a scene reads few files; opening the chunk per '
            'asset would give back every byte of that',
      );
    });

    test('concurrent reads of one chunk share a single open', () async {
      final bundle = _CountingBundle(<String, Uint8List>{
        'assets/chunk_root.dat': chunk,
      });
      AssetPack.install(packOf(bundle));

      // Started together, so both are in flight before either finishes - the
      // case an "is it already open" check alone would miss.
      await Future.wait(<Future<Uint8List>>[
        const BundleSource('assets/a.webp').load(),
        const BundleSource('assets/b.ogg').load(),
      ]);
      expect(bundle.loads['assets/chunk_root.dat'], 1);
    });

    test('releaseChunks drops the cache, so the next read re-opens', () async {
      final bundle = _CountingBundle(<String, Uint8List>{
        'assets/chunk_root.dat': chunk,
      });
      final pack = packOf(bundle);
      AssetPack.install(pack);

      await const BundleSource('assets/a.webp').load();
      pack.releaseChunks();
      await const BundleSource('assets/a.webp').load();

      expect(
        bundle.loads['assets/chunk_root.dat'],
        2,
        reason:
            'holding every chunk forever is the failure mode - a scene '
            'boundary is where the engine knows the burst is over',
      );
    });

    test('a chunk over the budget is still readable', () async {
      // Refusing to hold it would mean it could never be read at all, which is
      // worse than briefly exceeding a soft ceiling.
      final bundle = _CountingBundle(<String, Uint8List>{
        'assets/chunk_root.dat': chunk,
      });
      AssetPack.install(
        AssetPack(
          mapping: const <String, String>{
            'assets/a.webp': 'assets/chunk_root.dat',
          },
          key: const <int>[],
          bundle: bundle,
          residentChunkBudget: 1,
        ),
      );
      expect(
        utf8.decode(await const BundleSource('assets/a.webp').load()),
        'texture bytes',
      );
    });
  });

  group('check', () {
    test('an asset the pack never received is unknown', () async {
      AssetPack.install(
        packOf(_CountingBundle(<String, Uint8List>{
          'assets/chunk_root.dat': chunk,
        })),
      );
      expect(
        await const BundleSource('assets/never.webp').check(),
        AssetAvailability.unknown,
        reason:
            'this is the real finding a readiness check exists for - the build '
            'declares an asset the pack was never given',
      );
    });

    test('an unopened chunk is unverifiable, not a false pass', () async {
      AssetPack.install(
        packOf(_CountingBundle(<String, Uint8List>{
          'assets/chunk_root.dat': chunk,
        })),
      );
      expect(
        await const BundleSource('assets/a.webp').check(),
        AssetAvailability.unverifiable,
        reason:
            'confirming it means decrypting a chunk, and a bundle entry cannot '
            'be stat-ed - claiming `present` would be a guess',
      );
    });

    test('once its chunk has opened, an asset reports present for free', () async {
      AssetPack.install(
        packOf(_CountingBundle(<String, Uint8List>{
          'assets/chunk_root.dat': chunk,
        })),
      );
      await const BundleSource('assets/a.webp').load();
      expect(
        await const BundleSource('assets/b.ogg').check(),
        AssetAvailability.present,
        reason: 'a sibling in the same chunk is now known good, at no cost',
      );
    });

    test('verifyChunks opens each chunk once and reports failures', () async {
      final bundle = _CountingBundle(<String, Uint8List>{
        'assets/chunk_root.dat': chunk,
      });
      final pack = AssetPack(
        mapping: const <String, String>{
          'assets/a.webp': 'assets/chunk_root.dat',
          'assets/b.ogg': 'assets/chunk_root.dat',
          'assets/c.webp': 'assets/chunk_missing.dat',
        },
        key: const <int>[],
        bundle: bundle,
      );
      final failures = await pack.verifyChunks();
      expect(failures.keys, ['assets/chunk_missing.dat']);
      expect(
        bundle.loads['assets/chunk_root.dat'],
        1,
        reason: 'one open per chunk, not per asset - two assets, one read',
      );
    });
  });

  group('the chunk format', () {
    test('reads a chunk goo_cli actually produced', () async {
      // The one test here that is not goo agreeing with itself.
      //
      // Everything else in this file is built by `plainChunk` above - goo's
      // own idea of the layout, uncompressed and unencrypted. goo_cli could
      // seal chunks in a shape this reader cannot open and both suites would
      // stay green, because neither has ever seen the other's bytes. The
      // failure would land in a release build, on the first asset load.
      //
      // So this opens a chunk goo_cli sealed, compressed *and* encrypted,
      // checked in at fixtures/asset_chunk/ and belonging to neither package.
      // See the README there before regenerating it.
      final golden = File('../../fixtures/asset_chunk/chunk_v1_aes_gzip.dat');
      expect(
        golden.existsSync(),
        isTrue,
        reason:
            'the golden chunk is checked in, not generated - see '
            'fixtures/asset_chunk/README.md',
      );
      final members = readChunkBody(
        await openChunk(
          sealed: Uint8List.fromList(golden.readAsBytesSync()),
          // Documented in the fixture's README. Not a secret, and not an
          // example to copy - a real one comes from asset_key.dart.
          key: List<int>.generate(32, (i) => i * 7 % 256),
        ),
      );
      expect(utf8.decode(members['assets/a.webp']!), 'texture bytes');
      expect(utf8.decode(members['assets/b.ogg']!), 'audio bytes');
    });

    test('a foreign file is refused by magic rather than decoded', () async {
      await expectLater(
        () => openChunk(
          sealed: Uint8List.fromList(List<int>.filled(64, 0)),
          key: const <int>[],
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a future version says so rather than reading nonsense', () async {
      final future = Uint8List.fromList(chunk)..[4] = chunkVersion + 1;
      await expectLater(
        () => openChunk(sealed: future, key: const <int>[]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('different versions of the tool'),
          ),
        ),
      );
    });

    test('a truncated chunk is refused, not read past its end', () async {
      await expectLater(
        () => openChunk(
          sealed: Uint8List.fromList(chunkMagic),
          key: const <int>[],
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a key of the wrong length is refused at construction', () {
      expect(
        () => AssetPack(
          mapping: const <String, String>{'a': 'chunk.dat'},
          key: const <int>[1, 2, 3],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('different key files'),
          ),
        ),
        reason:
            'every sealed chunk would fail its tag - better to say why at '
            'startup than once per asset later',
      );
    });

    test('an empty key is fine - that is an unencrypted pack', () {
      //  is a supported build, so requiring
      // a key here would refuse a pack the tool produces.
      expect(
        () => AssetPack(
          mapping: const <String, String>{'a': 'chunk.dat'},
          key: const <int>[],
        ),
        returnsNormally,
      );
    });
  });
}
