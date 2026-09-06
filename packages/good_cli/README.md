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
good generate         # normalize -> bindings -> chunk, compress, encrypt
```

One command, because the stages have one order and running them out of it
produces a build that succeeds and is quietly stale. `--no-normalize` and
`--no-pack` turn a stage off when you are iterating on the other half;
normalisation is incremental anyway, so an unchanged file is never re-encoded.

`good generate` is what lets you write `Textures.spritesPlayer` instead of a
string path, so a renamed file is a compile error, not a black square at
runtime.

## Shipping

```bash
good build windows            # also: linux, android, ios
```

`good build` runs `good generate` first - the way `flutter build` runs
`flutter pub get` - so the release bundle carries current chunks;
`--no-generate` builds what is already on disk. What else it carries is what `flutter: assets:` says: that list and
`good: assets:` are read separately, so a file good packs is not thereby handed
to Flutter's bundler.

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
