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

// `--no-pub-get` on every one of these. The projects below are the smallest
// thing the build commands will accept and not resolvable Flutter apps, so a
// real `flutter pub get` in one fails on its own terms and says nothing about
// what these tests are asking.
ProcessResult _good(Directory project, List<String> args) => GoodCli.instance
    .run(<String>[...args, '--project-dir', project.path, '--no-pub-get']);

void main() {
  tearDownAll(GoodCli.disposeAll);

  test(
    'a release build does not delete assets from the project source tree',
    () {
      // probe.png lives directly in assets/ with no matching file in assets_src/.
      // It is an "original" the CLI cannot rebuild. strip-originals defaults to
      // false, so the build must leave it alone.
      //
      // On master before this fix the guard refused to pack at all when it found
      // any such original, so chunk_root.dat was never written. After the fix
      // packing runs and the file survives untouched.
      final project = _project(); // strip-originals: false
      File('${project.path}/assets/probe.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([0]); // one byte - just needs to be on disk

      final build = _good(project, <String>['build', 'windows']);
      final log = '${build.stdout}${build.stderr}';

      // Packing must have run. The chunk is the evidence.
      expect(
        File('${project.path}/assets/packed/chunk_root.dat').existsSync(),
        isTrue,
        reason:
            'packing has to have run before the strip can matter; if the '
            'chunk is absent the build stopped early:\n$log',
      );

      // The source file must survive so Image.asset can resolve it.
      // Flutter bundles assets/ untouched; if this file is gone the path
      // throws in release.
      expect(
        File('${project.path}/assets/probe.png').existsSync(),
        isTrue,
        reason:
            'the build deleted a hand-placed asset from the source tree; '
            'Image.asset("assets/probe.png") needs it there:\n$log',
      );
    },
  );

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
    test('is left alone when strip-originals is not set', () {
      // With the default strip-originals: false the build packs everything but
      // does not strip anything from assets/. handmade.png has no source file
      // so compaction cannot rebuild it, but that no longer stops the build:
      // it stays on disk so Image.asset can still resolve it from the Flutter
      // bundle.
      final project = _project();
      _image('${project.path}/assets_src/player.png', 'red', '64x64');
      _image('${project.path}/assets/handmade.png', 'yellow', '16x16');

      final build = _good(project, <String>['build', 'windows']);
      final log = '${build.stdout}${build.stderr}';

      // Packing must have run (flutter stub then fails, so exit 70 is normal).
      expect(
        File('${project.path}/assets/packed/chunk_root.dat').existsSync(),
        isTrue,
        reason: 'packing must have run:\n$log',
      );
      // The file must survive untouched.
      expect(
        File('${project.path}/assets/handmade.png').existsSync(),
        isTrue,
        reason:
            'no source can rebuild it, so the build must not delete it; '
            'Image.asset needs it in assets/:\n$log',
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

    test('is kept on disk when strip-originals is not set', () {
      // With the default strip-originals: false the build packs but does not
      // strip. Both compaction outputs stay in assets/ so Image.asset can
      // reach them, even though they are also inside the chunk.
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
      // With strip-originals: false nothing is removed from the source tree.
      expect(
        File('${project.path}/assets/player.webp').existsSync(),
        isTrue,
        reason:
            'strip-originals: false must not touch assets/; '
            'Image.asset("assets/player.webp") needs the file there:\n$log',
      );
    }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');
  });
}
