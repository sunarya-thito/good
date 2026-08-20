@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

// `good build` end to end, as far as the strip.
//
// The unit tests in strip_test.dart pin what `stripLoose` does with the set it
// is given. This one pins *which set the build hands it*, which is where the
// double-ship lived: packing takes every declared asset, and stripping used to
// remove only the files compaction had generated, so anything placed in the
// asset directory by hand shipped twice - once inside the chunk and once loose
// in plaintext.
//
// The `flutter build` at step 4 fails, and that is fine: it runs after the
// strip, and nothing here reads the exit code.

final String _repoRoot = Directory.current.path;

bool get _hasFfmpeg {
  try {
    return Process.runSync('ffmpeg', <String>['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Directory _project() {
  final dir = Directory.systemTemp.createTempSync('good_build_strip');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  Directory('${dir.path}/assets_src').createSync(recursive: true);
  Directory('${dir.path}/assets/packed').createSync(recursive: true);
  File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: build_strip_probe
environment:
  sdk: ^3.5.0

dependencies:
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

ProcessResult _good(Directory project, List<String> args) => Process.runSync(
  Platform.resolvedExecutable,
  <String>['run', 'bin/good.dart', ...args, '--project-dir', project.path],
  workingDirectory: _repoRoot,
);

void main() {
  test('a release build leaves no asset both packed and loose', () {
    final project = _project();
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
    final project = _project();
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
}
