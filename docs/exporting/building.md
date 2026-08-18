# Building for a platform

```bash
good build windows
good build linux
good build android
good build ios
```

One command per platform rather than one command with a `--platform` option,
because they are genuinely different: each grows its own signing, bundling and
packaging options, and an option that applies to one target is one every other
target's help has to explain away.

| Command | Runs | Produces |
|---|---|---|
| `good build windows` | `flutter build windows` | `build/windows/x64/runner/Release/` |
| `good build linux` | `flutter build linux` | `build/linux/x64/release/bundle/` |
| `good build android` | `flutter build apk` | `build/app/outputs/flutter-apk/` |
| `good build ios` | `flutter build ios` | An Xcode archive to sign |

## Options

Every platform shares these:

| Option | Default | What it does |
|---|---|---|
| `--project-dir=<dir>` | `.` | The project to build |
| `--assets=<development\|release>` | `release` | Loose files, or a packed bundle |
| `--asset-encryption=<none\|aes>` | `aes` | Encryption for packed assets |
| `--asset-compression=<none\|fast\|normal\|best>` | `normal` | Compression, applied before encryption |
| `--no-download` | off | Fail rather than downloading ffmpeg when none is installed |
| `--dry-run` | off | Report the plan and do nothing |
| `--verbose` | off | Show every file the pipeline touches |

### Check the plan first

```console
$ good build windows --dry-run
good build windows
  project:     .
  assets:      release
  encryption:  aes
  compression: normal

Would run, in order:
  1. good assets compact
  2. good generate
  3. good assets pack --mode=release
  4. flutter build windows
```

### Development assets in a platform build

```bash
good build windows --assets=development
```

Loose files in a real platform build — for a debugging build you intend to poke
at. The command tells you when a setting has nothing to act on rather than
silently resolving it:

```console
  note: --assets=development loads loose files, so --asset-encryption has no effect.
```

---

## Per-platform notes

=== "Windows"

    Needs Visual Studio with the *Desktop development with C++* workload.

    ```
    build/windows/x64/runner/Release/
    ├── my_game.exe
    ├── flutter_windows.dll
    ├── *_plugin.dll              ← one per plugin, incl. Box2D if used
    └── data/
        ├── icudtl.dat
        ├── app.so
        └── flutter_assets/
    ```

    **Ship the whole directory.** The `.exe` alone does not run.

=== "Linux"

    Needs `clang`, `cmake`, `ninja-build`, `pkg-config` and `libgtk-3-dev`.

    ```
    build/linux/x64/release/bundle/
    ├── my_game
    ├── lib/
    └── data/flutter_assets/
    ```

    The bundle is relocatable. For distribution, wrap it — AppImage, Flatpak, or
    a tarball with a launcher script.

=== "Android"

    Needs the Android SDK, and the **NDK** if you use physics: Box2D is compiled
    through Gradle's CMake integration for each ABI.

    `good build android` produces an APK. For Play Store submission you want an
    App Bundle, which Flutter builds directly:

    ```bash
    good build android --dry-run     # run the asset pipeline steps you need
    flutter build appbundle
    ```

    Signing is configured in `android/app/build.gradle.kts` as it is for any
    Flutter app; good does not interpose.

=== "iOS"

    Needs Xcode and CocoaPods. Box2D compiles through a podspec and links
    statically.

    `good build ios` produces an archive to sign and upload through Xcode or
    `xcrun`. Signing identities and provisioning profiles are Xcode's business.

=== "macOS"

    There is no `good build macos` target yet. Run the pipeline steps and then
    Flutter directly:

    ```bash
    good assets compact && good generate && good assets pack
    flutter build macos
    ```

!!! warning "No web target"
    The kernel uses `dart:ffi` for component storage and spawns an isolate for
    the simulation. Neither exists on the web.

---

## What ends up in the bundle

After a release build, the loose assets are gone and the chunks remain:

```
data/flutter_assets/assets/
├── .gitkeep
├── .good_compact.json              ← the incremental-compaction cache
└── packed/chunk_shared.dat        ← your assets
```

Each asset ships exactly once. `.good_compact.json` is the compaction cache; it
is small, and it names your *source* files, so treat it as one more reason not
to put anything sensitive in a filename.

Restore the loose files for further development with:

```bash
good assets compact
```

---

## Reproducible builds

A pack is byte-reproducible given the same inputs:

- the chunk nonce is derived from a hash of the compressed body, not randomly;
- gzip headers have their modification time zeroed;
- chunk membership is sorted.

Two builds of the same commit with the same `asset_key.dart` produce identical
chunks. That is worth knowing when diffing artifacts, or verifying a release
came from the source it claims to.

---

## CI

```yaml
- run: dart pub global activate good_cli
- run: flutter pub get
- run: good build windows --no-download --verbose
```

`--no-download` is the flag that matters: it turns "quietly fetch an ffmpeg"
into an explicit failure, so a CI machine's toolchain is a decision rather than
an accident. Install ffmpeg as a build step instead.

Cache `assets/` between runs to keep compaction incremental — the
`.good_compact.json` hash cache is what makes an unchanged asset free.

!!! danger "`asset_key.dart` must be in the repository"
    A CI machine that regenerates it produces a build whose assets no previously
    shipped client can read, and whose own chunks no *other* build can read.
    Commit it.

---

## Next

[Troubleshooting →](troubleshooting.md)
