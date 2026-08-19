# Getting started

You need Flutter installed and enough Dart to read a class. **You do not need to
have built a game before.**

## What a game is made of here

Four ideas, and that is the whole model:

- **Entities** are the things in your game: a player, a bullet, a tree. An
  entity is a number, and its data lives in columns beside it.
- **Prefabs** say what a kind of entity is made of — a player has a position, a
  sprite and a speed.
- **Scenes** say what exists when the game starts.
- **Systems** are where behaviour goes: code that runs every step of the
  simulation, over every entity that matches what it asked for.

So a game is: declare the kinds of thing, declare what exists, write the code
that moves them. Nothing inherits from anything, and you never write a game
loop — the engine runs one and calls your systems from it.

If you have used Unity, Godot or Flame, some of that will look familiar and some
of it will not. [Thinking in ECS](../guide/thinking-in-ecs.md) is the gentler
way in: it takes the habits you already have and shows where each one lands,
including the ones that have no home here.
[Coming from Unity, Godot or Flutter](../guide/mental-model.md) is the
translation table for when you want the call you would have written and its
replacement, side by side.

## Three pages, in the order you meet them

1. **[Installation](installation.md)** — the Flutter SDK, the per-platform
   native toolchains, and putting `good` on your `PATH`.
2. **[Create a project](create-a-project.md)** — `good create`, what it writes,
   and how a good project is configured.
3. **[Your first game](your-first-game.md)** — a sprite driven by the keyboard,
   built up from the empty scaffold.

By the end of the third page you have something you can run and move around.

## A note on the code you will see

Every example uses `goo2d`, the 2D engine. Scenes, prefabs, systems, input and
assets come from the kernel underneath it, so a 3D game writes those the same
way; only the transform, sprite and camera types differ. The axes agree too —
both put **+Y up**, so a system that moves something upward keeps meaning that
when you carry it into 3D. See
[2D and 3D](../packages/2d-and-3d.md) if you want the whole picture first.

Words like *prefab*, *archetype* and *isolate* have a dotted underline wherever
they appear — hover for a one-line definition rather than going to look it up.

If you would rather understand the engine before writing any of it, start with
[Architecture](../guide/architecture.md).
