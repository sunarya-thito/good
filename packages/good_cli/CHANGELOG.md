## Unreleased

### Changed

* **`good create` scaffolds its system's query as a field.** The generated
  `SpinSystem` writes `final _players = Query.all(Transform3D, Player);`
  instead of a `describeQuery` override, matching the field form `good` now
  offers (#91).

### Fixed

* **`good build` no longer deletes files from `assets/` when `strip-originals`
  is not set.** The default (`strip-originals: false`) now leaves every file in
  the asset output directory untouched. Assets declared with
  `Image.asset('assets/...')` in Flutter widgets survive the release build and
  resolve correctly at run time. Set `strip-originals: true` in `good: assets:`
  to keep the old behaviour of removing loose copies once they are inside a
  chunk.

* **`texture: quality: 100` now produces a byte-exact WebP.** It emitted
  `-lossless 1`, but after `-pix_fmt yuva420p`, so ffmpeg halved the chroma
  and libwebp then stored the damaged image exactly. On a 64x32 fixture whose
  texel `(x, y)` is a function of `x` and `y`, that decoded back with 2960 of
  8192 bytes changed and took 1254 bytes on disk; through `-pix_fmt bgra` it
  is identical to its source in 70 bytes. There is no lossy step left at 100,
  and nothing to configure - the setting finally does what
  `packages/good_cli/lib/src/config.dart` says it does.

  `bgra` replaces `yuva420p` below 100 too. The flag was there to keep alpha
  from being negotiated away, which `bgra` does equally, and measured against
  each other the two are within noise on both size and error - except that
  `bgra` reproduces a partially transparent sprite's alpha exactly where
  `yuva420p` moved it by one.

  Expect one slow `good assets compact` after upgrading: every texture
  re-encodes, including the ones the journal called up to date. A journal
  entry now records the ffmpeg flags themselves instead of a summary
  assembled from config values, because the pixel format is not a config
  value and a summary of config values cannot see it change.

* **`good generate` no longer refuses a private column name that two libraries
  both declare.** A `_`-prefixed name is private to its library, so two
  component mixins in different files each declaring `final _dirty =
  Field.boolean()` declare two independent members - both columns reachable,
  both wanted. The shadowed-field check compared bare names, called that a
  collision and threw before writing anything, which stopped `good generate`,
  `good build` and `good create` alike on correct code. Its advice did not
  help either: a private name has no cross-library collision to prefix away.

  A private name that collides inside one library is still reported, and the
  library is the language's and not the file: `part` splits one library across
  several files, and two parts of it declaring `_dirty` do collide. That comes
  off the `part` directives of files the scan already parses, so nothing about
  it costs a resolution.

* **The API documentation no longer teaches `good compile`.** The worked
  examples on `Command`, `CommandRunner` and `BuildCommand` all named it, and
  no published release has had such a command: it was `goo compile` in the
  pre-release `goo_cli`, became `build` before 0.1.0, and 0.1.0 shipped
  `good build windows|linux|android|ios`. Copying one of those examples gets
  `Unexpected argument "compile"` and a usage block listing the four commands
  there are. Examples that want a real command now say `good build`; the ones
  showing only the shape of a command tree say `my_command`, so nothing on the
  page reads as a `good` invocation that is not one.

## 0.2.0

Six changes stop a build that worked at 0.1.1. Each one turns something that
used to fail quietly, or not at all, into something that fails while you are
looking at it.

### Breaking

* **`--dimension=d2|d3` on `good create` is now `--2d` and `--3d`.** The old
  option is gone, and a command line still using it exits 64. `d2` and `d3`
  existed because a Dart enum value cannot begin with a digit, which was never
  a reason for you to type them.
* **`good build` exits 70 when a step fails.** It printed the error and exited
  0, so a CI job wrapped around a broken build passed, and
  `good build windows && upload` uploaded. Failure now has a code everywhere:
  64 for a malformed command line, 65 for something a command read, 70 for work
  that could not finish.
* **`good generate` fails on an asset directory the pubspec does not list.**
  `flutter: assets:` entries are not recursive, so a file in `assets/ui/` was
  bundled nowhere and got no enum value, and nothing said so. The error names
  the exact line to add.
* **`good generate` fails when two components declare the same field name.**
  Both columns were allocated and one of them was unreachable, so a row spent
  128 bits where one mixin uses 64. Rename one of the fields.
* **`good generate` fails on a component mixin whose `describeType`,
  `describeAssets` or `describeStruct` override drops its `super` call.** A
  mixin like that contributed no columns and no query bit, silently. Chain the
  call.
* **`good build` refuses to strip an asset compaction cannot rebuild.** A file
  you placed in `assets/` yourself is packed like any other, and removing the
  loose copies would delete the only one that exists. Move those files into
  `assets_src/` so compaction owns them, or set `strip-originals: true` under
  `good: assets:` to let the build delete them. At 0.1.1 they shipped twice,
  once inside the chunk and once in plaintext beside it.

### Added

* **`good create --3d` scaffolds a project that builds and runs.** It used to
  print `goo3d does not exist yet` and stop. What it writes is what `goo3d`
  has — a `Transform3D` prefab, a camera, the composition system and a system
  that turns the entity once per tick — and each file says in its comments what
  is missing and which issue brings it.
* **`strip-originals`** under `good: assets:`, covering the refusal above.
* **`good generate` reports an unbundled asset with exit 65**, so a build script
  can tell a bad pubspec from a command it typed wrong.

### Fixed

* **`good create` writes its own `lib/main.dart`.** `flutter create` runs first
  and writes a counter app, and the scaffolder skipped every file that already
  existed, so a new project ran Flutter's demo and the log said
  `Kept existing lib/main.dart`. A project you reach through
  `--no-flutter-create` is still never overwritten.
* **The scaffolded `test/widget_test.dart` compiles.** It named `MyApp`, which
  stops existing the moment `main.dart` is the good one, so `flutter analyze`
  failed on a project one minute old. It now builds the real app and waits for
  the game to start.
* **Re-running `good create --no-flutter-create` no longer breaks the pubspec.**
  The check for "already added" matched the literal line it had written, so a
  constraint you had pinned, widened or moved under a comment read as absent and
  the command appended a second `goo2d:` and a second `assets:`. A duplicate
  mapping key is not a bad merge to clean up; every `flutter` command refuses to
  read the file at all.
* **The compaction journal moved to `.dart_tool/good/compact.json`.** It sat in
  the asset directory, which `flutter: assets:` lists, and flutter_tools bundles
  dotfiles like anything else — so every release carried the name and SHA-256 of
  every source file, in plaintext beside the encrypted chunks. A journal at the
  old path is picked up once so nothing re-encodes, then deleted.
* **A scaffolded project's engine constraint is `^0.1.0`.** It was `^0.0.1`,
  which has admitted no published version since 0.1.0, so a new project failed
  `flutter pub get` on any machine without a path override.

## 0.1.1

Documentation only. No code changes.

The README now shows the actual commands, and no longer calls the package a
placeholder or advertises `good codegen` and `good run`, which do not exist.

## 0.1.0

First published release. The `good` command is implemented and verified end to
end, not scaffolded:

* **`good create`** — scaffolds a project that compiles and runs.
* **`good generate`** — writes asset bindings (e.g. a populated `Textures`
  enum) by scanning the project with `package:analyzer`.
* **`good assets compact`** — one canonical format per asset kind, via ffmpeg,
  which it will download on demand.
* **`good assets pack`** — scene-grouped chunks, compressed then encrypted
  (AES-256-GCM), plus the mapping the runtime loads.
* **`good build windows|linux|android|ios`** — runs the pipeline and ships each
  asset exactly once.

Known rough edges are listed in the documentation's implementation-status page
instead of hidden here; the notable ones are that `good create` keeps
Flutter's own `main.dart`, and that re-running it after editing the pubspec can
duplicate keys.

Not here yet: struct-layout codegen (hoisting the runtime `DataDescriptor`
algorithm to build time), `good build macos`, and `good run`.

## 0.0.1

* Package scaffolded. Never published.
