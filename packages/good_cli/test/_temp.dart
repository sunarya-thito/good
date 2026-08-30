/// Where a fixture goes, and how it is taken away again.
///
/// # The isolation rule for this suite
///
/// `dart test` runs every file in this directory as an isolate of one process,
/// eight of them at a time by default, and which eight are running together at
/// any moment is decided by how fast the machine is. So a fixture that two
/// files could both reach is a test whose verdict depends on the scheduler.
/// Every fixture in this suite goes under [testTempDir] and nowhere else:
/// never `Directory.current`, never a path built from the project name, never
/// `$HOME`. Nothing here writes to the developer's machine outside the system
/// temp directory and this package's own `.dart_tool`.
///
/// The second rule is about size, and it is the one #289 turned on. Anything
/// large and reusable belongs in `.dart_tool`, not here: the system temp
/// directory is one drive shared with every other tool on the machine, a
/// fixture only comes back when the run reaches its teardown, and a full drive
/// makes `dart test` fail at whichever file happened to be writing - a
/// different set every run, each of them green when run alone. `_cli.dart`
/// has the numbers. Fixtures are small and belong here; a thirty-three
/// megabyte compiled kernel did not.
///
/// The second half of the rule is [removeTempDir], and it is the half that is
/// easy to get wrong - see its own doc for what deleting a fixture the obvious
/// way does on Windows.
library;

import 'dart:io';

import 'package:test/test.dart';

/// A directory for one test, taken away when that test finishes.
Directory testTempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => removeTempDir(dir));
  return dir;
}

/// Removes [dir], allowing for a handle the OS has not let go of yet.
///
/// Windows refuses to delete a directory while any file under it is open, and
/// these fixtures are deleted the instant after subprocesses have been reading
/// and writing in them - ffmpeg, the compiled CLI, `dart analyze`. The child
/// has exited by then, but a virus scanner opening a file good has just
/// written is enough on its own, and the window widens with every other suite
/// the runner has scheduled beside this one. `deleteSync` answers that with
/// `PathAccessException`, and a throw from a tearDown is reported as the test
/// failing - so the test's verdict becomes a statement about the OS's timing
/// rather than about the code it was written to check, and it moves between
/// runs because the timing does. That is the shape of #289.
///
/// Retried briefly, then left alone. A directory still standing in the system
/// temp directory is the OS's to reclaim and is not worth a failure; the thing
/// worth refusing is a passing test that quietly wrote outside its fixture,
/// and that is [testTempDir]'s half of the rule, not this one's.
///
/// Nothing about this is needed on Linux, where the unlink succeeds with the
/// file still open. That is also why CI has never seen #289 and cannot be read
/// as evidence the suite is sound.
void removeTempDir(Directory dir) {
  for (var attempt = 0; attempt < 5; attempt++) {
    if (!dir.existsSync()) return;
    try {
      dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      sleep(const Duration(milliseconds: 50));
    }
  }
}
