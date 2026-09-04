@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:test/test.dart';

import '_cli.dart';
import '_temp.dart';

// What the shell sees.
//
// Every one of these commands already printed the right thing when it failed.
// What it did not do was exit non-zero, so `good build windows && upload`
// uploaded, and a CI step wrapped around a broken build went green. These
// tests assert the code and nothing else - asserting the message could never
// have caught this, because the message was always right.
//
// 70 is EX_SOFTWARE: the command ran, understood its input, and could not
// finish. 64 is a malformed command line, 65 something it read being wrong.

const int ok = 0;
const int exUsage = 64;
const int exDataErr = 65;
const int exSoftware = 70;

bool get _hasFfmpeg {
  try {
    return Process.runSync('ffmpeg', <String>['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Directory _tempDir() {
  final dir = testTempDir('good_exit');
  return dir;
}

/// A project good can work on. [packedDeclared] is off for the one test that
/// needs packing to refuse.
Directory _project({bool packedDeclared = true}) {
  final dir = _tempDir();
  Directory('${dir.path}/assets_src').createSync(recursive: true);
  Directory('${dir.path}/assets/packed').createSync(recursive: true);
  final packed = packedDeclared ? '    - assets/packed/\n' : '';
  File('${dir.path}/pubspec.yaml').writeAsStringSync(
    'name: exit_probe\n'
    'environment:\n'
    '  sdk: ^3.5.0\n'
    '\n'
    'good:\n'
    '  assets:\n'
    '    - assets/\n'
    '\n'
    'flutter:\n'
    '  uses-material-design: true\n'
    '\n'
    '  assets:\n'
    '    - assets/\n'
    '$packed',
  );
  return dir;
}

/// A real image, so compaction succeeds.
void _image(String path) {
  File(path).parent.createSync(recursive: true);
  final result = Process.runSync('ffmpeg', <String>[
    '-loglevel',
    'error',
    '-y',
    '-f',
    'lavfi',
    '-i',
    'color=c=red:s=32x32:d=1',
    '-frames:v',
    '1',
    path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg could not write $path: ${result.stderr}');
  }
}

/// A file ffmpeg cannot convert, so compaction reports a failure.
void _notAnImage(String path) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('this is not a png');
}

int _run(List<String> args) => GoodCli.instance.run(args).exitCode;

void main() {
  final needsFfmpeg = _hasFfmpeg ? null : 'ffmpeg is not installed';

  group('good build', () {
    test('exits 70 when flutter build fails', () {
      final dir = _project();
      _image('${dir.path}/assets_src/player.png');
      // Step 4 runs the stub flutter from _cli.dart, which fails at once.
      expect(
        _run(<String>['build', 'windows', '--project-dir', dir.path, '--no-pub-get']),
        exSoftware,
      );
    }, skip: needsFfmpeg);

    test('exits 70 when compaction cannot convert a file', () {
      final dir = _project();
      _notAnImage('${dir.path}/assets_src/broken.png');
      expect(
        _run(<String>['build', 'windows', '--project-dir', dir.path, '--no-pub-get']),
        exSoftware,
      );
    }, skip: needsFfmpeg);

    test('exits 70 when packing refuses', () {
      // The pubspec does not list the packed directory, so the chunks would be
      // built and never bundled. `_pack` stops before writing anything.
      final dir = _project(packedDeclared: false);
      _image('${dir.path}/assets_src/player.png');
      expect(
        _run(<String>['build', 'windows', '--project-dir', dir.path, '--no-pub-get']),
        exSoftware,
      );
    }, skip: needsFfmpeg);

    test('exits 0 for --dry-run, which is not a failure', () {
      final dir = _project();
      expect(
        _run(<String>[
          'build',
          'windows',
          '--project-dir',
          dir.path,
          '--dry-run',
        ]),
        ok,
      );
    });
  });

  group('good create', () {
    test('exits 70 without a project name', () {
      expect(_run(<String>['create']), exSoftware);
    });

    test('exits 70 for --2d and --3d together', () {
      final dir = _tempDir();
      expect(
        _run(<String>[
          'create',
          'demo',
          '--directory',
          dir.path,
          '--2d',
          '--3d',
        ]),
        exSoftware,
      );
    });

    test('exits 70 rather than writing over a directory that is there', () {
      final dir = _tempDir();
      Directory('${dir.path}/demo').createSync();
      expect(
        _run(<String>['create', 'demo', '--directory', dir.path]),
        exSoftware,
      );
    });

    test('exits 70 when --no-flutter-create has nothing to add to', () {
      final dir = _tempDir();
      expect(
        _run(<String>[
          'create',
          'demo',
          '--directory',
          dir.path,
          '--no-flutter-create',
        ]),
        exSoftware,
      );
    });

    test('exits 70 when flutter create fails', () {
      final dir = _tempDir();
      expect(
        _run(<String>['create', 'demo', '--directory', dir.path]),
        exSoftware,
      );
    });

    test('exits 0 for --dry-run', () {
      final dir = _tempDir();
      expect(
        _run(<String>['create', 'demo', '--directory', dir.path, '--dry-run']),
        ok,
      );
    });
  });

  group('good assets pack', () {
    test('exits 70 when the key material is missing', () {
      // Release plus AES needs the bundle package's asset_key.dart, and
      // nothing has generated one.
      final dir = _project();
      File('${dir.path}/assets/player.webp').writeAsStringSync('bytes');
      expect(
        _run(<String>[
          'assets',
          'pack',
          '--project-dir',
          dir.path,
          '--mode=release',
          '--encryption=aes',
        ]),
        exSoftware,
      );
    });

    test('exits 0 when there is nothing to pack', () {
      final dir = _project();
      expect(_run(<String>['assets', 'pack', '--project-dir', dir.path]), ok);
    });

    test('exits 0 for --dry-run', () {
      final dir = _project();
      File('${dir.path}/assets/player.webp').writeAsStringSync('bytes');
      expect(
        _run(<String>[
          'assets',
          'pack',
          '--project-dir',
          dir.path,
          '--dry-run',
        ]),
        ok,
      );
    });
  });

  group('good assets compact', () {
    test('exits 70 when a file will not convert', () {
      final dir = _project();
      _notAnImage('${dir.path}/assets_src/broken.png');
      expect(
        _run(<String>['assets', 'compact', '--project-dir', dir.path]),
        exSoftware,
      );
    }, skip: needsFfmpeg);

    test('exits 70 whether ffmpeg is missing or the file is bad', () {
      // --no-download turns a machine with no ffmpeg into a failure rather
      // than a download. Where ffmpeg is installed the conversion fails
      // instead. Both are the same 70, which is the point.
      final dir = _project();
      _notAnImage('${dir.path}/assets_src/art.png');
      expect(
        _run(<String>[
          'assets',
          'compact',
          '--project-dir',
          dir.path,
          '--no-download',
        ]),
        exSoftware,
      );
    });

    test('exits 0 when there is no source directory', () {
      final dir = _tempDir();
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: exit_probe\n');
      expect(
        _run(<String>['assets', 'compact', '--project-dir', dir.path]),
        ok,
      );
    });

    test('exits 0 for --dry-run', () {
      final dir = _project();
      _notAnImage('${dir.path}/assets_src/art.png');
      expect(
        _run(<String>[
          'assets',
          'compact',
          '--project-dir',
          dir.path,
          '--dry-run',
        ]),
        ok,
      );
    });
  });

  group('the other codes still mean what they meant', () {
    test('a malformed command line is 64', () {
      expect(_run(<String>['build', 'windows', '--nonsense']), exUsage);
    });

    test('an asset the pubspec will not bundle is 65', () {
      final dir = _project();
      File('${dir.path}/assets/ui/button.webp')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('bytes');
      expect(_run(<String>['generate', '--project-dir', dir.path, '--no-pub-get']), exDataErr);
    });

    test('a command that finishes is 0', () {
      final dir = _project();
      File('${dir.path}/assets/player.webp').writeAsStringSync('bytes');
      expect(_run(<String>['generate', '--project-dir', dir.path, '--no-pub-get']), ok);
    });
  });
}
