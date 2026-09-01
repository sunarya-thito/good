## Unreleased

### Breaking

* **`good generate` checks only `describeStruct` for a missing `super`**
  (#287). `describeType` and then a component's `describeAssets` both left the
  set, because what they declared moved onto a field initialiser and no chain
  runs through one, so the defect the check exists for cannot be written.

* **An asset key `good build` cannot read is named where it was written**
  (#287). A prefab declaring `Asset.of(keys[i])` is reported as
  `Plane.Asset.of` rather than `Plane.describeAssets`, which no longer exists
  on a prefab. A scene's hook is still reported as `S.describeAssets`.

* **The scaffolded `lib/game.dart` teaches `Asset.of`** (#287). Its comment
  showed a `describeAssets` override; it shows the field now.

  The component-type scan reads `Component.type<T>()` field initialisers
  instead of `has<T>()` calls inside a `describeType` body. It matches on the
  receiver name `Component`, exactly as the column check matches on `Field`,
  with the same liability: a declaration static on some other type is invisible
  until that is edited.

### Changed

* **The scene scan reads field initialisers, not only method bodies.** It kept
  `describeAssets` and `describeScene` bodies and skipped everything else, so
  `final texture = Asset.of(Textures.player)` was attributed to no scene. That
  never lost an asset - `_planByScene` puts an unattributed asset in the shared
  chunk and it still ships - but the scene paid a chunk read it did not need,
  and the cost grows as declarations move to where they are used (#194).

  `EntityStruct.of` in a field initialiser is read for the same reason, and
  that closes a gap that predates it: a child prefab declared that way
  contributed nothing here, so its own assets were unattributed too.

  Static field initialisers are deliberately not read. A static is lazy, so it
  runs on first read rather than during the pass both isolate copies replay,
  and the runtime refuses it - reading it here would attribute an asset no
  scene ever declares.

* **`good generate` reads a package because it depends on the engine, not
  because of its name.** The shadowed-field and chained-hook checks decided
  which of your dependencies to parse with
  `name == 'good' || name.startsWith('goo')`, so every project with
  `google_fonts` - or `google_sign_in`, `googleapis`, `goodies`, `gooey` - had
  that package's whole `lib/` walked by a component scan on every run, and a
  third-party component package named anything else was invisible to it. A
  package is now read when `package:good` is in the transitive closure of its
  `dependencies:`, so a physics backend that names only `goo2d` is read and
  `google_fonts` is not (#305).

  Nothing to do about it. If you had a dependency being read for its name
  alone, it is no longer parsed, and the run is faster; if you depend on a
  component package this check could not see, collisions with its columns are
  reported from now on where they were silent before.

* **The package the generated files import comes from the dependency graph.**
  `good generate` chose it from `['goo2d', 'goo3d', 'good']`, first match wins,
  so a project built on a renderer that is not one of those three fell through
  to `good` and generated code importing the kernel. The choice is now the
  project's direct dependencies narrowed by the same engine test as above, and
  then to the one none of the others is built on: a project depending on a
  renderer and on the kernel imports the renderer, and a project depending on
  a renderer that depends on `goo2d` imports that renderer (#309).

  It reads each candidate's own pubspec through
  `.dart_tool/package_config.json`. A dependency added since the last
  `flutter pub get` is in no package config, so nothing says it is an engine
  package and the fallback to `good` applies; resolving the project and running
  `good generate` again gives the right import. `good create` names the engine
  it scaffolded and does not go through this, so a fresh project is unaffected.

* **The scaffold emits the new component-read spelling.** `good create` wrote
  `group.get<Player>()` into the generated system; it writes `group<Player>()`,
  which is what `good` 0.3.0-dev accepts after `get`/`tryGet` folded into the
  receiver's own call (#220).

* **The shadowed-field check sees two shapes it was missing.** `_isColumn`
  recognises a declaration by the receiver's name, and `InitialPointer` -
  which is what `hasFloat64` and the rest actually return - was not in the set
  of column types, so `late final InitialPointer<double> speed;` written in
  the older form fell through the check entirely (#262, #210).

  The scan also parses with `dot-shorthands` enabled now. A column written
  `Field.array(.uint16, 4)` parsed to the right tree either way, since the
  shorthand is an argument and the receiver is still the identifier `Field`,
  but a bare `parseString` reported `EXPERIMENT_NOT_ENABLED` on it. This pass
  never reads its diagnostics, so nothing was wrong today; a pass that did
  would have seen an error on every element-spelled array in the tree.

  The scaffolded game writes `cameraFieldOfView.initialValue`.

* **The scaffolded game writes `eye.cameraView[camera]`.** `Camera.view` is
  `Camera.cameraView` in `goo2d` 0.3.0-dev, and the starter project generated
  by `good create` follows it (#133). Nothing in this package's own API moves.
  The shadowed-field check reads the engine's declarations as it always did,
  so a project of yours colliding with one is still reported - there is just
  much less to collide with now.

* **Everything good generates moves into a package beside the project.** A
  project called `my_game` gets `my_game/my_game_bundle/`, and `lib/` holds
  nothing generated: `textures.dart`, `audios.dart`, `good.dart` and
  `asset_key.dart` are now `package:my_game_bundle/...` rather than
  `lib/good.generated/...` (#108, #113). The split is by who wrote a file
  rather than by what kind of file it is, so "may good overwrite this" has one
  answer instead of two. An existing project is migrated by the next
  generate - the four files move, `lib/good.generated/` goes away, and the
  imports that named it are repointed. `asset_key.dart` is carried over byte
  for byte, so the keys every shipped pack was built with are not rotated by
  the migration.

* **The bundle package's name is recorded in the pubspec, not derived from the
  project's.** `good: bundle: my_game_bundle` is written the first time the
  package is generated. A project renamed afterwards keeps pointing at the
  directory that already exists, rather than leaving a stale bundle on disk
  and in `dependencies:` while a second one is generated beside it (#113).

* **Nothing writes to or deletes from the bundle package without proof it is
  generated.** A `.good_bundle` marker is written into it and checked before
  anything else. Absent, the command refuses and names the path; so do two
  marked directories, a marked directory that is not the recorded name, and a
  `dependencies:` entry of that name pointing somewhere else. Regeneration
  rewrites in place rather than clearing and refilling, because the generated
  code is imported by package name and an empty package is every one of those
  imports failing to resolve.

* **Generating runs `flutter pub get` and checks what it wrote.** A path
  dependency that was never resolved does not fail a build - Flutter builds
  green and ships without the package. The resolve is skipped only when the
  project's package config already points at the bundle, and `--no-pub-get`
  turns it off for a caller that resolves for itself. Afterwards the files,
  the marker, both pubspecs and the resolved config are all read back, and
  anything wrong stops the command.

* **`good create` no longer tells you to run `flutter pub get`.** Generating
  the bundle package does it.

* **`good create` starts its game with a constructor.** The generated
  `main.dart` writes `await Game.start(MyGameGame.new)` rather than building
  the game and handing over the instance, following `good`'s `Game.start`
  (#91). Re-run `good create` for the new spelling; an existing project
  updates at its one start call.

* **The scaffolded `main.dart` no longer leaks the game when the widget is
  disposed mid-start.** It held a nullable field assigned *after* the await
  and called `_game?.stop()` in `dispose`, so a dispose landing during
  bring-up stopped nothing and the isolate outlived the widget. The teardown
  now hangs off the start future, which covers both orderings - and it has to,
  because `Game.start` is what builds the game and there is nothing to hold
  until it completes.

* **`good create` declares its systems with a constructor.** The generated
  `describeSystems` writes `descriptor.has(SpinSystem.new)` rather than
  `descriptor.has(SpinSystem())`, following `good`'s `SystemDescriptor.has`
  (#91). Re-run `good create` for the new spelling; an existing project
  updates by hand at each system declaration.

* **`good create` scaffolds its system's query as a field.** The generated
  `SpinSystem` writes `final _players = Query.all(Transform3D, Player);`
  instead of a `describeQuery` override, matching the field form `good` now
  offers (#91).

### Fixed

* **The `.good_bundle` marker is written before anything else in the generated
  package.** `good generate` created the package's `lib/` first, so a run that
  stopped in between - a closed terminal, a full disk - left a directory with
  nothing in it proving good had created it. Every later good command refuses
  such a directory by name, so the only way forward was deleting the package by
  hand. The order is the directory, the marker, then `lib/` and the files, and
  an interrupted run now leaves a package the next run finishes (#113).

* **`good create --no-flutter-create` stops before writing when the bundle
  package's name is taken.** A directory of that name carrying no marker, and a
  `dependencies:` entry of that name pointing somewhere else, were both found by
  the generate step at the end of the command - after the scaffold had written
  `lib/game/` and patched the pubspec into a project the command then declined
  to touch. Both are checked before the first file, and the project is left as
  it was (#113).

* **`good build` and `good assets pack` ask who owns the bundle package at their
  first step.** A build resolved it inside step 2, so a project whose bundle
  directory is not good's paid a whole compaction pass - every source asset
  re-encoded into `assets/` - before the refusal. Packing created the chunk
  directory before asking. Neither writes anything now until the question is
  answered (#113).

* **`good create --dry-run` reports the recorded bundle name.** It built the
  name from the `<project_name>` argument, so a dry run over a project whose
  pubspec records something else named a directory a real run would not write
  (#113).

* **`good build` no longer deletes files from `assets/` when `strip-originals`
  is not set.** The default (`strip-originals: false`) now leaves every file in
  the asset output directory untouched. Assets declared with
  `Image.asset('assets/...')` in Flutter widgets survive the release build and
  resolve correctly at run time. Set `strip-originals: true` in `good: assets:`
  to keep the old behaviour of removing loose copies once they are inside a
  chunk. The consequence is that both asset directories ship and a packed asset
  is bundled twice; the pubspec comment `good create` writes,
  `assets/packed/.gitkeep` and the exporting pages now say so (#270).

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
