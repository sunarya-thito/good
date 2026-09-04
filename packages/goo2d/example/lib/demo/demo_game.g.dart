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
part of 'demo_game.dart';

List<ScannableField> _collect$SetPopulation(Object object) {
  final owner = object as SetPopulation;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$FixedPhaseStart(Object object) {
  final owner = object as _FixedPhaseStart;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$FixedPhaseEnd(Object object) {
  final owner = object as _FixedPhaseEnd;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$PresentPhaseStart(Object object) {
  final owner = object as _PresentPhaseStart;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$RenderPhaseStart(Object object) {
  final owner = object as _RenderPhaseStart;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$RenderPhaseEnd(Object object) {
  final owner = object as _RenderPhaseEnd;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$DemoStats(Object object) {
  final owner = object as DemoStats;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _demoGameDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/example/lib/demo/demo_game.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(SetPopulation, _collect$SetPopulation),
        DeclarationCollector(_FixedPhaseStart, _collect$FixedPhaseStart),
        DeclarationCollector(_FixedPhaseEnd, _collect$FixedPhaseEnd),
        DeclarationCollector(_PresentPhaseStart, _collect$PresentPhaseStart),
        DeclarationCollector(_RenderPhaseStart, _collect$RenderPhaseStart),
        DeclarationCollector(_RenderPhaseEnd, _collect$RenderPhaseEnd),
        DeclarationCollector(DemoStats, _collect$DemoStats),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );
