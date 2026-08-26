import 'dart:ffi';
import 'dart:io';

import 'box2d.g.dart';

/// The loaded native library, or `null` until something asks for it. Read it
/// through [box2d], whose doc says why it lives here and not on an object.
Box2DBindings? _bindings;

/// The path to open instead of searching for the native library.
///
/// For tests and tools that run outside a Flutter app. A Flutter build
/// bundles the shim beside the executable and the search finds it there;
/// `flutter test`, `dart run` and `tool/` scripts build no plugins, so there
/// is nothing beside the executable to find.
///
/// Set it before the first physics call - once the library has resolved,
/// setting it does nothing.
String? nativeLibraryPathOverride;

/// The generated Box2D shim bindings, resolved on first use.
///
/// **Read it on every use. Never copy the result into a field.** These
/// bindings hold the `DynamicLibrary`'s `lookup` tear-off, so they carry the
/// native handle with them, and a native handle is not sendable through
/// `Isolate.spawn` - the same category as `ReceivePort` and `dart:ui.Image`.
/// `good` boots on the main isolate and hands the whole `Game` object graph
/// to the game isolate by deep copy, so bindings in a field of a
/// `GameSystem`, or of anything else `Game` can reach, make that spawn
/// fail.
///
/// It fails *intermittently*. A `late final` field holds nothing until
/// something has touched the library, so a headless test that never steps
/// physics passes and the real game does not. The bindings live on a
/// library-private static instead, which no isolate copy touches: each
/// isolate resolves its own, which is what each isolate needs anyway.
///
/// The null check here is one predictable branch.
Box2DBindings get box2d => _bindings ??= _load();

Box2DBindings _load() {
  final bindings = Box2DBindings(_openLibrary());

  // A stale copy of this library on the search path would otherwise surface
  // as inexplicable physics behaviour much later. Box2D's own reported
  // version is the cheapest way to catch it at the boundary.
  final packed = bindings.gooB2Version();
  final major = packed >> 16;
  final minor = (packed >> 8) & 0xFF;
  assert(
    major == 3,
    'goo2d_ffi_box2d expects Box2D v3.x, but the loaded native library '
    'reports v$major.$minor. The vendored source is v3.1.1 - a different '
    'version on the library search path is being picked up instead.',
  );

  return bindings;
}

DynamicLibrary _openLibrary() {
  final override = nativeLibraryPathOverride;
  if (override != null) {
    return DynamicLibrary.open(override);
  }

  // Apple platforms link the shim statically into the application binary
  // (see macos/goo2d_ffi_box2d.podspec), so there is no separate library
  // file to open - the symbols are already in this process.
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  }

  final fileName = Platform.isWindows
      ? 'goo2d_box2d.dll'
      : 'libgoo2d_box2d.so';

  // In a real Flutter app the plugin's build has already placed the library
  // beside the executable (or in the APK's jniLibs), so the bare name
  // resolves.
  try {
    return DynamicLibrary.open(fileName);
  } on ArgumentError {
    // Fall through to the development search below.
  }

  // `flutter test` and `dart run` do not build plugins, so nothing has put
  // the library anywhere the loader can see. Rather than making every test
  // set an override by hand, look for the artifact tool/build_native.ps1
  // produces. This path is a development convenience only - it is never
  // reached in a built application, where the branch above succeeds.
  final found = _findDevelopmentBuild(fileName);
  if (found != null) {
    return DynamicLibrary.open(found);
  }

  throw StateError(
    'Could not load the goo2d Box2D native library ($fileName).\n'
    '\n'
    'In a Flutter application this is built and bundled automatically by '
    'the goo2d_ffi_box2d plugin. Outside one - `flutter test`, `dart run`, '
    'a tool/ script - it has to be built first:\n'
    '\n'
    '  cd packages/goo2d_ffi_box2d && powershell -File tool/build_native.ps1\n'
    '\n'
    'Alternatively set nativeLibraryPathOverride to an existing build.',
  );
}

/// Walks up from the current directory looking for this package's
/// development build output.
///
/// Walks *up*, and does not resolve relative to `Platform.script`: a test
/// runner's script path is a generated temporary file whose location says
/// nothing useful about the repository. The working directory during
/// `flutter test` is the package under test, which is always somewhere
/// beneath the repository root, so climbing until `packages/` appears finds
/// the build from `goo2d_ffi_box2d`, from `goo2d_physics_box2d`, or from the
/// example app equally well.
String? _findDevelopmentBuild(String fileName) {
  // tool/build_native.ps1 writes into build/<host os>, so a developer who
  // works on two platforms out of one checkout does not have them
  // overwriting each other's artifacts.
  final relative = [
    'packages',
    'goo2d_ffi_box2d',
    'build',
    Platform.operatingSystem,
  ];

  var directory = Directory.current.absolute;
  for (var depth = 0; depth < 8; depth++) {
    final candidate = File(
      [directory.path, ...relative, fileName].join(Platform.pathSeparator),
    );
    if (candidate.existsSync()) {
      return candidate.path;
    }

    final parent = directory.parent;
    if (parent.path == directory.path) {
      return null; // Reached the filesystem root.
    }
    directory = parent;
  }
  return null;
}
