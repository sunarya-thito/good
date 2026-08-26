# Troubleshooting

<!-- snippet-scope
late Future<void> someFuture;
late DefaultPointer<bool> isBullet;
-->

The failures the pipeline can produce, what each one means, and what to do.

## Assets

### `pubspec.yaml does not list assets/packed/ under flutter: assets:`

```
pubspec.yaml does not list assets/packed/ under `flutter: assets:`, so the
chunks would be built and never bundled. Add it - good creates the directory
itself.
```

Checked **before anything is written**, because the failure it prevents is the
quietest in the pipeline: chunks build, the mapping points at them, Flutter
bundles none of them, and the game fails at its first asset load with every file
present on the build machine.

```yaml
flutter:
  assets:
    - assets/
    - assets/packed/
```

### `These directories now hold assets but are not listed`

```
These directories now hold assets but are not listed under `flutter: assets:`
in pubspec.yaml, so Flutter will not bundle them and `good generate` will not
see them:
  - assets/sprites/
```

Flutter's directory entries bundle files, **not** subdirectories. Add each one:

```yaml
flutter:
  assets:
    - assets/
    - assets/packed/
    - assets/sprites/
```

### `N asset(s) under the output directory are not bundled`

The same cause, caught later. `good generate` stops rather than writing an enum
with the file missing, and names the entry to add:

```
1 asset(s) under the output directory are not bundled: assets/ui/button.webp.
Flutter's `flutter: assets:` entries are not recursive, so a subdirectory needs
a line of its own. Add to pubspec.yaml:
    - assets/ui/
```

### The `Textures` enum is missing a value you just added

`good generate` scans what the **pubspec declares**, not what is on disk. If the
file is in a directory the pubspec does not list, generation now stops with the
message above instead of writing the enum without it. Fix the pubspec and
regenerate.

If the file is in `assets_src/` only, run `good assets compact` first — the
source directory is never scanned, because generating keys for
source art would name files that never reach the bundle.

### `Missing N asset(s) this build declares`

Thrown by `ensureGameReady()` at startup. Either the install is incomplete, or
the pubspec declares an asset that was never shipped. Re-running `good generate`
refreshes the declared set.

This check consults the manifest and at most stats a file — it never decodes —
which is why it can run over a whole game at startup.

### `Could not update assetMapping in .../asset_key.dart`

Packing writes the chunk mapping back into that file and could not. Run
`good generate` to recreate it; without the mapping, a packed build cannot find
its chunks.

### A release build loads no assets, with no error

The mapping is empty. Either packing did not run, or it ran in
`--mode=development`, which *clears* the mapping so the runtime
stops looking for chunks that are no longer built.

```bash
good assets pack --mode=release
```

### Assets vanished from `assets/`

Expected. A release build strips the loose copy of everything it packed, so each
asset ships exactly once, inside a chunk:

```
stripped 3 loose asset(s) now carried in chunks; `good assets compact` rebuilds them
```

`good assets compact` rebuilds whatever came from `assets_src/`, which is
everything a build will strip unless you have opted out of that protection.

### `N packed asset(s) cannot be rebuilt if the build strips them`

A file you put into `assets/` yourself came from no source. It ships, so packing
takes it, and stripping the loose copies would delete the only one there is. The
build stops before that happens:

```
1 packed asset(s) cannot be rebuilt if the build strips them:
    assets/handmade.png
Compaction did not produce these, so deleting the loose copy destroys the only
one. Leaving it in place ships a legible copy beside the encrypted chunk.

Choose one:
  - move them into assets_src/ so compaction owns them, or
  - add `strip-originals: true` under `good: assets:` in pubspec.yaml to accept
    the deletion.
```

Move the file into `assets_src/` and run `good assets compact`. Compaction owns
it from then on, the art survives, and the release ships it only inside a chunk.

Opt in when `assets_src/` already holds every original and `assets/` is
disposable:

```yaml
good:
  assets:
    strip-originals: true
```

The build strips those files and names each one as it goes.

### `Asset chunk is version N; this build understands 1`

A chunk built by a newer good than the runtime reading it. Rebuild the pack with
the same version you are shipping.

### Assets stopped decrypting after a rebuild

`asset_key.dart` was regenerated. Its keys decrypt the packs built with them, so
new keys orphan every existing pack. Restore the file from version control and
repack; use `good generate --rotate-keys` only when you mean it, and repack
immediately after.

### N declarations could not be attributed to a scene

```
3 declaration(s) could not be attributed to a scene statically; their assets go
in the shared chunk. Run with --verbose to see them.
```

Not an error. The packer scans `lib/` statically to group chunks by scene, and
anything it cannot attribute goes in the shared chunk — correct, just less
optimal. `--verbose` lists them if you want to make the declarations more
obvious to the scan.

## ffmpeg

### `ffmpeg is unavailable`

With `--no-download`, a missing ffmpeg is an error, not a download.
Install one, or drop the flag.

### N assets failed to convert

```
2 asset(s) failed to convert:
  sprites/broken.png: <ffmpeg's message>
```

The build **stops here**. Carrying on would ship a game missing an asset, and
the whole point of the readiness check is that that is not something to discover
at run time.

### A converted asset looks wrong

Change `quality` under `good: texture:` or `good: audio:` in the pubspec, then
force a reconversion — the incremental cache keys on the settings, but `--force`
is the reliable way:

```bash
good assets compact --force
```

## Project setup

### `<dir> already exists`

`good create` refuses to run `flutter create` over an existing tree, because that
rewrites platform folders. Use `--no-flutter-create` to add only the good files.

### `Duplicate mapping key` from every `flutter` command

