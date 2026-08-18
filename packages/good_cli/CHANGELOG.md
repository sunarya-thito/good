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
rather than smoothed over here; the notable ones are that `good create` keeps
Flutter's own `main.dart`, and that re-running it after editing the pubspec can
duplicate keys.

Not here yet: struct-layout codegen (hoisting the runtime `DataDescriptor`
algorithm to build time), `good build macos`, and `good run`.

## 0.0.1

* Package scaffolded. Never published.
