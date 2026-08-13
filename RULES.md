1. Avoid heap object allocation on hotpath (this includes records, wrapper classes, etc, type extension (ON A NON-HEAP OBJECT) is okay)
2. Assume all framework game events as hotpath
3. Avoid Canvas.save, Canvas.restore, Canvas.rotate, Canvas.drawImage, Canvas.translate
4. Avoid Zone API
5. No closures on the hotpath either - rule 1 covers them, but they hide well and
   deserve calling out. `list.any((c) => c.matches(x))`, `where`, `map`, `forEach`,
   `fold` and friends all allocate a closure per call (and often an Iterable too).
   Write the indexed `for` loop. Closures at *declare* time (a one-shot
   `describe*` pass, `seal()`, boot) are fine - it is per-entity/per-tick that
   matters.
6. No name-based lookup for anything the framework hands back. If a
   `describe*` pass produces a thing, it must return a typed handle the caller
   stores in a field - never a `String`/`int` key the caller has to quote again
   later, and never a `Map<String, ...>` the framework searches at use time.
   The analyzer cannot catch `buffers['playersprite']` vs `buffers['playerSprite']`;
   it catches `playerSprite` immediately. A direct field read also beats a map
   lookup at runtime, so this costs nothing.
       // yes
       late final Sprite playerSprite;
       void describeSprites(SpriteDescriptor d) {
         playerSprite = d.has(texture: playerTexture, width: 64, height: 64);
       }
       void use(Entity e) { playerSprite.color[e] = 0xFFFF0000; }
       // no
       void describeSprites(SpriteDescriptor d) { d.has('playerSprite'); }
       void use() { sprites['playerSprite']; }
   Same rule for buffers, state channels, inputs, coroutines, colliders - every
   `describe*` hook.
7. Never `print` to report a framework problem, and never smuggle one through
   `assert(() { print(...); return true; }())`. `print` is not a reliable error
   channel (swallowed in release, invisible in a test runner's captured output,
   unformatted in production logs). Use a plain `assert(false, 'message')` - it
   is the debug-build failure signal the engine already relies on everywhere
   else, and it compiles out of release exactly the same way.
8. Don't add a specialized variant of an existing method to escape a
   constraint. If `operator[]` reads the published snapshot and you want the
   uncommitted one, the answer is not `readPending()` alongside it - a second
   read path means every future reader has to know which one is "the right
   one here", and the invariant the first one enforces quietly stops being an
   invariant. Fix the placement instead: a value that must be read after it is
   written belongs in a later *phase*, not behind a sharper accessor. Unity
   DOTS resolves exactly this by running `PresentationSystemGroup` after
   `SimulationSystemGroup` and having both read the same `LocalToWorld`
   component - one storage, one writer, consumers ordered after. Same here:
   `WorldTransformSystem` writes during the fixed tick, and anything that
   consumes world transforms runs after that tick commits.
9. Isolate affinity is a type, not a convention. A game-isolate event is a
   `GameEvent` dispatched to a `GameListener`; a Flutter/main-isolate event is a
   `WidgetEvent` dispatched to a `WidgetListener`. `GameState` is a
   `GameListener`, `Game` is a `WidgetListener`, so listening to the wrong side
   is a compile error rather than something that silently never fires.
