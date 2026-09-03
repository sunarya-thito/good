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
// A generic fixture also gets an `is` test. Nothing at run
// time can take the type arguments off a `Type`, so the
// literal in the table below never equals an instance's
// `runtimeType` - the test is what matches the two.
part of 'generic_declaration_test.dart';

List<ScannableField> _collect$Enemy(Object object) {
  final owner = object as _Enemy;
  return <ScannableField>[
    owner.hp,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Pickup(Object object) {
  final owner = object as _Pickup;
  return <ScannableField>[
    owner.value,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Spawner(Object object) {
  final owner = object as _Spawner;
  return <ScannableField>[
    owner.rate,
    owner.budget,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Base(Object object) {
  final owner = object as _Base;
  return <ScannableField>[
    owner.base,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Derived(Object object) {
  final owner = object as _Derived;
  return <ScannableField>[
    owner.derived,
    owner.base,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

/// Whether an object is a _Spawner, whatever its type arguments are.
bool _is$Spawner(Object object) => object is _Spawner;

/// Whether an object is a _Base, whatever its type arguments are.
bool _is$Base(Object object) => object is _Base;

/// Whether an object is a _Derived, whatever its type arguments are.
bool _is$Derived(Object object) => object is _Derived;

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _genericDeclarationTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/generic_declaration_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Enemy, _collect$Enemy),
        DeclarationCollector(_Pickup, _collect$Pickup),
        DeclarationCollector.generic(_Spawner, _collect$Spawner, _is$Spawner),
        DeclarationCollector.generic(_Base, _collect$Base, _is$Base),
        DeclarationCollector.generic(_Derived, _collect$Derived, _is$Derived),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_genericDeclarationTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_genericDeclarationTestDeclarations],
);
