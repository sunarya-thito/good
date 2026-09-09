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
part of 'column_declaration_test.dart';

List<ScannableField> _collect$WideColumn(Object object) {
  final owner = object as _WideColumn;
  return <ScannableField>[
    owner.wide,
  ];
}

List<ScannableField> _collect$EmptyArray(Object object) {
  final owner = object as _EmptyArray;
  return <ScannableField>[
    owner.slots,
  ];
}

List<ScannableField> _collect$NeverRegistered(Object object) {
  final owner = object as _NeverRegistered;
  return <ScannableField>[
    owner.slots,
    owner.wide,
  ];
}

List<ScannableField> _collect$WideScene(Object object) {
  final owner = object as _WideScene;
  return <ScannableField>[
    owner.wide,
  ];
}

List<ScannableField> _collect$EmptyArrayScene(Object object) {
  final owner = object as _EmptyArrayScene;
  return <ScannableField>[
    owner.empty,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _columnDeclarationTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/column_declaration_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_WideColumn, _collect$WideColumn),
        DeclarationCollector(_EmptyArray, _collect$EmptyArray),
        DeclarationCollector(_NeverRegistered, _collect$NeverRegistered),
        DeclarationCollector(_WideScene, _collect$WideScene),
        DeclarationCollector(_EmptyArrayScene, _collect$EmptyArrayScene),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_columnDeclarationTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_columnDeclarationTestDeclarations],
);
