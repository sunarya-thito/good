# good_cli

The `good` command-line build tool:

- **Asset pipeline**: content-addressed packer, per-asset AES-256-GCM
  encryption (deters casual extraction, not DRM against a determined
  reverse engineer - the key ships in the binary), manifest generation.
- **Compile-time codegen**: scans `Component`/`EntityStruct` subclasses
  (via `package:analyzer`) and generates concrete struct layouts, hoisting
  `good`'s runtime `DataDescriptor` layout algorithm to build time.
- **Packaging orchestration**: wraps `dart compile exe`/`flutter build` per
  target platform and bundles the encrypted asset pack alongside.

Dimension-agnostic - lives here, not under `goo2d`, so `goo2d` and a future
`goo3d` register their own asset types into the same pipeline instead of each
needing their own CLI.

Commands: `good create`, `good generate`, `good assets compact`,
`good assets pack`, and `good build windows|linux|android|ios`.

Status: **working**, verified end to end. Not implemented yet: struct-layout
codegen, `good build macos`, and `good run`. The
[implementation status page](https://sunarya-thito.github.io/good/reference/roadmap/) lists what works today, including the
rough edges in `good create` that will surprise you.
