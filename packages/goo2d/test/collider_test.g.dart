// GENERATED - do not edit.
//
// Regenerate with `dart run good_tool --tests` from
// packages/good_tool, and commit what changes.
// `dart run good_tool --tests --check` is what CI runs; it
// fails if this file is not what the generator would write.
//
// One function per fixture this library declares. It is a
// part of that library because a fixture is private, and a
// private class can only be named from inside the library
// that declares it.
//
// The order inside each list is the order the fields would
// have been initialised in, which is the field order of every
// row of that archetype.
//
// A commented-out line is a declaration a mixin from a
// package's lib/ holds privately. That is another library,
// so nothing here can read it - it keeps its place so that
// what the row is missing, and where, is visible.
//
// Beside each list is every type an instance of that fixture
// is, the fixture itself first, then the names in its
// extends, with and implements clauses in that order, each
// followed by its own supertypes. Nothing reads that order
// positionally; it is fixed so two machines write one file.
//
// A type the generator did not read is not listed. A type it
// read and this part cannot name keeps its place as a
// comment - a part writes no imports of its own, so what it
// may name is what its library already does.
part of 'collider_test.dart';

List<ScannableField> _collect$Player(Object object) {
  final owner = object as _Player;
  return <ScannableField>[
    owner.box,
    owner.hurtbox,
    owner.pickupRange,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Player = <Type>[
  _Player,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Collider2D,
];

List<ScannableField> _collect$Watcher(Object object) {
  object as _Watcher;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Watcher = <Type>[
  _Watcher,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  CollisionListener,
];

List<ScannableField> _collect$Wall(Object object) {
  final owner = object as _Wall;
  return <ScannableField>[
    owner.box,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Wall = <Type>[
  _Wall,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Collider2D,
];

List<ScannableField> _collect$Polygon(Object object) {
  final owner = object as _Polygon;
  return <ScannableField>[
    owner.triangle,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Polygon = <Type>[
  _Polygon,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Collider2D,
];

List<ScannableField> _collect$Capsule(Object object) {
  final owner = object as _Capsule;
  return <ScannableField>[
    owner.pill,
    owner.squashed,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Capsule = <Type>[
  _Capsule,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Collider2D,
];

List<ScannableField> _collect$Concave(Object object) {
  final owner = object as _Concave;
  return <ScannableField>[
    owner.arrow,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Concave = <Type>[
  _Concave,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Collider2D,
];

List<ScannableField> _collect$Scene(Object object) {
  final owner = object as _Scene;
  return <ScannableField>[
    owner.player,
    owner.wall,
    owner.polygon,
    owner.capsule,
    owner.concave,
  ];
}

const List<Type> _supertypes$Scene = <Type>[
  _Scene,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$WidePolygon(Object object) {
  final owner = object as _WidePolygon;
  return <ScannableField>[
    owner.wide,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$WidePolygon = <Type>[
  _WidePolygon,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Collider2D,
];

List<ScannableField> _collect$WidePolygonScene(Object object) {
  final owner = object as _WidePolygonScene;
  return <ScannableField>[
    owner.polygon,
  ];
}

const List<Type> _supertypes$WidePolygonScene = <Type>[
  _WidePolygonScene,
  SceneStruct,
  Coroutines,
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _colliderTestDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/test/collider_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Player, _collect$Player, _supertypes$Player),
        DeclarationCollector(_Watcher, _collect$Watcher, _supertypes$Watcher),
        DeclarationCollector(_Wall, _collect$Wall, _supertypes$Wall),
        DeclarationCollector(_Polygon, _collect$Polygon, _supertypes$Polygon),
        DeclarationCollector(_Capsule, _collect$Capsule, _supertypes$Capsule),
        DeclarationCollector(_Concave, _collect$Concave, _supertypes$Concave),
        DeclarationCollector(_Scene, _collect$Scene, _supertypes$Scene),
        DeclarationCollector(
          _WidePolygon,
          _collect$WidePolygon,
          _supertypes$WidePolygon,
        ),
        DeclarationCollector(
          _WidePolygonScene,
          _collect$WidePolygonScene,
          _supertypes$WidePolygonScene,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );

/// Installs [_colliderTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_colliderTestDeclarations],
);
