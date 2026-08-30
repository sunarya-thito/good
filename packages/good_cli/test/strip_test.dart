import 'dart:io';

import 'package:good_cli/src/assets/strip.dart';
import 'package:test/test.dart';

import '_temp.dart';

// What a release build is allowed to delete.
//
// This is the one step in the pipeline that removes files a person might have
// put there, so the tests below are mostly about what it must *not* touch. A
// bug here does not produce a wrong build - it produces missing artwork with no
// copy left anywhere.

Directory _assets(List<String> names) {
  final dir = testTempDir('good_strip');
  for (final name in names) {
    File('${dir.path}/$name')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('bytes');
  }
  return dir;
}

/// The logical paths a pack of [names] out of `assets/` would report.
List<String> _packed(List<String> names) => <String>[
  for (final name in names) 'assets/$name',
];

void main() {
  test('removes the loose copies of what was packed', () {
    final dir = _assets(['a.webp', 'b.webp']);
    expect(
      stripLoose(
        assetDir: dir,
        packed: _packed(['a.webp', 'b.webp']),
        assetRoot: 'assets/',
      ),
      2,
    );
    expect(dir.listSync(), isEmpty);
  });

  test('removes a hand-placed asset once a chunk carries it', () {
    // The defect this set exists for. `by_hand.webp` was never a compaction
    // output, so stripping the *compaction plan* left it behind - shipped
    // loose and legible beside the chunk holding the same bytes.
    final dir = _assets(['generated.webp', 'by_hand.webp']);
    expect(
      stripLoose(
        assetDir: dir,
        packed: _packed(['by_hand.webp', 'generated.webp']),
        assetRoot: 'assets/',
      ),
      2,
    );
    expect(
      File('${dir.path}/by_hand.webp').existsSync(),
      isFalse,
      reason: 'its bytes are in the chunk, so a loose copy is a second ship',
    );
  });

  test('leaves a file no chunk carries', () {
    // The important one. A file the pack did not take is the only copy of
    // itself, and there is nowhere to get it back from.
    final dir = _assets(['packed.webp', 'unpacked.webp']);
    expect(
      stripLoose(
        assetDir: dir,
        packed: _packed(['packed.webp']),
        assetRoot: 'assets/',
      ),
      1,
    );
    expect(File('${dir.path}/unpacked.webp').existsSync(), isTrue);
  });

  test('a build that packed nothing loses nothing', () {
    final dir = _assets(['a.webp', 'b.webp']);
    expect(
      stripLoose(assetDir: dir, packed: const <String>[], assetRoot: 'assets/'),
      0,
    );
    expect(dir.listSync(), hasLength(2));
  });

  test('a file already gone is not an error', () {
    // Re-running a build after one has already stripped.
    final dir = _assets(['a.webp']);
    expect(
      stripLoose(
        assetDir: dir,
        packed: _packed(['a.webp', 'b.webp']),
        assetRoot: 'assets/',
      ),
      1,
    );
  });

  test('a subdirectory asset is found under its own path', () {
    final dir = _assets(['ui/button.webp']);
    expect(
      stripLoose(
        assetDir: dir,
        packed: _packed(['ui/button.webp']),
        assetRoot: 'assets/',
      ),
      1,
    );
    expect(File('${dir.path}/ui/button.webp').existsSync(), isFalse);
  });

  test('the chunks survive, since nothing packed them', () {
    final dir = _assets(['a.webp', 'packed/chunk_shared.dat']);
    stripLoose(
      assetDir: dir,
      packed: _packed(['a.webp']),
      assetRoot: 'assets/',
    );
    expect(File('${dir.path}/packed/chunk_shared.dat').existsSync(), isTrue);
  });

  test('reports each removed path relative to the asset directory', () {
    final dir = _assets(['ui/button.webp']);
    final seen = <String>[];
    stripLoose(
      assetDir: dir,
      packed: _packed(['ui/button.webp']),
      assetRoot: 'assets/',
      onStrip: seen.add,
    );
    expect(seen, ['ui/button.webp']);
  });
}
