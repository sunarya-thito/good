import 'dart:io';

import 'package:good_cli/src/assets/entry.dart';
import 'package:good_cli/src/config.dart';
import 'package:good_cli/src/generate/flutter_assets.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '_temp.dart';

// How dev-versus-release actually ships.
//
// The two copies of an asset - the original and the chunk made from it - hold
// the same bytes, and until they could be told apart both were handed to
// Flutter's bundler, so a packing build shipped every packed asset legible
// beside its own chunk (#270). `strip-originals` deleted the first copy
// afterwards and was off by default.
//
// Flavors replace that with an exclusion Flutter itself performs. Each entry
// good writes into `flutter: assets:` names the flavors that ship it, and
// `matchesFlavor` leaves a flavoured entry out of every build that did not ask
// for that flavor. So there is no moment at which both copies are in one
// bundle, and nothing has to delete anything.
//
// Two things are load-bearing and neither is obvious:
//
//   * an entry with **no** `flavors:` is shipped in every build, so an empty
//     set is not "none" - which is why an entry whose own flavors do not meet
//     the raw set has to be dropped rather than emitted unflavoured;
//   * `flutter: assets:` is the project's list, not good's, so a rewrite that
//     took anything else out of it would delete somebody's UI art.

GoodConfig _config(String pubspec) {
  final dir = testTempDir('good_flutter_assets');
  File('${dir.path}/pubspec.yaml').writeAsStringSync(pubspec);
  return GoodConfig.read(dir);
}

/// The `flutter: assets:` of [lines], as Flutter's own parser reads it.
List<Object?> _flutterAssets(List<String> lines) {
  final doc = loadYaml(lines.join('\n')) as YamlMap;
  final flutter = doc['flutter'] as YamlMap;
  return (flutter['assets'] as YamlList).toList();
}

