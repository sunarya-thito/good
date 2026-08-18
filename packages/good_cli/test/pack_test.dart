import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:good_cli/src/assets/key_material.dart';
import 'package:good_cli/src/assets/options.dart';
import 'package:good_cli/src/assets/pack.dart';
import 'package:good_cli/src/verbosable.dart';
import 'package:test/test.dart';

// Packing: how assets are grouped, what a chunk looks like on disk, and that
// what comes out of a chunk is exactly what went in.
//
// The round-trip is the load-bearing part. A packer with no reader produces
// files nobody can prove are correct, so `openChunk` lives beside `sealChunk`
// and every property below is asserted through both.

final VerboseOutput _quiet = _Null();

class _Null implements VerboseOutput {
  @override
  void println(Object? object) {}
  @override
  void print(Object? object) {}
  @override
  void printf(String format, List<Object?> args) {}
}

final List<int> _key = List<int>.generate(32, (i) => i * 7 % 256);

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('good_pack');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

Directory _assetTree() {
  final dir = _tempDir();
  File('${dir.path}/a.webp').writeAsStringSync('texture bytes');
  File('${dir.path}/ui/b.ogg')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('audio bytes');
  return dir;
}

const String _keySource = '''
final List<int> _assetKey = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08];
final List<int> _assetKey2 = [0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18];
final List<int> _assetKey3 = [0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28];
final List<int> _assetKey4 = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38];

final Map<String, String> assetMapping = <String, String>{};
''';

File _keyFile() {
  final file = File('${_tempDir().path}/asset_key.dart');
  file.writeAsStringSync(_keySource);
  return file;
}

