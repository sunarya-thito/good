import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good/io.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/asset_pack.dart';

// The mount table: N ordered tiers where a later one shadows an earlier one,
// generalising the hard-coded "pack first, bundle second" that BundleSource
// used to spell inline.
//
// **Every test here that is about ordering asserts on content, not presence.**
// A logical path present in exactly one mount proves nothing - it resolved
// before there was a table, and it would resolve under any mount order at all.
// So each tier holds a *different* string at the same logical path, and a
// wrong tier is a wrong value rather than a missing file. #110 established the
// same discipline for textures, where two mounts of matching size would have
// made a swapped pair invisible.

/// A bundle that serves prepared text and reports a missing key the way
/// `PlatformAssetBundle` does - a `FlutterError`, which is what [BundleMount]
/// reads as "not mine".
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.entries);

  final Map<String, String> entries;

  @override
  Future<ByteData> load(String key) async {
    final value = entries[key];
    if (value == null) throw FlutterError('no asset bundled at $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}

/// A [DirectoryMount] that counts reads, so "opened once" is observable.
class _CountingDirectory extends DirectoryMount {
  _CountingDirectory(super.directory);

  int reads = 0;

  @override
  Future<Uint8List?> tryRead(String path) {
    reads++;
    return super.tryRead(path);
  }
}

/// A temp directory holding one file per entry, deleted at the end of the test.
Directory _dirOf(String name, Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('good_mount_$name');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final entry in files.entries) {
    final file = File('${dir.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  return dir;
}

/// One chunk in the shipped format, uncompressed and unencrypted - flags 0, so
/// the reader takes the plain path. The sealed layout itself is
/// `asset_pack_test.dart`'s subject; here it only has to be openable.
Uint8List _chunkOf(Map<String, String> members) {
  final names = members.keys.toList()..sort();
  final header = BytesBuilder();
  final payload = BytesBuilder();
  header.add(
    (ByteData(
      4,
    )..setUint32(0, names.length, Endian.little)).buffer.asUint8List(),
  );
  var offset = 0;
  for (final name in names) {
    final bytes = utf8.encode(members[name]!);
    final encoded = utf8.encode(name);
    header
      ..add(
        (ByteData(
          2,
        )..setUint16(0, encoded.length, Endian.little)).buffer.asUint8List(),
      )
      ..add(encoded)
      ..add(
        (ByteData(8)
              ..setUint32(0, offset, Endian.little)
              ..setUint32(4, bytes.length, Endian.little))
            .buffer
            .asUint8List(),
      );
    payload.add(bytes);
    offset += bytes.length;
  }
  return Uint8List.fromList(<int>[
    ...chunkMagic,
    chunkVersion,
    0, // neither compressed nor encrypted
    ...List<int>.filled(12, 0), // nonce
    ...List<int>.filled(16, 0), // tag
    ...header.takeBytes(),
    ...payload.takeBytes(),
  ]);
}

/// A temp directory holding one chunk file, deleted at the end of the test.
Directory _packDirOf(String name, Map<String, String> members) {
  final dir = Directory.systemTemp.createTempSync('good_chunks_$name');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/chunk_0.dat').writeAsBytesSync(_chunkOf(members));
  return dir;
}

AssetPack _packOf(AssetMount chunks) => AssetPack(
  mapping: const <String, String>{'assets/greeting.txt': 'chunk_0.dat'},
  key: const <int>[],
  chunkSource: chunks,
);

Future<String> _read(String path) async =>
    utf8.decode(await BundleSource(path).load());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(AssetMounts.clear);

  group('ordering', () {
    test(
      'the later mount answers and the earlier value survives under it',
      () async {
        // Both directories carry assets/greeting.txt with different bytes. A
        // bottom-up walk would read 'from below' and fail on the value rather
        // than on an absence.
        final below = _dirOf('below', {'assets/greeting.txt': 'from below'});
        final above = _dirOf('above', {'assets/greeting.txt': 'from above'});

        AssetMounts.mount(DirectoryMount(below.path));
        AssetMounts.mount(DirectoryMount(above.path));

        expect(await _read('assets/greeting.txt'), 'from above');
        expect(
          File('${below.path}/assets/greeting.txt').readAsStringSync(),
          'from below',
          reason: 'shadowing hides a value; it does not replace one',
        );
      },
    );

    test('reversing the mount order reverses the answer', () async {
      // The deliberate break, kept as a test: the same two mounts in the other
      // order give the other content. If mount order did not decide the
      // answer, both halves of this could not pass at once.
      final a = _dirOf('a', {'assets/greeting.txt': 'from A'});
      final b = _dirOf('b', {'assets/greeting.txt': 'from B'});

      AssetMounts.mount(DirectoryMount(a.path));
      AssetMounts.mount(DirectoryMount(b.path));
      expect(await _read('assets/greeting.txt'), 'from B');

      AssetMounts.clear();
      AssetMounts.mount(DirectoryMount(b.path));
      AssetMounts.mount(DirectoryMount(a.path));
      expect(await _read('assets/greeting.txt'), 'from A');
    });

    test(
      'a mount that does not carry the path is skipped, not an error',
      () async {
        final base = _dirOf('base', {'assets/greeting.txt': 'from base'});
        final dlc = _dirOf('dlc', {'assets/extra.txt': 'dlc only'});

        AssetMounts.mount(DirectoryMount(base.path));
        AssetMounts.mount(DirectoryMount(dlc.path));

        // The top mount has no greeting, so the walk continues rather than
        // reporting the asset missing.
        expect(await _read('assets/greeting.txt'), 'from base');
        expect(await _read('assets/extra.txt'), 'dlc only');
      },
    );

    test('unmount puts the shadowed value back', () async {
      final base = _dirOf('base', {'assets/greeting.txt': 'shipped'});
      final patch = _dirOf('patch', {'assets/greeting.txt': 'patched'});
      final patchMount = DirectoryMount(patch.path);

      AssetMounts.mount(DirectoryMount(base.path));
      AssetMounts.mount(patchMount);
      expect(await _read('assets/greeting.txt'), 'patched');

      expect(AssetMounts.unmount(patchMount), isTrue);
      expect(await _read('assets/greeting.txt'), 'shipped');
      expect(
        AssetMounts.unmount(patchMount),
        isFalse,
        reason:
            'unmounting what is not mounted is not a failure, but it is '
            'not a removal either',
      );
    });
  });

  group('the bundle floor', () {
    test('a mounted directory shadows what shipped in the app', () async {
      // The dev-time reload case, and the one shape the two-tier lookup could
      // not express: the source tree on top of the shipped copy, same logical
      // path, different bytes.
      final source = _dirOf('src', {'assets/greeting.txt': 'edited on disk'});
      final bundle = _FakeBundle({'assets/greeting.txt': 'shipped in the app'});
      final asset = BundleSource('assets/greeting.txt', bundle: bundle);

      expect(
        utf8.decode(await asset.load()),
        'shipped in the app',
        reason: 'nothing mounted, so the floor answers',
      );

      AssetMounts.mount(DirectoryMount(source.path));
      expect(utf8.decode(await asset.load()), 'edited on disk');
    });

    test('an asset nothing carries fails as the bundle\'s own error', () async {
      // The floor cannot be unmounted, so a genuinely absent asset reports
      // what it reported before there was a table - which is what
      // `throwsFlutterError` in goo2d's texture suite is asserting.
      AssetMounts.mount(DirectoryMount(_dirOf('empty', {}).path));
      await expectLater(
        BundleSource('assets/absent.txt', bundle: _FakeBundle({})).load(),
        throwsFlutterError,
      );
    });
  });

  group('a pack is a mount like any other', () {
    test(
      'a patch pack mounted above the shipped one wins on content',
      () async {
        // Two packs naming the same logical path, each reading its chunks from
        // its own tier. Nothing about the path or the key changes between them.
        final base = _packOf(
          DirectoryMount(
            _packDirOf('ship', {'assets/greeting.txt': 'version one'}).path,
          ),
        );
        final patch = _packOf(
          DirectoryMount(
            _packDirOf('patch', {'assets/greeting.txt': 'version two'}).path,
          ),
        );

        AssetMounts.mount(base);
        AssetMounts.mount(patch);
        expect(await _read('assets/greeting.txt'), 'version two');

        AssetMounts.clear();
        AssetMounts.mount(patch);
        AssetMounts.mount(base);
        expect(await _read('assets/greeting.txt'), 'version one');
      },
    );

    test('a loose file mounted above a pack shadows the packed copy', () async {
      final packed = _packDirOf('only', {'assets/greeting.txt': 'packed'});
      final loose = _dirOf('loose', {'assets/greeting.txt': 'loose'});

      AssetMounts.mount(_packOf(DirectoryMount(packed.path)));
      AssetMounts.mount(DirectoryMount(loose.path));

      expect(await _read('assets/greeting.txt'), 'loose');
    });

    test('a pack reads its chunks out of a bundle when told to', () async {
      // The shipped arrangement, and the reason `chunks` is a mount rather
      // than a directory: on Android there is no filesystem path to a chunk.
      final bundle = _FakeBundle({});
      final pack = _packOf(BundleMount(bundle: bundle));
      expect(pack.chunkSource, isA<BundleMount>());
      await expectLater(
        pack.read('assets/greeting.txt'),
        throwsA(isA<StateError>()),
        reason:
            'the fake bundle carries no chunk, so this is the missing-'
            'chunk path rather than a silent fall-through',
      );
    });

    test(
      'a manifest naming a chunk its source does not carry says so',
      () async {
        // Not a fall-through: the pack claims this path, so serving whatever a
        // tier below happens to hold would hide a broken install.
        final empty = Directory.systemTemp.createTempSync('good_chunks_none');
        addTearDown(() => empty.deleteSync(recursive: true));
        AssetMounts.mount(_packOf(DirectoryMount(empty.path)));
        await expectLater(
          const BundleSource('assets/greeting.txt').load(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('does not carry it'),
            ),
          ),
        );
      },
    );
  });

  group('check', () {
    test('a directory mount reports a file it has as present', () async {
      AssetMounts.mount(
        DirectoryMount(_dirOf('present', {'assets/greeting.txt': 'here'}).path),
      );
      expect(
        await const BundleSource('assets/greeting.txt').check(),
        AssetAvailability.present,
      );
    });

    test('a zero-byte file is missing, not present', () async {
      // The partial-install case, and the one thing a stat can actually catch:
      // the entry is there and the bytes are not.
      AssetMounts.mount(
        DirectoryMount(_dirOf('blank', {'assets/greeting.txt': ''}).path),
      );
      expect(
        await const BundleSource('assets/greeting.txt').check(),
        AssetAvailability.missing,
      );
    });

    test('an unlisted pack entry is still reported under a mount that has '
        'never heard of it either', () async {
      // `unknown` is the finding a readiness check exists for - stale codegen
      // naming an asset the packer never saw. A mount above that simply does
      // not carry the path must not bury it.
      AssetMounts.mount(_packOf(const BundleMount()));
      AssetMounts.mount(
        DirectoryMount(_dirOf('other', {'assets/other.txt': 'x'}).path),
      );
      expect(
        await const BundleSource('assets/never.txt').check(),
        AssetAvailability.unknown,
      );
    });

    test(
      'a file above an unlisted pack entry answers instead of the finding',
      () async {
        // The other half of the same rule: `unknown` is remembered, not
        // returned, so a tier that really does carry the asset still wins.
        AssetMounts.mount(_packOf(const BundleMount()));
        AssetMounts.mount(
          DirectoryMount(
            _dirOf('dlc', {'assets/never.txt': 'shipped as DLC'}).path,
          ),
        );
        expect(
          await const BundleSource('assets/never.txt').check(),
          AssetAvailability.present,
        );
        expect(await _read('assets/never.txt'), 'shipped as DLC');
      },
    );

    test('an empty table cannot check a bundle entry', () async {
      expect(
        await const BundleSource('assets/greeting.txt').check(),
        AssetAvailability.unverifiable,
        reason: 'the floor exposes only load, and loading is reading',
      );
    });
  });

  group('release', () {
    test('the scene-boundary call reaches every mounted pack', () async {
      final counting = _CountingDirectory(
        _packDirOf('release', {'assets/greeting.txt': 'packed'}).path,
      );
      AssetMounts.mount(_packOf(counting));

      await _read('assets/greeting.txt');
      await _read('assets/greeting.txt');
      expect(counting.reads, 1, reason: 'the chunk stays open between reads');

      AssetMounts.release();
      await _read('assets/greeting.txt');
      expect(
        counting.reads,
        2,
        reason:
            'a pack that is mounted rather than installed must still be '
            'told the burst is over, or it holds its chunks for the life of '
            'the process',
      );
    });
  });
}
