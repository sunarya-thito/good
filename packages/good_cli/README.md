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

Dimension-agnostic - lives here, not under `goo2d`, so `goo2d_render` and a
future `goo3d_render` register their own asset types into the same
pipeline instead of each needing their own CLI.

Command shape: `good codegen`, `good assets pack`, `good build <target>`,
`good run`.

Status: **placeholder.** This is Phase 4 of the project root plan; nothing
here is implemented yet.