void main() {
  group('planPack', () {
    test('groups by top-level directory under the asset root', () {
      final plan = planPack([
        'assets/dot.webp',
        'assets/ui/button.webp',
        'assets/ui/panel.webp',
        'assets/sfx/hit.ogg',
      ], assetRoot: 'assets/');
      expect(plan.chunks.map((c) => c.name), [
        'chunk_root.dat',
        'chunk_sfx.dat',
        'chunk_ui.dat',
      ]);
      expect(plan.chunks[2].members, [
        'assets/ui/button.webp',
        'assets/ui/panel.webp',
      ]);
    });

    test('says out loud that the grouping is a stand-in', () {
      final plan = planPack(['assets/a.webp'], assetRoot: 'assets/');
      expect(
        plan.grouping,
        contains('stand-in'),
        reason:
            'the design calls for scene-aware chunks; claiming this is that '
            'would be the report lying about what the build did',
      );
    });

    test('every asset lands in exactly one chunk', () {
      final paths = ['assets/a.webp', 'assets/ui/b.webp', 'assets/ui/c.ogg'];
      final plan = planPack(paths, assetRoot: 'assets/');
      expect(plan.assetCount, paths.length);
      expect(plan.chunks.expand((c) => c.members).toSet(), paths.toSet());
    });
  });

  group('chunk body', () {
    test('round-trips every member, bytes intact', () {
      final members = <String, Uint8List>{
        'assets/a.webp': _bytes('first asset'),
        'assets/ui/b.ogg': _bytes('second, longer asset payload'),
      };
      final read = readChunkBody(buildChunkBody(members));
      expect(read.keys.toSet(), members.keys.toSet());
      for (final name in members.keys) {
        expect(read[name], members[name], reason: name);
      }
    });

    test('an empty member is preserved, not dropped', () {
      // A zero-length asset is legal, and its absence would be a silent hole.
      final read = readChunkBody(buildChunkBody({'e': Uint8List(0)}));
      expect(read.containsKey('e'), isTrue);
      expect(read['e'], isEmpty);
    });
  });

  group('sealChunk', () {
    test('seals and opens back to the same bytes', () async {
      final body = buildChunkBody({'a': _bytes('hello packed world')});
      final sealed = await sealChunk(
        body: body,
        key: _key,
        compression: AssetCompressionLevel.normal,
      );
      expect(await openChunk(sealed: sealed, key: _key), body);
    });

    test('compresses before encrypting - the only useful order', () async {
      // Highly compressible input. Encrypted bytes are indistinguishable from
      // random and do not compress, so if the order were reversed the sealed
      // chunk could not be smaller than the plaintext.
      final body = Uint8List.fromList(List<int>.filled(20000, 0x41));
      final sealed = await sealChunk(
        body: body,
        key: _key,
        compression: AssetCompressionLevel.best,
      );
      expect(
        sealed.length,
        lessThan(body.length ~/ 10),
        reason:
            'encrypt-then-compress produces a larger file and the same '
            'security - pure loss, so the order has to be observable',
      );
      expect(await openChunk(sealed: sealed, key: _key), body);
    });

    test('the nonce is derived from content, so two chunks differ', () async {
      final one = await sealChunk(
        body: buildChunkBody({'a': _bytes('one')}),
        key: _key,
        compression: AssetCompressionLevel.normal,
      );
      final two = await sealChunk(
        body: buildChunkBody({'a': _bytes('two')}),
        key: _key,
        compression: AssetCompressionLevel.normal,
      );
      expect(
        one.sublist(6, 18),
        isNot(two.sublist(6, 18)),
        reason:
            "a repeated (key, nonce) pair is GCM's one unforgivable "
            'failure',
      );
    });

    test(
      'identical content seals identically, so a pack is reproducible',
      () async {
        final body = buildChunkBody({'a': _bytes('same')});
        final one = await sealChunk(
          body: body,
          key: _key,
          compression: AssetCompressionLevel.normal,
        );
        final two = await sealChunk(
          body: body,
          key: _key,
          compression: AssetCompressionLevel.normal,
        );
        expect(one, two);
      },
    );

    test(
      'a tampered chunk fails to open rather than yielding garbage',
      () async {
        final sealed = await sealChunk(
          body: buildChunkBody({'a': _bytes('authentic')}),
          key: _key,
          compression: AssetCompressionLevel.normal,
        );
        sealed[sealed.length - 1] ^= 0xFF;
        await expectLater(
          () => openChunk(sealed: sealed, key: _key),
          throwsA(anything),
          reason:
              'GCM authenticates - which is why a startup readiness check does '
              'not need to hash anything to catch a corrupt install',
        );
      },
    );

    test('the wrong key fails to open', () async {
      final sealed = await sealChunk(
        body: buildChunkBody({'a': _bytes('secret')}),
        key: _key,
        compression: AssetCompressionLevel.normal,
      );
      await expectLater(
        () => openChunk(sealed: sealed, key: List<int>.filled(32, 9)),
        throwsA(anything),
      );
    });

    test('a foreign file is refused by magic, not decrypted', () async {
      await expectLater(
        () => openChunk(
          sealed: Uint8List.fromList(List<int>.filled(64, 0)),
          key: _key,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('packAssets', () {
    Future<PackResult> pack({
      required Directory assets,
      required Directory output,
      required AssetMode mode,
      AssetEncryption encryption = AssetEncryption.aes,
    }) => packAssets(
      plan: planPack([
        'assets/a.webp',
        'assets/ui/b.ogg',
      ], assetRoot: 'assets/'),
      assetDir: assets,
      outputDir: output,
      mode: mode,
      encryption: encryption,
      compression: AssetCompressionLevel.normal,
      key: _key,
      assetRoot: 'assets/',

      chunkRoot: 'assets/packed/',
      out: _quiet,
      verbose: _quiet,
    );

    test('development mode is a genuine passthrough', () async {
      final output = _tempDir();
      final result = await pack(
        assets: _assetTree(),
        output: output,
        mode: AssetMode.development,
      );
      expect(
        result.mapping,
        isEmpty,
        reason:
            'an empty mapping is what makes BundleSource resolve straight '
            'through rootBundle',
      );
      expect(
        output.listSync(),
        isEmpty,
        reason: 'development must not write chunks at all',
      );
    });

    test('release writes one chunk per group and maps every asset', () async {
      final output = _tempDir();
      final result = await pack(
        assets: _assetTree(),
        output: output,
        mode: AssetMode.release,
      );
      expect(
        result.mapping,
        {
          'assets/a.webp': 'assets/packed/chunk_root.dat',
          'assets/ui/b.ogg': 'assets/packed/chunk_ui.dat',
        },
        reason:
            'the mapping is a bundle path the runtime looks up at load, so it '
            'has to name where the chunks *ship* - not the directory the '
            'assets came from',
      );
      expect(output.listSync().map((e) => e.uri.pathSegments.last).toSet(), {
        'chunk_root.dat',
        'chunk_ui.dat',
      });
    });

    test('a packed asset opens back to its original bytes', () async {
      final output = _tempDir();
      await pack(assets: _assetTree(), output: output, mode: AssetMode.release);
      final sealed = File('${output.path}/chunk_ui.dat').readAsBytesSync();
      final body = await openChunk(sealed: sealed, key: _key);
      expect(readChunkBody(body)['assets/ui/b.ogg'], _bytes('audio bytes'));
    });

    test('encryption=none still packs, and opens without a key', () async {
      final output = _tempDir();
      await pack(
        assets: _assetTree(),
        output: output,
        mode: AssetMode.release,
        encryption: AssetEncryption.none,
      );
      final sealed = File('${output.path}/chunk_root.dat').readAsBytesSync();
      final body = await openChunk(sealed: sealed, key: const <int>[]);
      expect(readChunkBody(body)['assets/a.webp'], _bytes('texture bytes'));
    });

    test('a missing asset is refused by name', () async {
      await expectLater(
        () => pack(
          assets: _tempDir(),
          output: _tempDir(),
          mode: AssetMode.release,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('good assets compact'),
          ),
        ),
      );
    });

    test('a short key is refused before anything is written', () async {
      await expectLater(
        () => packAssets(
          plan: planPack(['assets/a.webp'], assetRoot: 'assets/'),
          assetDir: _assetTree(),
          outputDir: _tempDir(),
          mode: AssetMode.release,
          encryption: AssetEncryption.aes,
          compression: AssetCompressionLevel.normal,
          key: const <int>[1, 2, 3],
          assetRoot: 'assets/',

          chunkRoot: 'assets/packed/',
          out: _quiet,
          verbose: _quiet,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('32-byte key'),
          ),
        ),
      );
    });
  });

  group('asset_key.dart', () {
    test('reads 32 bytes across the four parts', () {
      final key = readKeyMaterial(_keyFile());
      expect(key, hasLength(32));
      expect(key.first, 0x01);
      expect(key.last, 0x38);
    });

    test('a missing file says to run generate', () {
      expect(
        () => readKeyMaterial(File('${_tempDir().path}/absent.dart')),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('good generate'),
          ),
        ),
      );
    });

    test('writing the mapping leaves the keys untouched', () {
      final file = _keyFile();
      final before = readKeyMaterial(file);
      expect(
        writeAssetMapping(file, {'assets/a.webp': 'assets/chunk_root.dat'}),
        isTrue,
      );
      expect(
        readKeyMaterial(file),
        before,
        reason:
            'rotating the keys as a side effect of building would orphan '
            'every pack already shipped',
      );
      expect(file.readAsStringSync(), contains("'assets/a.webp'"));
    });

    test('an empty mapping clears a stale one', () {
      final file = _keyFile();
      writeAssetMapping(file, {'assets/a.webp': 'assets/chunk_root.dat'});
      writeAssetMapping(file, <String, String>{});
      expect(
        file.readAsStringSync(),
        contains('assetMapping = <String, String>{};'),
        reason:
            'switching back to development has to clear the mapping, or the '
            'runtime keeps looking for chunks that are no longer built',
      );
    });

    test('the mapping round-trips through a real file', () {
      final file = _keyFile();
      const mapping = {
        'assets/a.webp': 'assets/chunk_root.dat',
        'assets/ui/b.ogg': 'assets/chunk_ui.dat',
      };
      writeAssetMapping(file, mapping);
      final source = file.readAsStringSync();
      for (final entry in mapping.entries) {
        expect(source, contains("'${entry.key}': '${entry.value}',"));
      }
    });
  });
}
