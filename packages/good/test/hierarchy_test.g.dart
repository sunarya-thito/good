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
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Leaf(Object object) {
  final owner = object as _Leaf;
  return <ScannableField>[
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.tag,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$NoChild(Object object) {
  final owner = object as _NoChild;
  return <ScannableField>[
    owner.tag,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$BareNode(Object object) {
  final owner = object as _BareNode;
  return <ScannableField>[
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Barrel(Object object) {
  final owner = object as _Barrel;
  return <ScannableField>[
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.tag,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Tip(Object object) {
  final owner = object as _Tip;
  return <ScannableField>[
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.tag,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

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
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Rig(Object object) {
  final owner = object as _Rig;
  return <ScannableField>[
    owner.left,
    owner.middle,
    owner.right,
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.tag,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

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
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$DeepTurret(Object object) {
  final owner = object as _DeepTurret;
  return <ScannableField>[
    owner.barrel,
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.tag,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$DeclaresANonChild(Object object) {
  final owner = object as _DeclaresANonChild;
  return <ScannableField>[
    owner.loose,
    owner.parentFirstChild,
    owner.parentLastChild,
    owner.tag,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$DeclaresWithoutParent(Object object) {
  final owner = object as _DeclaresWithoutParent;
  return <ScannableField>[
    owner.barrel,
    owner.childParent,
    owner.childNextSibling,
    owner.childPrevSibling,
    owner.tag,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$Probed(Object object) {
  final owner = object as _Probed;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$ProbedSuperLast(Object object) {
  final owner = object as _ProbedSuperLast;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$ProbedNoSuper(Object object) {
  final owner = object as _ProbedNoSuper;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

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
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$OneOff(Object object) {
  final owner = object as _OneOff;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _hierarchyTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/hierarchy_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Node, _collect$Node),
        DeclarationCollector(_Leaf, _collect$Leaf),
        DeclarationCollector(_NoChild, _collect$NoChild),
        DeclarationCollector(_BareNode, _collect$BareNode),
        DeclarationCollector(_Barrel, _collect$Barrel),
        DeclarationCollector(_Tip, _collect$Tip),
        DeclarationCollector(_Turret, _collect$Turret),
        DeclarationCollector(_Rig, _collect$Rig),
        DeclarationCollector(_DeepBarrel, _collect$DeepBarrel),
        DeclarationCollector(_DeepTurret, _collect$DeepTurret),
        DeclarationCollector(_DeclaresANonChild, _collect$DeclaresANonChild),
        DeclarationCollector(_DeclaresWithoutParent, _collect$DeclaresWithoutParent),
        DeclarationCollector(_Probed, _collect$Probed),
        DeclarationCollector(_ProbedSuperLast, _collect$ProbedSuperLast),
        DeclarationCollector(_ProbedNoSuper, _collect$ProbedNoSuper),
        DeclarationCollector(_Level, _collect$Level),
        DeclarationCollector(_OneOff, _collect$OneOff),
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
