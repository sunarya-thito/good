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
part of 'field_declaration_test.dart';

List<ScannableField> _collect$Declared(Object object) {
  final owner = object as _Declared;
  return <ScannableField>[
    owner.speed,
    owner.hp,
    owner.alive,
  ];
}

const List<Type> _supertypes$Declared = <Type>[
  _Declared,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$Mixed(Object object) {
  final owner = object as _Mixed;
  return <ScannableField>[
    owner.own,
  ];
}

const List<Type> _supertypes$Mixed = <Type>[
  _Mixed,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Legacy,
];

List<ScannableField> _collect$OwnOnly(Object object) {
  final owner = object as _OwnOnly;
  return <ScannableField>[
    owner.own,
  ];
}

const List<Type> _supertypes$OwnOnly = <Type>[
  _OwnOnly,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$Twin(Object object) {
  final owner = object as _Twin;
  return <ScannableField>[
    owner.speed,
    owner.hp,
    owner.alive,
  ];
}

const List<Type> _supertypes$Twin = <Type>[
  _Twin,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$Throws(Object object) {
  final owner = object as _Throws;
  return <ScannableField>[
    owner.declaredBeforeTheThrow,
  ];
}

const List<Type> _supertypes$Throws = <Type>[
  _Throws,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$After(Object object) {
  final owner = object as _After;
  return <ScannableField>[
    owner.mark,
  ];
}

const List<Type> _supertypes$After = <Type>[
  _After,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$Broken(Object object) {
  final owner = object as _Broken;
  return <ScannableField>[
    owner.after,
  ];
}

const List<Type> _supertypes$Broken = <Type>[
  _Broken,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$Level(Object object) {
  final owner = object as _Level;
  return <ScannableField>[
    owner.declared,
    owner.mixed,
    owner.ownOnly,
    owner.twin,
  ];
}

const List<Type> _supertypes$Level = <Type>[
  _Level,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$FromConstructor(Object object) {
  final owner = object as _FromConstructor;
  return <ScannableField>[
    owner.speed,
  ];
}

const List<Type> _supertypes$FromConstructor = <Type>[
  _FromConstructor,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

List<ScannableField> _collect$FromNowhere(Object object) {
  final owner = object as _FromNowhere;
  return <ScannableField>[
    owner.speed,
  ];
}

const List<Type> _supertypes$FromNowhere = <Type>[
  _FromNowhere,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _fieldDeclarationTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/field_declaration_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(
          _Declared,
          _collect$Declared,
          _supertypes$Declared,
        ),
        DeclarationCollector(_Mixed, _collect$Mixed, _supertypes$Mixed),
        DeclarationCollector(_OwnOnly, _collect$OwnOnly, _supertypes$OwnOnly),
        DeclarationCollector(_Twin, _collect$Twin, _supertypes$Twin),
        DeclarationCollector(_Throws, _collect$Throws, _supertypes$Throws),
        DeclarationCollector(_After, _collect$After, _supertypes$After),
        DeclarationCollector(_Broken, _collect$Broken, _supertypes$Broken),
        DeclarationCollector(_Level, _collect$Level, _supertypes$Level),
        DeclarationCollector(
          _FromConstructor,
          _collect$FromConstructor,
          _supertypes$FromConstructor,
        ),
        DeclarationCollector(
          _FromNowhere,
          _collect$FromNowhere,
          _supertypes$FromNowhere,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_fieldDeclarationTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_fieldDeclarationTestDeclarations],
);
