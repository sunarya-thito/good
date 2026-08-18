import 'dart:io';

import 'package:good_cli/src/assets/compact.dart';
import 'package:good_cli/src/assets/strip.dart';
import 'package:good_cli/src/generate/assets.dart';
import 'package:test/test.dart';

// What a release build is allowed to delete.
//
// This is the one step in the pipeline that removes files a person might have
// put there, so the tests below are mostly about what it must *not* touch. A
// bug here does not produce a wrong build - it produces missing artwork with no
// copy left anywhere.

Directory _assets(List<String> names) {
  final dir = Directory.systemTemp.createTempSync('good_strip');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  for (final name in names) {
    File('${dir.path}/$name')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('bytes');
  }
  return dir;
}

CompactPlan _plan(List<String> outputs) => CompactPlan(
  steps: <CompactStep>[
    for (final output in outputs)
      CompactStep(
        source: output,
        output: output,
        kind: AssetKind.texture,
        copyOnly: true,
      ),
  ],
  skipped: const <String, String>{},
);

void main() {
  test('removes the loose copies of what was compacted', () {
    final dir = _assets(['a.webp', 'b.webp']);
    expect(
      stripLoose(assetDir: dir, compacted: _plan(['a.webp', 'b.webp'])),
      2,
    );
    expect(dir.listSync(), isEmpty);
  });

  test('leaves a file compaction did not produce', () {
    // The important one. A file in the asset directory that no source built is
    // an original, and there is nowhere to get it back from.
    final dir = _assets(['generated.webp', 'by_hand.webp']);
    expect(stripLoose(assetDir: dir, compacted: _plan(['generated.webp'])), 1);
    expect(File('${dir.path}/by_hand.webp').existsSync(), isTrue);
  });

  test('a project with no source directory loses nothing', () {
    // Its empty plan is what makes this safe: every file in the asset
    // directory is an original, and none of them is named by any step.
    final dir = _assets(['a.webp', 'b.webp']);
    expect(
      stripLoose(
        assetDir: dir,
        compacted: const CompactPlan(
          steps: <CompactStep>[],
          skipped: <String, String>{},
        ),
      ),
      0,
    );
    expect(dir.listSync(), hasLength(2));
  });

  test('an output already gone is not an error', () {
    // Re-running a build after one has already stripped.
    final dir = _assets(['a.webp']);
    expect(
      stripLoose(assetDir: dir, compacted: _plan(['a.webp', 'b.webp'])),
      1,
    );
  });

  test('the packed directory survives, since it is not an output', () {
    final dir = _assets(['a.webp', 'packed/chunk_shared.dat']);
    stripLoose(assetDir: dir, compacted: _plan(['a.webp']));
    expect(File('${dir.path}/packed/chunk_shared.dat').existsSync(), isTrue);
  });
}
