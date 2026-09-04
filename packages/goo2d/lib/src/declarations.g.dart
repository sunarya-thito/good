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

import 'package:goo2d/src/data/world_transform.dart';
import 'package:goo2d/src/input/pointer.dart';
import 'package:goo2d/src/render/render_2d.dart';
import 'package:good/good.dart';

List<ScannableField> _worldTransformSystem(Object object) {
  final owner = object as WorldTransformSystem;
  return <ScannableField>[
    owner.roots,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _pointerPickingSystem(Object object) {
  final owner = object as PointerPickingSystem;
  return <ScannableField>[
    owner.cursor,
    owner.click,
    owner.contacts,
    owner.pressables,
    owner.hoverables,
    owner.cameras,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _gameRenderer2D(Object object) {
  final owner = object as GameRenderer2D;
  return <ScannableField>[
    owner.renderables,
    owner.screenRenderables,
    owner.labels,
    owner.cameras,
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

/// Every class `package:goo2d` can instantiate that holds a
/// declaration, and how to read one.
///
/// Pass this to `Game.declarations` - together with the table
/// of every other engine package the game uses, and the one
/// generated for the game itself - so a registration can read
/// what a constructed object declared.
const GeneratedDeclarations goo2dDeclarations = GeneratedDeclarations(
  package: 'goo2d',
  collectors: <DeclarationCollector>[
    DeclarationCollector(WorldTransformSystem, _worldTransformSystem),
    DeclarationCollector(PointerPickingSystem, _pointerPickingSystem),
    DeclarationCollector(GameRenderer2D, _gameRenderer2D),
  ],
  dependencies: <GeneratedDeclarations>[
    goodDeclarations,
  ],
);
