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
part of 'archetype_test.dart';

List<ScannableField> _collect$Player(Object object) {
  final owner = object as _Player;
  return <ScannableField>[
    owner.team,
    owner.visible,
    owner.hitPoints,
    owner.offsetX,
    owner.offsetY,
    owner.rotation,
  ];
}

const List<Type> _supertypes$Player = <Type>[
  _Player,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Transform,
  _Health,
  _Flags,
];

List<ScannableField> _collect$Enemy(Object object) {
  final owner = object as _Enemy;
  return <ScannableField>[
    owner.team,
    owner.visible,
    owner.offsetX,
    owner.offsetY,
    owner.rotation,
  ];
}

const List<Type> _supertypes$Enemy = <Type>[
  _Enemy,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Transform,
  _Flags,
];

List<ScannableField> _collect$Rock(Object object) {
  object as _Rock;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Rock = <Type>[
  _Rock,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$ChildOnly(Object object) {
  final owner = object as _ChildOnly;
  return <ScannableField>[
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
  ];
}

const List<Type> _supertypes$ChildOnly = <Type>[
  _ChildOnly,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Child,
];

List<ScannableField> _collect$Level(Object object) {
  final owner = object as _Level;
  return <ScannableField>[
    owner.player,
    owner.enemy,
  ];
}

const List<Type> _supertypes$Level = <Type>[
  _Level,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _archetypeTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/archetype_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Player, _collect$Player, _supertypes$Player),
        DeclarationCollector(_Enemy, _collect$Enemy, _supertypes$Enemy),
        DeclarationCollector(_Rock, _collect$Rock, _supertypes$Rock),
        DeclarationCollector(
          _ChildOnly,
          _collect$ChildOnly,
          _supertypes$ChildOnly,
        ),
        DeclarationCollector(_Level, _collect$Level, _supertypes$Level),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_archetypeTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_archetypeTestDeclarations],
);
