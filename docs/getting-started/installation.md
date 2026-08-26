# Installation

good is a set of Flutter packages plus a command-line tool. There is nothing to
install globally beyond the Flutter SDK and one `dart pub global activate` for
the `good` command.

## Prerequisites

| Requirement | Version | Why |
|---|---|---|
| Flutter SDK | `>=3.47.0` | The kernel depends on Flutter — `StateChannel` is a `ValueListenable` and `GameView` is a widget |
| Dart SDK | `^3.13.0` | Ships with Flutter |
| A desktop or mobile toolchain | see below | good uses `dart:ffi` and native memory |

Check what you have:

```bash
flutter --version
flutter doctor
```

!!! warning "The web is not a supported target"
    The kernel allocates component storage with `dart:ffi` and runs the
    simulation on a spawned isolate. Neither exists on the web. `Game.start`
    falls back to running the simulation inline there, but there is no web
    renderer and `good build` has no web target.

### Platform toolchains

The engine itself is pure Dart. The **physics package** compiles vendored
Box2D from source per platform, so if you add `goo2d_physics_box2d` you need a
native toolchain — the same one Flutter already requires for that platform.

=== "Windows"

    - Visual Studio with the *Desktop development with C++* workload
    - CMake 3.15+ (bundled with Visual Studio)

=== "Linux"

    - `clang`, `cmake`, `ninja-build`, `pkg-config`
    - `libgtk-3-dev`

=== "Android"

    - Android SDK and the **NDK** (Box2D is built through Gradle's CMake
      integration)

=== "macOS / iOS"

    - Xcode and CocoaPods (Box2D compiles through a podspec, linked statically)

A Flutter app builds all of this automatically. Outside one — `flutter test`,
`dart run`, a `tool/` script — nothing builds plugins, so build the native
library once by hand, from the repository root:

=== "Windows"

    ```powershell
    powershell -File packages/goo2d_ffi_box2d/tool/build_native.ps1
    ```

    The script runs the two cmake commands in the Linux tab against
    `build/windows`, inside a Visual Studio environment. Windows needs that
    environment and the bare commands do not have it: CMake picks its
    generator from the Visual Studio version it finds, and for a version
    newer than it knows about it falls back to NMake Makefiles and stops with
    `CMAKE_C_COMPILER not set`.

=== "Linux"

    ```sh
    cmake -S packages/goo2d_ffi_box2d/src \
          -B packages/goo2d_ffi_box2d/build/linux -DCMAKE_BUILD_TYPE=Release
    cmake --build packages/goo2d_ffi_box2d/build/linux --parallel
    ```

    `src/CMakeLists.txt` is a build root of its own, so no wrapper is
    involved. This is what CI runs.

=== "macOS / iOS"

    There is no route. The podspec links the shim into the application
    binary, so there is no library file to open and `goo2d_ffi_box2d` reads
    the symbols out of the process instead. Outside an app nothing has linked
    them, and the first call fails on a missing symbol.

The output directory is load-bearing. `goo2d_ffi_box2d` searches for
`packages/goo2d_ffi_box2d/build/<operating system>`, so a build written to a
generic `build/` succeeds and is then never found — a failure that looks like
a build that never ran.

It finds the artifact by walking up from the working directory, so tests in
sibling packages pick up one build with no configuration.

### ffmpeg (optional, fetched on demand)

The asset pipeline converts source art into one canonical format per kind
(WebP for images, Ogg Vorbis for audio) using **ffmpeg**. You do not have to
install it: `good assets compact` and `good build` look for an ffmpeg on your
`PATH` and download one if there is none.

Pass `--no-download` to make a missing ffmpeg an error instead — worth doing in
CI, where an unexpected download is a slow surprise, not a convenience.

---

## Adding the engine

A 2D game adds **`goo2d` only**. It re-exports the kernel, so there is no second
package to add and keep version-matched by hand:

```bash
flutter pub add goo2d
```

```dart
import 'package:goo2d/goo2d.dart';   // ECS, scenes, tick loop, rendering, GameView
```

Opt-in packages stay separate because they carry weight not every game wants.
Each also needs its system declared in `describeSystems`:

```yaml title="pubspec.yaml"
dependencies:
  goo2d: ^0.1.0
  goo2d_physics_box2d: ^0.1.0   # native Box2D — only if you want physics
  good_net_p2p: ^0.1.0           # serverless multiplayer — only if you want it
```

### Working from a clone

If you are developing against the engine's own source — tracking `master`, or
working on the engine itself — depend on it by path instead:

```bash
git clone https://github.com/sunarya-thito/good.git
```

```yaml title="pubspec.yaml"
dependencies:
  goo2d:
    path: ../good/packages/goo2d
```

This is what the repository's own `game/` directory does. A `git:` dependency
works the same way, and should pin `ref:` to a tag or commit for anything you
intend to ship:

```yaml
dependencies:
  goo2d:
    git:
      url: https://github.com/sunarya-thito/good.git
      path: packages/goo2d
      ref: v0.1.0
```

---

## Installing the `good` CLI

The same CLI serves `goo2d` and `goo3d`
projects.

```bash
dart pub global activate good_cli
```

Make sure the pub cache's `bin` is on your `PATH`:

=== "Windows"

    ```
    %LOCALAPPDATA%\Pub\Cache\bin
    ```

=== "macOS / Linux"

    ```
    $HOME/.pub-cache/bin
    ```

Verify:

```console
$ good --help
Usage: good <command> [options]

Commands:
  create    Scaffold a new Flutter project wired up to good.
  generate  Write lib/good.generated/ from the assets the pubspec declares.
  assets    Convert and pack the assets a project ships.
  build     Build and package a game for a target platform.

Options:
  --help  Show this help and exit.
```

### From a clone

Activate the local copy, which is what you want when tracking the engine's
source:

```bash
dart pub global activate --source path packages/good_cli
```

Or skip activation entirely — handy in CI, and when switching between engine
versions:

```bash
dart run /path/to/goo2d/packages/good_cli/bin/good.dart --help
```

Everywhere this documentation writes `good <command>`, that form works too.

---

## Next

[Create a project →](create-a-project.md)
