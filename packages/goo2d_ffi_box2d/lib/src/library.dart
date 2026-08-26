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

  // On Apple platforms CocoaPods builds the shim into a framework the
  // application loads at launch (see macos/goo2d_ffi_box2d.podspec), so its
  // symbols are already in this process and there is no library file to
  // open.
  //
  // Outside an application there is nothing to have linked them, so the
  // handle resolves and the first lookup in `_load` fails instead. Apple
  // therefore has no `flutter test` route to the shim, and never reaches
  // the search or the error below.
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
  // the library anywhere the loader can see. Look for a build made by hand
  // instead, so that every test does not have to set an override. This path
  // is a development convenience only - it is never reached in a built
  // application, where the branch above succeeds.
  final found = _findDevelopmentBuild(fileName);
  if (found != null) {
    return DynamicLibrary.open(found);
  }

  final buildDir = 'packages/goo2d_ffi_box2d/build/${Platform.operatingSystem}';

  // Windows gets the wrapper and not the two commands. CMake chooses its
  // generator from the Visual Studio version it finds, and for a version
  // newer than it knows about it falls back to NMake Makefiles, which then
  // fails with CMAKE_C_COMPILER not set. tool/build_native.ps1 runs the same
  // two commands inside vcvars64, where cl.exe is on PATH.
  final build = Platform.isWindows
      ? '  powershell -File packages/goo2d_ffi_box2d/tool/build_native.ps1'
      : '  cmake -S packages/goo2d_ffi_box2d/src -B $buildDir '
            '-DCMAKE_BUILD_TYPE=Release\n'
            '  cmake --build $buildDir --parallel';

  throw StateError(
    'Could not load the goo2d Box2D native library ($fileName).\n'
    '\n'
    'In a Flutter application this is built and bundled automatically by '
    'the goo2d_ffi_box2d plugin. Outside one - `flutter test`, `dart run`, '
    'a tool/ script - build it first, from the repository root:\n'
    '\n'
    '$build\n'
    '\n'
    'The result has to land in $buildDir. That is the directory searched '
    'just now, and a build written anywhere else succeeds without being '
    'found.\n'
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
  // The build goes in build/<host os>, so a developer who works on two
  // platforms out of one checkout does not have them overwriting each
  // other's artifacts. Both routes that produce it - the two cmake commands
  // `_openLibrary`'s error prints, and tool/build_native.ps1 - write there.
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
