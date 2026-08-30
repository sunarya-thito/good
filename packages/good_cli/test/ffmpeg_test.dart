import 'dart:io';

import 'package:good_cli/src/assets/ffmpeg.dart';
import 'package:good_cli/src/verbosable.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '_temp.dart';

// Where ffmpeg comes from, and in what order.
//
// The order is the whole of the interesting logic here, and getting it wrong
// is quiet rather than loud: silently downloading a binary when the machine
// already had one, or silently using a different ffmpeg than the one someone
// pinned, both produce a build that works and output nobody can explain.
//
// None of this touches the network. The probe and the downloader are injected
// exactly so resolution can be tested without a download and without ffmpeg
// installed - `_ffmpeg_download_probe.dart` exercises the real fetch by hand,
// because a suite that pulls tens of megabytes on every run is a suite people
// stop running.

/// Records what it was told, so a test can assert on what the user was shown.
class _Recording implements VerboseOutput {
  final StringBuffer buffer = StringBuffer();

  @override
  void println(Object? object) => buffer.writeln(object);
  @override
  void print(Object? object) => buffer.write(object);
  @override
  void printf(String format, List<Object?> args) {
    var index = 0;
    buffer.write(
      format.replaceAllMapped(RegExp('%s'), (_) => '${args[index++]}'),
    );
  }

  @override
  String toString() => buffer.toString();
}

Directory _tempDir() {
  final dir = testTempDir('good_ffmpeg');
  return dir;
}

/// A downloader that must never run.
Future<String> _neverDownloads(FfmpegDownload download, Directory into) async {
  fail('resolve() reached the network when it had a local ffmpeg to use');
}

