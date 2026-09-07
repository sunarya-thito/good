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

const List<Type> _supertypes$Damage = <Type>[
  _Damage,
  GameCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$Ping(Object object) {
  object as _Ping;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Ping = <Type>[
  _Ping,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$NextId(Object object) {
  final owner = object as _NextId;
  return <ScannableField>[
    owner.id,
  ];
}

const List<Type> _supertypes$NextId = <Type>[
  _NextId,
  SupplierCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$Log(Object object) {
  final owner = object as _Log;
  return <ScannableField>[
    owner.message,
  ];
}

const List<Type> _supertypes$Log = <Type>[
  _Log,
  SinkCommand,
  GameCommandBase,
  Scannable,
];

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

const List<Type> _supertypes$Wide = <Type>[
  _Wide,
  GameCommand,
  GameCommandBase,
  Scannable,
];

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

const List<Type> _supertypes$Vocabulary = <Type>[
  _Vocabulary,
  GameCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$OneBitAsNumber(Object object) {
  final owner = object as _OneBitAsNumber;
  return <ScannableField>[
    owner.on,
  ];
}

const List<Type> _supertypes$OneBitAsNumber = <Type>[
  _OneBitAsNumber,
  GameCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$OneBitAsFlag(Object object) {
  final owner = object as _OneBitAsFlag;
  return <ScannableField>[
    owner.on,
  ];
}

const List<Type> _supertypes$OneBitAsFlag = <Type>[
  _OneBitAsFlag,
  GameCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$OrderUnit(Object object) {
  final owner = object as _OrderUnit;
  return <ScannableField>[
    owner.unit,
    owner.waypoint,
    owner.escort,
  ];
}

const List<Type> _supertypes$OrderUnit = <Type>[
  _OrderUnit,
  GameCommand,
  GameCommandBase,
  Scannable,
];

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

const List<Type> _supertypes$Publish = <Type>[
  _Publish,
  GameCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$Unhandled(Object object) {
  object as _Unhandled;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Unhandled = <Type>[
  _Unhandled,
  SignalCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$TwoOnFieldsOneInHook(Object object) {
  final owner = object as _TwoOnFieldsOneInHook;
  return <ScannableField>[
    owner.head,
    owner.flag,
  ];
}

const List<Type> _supertypes$TwoOnFieldsOneInHook = <Type>[
  _TwoOnFieldsOneInHook,
  SinkCommand,
  GameCommandBase,
  Scannable,
];

List<ScannableField> _collect$OneOnFieldTwoInHook(Object object) {
  final owner = object as _OneOnFieldTwoInHook;
  return <ScannableField>[
    owner.head,
  ];
}

const List<Type> _supertypes$OneOnFieldTwoInHook = <Type>[
  _OneOnFieldTwoInHook,
  SinkCommand,
  GameCommandBase,
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _commandParamTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/command_param_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Damage, _collect$Damage, _supertypes$Damage),
        DeclarationCollector(_Ping, _collect$Ping, _supertypes$Ping),
        DeclarationCollector(_NextId, _collect$NextId, _supertypes$NextId),
        DeclarationCollector(_Log, _collect$Log, _supertypes$Log),
        DeclarationCollector(_Wide, _collect$Wide, _supertypes$Wide),
        DeclarationCollector(
          _Vocabulary,
          _collect$Vocabulary,
          _supertypes$Vocabulary,
        ),
        DeclarationCollector(
          _OneBitAsNumber,
          _collect$OneBitAsNumber,
          _supertypes$OneBitAsNumber,
        ),
        DeclarationCollector(
          _OneBitAsFlag,
          _collect$OneBitAsFlag,
          _supertypes$OneBitAsFlag,
        ),
        DeclarationCollector(
          _OrderUnit,
          _collect$OrderUnit,
          _supertypes$OrderUnit,
        ),
        DeclarationCollector(_Publish, _collect$Publish, _supertypes$Publish),
        DeclarationCollector(
          _Unhandled,
          _collect$Unhandled,
          _supertypes$Unhandled,
        ),
        DeclarationCollector(
          _TwoOnFieldsOneInHook,
          _collect$TwoOnFieldsOneInHook,
          _supertypes$TwoOnFieldsOneInHook,
        ),
        DeclarationCollector(
          _OneOnFieldTwoInHook,
          _collect$OneOnFieldTwoInHook,
          _supertypes$OneOnFieldTwoInHook,
        ),
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
