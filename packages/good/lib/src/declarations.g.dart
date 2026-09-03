// GENERATED - do not edit.
//
// Regenerate with `dart run good_tool` from
// packages/good_tool, and commit what changes.
// `dart run good_tool --check` is what CI runs; it fails if
// this file is not what the generator would write.
//
// One function per class this package can instantiate that
// declares anything. A declaration is a field holding its own
// value, with nothing open around it, so this is the only
// record of what a class declared - and a class's field list
// is the one thing a running program cannot ask for.
//
// The order inside each list is the order the fields would
// have been initialised in: the class's own, then each
// mixin's with the last name in the `with` clause first,
// then the superclass's. That order is the field order of
// every row of the archetype, so reordering a list here
// relays out the entities.
//
// A commented-out line is a declaration held by a private
// field. Dart privacy is per library and this is a different
// one, so nothing here can read it - it keeps its place so
// that what the row is missing, and where, is visible.

import 'package:good/src/game.dart';
import 'package:good/src/scannable.dart';

List<ScannableField> _reportDisabledSystemCommand(Object object) {
  final owner = object as ReportDisabledSystemCommand;
  return <ScannableField>[
    owner.systemName,
    owner.error,
    owner.stackTrace,
  ];
}

List<ScannableField> _setPausedCommand(Object object) {
  final owner = object as SetPausedCommand;
  return <ScannableField>[
    owner.paused,
  ];
}

List<ScannableField> _setTimeScaleCommand(Object object) {
  final owner = object as SetTimeScaleCommand;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _setVisibleCommand(Object object) {
  final owner = object as SetVisibleCommand;
  return <ScannableField>[
    owner.visible,
  ];
}

List<ScannableField> _stepOnceCommand(Object object) {
  object as StepOnceCommand;
  return const <ScannableField>[];
}

/// Every class `package:good` can instantiate that holds a
/// declaration, and how to read one.
///
/// Pass this to `Game.declarations` - together with the table
/// of every other engine package the game uses, and the one
/// generated for the game itself - so a registration can read
/// what a constructed object declared.
const GeneratedDeclarations goodDeclarations = GeneratedDeclarations(
  package: 'good',
  collectors: <DeclarationCollector>[
    DeclarationCollector(ReportDisabledSystemCommand, _reportDisabledSystemCommand),
    DeclarationCollector(SetPausedCommand, _setPausedCommand),
    DeclarationCollector(SetTimeScaleCommand, _setTimeScaleCommand),
    DeclarationCollector(SetVisibleCommand, _setVisibleCommand),
    DeclarationCollector(StepOnceCommand, _stepOnceCommand),
  ],
);
