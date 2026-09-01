import 'dart:convert';
import 'dart:io';

import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/scaffold.dart';
import 'package:good_cli/src/generate/templates.dart';
import 'package:test/test.dart';

import '_temp.dart';

// Whether a scaffolded project compiles - asked of the analyzer, not of the
// template text.
//
// Every other test over these templates asserts on the strings `scaffoldFiles`
// returns, and that is exactly how `good create --3d` came to scaffold a
// project that did not compile: `Camera3DDescriptor` was deleted from goo3d,
// the `Eye` template went on overriding `describeCamera`, and a green suite had
// nothing to say about it because no test there had ever resolved a goo3d name.
// A string assertion can only catch the mistakes somebody already thought of;
// this checks the templates against the API as it is today.
//
// It runs neither `flutter create` nor `pub get`. The generated files import
// `package:flutter`, `package:flutter_test` and the engine package, all of
// which this repository has already resolved under `packages/`, so the
// scaffolded project is handed the engine's own package config with its
// relative entries made absolute and itself added. `dart analyze` then resolves
// the real API out of the real source tree. Fifteen seconds per project,
// against minutes for a real `flutter create` plus `flutter pub get`.

/// The repository root, found by walking up from wherever the suite was run.
Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}/mkdocs.yml').existsSync() &&
        Directory('${dir.path}/packages').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('run this suite from inside the repository');
}

/// `packages/<engine>`'s resolved package config, with every path absolute.
///
/// A relative `rootUri` is relative to the `.dart_tool` directory holding the
/// file, so it means nothing once the config is written somewhere else.
/// Resolving them here is what lets the scaffolded project sit in a temp
/// directory and still see this repository's packages.
Map<String, Object?> _absolutePackageConfig(Directory root, String engine) {
  final file = File(
    '${root.path}/packages/$engine/.dart_tool/package_config.json',
  );
  if (!file.existsSync()) {
    fail(
      'packages/$engine is not resolved - run `flutter pub get` there. This '
      'test borrows its package config rather than resolving one of its own.',
    );
  }
  final base = file.parent.uri;
  final config = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return <String, Object?>{
    ...config,
    'packages': <Object?>[
      for (final entry in config['packages']! as List<Object?>)
        <String, Object?>{
          ...entry as Map<String, Object?>,
          'rootUri': base.resolve(entry['rootUri']! as String).toString(),
        },
    ],
  };
}

void main() {
  for (final engine in GoodEngine.values) {
    test('a scaffolded ${engine.package} project analyzes clean', () async {
      const projectName = 'scaffold_probe';
      final root = _repoRoot();
      final dir = testTempDir('good_scaffold_analyze');

      final files = scaffoldFiles(
        projectName: projectName,
        engine: engine,
        command: 'good create',
      );
      for (final entry in files.entries) {
        File('${dir.path}/${entry.key}')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(entry.value);
      }

      // `flutter create` writes the pubspec and `patchedPubspecLines` covers
      // what good adds to it. Only the two things the analyzer reads are
      // needed here: the package's name and its language version.
      File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: $projectName

environment:
  sdk: ^3.13.0
''');

      final config = _absolutePackageConfig(root, engine.package);
      File('${dir.path}/.dart_tool/package_config.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode(<String, Object?>{
            ...config,
            'packages': <Object?>[
              ...config['packages']! as List<Object?>,
              // test/widget_test.dart imports the project by package name, the
              // way `flutter create`'s own does.
              <String, Object?>{
                'name': projectName,
                'rootUri': dir.uri.toString(),
                'packageUri': 'lib/',
                'languageVersion': '3.13',
              },
            ],
          }),
        );

      // The VM running this suite, so nothing here depends on `dart` being on
      // PATH.
      final result = await Process.run(
        Platform.resolvedExecutable,
        <String>['analyze', dir.path],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      expect(
        result.exitCode,
        0,
        reason:
            'a project `good create` writes has to compile before its author '
            'has touched it:\n${result.stdout}${result.stderr}',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  test('a generated textures.dart with assets in it analyzes clean', () async {
    // Every other test over `emitTextures` reads its output as a string, and a
    // string assertion only catches what somebody thought to assert. This is
    // the one that would notice `TextureSize` colliding with a name goo2d
    // exports, or an enum whose constructor no longer matches its fields.
    final root = _repoRoot();
    final dir = testTempDir('good_generated_analyze');
    File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: generated_probe

environment:
  sdk: ^3.13.0

flutter:
  assets:
    - assets/
''');
    // A 24-byte PNG: signature and IHDR, which is all a header read needs.
    final png = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
      0, 0, 2, 0, // 512
      0, 0, 1, 0, // 256
    ];
    File('${dir.path}/assets/sheet.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(png);
    File('${dir.path}/assets/theme.ogg').writeAsBytesSync(<int>[0]);

    final scan = scanAssets(dir);
    final lib = Directory('${dir.path}/lib')..createSync(recursive: true);
    File('${lib.path}/textures.dart').writeAsStringSync(
      emitTextures(
        scan,
        command: 'good generate',
        package: 'goo2d',
        drawsTextures: true,
      ),
    );
    File('${lib.path}/audios.dart').writeAsStringSync(
      emitAudios(scan, command: 'good generate', package: 'goo2d'),
    );
    // The constants where the guide puts them: inside a const expression, in a
    // file that names goo2d's own API. `TextureSize.sheetWidth` compiles here
    // and `Textures.sheet.width` would not.
    File('${lib.path}/use.dart').writeAsStringSync('''
import 'package:goo2d/goo2d.dart';

import 'textures.dart';

const List<SpriteFrame> frames = <SpriteFrame>[
  SpriteFrame.pixels(
    x: 0,
    y: 0,
    width: 32,
    height: 32,
    sheetWidth: TextureSize.sheetWidth,
    sheetHeight: TextureSize.sheetHeight,
  ),
];

const NineSliceBorder border = NineSliceBorder.pixels(
  left: 4,
  sourceWidth: TextureSize.sheetWidth,
  sourceHeight: TextureSize.sheetHeight,
);

int get pixels => Textures.sheet.width * Textures.sheet.height;
''');

    final config = _absolutePackageConfig(root, 'goo2d');
    File('${dir.path}/.dart_tool/package_config.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          ...config,
          'packages': <Object?>[
            ...config['packages']! as List<Object?>,
            <String, Object?>{
              'name': 'generated_probe',
              'rootUri': dir.uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.13',
            },
          ],
        }),
      );

    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>['analyze', dir.path],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(
      result.exitCode,
      0,
      reason:
          'the generated bindings are what every project compiles against:\n'
          '${result.stdout}${result.stderr}',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
