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
//
// A generic fixture also gets an `is` test. Nothing at run
// time can take the type arguments off a `Type`, so the
// literal in the table below never equals an instance's
// `runtimeType` - the test is what matches the two.
part of 'supertype_collection_test.dart';

List<ScannableField> _collect$Player(Object object) {
  final owner = object as _Player;
  return <ScannableField>[
    owner.name,
    owner.hp,
    owner.x,
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
  _Positioned,
  _Damaged,
  _Tagged,
];

List<ScannableField> _collect$Bare(Object object) {
  object as _Bare;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Bare = <Type>[
  _Bare,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$Spawner(Object object) {
  final owner = object as _Spawner;
  return <ScannableField>[
    owner.rate,
  ];
}

const List<Type> _supertypes$Spawner = <Type>[
  _Spawner,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Tagged,
];

/// Whether an object is a _Spawner, whatever its type arguments are.
bool _is$Spawner(Object object) => object is _Spawner;

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _supertypeCollectionTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/supertype_collection_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Player, _collect$Player, _supertypes$Player),
        DeclarationCollector(_Bare, _collect$Bare, _supertypes$Bare),
        DeclarationCollector.generic(
          _Spawner,
          _collect$Spawner,
          _is$Spawner,
          _supertypes$Spawner,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_supertypeCollectionTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_supertypeCollectionTestDeclarations],
);
