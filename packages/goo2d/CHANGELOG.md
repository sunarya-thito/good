## 0.1.0

**This is a rewrite. Nothing from 0.0.2 carries over.** pub.dev served 0.0.2 in
April 2026; that was an earlier iteration of this engine with an entirely
different API. A pubspec saying `goo2d: ^0.0.1` resolves to *that* version and
resolves successfully, so the mismatch shows up as analyzer errors rather than
as a resolution failure. Depend on `^0.1.0` and expect to rewrite call sites.

The 2D renderer on top of the new [`good`](https://pub.dev/packages/good)
kernel:

* **Transforms** — `Transform2D`, composed world transforms, and the camera.
* **Rendering** — sprites, `SpriteFrame` for sampling one region of a texture,
  nine-slice borders with source-relative cuts, and a `zIndex` sort.
* **Colliders and mouse picking.**
* **Audio assets** — decoding and the asset pipeline half. There is no audio
  backend, mixer, or voice management yet.

Not here yet: z-ordering and culling beyond declaration order and the `zIndex`
sort. Web is unsupported, because the kernel needs `dart:ffi` and isolates.

## 0.0.2

* An earlier, unrelated iteration of the engine. Superseded entirely by 0.1.0.
