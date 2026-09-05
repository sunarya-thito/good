import 'dart:io';
import 'dart:math';

import 'dart:typed_data';

import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/bundle.dart';
import 'package:good_cli/src/generate/engine_dependency.dart';
import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/generate/scaffold.dart';
import 'package:good_cli/src/generate/templates.dart';
import 'package:good_cli/src/verbosable.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '_resolved.dart';
import '_temp.dart';

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
  final dir = testTempDir('good_cli_test');
  File('${dir.path}/pubspec.yaml').writeAsStringSync(pubspec);
  for (final path in files) {
    final file = File('${dir.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('');
  }
  return dir;
}

/// A project whose declared assets are real PNGs of the stated size.
///
/// The size is written into the header here, so a generated `512` can only
/// have come from the header being read - [_project] writes empty files, which
/// is what every test above wants and what no test of a dimension can use.
Directory _projectWithImages(String pubspec, Map<String, List<int>> images) {
  final dir = testTempDir('good_cli_test');
  File('${dir.path}/pubspec.yaml').writeAsStringSync(pubspec);
  images.forEach((path, size) {
    File('${dir.path}/$path')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(_pngBytes(size[0], size[1]));
  });
  return dir;
}

/// A 24-byte PNG: the signature and an `IHDR` chunk, and nothing after it.
///
/// Enough for a header read and for nothing else. Encoding an actual image
/// would need a compressor and would leave the dimension in two places.
Uint8List _pngBytes(int width, int height) {
  final bytes = Uint8List(24)
    ..setRange(0, 8, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A,
      0x0A])
    ..setRange(12, 16, 'IHDR'.codeUnits);
  for (var i = 0; i < 4; i++) {
    bytes[16 + i] = (width >> (24 - 8 * i)) & 0xFF;
    bytes[20 + i] = (height >> (24 - 8 * i)) & 0xFF;
  }
  return bytes;
}

