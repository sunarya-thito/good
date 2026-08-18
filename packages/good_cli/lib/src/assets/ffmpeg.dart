import 'dart:typed_data' show BytesBuilder;
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:good_cli/src/verbosable.dart';
import 'package:meta/meta.dart';

/// Where a usable ffmpeg came from.
///
/// Reported rather than kept private, because "which ffmpeg am I actually
/// running" is the first question when a transcode produces something
/// unexpected, and the answer differs per machine.
enum FfmpegOrigin {
  /// `$GOOD_FFMPEG` named it. First in the order so a project can pin a
  /// specific build - a CI image with a known ffmpeg, or a local one being
  /// tested - without anything else being consulted.
  environment,

  /// Found on `PATH`. The ordinary case on a developer machine.
  path,

  /// A previous run downloaded it into the cache.
  cache,

  /// Downloaded during this run.
  downloaded,
}

@immutable
class Ffmpeg {
  const Ffmpeg(this.executable, this.origin);

  final String executable;
  final FfmpegOrigin origin;
}

/// Raised when no ffmpeg could be found or fetched.
///
/// A distinct type rather than a generic failure: the caller wants to say
/// *why* transcoding cannot happen, and the three reasons - not installed,
/// download refused, download failed - lead to three different next steps.
class FfmpegUnavailable implements Exception {
  FfmpegUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Finds ffmpeg, fetching one if there is none.
///
/// # The order, and why
///
/// `$GOOD_FFMPEG` -> `PATH` -> cache -> download. Every step before the last is
/// something the machine already has, and downloading a binary is the most
/// surprising thing this tool can do - so it happens only when nothing else
/// answered, only with the URL printed first, and never at all under
/// [allowDownload] `false`.
///
/// # Injected, so it can be tested
///
/// The environment, the cache directory, the "can this be run" probe and the
/// downloader are all parameters. Resolution *order* is the interesting logic
/// and it is testable without a network, without ffmpeg installed, and without
/// touching the real cache - which is the only way a test of "prefers PATH
/// over download" means anything. `test/ffmpeg_test.dart` covers the order.
///
/// The real fetch is deliberately *not* in the suite: it pulls a hundred
/// megabytes over the network, and a suite that does that on every run is one
/// people stop running. `test/_ffmpeg_download_probe.dart` exercises it by
/// hand, which is what to reach for when [FfmpegDownload]'s archive layout
/// might have shifted under it.
class FfmpegResolver {
  FfmpegResolver({
    Map<String, String>? environment,
    this._cacheDir,
    bool Function(String executable)? probe,
    Future<String> Function(FfmpegDownload download, Directory into)? download,
  }) : _environment = environment ?? Platform.environment,
       _probe = probe ?? runsSuccessfully,
       _download = download ?? downloadFfmpeg;

  final Map<String, String> _environment;
  final Directory? _cacheDir;
  final bool Function(String) _probe;
  final Future<String> Function(FfmpegDownload, Directory) _download;

  /// The environment variable that pins a specific binary.
  static const String overrideVariable = 'GOOD_FFMPEG';

  Directory get cacheDir =>
      _cacheDir ?? Directory('${_home(_environment)}/.good/ffmpeg');

  Future<Ffmpeg> resolve({
    required bool allowDownload,
    required VerboseOutput out,
    required VerboseOutput verbose,
  }) async {
    final pinned = _environment[overrideVariable];
    if (pinned != null && pinned.isNotEmpty) {
      if (!_probe(pinned)) {
        // Loudly, rather than falling through to PATH. Someone who set the
        // variable meant that binary; quietly using a different one would
        // produce output they did not ask for and cannot explain.
        throw FfmpegUnavailable(
          '$overrideVariable is set to "$pinned", but that could not be run. '
          'Fix or unset it - good will not silently fall back to a different '
          'ffmpeg when you have named one.',
        );
      }
      verbose.printf('ffmpeg: %s (from $overrideVariable)\n', [pinned]);
      return Ffmpeg(pinned, FfmpegOrigin.environment);
    }

    if (_probe('ffmpeg')) {
      verbose.println('ffmpeg: found on PATH');
      return const Ffmpeg('ffmpeg', FfmpegOrigin.path);
    }

    final cached = _cachedExecutable();
    if (cached != null && _probe(cached)) {
      verbose.printf('ffmpeg: %s (cached)\n', [cached]);
      return Ffmpeg(cached, FfmpegOrigin.cache);
    }

    final download = FfmpegDownload.forHost();
    if (!allowDownload) {
      throw FfmpegUnavailable(
        'ffmpeg is required to convert assets, and none was found on PATH or '
        'in ${cacheDir.path}.\n'
        '--no-download says not to fetch one, so either install ffmpeg, or '
        'point $overrideVariable at a binary, or re-run without --no-download '
        'to fetch ${download?.url ?? "a static build"}.',
      );
    }
    if (download == null) {
      throw FfmpegUnavailable(
        'ffmpeg is required to convert assets, and good has no download for '
        '${Platform.operatingSystem}. Install ffmpeg, or point '
        '$overrideVariable at a binary.',
      );
    }

    // Announced before it happens, every time, and not behind --verbose. A
    // tool that reaches onto the network should say so where the user is
    // already looking.
    out
      ..println('ffmpeg was not found. Downloading a static build:')
      ..printf('  %s\n', [download.url])
      ..printf('  into %s\n', [cacheDir.path])
      ..println(
        '  (set $overrideVariable to use your own, or --no-download to '
        'refuse)',
      );

    cacheDir.createSync(recursive: true);
    final String executable;
    try {
      executable = await _download(download, cacheDir);
    } on Object catch (error) {
      throw FfmpegUnavailable(
        'Downloading ffmpeg from ${download.url} failed: $error\n'
        'Install ffmpeg yourself, or set $overrideVariable to a binary.',
      );
    }
    if (!_probe(executable)) {
      throw FfmpegUnavailable(
        'Downloaded ffmpeg to $executable, but it could not be run. The '
        'archive layout may have changed; install ffmpeg yourself, or set '
        '$overrideVariable.',
      );
    }
    out.printf('ffmpeg ready: %s\n', [executable]);
    return Ffmpeg(executable, FfmpegOrigin.downloaded);
  }

