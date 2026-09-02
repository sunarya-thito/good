# good_tool

The code generator for a **package** built on this engine. `good_cli` is the
other half and is the one an application developer runs: it generates into
their project, from their assets, into a bundle package beside their source.
The line between the two is package versus application, not this repository
versus everyone else (#305).

```bash
cd packages/good_tool
dart run good_tool --dir ../../packages            # write
dart run good_tool --dir ../../packages --check    # fail if committed is stale
dart run good_tool --dir ../../packages --verbose  # say what got nothing, why
dart run good_tool --dir ../../packages --doc-references  # check doc links
```

`--dir` says **where to look** and may be given more than once. A third-party
package author runs `--dir .` from their own package root; this repository
names its `packages/`. There is no default, because the only default there
could be is this repository's layout — a default of `packages/` finds nothing
in anybody else's tree and, before #305, exited reporting success while it did
so.

More than one `--dir` is not a convenience: the component-bit table is numbered
over every package one run sees, so a tree with packages in two places has to
be one run or the two halves get two numberings.

Within those directories — each one itself, plus its immediate children — a
package is handled when it has a `lib/`, is not `publish_to: none`, and
**depends on the engine**: `package:good` in the transitive closure of its
`dependencies:`. Transitive, because `goo2d_physics_box2d` names `goo2d` and
never names `good`. A run that matches no package says what it looked at and
what it turned down, and exits 65.

Two codes, the ones `good_cli`'s runner already uses. **64** is the command
line being wrong — an argument it does not know, a `--dir` with nothing after
it, no `--dir` at all, or a `--dir` naming a directory that is not there — and
every one of them reprints the usage. **65** is the command line being right and
the source not: no package qualifies, two are called one thing, a column would
shadow a member of `Accessor`, `Entity` or `int`, the bit table would not fit a
signature, `--check` found a stale file, or `--doc-references` found a doc
comment naming something written nowhere. The pair that look alike sit either
side of it on purpose: a `--dir` that does not exist was never read, and a
`--dir` holding no engine package was read and rejected.

The packages those depend on are **read** as well, and never written into —
without `good`, a standalone package's `Component` and `Field` are undeclared
names and there is nothing to generate. An upstream package generates its own
files in its own run.

The output is **committed**, into the `lib/` of each package it was pointed at.

## Why the two are separate

They differ in more than a destination (#300). What this writes ships inside
`good` and `goo2d`, so it is reviewed in a diff and read by people — a
regeneration that reordered nothing semantically would still be noise in a pull
request, which is why the ordering here is pinned and the imports are sorted.
What `good_cli` writes is regenerated on demand and nobody reads it. A flag on
`good_cli` would also ship engine-development machinery to every game that
depends on it.

A package rather than a `tool/` directory at the root, because there is no root
`tool/` and no root pubspec: this needs `analyzer` (through `good_cli`, whose
parse it reuses) and it has tests of its own.

It is still `publish_to: none`, so a third-party author reaches it by cloning
this repository rather than by adding a dev dependency. #305 removed the
assumptions that made it useless outside this tree; publishing it is a separate
decision.

## Why the output is committed

Because it ships. `entity<Transform2D>().offsetX` has to work for somebody who
installed `goo2d` from pub.dev and has never heard of this tool, and a published
package carries what is in its `lib/` — nothing runs a build step there.

Two things follow, and both are the point rather than the cost. A change to the
generator shows its effect in the same diff as the change. And a fresh clone
needs no tool run before it can analyze.

What goes wrong with a committed generated file is that it goes stale, so
`--check` exists, CI runs it, and `test/good_tool_test.dart` runs it too — so it
fails on the machine that made the change rather than only in CI.

## What it generates

One extension per component, a getter and a setter per column (#99):

```dart
extension Accessor$Transform2D on Accessor<Transform2D> {
  double get offsetX => component.transformOffsetX[entity];
  set offsetX(double newValue) => component.transformOffsetX[entity] = newValue;
}
```

into `lib/src/accessors.g.dart` in each package that has any, exported from that
package's entry library by a **hand-written** line — the same arrangement
`goo2d_ffi_box2d` uses for `box2d.g.dart`. A generator editing a hand-written
file is one that can lose somebody's edit; an absent export is reported and
fails `--check`.

It needs each column's name and type and never its byte offset, which is why it
was not blocked by what stopped #18: a property calls through the existing
`DataPointer`, and an offset is the running total of a `declareField` sequence
that reads values only available at run time.

And the component-bit table (#18), one per package, into
`lib/src/component_bits.g.dart` and exported the same way:

```dart
const GeneratedComponentBits goo2dComponentBits = GeneratedComponentBits(
  package: 'goo2d',
  types: <Type>[Camera, Collider2D, ScreenTransform2D, Transform2D, ...],
  dependencies: <GeneratedComponentBits>[goodComponentBits],
);
```

`ComponentTypeRegistry` hands each component type a bit the first time a
`Component.type<T>()` field initialiser names it, so which bit a type holds
follows the order the scenes were declared in. A game that names these tables to
`Game.componentBits` has them numbered before that, in an order this tool fixes
— the package name, then the declaring file, then the type name — so two
processes running the same engine packages read a query signature the same way.

An order and not an index. A table saying `Transform2D` is bit 12 would fix that
against the whole repository, and a game on `goo2d` but not `goo3d` would then
install a table full of holes out of sixty-four; an order lets the registry
number whatever set it is given, contiguously from zero.

The set is the types some `Component.type<T>()` field initialiser in this
repository names, which is exactly the set `bitFor` is called with. Not every
component mixin: `CollisionListener` is a mixin on `Component` that declares no
type, and a bit for it would be one of sixty-four spent on a type no signature
carries. Not a prefab's own type either — the framework ORs that in from
`runtimeType`, so a prefab's bit stays a run-time assignment.

Sixteen entries today, out of sixty-four. The tool refuses to write a table
larger than that and names every type in it, which is the failure #18 wanted
moved off the run: a full registry throws at run time naming whichever type
arrived last, and that is whichever scene was declared last.

## What it refuses, and what it merely skips

It **refuses** exactly one thing: a column whose property name is already a
member of `Accessor`, `Entity` or `int` — `sign`, `component`, `sceneSlot` — or
of a hand-written `extension ... on Accessor<T>`. A Dart extension member is
reached only where the receiver has no member of that name, so a shadowed
property would compile, never be called, and quietly answer about the entity
handle. That is the one failure no compiler downstream can catch.

Everything else is **skipped** with a note at `--verbose`, because everything
else fails loudly at the use site with *the getter isn't defined*: an array
column, a private one, a column whose type the generated file cannot name, a
component name two libraries both declare.

## What it does not do

An **application's** own components get nothing, and that is permanent. This
writes into a package, and `good_cli` does not generate properties into a
project — the bundle package it writes is a *dependency* of the project and
cannot import the project back. Making that unnecessary is a separate design.

A **package's** own components do get everything, whoever wrote it. That is the
correction #305 made to what #99 recorded as a limitation: a published package
carries what is in its `lib/`, so anything generated for it has to be generated
before it is published, by its author, with this.

## The doc-reference check

```bash
dart run good_tool --dir ../../packages --doc-references
```

Reads every doc comment under the `lib/` of the packages it was pointed at, and
fails on a `[Reference]` whose name is written nowhere in those packages or in
the engine packages they depend on. It generates nothing and writes nothing. CI
runs it, and `test/good_tool_test.dart` runs it against these packages too, so
it fails on the machine that made the change.

Doc comments are the published API reference, so a reference to a member that
does not exist is a link a reader follows to nothing. The analyzer's lint for
this is `comment_references`, and it is not enabled anywhere here: over the
`lib/` of the eight packages this tool handles it reports 97 sites, and 90 of
them name something the package declares and the file naming it does not
import. `good.dart` exports those from one library, so dartdoc resolves them
and the reader lands where the reference meant. Enabling the lint costs 90
`// ignore` comments or 90 imports for names those files do not otherwise use.
This reports the other seven and none of the 90.

### The rule

A name counts as written when it appears as an identifier token anywhere in the
`lib/` of a package the run read, outside comments. Not a list of declarations:
a reference may name a member, a constructor, a named parameter, a library
prefix or a private field, and the token stream is the one place that holds all
of them. `[Future]` passes because the packages write `Future` in code, not
because anything here reads `dart:async`.

A reference is a chain of names — `Game`, or `Game.addTickListener`. The first
is looked up always. A later one is looked up only when the name in front of it
is a top-level declaration of a package the run read, where the type is one of
ours and its members are all in the token stream.

A reference holding anything that is not an identifier is left alone.
`[operator +]` reaches the check with `+` as its name.

### What it does not find

**A name that is written somewhere and named where it makes no sense.** "A
system that is a `Tickable` lands in [tick]" pointed at `GameState.tick`, the
tick number, where the dispatcher it meant is `tickEvent`. That reference
resolves, so nothing short of a resolved analysis tells it from a correct one.

**A member of a type declared outside the packages read.** `[Canvas.drawRect]`
is left alone, because nothing here can say what a Flutter type's members are.

**A name another package in the run writes and this one does not.** The word
list is the whole run, so `[Entity]` passes in a package that documents one
without naming it in code.
