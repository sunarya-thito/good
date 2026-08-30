@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import '_cli.dart';
import '_temp.dart';

// What keeps one file in this suite from deciding another file's result.
//
// #289: the suite failed a different set of tests on every run, and every
// failing file passed when run alone. What was actually shared was the drive.
// `dart test` runs these files as isolates of one process, eight at a time,
// and each one writes into the system temp directory - the runner its own
// kernel per suite, this suite four copies of a thirty-three megabyte compiled
// CLI that only come back if the run reaches its teardown. Fifty-seven of
// those were still on the machine when this was diagnosed, and the drive was
// down to its last gigabyte. Past that point `dart test` fails at whichever
// file happens to be writing, which is a set that moves every run and a
// failure that names no test.
//
// So what is asserted here is size and place: one build, under `.dart_tool`,
// keyed so it can never be stale, and a fixture that comes back even when the
// OS will not let go of it. `_cli.dart` and `_temp.dart` carry the rule.

void main() {
  group('the compiled CLI is built once for the run', () {
    test('a second caller reuses the kernel rather than compiling again', () {
      final first = GoodCli.sharedBuild();
      final built = File(first.snapshot).lastModifiedSync();

      final second = GoodCli.sharedBuild();

      expect(
        second.snapshot,
        first.snapshot,
        reason:
            'every file in this suite has to arrive at the same kernel; a '
            'path of its own is a compile of its own',
      );
      expect(
        File(second.snapshot).lastModifiedSync(),
        built,
        reason:
            'the file was rewritten, so the second caller compiled - which is '
            'what four files did at once before #289',
      );
    });

    test('the kernel is under .dart_tool, not in a directory of its own', () {
      // Where it lives is the mechanism. A kernel in a fresh temp directory
      // cannot be found by the next isolate however it is keyed.
      final build = GoodCli.sharedBuild();
      expect(
        build.snapshot.replaceAll(r'\', '/'),
        startsWith('.dart_tool/good_cli_test/'),
      );
      expect(
        build.snapshot.replaceAll(r'\', '/'),
        isNot(startsWith(Directory.systemTemp.path.replaceAll(r'\', '/'))),
      );
    });

    test('good keeps its own cache under that build, not the developer\'s', () {
      // Unset, `$GOOD_HOME` is the user profile, so every `good` this suite
      // starts would read and write the developer's own ffmpeg cache - and on
      // a machine with no ffmpeg on PATH, four files would race to unpack one
      // archive into one directory. `--no-download` makes good name the cache
      // it would have used instead of fetching into it.
      final cli = GoodCli.instance;
      final dir = testTempDir('good_home');
      File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: home_probe

environment:
  sdk: ^3.5.0

flutter:
  assets:
    - assets/
''');
      File('${dir.path}/assets_src/art.png')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('not really a png');

      final result = cli.run(
        <String>[
          'assets',
          'compact',
          '--project-dir',
          dir.path,
          '--no-download',
        ],
        environment: <String, String>{'PATH': cli.build.stubs},
      );

      final said = '${result.stdout}${result.stderr}';
      expect(
        said,
        contains(cli.build.home),
        reason:
            'good was told to look somewhere else and named the home it was '
            'started from instead:\n$said',
      );
    });
  });

  group('the source key', () {
    // The key is the whole safety of reusing a kernel across runs: reuse under
    // a key that missed an edit is a suite testing a CLI that no longer
    // exists, which is worse than the four compiles it replaces.
    List<File> sources(Directory dir) => <File>[
      File('${dir.path}/a.dart'),
      File('${dir.path}/b.dart'),
    ];

    Directory twoFiles() {
      final dir = testTempDir('good_key');
      File('${dir.path}/a.dart').writeAsStringSync('void main() {}\n');
      File('${dir.path}/b.dart').writeAsStringSync('const x = 1;\n');
      return dir;
    }

    test('moves when a byte of a source moves', () {
      final dir = twoFiles();
      final before = GoodCli.sourceKey(sources(dir));

      File('${dir.path}/b.dart').writeAsStringSync('const x = 2;\n');

      expect(GoodCli.sourceKey(sources(dir)), isNot(before));
    });

    test('tells a source that is absent from one that is empty', () {
      // One file on its own, because with two the path written beside each
      // one already moves the key when either is deleted - so a pair cannot
      // say whether the absent case is handled or merely covered. What needs
      // it is `pubspec_overrides.yaml`: no overrides and an empty overrides
      // file resolve differently and must not share a kernel.
      final dir = testTempDir('good_key_absent');
      final probe = File('${dir.path}/overrides.yaml');
      final absent = GoodCli.sourceKey(<File>[probe]);

      probe.writeAsStringSync('');

      expect(GoodCli.sourceKey(<File>[probe]), isNot(absent));
    });

    test('moves when the same bytes are split across other files', () {
      // The path is hashed beside the bytes. Bytes alone, two files whose
      // contents run together the same way would key the same - and moving a
      // declaration from one file into the next is exactly that.
      final dir = testTempDir('good_key_split');
      final a = File('${dir.path}/a.dart');
      final b = File('${dir.path}/b.dart');
      final files = <File>[a, b];
      a.writeAsStringSync('const x = 1;');
      b.writeAsStringSync('const y = 2;');
      final before = GoodCli.sourceKey(files);

      a.writeAsStringSync('const x = 1;const y = 2;');
      b.writeAsStringSync('');

      expect(GoodCli.sourceKey(files), isNot(before));
    });

    test('stays put when the files are listed in another order', () {
      final dir = twoFiles();
      expect(
        GoodCli.sourceKey(sources(dir).reversed.toList()),
        GoodCli.sourceKey(sources(dir)),
        reason: 'listSync order is the filesystem\'s, not the suite\'s',
      );
    });

    test('stays put when a source is only touched', () {
      // A checkout, a branch switch and a stash all rewrite modification
      // times. A key that moved for those would throw the build away several
      // times a day for nothing.
      final dir = twoFiles();
      final before = GoodCli.sourceKey(sources(dir));

      final file = File('${dir.path}/a.dart');
      file.setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));

      expect(GoodCli.sourceKey(sources(dir)), before);
    });
  });

  group('a fixture is removed without failing the test', () {
    test('an open handle in the tree is not a failure', () {
      // What a subprocess that has not quite let go looks like. Windows
      // refuses the delete outright while this handle is open; `deleteSync`
      // throws PathAccessException, and from a tearDown that is reported as
      // the test failing - a verdict on the OS's timing rather than on the
      // code. On Linux the unlink goes through and there is nothing to see,
      // which is also why CI has never shown #289.
      final dir = Directory.systemTemp.createTempSync('good_open_handle');
      final held = File('${dir.path}/held.bin')..writeAsStringSync('bytes');
      final handle = held.openSync(mode: FileMode.append);
      try {
        expect(() => removeTempDir(dir), returnsNormally);
      } finally {
        handle.closeSync();
        removeTempDir(dir);
      }
      expect(
        dir.existsSync(),
        isFalse,
        reason: 'the handle is closed now, so the retry has to take it away',
      );
    });

    test('an ordinary fixture is still taken away', () {
      // The tolerance above must not become "never deletes anything": a
      // fixture left behind on every test is a temp directory that grows
      // without bound.
      final dir = Directory.systemTemp.createTempSync('good_plain');
      File('${dir.path}/nested/file.txt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('bytes');

      removeTempDir(dir);

      expect(dir.existsSync(), isFalse);
    });

    test('a directory that was never there is not a failure', () {
      final dir = Directory.systemTemp.createTempSync('good_gone');
      dir.deleteSync();

      expect(() => removeTempDir(dir), returnsNormally);
    });
  });
}
