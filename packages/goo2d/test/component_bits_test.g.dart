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
part of 'component_bits_test.dart';

List<ScannableField> _collect$Ship(Object object) {
  final owner = object as _Ship;
  return <ScannableField>[
    owner.worldX,
    owner.worldY,
    owner.worldScaleX,
    owner.worldScaleY,
    owner.worldRotation,
    owner.worldCachedOffsetX,
    owner.worldCachedOffsetY,
    owner.worldCachedRotation,
    owner.worldCachedScaleX,
    owner.worldCachedScaleY,
    owner.worldCachedParent,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Ship = <Type>[
  _Ship,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  WorldTransform2D,
];

List<ScannableField> _collect$Eye(Object object) {
  final owner = object as _Eye;
  return <ScannableField>[
    owner.cameraZoom,
    owner.cameraView,
    owner.transformOffsetX,
    owner.transformOffsetY,
    owner.transformScaleX,
    owner.transformScaleY,
    owner.transformRotation,
  ];
}

const List<Type> _supertypes$Eye = <Type>[
  _Eye,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Transform2D,
  Camera,
];

List<ScannableField> _collect$Bare(Object object) {
  final owner = object as _Bare;
  return <ScannableField>[
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
  ];
}

const List<Type> _supertypes$Bare = <Type>[
  _Bare,
  EntityStruct,
  Coroutines,
  Animations,
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Child,
];

List<ScannableField> _collect$Forward(Object object) {
  final owner = object as _Forward;
  return <ScannableField>[
    owner.ship,
    owner.eye,
    owner.bare,
  ];
}

const List<Type> _supertypes$Forward = <Type>[
  _Forward,
  SceneStruct,
  Coroutines,
  Scannable,
];

List<ScannableField> _collect$Reversed(Object object) {
  final owner = object as _Reversed;
  return <ScannableField>[
    owner.bare,
    owner.eye,
    owner.ship,
  ];
}

const List<Type> _supertypes$Reversed = <Type>[
  _Reversed,
  SceneStruct,
  Coroutines,
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _componentBitsTestDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/test/component_bits_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Ship, _collect$Ship, _supertypes$Ship),
        DeclarationCollector(_Eye, _collect$Eye, _supertypes$Eye),
        DeclarationCollector(_Bare, _collect$Bare, _supertypes$Bare),
        DeclarationCollector(_Forward, _collect$Forward, _supertypes$Forward),
        DeclarationCollector(
          _Reversed,
          _collect$Reversed,
          _supertypes$Reversed,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );

/// Installs [_componentBitsTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_componentBitsTestDeclarations],
);
