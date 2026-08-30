import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// Runs the `good` CLI from a test, without the three things that make a
/// subprocess unreliable here.
///
/// **Compiled once for the whole run, into `.dart_tool` and not the system
/// temp directory.** This is #289, and the size is the whole of it. The kernel
/// is thirty-three megabytes. Four files need it, so compiling one per file
/// wrote a hundred and thirty-two megabytes into `Directory.systemTemp` every
/// run, and `tearDownAll` only takes that back when the run reaches the end -
/// an interrupted run, a killed agent, a file that failed to load, and the
/// directory stays. Fifty-seven of them were found on the machine this was
/// diagnosed on, eight hundred and twenty megabytes, the oldest a day old,
/// with the drive holding the system temp directory down to its last
/// gigabyte.
///
/// What a full drive does to `dart test` is exactly what #289 reported. The
/// runner copies a kernel per suite into the same temp directory, so the file
/// that fails is whichever one happened to be writing when the space ran out:
/// `Failed to load "test/x_test.dart"`, with nothing wrong with that file and
/// no test to name. A different set every run, because the order is the
/// scheduler's. Green when run alone, because one file needs a fraction of
/// the space. Green on CI forever, because a fresh runner has tens of
/// gigabytes and its own disk.
///
/// So the kernel goes under `.dart_tool` - on the drive the checkout is on,
/// one copy, keyed by [sourceKey] and reused until the CLI's sources change.
/// A run that is killed leaves that one directory, and the next run uses it
/// rather than adding another. Compiling four at once was also four CFE
/// frontends at once, eleven seconds each idle and forty-nine under load,
/// which is worth removing on its own - but the frontends only cost time and
/// the temp directory cost the suite its meaning. See [sharedBuild].
///
/// It is not `dart run bin/good.dart`. That compiles into `.dart_tool/pub/`,
/// beside where the test runner keeps its own kernels, and that collision
/// shows up as a test file failing to load with nothing whatever wrong with
/// it - the same symptom, one directory over.
///
/// **`flutter` is shadowed by a stub that fails at once.** `good build` hands
/// off to `flutter build` as its last step, long after the asset work these
/// tests look at. Running the real one costs minutes, needs a complete Flutter
/// checkout, and collides with any other Flutter process in the repository -
/// none of which says anything about whether the assets came out right.
///
/// **`GOOD_HOME` points into the build directory.** Unset, good keeps its
/// downloaded ffmpeg in `$USERPROFILE/.good/ffmpeg` or `$HOME/.good/ffmpeg`,
/// so a suite that left it alone would read and write the developer's own
/// cache, and on a machine with no ffmpeg on PATH four files would race to
/// unpack one archive into one directory. Pointing it at the build directory
/// is the same rule `_temp.dart` states for fixtures, applied to the one path
/// a subprocess picks for itself.
class GoodCli {
  GoodCli._(this.build, this._path);

  /// The kernel this runs and the directories it runs against.
  final CliBuild build;

  final String _path;

  static GoodCli? _instance;

  /// The compiled CLI, resolved on first use and kept for the test process.
  static GoodCli get instance => _instance ??= _fromBuild(sharedBuild());

  /// Runs `good [args]`, with the stub ahead of anything real on the path.
  ///
  /// [environment] is laid over the two variables this sets for itself, for
  /// the one test that has to see what good does with a path of its own.
  ProcessResult run(
    List<String> args, {
    Map<String, String> environment = const <String, String>{},
  }) => Process.runSync(
    Platform.resolvedExecutable,
    <String>[build.snapshot, ...args],
    environment: <String, String>{
      'PATH': _path,
      'GOOD_HOME': build.home,
      ...environment,
    },
  );

  static GoodCli _fromBuild(CliBuild build) {
    final separator = Platform.isWindows ? ';' : ':';
    return GoodCli._(
      build,
      '${build.stubs}$separator${Platform.environment['PATH']}',
    );
  }

