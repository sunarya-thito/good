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
flutter run
```

## The asset pipeline

Drop source art in `assets_src/`, then:

```bash
good assets compact   # one canonical format per kind, via ffmpeg
good generate         # writes lib/good.generated/ — an enum per shipped asset
```

`good generate` is what lets you write `Textures.spritesPlayer` instead of a
string path, so a renamed file is a compile error , not a black square at
runtime.

## Shipping

```bash
good assets pack              # compress, encrypt, group into chunks
good build windows            # also: linux, android, ios
```

`good build` runs the pipeline first, so the release bundle carries the packed
chunks and not your loose source assets.

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
