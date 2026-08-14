1. Avoid heap object allocation on hotpath (this includes records, wrapper classes, etc, type extension (ON A NON-HEAP OBJECT) is okay)
2. Assume all framework game events as hotpath
3. Avoid Canvas.save, Canvas.restore, Canvas.rotate, Canvas.drawImage, Canvas.translate
4. Avoid Zone API
5. No closures on the hotpath. Rule 1 covers them, but they hide well.
   `any`, `where`, `map`, `forEach`, `fold` allocate a closure per call, and
   usually an Iterable too. Write the indexed `for`. Closures in a `describe*`
   pass, in `seal()`, or at boot are fine - those run once.
6. Whatever a `describe*` pass produces comes back as a typed handle the caller
   keeps in a field. No String or int keys, no `Map<String, ...>` the framework
   searches at use time.
       // yes
       late final Sprite playerSprite;
       void describeSprites(SpriteDescriptor d) {
         playerSprite = d.has(texture: playerTexture, width: 64, height: 64);
       }
       void use(Entity e) { playerSprite.color[e] = 0xFFFF0000; }
       // no
       void describeSprites(SpriteDescriptor d) { d.has('playerSprite'); }
       void use() { sprites['playerSprite']; }
   The analyzer catches a misspelled field, not a misspelled string. Applies to
   buffers, state channels, inputs, coroutines, colliders - every `describe*`.
7. Never `print` to report a framework problem, including through
   `assert(() { print(...); return true; }())`. It is swallowed in release and
   invisible in test output. Use `assert(false, 'message')`.
8. Don't add a specialized variant of a method to escape a constraint. If
   `operator[]` reads the published snapshot and you want the uncommitted one,
   the answer is not `readPending()` beside it - a second read path means every
   later reader has to know which one is right here, and the first one stops
   guaranteeing anything. Fix the placement instead: a value that must be read
   after it is written belongs in a later phase. Unity DOTS does this by
   running `PresentationSystemGroup` after `SimulationSystemGroup` over the
   same `LocalToWorld`. Same here - `WorldTransformSystem` writes during the
   fixed tick, and consumers run after it commits.
9. Isolate affinity is a type. `GameListener` means "lives on the game
   isolate": `GameState`, `SceneStruct`, `EntityStruct`, `GameSystem`. `Game`
   is not one, so `class MyGame extends Game with FixedTickable` fails to
   compile instead of silently never ticking. There is no second event lane for
   the main isolate - `Game.buildView` is its whole surface, and traffic the
   other way goes through `GameCommand` or `StateChannel`.
10. One fact, one place. If two structures have to agree and only your memory
   keeps them agreeing, they will drift. The analyzer checks types, not "these
   stay in step".
   The tell: you can't change one place without hunting for the others. Adding
   to a list means adding to a second list. Sorting one means permuting
   another. Setting a flag means also updating a count, a cache, or a mirror.
   When the correct edit is "and don't forget to...", fix the structure.
   Remove the second copy, preferring in this order:
   - move the fact onto the object it describes - a property of the things in a
     list belongs on those things, not in a second array beside them;
   - derive it instead of storing it, when that is cheap enough;
   - fuse the structures, when they only ever get used together;
   - last resort, one collection of one small object with named fields.
   The last one comes to mind first and is the weakest: it makes the coupling
   safe instead of removing it. Collapsing properly usually turns up dead
   weight - `_EventDescriptor` held three lists in lockstep, and fusing them
   showed two were the same decision and the third was never read.
   Exception: struct-of-arrays for cache locality, which the storage layer is
   built on. That needs a benchmark and a comment saying so, and it never
   applies to boot-time structures.
   Already fixed here: `Game._systemEnabled` beside `_systems`;
   `_fixedTickableIndices`/`_tickableIndices`; `_EventDescriptor`'s
   `_dispatchers`/`_accepts`/`_adds`.
