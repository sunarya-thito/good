# The asset pipeline

Three stages turn the art you edit into the bytes you ship.

```
assets_src/                    good assets compact      assets/
  sprites/player.png     ──────────────────────▶        sprites/player.webp
  sfx/hit.wav              (ffmpeg, one format          sfx/hit.ogg
                            per kind)
                                     │
                                     │ good generate    lib/good.generated/
                                     ├───────────────▶   textures.dart
                                     │                   audios.dart
                                     │
                                     │ good assets pack assets/packed/
                                     └───────────────▶   chunk_main.dat
                                        (compress,        chunk_shared.dat
                                         then encrypt,
                                         then chunk)
```

## Configuration

Everything is configured in the pubspec's `good:` section — not a second file
beside it. A project already has one file that says what it is and what it
ships, and this puts the asset *source* directory next to the `flutter: assets:`
list that names the *output*.

```yaml title="pubspec.yaml"
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

flutter:
  assets:
    - assets/
    - assets/packed/
```

Every value shown is the default, and the whole section is optional.

| Directory | Committed? | Contents |
|---|---|---|
| `assets_src/` | **Yes** | Your originals, in whatever format you work in |
| `assets/` | Safe to gitignore | Canonical files. Rebuilt by `good assets compact` |
| `assets/packed/` | Safe to gitignore | Release chunks. Rebuilt by `good assets pack` |

Both `assets/` and `assets/packed/` must appear under `flutter: assets:` — that
list is the only thing Flutter bundles from. A release build fills `packed` and
then empties `output` of everything it generated, so the two are listed together
and only one of them ever ships anything.

---

## Stage 1 — compaction

```bash
good assets compact
```

One canonical format per kind: **WebP** for images, **Ogg Vorbis** for audio.

```console
$ good assets compact
  sprites/player.png -> sprites/player.webp
1 written, 0 up to date, 0 failed.
```

The source tree's shape is preserved — `ui/button.jpg` becomes `ui/button.webp`,
not `button.webp` — because the output path is what becomes an identifier, and
flattening would create collisions the source tree deliberately avoided.

!!! info "Compaction is not a release-only step"
    Development and release load byte-identical files, because both load the
    *output* directory. A format bug that only appeared in release would be the
    worst kind, so both modes go through the same conversion.

### Incremental by default

A hash of each source plus its conversion settings is kept in
`assets/.good_compact.json`, so an unchanged file is skipped:

```console
0 written, 1 up to date, 0 failed.
```

`--force` reconverts everything, which is what to reach for after changing
`quality` in the pubspec.

A file already in the canonical format is **copied, not re-encoded** —
re-encoding a WebP to WebP is generation loss, and running ffmpeg over a file
that is already right is time spent making the asset slightly worse.

### ffmpeg

Compaction needs ffmpeg and downloads one if your `PATH` has none. In CI, pass
`--no-download` to make a missing ffmpeg an explicit failure rather than a slow
surprise.

### Files it has no rule for

Anything compaction cannot convert is reported as skipped, with a reason, rather
than silently dropped. Put files that are already final — a JSON level
definition, a font — directly in the output directory; nothing there is
regenerable, so nothing there is ever stripped.

---

## Stage 2 — generation

```bash
good generate
```

Scans what the pubspec declares under `flutter: assets:` and writes four files.

```console
$ good generate
Wrote ./lib/good.generated/textures.dart
Wrote ./lib/good.generated/audios.dart
Wrote ./lib/good.generated/good.dart
1 texture(s), 0 audio file(s).
```

| File | Rewritten | Contents |
|---|---|---|
| `textures.dart` | every run | One enum value per shipped image |
| `audios.dart` | every run | One enum value per shipped audio file |
| `good.dart` | every run | `ensureGameReady()`, the startup check |
| `asset_key.dart` | **once** | Encryption keys, and the chunk mapping |

!!! danger "`asset_key.dart` is written once, deliberately"
    Its keys decrypt the packs already built with them, so regenerating would
    orphan every shipped build. `good generate --rotate-keys` changes them
    deliberately — and every existing pack stops decrypting, so repack
    immediately after.

    **Commit this file.** It is generated, and it is also the only record of
    your keys.

### Subdirectories must be listed

Flutter's directory entries bundle files, not subdirectories. Compaction says so
when it notices:

```console
These directories now hold assets but are not listed under `flutter: assets:` in pubspec.yaml,
so Flutter will not bundle them and `good generate` will not see them:
  - assets/sprites/
```

```yaml
flutter:
  assets:
    - assets/
    - assets/packed/
    - assets/sprites/
```

---

## Stage 3 — packing

```bash
good assets pack
```

