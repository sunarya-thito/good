import 'dart:convert';
import 'dart:io';

import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/engine_dependency.dart';
import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/generate/scaffold.dart';
import 'package:good_cli/src/generate/templates.dart';
import 'package:test/test.dart';

import '_resolved.dart';
import '_scaffolded.dart';
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
// The project it reads is `scaffoldProject`'s, which is the same one
// `scaffold_boot_test` runs - scaffolded, generated into, and resolved against
// this repository's own packages. That sharing is not tidiness: this suite
// used to write its own pubspec beside the templates, so what it analyzed was
// a project nobody is handed, and a scaffold that could not boot passed it.
//
// # Every case here runs the analyzer the way the project's owner will
//
// `dart analyze` exits 0 on an info, and `flutter analyze` fails a project on
// one, so an exit code alone says nothing about the diagnostics a user meets
// first (#321). Two things close that gap and both are needed:
// [_analyzeClean] passes `--fatal-infos`, and every project analyzed carries
// the `analysis_options.yaml` `flutter create` writes, so the rules in force
// are the ones it ships with.
//
// The pubspecs matter for the same reason. `depend_on_referenced_packages`
// reads the `dependencies:` map, so a project that declares nothing reports
// every import in it and one that declares everything reports none. The
// scaffolded cases get theirs from `scaffoldProject`, and the
// generated-bindings case builds its list out of [generatedImports] - the
// function whose job is to name what the emitters import.

/// Runs the analyzer over [path] and fails on anything it reports.
///
/// `--fatal-infos` is the whole point: without it `dart analyze` exits 0 on an
/// info, and the two lints a generated file is most likely to trip -
/// `unnecessary_import` and `depend_on_referenced_packages` - are both infos.
/// The alternative is reading `stdout` for `No issues found`, which works and
/// needs the expected text kept in step with the analyzer's wording.
///
/// The VM running this suite, so nothing here depends on `dart` being on PATH.
Future<void> _analyzeClean(String path, {required String reason}) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    <String>['analyze', '--fatal-infos', path],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  expect(
    result.exitCode,
    0,
    reason: '$reason:\n${result.stdout}${result.stderr}',
  );
}

void main() {
  for (final engine in GoodEngine.values) {
    test('a scaffolded ${engine.package} project analyzes clean', () async {
      // Generated as well as scaffolded, which is the whole project rather
      // than half of it. `good create` runs `good generate` before it returns,
      // and the templates name what generation writes: the bundle's
      // `ensureGameReady`, and the declaration table the game overrides
      // `Game.declarations` with. Analyzing the templates alone was a check
      // over a project nobody is ever handed.
      final dir = scaffoldProject(
        name: '${engine.package}_analyze_probe',
        engine: engine,
      );
      await _analyzeClean(
        dir.path,
        reason:
            'a project `good create` writes has to compile before its author '
            'has touched it, and analyze clean under the lints it ships with',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  test('a generated textures.dart with assets in it analyzes clean', () async {
    // Every other test over `emitTextures` reads its output as a string, and a
    // string assertion only catches what somebody thought to assert. This is
    // the one that would notice `TextureSize` colliding with a name goo2d
    // exports, or an enum whose constructor no longer matches its fields.
    final root = repoRoot();
    final dir = testTempDir('good_generated_analyze');
    // The dependencies are `generatedImports`', which is the set the bundle's
    // own pubspec declares. An emitter that starts importing a package that
    // set does not name reports `depend_on_referenced_packages` here, the way
    // it would in a project whose bundle pubspec was written from the same
    // set.
    final imports = generatedImports(drawsTextures: true).toList()..sort();
    File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: generated_probe

environment:
  sdk: ^3.13.0

dependencies:
  flutter:
    sdk: flutter
${imports.map((String p) => '  $p: any\n').join()}
dev_dependencies:
  flutter_lints: any

good:
  assets:
    - assets/
''');
    File(
      '${dir.path}/analysis_options.yaml',
    ).writeAsStringSync(scaffoldAnalysisOptions);
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
      emitTextures(scan, command: 'good generate', drawsTextures: true),
    );
    File(
      '${lib.path}/audios.dart',
    ).writeAsStringSync(emitAudios(scan, command: 'good generate'));
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

    final config = absolutePackageConfig(root, 'goo2d');
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

    await _analyzeClean(
      dir.path,
      reason: 'the generated bindings are what every project compiles against',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a bundle generated for an entry package that re-exports nothing '
      'analyzes clean', () async {
    // #316, end to end and with the lints a real project runs under.
    //
    // The project declares a physics backend and goo2d, so #309 resolves the
    // backend as the entry package - and that package's library exports its
    // own `src/` and re-exports neither goo2d nor the kernel. A bundle that
    // named every type through the entry package failed at `AssetKey`, which
    // is every asset kind and not the textures alone.
    //
    // `depend_on_referenced_packages` and `unnecessary_import` are the two
    // ways the fix can be wrong in the other direction: an import the bundle's
    // pubspec does not declare, and a second import of a library the first one
    // already re-exports. Both are infos, so `--fatal-infos` is what makes
    // this case able to see either of them.
    //
    // The options file sits in the project and the bundle sits under it, which
    // is where the analyzer looks for one: a generated package inherits the
    // rules of the project it was generated into.
    final root = repoRoot();
    final dir = testTempDir('good_bundle_analyze');
    File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: bundle_probe

environment:
  sdk: ^3.13.0

dependencies:
  demo_physics: ^0.1.0
  goo2d: ^0.3.0

dev_dependencies:
  flutter_lints: any

good:
  assets:
    - assets/
''');
    File(
      '${dir.path}/analysis_options.yaml',
    ).writeAsStringSync(scaffoldAnalysisOptions);
    // A 24-byte PNG: signature and IHDR, which is all a header read needs.
    File('${dir.path}/assets/sheet.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
        0, 0, 2, 0,
        0, 0, 1, 0,
      ]);
    File('${dir.path}/assets/theme.ogg').writeAsBytesSync(<int>[0]);

    // Stubs, so the entry package is resolved out of a graph the way a
    // `pub get` leaves one, and the struct scan has nothing to walk.
    resolvePackages(dir, <String, List<String>>{
      'demo_physics': <String>['goo2d'],
      'goo2d': <String>['good'],
      'good': <String>[],
    });
    runGenerate(
      projectDir: dir,
      command: 'good generate',
      out: quietOutput,
      verbose: quietOutput,
      pubGet: false,
    );
    final bundle = Directory('${dir.path}/bundle_probe_bundle');
    expect(
      bundle.existsSync(),
      isTrue,
      reason: 'the bundle package is what is about to be analyzed',
    );

    // Now the real packages, so `AssetKey`, `AudioClip` and `Texture` are the
    // declarations this repository ships rather than empty stub directories.
    final config = absolutePackageConfig(root, 'goo2d');
    File('${dir.path}/.dart_tool/package_config.json').writeAsStringSync(
      jsonEncode(<String, Object?>{
        ...config,
        'packages': <Object?>[
          ...config['packages']! as List<Object?>,
          <String, Object?>{
            'name': 'bundle_probe',
            'rootUri': dir.uri.toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.13',
          },
          <String, Object?>{
            'name': 'bundle_probe_bundle',
            'rootUri': bundle.uri.toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.13',
          },
        ],
      }),
    );

    await _analyzeClean(
      bundle.path,
      reason:
          'every name in the bundle has to resolve through an import the '
          'bundle declares, and through one import and not two',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
