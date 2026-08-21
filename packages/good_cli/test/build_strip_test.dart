@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import '_cli.dart';

// `good build` end to end, as far as the strip.
//
// The unit tests in strip_test.dart pin what `stripLoose` does with the set it
// is given. This one pins *which set the build hands it*, which is where the
// double-ship lived: packing takes every declared asset, and stripping used to
// remove only the files compaction had generated, so anything placed in the
// asset directory by hand shipped twice - once inside the chunk and once loose
// in plaintext.
//
// A build only reaches the strip when every packed file is one compaction can
// build again, or when the project set `strip-originals: true`. The refusal
// that guards the other case is at the bottom of this file.
//
// The `flutter build` at step 4 runs against a stub that fails at once - see
// GoodCli, so an exit code of 70 says nothing on its own about the strip. What
// separates the cases here is whether the chunk was written and whether the
// file survived.

bool get _hasFfmpeg {
  try {
    return Process.runSync('ffmpeg', <String>['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Directory _project({bool stripOriginals = false}) {
  final dir = Directory.systemTemp.createTempSync('good_build_strip');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  Directory('${dir.path}/assets_src').createSync(recursive: true);
  Directory('${dir.path}/assets/packed').createSync(recursive: true);
  const optInBlock = '''
good:
  assets:
    strip-originals: true

''';
  final optIn = stripOriginals ? optInBlock : '';
  File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: build_strip_probe
environment:
  sdk: ^3.5.0

${optIn}dependencies:
  goo2d: ^0.1.0

flutter:
  uses-material-design: true

  assets:
    - assets/
    - assets/packed/
''');
  return dir;
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

ProcessResult _good(Directory project, List<String> args) =>
    GoodCli.instance.run(<String>[...args, '--project-dir', project.path]);

void main() {
  tearDownAll(GoodCli.disposeAll);
  test('a release build leaves no asset both packed and loose', () {
    // Opted in, because the hand-placed file is the whole point of the test
    // and the default now refuses it. See the refusal group below.
    final project = _project(stripOriginals: true);
    // One asset that comes from a source file, and one placed straight into
    // the asset directory. Both are declared, so both are packed.
    _image('${project.path}/assets_src/player.png', 'red', '64x64');
    _image('${project.path}/assets/handmade.png', 'yellow', '16x16');

    final build = _good(project, <String>['build', 'windows']);
    final log = '${build.stdout}${build.stderr}';

    final chunk = File('${project.path}/assets/packed/chunk_root.dat');
    expect(
      chunk.existsSync(),
      isTrue,
      reason: 'packing has to have run for the strip to matter:\n$log',
    );

    final loose = Directory('${project.path}/assets')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => !name.startsWith('.'))
        .toList();
    expect(
      loose,
      isEmpty,
      reason:
          'every one of these is inside chunk_root.dat as well, so a release '
          'ships it twice and one of the copies is readable:\n$log',
    );
  }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');

  test('the build names the stripped files it cannot rebuild', () {
    final project = _project(stripOriginals: true);
    _image('${project.path}/assets_src/player.png', 'red', '64x64');
    _image('${project.path}/assets/handmade.png', 'yellow', '16x16');

    final build = _good(project, <String>['build', 'windows']);
    final log = '${build.stdout}${build.stderr}';

    expect(
      log,
      contains('assets/handmade.png'),
      reason:
          'compaction did not produce it, so deleting it silently would be '
          'the last anyone saw of it:\n$log',
    );
    expect(log, isNot(contains('assets/player.webp')));
  }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');

  group('an original compaction cannot rebuild', () {
    test('stops the build and leaves the file alone', () {
      final project = _project();
      _image('${project.path}/assets_src/player.png', 'red', '64x64');
      _image('${project.path}/assets/handmade.png', 'yellow', '16x16');

      final build = _good(project, <String>['build', 'windows']);
      final log = '${build.stdout}${build.stderr}';

      expect(build.exitCode, 70, reason: log);
      expect(
        File('${project.path}/assets/handmade.png').existsSync(),
        isTrue,
        reason:
            'no source can build it again, so a build that deletes it has '
            'destroyed the only copy:\n$log',
      );
      // The stub flutter fails too, so 70 alone does not say which refusal
      // this was. An unwritten chunk does: the guard runs before packing.
      expect(
        File('${project.path}/assets/packed/chunk_root.dat').existsSync(),
        isFalse,
        reason: 'it should stop before packing anything:\n$log',
      );
      expect(log, contains('assets/handmade.png'));
      expect(
        log,
        contains('assets_src/'),
        reason: 'one of the two ways out has to be named:\n$log',
      );
      expect(
        log,
        contains('strip-originals: true'),
        reason: 'and so does the other:\n$log',
      );
    }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');

    test('strips it when the project opts in', () {
      final project = _project(stripOriginals: true);
      _image('${project.path}/assets_src/player.png', 'red', '64x64');
      _image('${project.path}/assets/handmade.png', 'yellow', '16x16');

      final build = _good(project, <String>['build', 'windows']);
      final log = '${build.stdout}${build.stderr}';

      expect(
        File('${project.path}/assets/handmade.png').existsSync(),
        isFalse,
        reason: 'the project asked for exactly this:\n$log',
      );
      expect(
        File('${project.path}/assets/packed/chunk_root.dat').existsSync(),
        isTrue,
        reason: 'and the build got past packing to do it:\n$log',
      );
      expect(log, isNot(contains('cannot be rebuilt')));
    }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');

    test('is not mentioned when every packed file is regenerable', () {
      final project = _project();
      _image('${project.path}/assets_src/player.png', 'red', '64x64');
      _image('${project.path}/assets_src/sheet.png', 'green', '32x32');

      final build = _good(project, <String>['build', 'windows']);
      final log = '${build.stdout}${build.stderr}';

      expect(
        log,
        isNot(contains('cannot be rebuilt')),
        reason: 'compaction produced both, so nothing is at risk:\n$log',
      );
      expect(
        File('${project.path}/assets/packed/chunk_root.dat').existsSync(),
        isTrue,
        reason: log,
      );
      final loose = Directory('${project.path}/assets')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((name) => !name.startsWith('.'))
          .toList();
      expect(loose, isEmpty, reason: 'both are inside the chunk now:\n$log');
    }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');
  });
}