  /// The build every file in this suite shares, made if nobody has made it.
  ///
  /// Under `.dart_tool/good_cli_test/<key>/`, where the key is [sourceKey]
  /// over everything the CLI is compiled from. A kernel is only ever read back
  /// under the key of the sources it was built from, so a source edit produces
  /// a different directory rather than a stale snapshot - which is the one way
  /// a shared build could be worse than no sharing at all.
  ///
  /// The claim on that directory is `File.createSync(exclusive: true)` on a
  /// marker beside it, and not `RandomAccessFile.lockSync`: POSIX file locks
  /// belong to the process, and every file in this suite is an isolate of one
  /// process, so a lock would have let all four through at once on Linux while
  /// working on Windows. An exclusive create is the same answer everywhere.
  ///
  /// Nothing here can fail the suite. A claim nobody releases, a rename that
  /// will not go through, a `.dart_tool` that cannot be written - each ends in
  /// [_privateBuild], which is what this file did for every caller before.
  static CliBuild sharedBuild() {
    final key = sourceKey(cliSources());
    final root = Directory('${_cacheRoot.path}/$key');
    final snapshot = '${root.path}/good.dill';
    if (File(snapshot).existsSync()) return _finish(root, snapshot);

    final claim = File('${root.path}.claim');
    for (var waited = Duration.zero; waited < _claimTimeout;) {
      try {
        claim.parent.createSync(recursive: true);
        claim.createSync(exclusive: true);
      } on FileSystemException {
        // Somebody else is compiling this key, or finished while we asked.
        if (File(snapshot).existsSync()) return _finish(root, snapshot);
        if (_isStale(claim)) {
          _ignoringFailure(claim.deleteSync);
          continue;
        }
        sleep(_pollInterval);
        waited += _pollInterval;
        continue;
      }
      try {
        _compileInto(root, snapshot);
        _pruneOtherBuilds(key);
        return _finish(root, snapshot);
      } finally {
        _ignoringFailure(claim.deleteSync);
      }
    }
    return _privateBuild();
  }

  /// Every file the compiled CLI is built out of, plus what resolved it.
  ///
  /// `bin/` and `lib/` are what the frontend reads. The four resolution files
  /// behind them are here because a dependency moving - a version bump, a path
  /// override pointed somewhere else - changes the kernel without changing a
  /// line under `lib/`. Read relative to the current directory, which is the
  /// package directory: this suite is run from `packages/good_cli`, the same
  /// thing `chunk_golden_test.dart` already needs.
  static List<File> cliSources() => <File>[
    for (final root in const <String>['bin', 'lib'])
      ...Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    File('pubspec.yaml'),
    File('pubspec.lock'),
    File('pubspec_overrides.yaml'),
    File('.dart_tool/package_config.json'),
  ];

  /// A digest over [files] that moves when any of their contents move.
  ///
  /// Contents and not timestamps, because a checkout, a branch switch and a
  /// `git stash` all rewrite modification times without changing what will be
  /// compiled, and a key that moved for those would throw the shared build
  /// away several times a day. Each path is hashed alongside its bytes, so
  /// renaming a file and adding one both count. A file that is not there is
  /// hashed as absent rather than skipped, so deleting one counts too.
  ///
  /// The Dart version is in the salt: the same sources under a different SDK
  /// are a different kernel.
  static String sourceKey(List<File> files) {
    final sorted = <File>[...files]..sort((a, b) => a.path.compareTo(b.path));
    final bytes = BytesBuilder(copy: false)..add(utf8.encode(Platform.version));
    for (final file in sorted) {
      bytes.add(utf8.encode('|${file.path}|'));
      bytes.add(
        file.existsSync() ? file.readAsBytesSync() : utf8.encode('<absent>'),
      );
    }
    return '${sha256.convert(bytes.takeBytes())}'.substring(0, 16);
  }

  static Directory get _cacheRoot => Directory('.dart_tool/good_cli_test');

