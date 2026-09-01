# CLI reference

```console
$ good --help
Usage: good <command> [options]

Commands:
  create    Scaffold a new Flutter project wired up to good.
  generate  Write the generated bundle package from the assets the pubspec
            declares.
  assets    Convert and pack the assets a project ships.
  build     Build and package a game for a target platform.

Options:
  --help  Show this help and exit.
```

The commands are listed in the order a project meets them: make one, generate
its bindings, build it.

## Installing

```bash
dart pub global activate good_cli
```

Or run it straight out of a clone, which is what to do in CI or when tracking
the engine's source:

```bash
dart run /path/to/goo2d/packages/good_cli/bin/good.dart <command>
```

## Syntax

| Form | Meaning |
|---|---|
| `--option=value` | An option and its value |
| `--option value` | The same |
| `--flag` | A flag. There is no `--no-flag` — leave it out to turn it off |
| `--` | Everything after is positional, however it is spelled |
| `--help`, `-h` | Works at every level: `good assets pack --help` |

`--verbose` is available on every command that does work, and shows every file
touched and every decision made.

---

## `good create`

```
Usage: good create [options] [project_name=]
```

Scaffolds a Flutter app wired up to good, patches the pubspec, and runs
`good generate`.

| Option | Default | Description |
|---|---|---|
| `<project_name>` | *(required)* | The package and directory name. Must be a valid Dart package name |
| `--directory=<dir>` | `.` | Where to create the project |
| `--2d` | on | Build against `goo2d` |
| `--3d` | | Build against `goo3d` |
| `--dry-run` | off | Report what would be created, and create nothing |
| `--no-flutter-create` | off | Write only the good files, into a project that already exists |
| `--verbose` | off | Verbose output |

```bash
good create my_game
good create my_game --directory=games
good create my_existing_app --no-flutter-create
good create my_game --dry-run
```

**Never writes over an existing file** — scaffolding is a starting point, and
replacing a `main.dart` someone has worked in is the one unrecoverable thing it
could do. **Refuses an existing directory** unless `--no-flutter-create`, because
`flutter create` rewrites platform folders.

**Stops before writing when the bundle package's name is taken.** Under
`--no-flutter-create` the name can already belong to a directory, or to a
`dependencies:` entry pointing elsewhere. Either exits 65 and names the path
before the first scaffold file and before the pubspec patch. Set `good: bundle:`
to a free name and run it again.

`--dry-run` reports the recorded name when the project has one, so the directory
it names is the one a real run would write.

See [Create a project](../getting-started/create-a-project.md).

---

## `good generate`

```
Usage: good generate [options]
```

Writes the generated bundle package — `my_game_bundle/` beside a project called
`my_game` — from the assets the pubspec declares.

Everything good generates lives there and nothing good generates lives under
`lib/`. The package's name is **recorded** in the pubspec's `good:` section the
first time it is written, so renaming the project later points at the directory
that already exists rather than building a second one beside it. A
`.good_bundle` marker inside proves the directory is good's; without it the
command refuses to write or delete anything there and names the path.

The marker is written before anything else in the directory. A run that stops
after it leaves a package the next run can finish; a run that stops before it
leaves no directory at all. `good build` and `good assets pack` ask the same
question at their first step, so a refusal costs no compaction pass and creates
no chunk directory.

### Which package the generated files import

`textures.dart`, `audios.dart` and `good.dart` import one engine package, and the
bundle's own pubspec depends on that same package. The project's dependencies
decide which: the direct ones that reach `package:good` through their own
pubspecs, narrowed to the one none of the others is built on. A project
depending on `goo2d` gets `package:goo2d`. A project depending on a renderer
that depends on `goo2d` gets that renderer, and `goo2d` is what it is built on.
No package name takes part, so a renderer somebody else publishes is found the
same way `goo2d` is.

The graph is read from `.dart_tool/package_config.json`. A dependency added
since the last `flutter pub get` appears in no package config, so nothing says
it is an engine package and the generated files import `package:good`. Resolve
the project and run `good generate` again. `good create` names the engine it
scaffolded and does not go through this.

| Option | Default | Description |
|---|---|---|
| `--project-dir=<dir>` | `.` | The project to generate into |
| `--dry-run` | off | Report what would be written, and write nothing |
| `--rotate-keys` | off | Regenerate `asset_key.dart` |
| `--no-pub-get` | off | Skip `flutter pub get` after writing the package |
| `--verbose` | off | Verbose output |

| File | Rewritten |
|---|---|
| `textures.dart` | Every run — a pure function of the pubspec |
| `audios.dart` | Every run |
| `good.dart` | Every run — `ensureGameReady()` |
| `asset_key.dart` | **Once**, then left alone |

!!! danger "`--rotate-keys`"
    Every existing asset pack stops decrypting. Repack immediately after, and
    understand that any build already shipped can no longer read a pack made
    with the new keys.

!!! warning "`--no-pub-get`"
    The resolve is what makes the path dependency real. Skip it and Flutter
    still builds — it builds without the generated package, exits 0, and says
    nothing. Use it only where something else runs `flutter pub get` after.

Scans what the pubspec **declares** under `flutter: assets:`, not what is on
disk — a file in an unlisted directory is invisible to it, and to Flutter.

### Texture sizes

`textures.dart` carries each image's pixel size, read from its header at
generate time. PNG, WebP, GIF, BMP and JPEG, from the leading bytes and not from
the extension. Nothing is decoded.

```dart
enum Textures with LocalEnumAssetKey<Texture> {
  sheet('assets/sheet.webp', 512, 256);
  // ...
}

abstract final class TextureSize {
  static const int sheetWidth = 512;
  static const int sheetHeight = 256;
}
```

