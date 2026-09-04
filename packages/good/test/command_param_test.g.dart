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
part of 'command_param_test.dart';

List<ScannableField> _collect$Damage(Object object) {
  final owner = object as _Damage;
  return <ScannableField>[
    owner.amount,
    owner.crit,
    owner.dealt,
    owner.overkill,
  ];
}

List<ScannableField> _collect$Ping(Object object) {
  object as _Ping;
  return const <ScannableField>[];
}

List<ScannableField> _collect$NextId(Object object) {
  final owner = object as _NextId;
  return <ScannableField>[
    owner.id,
  ];
}

List<ScannableField> _collect$Log(Object object) {
  final owner = object as _Log;
  return <ScannableField>[
    owner.message,
  ];
}

List<ScannableField> _collect$Wide(Object object) {
  final owner = object as _Wide;
  return <ScannableField>[
    owner.flag,
    owner.pair,
    owner.nibble,
    owner.u8,
    owner.i8,
    owner.u16,
    owner.i16,
    owner.u32,
    owner.i32,
    owner.i64,
    owner.f32,
    owner.f64,
    owner.name,
  ];
}

List<ScannableField> _collect$Vocabulary(Object object) {
  final owner = object as _Vocabulary;
  return <ScannableField>[
    owner.on,
    owner.off,
    owner.s1,
    owner.s2,
    owner.s4,
    owner.u64,
  ];
}

List<ScannableField> _collect$OneBitAsNumber(Object object) {
  final owner = object as _OneBitAsNumber;
  return <ScannableField>[
    owner.on,
  ];
}

List<ScannableField> _collect$OneBitAsFlag(Object object) {
  final owner = object as _OneBitAsFlag;
  return <ScannableField>[
    owner.on,
  ];
}

List<ScannableField> _collect$OrderUnit(Object object) {
  final owner = object as _OrderUnit;
  return <ScannableField>[
    owner.unit,
    owner.waypoint,
    owner.escort,
  ];
}

List<ScannableField> _collect$Publish(Object object) {
  final owner = object as _Publish;
  return <ScannableField>[
    owner.topic,
    owner.body,
    owner.blob,
    owner.stamp,
    owner.receipt,
  ];
}

List<ScannableField> _collect$Unhandled(Object object) {
  object as _Unhandled;
  return const <ScannableField>[];
}

List<ScannableField> _collect$TwoOnFieldsOneInHook(Object object) {
  final owner = object as _TwoOnFieldsOneInHook;
  return <ScannableField>[
    owner.head,
    owner.flag,
  ];
}

List<ScannableField> _collect$OneOnFieldTwoInHook(Object object) {
  final owner = object as _OneOnFieldTwoInHook;
  return <ScannableField>[
    owner.head,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _commandParamTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/command_param_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Damage, _collect$Damage),
        DeclarationCollector(_Ping, _collect$Ping),
        DeclarationCollector(_NextId, _collect$NextId),
        DeclarationCollector(_Log, _collect$Log),
        DeclarationCollector(_Wide, _collect$Wide),
        DeclarationCollector(_Vocabulary, _collect$Vocabulary),
        DeclarationCollector(_OneBitAsNumber, _collect$OneBitAsNumber),
        DeclarationCollector(_OneBitAsFlag, _collect$OneBitAsFlag),
        DeclarationCollector(_OrderUnit, _collect$OrderUnit),
        DeclarationCollector(_Publish, _collect$Publish),
        DeclarationCollector(_Unhandled, _collect$Unhandled),
        DeclarationCollector(_TwoOnFieldsOneInHook, _collect$TwoOnFieldsOneInHook),
        DeclarationCollector(_OneOnFieldTwoInHook, _collect$OneOnFieldTwoInHook),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_commandParamTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_commandParamTestDeclarations],
);
