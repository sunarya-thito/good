# Exporting a game

Shipping a good game is one command:

```bash
good build windows
```

It runs four steps in the order that makes them correct, and the order is the
whole reason the command exists:

```
[1/4] compacting assets     source art  ->  one canonical format per kind
[2/4] generating bindings   canonical   ->  lib/good.generated/
[3/4] packing assets        canonical   ->  compressed, encrypted chunks
[4/4] flutter build windows everything on disk  ->  an application
```

Compaction writes the canonical files. Generation reads *those* and emits the
enums, so it has to follow. Packing reads the generated key material and writes
the chunk mapping back into the same file, so it follows generation.
`flutter build` bundles whatever is on disk by then, so it goes last.

!!! tip "Running these by hand in the wrong order does not fail"
    It produces a build that is subtly **stale** , not one that errors —
    which is exactly the mistake this command exists to remove.

## What a release build produces

```console
$ good build windows
good build windows
  project:     .
  assets:      release
  encryption:  aes
  compression: normal

[1/4] compacting assets
0 written, 1 up to date, 0 failed.
[2/4] generating bindings
Wrote ./lib/good.generated/textures.dart
1 texture(s), 0 audio file(s).
[3/4] packing assets
  1 asset(s) in 1 chunk(s), grouped by scene (1 scene(s); 0 asset(s) shared or unattributed)
  stripped 1 loose asset(s) now carried in chunks; `good assets compact` rebuilds them
[4/4] flutter build windows

Built windows.
```

The shipped bundle contains the chunks and **not** the loose files — each asset
ships exactly once:

```
build/windows/x64/runner/Release/
├── my_game.exe
├── flutter_windows.dll
└── data/flutter_assets/assets/
    └── packed/chunk_shared.dat        ← the assets, compressed and encrypted
```

## The three pages

<div class="grid cards" markdown>

- **[The asset pipeline](asset-pipeline.md)**

    Compaction, chunking, compression, encryption, and why the order is
    compress-then-encrypt.

- **[Building for a platform](building.md)**

    Every target, the options that matter, and what to do about signing and
    packaging.

- **[Troubleshooting](troubleshooting.md)**

    The failures the pipeline can produce, and what each one means.

</div>

## Development versus release

The two modes want opposite things, and both are first-class.

| | Development | Release |
|---|---|---|
| Assets | Loose files | Chunked |
| Compression | None | gzip |
| Encryption | None | AES-256-GCM |
| Asset mapping | Empty | Path → chunk |
| Resolution | Straight through `rootBundle` | Through the installed `AssetPack` |
| How you get it | `flutter run` | `good build <platform>` |

**Development leaves everything alone.** The shortest path from a changed file
to seeing it is not to touch it, so `flutter run` loads loose files and nothing
is packed at all.

**Nothing in your game code differs between the two.** The same logical path
resolves through `rootBundle` in one and out of an encrypted chunk in the other.

`good build` defaults to release because `flutter run` is the development path
and does not come through here — someone typing `good build windows` is making
something to ship. Pass `--assets=development` if you want a platform build
with loose assets, for a debugging build you intend to poke at.

## Before you ship

- [ ] `flutter analyze` is clean.
- [ ] `lib/good.generated/asset_key.dart` is **committed** — it is the only
      record of your encryption keys, and losing it orphans every pack already
      shipped.
- [ ] Both `assets/` and `assets/packed/` are listed under `flutter: assets:`.
- [ ] `ensureGameReady()` is called before `Game.start` — it catches a missing
      asset before the first frame instead of mid-scene.
- [ ] A release build has actually been run and launched, not just compiled.

---

## Next

[The asset pipeline →](asset-pipeline.md)
