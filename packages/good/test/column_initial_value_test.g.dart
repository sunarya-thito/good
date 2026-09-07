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
part of 'column_initial_value_test.dart';

List<ScannableField> _collect$Grunt(Object object) {
  final owner = object as _Grunt;
  return <ScannableField>[
    owner.speed,
    owner.hp,
    owner.alive,
    owner.stance,
    owner.leader,
    owner.shield,
    owner.aim,
  ];
}

const List<Type> _supertypes$Grunt = <Type>[
  _Grunt,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Body,
];

List<ScannableField> _collect$Captain(Object object) {
  final owner = object as _Captain;
  return <ScannableField>[
    owner.speed,
    owner.hp,
    owner.alive,
    owner.stance,
    owner.leader,
    owner.shield,
    owner.aim,
  ];
}

const List<Type> _supertypes$Captain = <Type>[
  _Captain,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Body,
];

List<ScannableField> _collect$Lieutenant(Object object) {
  final owner = object as _Lieutenant;
  return <ScannableField>[
    owner.speed,
    owner.hp,
    owner.alive,
    owner.stance,
    owner.leader,
    owner.shield,
    owner.aim,
  ];
}

const List<Type> _supertypes$Lieutenant = <Type>[
  _Lieutenant,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Body,
];

List<ScannableField> _collect$Squad(Object object) {
  final owner = object as _Squad;
  return <ScannableField>[
    owner.grunt,
    owner.captain,
    owner.lieutenant,
  ];
}

const List<Type> _supertypes$Squad = <Type>[
  _Squad,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _columnInitialValueTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/column_initial_value_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Grunt, _collect$Grunt, _supertypes$Grunt),
        DeclarationCollector(_Captain, _collect$Captain, _supertypes$Captain),
        DeclarationCollector(
          _Lieutenant,
          _collect$Lieutenant,
          _supertypes$Lieutenant,
        ),
        DeclarationCollector(_Squad, _collect$Squad, _supertypes$Squad),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_columnInitialValueTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_columnInitialValueTestDeclarations],
);
