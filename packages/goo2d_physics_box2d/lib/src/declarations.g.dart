// GENERATED - do not edit.
//
// Regenerate with `dart run good_tool` from
// packages/good_tool, and commit what changes.
// `dart run good_tool --check` is what CI runs; it fails if
// this file is not what the generator would write.
//
// One function per class this package can instantiate that
// declares anything. A declaration is a field holding its own
// value, with nothing open around it, so this is the only
// record of what a class declared - and a class's field list
// is the one thing a running program cannot ask for.
//
// The order inside each list is the order the fields would
// have been initialised in: the class's own, then each
// mixin's with the last name in the `with` clause first,
// then the superclass's. That order is the field order of
// every row of the archetype, so reordering a list here
// relays out the entities.
//
// A commented-out line is a declaration held by a private
// field. Dart privacy is per library and this is a different
// one, so nothing here can read it - it keeps its place so
// that what the row is missing, and where, is visible.

import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/src/physics_system.dart';

List<ScannableField> _box2DPhysicsSystem(Object object) {
  final owner = object as Box2DPhysicsSystem;
  return <ScannableField>[
    // Box2DPhysicsSystem._effectorZones: private, unreachable.
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

/// Every class `package:goo2d_physics_box2d` can instantiate that holds a
/// declaration, and how to read one.
///
/// Pass this to `Game.declarations` - together with the table
/// of every other engine package the game uses, and the one
/// generated for the game itself - so a registration can read
/// what a constructed object declared.
const GeneratedDeclarations goo2dPhysicsBox2dDeclarations =
    GeneratedDeclarations(
      package: 'goo2d_physics_box2d',
      collectors: <DeclarationCollector>[
        DeclarationCollector(Box2DPhysicsSystem, _box2DPhysicsSystem),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );
