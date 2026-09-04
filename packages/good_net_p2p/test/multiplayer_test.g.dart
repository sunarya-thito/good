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
part of 'multiplayer_test.dart';

List<ScannableField> _collect$Fire(Object object) {
  final owner = object as Fire;
  return <ScannableField>[
    owner.angle,
    owner.weapon,
  ];
}

List<ScannableField> _collect$Hit(Object object) {
  final owner = object as Hit;
  return <ScannableField>[
    owner.slot,
    owner.damage,
  ];
}

List<ScannableField> _collect$ShooterGame(Object object) {
  object as ShooterGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$ShooterState(Object object) {
  final owner = object as ShooterState;
  return <ScannableField>[
    owner.peerJoinedEvent,
    owner.peerLeftEvent,
    owner.sessionOpenedEvent,
    owner.sessionClosedEvent,
    owner.fixedTickEvent,
    owner.tickEvent,
    owner.gameMountedEvent,
    owner.gameUnmountedEvent,
    owner.appHiddenEvent,
    owner.appShownEvent,
    owner.entitySpawnedEvent,
    owner.entityDespawnedEvent,
    owner.sceneLoadedEvent,
    owner.sceneUnloadedEvent,
  ];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the generated tables this library imports,
/// so installing this installs the collectors for the
/// engine classes a fixture is built on as well. Not this
/// package's own: either it has none, or one of these
/// already names it.
const GeneratedDeclarations _multiplayerTestDeclarations =
    GeneratedDeclarations(
      package: 'good_net_p2p/test/multiplayer_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(Fire, _collect$Fire),
        DeclarationCollector(Hit, _collect$Hit),
        DeclarationCollector(ShooterGame, _collect$ShooterGame),
        DeclarationCollector(ShooterState, _collect$ShooterState),
      ],
      dependencies: <GeneratedDeclarations>[
        goodNetDeclarations,
      ],
    );

/// Installs [_multiplayerTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_multiplayerTestDeclarations],
);
