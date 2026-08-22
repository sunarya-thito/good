## Unreleased

World space changed direction. Read the first entry before you upgrade a game
that has any y in it.

### Breaking

* **`+y` is up.** It pointed down to match Flutter's canvas, while `goo3d` has
  always had `+y` up, so a game moving between the two had every y-touching
  system reverse meaning with nothing to catch it. Anything you wrote with a
  sign in y needs that sign checked: an input binding that yielded `-1` on `W`
  now walks a player the other way. Sprites are unaffected, since the quad is
  composed in view space. A positive rotation still turns the same way on
  screen.
* **A polygon collider takes its points.** `hasPolygonCollider` took only a
  capacity, so a fixed triangle needed an `EntityLifecycleListener` and an
  `onEntityMounted` body to fill in; it now takes the shape as a named
  parameter like every other `has*Collider`. The eight-vertex cap moved to the
  physics bridge, so `goo2d` on its own accepts a longer outline — containment
  here is an even-odd crossing test, which needs no solver.

### Fixed

* **A collider offset and a sprite pivot take the same sign, and the docs said
  otherwise.** `ColliderBody.containsLocalPoint` claimed a collider lining up
  with an off-centre sprite needed the opposite sign. It does not, and a body
  placed by that advice sits at twice the offset from where it belongs, on the
  wrong side. A pivot `offsetY` of `+20` draws the sprite 20 units up; a
  collider `offsetY` of `+20` puts a body 20 units up. Check the sign on any
  collider you offset to match a pivot. Nothing about how either one behaves
  has changed — only what the documentation said about it, and
  `docs/guide/rendering.md` now works it through where pivots are explained
  (#84).

* **`AudioClip` moved into the kernel.** Nothing to do: `goo2d` re-exports the
  kernel, so every name is where it was. It moved because a clip has no canvas
  or dimension in it and a 3D project needs sound too (#93).

* **Audio assets load.** `AudioLoader` was written and registered nowhere, so
  every `Audios.x` load threw `StateError` - the CLI transcoded a clip, keyed
  it, packed it and shipped it, and the pipeline stopped there. `Game2D`
  registers it now, through the new `describeAssetLoaders`. This is loading and
  not playback: `goo2d` still has no audio backend, mixer or voice management,
  so a loaded `AudioClip` is bytes held in memory.

* **Textures decode without a `DrawCanvas2D` being built.** The texture decoder
  was registered by that widget's constructor, so a game that built no canvas -
  a headless boot, a test, a case that starts before its first frame - failed
  every texture load with an error naming the missing loader rather than the
  cause. `Renderer2D` registers it now, which means mixing in the renderer is
  what gets you the decoder. If your game called
  `AssetLoaders.register<Texture>(const TextureLoader())` to work around this,
  that line is no longer needed; leaving it in is harmless.

* **Mouse picking is filtered by the view's scene.** The renderer skipped
  entities outside the scene its view's camera is in and the picker did not, so
  a click could land on an entity that drew nothing.

`goo2d` re-exports the `good` kernel, so its `Unreleased` entries apply here
too — in particular the profiler coming out of `GameState`.

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
