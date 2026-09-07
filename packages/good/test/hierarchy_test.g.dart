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
part of 'hierarchy_test.dart';

List<ScannableField> _collect$Node(Object object) {
  final owner = object as _Node;
  return <ScannableField>[
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.tag,
  ];
}

const List<Type> _supertypes$Node = <Type>[
  _Node,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Name,
  Child,
  Parent,
];

List<ScannableField> _collect$Leaf(Object object) {
  final owner = object as _Leaf;
  return <ScannableField>[
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.tag,
  ];
}

const List<Type> _supertypes$Leaf = <Type>[
  _Leaf,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Name,
  Child,
];

List<ScannableField> _collect$NoChild(Object object) {
  final owner = object as _NoChild;
  return <ScannableField>[
    owner.tag,
  ];
}

const List<Type> _supertypes$NoChild = <Type>[
  _NoChild,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Name,
];

List<ScannableField> _collect$BareNode(Object object) {
  final owner = object as _BareNode;
  return <ScannableField>[
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
  ];
}

const List<Type> _supertypes$BareNode = <Type>[
  _BareNode,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  Child,
  Parent,
];

List<ScannableField> _collect$Barrel(Object object) {
  final owner = object as _Barrel;
  return <ScannableField>[
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.tag,
  ];
}

const List<Type> _supertypes$Barrel = <Type>[
  _Barrel,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Name,
  Child,
];

List<ScannableField> _collect$Tip(Object object) {
  final owner = object as _Tip;
  return <ScannableField>[
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.tag,
  ];
}

const List<Type> _supertypes$Tip = <Type>[
  _Tip,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Name,
  Child,
];

List<ScannableField> _collect$Turret(Object object) {
  final owner = object as _Turret;
  return <ScannableField>[
    owner.barrel,
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.tag,
  ];
}

const List<Type> _supertypes$Turret = <Type>[
  _Turret,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Name,
  Child,
  Parent,
];

List<ScannableField> _collect$Rig(Object object) {
  final owner = object as _Rig;
  return <ScannableField>[
    owner.left,
    owner.middle,
    owner.right,
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.tag,
  ];
}

const List<Type> _supertypes$Rig = <Type>[
  _Rig,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Name,
  Parent,
];

List<ScannableField> _collect$DeepBarrel(Object object) {
  final owner = object as _DeepBarrel;
  return <ScannableField>[
    owner.tip,
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.tag,
  ];
}

const List<Type> _supertypes$DeepBarrel = <Type>[
  _DeepBarrel,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Name,
  Child,
  Parent,
];

List<ScannableField> _collect$DeepTurret(Object object) {
  final owner = object as _DeepTurret;
  return <ScannableField>[
    owner.barrel,
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.tag,
  ];
}

const List<Type> _supertypes$DeepTurret = <Type>[
  _DeepTurret,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Name,
  Parent,
];

List<ScannableField> _collect$DeclaresANonChild(Object object) {
  final owner = object as _DeclaresANonChild;
  return <ScannableField>[
    owner.loose,
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.tag,
  ];
}

const List<Type> _supertypes$DeclaresANonChild = <Type>[
  _DeclaresANonChild,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Name,
  Parent,
];

List<ScannableField> _collect$DeclaresWithoutParent(Object object) {
  final owner = object as _DeclaresWithoutParent;
  return <ScannableField>[
    owner.barrel,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.tag,
  ];
}

const List<Type> _supertypes$DeclaresWithoutParent = <Type>[
  _DeclaresWithoutParent,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Name,
  Child,
];

List<ScannableField> _collect$Probed(Object object) {
  object as _Probed;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Probed = <Type>[
  _Probed,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Probe,
];

List<ScannableField> _collect$ProbedSuperLast(Object object) {
  object as _ProbedSuperLast;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ProbedSuperLast = <Type>[
  _ProbedSuperLast,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Probe,
];

List<ScannableField> _collect$ProbedNoSuper(Object object) {
  object as _ProbedNoSuper;
  return const <ScannableField>[];
}

const List<Type> _supertypes$ProbedNoSuper = <Type>[
  _ProbedNoSuper,
  EntityStruct,
  // Coroutines: the library this part belongs to does not import it.
  // Animations: the library this part belongs to does not import it.
  MultiComponent,
  Component,
  Scannable,
  ScannableField,
  _Probe,
];

List<ScannableField> _collect$Level(Object object) {
  final owner = object as _Level;
  return <ScannableField>[
    owner.node,
    owner.leaf,
    owner.noChild,
    owner.bareNode,
    owner.turret,
    owner.rig,
    owner.deepTurret,
    owner.probed,
    owner.probedSuperLast,
    owner.probedNoSuper,
  ];
}

const List<Type> _supertypes$Level = <Type>[
  _Level,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$OneOff(Object object) {
  object as _OneOff;
  return const <ScannableField>[];
}

const List<Type> _supertypes$OneOff = <Type>[
  _OneOff,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

/// Whether an object is a _OneOff, whatever its type arguments are.
bool _is$OneOff(Object object) => object is _OneOff;

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _hierarchyTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/hierarchy_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Node, _collect$Node, _supertypes$Node),
        DeclarationCollector(_Leaf, _collect$Leaf, _supertypes$Leaf),
        DeclarationCollector(_NoChild, _collect$NoChild, _supertypes$NoChild),
        DeclarationCollector(
          _BareNode,
          _collect$BareNode,
          _supertypes$BareNode,
        ),
        DeclarationCollector(_Barrel, _collect$Barrel, _supertypes$Barrel),
        DeclarationCollector(_Tip, _collect$Tip, _supertypes$Tip),
        DeclarationCollector(_Turret, _collect$Turret, _supertypes$Turret),
        DeclarationCollector(_Rig, _collect$Rig, _supertypes$Rig),
        DeclarationCollector(
          _DeepBarrel,
          _collect$DeepBarrel,
          _supertypes$DeepBarrel,
        ),
        DeclarationCollector(
          _DeepTurret,
          _collect$DeepTurret,
          _supertypes$DeepTurret,
        ),
        DeclarationCollector(
          _DeclaresANonChild,
          _collect$DeclaresANonChild,
          _supertypes$DeclaresANonChild,
        ),
        DeclarationCollector(
          _DeclaresWithoutParent,
          _collect$DeclaresWithoutParent,
          _supertypes$DeclaresWithoutParent,
        ),
        DeclarationCollector(_Probed, _collect$Probed, _supertypes$Probed),
        DeclarationCollector(
          _ProbedSuperLast,
          _collect$ProbedSuperLast,
          _supertypes$ProbedSuperLast,
        ),
        DeclarationCollector(
          _ProbedNoSuper,
          _collect$ProbedNoSuper,
          _supertypes$ProbedNoSuper,
        ),
        DeclarationCollector(_Level, _collect$Level, _supertypes$Level),
        DeclarationCollector.generic(
          _OneOff,
          _collect$OneOff,
          _is$OneOff,
          _supertypes$OneOff,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_hierarchyTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_hierarchyTestDeclarations],
);
