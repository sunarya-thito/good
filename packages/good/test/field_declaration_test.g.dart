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
part of 'field_declaration_test.dart';

List<ScannableField> _collect$Declared(Object object) {
  final owner = object as _Declared;
  return <ScannableField>[
    owner.speed,
    owner.hp,
    owner.alive,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Mixed(Object object) {
  final owner = object as _Mixed;
  return <ScannableField>[
    owner.own,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$OwnOnly(Object object) {
  final owner = object as _OwnOnly;
  return <ScannableField>[
    owner.own,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Twin(Object object) {
  final owner = object as _Twin;
  return <ScannableField>[
    owner.speed,
    owner.hp,
    owner.alive,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Throws(Object object) {
  final owner = object as _Throws;
  return <ScannableField>[
    owner.declaredBeforeTheThrow,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$After(Object object) {
  final owner = object as _After;
  return <ScannableField>[
    owner.mark,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Broken(Object object) {
  final owner = object as _Broken;
  return <ScannableField>[
    owner.after,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Level(Object object) {
  final owner = object as _Level;
  return <ScannableField>[
    owner.declared,
    owner.mixed,
    owner.ownOnly,
    owner.twin,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$FromConstructor(Object object) {
  final owner = object as _FromConstructor;
  return <ScannableField>[
    owner.speed,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$FromNowhere(Object object) {
  final owner = object as _FromNowhere;
  return <ScannableField>[
    owner.speed,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _fieldDeclarationTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/field_declaration_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Declared, _collect$Declared),
        DeclarationCollector(_Mixed, _collect$Mixed),
        DeclarationCollector(_OwnOnly, _collect$OwnOnly),
        DeclarationCollector(_Twin, _collect$Twin),
        DeclarationCollector(_Throws, _collect$Throws),
        DeclarationCollector(_After, _collect$After),
        DeclarationCollector(_Broken, _collect$Broken),
        DeclarationCollector(_Level, _collect$Level),
        DeclarationCollector(_FromConstructor, _collect$FromConstructor),
        DeclarationCollector(_FromNowhere, _collect$FromNowhere),
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
