# doc_snippets

Compiles the fenced `dart` blocks in `docs/` against the real packages, so
renaming a public name breaks the build at the documentation still using the old
one.

```bash
dart run tool/extract.dart      # docs/ -> lib/pages/, one library per page
flutter analyze --no-pub
```

`lib/pages/` is generated and git-ignored. Nothing here is published, and
nothing in `docs/` needs to know this package exists.

## A fence is checked unless it says otherwise

That is the whole rule, and it is the reason the check is worth anything: a page
written next month is covered without its author knowing about this package.
The alternative default — check only what is tagged — would have covered
nothing at all as the docs grew, which is the failure this was built to stop.

The cost is that a snippet the analyzer cannot make sense of has to say so, in
an HTML comment above the fence:

```markdown
<!-- snippet: skip shows the shape the rule rejects -->
```

The reason is mandatory and it is printed in the run summary, so the holes are
counted every build instead of accumulating quietly.

## Placement

Most fences need no tag. A block starting with `class`, `mixin`, `enum` or an
import goes to the top level; anything else is wrapped in a method of a
generated `GameSystem`, which is where `game`, `state`, `getSystem`,
`singleScene` and `startCoroutine` come from. Override that with:

| Tag | Wraps the fence in |
|---|---|
| `<!-- snippet: top -->` | the library, for a declaration the guesser read as a statement |
| `<!-- snippet: body -->` | a `GameSystem` method |
| `<!-- snippet: body <header> -->` | a method of `class _Snippet extends <header>` |
| `<!-- snippet: in <header> -->` | the body of `class _Snippet extends <header>`, for `@override` fragments |
| `<!-- snippet: plain -->` | a top-level function, for main-isolate code |
| `<!-- snippet: expr -->` | a top-level function's expression body, for a widget tree |

## Names a fence uses without introducing

Two levels. `lib/scaffold.dart` carries what turns up everywhere — `entity`,
`scene`, `query`, a `Player`, a `MyGame` — and every generated library imports
it.

Per page, a `<!-- snippet-scope ... -->` block near the top declares that page's
own cast. It is emitted verbatim at the top of the page's library:

```markdown
<!-- snippet-scope
late Transform2D transform;
late Query orcs;
void showBanner() {}
-->
```

For one fence rather than a page, `<!-- snippet-setup ... -->` directly above it
puts the declarations inside that fence's wrapper, where they shadow anything of
the same name:

```markdown
<!-- snippet-setup
final descriptor = given<SpriteDescriptor>();
-->
```

`given<T>()` is the scaffold's stand-in for a value the surrounding code would
have handed the fragment. **Nothing declared this way may be `dynamic`** — a
`dynamic` would make every member access on it legal and the check would pass
over the renames it exists to catch. `avoid_dynamic_calls` is an error here for
the same reason.

## A page that documents an API that does not exist

The docs describe the finished engine, so some pages are ahead of the code. One
line under the H1 covers the page:

```markdown
<!-- snippet-page: skip no 3D physics backend exists yet -->
```

Reach for this only where [the roadmap](../../docs/reference/roadmap.md) says
the package is not built. A page about something that *does* exist gets its
fences checked.

## Redefinition within a page

Teaching pages grow a class across a page — `Orc` is declared five times in
`thinking-in-ecs.md`, each version bigger than the last, and every fence below
one means the nearest one above it. The extractor cuts a page into segments at
each redefinition and has segment N import segment N-1 with the redefined names
hidden, so a reference resolves to the most recent definition above it.

Two consequences worth knowing when a snippet will not compile for no visible
reason:

- A `_private` name in a page scope is not visible from a later segment, because
  segments are separate libraries. Use a `snippet-setup` on the fence instead.
- A fence cannot call something a later fence declares. That is a real forward
  reference and the honest answer is a `skip` with the reason.

## What it will not catch

That a snippet does the right thing. This is a compile, not a test: it proves
every name exists and every argument fits, which is what silently rotted the
effector API in #32.