void main() {
  final out = _Recording();
  final verbose = _Recording();

  group('resolution order', () {
    test(r'$GOOD_FFMPEG wins over everything else', () async {
      final resolved = await FfmpegResolver(
        environment: const <String, String>{'GOOD_FFMPEG': '/pinned/ffmpeg'},
        cacheDir: _tempDir(),
        probe: (executable) => true, // PATH and cache would both answer too
        download: _neverDownloads,
      ).resolve(allowDownload: true, out: out, verbose: verbose);

      expect(resolved.executable, '/pinned/ffmpeg');
      expect(resolved.origin, FfmpegOrigin.environment);
    });

    test(
      r'a broken $GOOD_FFMPEG fails rather than falling back to PATH',
      () async {
        // The one that matters most. Someone who set the variable meant that
        // binary; quietly transcoding with a different one produces output they
        // did not ask for and cannot account for.
        await expectLater(
          FfmpegResolver(
            environment: const <String, String>{'GOOD_FFMPEG': '/gone/ffmpeg'},
            cacheDir: _tempDir(),
            probe: (executable) => executable != '/gone/ffmpeg',
            download: _neverDownloads,
          ).resolve(allowDownload: true, out: out, verbose: verbose),
          throwsA(
            isA<FfmpegUnavailable>().having(
              (e) => e.message,
              'message',
              contains('will not silently fall back'),
            ),
          ),
        );
      },
    );

    test('PATH is preferred over the cache', () async {
      final cache = _tempDir();
      File('${cache.path}/ffmpeg.exe').writeAsStringSync('cached');
      File('${cache.path}/ffmpeg').writeAsStringSync('cached');

      final resolved = await FfmpegResolver(
        environment: const <String, String>{},
        cacheDir: cache,
        probe: (executable) => true,
        download: _neverDownloads,
      ).resolve(allowDownload: true, out: out, verbose: verbose);

      expect(resolved.origin, FfmpegOrigin.path);
      expect(resolved.executable, 'ffmpeg');
    });

    test('the cache is used before anything is downloaded', () async {
      final cache = _tempDir();
      final wanted = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
      // Nested, because each platform's archive unpacks to its own directory
      // name and version - the cache is searched, not assumed.
      final cached = File('${cache.path}/ffmpeg-7.1-essentials/bin/$wanted')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('cached');

      final resolved = await FfmpegResolver(
        environment: const <String, String>{},
        cacheDir: cache,
        probe: (executable) => executable != 'ffmpeg',
        download: _neverDownloads,
      ).resolve(allowDownload: true, out: out, verbose: verbose);

      expect(resolved.origin, FfmpegOrigin.cache);
      // Normalised on both sides: `listSync` hands back the OS separator on
      // Windows while `File('a/b').path` keeps the slash it was given, and
      // that difference is the test's, not the resolver's.
      expect(
        p.equals(resolved.executable, cached.path),
        isTrue,
        reason: 'expected \${cached.path}, got \${resolved.executable}',
      );
    });

    test('downloading is last, and only when nothing local answered', () async {
      final cache = _tempDir();
      var downloads = 0;
      final resolved = await FfmpegResolver(
        environment: const <String, String>{},
        cacheDir: cache,
        probe: (executable) => executable.endsWith('fetched'),
        download: (download, into) async {
          downloads++;
          return '${into.path}/fetched';
        },
      ).resolve(allowDownload: true, out: out, verbose: verbose);

      expect(downloads, 1);
      expect(resolved.origin, FfmpegOrigin.downloaded);
    });
  });

  group('what the user is told', () {
    test('a download announces the URL before it happens', () async {
      // Not behind --verbose. A tool that reaches onto the network should say
      // so where the person is already looking.
      final shown = _Recording();
      await FfmpegResolver(
        environment: const <String, String>{},
        cacheDir: _tempDir(),
        probe: (executable) => executable.endsWith('fetched'),
        download: (download, into) async => '${into.path}/fetched',
      ).resolve(allowDownload: true, out: shown, verbose: _Recording());

      final text = shown.toString();
      expect(text, contains('Downloading a static build'));
      expect(text, contains(FfmpegDownload.forHost()!.url));
      expect(
        text,
        contains('GOOD_FFMPEG'),
        reason: 'the way out has to be in the message that announces the fetch',
      );
    });

    test('--no-download names the URL it is refusing to fetch', () async {
      // So someone can go and get it themselves, which is the whole point of
      // refusing rather than failing blank.
      await expectLater(
        FfmpegResolver(
          environment: const <String, String>{},
          cacheDir: _tempDir(),
          probe: (executable) => false,
          download: _neverDownloads,
        ).resolve(allowDownload: false, out: out, verbose: verbose),
        throwsA(
          isA<FfmpegUnavailable>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('--no-download'),
              contains(FfmpegDownload.forHost()!.url),
            ),
          ),
        ),
      );
    });

    test('a download that unpacks something unrunnable says so', () async {
      // Distinguished from a failed fetch on purpose: the fetch worked, so the
      // next step is "the archive layout changed", not "check your network".
      await expectLater(
        FfmpegResolver(
          environment: const <String, String>{},
          cacheDir: _tempDir(),
          probe: (executable) => false,
          download: (download, into) async => '${into.path}/ffmpeg',
        ).resolve(allowDownload: true, out: out, verbose: verbose),
        throwsA(
          isA<FfmpegUnavailable>().having(
            (e) => e.message,
            'message',
            contains('archive layout may have changed'),
          ),
        ),
      );
    });

    test('a failed fetch reports the URL that failed', () async {
      await expectLater(
        FfmpegResolver(
          environment: const <String, String>{},
          cacheDir: _tempDir(),
          probe: (executable) => false,
          download: (download, into) async => throw const SocketException('no'),
        ).resolve(allowDownload: true, out: out, verbose: verbose),
        throwsA(
          isA<FfmpegUnavailable>().having(
            (e) => e.message,
            'message',
            allOf(contains(FfmpegDownload.forHost()!.url), contains('failed')),
          ),
        ),
      );
    });
  });

  group('the cache location', () {
    test('honours GOOD_HOME, so a CI image can put it somewhere it keeps', () {
      final resolver = FfmpegResolver(
        environment: const <String, String>{'GOOD_HOME': '/ci/cache'},
      );
      expect(resolver.cacheDir.path, '/ci/cache/.good/ffmpeg');
    });

    test('falls back to the user profile', () {
      final resolver = FfmpegResolver(
        environment: const <String, String>{'USERPROFILE': '/home/dev'},
      );
      expect(resolver.cacheDir.path, '/home/dev/.good/ffmpeg');
    });
  });

  test('every platform good claims to support has a download', () {
    // `forHost` returning null is a legitimate answer for a platform good has
    // no build for, and the resolver says so - but not for the three it does.
    expect(FfmpegDownload.forHost(), isNotNull);
  });
}
