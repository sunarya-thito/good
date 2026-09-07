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
part of 'demo_game.dart';

List<ScannableField> _collect$SetPopulation(Object object) {
  final owner = object as SetPopulation;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$SetPopulation = <Type>[
  SetPopulation,
  ValueSink,
  SinkCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$FixedPhaseStart(Object object) {
  object as FixedPhaseStart;
  return const <ScannableField>[];
}

const List<Type> _supertypes$FixedPhaseStart = <Type>[
  FixedPhaseStart,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$FixedPhaseEnd(Object object) {
  object as _FixedPhaseEnd;
  return const <ScannableField>[];
}

const List<Type> _supertypes$FixedPhaseEnd = <Type>[
  _FixedPhaseEnd,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$PresentPhaseStart(Object object) {
  object as PresentPhaseStart;
  return const <ScannableField>[];
}

const List<Type> _supertypes$PresentPhaseStart = <Type>[
  PresentPhaseStart,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  Tickable,
];

List<ScannableField> _collect$RenderPhaseStart(Object object) {
  object as _RenderPhaseStart;
  return const <ScannableField>[];
}

const List<Type> _supertypes$RenderPhaseStart = <Type>[
  _RenderPhaseStart,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  Tickable,
];

List<ScannableField> _collect$RenderPhaseEnd(Object object) {
  object as _RenderPhaseEnd;
  return const <ScannableField>[];
}

const List<Type> _supertypes$RenderPhaseEnd = <Type>[
  _RenderPhaseEnd,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  Tickable,
];

List<ScannableField> _collect$DemoStats(Object object) {
  object as DemoStats;
  return const <ScannableField>[];
}

const List<Type> _supertypes$DemoStats = <Type>[
  DemoStats,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  Tickable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _demoGameDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/example/lib/demo/demo_game.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(
          SetPopulation,
          _collect$SetPopulation,
          _supertypes$SetPopulation,
        ),
        DeclarationCollector(
          FixedPhaseStart,
          _collect$FixedPhaseStart,
          _supertypes$FixedPhaseStart,
        ),
        DeclarationCollector(
          _FixedPhaseEnd,
          _collect$FixedPhaseEnd,
          _supertypes$FixedPhaseEnd,
        ),
        DeclarationCollector(
          PresentPhaseStart,
          _collect$PresentPhaseStart,
          _supertypes$PresentPhaseStart,
        ),
        DeclarationCollector(
          _RenderPhaseStart,
          _collect$RenderPhaseStart,
          _supertypes$RenderPhaseStart,
        ),
        DeclarationCollector(
          _RenderPhaseEnd,
          _collect$RenderPhaseEnd,
          _supertypes$RenderPhaseEnd,
        ),
        DeclarationCollector(
          DemoStats,
          _collect$DemoStats,
          _supertypes$DemoStats,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );
