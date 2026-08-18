# CLI reference

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

See [Create a project](../getting-started/create-a-project.md).

---

## `good generate`

```
Usage: good generate [options]
```

Writes `lib/good.generated/` from the assets the pubspec declares.

| Option | Default | Description |
|---|---|---|
| `--project-dir=<dir>` | `.` | The project to generate into |
| `--dry-run` | off | Report what would be written, and write nothing |
| `--rotate-keys` | off | Regenerate `asset_key.dart` |
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

Scans what the pubspec **declares** under `flutter: assets:`, not what is on
disk — a file in an unlisted directory is invisible to it, and to Flutter.

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
`assets/.good_compact.json`. A file already in the canonical format is **copied,
not re-encoded** — re-encoding is generation loss.

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

Writes the chunks and **leaves the loose assets alone**. Only `good build` strips
them — only there is good the one who compacted them and able to say which files
are safe to delete.

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

---

## Exit codes

`0` on success, non-zero on failure. Every failure prints what went wrong and,
where there is one, the command that fixes it.
