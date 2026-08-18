import 'dart:io';

import 'package:good_cli/src/assets/compact.dart';
import 'package:good_cli/src/assets/ffmpeg.dart';
import 'package:good_cli/src/config.dart';
import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/verbosable.dart';
import 'package:test/test.dart';

// Asset compaction: which source becomes which output, which ffmpeg gets used,
// and what is skipped because it has not changed.
//
// None of this runs ffmpeg. The plan, the resolver's ordering and the
// up-to-date check are all decidable without it, and they are the parts that
// can be wrong in ways nobody notices - a resolver that reaches for the
// network when a perfectly good ffmpeg is on PATH, or a rebuild that
// re-encodes a library every time. The transcode itself is exercised
// separately and skipped where no ffmpeg exists.

final VerboseOutput _quiet = _NullOutput();

class _NullOutput implements VerboseOutput {
  @override
  void println(Object? object) {}
  @override
  void print(Object? object) {}
  @override
  void printf(String format, List<Object?> args) {}
}

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('good_compact');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

Directory _sourceTree(List<String> files) {
  final dir = _tempDir();
  for (final path in files) {
    final file = File('${dir.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('bytes for $path');
  }
  return dir;
}

void main() {
  group('planCompaction', () {
    test('every texture becomes the one canonical texture format', () {
      final source = _sourceTree(['a.jpg', 'b.png', 'c.bmp']);
      final plan = planCompaction(
        sourceDir: source,
        config: GoodConfig.defaults,
      );
      expect(plan.steps.map((s) => s.output), ['a.webp', 'b.webp', 'c.webp']);
      expect(
        plan.steps.every((s) => s.kind == AssetKind.texture),
        isTrue,
        reason:
            'collapsing many source formats to one is the entire point - it '
            'is one decoder the runtime has to be right about instead of six',
      );
    });

    test('every audio file becomes the one canonical audio format', () {
      final source = _sourceTree(['music.mp3', 'hit.wav']);
      final plan = planCompaction(
        sourceDir: source,
        config: GoodConfig.defaults,
      );
      expect(plan.steps.map((s) => s.output), ['hit.ogg', 'music.ogg']);
    });

    test('the source tree shape is preserved, never flattened', () {
      final source = _sourceTree(['ui/button.jpg', 'hud/button.jpg']);
      final plan = planCompaction(
        sourceDir: source,
        config: GoodConfig.defaults,
      );
      expect(plan.steps.map((s) => s.output), [
        'hud/button.webp',
        'ui/button.webp',
      ]);
      // Flattening would make these one file, and would make the identifiers
      // `good generate` derives collide - the source tree already said they
      // were different things.
      expect(plan.steps.map((s) => s.output).toSet(), hasLength(2));
    });

    test('a file already in the target format is copied, not re-encoded', () {
      final source = _sourceTree(['already.webp', 'other.png']);
      final plan = planCompaction(
        sourceDir: source,
        config: GoodConfig.defaults,
      );
      final already = plan.steps.firstWhere((s) => s.source == 'already.webp');
      final other = plan.steps.firstWhere((s) => s.source == 'other.png');
      expect(
        already.copyOnly,
        isTrue,
        reason:
            're-encoding a lossy format into itself is generation loss for '
            'nothing - the file is already what was asked for',
      );
      expect(other.copyOnly, isFalse);
    });

    test('an unrecognised file is reported, not silently dropped', () {
      final source = _sourceTree(['notes.txt', 'a.png']);
      final plan = planCompaction(
        sourceDir: source,
        config: GoodConfig.defaults,
      );
      expect(plan.steps, hasLength(1));
      expect(plan.skipped.keys, ['notes.txt']);
    });

    test('a source directory with a trailing slash keeps whole filenames', () {
      // The bug this exists for: GoodConfig normalises every directory to end
      // in '/', so the real command always passes a trailing-separator path -
      // and `path.length + 1` then ate the first character of every relative
      // path. `dot.png` became `ot.png`, silently, and only surfaced as a
      // missing file at the transcode. Every fixture here used a temp dir,
      // which has no trailing slash, so nothing caught it.
      final source = _sourceTree(['dot.png', 'ui/beep.wav']);
      final plan = planCompaction(
        sourceDir: Directory('${source.path}/'),
        config: GoodConfig.defaults,
      );
      expect(plan.steps.map((s) => s.source), ['dot.png', 'ui/beep.wav']);
      expect(plan.steps.map((s) => s.output), ['dot.webp', 'ui/beep.ogg']);
    });

    test('a missing source directory is an empty plan, not a crash', () {
      final plan = planCompaction(
        sourceDir: Directory('${_tempDir().path}/nope'),
        config: GoodConfig.defaults,
      );
      expect(plan.isEmpty, isTrue);
    });

    test('the configured format is honoured', () {
      final source = _sourceTree(['a.jpg']);
      final plan = planCompaction(
        sourceDir: source,
        config: const GoodConfig(
          assetSource: 'assets_src/',
          assetOutput: 'assets/',
          texture: TextureConfig(format: TextureFormat.png),
          audio: AudioConfig(),
        ),
      );
      expect(plan.steps.single.output, 'a.png');
    });
  });

  group('ffmpegArguments', () {
    const step = CompactStep(
      source: 'a.jpg',
      output: 'a.webp',
      kind: AssetKind.texture,
      copyOnly: false,
    );

    test('a texture encode keeps alpha', () {
      final arguments = ffmpegArguments(
        step: step,
        config: GoodConfig.defaults,
        input: 'in.jpg',
        output: 'out.webp',
      );
      expect(arguments, containsAllInOrder(['-c:v', 'libwebp']));
      expect(
        arguments,
        containsAllInOrder(['-pix_fmt', 'yuva420p']),
        reason:
            'the default pixel format discards alpha for some inputs, which '
            'silently ruins every sprite that has any',
      );
    });

    test('quality 100 asks for lossless', () {
      final arguments = ffmpegArguments(
        step: step,
        config: const GoodConfig(
          assetSource: 'assets_src/',
          assetOutput: 'assets/',
          texture: TextureConfig(quality: 100),
          audio: AudioConfig(),
        ),
        input: 'in.png',
        output: 'out.webp',
      );
      expect(arguments, containsAllInOrder(['-lossless', '1']));
    });

    test('an audio encode drops cover art', () {
      final arguments = ffmpegArguments(
        step: const CompactStep(
          source: 'a.mp3',
          output: 'a.ogg',
          kind: AssetKind.audio,
          copyOnly: false,
        ),
        config: GoodConfig.defaults,
        input: 'in.mp3',
        output: 'out.ogg',
      );
      expect(arguments, containsAllInOrder(['-c:a', 'libvorbis']));
      expect(
        arguments,
        contains('-vn'),
        reason:
            'an album-art frame in a sound effect turns a stream copy into a '
            'video encode, and can fail the conversion outright',
      );
    });

    test('never prompts, and stays quiet unless something is wrong', () {
      final arguments = ffmpegArguments(
        step: step,
        config: GoodConfig.defaults,
        input: 'in.jpg',
        output: 'out.webp',
      );
      expect(
        arguments,
        contains('-y'),
        reason: 'a prompt in a build tool is a hang in CI',
      );
      expect(arguments, containsAllInOrder(['-loglevel', 'error']));
    });
  });

  group('FfmpegResolver ordering', () {
    Future<Ffmpeg> resolve({
      Map<String, String> environment = const <String, String>{},
      required bool Function(String) probe,
      Directory? cache,
      bool allowDownload = true,
      Future<String> Function(FfmpegDownload, Directory)? download,
    }) => FfmpegResolver(
      environment: environment,
      cacheDir: cache ?? _tempDir(),
      probe: probe,
      download:
          download ??
          (d, into) async => throw StateError('should not have downloaded'),
    ).resolve(allowDownload: allowDownload, out: _quiet, verbose: _quiet);

    test('GOOD_FFMPEG wins over everything', () async {
      final resolved = await resolve(
        environment: const {'GOOD_FFMPEG': '/pinned/ffmpeg'},
        probe: (_) => true,
      );
      expect(resolved.executable, '/pinned/ffmpeg');
      expect(resolved.origin, FfmpegOrigin.environment);
    });

    test('a broken GOOD_FFMPEG fails rather than falling back', () async {
      await expectLater(
        () => resolve(
          environment: const {'GOOD_FFMPEG': '/pinned/ffmpeg'},
          // PATH would answer, but the pin must still win.
          probe: (exe) => exe != '/pinned/ffmpeg',
        ),
        throwsA(
          isA<FfmpegUnavailable>().having(
            (e) => e.message,
            'message',
            contains('will not silently fall back'),
          ),
        ),
        reason:
            'someone who named a binary meant that one; using another would '
            'produce output they cannot explain',
      );
    });

    test('PATH is preferred over downloading', () async {
      final resolved = await resolve(probe: (exe) => exe == 'ffmpeg');
      expect(resolved.origin, FfmpegOrigin.path);
    });

    test('a cached copy is used before downloading', () async {
      final cache = _tempDir();
      final name = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
      final cached = File('${cache.path}/build/$name')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
      String slash(String p) => p.replaceAll(r'\', '/');
      final resolved = await resolve(
        cache: cache,
        // Compared with separators normalised: File.path hands back backslashes
        // on Windows while the fixture built its path with forward ones, and
        // the resolver is not what should be normalising them.
        probe: (exe) => slash(exe) == slash(cached.path),
      );
      expect(resolved.origin, FfmpegOrigin.cache);
      expect(slash(resolved.executable), slash(cached.path));
    });

    test('--no-download refuses, and says how to proceed', () async {
      await expectLater(
        () => resolve(probe: (_) => false, allowDownload: false),
        throwsA(
          isA<FfmpegUnavailable>().having(
            (e) => e.message,
            'message',
            allOf(contains('--no-download'), contains('GOOD_FFMPEG')),
          ),
        ),
      );
    });

    test('downloads only when nothing else answered', () async {
      var downloaded = false;
      final resolved = await resolve(
        probe: (exe) => exe != 'ffmpeg',
        download: (d, into) async {
          downloaded = true;
          return '${into.path}/ffmpeg';
        },
      );
      expect(downloaded, isTrue);
      expect(resolved.origin, FfmpegOrigin.downloaded);
    });

    test(
      'a failed download explains itself and names the alternatives',
      () async {
        await expectLater(
          () => resolve(
            probe: (_) => false,
            download: (d, into) async => throw const SocketException('offline'),
          ),
          throwsA(
            isA<FfmpegUnavailable>().having(
              (e) => e.message,
              'message',
              allOf(contains('failed'), contains('GOOD_FFMPEG')),
            ),
          ),
        );
      },
    );
  });

  group('up-to-date skipping', () {
    test('a fingerprint changes with the bytes and with the settings', () {
      final dir = _tempDir();
      final file = File('${dir.path}/a.png')..writeAsStringSync('one');
      final first = CompactManifest.fingerprint(file, 'webp:90');
      expect(CompactManifest.fingerprint(file, 'webp:90'), first);
      expect(
        CompactManifest.fingerprint(file, 'webp:75'),
        isNot(first),
        reason:
            'changing the quality has to invalidate every texture even though '
            'not one source byte moved',
      );
      file.writeAsStringSync('two');
      expect(CompactManifest.fingerprint(file, 'webp:90'), isNot(first));
    });

    test('a corrupt manifest means recompact, not crash', () {
      final dir = _tempDir();
      final file = File('${dir.path}/${CompactManifest.fileName}')
        ..writeAsStringSync('not json at all');
      expect(CompactManifest.read(file).entries, isEmpty);
    });

    test('a manifest round-trips', () {
      final dir = _tempDir();
      final file = File('${dir.path}/${CompactManifest.fileName}');
      CompactManifest({'a.png': 'abc:webp:90'}).write(file);
      expect(CompactManifest.read(file).entries, {'a.png': 'abc:webp:90'});
    });
  });

  group('runCompaction (needs ffmpeg)', () {
    // Gated rather than failing: the plan and the resolver are tested above
    // without ffmpeg, and a suite that cannot run on a machine without it
    // would just be skipped wholesale instead.
    final available = runsSuccessfully('ffmpeg');

    test('converts a real image and skips it on the second run', () async {
      final source = _sourceTree(<String>[]);
      // A 1x1 PNG, so this is a genuine decode-and-encode rather than a copy.
      File('${source.path}/dot.png').writeAsBytesSync(<int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
        0x1F,
        0x15,
        0xC4,
        0x89,
        0x00,
        0x00,
        0x00,
        0x0A,
        0x49,
        0x44,
        0x41,
        0x54,
        0x78,
        0x9C,
        0x63,
        0x00,
        0x01,
        0x00,
        0x00,
        0x05,
        0x00,
        0x01,
        0x0D,
        0x0A,
        0x2D,
        0xB4,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ]);
      final output = _tempDir();
      final plan = planCompaction(
        sourceDir: source,
        config: GoodConfig.defaults,
      );

      final first = await runCompaction(
        plan: plan,
        sourceDir: source,
        outputDir: output,
        config: GoodConfig.defaults,
        ffmpeg: const Ffmpeg('ffmpeg', FfmpegOrigin.path),
        out: _quiet,
        verbose: _quiet,
      );
      expect(first.failed, isEmpty);
      expect(first.written, 1);
      expect(File('${output.path}/dot.webp').existsSync(), isTrue);

      final second = await runCompaction(
        plan: plan,
        sourceDir: source,
        outputDir: output,
        config: GoodConfig.defaults,
        ffmpeg: const Ffmpeg('ffmpeg', FfmpegOrigin.path),
        out: _quiet,
        verbose: _quiet,
      );
      expect(
        second.upToDate,
        1,
        reason: 'an unchanged source must not be re-encoded',
      );
      expect(second.written, 0);
    }, skip: available ? null : 'ffmpeg is not installed');

    test(
      'a deleted output forces a rebuild even if the manifest agrees',
      () async {
        final source = _sourceTree(['tone.wav']);
        final output = _tempDir();
        final plan = planCompaction(
          sourceDir: source,
          config: GoodConfig.defaults,
        );
        // The source is not real audio, so the conversion fails - which is the
        // point of this one: a failure is recorded, not thrown, and does not
        // land in the manifest.
        final result = await runCompaction(
          plan: plan,
          sourceDir: source,
          outputDir: output,
          config: GoodConfig.defaults,
          ffmpeg: const Ffmpeg('ffmpeg', FfmpegOrigin.path),
          out: _quiet,
          verbose: _quiet,
        );
        expect(result.failed.keys, ['tone.wav']);
        expect(result.written, 0);
        expect(
          CompactManifest.read(
            File('${output.path}/${CompactManifest.fileName}'),
          ).entries,
          isEmpty,
          reason:
              'a file that failed must not be recorded as done, or the next run '
              'would skip it and the asset would never appear',
        );
      },
      skip: available ? null : 'ffmpeg is not installed',
    );
  });
}
