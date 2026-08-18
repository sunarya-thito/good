import 'dart:io';
import 'package:good_cli/src/assets/ffmpeg.dart';

/// Exercises the real download once. Not a test - it reaches the network and
/// pulls tens of megabytes, which is not something a suite should do on every
/// run. Run it by hand when the archive layout might have changed:
///
///     dart run test/_ffmpeg_download_probe.dart
Future<void> main() async {
  final download = FfmpegDownload.forHost();
  if (download == null) {
    stderr.writeln('No download for ${Platform.operatingSystem}.');
    exitCode = 1;
    return;
  }
  final into = Directory.systemTemp.createTempSync('good_ffmpeg_probe');
  stdout.writeln('GET ${download.url}');
  stdout.writeln('into ${into.path}');
  final started = DateTime.now();
  try {
    final executable = await downloadFfmpeg(download, into);
    final size = File(executable).lengthSync();
    final seconds = DateTime.now().difference(started).inSeconds;
    stdout.writeln('unpacked $executable ($size bytes) in ${seconds}s');
    final ran = runsSuccessfully(executable);
    stdout.writeln('runs: $ran');
    final version = Process.runSync(executable, <String>['-version']);
    stdout.writeln(version.stdout.toString().split('\n').first);
    exitCode = ran ? 0 : 1;
  } finally {
    if (into.existsSync()) into.deleteSync(recursive: true);
  }
}
