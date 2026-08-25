@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:good_cli/src/assets/compact.dart';
import 'package:test/test.dart';

import '_cli.dart';

// Where the compaction journal lives, and how a project already carrying one
// at the old path gets moved over.
//
// The journal records every source filename and the SHA-256 of its bytes. It
// used to be written into the asset directory, which `flutter: assets:` lists
// and flutter_tools expands by listing every file in it - dotfiles included -
// so it went into every release in plaintext beside the encrypted chunks.

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('good_journal');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

bool get _hasFfmpeg {
  try {
    return Process.runSync('ffmpeg', <String>['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  tearDownAll(GoodCli.disposeAll);

  group('readCompactJournal', () {
    test('reads the journal when nothing is at the old path', () {
      final dir = _tempDir();
      final journal = compactJournal(dir);
      CompactManifest({'a.png': 'aaa:webp:90'}).write(journal);
      final legacy = File('${dir.path}/${CompactManifest.legacyFileName}');

      final manifest = readCompactJournal(journal: journal, legacy: legacy);
      expect(manifest.entries, {'a.png': 'aaa:webp:90'});
    });

    test('adopts a journal left at the old path, and removes it', () {
      final dir = _tempDir();
      final journal = compactJournal(dir);
      final legacy = File('${dir.path}/${CompactManifest.legacyFileName}');
      CompactManifest({'a.png': 'aaa:webp:90'}).write(legacy);

      final moved = <String>[];
      final manifest = readCompactJournal(
        journal: journal,
        legacy: legacy,
        onMigrate: (file) => moved.add(file.path),
      );
      expect(manifest.entries, {
        'a.png': 'aaa:webp:90',
      }, reason: 'dropping these would re-encode every asset for nothing');
      expect(
        legacy.existsSync(),
        isFalse,
        reason: 'left there it ships in the next release',
      );
      expect(moved, [legacy.path]);
    });

    test('prefers the new journal, and still removes the old one', () {
      final dir = _tempDir();
      final journal = compactJournal(dir);
      final legacy = File('${dir.path}/${CompactManifest.legacyFileName}');
      CompactManifest({'a.png': 'current:webp:90'}).write(journal);
      CompactManifest({'a.png': 'stale:webp:90'}).write(legacy);

      final manifest = readCompactJournal(journal: journal, legacy: legacy);
      expect(manifest.entries, {'a.png': 'current:webp:90'});
      expect(legacy.existsSync(), isFalse);
    });
  });

  group('good assets compact (needs ffmpeg)', () {
    Directory project() {
      final dir = _tempDir();
      Directory('${dir.path}/assets_src').createSync(recursive: true);
      Directory('${dir.path}/assets').createSync(recursive: true);
      File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: journal_probe
environment:
  sdk: ^3.5.0

flutter:
  assets:
    - assets/
''');
      final image = Process.runSync('ffmpeg', <String>[
        '-loglevel',
        'error',
        '-y',
        '-f',
        'lavfi',
        '-i',
        'color=c=red:s=32x32:d=1',
        '-frames:v',
        '1',
        '${dir.path}/assets_src/player.png',
      ]);
      if (image.exitCode != 0) {
        throw StateError('ffmpeg could not write the probe image');
      }
      return dir;
    }

    ProcessResult compact(Directory dir) => GoodCli.instance.run(<String>[
      'assets',
      'compact',
      '--project-dir',
      dir.path,
    ]);

    test('writes nothing of its own into the shipped directory', () {
      final dir = project();
      final log = '${compact(dir).stdout}';
      expect(log, contains('1 written'));

      final shipped = Directory('${dir.path}/assets')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(shipped, [
        'player.webp',
      ], reason: 'anything else here is a build artifact that ships: $shipped');
      expect(compactJournal(dir).existsSync(), isTrue);
    }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');

    test('adopts a journal an older good left in the asset directory', () {
      final dir = project();
      expect('${compact(dir).stdout}', contains('1 written'));

      // Put the project back the way an older good would have left it.
      final journal = compactJournal(dir);
      final legacy = File(
        '${dir.path}/assets/${CompactManifest.legacyFileName}',
      );
      journal.renameSync(legacy.path);
      expect(journal.existsSync(), isFalse);

      final log = '${compact(dir).stdout}';
      expect(
        log,
        contains('0 written, 1 up to date'),
        reason: 'the old entries still describe the file, so nothing is stale',
      );
      expect(
        legacy.existsSync(),
        isFalse,
        reason: 'the migration has to take the old copy with it',
      );
      expect(journal.existsSync(), isTrue);
    }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');

    test('an entry carries the encoder flags, not a summary of them', () {
      final dir = project();
      expect('${compact(dir).stdout}', contains('1 written'));

      final entry = CompactManifest.read(
        compactJournal(dir),
      ).entries['player.png'];
      expect(entry, isNotNull);
      expect(
        entry,
        contains('-pix_fmt bgra'),
        reason:
            'the pixel format is not a config value, so a summary built out '
            'of config values cannot notice when it changes - which is how '
            '#189 would have shipped a fix that never reached a project that '
            'already had a journal',
      );
      expect(
        '${compact(dir).stdout}',
        contains('0 written, 1 up to date'),
        reason: 'nothing changed, so the second run has to skip the encode',
      );
    }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');
  });
}
