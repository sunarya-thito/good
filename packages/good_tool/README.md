# good_tool

This repository's own code generator. Never published, never a dependency of
anything a user installs.

```bash
cd packages/good_tool
dart run good_tool            # write
dart run good_tool --check    # fail if what is committed is stale
dart run good_tool --verbose  # say what got no property, and why
```

It writes into `packages/*/lib/` and the output is **committed**. `good_cli` is
the other half and is the one users run: it generates into their project, from
their assets, into a bundle package beside their source.

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

A game's own components get nothing. This runs over the engine's repository and
writes into packages published from it; a component in somebody's `lib/` is in
neither, and `good_cli` does not generate properties into a project — the bundle
package it writes is a *dependency* of the project and cannot import the project
back. Making that unnecessary is a separate design.
