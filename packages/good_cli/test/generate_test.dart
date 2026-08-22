import 'dart:io';
import 'dart:math';

import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/generate/scaffold.dart';
import 'package:good_cli/src/generate/templates.dart';
import 'package:good_cli/src/verbosable.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

// Codegen: does a project's *declared* assets become the right enum, and does
// a bad input fail at generate time rather than at run time.
//
// The emitters are pure functions of a scan, so almost none of this needs a
// disk. `scanAssets` does, and gets a real temp project - reading a pubspec is
// the thing it is for, and a fake would be testing the fake.

/// The version `packages/[package]` declares, read from its pubspec.
///
/// Walks up for the repository root the same way `scaffold_analyze_test` does,
/// so the suite can be run from the package directory or from the root.
Version _packageVersion(String package) {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}/mkdocs.yml').existsSync() &&
        Directory('${dir.path}/packages').existsSync()) {
      final pubspec = File('${dir.path}/packages/$package/pubspec.yaml');
      if (!pubspec.existsSync()) {
        fail('packages/$package has no pubspec.yaml');
      }
      final line = pubspec.readAsLinesSync().firstWhere(
        (l) => l.startsWith('version:'),
        orElse: () => fail('packages/$package declares no version'),
      );
      return Version.parse(line.substring('version:'.length).trim());
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('run this suite from inside the repository');
}

