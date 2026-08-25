## Unreleased

### Breaking

* **`Sprite.setNineSliceBorder` now writes the four destination insets as
  well as the four source cuts**, which is what makes it do anything at all.
  It wrote `borderLeft`/`borderTop`/`borderRight`/`borderBottom` and nothing
  else, and it is the insets `GameRenderer2D` branches on to decide whether a
  sprite draws as nine rectangles - so a sprite declared plain could not be
  sliced at run time and one declared sliced could not be unsliced. The only
  way to get a nine-slice was `has(nineSliceBorder: ...)`.

  **What to check if you already call it.** The setter writes the whole value
  object, so an inset you do not name is written as zero, exactly the way an
  unnamed pivot component already is. `NineSliceBorder(left: 0.25, top: 0.25,
  right: 0.25, bottom: 0.25)` leaves all four insets at their default `0`, and
  passing that to a sprite declared nine-sliced used to change only where the
  source was cut - now it clears the insets too and the sprite goes back to a
  single quad. Build the border with `NineSliceBorder.pixels` or
  `NineSliceBorder.all`, which set both halves from the numbers an artist
  has, or name the insets on the general constructor. `NineSliceBorder.none`
  is now how a sprite stops being nine-sliced (#176).
* **`MouseEvent.position` and `MousePickingSystem.cursor` carry a
  `CursorPosition`**, which is `good`'s `MousePosition` under a new name - see
  its changelog for why. Rename the type where you spell it out; the fields on
  it, and `MouseBinding`, are unchanged. Nothing in `goo2d` is renamed:
  `MousePickingSystem`, `MouseReceiver`, `MouseEvent` and `MouseListener` are
  all as they were (#129).
* **A sprite outside the camera's viewport is no longer drawn.**
  `GameRenderer2D` tested only which scene an entity belonged to; the frustum
  half was never written, so every sprite in a loaded scene was queued,
  transformed, sorted and written every tick however far from the camera it
  sat. It is now rejected before it is queued, and `lastRecordCount` follows
  the size of the view rather than the size of the world: 20,000 sprites
  spread across 100,000 world units come out as 17 records, and stay at 17 as
  the camera pans.

  **The picture is unchanged** if you show the game through
  `Game2D.buildView`. That has always wrapped the canvas in a `ClipRect` at
  the view's own bounds, and what is dropped now is what that rect was already
  throwing away. Two other things do change. `lastSpriteCount`,
  `lastRecordCount` and `lastRecordsOverBudget` count only what the camera can
  see, so a test asserting on any of them needs its numbers read again - and a
  scene that was over `maxSpritesPerTick` because of sprites nobody could see
  now fits. And a game that drains `framesFor(view)` itself and paints the
  batch onto something larger than the size it reported through
  `CameraView.setViewport` will find the edges missing: report the size you
  paint at, or report zero, which means "the size is not known" and culls
  nothing.

  The bound is a circle around the sprite's pivot with the radius of its
  furthest corner, so it holds under rotation (the pivot is the point rotation
  turns about, so the radius cannot depend on the angle), an off-centre pivot,
  a negative scale and zoom. It over-covers rather than clips: a sprite one
  pixel on screen is kept. A nine-sliced sprite is culled as one sprite, since
  its nine cells tile exactly the rectangle a single quad would have (#23).

### Added

* **`CameraProjection.showsCircle`**, and the `viewLeft`/`viewTop`/
  `viewRight`/`viewBottom` rectangle it tests against - the viewport-culling
  test, kept beside the projection that defines the view so the renderer and
  anything else that needs it cannot drift apart. The rectangle is infinite on
  all four sides whenever the view reports no size, which is what a headless
  run, a view no `GameView` is showing, and the frames before the first layout
  all report (#23).

* **`GameRenderer2D.lastRecordsOverBudget`** reports how many draw records the
  last tick asked for and could not fit under `maxSpritesPerTick`. Exceeding
  the budget used to be silent: `lastWriteDropped` is about a busy handoff slot
  and stayed false, so sprites vanished with no counter, flag or assert
  anywhere. Zero means the frame fit; anything else is the amount to raise
  `maxSpritesPerTick` by. It is the exact shortfall, not a lower bound - the
  fill pass now finishes its walk to total what it turns away, which costs a
  partial walk on frames that are already over budget and nothing on frames
  that are not. What gets drawn is unchanged, including which sprites are the
  ones dropped (#175).

## 0.2.0

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
