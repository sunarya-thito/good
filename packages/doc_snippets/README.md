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

## `///` fences in the packages

`--api` adds every fenced `dart` block in a `///` comment under
`packages/*/lib` to the run, one generated library per source file, fences in
declaration order:

```bash
dart run tool/extract.dart --api
flutter analyze --no-pub
```

CI runs without it. That surface is **142 fences in 51 files**, half again what
`docs/` carries, and **109 of them do not compile standalone** - a fence inside
a `///` block names what is in scope at that declaration, and the generated
library has none of it:

| failing | cause | what clears it |
|---:|---|---|
| 67 | free names the declaration supplies - `descriptor`, `input`, the command the example is about | `<!-- snippet-setup -->` above the fence |
| 21 | an `@override` fragment wrapped as a statement | `<!-- snippet: in <header> -->` |
| 15 | not standalone Dart - two signatures, a cascade fragment, half a class body | `<!-- snippet: skip <reason> -->` |
| 6 | a type the fence names and never introduces | `<!-- snippet-setup -->`, or `top` on the fence that declares it |

Those are the tags a `docs/` page uses, written inside the `///` block, where
dartdoc renders an HTML comment as nothing:

````dart
/// <!-- snippet-setup
/// final CommandDescriptor descriptor = given();
/// final Damage damage = given();
/// -->
/// ```dart
/// descriptor.hasHandler(damage, (p) => p.amount * (p.crit ? 2 : 1));
/// ```
````

A setup line spells its types without angle brackets, as above: a `<` in a
`///` comment trips `unintended_html_in_doc_comment`, so a fence whose only
spelling needs a type argument stays unchecked.

None of the 109 is a call that fails against the signature above it. Three
were, and each is fixed: `CommandDescriptor.hasHandler` shown taking a
two-argument handler, `Effectors2D.areaEffector` called without its `Scene`,
and a `Game` field named `pause` over `Game.pause`. Two of the three
`hasHandler` fences carry a `snippet-setup` so they stay checked. Turning
`--api` on in CI costs the 109 annotations above.

## What it will not catch

That a snippet does the right thing. This is a compile, not a test: it proves
every name exists and every argument fits, which is what silently rotted the
effector API in #32.
