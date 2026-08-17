import 'dart:io';
import 'dart:math';

import 'package:goo_cli/src/generate/assets.dart';
import 'package:goo_cli/src/generate/scaffold.dart';
import 'package:goo_cli/src/generate/templates.dart';
import 'package:test/test.dart';

// Codegen: does a project's *declared* assets become the right enum, and does
// a bad input fail at generate time rather than at run time.
//
// The emitters are pure functions of a scan, so almost none of this needs a
// disk. `scanAssets` does, and gets a real temp project - reading a pubspec is
// the thing it is for, and a fake would be testing the fake.

Directory _project(String pubspec, List<String> files) {
  final dir = Directory.systemTemp.createTempSync('goo_cli_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/pubspec.yaml').writeAsStringSync(pubspec);
  for (final path in files) {
    final file = File('${dir.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('');
  }
  return dir;
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
      final dir = Directory.systemTemp.createTempSync('goo_cli_empty');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(() => scanAssets(dir), throwsArgumentError);
    });
  });

  group('emitTextures', () {
    test('emits one enum value per texture, with its bundle path', () {
      final dir = _project(_pubspecWithAssets, [
        'assets/plane_player_blue.png',
      ]);
      final source = emitTextures(scanAssets(dir), command: 'goo generate');
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
      final source = emitTextures(scanAssets(dir), command: 'goo generate');
      expect(
        source,
        contains("'assets/tile.png'"),
        reason:
            'BundleSource hands this straight to rootBundle in a development '
            'build, and the bundle knows the pubspec path or nothing at all',
      );
      expect(source, isNot(contains("('tile')")));
    });

    test('an empty project still emits a compilable enum', () {
      final dir = _project('name: demo\n', <String>[]);
      final source = emitTextures(scanAssets(dir), command: 'goo generate');
      expect(
        source,
        contains('enum Textures'),
        reason: 'code importing it has to keep compiling',
      );
      expect(source, contains(';'));
    });

    test('every generated file says how to regenerate it', () {
      final dir = _project('name: demo\n', <String>[]);
      for (final source in [
        emitTextures(scanAssets(dir), command: 'goo generate'),
        emitReadiness(command: 'goo generate'),
        emitAssetKeys(command: 'goo generate', random: Random(1)),
      ]) {
        expect(source, contains('GENERATED - do not edit'));
        expect(source, contains('goo generate'));
      }
    });
  });

  group('emitAssetKeys', () {
    test('keys are not const, so they stay out of the constant pool', () {
      final source = emitAssetKeys(command: 'goo generate', random: Random(1));
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
      final source = emitAssetKeys(command: 'goo generate', random: Random(7));
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
      final source = emitAssetKeys(command: 'goo generate', random: Random(1));
      expect(source, contains('assetMapping = <String, String>{}'));
    });
  });

  group('scaffoldFiles', () {
    test('names the game file after the project', () {
      final files = scaffoldFiles(
        projectName: 'demo',
        package: 'goo2d',
        command: 'goo create',
      );
      expect(files.keys, contains('lib/game/demo_game.dart'));
    });

    test('does not double a _game suffix the name already has', () {
      final files = scaffoldFiles(
        projectName: 'penguin_game',
        package: 'goo2d',
        command: 'goo create',
      );
      expect(files.keys, contains('lib/game/penguin_game.dart'));
      expect(files.keys, isNot(contains('lib/game/penguin_game_game.dart')));
    });

    test('class names are PascalCase from the package name', () {
      final files = scaffoldFiles(
        projectName: 'my_arcade',
        package: 'goo2d',
        command: 'goo create',
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
        package: 'goo2d',
        command: 'goo create',
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
        package: 'goo2d',
        command: 'goo create',
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
  });
}
