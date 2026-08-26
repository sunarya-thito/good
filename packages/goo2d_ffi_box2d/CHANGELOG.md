## Unreleased

macOS and iOS build for the first time; the rest is documentation and build
tooling. One C signature changes and one message string differs. Every
exported symbol is what it was.

* The macOS and iOS podspecs named their sources with patterns that climb out
  of the pod directory. CocoaPods matches `source_files` against the files
  under the pod root, so every one of those patterns matched nothing and the
  pod compiled no sources at all. An application built against it succeeded,
  bundled no shim, and threw `Failed to lookup symbol` at the first physics
  call. `ios/Classes` and `macos/Classes` now hold files that `#include` the
  sources out of `src`, which is what a podspec can reach.
* `gooThreadPoolEnqueue` takes a `GooTaskFn*` where it took a `void*`. Box2D's
  `b2WorldDef.enqueueTask` holds a function pointer, and assigning a `void*`
  function to it is a warning under GCC and MSVC and an error under Clang 16
  and newer, so `gooWorldCreateThreaded` compiled on no Apple toolchain. The
  Dart bindings come from `goo_box2d.h` alone and do not change.
* `goo_threads.h` said its two callbacks match Box2D's signatures exactly. One
  of them did not, which is the line above.
* `.github/workflows/test.yml` builds an application against both podspecs on
  a macOS runner and reads the shim's symbols back out of the bundle. Neither
  Apple platform had been built anywhere.
* `test/apple_forwarders_test.dart` compares the Apple source list against the
  directory `src/CMakeLists.txt` globs, so the two descriptions of this build
  cannot drift apart unnoticed.
* The README, the docs and `library.dart` said the podspec links the shim into
  the application binary. CocoaPods builds it into a framework the application
  loads at launch. `DynamicLibrary.process()` is right either way, and it is
  the reason it is right that changes.

* `ffigen.yaml`'s function filter matched none of the shim's 60 symbols, so
  `dart run ffigen --config ffigen.yaml` emptied `lib/src/box2d.g.dart` instead
  of regenerating it. The checked-in bindings were always correct; regenerating
  from them was not.
* `gooJointCreateMouse` now documents the anchor-ordering trap and its
  measurement. That section was in the C header and had never reached the
  generated file, so it was absent from the published API docs.
* `gooShapeEnableContactEvents` and `gooShapeEnableSensorEvents` say what the
  flags do and how contacts and sensors differ, in place of a reference to a
  plan that no longer exists.
* No comment names `RULES.md`, which is not in the repository. The two rules
  cited were the no-allocation hot-path rule and one fact, one place, both on
  the docs site.
* Every doc comment on `Box2DBindings` now leads with what the call does and
  what you have to get right, in place of arguing the design against
  alternatives you cannot see. Signatures and symbols are unchanged; the text
  on pub.dev is new.
* `gooThreadPoolCreate` said it starts `workerCount - 1` threads. It starts
  `workerCount`, and the calling thread never runs a slice. `goo_threads.h`
  also said Box2D's solver enqueues `workerCount - 1` tasks; it enqueues
  `workerCount`.
* `goo_box2d.c` said the shim holds no state, three lines above the thread-pool
  array it holds.
* The missing-library `StateError` now prints a command the host platform can
  run. It told every reader to run `powershell -File tool/build_native.ps1`,
  which is not a command on Linux. Off Windows it gives the two cmake commands
  against `src/CMakeLists.txt`, and it names the `build/<operating system>`
  directory it just searched, because a build written anywhere else succeeds
  without being found.

## 0.1.1

Documentation only. No code changes.

README links now resolve on pub.dev.

## 0.1.0

First published release. Raw FFI bindings to Box2D:

* **Box2D v3.1.1 vendored** (MIT, © Erin Catto — see `src/box2d/LICENSE`)
  behind a flat C shim.
* Bindings generated over that shim, and a worker-thread pool so the solver can
  run across cores.
* Builds on Windows, Linux, Android, macOS and iOS.

This is the raw binding layer. Use
[`goo2d_physics_box2d`](https://pub.dev/packages/goo2d_physics_box2d) for the
ECS-facing API; depending on this package directly means managing worlds and
bodies by hand.

## 0.0.1

* Package scaffolded, no bindings generated. Never published.
