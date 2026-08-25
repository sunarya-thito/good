/// The parts of the kernel that need a filesystem.
///
/// Separate from `package:good/good.dart` so the barrel stays free of
/// `dart:io`. That is not a web hedge - the kernel imports `dart:ffi` in ten
/// files and spawns an isolate for the simulation, so a browser is out of
/// reach for reasons a conditional import cannot fix (#26). It is so that the
/// one library needing a filesystem says so in its name, and so that the day
/// a platform without one turns up, the boundary is already drawn rather than
/// having to be found.
///
/// There are no conditional imports anywhere in this repo, and this is why
/// none is needed here: everything under `dart:io` is opt-in by import.
library;

export 'src/asset_mount_io.dart';