void main() {
  group('goodFlutterAssets', () {
    test('synthesizes dev and prod for a project that maps no flavors', () {
      // The degenerate case of the same rule. A project with no flavors has
      // nothing to map, and two unflavoured entries both ship - which is the
      // double-ship, not a neutral default.
      final entries = goodFlutterAssets(
        _config('''
name: demo
good:
  assets:
    - assets/
'''),
      );
      expect(entries.map((e) => e.path), <String>['assets/', 'assets/packed/']);
      expect(entries[0].flavors, <String>{'dev'});
      expect(entries[1].flavors, <String>{'prod'});
    });

    test('writes the project flavor names, and invents none', () {
      final entries = goodFlutterAssets(
        _config('''
name: demo
good:
  flavors:
    development: raw
    staging: bundled
    production: bundled
  assets:
    - assets/game/
'''),
      );
      expect(entries.map((e) => e.path), <String>[
        'assets/game/',
        'assets/packed/',
      ]);
      expect(entries[0].flavors, <String>{'development'});
      expect(entries[1].flavors, <String>{'production', 'staging'});
    });

    test('intersects an entry flavors with the raw ones', () {
      final entries = goodFlutterAssets(
        _config('''
name: demo
good:
  flavors:
    demo: raw
    development: raw
    production: bundled
  assets:
    - path: assets/full/
      flavors: [development, production]
'''),
      );
      expect(entries.first.path, 'assets/full/');
      expect(
        entries.first.flavors,
        <String>{'development'},
        reason:
            'the raw copy ships in the raw flavors this entry names, and demo '
            'is a raw flavor this entry does not name',
      );
    });

    test('emits no raw entry when that intersection is empty', () {
      // The one that cannot be got wrong quietly. An empty `flavors:` ships in
      // every build, so emitting the entry with what the intersection produced
      // would ship an asset in every flavor - including the ones its own line
      // in the pubspec excludes.
      final entries = goodFlutterAssets(
        _config('''
name: demo
good:
  flavors:
    development: raw
    production: bundled
  assets:
    - path: assets/release_only/
      flavors: [production]
'''),
      );
      expect(entries.map((e) => e.path), <String>['assets/packed/']);
    });

    test('carries platforms and transformers onto the raw copy', () {
      final entries = goodFlutterAssets(
        _config('''
name: demo
good:
  flavors:
    development: raw
    production: bundled
  assets:
    - path: assets/vector/
      platforms: [android, ios]
      transformers:
        - package: vector_graphics_compiler
          args: [--tessellate]
'''),
      );
      expect(entries.first.platforms, <String>{'android', 'ios'});
      expect(
        entries.first.transformers.single.package,
        'vector_graphics_compiler',
      );
      expect(entries.first.transformers.single.args, <String>['--tessellate']);
    });

    test('does not emit the chunk directory twice', () {
      final entries = goodFlutterAssets(
        _config('''
name: demo
good:
  assets:
    - assets/
    - assets/packed/
'''),
      );
      expect(
        entries.where((e) => e.path == 'assets/packed/').length,
        1,
        reason:
            'the chunk directory is made from the sources rather than being '
            'one, and it ships under the bundled flavors either way',
      );
    });

    test('emits no chunk entry when every flavor ships raw', () {
      final entries = goodFlutterAssets(
        _config('''
name: demo
good:
  flavors:
    development: raw
  assets:
    - assets/
'''),
      );
      expect(entries.map((e) => e.path), <String>['assets/']);
    });
  });

  group('patchedFlutterAssetLines', () {
    const List<String> pubspec = <String>[
      'name: my_game',
      '',
      'flutter:',
      '  uses-material-design: true',
      '',
      '  # my own art, bundled by path',
      '  assets:',
      '    - assets/ui/',
      '    - assets/',
      '    - assets/packed/',
      '',
      'good:',
      '  assets:',
      '    - assets/',
    ];

    test('replaces the entries good owns, in place', () {
      final config = _config(pubspec.join('\n'));
      final patched = patchedFlutterAssetLines(pubspec, config)!;
      expect(_flutterAssets(patched), <Object?>[
        'assets/ui/',
        <String, Object?>{
          'path': 'assets/',
          'flavors': <String>['dev'],
        },
        <String, Object?>{
          'path': 'assets/packed/',
          'flavors': <String>['prod'],
        },
      ]);
    });

    test('leaves the entries that are not good\'s alone', () {
      // `flutter: assets:` is the project's list. A rewrite that took
      // `assets/ui/` out of it would delete the art `Image.asset` resolves.
      final config = _config(pubspec.join('\n'));
      final patched = patchedFlutterAssetLines(pubspec, config)!;
      expect(patched, contains('    - assets/ui/'));
      expect(patched, contains('  # my own art, bundled by path'));
    });

    test('is idempotent', () {
      final config = _config(pubspec.join('\n'));
      final once = patchedFlutterAssetLines(pubspec, config)!;
      expect(patchedFlutterAssetLines(once, config), once);
    });

    test('follows a changed flavor map on the next run', () {
      final once = patchedFlutterAssetLines(
        pubspec,
        _config(pubspec.join('\n')),
      )!;
      final renamed = _config('''
name: my_game
good:
  flavors:
    development: raw
    production: bundled
  assets:
    - assets/
''');
      final twice = patchedFlutterAssetLines(once, renamed)!;
      expect(_flutterAssets(twice), <Object?>[
        'assets/ui/',
        <String, Object?>{
          'path': 'assets/',
          'flavors': <String>['development'],
        },
        <String, Object?>{
          'path': 'assets/packed/',
          'flavors': <String>['production'],
        },
      ]);
    });

    test('appends when the list holds nothing of good\'s yet', () {
      const List<String> theirs = <String>[
        'name: my_game',
        'flutter:',
        '  assets:',
        '    - assets/ui/',
        'good:',
        '  assets:',
        '    - assets/',
      ];
      final patched = patchedFlutterAssetLines(
        theirs,
        _config(theirs.join('\n')),
      )!;
      expect(_flutterAssets(patched).first, 'assets/ui/');
      expect(_flutterAssets(patched).length, 3);
    });

    test('refuses a flow-style list rather than mangling it', () {
      // Two entries on one line, so there is no line to remove that belongs to
      // one of them. The caller prints the block to write by hand.
      const List<String> flow = <String>[
        'name: my_game',
        'flutter:',
        '  assets: [assets/, assets/packed/]',
        'good:',
        '  assets:',
        '    - assets/',
      ];
      expect(patchedFlutterAssetLines(flow, _config(flow.join('\n'))), isNull);
    });

    test('refuses a pubspec with no flutter: assets: at all', () {
      const List<String> bare = <String>['name: my_game', 'flutter:'];
      expect(
        patchedFlutterAssetLines(bare, _config('name: my_game\n')),
        isNull,
      );
    });
  });

  group('assetEntryLines', () {
    // The lines are read back by Flutter's own parser, so writing an entry and
    // parsing it has to be a round trip. An entry that wrote back as something
    // else would bundle something else.
    void roundTrips(String name, AssetEntry entry) {
      test(name, () {
        final lines = <String>[
          'flutter:',
          '  assets:',
          ...assetEntryLines(entry, '    '),
        ];
        final read = _flutterAssets(lines).single;
        expect(AssetEntry.parse(read, context: 'flutter: assets'), entry);
      });
    }

    roundTrips('a plain path', AssetEntry(uri: Uri.parse('assets/game/')));
    roundTrips(
      'flavors and platforms',
      AssetEntry(
        uri: Uri.parse('assets/premium/'),
        flavors: const <String>{'paid'},
        platforms: const <String>{'android', 'ios'},
      ),
    );
    roundTrips(
      'transformers with arguments',
      AssetEntry(
        uri: Uri.parse('assets/vector/'),
        flavors: const <String>{'dev'},
        transformers: const <AssetTransformer>[
          AssetTransformer(
            package: 'vector_graphics_compiler',
            args: <String>['--tessellate'],
          ),
        ],
      ),
    );
    roundTrips(
      'a path that needs quoting',
      AssetEntry(
        uri: Uri.parse('assets/my art: v2/'),
        flavors: const <String>{'dev'},
      ),
    );
  });
}