The pubspec has two `goo2d:` entries or two `assets:` blocks. This happens if
`good create` re-patches a pubspec whose dependency line has been edited by hand
— the idempotence check matches the literal line it wrote. Remove the duplicate.

### `The name 'AssetKey' isn't a type`

The generated code is compiling against a different `goo2d` than the one it was
generated for. Check what the dependency actually resolved to:

```bash
grep -A3 '"name": "goo2d"' .dart_tool/package_config.json
```

If it points into `.pub-cache` when you expected your clone, switch to a `path:`
or `git:` dependency — see
[Getting the engine](../getting-started/installation.md#adding-the-engine).

## Running

### A black screen

In order of likelihood:

1. **Nothing was spawned.** `onSceneMounted` has to `scene.addEntity(...)`.
2. **The prefab has no `WorldTransform2D`.** The renderer reads world
   transforms; a prefab with only `Transform2D` is never drawn.
3. **The sprite has no size.** `width` and `height` default to `0`.
4. **The camera is looking elsewhere.** Remove the camera entirely to check —
   with no camera the projection sits at the origin and draws the whole world.
5. **`visible` is false**, or `zIndex` puts it behind something opaque.

### `LateInitializationError` on mount

A `late final` handle was read by a `describe*` pass that never assigned it —
almost always an asset used in `describeSprites` but not declared in
`describeAssets` on that same prefab. The scene declaring it does not assign
*your* field. Declare it in both places; it costs nothing.

### Entities appear at the origin for one frame, then snap

The prefab is not *finished* at mount. If the update loop derives a transform
from an angle, write that transform in `onEntityMounted` with the same
expression. An entity has to be complete when it is mounted, not completed by
the first pass that happens to see it.

### An entity is invisible with no obvious cause

Check `transformScaleX`/`transformScaleY`. A zero scale collapses every point to
the origin. `Transform2D` defaults them to `1` for this reason, but code that
writes a scale from a computed value can write a zero.

### Component writes seem to be discarded

They are outside the tick window. `beginTick` copies the last published snapshot
over the write slot, so anything written after `commitTick` is thrown away.
Almost always an `await` in gameplay code: `await` resumes on a microtask.

Use a coroutine, which is a `sync*` generator resumed inside the tick window:

```dart
yield WaitForFuture(someFuture);
```

### A read returns a stale value

An ordinary read returns the last **published** snapshot, not what you wrote a
moment ago in the same tick. That is by design. If a value must be read after it
is written, move the reader to a later phase instead of looking for a second
read method — see [Engine design rules](../reference/design-rules.md#do-not-add-a-specialised-variant-to-escape-a-constraint).

### The game never ticks

`Game` cannot be `FixedTickable` — it lives on the Flutter isolate, and the
compiler rejects it. Put the tick on the `GameState`, a `SceneStruct` or a
`GameSystem`.

### Input does nothing

There is no `GameView` in the widget tree, so nothing is feeding the device
state and every action reads its default. That is also the state of a
headless-plus-HUD game, which is legitimate — but if you expected input, check
the widget tree first.

### `StateError` reading an input's value

The action has no default anywhere and has never resolved. Give it one, or call
`super.describeInputs(input)` — dropping the shipped `bool`/`Vector2` defaults
is a silent failure until the first read.

## Physics

### Everything feels floaty

Units. Box2D wants **metres**, and works best with moving objects between
roughly 0.1 m and 10 m. A game treating one world unit as one pixel gives a
32-pixel crate the mass of a 32-metre building. Work in metres and apply the
pixels-per-metre scale once, at the camera's zoom.

### A dynamic body will not move where you put it

You are writing its `Transform2D`, which fights the solver. Box2D owns a dynamic
body's transform; apply forces or set velocity instead. Make it kinematic if you
want to drive it directly.

### Fast objects pass through walls

Tunnelling. Turn on continuous detection for the projectile:

```dart
isBullet.defaultValue = true;   // in the prefab's describeStruct
```

It costs real solver time, so put it on projectiles instead of on everything
that happens to move quickly.

### Physics is slow with a moderate body count

Cost follows the **contact graph**, not the count. Bodies crushed into a space
too small overlap, get pushed apart every step without converging, and never
sleep. Give the pile room before optimising anything else — and check body
counts for a leak, which looks identical from the outside.

### A body was destroyed but physics still costs the same

Check the body count against your entity count. If they diverge, bodies are not
being released when their entities are.

## Building

### `flutter build <target> failed`

good prints Flutter's own stdout and stderr. Read that first — the failure is
almost always Flutter's toolchain, not the pipeline. `flutter doctor`
next.

### Box2D fails to link

Nothing builds plugins outside a Flutter app. For `flutter test`, `dart run` or
a `tool/` script, build the native library once by hand, from the repository
root:

=== "Windows"

    ```powershell
    powershell -File packages/goo2d_ffi_box2d/tool/build_native.ps1
    ```

=== "Linux"

    ```sh
    cmake -S packages/goo2d_ffi_box2d/src \
          -B packages/goo2d_ffi_box2d/build/linux -DCMAKE_BUILD_TYPE=Release
    cmake --build packages/goo2d_ffi_box2d/build/linux --parallel
    ```

The build has to land in `packages/goo2d_ffi_box2d/build/<operating system>`,
which is where the loader looks. A generic `build/` succeeds and is then never
found. [Installation](../getting-started/installation.md#platform-toolchains) has
the rest, including why macOS and iOS have no route outside an app.

### The `.exe` runs on my machine but nowhere else

Ship the whole output directory. The executable needs `flutter_windows.dll`, the
plugin DLLs and `data/` beside it.