Two forms, because they are not interchangeable. `Textures.sheet.width` reads
well; field access on an enum value is never a constant expression, so it cannot
appear in the `static const List<SpriteFrame>` tables
[Rendering](../guide/rendering.md#atlases-and-sprite-sheets) teaches.
`TextureSize.sheetWidth` can. Feed `SpriteFrame.pixels` and
`NineSliceBorder.pixels` from the constants and re-exporting the art at another
size needs no edit.

`Textures` and `TextureSize` are separate declarations because enum values and
static members share one namespace. That leaves the enum's own two field names
reserved: a texture whose path generates the identifier `width` or `height` —
`assets/width.png`, `assets/ui/height.png` — is refused at generate time, with
the path in the message.

A file whose header states no size generates `0` for both, and `good generate`
names it. Re-export it in one of the five formats above.

### Which payload type a texture key carries

`Texture` is declared in `goo2d`. A texture key is typed `Texture` where the
project's engine package reaches `goo2d` through its `dependencies:`, and
`Object?` where it does not. A renderer published on top of `goo2d` gets typed
keys the same way `goo2d` does; a `goo3d` project gets `Object?`, which is what
keeps `Texture isn't a type` out of its first `flutter analyze`.

The graph is read from `.dart_tool/package_config.json`. An entry package added
since the last `flutter pub get` is in no package config, so the keys come out
`Object?`; resolve the project and run `good generate` again. The sizes above
are emitted either way — a pixel dimension is an `int` and names no engine
type.

---

## `good assets`

```
Usage: good assets <command> [options]

Commands:
  compact  Convert source art into the one canonical format per kind.
  pack     Chunk, compress and encrypt the assets a build ships.
```

### `good assets compact`

Converts everything in the source directory into one canonical format per kind —
WebP for images, Ogg Vorbis for audio — using ffmpeg.

| Option | Default | Description |
|---|---|---|
| `--project-dir=<dir>` | `.` | The project whose assets to compact |
| `--dry-run` | off | Report the plan, convert nothing |
| `--force` | off | Reconvert everything, ignoring what is already up to date |
| `--no-download` | off | Fail instead of downloading ffmpeg when none is installed |
| `--verbose` | off | Verbose output |

Incremental by default: a hash of each source plus its settings lives in
`.dart_tool/good/compact.json`. A file already in the canonical format is
**copied, not re-encoded** — re-encoding is generation loss.

### `good assets pack`

Chunks, compresses and encrypts what a build ships, then writes the chunk
mapping back into `asset_key.dart`.

| Option | Default | Description |
|---|---|---|
| `--project-dir=<dir>` | `.` | The project whose assets to pack |
| `--output-dir=<dir>` | the `packed:` directory | Where chunks are written |
| `--mode=<development\|release>` | `release` | Loose files, or a packed bundle |
| `--encryption=<none\|aes>` | `aes` | Encryption for packed chunks |
| `--compression=<none\|fast\|normal\|best>` | `normal` | Applied **before** encryption |
| `--dry-run` | off | Report the plan, write nothing |
| `--verbose` | off | Show chunk membership |

Writes the chunks and **leaves the loose assets alone**. Removing them is `good
build`'s to do, and only when the project sets `strip-originals: true` — only
there is good the one who compacted them and able to say which files are safe to
delete.

`--mode=development` writes nothing and **clears** the mapping, which is what
switches a project back to loose assets.

See [The asset pipeline](../exporting/asset-pipeline.md).

---

## `good build`

```
Usage: good build <command> [options]

Commands:
  windows  Build for Windows.
  linux    Build for Linux.
  android  Build for Android.
  ios      Build for iOS.
```

Runs the whole pipeline in the order that makes it correct, then hands off to
Flutter:

```
[1/4] compacting assets
[2/4] generating bindings
[3/4] packing assets
[4/4] flutter build <target>
```

Every platform takes the same options:

| Option | Default | Description |
|---|---|---|
| `--project-dir=<dir>` | `.` | The project to build |
| `--assets=<development\|release>` | `release` | Loose files, or a packed bundle |
| `--asset-encryption=<none\|aes>` | `aes` | Encryption for packed assets |
| `--asset-compression=<none\|fast\|normal\|best>` | `normal` | Compression for packed assets |
| `--no-download` | off | Fail instead of downloading ffmpeg |
| `--dry-run` | off | Report the plan, and do nothing |
| `--verbose` | off | Verbose output |

One command per platform, not a `--platform` option, because each grows
its own signing and packaging options and an option that applies to one target
is one every other target's help has to explain away.

Release is the default **for a build**: `flutter run` is the development path
and does not come through here.

See [Building for a platform](../exporting/building.md).

---

## Configuration

Read from the `good:` section of the project's `pubspec.yaml` — not a separate
file. A project already has one file that says what it is and what it ships.

```yaml
good:
  assets:
    source: assets_src/       # originals you edit and commit
    output: assets/           # canonical files, generated
    packed: assets/packed/    # release chunks, generated
    strip-originals: false    # may a build delete art it cannot rebuild
  texture:
    format: webp
    quality: 90
  audio:
    format: ogg
    quality: 5
```

Every value shown is the default and every key is optional — a project with no
`good:` section works, because a new project should run before anyone has
configured anything. Directory values are normalised to end in `/`, so `assets`
and `assets/` mean the same thing.

Both `output` and `packed` must appear under `flutter: assets:` — that list is
the only thing Flutter bundles from.

`strip-originals` is off, so a build that packs leaves the loose copies in
`output` and every packed asset ships twice. Turning it on deletes the loose
copy of each one: those paths stop resolving through `Image.asset`, and a file
you put in `output` yourself is deleted with no source to rebuild it from. The
build names each of those as it goes. Turn it on when `source` holds every
original and `output` is disposable.

---

## Exit codes

`0` on success, non-zero on failure. Every failure prints what went wrong and,
where there is one, the command that fixes it.
