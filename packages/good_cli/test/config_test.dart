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
  flavors:
    paid: bundled
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

  group('good: flavors:', () {
    void refuses(String name, String pubspec, Matcher message) {
      test(name, () {
        expect(
          () => GoodConfig.read(_project(pubspec)),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              message,
            ),
          ),
        );
      });
    }

    test('is empty for a project that declares none', () {
      expect(GoodConfig.read(_project('name: demo')).flavors, isEmpty);
    });

    test('synthesizes dev and prod there, and only there', () {
      // A project that maps nothing has nothing to map, and two unflavoured
      // entries cannot be told apart - both ship. The synthesized pair is the
      // same rule applied to that case, not a second mechanism.
      final bare = GoodConfig.read(_project('name: demo'));
      expect(bare.rawFlavors, <String>['dev']);
      expect(bare.bundledFlavors, <String>['prod']);

      final named = GoodConfig.read(
        _project('''
name: demo
good:
  flavors:
    free: bundled
    paid: bundled
    workshop: raw
'''),
      );
      expect(named.rawFlavors, <String>['workshop']);
      expect(named.bundledFlavors, <String>['free', 'paid']);
    });

    refuses('a pipeline that is not one', '''
name: demo
good:
  flavors:
    development: loose
''', allOf(contains('loose'), contains('raw'), contains('bundled')));

    refuses('a name a pubspec entry could not carry', '''
name: demo
good:
  flavors:
    "dev build": raw
''', contains('is not a flavor name'));

    refuses('a map that is not one', '''
name: demo
good:
  flavors:
    - development
''', contains('not a map'));

    refuses(
      'an asset entry naming a flavor nothing maps',
      '''
name: demo
good:
  flavors:
    development: raw
    production: bundled
  assets:
    - path: assets/premium/
      flavors: [paid]
''',
      // A typo here is silent otherwise: the raw copy intersects to nothing
      // and ships nowhere, and the chunk ships anyway, so the asset exists in
      // one build and not the other for a reason nothing states.
      allOf(
        contains('assets/premium/'),
        contains('paid'),
        contains('development, production'),
      ),
    );

    refuses('an asset entry with flavors in a project that maps none', '''
name: demo
good:
  assets:
    - path: assets/premium/
      flavors: [paid]
''', contains('declares no flavors at all'));
  });
}
