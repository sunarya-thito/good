import 'dart:io';

import 'package:good_cli/src/config.dart';
import 'package:test/test.dart';

import '_temp.dart';

// The `good:` section of a project's pubspec.
//
// `strip-originals` decides whether a release build may delete an asset
// compaction cannot rebuild, so a key that silently reads as the wrong thing
// is the difference between a refused build and destroyed art.

Directory _project(String pubspec) {
  final dir = testTempDir('good_config');
  File('${dir.path}/pubspec.yaml').writeAsStringSync(pubspec);
  return dir;
}

void main() {
  group('strip-originals', () {
    test('is off for a project with no good: section', () {
      expect(GoodConfig.read(_project('name: demo\n')).stripOriginals, isFalse);
    });

    test('is off when the assets: block does not mention it', () {
      final dir = _project('''
name: demo
good:
  assets:
    source: art/
''');
      final config = GoodConfig.read(dir);
      expect(config.stripOriginals, isFalse);
      expect(config.assetSource, 'art/', reason: 'the block still parsed');
    });

    test('is on when the project asks for it', () {
      final dir = _project('''
name: demo
good:
  assets:
    strip-originals: true
''');
      expect(GoodConfig.read(dir).stripOriginals, isTrue);
    });

    test('is off when the project says so outright', () {
      final dir = _project('''
name: demo
good:
  assets:
    strip-originals: false
''');
      expect(GoodConfig.read(dir).stripOriginals, isFalse);
    });

    test('falls back for a value that is not a boolean', () {
      // The safe reading of a key nobody can interpret is the safe behaviour,
      // not the destructive one.
      final dir = _project('''
name: demo
good:
  assets:
    strip-originals: whenever
''');
      expect(GoodConfig.read(dir).stripOriginals, isFalse);
    });
  });
}