  static const Duration _pollInterval = Duration(milliseconds: 200);
  static const Duration _claimTimeout = Duration(minutes: 5);

  /// A claim whose owner is gone. Five minutes is well past the slowest
  /// compile measured here, so taking it over cannot cut a live build short.
  static bool _isStale(File claim) {
    try {
      return DateTime.now().difference(claim.lastModifiedSync()) >
          _claimTimeout;
    } on FileSystemException {
      return false;
    }
  }

  /// Compiles into [root], through a name only this process writes.
  ///
  /// The rename is what makes the snapshot's existence mean "finished". A
  /// frontend writing straight to `good.dill` would let another file pick up a
  /// half-written kernel, and the failure that produces says nothing about the
  /// test that reports it.
  static void _compileInto(Directory root, String snapshot) {
    root.createSync(recursive: true);
    final partial = '$snapshot.$pid.part';
    final compiled = Process.runSync(Platform.resolvedExecutable, <String>[
      'compile',
      'kernel',
      'bin/good.dart',
      '-o',
      partial,
    ], workingDirectory: Directory.current.path);
    if (compiled.exitCode != 0) {
      _ignoringFailure(File(partial).deleteSync);
      throw StateError(
        'could not compile the CLI:\n${compiled.stdout}${compiled.stderr}',
      );
    }
    File(partial).renameSync(snapshot);
  }

  /// Everything the CLI needs beside the kernel, made if it is not there.
  static CliBuild _finish(Directory root, String snapshot) {
    final stubs = Directory('${root.path}/stub');
    if (!stubs.existsSync()) {
      stubs.createSync(recursive: true);
      if (Platform.isWindows) {
        File(
          '${stubs.path}/flutter.bat',
        ).writeAsStringSync('@echo stub flutter\r\n@exit /b 1\r\n');
      } else {
        final stub = File('${stubs.path}/flutter')
          ..writeAsStringSync('#!/bin/sh\necho "stub flutter"\nexit 1\n');
        Process.runSync('chmod', <String>['+x', stub.path]);
      }
    }
    final home = Directory('${root.path}/home')..createSync(recursive: true);
    return CliBuild(
      snapshot: snapshot,
      stubs: stubs.path,
      home: home.absolute.path,
    );
  }

  /// The build this file did for every caller before there was a shared one.
  ///
  /// Reached only when the shared build could not be claimed. Slower and
  /// nobody else's, but a suite that cannot use a cache has to still run.
  static CliBuild _privateBuild() {
    final root = Directory.systemTemp.createTempSync('good_cli_bin');
    final snapshot = '${root.path}/good.dill';
    _compileInto(root, snapshot);
    return _finish(root, snapshot);
  }

  /// Drops the builds of every other source state.
  ///
  /// Best effort: another `dart test` in this checkout may be running out of
  /// one, and Windows will refuse while it is. Whatever survives is dropped
  /// the next time somebody compiles.
  static void _pruneOtherBuilds(String keep) {
    final root = _cacheRoot;
    if (!root.existsSync()) return;
    for (final entity in root.listSync()) {
      // The name, not the path: `listSync` hands back the platform separator
      // while the path this built was assembled with a slash, and comparing
      // those two on Windows deletes the build that was just made.
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      if (name == keep || name == '$keep.claim') continue;
      _ignoringFailure(() => entity.deleteSync(recursive: true));
    }
  }

  static void _ignoringFailure(void Function() action) {
    try {
      action();
    } on FileSystemException {
      // Every caller here is tidying up. None of it is worth a failure.
    }
  }
}

/// Where one compiled CLI and the environment it runs under live.
@immutable
class CliBuild {
  const CliBuild({
    required this.snapshot,
    required this.stubs,
    required this.home,
  });

  /// The compiled kernel, run as `dart <snapshot> ...`.
  final String snapshot;

  /// The directory holding the `flutter` stub, put ahead of `PATH`.
  final String stubs;

  /// What `$GOOD_HOME` is set to, so good's own cache is not the user's.
  final String home;
}
