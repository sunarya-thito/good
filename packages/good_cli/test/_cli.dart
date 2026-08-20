import 'dart:io';

/// Runs the `good` CLI from a test, without the two things that make a
/// subprocess unreliable here.
///
/// **Compiled once, not `dart run`.** `dart run bin/good.dart` compiles into
/// the package's own `.dart_tool/`, which is where the test runner is reading
/// its own kernels from at the same time. That collision shows up as a test
/// file that fails to load with nothing whatever wrong with it.
///
/// **`flutter` is shadowed by a stub that fails at once.** `good build` hands
/// off to `flutter build` as its last step, long after the asset work these
/// tests look at. Running the real one costs minutes, needs a complete Flutter
/// checkout, and collides with any other Flutter process in the repository -
/// none of which says anything about whether the assets came out right.
class GoodCli {
  GoodCli._(this._dir, this._snapshot, this._path);

  final Directory _dir;
  final String _snapshot;
  final String _path;

  static GoodCli? _instance;

  /// The compiled CLI, built on first use and kept for the test process.
  static GoodCli get instance => _instance ??= _build();

  /// Removes what [instance] built. Safe to call when nothing was built.
  static void disposeAll() {
    final built = _instance;
    _instance = null;
    if (built != null && built._dir.existsSync()) {
      built._dir.deleteSync(recursive: true);
    }
  }

  static GoodCli _build() {
    final dir = Directory.systemTemp.createTempSync('good_cli_bin');
    final snapshot = '${dir.path}/good.dill';
    final compiled = Process.runSync(Platform.resolvedExecutable, <String>[
      'compile',
      'kernel',
      'bin/good.dart',
      '-o',
      snapshot,
    ], workingDirectory: Directory.current.path);
    if (compiled.exitCode != 0) {
      throw StateError(
        'could not compile the CLI:\n${compiled.stdout}${compiled.stderr}',
      );
    }

    final stubs = Directory('${dir.path}/stub')..createSync(recursive: true);
    if (Platform.isWindows) {
      File(
        '${stubs.path}/flutter.bat',
      ).writeAsStringSync('@echo stub flutter\r\n@exit /b 1\r\n');
    } else {
      final stub = File('${stubs.path}/flutter')
        ..writeAsStringSync('#!/bin/sh\necho "stub flutter"\nexit 1\n');
      Process.runSync('chmod', <String>['+x', stub.path]);
    }

    final separator = Platform.isWindows ? ';' : ':';
    return GoodCli._(
      dir,
      snapshot,
      '${stubs.path}$separator${Platform.environment['PATH']}',
    );
  }

  /// Runs `good [args]`, with the stub ahead of anything real on the path.
  ProcessResult run(List<String> args) => Process.runSync(
    Platform.resolvedExecutable,
    <String>[_snapshot, ...args],
    environment: <String, String>{'PATH': _path},
  );
}
