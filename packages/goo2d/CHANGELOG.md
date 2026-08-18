## 0.1.1

Documentation only. No code changes.

The README now opens with a runnable example instead of a description.

## 0.1.0

A ground-up rewrite sharing nothing with 0.0.2. Pin `^0.1.0`.

The 2D renderer on top of the [`good`](https://pub.dev/packages/good)
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