Directory _project(String pubspec, List<String> files) {
  final dir = Directory.systemTemp.createTempSync('good_cli_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/pubspec.yaml').writeAsStringSync(pubspec);
  for (final path in files) {
    final file = File('${dir.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('');
  }
  return dir;
}

final VerboseOutput _quiet = _NullOutput();

class _NullOutput implements VerboseOutput {
  @override
  void println(Object? object) {}
  @override
  void print(Object? object) {}
  @override
  void printf(String format, List<Object?> args) {}
}

const String _pubspecWithAssets = '''
name: demo
flutter:
  assets:
    - assets/
''';

void main() {
  group('identifierFor', () {
    test('snake_case becomes lowerCamelCase, without the extension', () {
      expect(identifierFor('assets/plane_player_blue.png'), 'planePlayerBlue');
    });

    test('a subdirectory contributes, so two "button"s cannot collide', () {
      expect(identifierFor('assets/ui/button.png'), 'uiButton');
      expect(identifierFor('assets/hud/button.png'), 'hudButton');
    });

    test(
      'the conventional assets/ root is dropped, but never the whole path',
      () {
        expect(identifierFor('assets/tile.png'), 'tile');
        expect(
          identifierFor('tile.png'),
          'tile',
          reason: 'a file declared without a directory still needs a name',
        );
      },
    );

    test('dashes, dots and spaces separate words like underscores do', () {
      expect(
        identifierFor('assets/main-menu.background.png'),
        'mainMenuBackground',
      );
      expect(identifierFor('assets/my tile.png'), 'myTile');
    });

    test('a leading digit is escaped rather than emitted as invalid Dart', () {
      final identifier = identifierFor('assets/2x_logo.png');
      expect(identifier.startsWith(r'$'), isTrue);
      expect(
        RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(identifier),
        isTrue,
        reason: 'whatever it is, it has to be a legal identifier',
      );
    });

    test('a reserved word is escaped - new.png is an ordinary filename', () {
      expect(identifierFor('assets/new.png'), 'new\$');
      expect(
        identifierFor('assets/values.png'),
        'values\$',
        reason:
            'an enum already has `values`, so a member of that name would not '
            'compile even though it is not a Dart keyword',
      );
    });
  });

  group('scanAssets', () {
    test('reads the files a directory entry bundles', () {
      final dir = _project(_pubspecWithAssets, [
        'assets/a.png',
        'assets/b.png',
      ]);
      final scan = scanAssets(dir);
      expect(scan.textures.map((t) => t.identifier), ['a', 'b']);
      expect(scan.textures.first.path, 'assets/a.png');
    });

    test('ignores a file that exists but is not declared', () {
      final dir = _project('name: demo\n', ['assets/a.png']);
      final scan = scanAssets(dir);
      expect(
        scan.textures,
        isEmpty,
        reason:
            'Flutter bundles what the pubspec lists; generating a key for a '
            'file it does not would produce code that compiles and then fails '
            'to load with the file sitting right there',
      );
    });

    test('never scans the chunks a previous build packed', () {
      // The build that found this wrote its chunks into `assets/`, and the
      // next run reported each one as an unrecognised extension - one step
      // away from packing them into chunks of their own, forever.
      final dir = _project(
        '''
name: demo
flutter:
  assets:
    - assets/
    - assets/packed/
''',
        ['assets/a.png', 'assets/packed/chunk_menuscene.dat'],
      );
      final scan = scanAssets(dir);
      expect(scan.textures.map((t) => t.path), ['assets/a.png']);
      expect(
        scan.unsupported,
        isEmpty,
        reason: 'a chunk is not an asset good failed to understand',
      );
    });

    test('ignores the sidecars the pipeline drops beside the assets', () {
      final dir = _project(_pubspecWithAssets, [
        'assets/a.png',
        'assets/.good_compact.json',
      ]);
      final scan = scanAssets(dir);
      expect(scan.textures.map((t) => t.path), ['assets/a.png']);
      expect(scan.unsupported, isEmpty);
    });

    test('honours an individually declared file', () {
      final dir = _project(
        '''
name: demo
flutter:
  assets:
    - assets/only.png
''',
        ['assets/only.png', 'assets/ignored.png'],
      );
      final scan = scanAssets(dir);
      expect(scan.textures.map((t) => t.path), ['assets/only.png']);
    });

    test('sorts each file into the enum its kind belongs to', () {
      final dir = _project(_pubspecWithAssets, [
        'assets/a.png',
        'assets/theme.mp3',
        'assets/notes.txt',
      ]);
      final scan = scanAssets(dir);
      expect(scan.textures.map((t) => t.identifier), ['a']);
      expect(
        scan.audio.map((t) => t.identifier),
        ['theme'],
        reason:
            'audio gets its own enum rather than being swept into the texture '
            'one, where it would generate an AssetKey<Texture> that fails at '
            'decode',
      );
      expect(scan.unsupported.keys, [
        'assets/notes.txt',
      ], reason: 'and only genuinely unrecognised files are reported as such');
    });

    test('one name in two kinds is two assets, not a collision', () {
      // `Textures.click` and `Audios.click` are different types in different
      // enums; refusing them would be inventing a clash that does not exist.
      final dir = _project(_pubspecWithAssets, [
        'assets/click.png',
        'assets/click.ogg',
      ]);
      final scan = scanAssets(dir);
      expect(scan.textures.single.identifier, 'click');
      expect(scan.audio.single.identifier, 'click');
    });

    test('output is sorted, so regenerating does not churn the diff', () {
      final dir = _project(_pubspecWithAssets, [
        'assets/z.png',
        'assets/a.png',
        'assets/m.png',
      ]);
      expect(scanAssets(dir).textures.map((t) => t.identifier), [
        'a',
        'm',
        'z',
      ]);
    });

    test('two paths that collapse to one identifier fail at generate time', () {
      final dir = _project(
        '''
name: demo
flutter:
  assets:
    - assets/
    - assets/ui/
''',
        ['assets/ui_button.png', 'assets/ui/button.png'],
      );
      expect(
        () => scanAssets(dir),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('uiButton'), contains('Rename')),
          ),
        ),
        reason:
            'collapsing two assets onto one enum value would silently make '
            'one of them unreachable',
      );
    });

    test('a project with no pubspec says so', () {
      final dir = Directory.systemTemp.createTempSync('good_cli_empty');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(() => scanAssets(dir), throwsArgumentError);
    });
  });

  group('emitTextures', () {
    test('emits one enum value per texture, with its bundle path', () {
      final dir = _project(_pubspecWithAssets, [
        'assets/plane_player_blue.png',
      ]);
      final source = emitTextures(
        scanAssets(dir),
        command: 'good generate',
        package: 'goo2d',
      );
      expect(
        source,
        contains("planePlayerBlue('assets/plane_player_blue.png')"),
      );
      expect(
        source,
        contains('with LocalEnumAssetKey<Texture>'),
        reason: 'an enum value *is* an AssetKey - that is the whole mechanism',
      );
    });

    test('the path keeps its extension, so a loose build can load it', () {
      final dir = _project(_pubspecWithAssets, ['assets/tile.png']);
      final source = emitTextures(
        scanAssets(dir),
        command: 'good generate',
        package: 'goo2d',
      );
      expect(
        source,
        contains("'assets/tile.png'"),
        reason:
            'BundleSource hands this straight to rootBundle in a development '
            'build, and the bundle knows the pubspec path or nothing at all',
      );
      expect(source, isNot(contains("('tile')")));
    });

    test('an empty project emits something that actually compiles', () {
      // The version of this test that only asserted `contains('enum
      // Textures')` passed while every new project failed to build: Dart has
      // no empty enum, so `enum Textures { ; }` is a compile error. The check
      // has to be about the shape, not the name.
      final dir = _project('name: demo\n', <String>[]);
      final source = emitTextures(
        scanAssets(dir),
        command: 'good generate',
        package: 'goo2d',
      );
      expect(
        source.split('\n').where((line) => line.startsWith('enum ')),
        isEmpty,
        reason:
            'an enum with no constants does not compile - and the doc comment '
            'above the class legitimately mentions the enum it becomes, so '
            'this has to look at declarations rather than at the text',
      );
      expect(source, contains('abstract final class Textures'));
      expect(
        source,
        contains('values'),
        reason:
            'the readiness check walks Textures.values, so it has to exist '
            'before the first asset does',
      );
    });

    test('the generated import names the package the project depends on', () {
      // `package:good` in a project that only depends on `goo2d` is a warning
      // on every new project, and an error under a stricter analysis setup.
      final dir = _project('name: demo\n', <String>[]);
      final scan = scanAssets(dir);
      expect(
        emitTextures(scan, command: 'good generate', package: 'goo2d'),
        contains("import 'package:goo2d/goo2d.dart';"),
      );
      expect(
        emitReadiness(command: 'good generate', package: 'goo2d'),
        contains("import 'package:goo2d/goo2d.dart';"),
      );
    });

    test('every generated file says how to regenerate it', () {
      final dir = _project('name: demo\n', <String>[]);
      for (final source in [
        emitTextures(
          scanAssets(dir),
          command: 'good generate',
          package: 'goo2d',
        ),
        emitReadiness(command: 'good generate', package: 'goo2d'),
        emitAssetKeys(command: 'good generate', random: Random(1)),
      ]) {
        expect(source, contains('GENERATED - do not edit'));
        expect(source, contains('good generate'));
      }
    });
  });

  group('emitAssetKeys', () {
    test('keys are not const, so they stay out of the constant pool', () {
      final source = emitAssetKeys(command: 'good generate', random: Random(1));
      expect(source, contains('final List<int> _assetKey ='));
      expect(
        source,
        isNot(contains('const List<int> _assetKey')),
        reason:
            'a const list is folded into the binary where `strings` finds it - '
            'which is the one thing this is trying to make less trivial',
      );
    });

    test('emits four distinct key parts', () {
      final source = emitAssetKeys(command: 'good generate', random: Random(7));
      for (final name in [
        '_assetKey',
        '_assetKey2',
        '_assetKey3',
        '_assetKey4',
      ]) {
        expect(source, contains('final List<int> $name ='));
      }
    });

    test('the mapping starts empty - it is the packer that fills it', () {
      final source = emitAssetKeys(command: 'good generate', random: Random(1));
      expect(source, contains('assetMapping = <String, String>{}'));
    });
  });

  group('enginePackageOf', () {
    test('names the renderer the project depends on, not the kernel', () {
      expect(
        enginePackageOf(
          _project('name: demo\ndependencies:\n  goo2d: ^0.1.0\n', <String>[]),
        ),
        'goo2d',
      );
      expect(
        enginePackageOf(
          _project('name: demo\ndependencies:\n  goo3d: ^0.1.0\n', <String>[]),
        ),
        'goo3d',
        reason:
            'left off this list, a 3D project generated files importing '
            'package:good - a package its pubspec does not depend on, which '
            'is a lint on every generated file',
      );
      expect(
        enginePackageOf(
          _project('name: demo\ndependencies:\n  good: ^0.1.0\n', <String>[]),
        ),
        'good',
      );
    });

    test('a renderer payload is typed only where the engine draws', () {
      expect(rendererPayloadType('goo2d', 'Texture'), 'Texture');
      expect(
        rendererPayloadType('goo3d', 'Texture'),
        'Object?',
        reason:
            'Texture is a goo2d type - a ui.Image behind a handle, meaningful '
            "only to something that can draw one. Naming it in a 3D project's "
            "generated bindings put four `Texture isn't a type` errors into "
            'its first flutter analyze',
      );
    });

    test('an audio key is typed in a 3D project too', () {
      // AudioClip moved into the kernel (#93), and every engine package
      // re-exports the kernel - so this one needs no per-package answer. It
      // used to come back `Object?` for goo3d, which is why a 3D project could
      // declare a sound and never load it.
      for (final package in <String>['goo2d', 'goo3d', 'good']) {
        expect(
          emitAudios(
            const AssetScan(
              textures: <DiscoveredAsset>[],
              audio: <DiscoveredAsset>[],
              unsupported: <String, String>{},
              declaredEntries: <String>[],
            ),
            command: 'good generate',
            package: package,
          ),
          contains('LocalEnumAssetKey<AudioClip>'),
          reason: '$package re-exports the kernel, so it names AudioClip',
        );
      }
    });
  });

  group('scaffoldFiles', () {
    test('names the game file after the project', () {
      final files = scaffoldFiles(
        projectName: 'demo',
        engine: GoodEngine.twoD,
        command: 'good create',
      );
      expect(files.keys, contains('lib/game/demo_game.dart'));
    });

    test('does not double a _game suffix the name already has', () {
      final files = scaffoldFiles(
        projectName: 'penguin_game',
        engine: GoodEngine.twoD,
        command: 'good create',
      );
      expect(files.keys, contains('lib/game/penguin_game.dart'));
      expect(files.keys, isNot(contains('lib/game/penguin_game_game.dart')));
    });

    test('class names are PascalCase from the package name', () {
      final files = scaffoldFiles(
        projectName: 'my_arcade',
        engine: GoodEngine.twoD,
        command: 'good create',
      );
      expect(
        files['lib/game/my_arcade_game.dart'],
        contains('class MyArcadeGame'),
      );
      expect(files['lib/main.dart'], contains('class MyArcadeApp'));
    });

    test('starts the game before showing it', () {
      final files = scaffoldFiles(
        projectName: 'demo',
        engine: GoodEngine.twoD,
        command: 'good create',
      );
      final main = files['lib/main.dart']!;
      expect(
        main,
        contains('await Game.start('),
        reason:
            'GameView needs a camera from a *running* game - this template '
            'shipped broken until it was compiled against the real API',
      );
      expect(main, contains('GameView(camera:'));
      expect(
        main,
        contains('_game?.stop()'),
        reason: 'the game owns an isolate and native memory',
      );
    });

    test('does not write a pubspec over the one flutter create made', () {
      final files = scaffoldFiles(
        projectName: 'demo',
        engine: GoodEngine.twoD,
        command: 'good create',
      );
      expect(
        files.keys,
        isNot(contains('pubspec.yaml')),
        reason:
            'rewriting it wholesale would discard whatever the installed '
            'Flutter version put there',
      );
      expect(pubspecPatch('goo2d'), contains('goo2d:'));
      expect(pubspecPatch('goo2d'), contains('- assets/'));
    });

    test('the dependency admits the version the engine is about to ship', () {
      // This test had this name and asserted the literal string `^0.1.0`,
      // which is not the same question and cannot answer it. The bug it was
      // written for has now happened twice: `engineConstraint` said `^0.0.1`
      // long after 0.1.0 shipped, and every project scaffolded in between
      // failed `flutter pub get` anywhere without a path override. A string
      // equality check passes just as happily the second time (#95).
      //
      // The repository's own version is the proxy for "what is published",
      // because it is what a release publishes. That makes this go red at the
      // moment someone bumps a package for a release and leaves the scaffold
      // pointing at the range before it - which is the only moment the fix is
      // cheap. `good` and `goo2d` both carry breaking changes under
      // `## Unreleased`, so the next release is 0.2.0, and `^0.1.0` stops at
      // 0.2.0 exclusive.
      final constraint = VersionConstraint.parse(engineConstraint);
      for (final engine in GoodEngine.values) {
        final version = _packageVersion(engine.package);
        expect(
          constraint.allows(version),
          isTrue,
          reason:
              'good create writes `${engine.package}: $engineConstraint`, and '
              'packages/${engine.package} is at $version. A project '
              'scaffolded against that constraint would not resolve the '
              'engine it was generated from. Bump `engineConstraint` in '
              'scaffold.dart to match the release.',
        );
      }
    });

    test('a column is declared by the field that holds it', () {
      final files = scaffoldFiles(
        projectName: 'demo',
        engine: GoodEngine.threeD,
        command: 'good create',
      );
      final player = files['lib/game/prefabs/player.dart']!;
      expect(player, contains('Field.float64('));
      expect(
        player,
        isNot(contains('DataPointer<')),
        reason:
            'the superseded form. A scaffold is how a shape spreads, so it '
            'has to teach the current one',
      );
      expect(player, isNot(contains('describeStruct')));
    });

    test('a prefab is declared by its constructor, not an instance', () {
      for (final engine in GoodEngine.values) {
        final files = scaffoldFiles(
          projectName: 'demo',
          engine: engine,
          command: 'good create',
        );
        expect(
          files['lib/game/scenes/main_scene.dart'],
          contains('descriptor.has(Player.new)'),
          reason:
              'a field initialiser has no descriptor in scope, so the '
              'framework opens one around the constructor call',
        );
      }
    });
  });

  group('scaffoldFiles --3d', () {
    Map<String, String> files() => scaffoldFiles(
      projectName: 'demo',
      engine: GoodEngine.threeD,
      command: 'good create',
    );

    /// [source] with its comments removed.
    ///
    /// The templates talk *about* the 2D side - what `Game2D` declares for you
    /// that a 3D game declares by hand - so a search for `2D` over the whole
    /// file finds prose. What must not appear is a 2D name in the code.
    String code(String source) => source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    test('imports goo3d and names nothing 2D', () {
      for (final entry in files().entries) {
        if (!entry.key.endsWith('.dart')) continue;
        expect(
          code(entry.value),
          isNot(contains('goo2d')),
          reason: '${entry.key} imports the wrong engine',
        );
        expect(
          code(entry.value),
          isNot(contains('2D')),
          reason:
              '${entry.key} names a 2D type - Transform2D, Renderable2D and '
              'Game2D are all things a goo3d project cannot resolve',
        );
      }
    });

    test('claims no renderer, because there is none', () {
      final scaffolded = files();
      final player = scaffolded['lib/game/prefabs/player.dart']!;
      expect(
        code(player),
        isNot(contains('Renderable3D')),
        reason:
            'there is no such component. goo3d is transforms, hierarchy and '
            'the camera; the draw path is issue #43',
      );
      expect(
        player,
        contains('#43'),
        reason:
            'a template that goes quiet about what is missing is worse than '
            'one that names the issue that brings it',
      );
      expect(
        scaffolded['lib/main.dart'],
        contains('Nothing is drawn here yet'),
      );
    });

    test('declares the view it shows, and a camera entity to occupy it', () {
      final scaffolded = files();
      final game = scaffolded['lib/game/demo_game.dart']!;
      expect(game, contains('mainView'));
      expect(
        game,
        contains('describeCameras'),
        reason: 'Game2D declares a default view for you; plain Game does not',
      );
      expect(
        scaffolded['lib/main.dart'],
        contains('GameView(camera: game.mainView)'),
      );
      expect(scaffolded.keys, contains('lib/game/prefabs/eye.dart'));
      expect(
        scaffolded['lib/game/scenes/main_scene.dart'],
        contains('eye.view[camera] ='),
        reason: 'a camera occupying no view is a camera nothing would show',
      );
    });

    test('declares the composition pass nothing else declares', () {
      expect(
        files()['lib/game/demo_game.dart'],
        contains('WorldTransform3DSystem()'),
        reason:
            'Renderer2DState declares the 2D twin for you. Without this a '
            'child never moves with its parent',
      );
    });

    test('turns an entity through the accessor, not a helper taking one', () {
      expect(
        files()['lib/game/systems/spin_system.dart'],
        contains('entity<Transform3D>().setEuler('),
        reason:
            "a method acting on one entity belongs on that component's "
            'accessor - see docs/reference/design-rules.md',
      );
    });
  });

  group('patchedPubspecLines', () {
    // What `flutter create` writes, trimmed to the two lines this anchors on
    // plus enough around them to tell placement from luck.
    const List<String> flutterCreated = <String>[
      'name: my_game',
      '',
      'dependencies:',
      '  flutter:',
      '    sdk: flutter',
      '  cupertino_icons: ^1.0.8',
      '',
      'flutter:',
      '  uses-material-design: true',
      '',
      '  # To add assets to your application, add an assets section',
    ];

    test('adds the dependency and both asset entries', () {
      final patched = patchedPubspecLines(flutterCreated, 'goo2d')!;
      expect(patched[3], '  goo2d: ^0.1.0');
      expect(
        patched,
        containsAllInOrder(<String>['    - assets/', '    - assets/packed/']),
      );
      expect(
        patched,
        contains(
          '  # To add assets to your application, add an assets section',
        ),
        reason:
            'a textual patch keeps the comments flutter create wrote; a YAML '
            'round-trip would have dropped them',
      );
    });

    test('the assets list lands inside the flutter section', () {
      final patched = patchedPubspecLines(flutterCreated, 'goo2d')!;
      expect(
        patched.indexOf('  assets:'),
        greaterThan(patched.indexOf('flutter:')),
        reason:
            'at the top level it would be silently ignored, and a build that '
            'bundles nothing is the hardest kind of wrong to see',
      );
    });

    test('running it twice does not add the dependency twice', () {
      final once = patchedPubspecLines(flutterCreated, 'goo2d')!;
      final twice = patchedPubspecLines(once, 'goo2d')!;
      expect(twice, once);
    });

    test('an edited dependency line is still the dependency', () {
      // #28. The check used to match the literal line this wrote, so a
      // constraint someone had pinned, widened, or that an older version of
      // this command wrote did not look present - and re-running appended a
      // second `goo2d:` and a second `assets:`. Two of either key is not a bad
      // merge; it is a pubspec every flutter command refuses to read.
      final once = patchedPubspecLines(flutterCreated, 'goo2d')!;
      for (final edit in <String>[
        '  goo2d: ^0.0.1', // what an older good create wrote
        '  goo2d: any',
        '  goo2d: 0.1.1',
        '  goo2d: ">=0.1.0 <0.2.0"',
      ]) {
        final edited = once
            .map((line) => line == '  goo2d: ^0.1.0' ? edit : line)
            .toList();
        expect(
          patchedPubspecLines(edited, 'goo2d'),
          edited,
          reason: '$edit is the goo2d dependency, however it is spelled',
        );
      }
    });

    test('a dependency under a comment is still the dependency', () {
      final once = patchedPubspecLines(flutterCreated, 'goo2d')!;
      final commented = <String>[
        for (final line in once) ...<String>[
          if (line == '  goo2d: ^0.1.0') '  # pinned deliberately, see #123',
          line,
        ],
      ];
      expect(patchedPubspecLines(commented, 'goo2d'), commented);
    });

    test('the two additions are independent', () {
      // A pubspec that has the dependency but no assets block gets the assets
      // block and nothing else. One early return for both used to mean the
      // first one present suppressed the other.
      final withDepOnly = <String>[
        'name: my_game',
        'dependencies:',
        '  goo2d: ^0.1.0',
        '  flutter:',
        '    sdk: flutter',
        '',
        'flutter:',
        '  uses-material-design: true',
      ];
      final patched = patchedPubspecLines(withDepOnly, 'goo2d')!;
      expect(
        patched.where((line) => line.trim().startsWith('goo2d:')).length,
        1,
      );
      expect(patched, contains('  assets:'));
    });

    test('a pubspec that already has duplicate keys is left alone', () {
      // It no longer parses, which is the state #28 produced. Editing it
      // further is not something to do blind - the caller prints the patch.
      expect(
        patchedPubspecLines(<String>[
          'name: my_game',
          'dependencies:',
          '  goo2d: ^0.1.0',
          'dependencies:',
          '  goo2d: ^0.1.0',
          'flutter:',
          '  uses-material-design: true',
        ], 'goo2d'),
        isNull,
      );
    });

    test('a pubspec it does not recognise is left alone', () {
      // The caller prints the patch instead. A wrong edit to someone's pubspec
      // is worse than an instruction to make the right one by hand.
      expect(
        patchedPubspecLines(<String>[
          'name: my_game',
          'dependencies:',
        ], 'goo2d'),
        isNull,
      );
    });
  });

  group('unbundledAssets', () {
    // Flutter's directory entries are not recursive, so a compaction output in
    // a subdirectory ships nowhere and produces no enum value. It used to do
    // that silently, and `good generate` exited 0.

    test('finds an asset in a subdirectory the pubspec does not list', () {
      final dir = _project(_pubspecWithAssets, <String>[
        'assets/player.png',
        'assets/ui/button.png',
      ]);
      expect(unbundledAssets(dir), {
        'assets/ui/': ['assets/ui/button.png'],
      });
    });

    test('a listed subdirectory is bundled and so is not reported', () {
      final dir = _project(
        '''
name: demo
flutter:
  assets:
    - assets/
    - assets/ui/
''',
        <String>['assets/player.png', 'assets/ui/button.png'],
      );
      expect(unbundledAssets(dir), isEmpty);
    });

    test('an individually declared file needs no directory entry', () {
      final dir = _project(
        '''
name: demo
flutter:
  assets:
    - assets/
    - assets/ui/button.png
''',
        <String>['assets/player.png', 'assets/ui/button.png'],
      );
      expect(unbundledAssets(dir), isEmpty);
    });

    test('chunks are not assets, so the packed directory is not reported', () {
      final dir = _project(_pubspecWithAssets, <String>[
        'assets/player.png',
        'assets/packed/chunk_root.dat',
      ]);
      expect(unbundledAssets(dir), isEmpty);
    });

    test('a subdirectory of things codegen would not name is left alone', () {
      // A font or a `.gitkeep` was never going to become an enum value, so a
      // directory holding only those is not a build to stop.
      final dir = _project(_pubspecWithAssets, <String>[
        'assets/player.png',
        'assets/fonts/roboto.ttf',
        'assets/ui/.gitkeep',
      ]);
      expect(unbundledAssets(dir), isEmpty);
    });

    test('the message names the files and the exact line to add', () {
      final message = unbundledAssetsMessage({
        'assets/ui/': ['assets/ui/button.png'],
      });
      expect(message, contains('assets/ui/button.png'));
      expect(
        message,
        contains('    - assets/ui/'),
        reason: 'the pubspec line is the whole fix, so it has to be in there',
      );
    });
  });

  group('runGenerate', () {
    test('fails rather than dropping an asset Flutter will not bundle', () {
      final dir = _project(_pubspecWithAssets, <String>[
        'assets/player.png',
        'assets/ui/button.png',
      ]);
      expect(
        () => runGenerate(
          projectDir: dir,
          command: 'good generate',
          out: _quiet,
          verbose: _quiet,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            allOf(contains('assets/ui/button.png'), contains('- assets/ui/')),
          ),
        ),
      );
      expect(
        Directory('${dir.path}/lib/good.generated').existsSync(),
        isFalse,
        reason: 'it stops before writing an enum that is missing a value',
      );
    });

    test('fails rather than generating over a shadowed column', () {
      // The same refusal as the unbundled asset above, and here for the same
      // reason: nothing downstream will ever mention it. The row simply grows
      // by a column no expression can reach, and reads written against the
      // hidden one land on its neighbour.
      final dir = _project(_pubspecWithAssets, <String>[]);
      File('${dir.path}/lib/game.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''
mixin Velocity on Component {
  final speed = Field.float64();
}
mixin Momentum on Component {
  final speed = Field.float64();
}
class Player extends EntityStruct with Velocity, Momentum {}
''');
      expect(
        () => runGenerate(
          projectDir: dir,
          command: 'good generate',
          out: _quiet,
          verbose: _quiet,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            allOf(
              contains('Momentum.speed shadows Velocity.speed'),
              contains('game.dart'),
            ),
          ),
        ),
      );
      expect(
        Directory('${dir.path}/lib/good.generated').existsSync(),
        isFalse,
        reason: 'it stops before writing anything',
      );
    });

    test('fails rather than generating over a broken describeX chain', () {
      // The same refusal as the two above. A mixin that stops chaining
      // contributes no columns and no query bit, and every mixin applied
      // before it is cut off too - with nothing said at run time.
      final dir = _project(_pubspecWithAssets, <String>[]);
      File('${dir.path}/lib/game.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''
mixin Velocity on Component {
  final speed = Field.float64();

  @override
  void describeType(ComponentDescriptor component) {
    component.has<Velocity>();
  }
}
''');
      expect(
        () => runGenerate(
          projectDir: dir,
          command: 'good generate',
          out: _quiet,
          verbose: _quiet,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            allOf(
              contains(
                'Velocity.describeType does not call '
                'super.describeType()',
              ),
              contains('game.dart'),
            ),
          ),
        ),
      );
      expect(
        Directory('${dir.path}/lib/good.generated').existsSync(),
        isFalse,
        reason: 'it stops before writing anything',
      );
    });

    test('writes the enum when every asset is bundled', () {
      final dir = _project(
        '''
name: demo
flutter:
  assets:
    - assets/
    - assets/ui/
''',
        <String>['assets/player.png', 'assets/ui/button.png'],
      );
      runGenerate(
        projectDir: dir,
        command: 'good generate',
        out: _quiet,
        verbose: _quiet,
      );
      final textures = File(
        '${dir.path}/lib/good.generated/textures.dart',
      ).readAsStringSync();
      expect(textures, contains("uiButton('assets/ui/button.png')"));
    });
  });
}
