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
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

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
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

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
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Squad(Object object) {
  final owner = object as _Squad;
  return <ScannableField>[
    owner.grunt,
    owner.captain,
    owner.lieutenant,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _columnInitialValueTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/column_initial_value_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Grunt, _collect$Grunt),
        DeclarationCollector(_Captain, _collect$Captain),
        DeclarationCollector(_Lieutenant, _collect$Lieutenant),
        DeclarationCollector(_Squad, _collect$Squad),
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