```console
$ good assets pack
1 asset(s) in 1 chunk(s), grouped by scene (1 scene(s); 0 asset(s) shared or unattributed).
  mode: release, encryption: aes, compression: normal
Wrote 1 chunk(s) to ./assets/packed/
  2082 bytes of assets -> 2117 bytes packed (102 per cent)
```

### Grouping by scene

Chunks are grouped so that **loading a scene reads its own chunk and at most the
shared one**. The packer scans your `lib/` statically to work out which scene
declares which asset.

Anything it cannot attribute to a scene goes in the shared chunk, and it says
how many:

```console
3 declaration(s) could not be attributed to a scene statically; their assets go
in the shared chunk. Run with --verbose to see them.
```

A project the scan cannot read anything out of falls back to grouping by
top-level directory rather than failing. The chunk format and the runtime do not
care how members were chosen, only that the mapping agrees with them.

### Compress, then encrypt — never the other way

Encrypted bytes are indistinguishable from random and **do not compress at
all**. Encrypt-then-compress produces a larger file and exactly the same
security — pure loss. Compress first and the ciphertext is as small as the
plaintext could be made.

### The chunk format

```
┌────────┬─────────┬───────┬──────────┬─────────┬──────────────────┐
│ 'GOOC' │ version │ flags │  nonce   │ GCM tag │    ciphertext    │
│ 4 B    │ 1 B     │ 1 B   │ 12 B     │ 16 B    │  the whole chunk │
└────────┴─────────┴───────┴──────────┴─────────┴──────────────────┘
```

Magic and version first, so a runtime reading a chunk from a future good **says
so** rather than decrypting nonsense. Flags carry compressed/encrypted
separately, because `--encryption=none` is a real combination.

The nonce is derived from a **hash of the compressed body**. GCM's one
unforgivable failure is a repeated (key, nonce) pair, and deriving from content
means two chunks cannot collide unless their bytes are identical — in which case
they are the same chunk and reusing the nonce leaks nothing new. It also makes a
pack **reproducible**, which a random nonce would not.

!!! question "Why seal whole chunks rather than individual assets?"
    A per-asset scheme needs an index outside the ciphertext saying where each
    asset begins and how long it is — and that index is a **map of the whole
    pack in plaintext**, which is most of what packing was meant to stop being
    trivial. Sealing whole chunks puts the index inside the ciphertext.

### What encryption is and is not

AES-256-GCM, and it **deters casual extraction**. It is not DRM against a
determined reverse engineer: the key ships in the binary, because the game has
to decrypt its own assets to draw anything.

The generated keys are four `final` lists combined at run time, not `const` — a
`const` list is folded into the binary's constant pool where `strings` finds it,
while a `final` one is assembled at run time. Neither stops someone with a
debugger, and the design says so plainly rather than implying more.

### The mapping

Packing writes the result back into `asset_key.dart`:

```dart
final Map<String, String> assetMapping = <String, String>{
  'assets/sprites/player.webp': 'assets/packed/chunk_shared.dat',
};
```

`ensureGameReady()` installs the pack when this is non-empty. It is rewritten
even when empty, because switching a project back to development mode has to
*clear* a stale mapping — otherwise the runtime keeps looking for chunks that
are no longer built.

### Options

| Option | Default | Notes |
|---|---|---|
| `--mode=<development\|release>` | `release` | Development writes nothing and clears the mapping |
| `--encryption=<none\|aes>` | `aes` | Packing without encrypting leaves every file header legible in a hex editor |
| `--compression=<none\|fast\|normal\|best>` | `normal` | Applied before encryption |
| `--output-dir=<dir>` | the `packed:` directory | Rarely worth overriding — a chunk written where Flutter does not bundle silently ships no assets |
| `--dry-run` | off | Report the plan, write nothing |

### What packing does not do

It writes the chunks and **leaves the loose assets where they are**, so running
`flutter build` straight after bundles both. Only `good build` strips them — and
only there, because only there is good the one who compacted them and can say
which files are safe to delete.

```console
stripped 1 loose asset(s) now carried in chunks; `good assets compact` rebuilds them
```

Deleting a working directory's assets out from under someone who asked for a
pack is not `good assets pack`'s call to make.

---

## Doing it by hand

`good build` runs all three in order. If you run them yourself, the order is:

```bash
good assets compact       # 1. canonical files
good generate             # 2. enums, from those files
good assets pack          # 3. chunks, writing the mapping back
flutter build windows    # 4. bundle whatever is on disk
```

Out of order produces a build that is **stale rather than broken**, which is
worse. Prefer `good build`.

---

## Next

[Building for a platform →](building.md)