  /// An ffmpeg a previous run left in the cache, or null.
  ///
  /// Searched rather than assumed at a fixed path, because each platform's
  /// archive unpacks to its own directory name and version.
  String? _cachedExecutable() {
    final dir = cacheDir;
    if (!dir.existsSync()) return null;
    final wanted = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.uri.pathSegments.last == wanted) {
        return entity.path;
      }
    }
    return null;
  }
}

String _home(Map<String, String> environment) =>
    environment['GOOD_HOME'] ??
    environment['USERPROFILE'] ??
    environment['HOME'] ??
    Directory.current.path;

/// Can [executable] be run at all?
///
/// `-version` rather than a bare invocation: ffmpeg with no arguments exits
/// non-zero, so "did it run" and "did it succeed" would disagree.
bool runsSuccessfully(String executable) {
  try {
    final result = Process.runSync(executable, <String>['-version']);
    return result.exitCode == 0;
  } on Object {
    // ProcessException for a missing binary, and anything else a broken one
    // manages to throw. Either way the answer is no.
    return false;
  }
}

/// Where a static ffmpeg comes from for one platform.
@immutable
class FfmpegDownload {
  const FfmpegDownload({required this.url, required this.archive});

  final String url;

  /// How the archive is packed, which decides how it is unpacked.
  final FfmpegArchive archive;

  /// The download for the running platform, or null where good has none.
  ///
  /// These are the long-standing community static-build hosts; good does not
  /// mirror them. That is a real supply-chain dependency and is worth knowing
  /// about deliberately, which is why [FfmpegResolver] prints the URL rather
  /// than fetching quietly - and why `$GOOD_FFMPEG` exists for anyone who would
  /// rather vendor their own.
  static FfmpegDownload? forHost() {
    if (Platform.isWindows) {
      return const FfmpegDownload(
        url: 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip',
        archive: FfmpegArchive.zip,
      );
    }
    if (Platform.isLinux) {
      return const FfmpegDownload(
        url:
            'https://johnvansickle.com/ffmpeg/releases/'
            'ffmpeg-release-amd64-static.tar.xz',
        archive: FfmpegArchive.tarXz,
      );
    }
    if (Platform.isMacOS) {
      return const FfmpegDownload(
        url: 'https://evermeet.cx/ffmpeg/getrelease/zip',
        archive: FfmpegArchive.zip,
      );
    }
    return null;
  }
}

enum FfmpegArchive { zip, tarXz }

/// Fetches and unpacks [download] into [into], returning the ffmpeg path.
///
/// Separated from the resolver and injectable there, so every test of
/// resolution order runs without a network.
Future<String> downloadFfmpeg(FfmpegDownload download, Directory into) async {
  final client = HttpClient();
  final List<int> bytes;
  try {
    final request = await client.getUrl(Uri.parse(download.url));
    request.followRedirects = true;
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'HTTP ${response.statusCode} from ${download.url}',
        uri: Uri.parse(download.url),
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    bytes = builder.takeBytes();
  } finally {
    client.close(force: true);
  }

  final archive = switch (download.archive) {
    FfmpegArchive.zip => ZipDecoder().decodeBytes(bytes),
    FfmpegArchive.tarXz => TarDecoder().decodeBytes(
      XZDecoder().decodeBytes(bytes),
    ),
  };

  final wanted = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
  for (final entry in archive) {
    if (!entry.isFile) continue;
    if (entry.name.split('/').last != wanted) continue;
    final out = File('${into.path}/$wanted');
    out.writeAsBytesSync(entry.content as List<int>);
    if (!Platform.isWindows) {
      // The archive's mode is not preserved by writeAsBytes, and an ffmpeg
      // that is not executable is indistinguishable from one that is missing.
      Process.runSync('chmod', <String>['+x', out.path]);
    }
    return out.path;
  }
  throw StateError(
    'No $wanted inside the archive from ${download.url}. Its layout may have '
    'changed.',
  );
}
