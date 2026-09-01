// GENERATED - do not edit.
//
// Regenerate with `dart run good_tool` from
// packages/good_tool, and commit what changes.
// `dart run good_tool --check` is what CI runs; it fails if
// this file is not what the generator would write.
//
// The order below is the bit order. A game names this table
// to `Game.componentBits`, and every type in it is then
// numbered before the game declares anything of its own, so
// the bits are the same on every machine and a query
// signature means the same thing to a peer that receives it.
//
// A component this tool never read - one in a game's own
// lib/, or in a package outside this repository - is not here
// and does not need to be. It takes the next free bit when it
// is first seen, after all of these, so nothing below ever
// renumbers because of it.

import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/src/effector.dart';
import 'package:goo2d_physics_box2d/src/rigid_body.dart';

/// Every component type `package:goo2d_physics_box2d` registers,
/// in the order their bits are assigned.
///
/// Pass this to `Game.componentBits` - together with the table
/// of every other engine package the game uses - to have these
/// types numbered at boot instead of on first sighting.
const GeneratedComponentBits goo2dPhysicsBox2dComponentBits =
    GeneratedComponentBits(
      package: 'goo2d_physics_box2d',
      types: <Type>[
        Effector2D,
        RigidBody2D,
      ],
      dependencies: <GeneratedComponentBits>[
        goo2dComponentBits,
      ],
    );
