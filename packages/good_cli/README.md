# good_cli

The `good` command: it scaffolds a project, generates asset bindings, converts
and packs your assets, and builds the result for a platform.

```bash
dart pub global activate good_cli
```

## Starting a project

```bash
good create my_game
cd my_game
flutter run --flavor dev
```

A new project maps two flavors, `dev` and `prod`. `dev` ships the loose files
under `assets/` and `prod` ships the chunks built from them, so no build
carries both copies of an asset. Rename them, or use the flavors your project
already has, under `good: flavors:`.

## The asset pipeline

Drop source art in `assets_src/`, then:

```bash
good assets compact   # one canonical format per kind, via ffmpeg
good generate         # writes the generated bundle package beside the project
```

`good generate` is what lets you write `Textures.spritesPlayer` instead of a
string path, so a renamed file is a compile error, not a black square at
runtime.

## Shipping

```bash
good assets pack              # compress, encrypt, group into chunks
good build windows            # also: linux, android, ios
```

`good build` runs the pipeline first, so the release bundle carries the packed
chunks. It passes `--flavor` straight through to `flutter build`, and picks the
one bundled flavor for you when there is only one. What else the build carries
is what `flutter: assets:` says: that list and `good: assets:` are read
separately, so a file good packs is not thereby handed to Flutter's bundler.

`good generate` writes good's own entries into `flutter: assets:` and gates
each on the flavors that ship it, so Flutter's bundler leaves the originals out
of a `prod` build and the chunks out of a `dev` one. Entries in that list which
are not good's are left where they are.

## Next

- **[Create a project](https://sunarya-thito.github.io/good/getting-started/create-a-project/)**
- **[The asset pipeline](https://sunarya-thito.github.io/good/exporting/asset-pipeline/)**
  explains the chunk format and what the encryption does and does not protect.
- **[CLI reference](https://sunarya-thito.github.io/good/reference/cli/)**

`create`, `generate`, `assets compact`, `assets pack` and `build` for Windows,
Linux, Android and iOS work today and are verified end to end. `good build
macos` and `good run` are not written yet, and `good create` has rough edges
worth reading about before you hit them:
[what works today](https://sunarya-thito.github.io/good/reference/roadmap/).