/// A project resolved against [graph], each entry a package and the
/// `dependencies:` its own pubspec declares.
///
/// [resolvePackages] writes it the way a `pub get` leaves one, which is where
/// the generator reads a dependency's pubspec from.
Directory _graph(Map<String, List<String>> graph) {
  final dir = _project('name: demo\n', <String>[]);
  resolvePackages(dir, graph);
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
good:
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
good:
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
good:
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
good:
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
      final dir = testTempDir('good_cli_empty');
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
        drawsTextures: true,
      );
      expect(
        source,
        contains("planePlayerBlue('assets/plane_player_blue.png', "),
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
        drawsTextures: true,
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
        drawsTextures: true,
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

    test('each generated file imports what declares the names in it', () {
      // Two questions, and each file asks the one it needs: `Texture` is
      // goo2d's, and `AssetKey`, `AudioClip` and the pack API are the
      // kernel's. The readiness check names none of the first kind, so it
      // imports the kernel in a 2D project as much as in a 3D one (#316).
      final dir = _project('name: demo\n', <String>[]);
      final scan = scanAssets(dir);
      expect(
        emitTextures(scan, command: 'good generate', drawsTextures: true),
        contains("import 'package:goo2d/goo2d.dart';"),
      );
      expect(
        emitTextures(scan, command: 'good generate', drawsTextures: false),
        contains("import 'package:good/good.dart';"),
      );
      expect(
        emitReadiness(command: 'good generate'),
        contains("import 'package:good/good.dart';"),
      );
    });

    test('a file naming Texture imports goo2d once, and not good as well', () {
      // Both imports resolve - two URIs delivering one declaration are not
      // ambiguous - and the second is still wrong. goo2d re-exports the
      // kernel, so naming it too is an `unnecessary_import`, which
      // `flutter analyze` reports and a project's CI fails on.
      final source = emitTextures(
        scanAssets(_project('name: demo\n', <String>[])),
        command: 'good generate',
        drawsTextures: true,
      );
      expect(source, isNot(contains("import 'package:good/good.dart';")));
      expect(
        'import '.allMatches(source).length,
        1,
        reason: 'one import line, and it is goo2d',
      );
    });

    test('every generated file says how to regenerate it', () {
      final dir = _project('name: demo\n', <String>[]);
      for (final source in [
        emitTextures(
          scanAssets(dir),
          command: 'good generate',
          drawsTextures: true,
        ),
        emitReadiness(command: 'good generate'),
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
    /// A project declaring [dependencies], resolved against [graph].
    Directory resolved(
      List<String> dependencies,
      Map<String, List<String>> graph,
    ) {
      final dir = _project(
        'name: demo\ndependencies:\n'
        '${dependencies.map((d) => '  $d: ^0.1.0\n').join()}',
        <String>[],
      );
      resolvePackages(dir, graph);
      return dir;
    }

    test('a renderer is named, and so is the kernel on its own', () {
      expect(
        enginePackageOf(
          resolved(<String>['goo2d'], <String, List<String>>{
            'goo2d': <String>['good'],
            'good': <String>[],
          }),
        ),
        'goo2d',
      );
      expect(
        enginePackageOf(
          resolved(<String>['goo3d'], <String, List<String>>{
            'goo3d': <String>['good'],
            'good': <String>[],
          }),
        ),
        'goo3d',
        reason:
            'goo3d reaches the kernel through its own dependencies and is a '
            'renderer by the same test goo2d is, without being named anywhere',
      );
      expect(
        enginePackageOf(
          resolved(<String>['good'], <String, List<String>>{
            'good': <String>[],
          }),
        ),
        'good',
      );
    });

    test('a renderer nothing here has heard of is the entry package', () {
      expect(
        enginePackageOf(
          resolved(<String>['neon'], <String, List<String>>{
            'neon': <String>['goo2d'],
            'goo2d': <String>['good'],
            'good': <String>[],
          }),
        ),
        'neon',
        reason:
            'a third-party renderer reaches the kernel through goo2d, so it '
            'is an engine dependency and it is the one the project draws '
            'through',
      );
    });

    test('the renderer wins over the packages it is built on', () {
      expect(
        enginePackageOf(
          resolved(<String>['neon', 'goo2d', 'good'], <String, List<String>>{
            'neon': <String>['goo2d'],
            'goo2d': <String>['good'],
            'good': <String>[],
          }),
        ),
        'neon',
        reason:
            'declaring all three, the generated code names the surface of the '
            'outermost one - the other two are what it is built on',
      );
    });

    test('a dependency that does not reach the engine is not a candidate', () {
      expect(
        enginePackageOf(
          resolved(<String>[
            'audioplayers',
            'google_fonts',
            'goo2d',
          ], <String, List<String>>{
            'audioplayers': <String>[],
            'google_fonts': <String>['flutter'],
            'goo2d': <String>['good'],
            'good': <String>[],
          }),
        ),
        'goo2d',
        reason:
            'audioplayers sorts first and google_fonts is the name the old '
            'prefix test matched, and neither reaches the engine, so neither '
            'is a package the generated code could import',
      );
    });

    test('two renderers side by side are ordered by name', () {
      const graph = <String, List<String>>{
        'goo2d': <String>['good'],
        'goo3d': <String>['good'],
        'good': <String>[],
      };
      expect(
        enginePackageOf(resolved(<String>['goo3d', 'goo2d'], graph)),
        'goo2d',
      );
      expect(
        enginePackageOf(resolved(<String>['goo2d', 'goo3d'], graph)),
        'goo2d',
        reason:
            'neither is built on the other, so nothing in the graph orders '
            'them - and the answer still cannot depend on which line of the '
            'pubspec came first',
      );
    });

    test('no engine dependency at all falls back to the kernel', () {
      expect(
        enginePackageOf(
          resolved(<String>['google_fonts'], <String, List<String>>{
            'google_fonts': <String>['flutter'],
          }),
        ),
        'good',
      );
    });

    test('an unresolved project falls back to the kernel', () {
      expect(
        enginePackageOf(
          _project('name: demo\ndependencies:\n  goo2d: ^0.1.0\n', <String>[]),
        ),
        'good',
        reason:
            'a dependency added since the last pub get is in no package '
            'config, so there is no pubspec of its own to read and nothing '
            'says it is an engine package',
      );
    });

    test('a directory with no pubspec falls back to the kernel', () {
      expect(enginePackageOf(testTempDir('good_cli_test')), 'good');
    });

    test('the caller can name the package instead', () async {
      final dir = _project(
        'name: demo\ndependencies:\n  goo2d: ^0.1.0\n\n'
        'good:\n  assets:\n    - assets/\n',
        <String>['assets/player.png'],
      );
      await runGenerate(
        projectDir: dir,
        command: 'good generate',
        out: _quiet,
        verbose: _quiet,
        enginePackage: 'goo2d',
        pubGet: false,
      );
      expect(
        File('${dir.path}/demo_bundle/lib/textures.dart').readAsStringSync(),
        contains("import 'package:goo2d/goo2d.dart';"),
        reason:
            'the project is unresolved, so nothing in it says goo2d is the '
            'engine - `good create` knows because it wrote the line, and '
            'says so',
      );
    });

    test('a renderer payload is typed only where the engine draws', () {
      expect(rendererPayloadType(true, 'Texture'), 'Texture');
      expect(
        rendererPayloadType(false, 'Texture'),
        'Object?',
        reason:
            'Texture is a goo2d type - a ui.Image behind a handle, meaningful '
            "only to something that can draw one. Naming it in a 3D project's "
            "generated bindings put four `Texture isn't a type` errors into "
            'its first flutter analyze',
      );
    });

    test('an audio key is typed through the kernel, in any project', () {
      // AudioClip moved into the kernel (#93), so an audio key is the same in
      // a 2D project and a 3D one - it came back `Object?` for goo3d once,
      // which is how a 3D project could declare a sound and never load it.
      //
      // The import is the kernel for the same reason: nothing in this file
      // names a renderer type, so nothing about it depends on which package
      // the project entered the engine through (#316).
      final source = emitAudios(
        const AssetScan(
          textures: <DiscoveredAsset>[],
          audio: <DiscoveredAsset>[],
          unsupported: <String, String>{},
          declaredEntries: <String>[],
        ),
        command: 'good generate',
      );
      expect(source, contains('LocalEnumAssetKey<AudioClip>'));
      expect(source, contains("import 'package:good/good.dart';"));
      expect(source, isNot(contains('goo2d')));
    });
  });

  group('generating into a project that has already been generated into', () {
    /// A generated bundle package at [root], declaring [dependencies] and
    /// carrying the marker that says the directory is good's.
    Directory markedBundleAt(Directory root, List<String> dependencies) {
      final name = p.basename(root.path);
      Directory('${root.path}/lib').createSync(recursive: true);
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: $name\ndependencies:\n'
        '${dependencies.map((d) => '  $d: any\n').join()}',
      );
      File(
        p.join(root.path, bundleMarkerName),
      ).writeAsStringSync('bundle: $name\n');
      return root;
    }

    const engineGraph = <String, List<String>>{
      'goo2d': <String>['good'],
      'good': <String>[],
    };

    test('the second run does not name the bundle as the entry package', () {
      // The shape no fixture had: `_recordBundle` puts the bundle in
      // `dependencies:`, a pub get resolves it, and it then reaches the engine
      // and has nothing depending on it - the most specific candidate by both
      // narrowings.
      final dir = _project(
        'name: demo\ndependencies:\n'
        '  demo_bundle:\n    path: demo_bundle\n'
        '  goo2d: ^0.3.0\n',
        <String>[],
      );
      resolvePackages(
        dir,
        engineGraph,
        at: <String, Directory>{
          'demo_bundle': markedBundleAt(
            Directory('${dir.path}/demo_bundle'),
            <String>['goo2d', 'good'],
          ),
        },
      );
      expect(
        enginePackageOf(dir),
        'goo2d',
        reason:
            'demo_bundle sorts before goo2d and is built on it, so it wins '
            'both the sort and the most-specific test - the marker is what '
            'takes it out of the running',
      );
    });

    test('a bundle belonging to another project is not a candidate', () {
      // Not this project's bundle: a different name, a directory outside the
      // project, reached the way a `path:` dependency on a sibling checkout
      // reaches anything. Generated code either way, so not something the
      // generated files can be written against.
      final root = testTempDir('good_cli_test');
      final dir = Directory('${root.path}/demo')..createSync();
      File('${dir.path}/pubspec.yaml').writeAsStringSync(
        'name: demo\ndependencies:\n'
        '  alpha_bundle:\n    path: ../alpha_bundle\n'
        '  goo2d: ^0.3.0\n',
      );
      resolvePackages(
        dir,
        engineGraph,
        at: <String, Directory>{
          'alpha_bundle': markedBundleAt(
            Directory('${root.path}/alpha_bundle')..createSync(),
            <String>['good'],
          ),
        },
      );
      expect(
        enginePackageOf(dir),
        'goo2d',
        reason:
            'alpha_bundle reaches the kernel and sorts first, and neither it '
            'nor goo2d is built on the other, so first-by-name would answer '
            'alpha_bundle',
      );
    });

    test('a package carrying the recorded name and no marker still counts', () {
      // The marker and not the name. `zed_bundle` is what `good: bundle:`
      // records, and the directory the config resolves it to holds no marker,
      // so it is somebody's package and is read like any other dependency. It
      // sorts last, so naming it cannot be the sort talking.
      final dir = _project(
        'name: demo\ndependencies:\n'
        '  goo2d: ^0.3.0\n'
        '  zed_bundle: ^1.0.0\n\n'
        'good:\n  bundle: zed_bundle\n',
        <String>[],
      );
      resolvePackages(dir, <String, List<String>>{
        'zed_bundle': <String>['goo2d'],
        'goo2d': <String>['good'],
        'good': <String>[],
      });
      expect(
        enginePackageOf(dir),
        'zed_bundle',
        reason:
            "nothing on disk says the directory is good's, and the name it "
            'happens to carry is not evidence - the same argument that took '
            '#305 and #309 off names',
      );
    });

    test(
      'two runs with a resolve between them leave a bundle that does not '
      'depend on itself',
      () async {
        final dir = _project(
          'name: demo\ndependencies:\n  goo2d: ^0.3.0\n\n'
          'good:\n  assets:\n    - assets/\n',
          <String>['assets/player.png'],
        );
        resolvePackages(dir, engineGraph);

        await runGenerate(
          projectDir: dir,
          command: 'good generate',
          out: _quiet,
          verbose: _quiet,
          pubGet: false,
        );

        // What `flutter pub get` does with the dependency that run added:
        // demo_bundle resolves to the directory it wrote, marker and all.
        resolvePackages(
          dir,
          engineGraph,
          at: <String, Directory>{
            'demo_bundle': Directory('${dir.path}/demo_bundle'),
          },
        );

        await runGenerate(
          projectDir: dir,
          command: 'good generate',
          out: _quiet,
          verbose: _quiet,
          pubGet: false,
        );

        final pubspec = File('${dir.path}/demo_bundle/pubspec.yaml');
        final doc = loadYaml(pubspec.readAsStringSync()) as YamlMap;
        final dependencies = doc['dependencies'] as YamlMap;
        expect(
          dependencies.keys,
          isNot(contains('demo_bundle')),
          reason:
              '`pub get` answers "A package may not list itself as a '
              'dependency" and refuses the whole project, so the second '
              '`good generate` on any resolved project failed here',
        );
        expect(
          dependencies.keys,
          containsAll(<String>['goo2d', 'good']),
          reason:
              'the entry package and the packages the generated files import '
              'are still what the bundle asks for',
        );
        expect(
          File('${dir.path}/demo_bundle/lib/textures.dart').readAsStringSync(),
          contains("import 'package:goo2d/goo2d.dart';"),
        );
      },
    );
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

    test('starts the game before showing it', () async {
      final files = scaffoldFiles(
        projectName: 'demo',
        engine: GoodEngine.twoD,
        command: 'good create',
      );
      final main = files['lib/main.dart']!;
      expect(
        main,
        contains('await Game.start(DemoGame.new)'),
        reason:
            'GameView needs a camera from a *running* game - this template '
            'shipped broken until it was compiled against the real API. The '
            'constructor and not an instance: Game.start builds the game so '
            'that a Channel.* or Input.of on one of its fields has a window '
            'to declare into, and a substring check for Game.start alone '
            'would pass on the retired spelling',
      );
      expect(main, contains('GameView(camera:'));
      expect(
        main,
        contains('_starting.then((game) => game.stop())'),
        reason:
            'the game owns an isolate and native memory, and Game.start is '
            'what builds it - so there is no instance to stop until the '
            'future completes, and a widget disposed mid-start has to stop '
            'it through the future or leak the isolate',
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

    test('a prefab is the field that holds it, and says so with @sub', () {
      for (final engine in GoodEngine.values) {
        final files = scaffoldFiles(
          projectName: 'demo',
          engine: engine,
          command: 'good create',
        );
        expect(
          files['lib/game/scenes/main_scene.dart'],
          contains('@sub\n  final player = Player();'),
          reason:
              'a bare constructor call tells a reader nothing on its own, so '
              'the marker is what says the line declares a prefab. Without it '
              'the field holds a spare Player, the scene registers no '
              'archetype, and the project still analyzes clean - which is why '
              'scaffold_analyze_test cannot stand in for this one',
        );
        expect(
          files['lib/game/scenes/main_scene.dart'],
          isNot(contains('descriptor.has(')),
          reason: 'the descriptor window a prefab needed is gone',
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
        contains('eye.cameraView[camera] ='),
        reason: 'a camera occupying no view is a camera nothing would show',
      );
    });

    test('declares the composition pass nothing else declares', () {
      expect(
        files()['lib/game/demo_game.dart'],
        contains('WorldTransform3DSystem.new'),
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
      expect(patched[3], '  goo2d: $engineConstraint');
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
            .map((line) => line == '  goo2d: $engineConstraint' ? edit : line)
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
          if (line == '  goo2d: $engineConstraint')
            '  # pinned deliberately, see #123',
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
good:
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
good:
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
    test('fails rather than dropping an asset Flutter will not bundle', () async {
      final dir = _project(_pubspecWithAssets, <String>[
        'assets/player.png',
        'assets/ui/button.png',
      ]);
      await expectLater(
        () => runGenerate(
          projectDir: dir,
          command: 'good generate',
          out: _quiet,
          verbose: _quiet,
          pubGet: false,
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
        Directory('${dir.path}/demo_bundle').existsSync(),
        isFalse,
        reason: 'it stops before writing an enum that is missing a value',
      );
    });

    test('fails rather than generating over a shadowed column', () async {
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
      await expectLater(
        () => runGenerate(
          projectDir: dir,
          command: 'good generate',
          out: _quiet,
          verbose: _quiet,
          pubGet: false,
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
        Directory('${dir.path}/demo_bundle').existsSync(),
        isFalse,
        reason: 'it stops before writing anything',
      );
    });

    test('fails rather than generating over a broken describeX chain', () async {
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
      await expectLater(
        () => runGenerate(
          projectDir: dir,
          command: 'good generate',
          out: _quiet,
          verbose: _quiet,
          pubGet: false,
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
        Directory('${dir.path}/demo_bundle').existsSync(),
        isFalse,
        reason: 'it stops before writing anything',
      );
    });

    test('writes the enum when every asset is bundled', () async {
      final dir = _project(
        '''
name: demo
good:
  assets:
    - assets/
    - assets/ui/
''',
        <String>['assets/player.png', 'assets/ui/button.png'],
      );
      await runGenerate(
        projectDir: dir,
        command: 'good generate',
        out: _quiet,
        verbose: _quiet,
        pubGet: false,
      );
      final textures = File(
        '${dir.path}/demo_bundle/lib/textures.dart',
      ).readAsStringSync();
      expect(textures, contains("uiButton('assets/ui/button.png'"));
    });
  });

  group('texture sizes', () {
    test('an enum value carries the size read from the image header', () {
      final dir = _projectWithImages(_pubspecWithAssets, <String, List<int>>{
        'assets/sheet.png': <int>[512, 256],
      });
      expect(
        emitTextures(
          scanAssets(dir),
          command: 'good generate',
          drawsTextures: true,
        ),
        contains("sheet('assets/sheet.png', 512, 256)"),
        reason:
            'the numbers are in the file and nowhere else - restating them at '
            'a call site is what re-exporting art at a new size then has to '
            'go and find',
      );
    });

    test('the size class holds constants, not enum members', () {
      // The whole point of the second form. Instance-field access is never a
      // constant expression, so `Textures.sheet.width` cannot appear in the
      // `static const List<SpriteFrame>` the rendering guide teaches; a
      // `static const int` can.
      final source = emitTextures(
        scanAssets(
          _projectWithImages(_pubspecWithAssets, <String, List<int>>{
            'assets/sheet.png': <int>[512, 256],
          }),
        ),
        command: 'good generate',
        drawsTextures: true,
      );
      expect(source, contains('abstract final class TextureSize'));
      expect(source, contains('static const int sheetWidth = 512;'));
      expect(source, contains('static const int sheetHeight = 256;'));
      expect(
        source.indexOf('abstract final class TextureSize'),
        greaterThan(source.indexOf('enum Textures')),
        reason:
            'enum values and static members share one namespace, so the '
            'constants have to be a separate declaration - a texture named '
            'sheet_width.png would otherwise land on sheetWidth',
      );
    });

    test('width and height are told apart', () {
      // A generator that wrote the width twice, or read one field for both,
      // passes on a square image.
      final source = emitTextures(
        scanAssets(
          _projectWithImages(_pubspecWithAssets, <String, List<int>>{
            'assets/tall.png': <int>[3, 97],
          }),
        ),
        command: 'good generate',
        drawsTextures: true,
      );
      expect(source, contains("tall('assets/tall.png', 3, 97)"));
      expect(source, contains('static const int tallWidth = 3;'));
      expect(source, contains('static const int tallHeight = 97;'));
    });

    test('a file whose header says nothing generates 0, not a guess', () {
      final dir = _project(_pubspecWithAssets, <String>['assets/broken.png']);
      final source = emitTextures(
        scanAssets(dir),
        command: 'good generate',
        drawsTextures: true,
      );
      expect(source, contains("broken('assets/broken.png', 0, 0)"));
      expect(source, contains('static const int brokenWidth = 0;'));
    });

    test('sizes are emitted where the payload is Object? too', () {
      // A project that cannot draw still ships images, and a pixel dimension
      // is an int that names no engine type.
      final source = emitTextures(
        scanAssets(
          _projectWithImages(_pubspecWithAssets, <String, List<int>>{
            'assets/sheet.png': <int>[512, 256],
          }),
        ),
        command: 'good generate',
        drawsTextures: false,
      );
      expect(source, contains('LocalEnumAssetKey<Object?>'));
      expect(source, contains('static const int sheetWidth = 512;'));
    });

    test('audio gets no dimensions', () {
      final source = emitAudios(
        scanAssets(
          _project(_pubspecWithAssets, <String>['assets/theme.ogg']),
        ),
        command: 'good generate',
      );
      expect(source, contains("theme('assets/theme.ogg')"));
      expect(source, isNot(contains('TextureSize')));
      expect(
        source,
        isNot(contains('final int width;')),
        reason: 'a sound has no canvas, and the emitter is shared',
      );
    });

    test('a project with no images still declares the size class', () {
      final source = emitTextures(
        scanAssets(_project('name: demo\n', <String>[])),
        command: 'good generate',
        drawsTextures: true,
      );
      expect(
        source,
        contains('abstract final class TextureSize'),
        reason:
            'the name has to resolve from the first run, the same reason the '
            'empty Textures class exists at all',
      );
    });

    test('a texture named width collides with the field every one carries', () {
      // `duplicate_definition` points at two lines of a generated file and
      // names no asset. This has to fail here, where the message can.
      final dir = _project(_pubspecWithAssets, <String>['assets/width.png']);
      expect(
        () => scanAssets(dir),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('assets/width.png'), contains('Rename')),
          ),
        ),
      );
    });

    test('a name that merely ends in Width is a texture like any other', () {
      // The reserved set is two basenames and does not grow with what a
      // project ships. A check written as a pattern over identifiers would
      // reject this one.
      final dir = _projectWithImages(_pubspecWithAssets, <String, List<int>>{
        'assets/sheet_width.png': <int>[8, 4],
      });
      expect(
        emitTextures(
          scanAssets(dir),
          command: 'good generate',
          drawsTextures: true,
        ),
        contains("sheetWidth('assets/sheet_width.png', 8, 4)"),
      );
    });

    test('an audio file named width is not reserved', () {
      // The fields are on the texture enum. Audios and Textures are separate
      // types, the same reason click.png and click.ogg do not collide.
      final dir = _project(_pubspecWithAssets, <String>['assets/width.ogg']);
      expect(scanAssets(dir).audio.single.identifier, 'width');
    });
  });

  group('enginePackageDrawsTextures', () {
    test('the entry package that declares Texture draws', () {
      expect(
        enginePackageDrawsTextures(
          _graph(<String, List<String>>{
            'goo2d': <String>['good'],
            'good': <String>[],
          }),
          'goo2d',
        ),
        isTrue,
      );
    });

    test('a renderer built on goo2d draws, though it is not named goo2d', () {
      // #312: the payload type was chosen by comparing the entry package's
      // name to 'goo2d', so a renderer somebody else publishes on top of
      // goo2d got Object? for keys whose payload is a Texture.
      expect(
        enginePackageDrawsTextures(
          _graph(<String, List<String>>{
            'neon': <String>['goo2d'],
            'goo2d': <String>['good'],
            'good': <String>[],
          }),
          'neon',
        ),
        isTrue,
        reason:
            'neon reaches goo2d, which is where Texture is declared, so its '
            'texture keys carry a payload type',
      );
    });

    test('an engine package that never reaches goo2d does not draw', () {
      // goo3d depends on good and never on goo2d, so naming Texture in a 3D
      // project puts `Texture isn't a type` into its first flutter analyze.
      expect(
        enginePackageDrawsTextures(
          _graph(<String, List<String>>{
            'goo3d': <String>['good'],
            'good': <String>[],
          }),
          'goo3d',
        ),
        isFalse,
      );
      expect(
        enginePackageDrawsTextures(
          _graph(<String, List<String>>{
            'good': <String>[],
          }),
          'good',
        ),
        isFalse,
        reason: 'the kernel has no renderer either',
      );
    });

    test('the walk is transitive, not one hop', () {
      expect(
        enginePackageDrawsTextures(
          _graph(<String, List<String>>{
            'studio_kit': <String>['neon'],
            'neon': <String>['goo2d'],
            'goo2d': <String>['good'],
            'good': <String>[],
          }),
          'studio_kit',
        ),
        isTrue,
      );
    });

    test('a dev dependency on goo2d is not a draw', () {
      final dir = testTempDir('good_cli_graph');
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
      final root = Directory('${dir.path}/packages/tool')
        ..createSync(recursive: true);
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: tool\ndev_dependencies:\n  goo2d: ^1.0.0\n',
      );
      File('${dir.path}/.dart_tool/package_config.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          '{ "configVersion": 2, "packages": [ { "name": "tool", '
          '"rootUri": "../packages/tool", "packageUri": "lib/" } ] }',
        );
      expect(
        enginePackageDrawsTextures(dir, 'tool'),
        isFalse,
        reason:
            "a dev dependency is not on lib/'s import path, so the generated "
            'file could not name Texture through it',
      );
    });

    test('the resolved entry package is the one asked about', () {
      // The two halves in sequence: #309 picks the entry package out of the
      // graph, #312 asks that package whether it draws. Each half is checked
      // on its own above and in `enginePackageOf`, and neither says what the
      // pair answers for a project built on a renderer nobody here has heard
      // of - which is the project both changes exist for.
      final dir = _project(
        'name: demo\ndependencies:\n  neon: ^0.1.0\n  goo2d: ^0.3.0\n',
        <String>[],
      );
      resolvePackages(dir, <String, List<String>>{
        'neon': <String>['goo2d'],
        'goo2d': <String>['good'],
        'good': <String>[],
      });
      final package = enginePackageOf(dir);
      expect(package, 'neon', reason: 'goo2d is what neon is built on');
      expect(
        rendererPayloadType(
          enginePackageDrawsTextures(dir, package),
          'Texture',
        ),
        'Texture',
      );
    });

    test('an unresolved project answers Object?, not a name that fails', () {
      // No package config, so nothing says what the renderer is built on.
      // Object? compiles; `Texture` would not resolve.
      final dir = testTempDir('good_cli_graph');
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
      expect(enginePackageDrawsTextures(dir, 'neon'), isFalse);
      expect(
        enginePackageDrawsTextures(dir, 'goo2d'),
        isTrue,
        reason:
            'goo2d is where Texture is declared, and that needs no graph - '
            'which is what keeps `good create` working before its first '
            'pub get',
      );
    });
  });

  group('what the generated files import', () {
    test('an entry package that re-exports nothing is not imported', () async {
      // #316. A project declaring a physics backend and goo2d has two engine
      // candidates; #309 drops goo2d as the less specific of the two, so the
      // entry package is the backend - whose library exports its own `src/`
      // and re-exports neither goo2d nor the kernel. Naming every type
      // through it stopped resolving at `AssetKey`, so every asset kind broke
      // and not the textures alone.
      final dir = _project(
        'name: demo\n'
        'dependencies:\n'
        '  demo_physics: ^0.1.0\n'
        '  goo2d: ^0.3.0\n\n'
        'good:\n  assets:\n    - assets/\n',
        <String>['assets/player.png', 'assets/theme.ogg'],
      );
      resolvePackages(dir, <String, List<String>>{
        'demo_physics': <String>['goo2d'],
        'goo2d': <String>['good'],
        'good': <String>[],
      });

      expect(
        enginePackageOf(dir),
        'demo_physics',
        reason: 'goo2d is what the backend is built on, so it is dropped',
      );

      await runGenerate(
        projectDir: dir,
        command: 'good generate',
        out: _quiet,
        verbose: _quiet,
        pubGet: false,
      );

      final lib = '${dir.path}/demo_bundle/lib';
      final textures = File('$lib/textures.dart').readAsStringSync();
      final audios = File('$lib/audios.dart').readAsStringSync();
      final readiness = File('$lib/good.dart').readAsStringSync();

      for (final source in <String>[textures, audios, readiness]) {
        expect(
          source,
          isNot(contains('demo_physics')),
          reason: 'nothing generated names a type the backend declares',
        );
      }
      expect(textures, contains("import 'package:goo2d/goo2d.dart';"));
      expect(textures, contains('LocalEnumAssetKey<Texture>'));
      expect(audios, contains("import 'package:good/good.dart';"));
      expect(readiness, contains("import 'package:good/good.dart';"));
    });

    test('the bundle declares every package the generated files import', () async {
      // An import the bundle's pubspec does not name is what
      // `depend_on_referenced_packages` reports, and `flutter analyze` fails a
      // project on an info.
      final dir = _project(
        'name: demo\n'
        'dependencies:\n'
        '  demo_physics: ^0.1.0\n\n'
        'good:\n  assets:\n    - assets/\n',
        <String>['assets/player.png'],
      );
      resolvePackages(dir, <String, List<String>>{
        'demo_physics': <String>['goo2d'],
        'goo2d': <String>['good'],
        'good': <String>[],
      });
      await runGenerate(
        projectDir: dir,
        command: 'good generate',
        out: _quiet,
        verbose: _quiet,
        pubGet: false,
      );
      final pubspec = File(
        '${dir.path}/demo_bundle/pubspec.yaml',
      ).readAsStringSync();
      expect(pubspec, matches(RegExp(r'^  good:', multiLine: true)));
      expect(pubspec, matches(RegExp(r'^  goo2d:', multiLine: true)));
      expect(
        pubspec,
        matches(RegExp(r'^  demo_physics:', multiLine: true)),
        reason: 'the entry package is the version the project asked for',
      );
    });

    test('a project that cannot draw declares and imports the kernel', () async {
      // The other half of the same question: `Object?` on the keys, and the
      // kernel names still have to come from somewhere.
      final dir = _project(
        'name: demo\n'
        'dependencies:\n'
        '  goo3d: ^0.1.0\n\n'
        'good:\n  assets:\n    - assets/\n',
        <String>['assets/player.png'],
      );
      resolvePackages(dir, <String, List<String>>{
        'goo3d': <String>['good'],
        'good': <String>[],
      });
      await runGenerate(
        projectDir: dir,
        command: 'good generate',
        out: _quiet,
        verbose: _quiet,
        pubGet: false,
      );
      final textures = File(
        '${dir.path}/demo_bundle/lib/textures.dart',
      ).readAsStringSync();
      expect(textures, contains("import 'package:good/good.dart';"));
      expect(textures, contains('LocalEnumAssetKey<Object?>'));
      expect(textures, isNot(contains('goo2d')));
      expect(
        File('${dir.path}/demo_bundle/pubspec.yaml').readAsStringSync(),
        isNot(matches(RegExp(r'^  goo2d:', multiLine: true))),
        reason: 'a project with no renderer depends on none',
      );
    });
  });
}
