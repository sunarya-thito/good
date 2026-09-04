@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '_cli.dart';
import '_temp.dart';

// `good build` end to end, over the tree it is packing.
//
// A build reads `good: assets:` for what to pack and writes chunks into the
// packed directory. It deletes nothing on the way, and that is now structural
// rather than a default: `flutter: assets:` decides what ships in the clear,
// so a plaintext copy in a bundle is a line to remove from that list and never
// a file for a build to go and delete behind someone's back. These tests are
// what the deleted stripper protected, stated the other way round.
//
// The `flutter build` at step 4 runs against a stub that fails at once - see
// GoodCli - so an exit code of 70 says nothing on its own. What separates the
// cases here is whether the chunk was written and whether the file survived.

bool get _hasFfmpeg {
  try {
    return Process.runSync('ffmpeg', <String>['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Directory _project({String flavors = ''}) {
  final dir = testTempDir('good_build_assets');
  Directory('${dir.path}/assets_src').createSync(recursive: true);
  Directory('${dir.path}/assets/packed').createSync(recursive: true);
  File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: build_assets_probe
environment:
  sdk: ^3.5.0

dependencies:
  goo2d: ^0.1.0

good:
$flavors  assets:
    - assets/

flutter:
  uses-material-design: true

  assets:
    - assets/
    - assets/packed/
''');
  return dir;
}

/// The project's `flutter: assets:`, as Flutter's own parser reads it.
List<Object?> _flutterAssets(Directory project) {
  final doc =
      loadYaml(File('${project.path}/pubspec.yaml').readAsStringSync())
          as YamlMap;
  return ((doc['flutter'] as YamlMap)['assets'] as YamlList).toList();
}

/// A real image, so compaction has something it can actually convert.
void _image(String path, String colour, String size) {
  File(path).parent.createSync(recursive: true);
  final result = Process.runSync('ffmpeg', <String>[
    '-loglevel',
    'error',
    '-y',
    '-f',
    'lavfi',
    '-i',
    'color=c=$colour:s=$size:d=1',
    '-frames:v',
    '1',
    path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg could not write $path: ${result.stderr}');
  }
}

// `--no-pub-get` on every one of these. The projects below are the smallest
// thing the build commands will accept and not resolvable Flutter apps, so a
// real `flutter pub get` in one fails on its own terms and says nothing about
// what these tests are asking.
ProcessResult _good(Directory project, List<String> args) => GoodCli.instance
    .run(<String>[...args, '--project-dir', project.path, '--no-pub-get']);

void main() {
  test('a release build packs what good: assets: names', () {
    // probe.png lives directly in assets/ with no matching file in
    // assets_src/, so compaction cannot rebuild it. That used to be a reason
    // to refuse to pack at all, and then a reason to delete it; it is now
    // neither, and the chunk is the evidence packing ran.
    final project = _project();
    File('${project.path}/assets/probe.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([0]); // one byte - just needs to be on disk

    final build = _good(project, <String>['build', 'windows']);
    final log = '${build.stdout}${build.stderr}';

    expect(
      File('${project.path}/assets/packed/chunk_root.dat').existsSync(),
      isTrue,
      reason: 'the build stopped before packing:\n$log',
    );
    expect(
      File('${project.path}/assets/probe.png').existsSync(),
      isTrue,
      reason:
          'the build deleted a hand-placed asset from the source tree; '
          'nothing in the pipeline may do that:\n$log',
    );
  });

  test('a release build leaves the whole asset directory where it is', () {
    // One asset built from a source file, one placed straight into the asset
    // directory. Both are declared, so both are packed, and both survive.
    final project = _project();
    _image('${project.path}/assets_src/player.png', 'red', '64x64');
    _image('${project.path}/assets/handmade.png', 'yellow', '16x16');

    final build = _good(project, <String>['build', 'windows']);
    final log = '${build.stdout}${build.stderr}';

    expect(
      File('${project.path}/assets/packed/chunk_root.dat').existsSync(),
      isTrue,
      reason: 'the build stopped before packing:\n$log',
    );
    final loose =
        Directory('${project.path}/assets')
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((name) => !name.startsWith('.'))
            .toList()
          ..sort();
    expect(
      loose,
      <String>['handmade.png', 'player.webp'],
      reason:
          'packing writes chunks and removes nothing, compaction output and '
          'hand-placed file alike:\n$log',
    );
  }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');

  test('a build gates the two copies on different flavors', () {
    // The mechanism that replaced stripping, end to end. The originals and
    // the chunks hold the same bytes; gated, no single build carries both, and
    // Flutter's own bundler is what leaves one out.
    final project = _project();
    File('${project.path}/assets/probe.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([0]);

    final build = _good(project, <String>['build', 'windows']);
    expect(_flutterAssets(project), <Object?>[
      <String, Object?>{
        'path': 'assets/',
        'flavors': <String>['dev'],
      },
      <String, Object?>{
        'path': 'assets/packed/',
        'flavors': <String>['prod'],
      },
    ], reason: '${build.stdout}${build.stderr}');
  });

  test('a release build refuses a flavor that ships the originals', () {
    // Bundling into chunks and then bundling the flavor that ships the loose
    // files would build every chunk and ship none of them. Silent otherwise:
    // the build succeeds and the game fails at its first asset load.
    final project = _project(
      flavors: '  flavors:\n    development: raw\n    production: bundled\n',
    );
    File('${project.path}/assets/probe.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([0]);

    final build = _good(project, <String>[
      'build',
      'windows',
      '--flavor',
      'development',
    ]);
    final log = '${build.stdout}${build.stderr}';
    expect(log, contains('development'));
    expect(log, contains('production'));
    expect(
      File('${project.path}/assets/packed/chunk_root.dat').existsSync(),
      isFalse,
      reason: 'it should refuse before packing anything:\n$log',
    );
  });

  test('a build says nothing about stripping anything', () {
    // The mechanism is gone. A message about it would be the comment that
    // outlives its code, which is what #270 was.
    final project = _project();
    _image('${project.path}/assets_src/player.png', 'red', '64x64');

    final build = _good(project, <String>['build', 'windows']);
    final log = '${build.stdout}${build.stderr}';
    expect(log, isNot(contains('strip')));
    expect(log, isNot(contains('cannot be rebuilt')));
  }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');
}
