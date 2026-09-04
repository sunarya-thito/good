import 'dart:io';

import 'package:good_cli/src/config.dart';
import 'package:test/test.dart';

import '_temp.dart';

// The `good:` section of a project's pubspec.
//
// `good: assets:` is the list of files good owns, separate from
// `flutter: assets:`, and reading one for the other is what shipped a packed
// asset in plaintext beside its own chunk. So the two must not be confused
// here, and a project that declares neither must still build.

Directory _project(String pubspec) {
  final dir = testTempDir('good_config');
  File('${dir.path}/pubspec.yaml').writeAsStringSync(pubspec);
  return dir;
}

void main() {
  group('the asset directories', () {
    test('fall back for a project with no good: section', () {
      final config = GoodConfig.read(_project('name: demo\n'));
      expect(config.assetSource, 'assets_src/');
      expect(config.assetOutput, 'assets/');
      expect(config.packOutput, 'assets/packed/');
    });

    test('are keys of good:, beside the list rather than inside it', () {
      final dir = _project('''
name: demo
good:
  asset-source: art/
  asset-output: canonical/
  pack-output: chunks/
''');
      final config = GoodConfig.read(dir);
      expect(config.assetSource, 'art/');
      expect(config.assetOutput, 'canonical/');
      expect(config.packOutput, 'chunks/');
    });

    test('gain the trailing slash a person leaves off', () {
      final dir = _project('''
name: demo
good:
  asset-source: art
''');
      expect(GoodConfig.read(dir).assetSource, 'art/');
    });
  });

  group('good: assets:', () {
    test('is empty for a project that declares none', () {
      expect(GoodConfig.read(_project('name: demo\n')).assets, isEmpty);
      final dir = _project('''
name: demo
good:
  bundle: demo_bundle
''');
      expect(GoodConfig.read(dir).assets, isEmpty);
    });

    test('is not read from flutter: assets:', () {
      // The whole point of the split. A file Flutter bundles is not thereby a
      // file good packs, and reading Flutter's list here is what put the
      // plaintext next to the chunk.
      final dir = _project('''
name: demo
flutter:
  assets:
    - assets/ui/
''');
      expect(GoodConfig.read(dir).assets, isEmpty);
    });

    test('reads the paths in order', () {
      final dir = _project('''
name: demo
good:
  assets:
    - assets/game/
    - assets/logo.png
''');
      expect(GoodConfig.read(dir).assets.map((e) => e.path), <String>[
        'assets/game/',
        'assets/logo.png',
      ]);
    });

    test('reads the map form with every key on it', () {
      final dir = _project('''
name: demo
good:
  assets:
    - path: assets/premium/
      platforms: [android, ios]
      flavors: [paid]
      transformers:
        - package: vector_graphics_compiler
          args: [--tessellate]
''');
      final entry = GoodConfig.read(dir).assets.single;
      expect(entry.path, 'assets/premium/');
      expect(entry.platforms, <String>{'android', 'ios'});
      expect(entry.flavors, <String>{'paid'});
      expect(entry.transformers.single.package, 'vector_graphics_compiler');
      expect(entry.transformers.single.args, <String>['--tessellate']);
    });

    test('refuses a key nobody can act on, naming it', () {
      final dir = _project('''
name: demo
good:
  assets:
    - path: assets/
      flavour: paid
''');
      expect(
        () => GoodConfig.read(dir),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            allOf(contains('good: assets'), contains('flavour')),
          ),
        ),
      );
    });

    test('refuses a value that is not a list at all', () {
      // Read leniently this is a project that meant to declare assets and
      // ships none of them, with nothing said.
      final dir = _project('''
name: demo
good:
  assets: assets/
''');
      expect(
        () => GoodConfig.read(dir),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('not a list'),
          ),
        ),
      );
    });
  });
}
