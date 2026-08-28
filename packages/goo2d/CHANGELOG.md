## Unreleased

### Fixed

* **A frame over the record budget drops its furthest layers, not its
  last-registered archetype.** The budget was spent during the fill pass,
  which walks in encounter order - archetype registration, then page, then
  row - and the sort by depth happened afterwards. So a scene with a tilemap
  declared first and a player declared last lost the player, and what a frame
  dropped had nothing to do with what it looked like (#175).

  The sort has not moved. The budget decision has: the fill pass queues every
  visible candidate, `sortByZ` runs exactly as before, and the budget is spent
  walking the sorted order from the camera backwards. Survivors are a
  contiguous depth slab - a sprite behind a refused one is refused too, even
  where it would have fit, because a background tile drawn while the
  mid-layer tile over it is missing is a worse frame than a missing back
  layer. A sliced sprite is still admitted only if every record it draws
  fits.

  On a frame that fits the trim is one integer comparison, measured at 1 ns
  against a 47-485 microsecond pass (`tool/budget_trim_bench.dart`). What it
  costs instead is the draw queue growing to the number of visible candidates
  rather than to the budget - Dart heap, 80 bytes per queued sprite. The
  native handoff and the byte scratch are still sized from
  `maxSpritesPerTick`, so nothing that crosses the isolate boundary grew.

  `lastRecordsOverBudget` is unchanged in meaning and still exact: every
  candidate is queued before anything is spent, so the shortfall is the
  queued total less what was drawn.

* **A nine-sliced sprite is charged the records it draws, not nine.** The
  charge was hardcoded at nine for anything with an inset on it, while the
  write pass has always skipped a collapsed row or column - and a sprite
  sliced on one axis has them by construction. A three-sliced capsule button
  cost three times what it drew, so ten of them against a 64-record budget
  dropped three panels from a frame that needed 30. `lastRecordCount` is now
  what the published batch holds, and `lastRecordsOverBudget` is the real
  shortfall rather than up to nine times it, which is what makes
  `maxSpritesPerTick += lastRecordsOverBudget` the fix its doc says it is
  (#252).

  A sprite whose scale collapses every cell now draws nothing and costs
  nothing, where before it cost nine.

### Changed

* **`Game2D.maxSpritesPerTick` defaults to 16384, up from 4096.** A
  full-screen layer of 16 px tiles is 8228 records on its own, so 4096 was a
  figure a first tilemap walked past on its first frame - and until the
  shortfall counter landed it did so in silence. The new default reserves
  3.56 MiB per declared `CameraView` against the previous 0.89 MiB. Override
  it downwards on a game that knows it draws less (#175).

* **`MousePickingSystem` declares `cursor` and `click` on their fields.** Both
  were `late final` assigned from a `describeInputs` override, which the
  system no longer has; they are plain `final` initialised by `Input.of`
  (#91). The fields are read exactly as before.

### Breaking

* **`Camera` columns carry the component's name.** `zoom` and `view` were two
  of the shortest, most guessable names in the engine, sitting in a namespace
  every other component on the entity shares. `Camera3D` declared its own
  `view` beside them, which was harmless only because nothing mixes both
  (#133).

  | before | after |
  |---|---|
  | `Camera.zoom` | `Camera.cameraZoom` |
  | `Camera.view` | `Camera.cameraView` |

  `Transform2D` and `WorldTransform2D` already prefixed and do not move.
  `CameraProjection.zoom` is a plain field on a class, not a column, and keeps
  its name.

  Names only - column order, widths and `strideBytes` are unchanged. `good`
  carries the same change for `Child` and `Parent`, and the rule behind both
  is in `docs/reference/design-rules.md`.

* **`Sprite.alignment` is deleted**, along with the `alignFractionX`,
  `alignFractionY`, `alignOffsetX` and `alignOffsetY` row fields, the
  `alignment:` parameter on `SpriteDescriptor.has`, and the `setAlignment`
  setter. Nothing in `GameRenderer2D` ever read them: two sprites differing
  only in their alignment emitted byte-identical geometry, so a game that set
  one saw no sprite move. What they were meant to do was never settled -
  an alignment resolves against the size of the container a sprite is
  anchored to, and neither candidate container exists. A parent's bounds
  would need a system publishing per-entity extents, and `goo2d` has no
  bounds concept at all; anchoring to the view is designed in #132, through a
  per-entity `ScreenTransform2D` and its own anchor enum, not through these
  fields (#171).

  **What to do about a call site.** Nothing, for the behaviour: deleting a
  field the geometry path never named cannot move a pixel. Delete the
  `alignment:` argument and the `setAlignment` call - the compiler finds
  every one of them. If you wanted to pin a sprite to a corner of the screen,
  that is #132 and it is not here yet; a `Transform2D` offset is the way to
  place a sprite until it lands, and `pivot` still covers anything inside the
  sprite's own bounds. The four columns were 32 bytes on every sprite row -
  21% of a sprite's 150, measured through `ArchetypeStorage.strideBytes` -
  which every game now gets back.
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

* **`SpriteWidget`** draws a texture, or one frame of a sprite sheet, as an
  ordinary Flutter widget - so a menu, a HUD or an inventory can show the art
  the game already loaded. It takes the `TextureAsset` a `describeAssets` pass
  returned, the same handle a `Sprite` points at, plus an optional
  `SpriteFrame` and `TextureFilter`. `SpriteFrame`'s fractions become source
  pixels inside the widget, off the decoded image - which is why this works on
  the main isolate and could not work on the game one.

  **It costs no extra memory, and the thing it replaces costs 100%.**
  `Image.asset` on a file the engine has already decoded decodes a *second*
  copy into Flutter's `imageCache` while the engine keeps holding the first;
  measured at 512 KiB for a 256x256 image rather than 256, on a cache whose
  default cap is 100 MiB and which evicts and re-decodes under pressure.
  Drawing the handle adds nothing to `imageCache` at all - 0 bytes, 0 entries,
  0 live images after a pump, against 8192 for the same 64x32 bytes through
  `MemoryImage` in the same harness.

  **An unloaded handle draws nothing rather than throwing.** Same call
  `DrawCanvas2D` already made for the renderer, for the reason written there: a
  declared-but-still-decoding texture is the ordinary state of the first frames
  of a run, and throwing on it took the whole app down. Such a widget also
  reports no preferred size, so it occupies nothing rather than a blank box.

  **Nothing in the signature is named `Texture`**, which is deliberate:
  `Texture` is also a widget in `package:flutter/widgets.dart`, so a file
  importing both `material.dart` and `goo2d.dart` gets `ambiguous_import` the
  moment it spells that name. `TextureAsset`, `SpriteFrame` and
  `TextureFilter` are all clear, so user widget code needs no `hide` clause.

  **What it does not do yet**: no preload helper, no nine-slice, no animation,
  and no way to name a texture that belongs to no prefab or scene. Loading is
  the caller's, and the handle has to come from a `describeAssets` pass (#120).

* **`ColliderBody.boundCovers`** answers whether a local point that far from
  the entity's origin could be inside a body at all - the cheap, conservative
  half of `containsLocalPoint`, and the reason `MousePickingSystem` no longer
  inverts the transform of every receiver in the scene. The distance is
  squared and measured from local `(0, 0)` rather than from the body's own
  `offsetX`/`offsetY`, because the origin is the point rotation turns about,
  so one radius holds at every angle and the test never reads the angle. It
  may be passed a distance smaller than the real one, which is what lets a
  caller holding a world-space point divide by the entity's largest scale
  factor instead of rotating: too small can only answer `true` too often, and
  the exact test decides after it. `ColliderBody.originDistance` is the
  shared first term.

  **Nothing about what gets picked changes.** The bound is only ever wider
  than the shape, `containsLocalPoint` still decides every hit, and a `NaN`
  in any field keeps the body rather than dropping it. What changes is the
  cost: picking 20,000 receivers went from 123 to 58 ns per receiver per
  fixed tick, which puts it back under the fill pass's 88.8. Most of that is
  not this bound - about 49 ns of it is the walk moving to `groups()`, so a
  component resolves once per archetype instead of once per row, and the
  bound is the remaining 16. Both figures are JIT: #154 rules out an AOT
  build of anything holding a `Query`, so they are ratios between legs in one
  VM rather than device numbers (#184).

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

### Fixed

* **A tick that destroys thousands of parented entities is linear in how many
  again.** `WorldTransformSystem` holds every entity spawned since the last
  fixed step, so it can compose those from what their spawner wrote rather
  than from a stale row, and it took a destroyed entity back out of that
  collection with a linear scan. So spawning and destroying N entities
  carrying `WorldTransform2D` inside one tick - an explosion clearing a
  squad, a level unloading - cost O(N^2). Measured over a 4x step in
  entities, it went from 11.6x to 2.7x. Nothing to do, and nothing about the
  composed transforms changes: the collection is a `Set` now, which iterates
  in the same spawn order it did as a `List`, and a scene with no
  `WorldTransform2D` in it never paid this and still does not (#180).

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
