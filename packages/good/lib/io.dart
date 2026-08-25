/// The parts of the kernel that need a filesystem.
///
/// Separate from `package:good/good.dart` so the barrel stays free of
/// `dart:io`. That is not a web hedge - the kernel imports `dart:ffi` in ten
/// files and spawns an isolate for the simulation, so a browser is out of reach
/// for reasons a conditional import cannot fix (#26). It is so the one library
/// needing a filesystem says so in its name, and so the boundary is already
/// drawn on the day a platform without one turns up.
///
/// Nothing in this repo uses a conditional import, and nothing here needs one:
/// everything under `dart:io` is opt-in by import.
library;

export 'src/asset_mount_io.dart';
