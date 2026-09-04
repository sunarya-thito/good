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
part of 'message_test.dart';

List<ScannableField> _collect$Fire(Object object) {
  final owner = object as _Fire;
  return <ScannableField>[
    owner.angle,
    owner.weapon,
  ];
}

List<ScannableField> _collect$Score(Object object) {
  final owner = object as _Score;
  return <ScannableField>[
    owner.score,
  ];
}

List<ScannableField> _collect$Chat(Object object) {
  final owner = object as _Chat;
  return <ScannableField>[
    owner.text,
  ];
}

List<ScannableField> _collect$Post(Object object) {
  final owner = object as _Post;
  return <ScannableField>[
    owner.text,
    owner.blob,
  ];
}

List<ScannableField> _collect$TailKind(Object object) {
  final owner = object as _TailKind;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$InlineKind(Object object) {
  final owner = object as _InlineKind;
  return <ScannableField>[
    owner.value,
  ];
}

List<ScannableField> _collect$Snapshot(Object object) {
  final owner = object as _Snapshot;
  return <ScannableField>[
    owner.state,
  ];
}

List<ScannableField> _collect$RoundOver(Object object) {
  object as _RoundOver;
  return const <ScannableField>[];
}

List<ScannableField> _collect$Ready(Object object) {
  object as _Ready;
  return const <ScannableField>[];
}

List<ScannableField> _collect$NetGame(Object object) {
  object as _NetGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$NetState(Object object) {
  final owner = object as _NetState;
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

List<ScannableField> _collect$Watcher(Object object) {
  final owner = object as _Watcher;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$FireRenamed(Object object) {
  final owner = object as _FireRenamed;
  return <ScannableField>[
    owner.angle,
    owner.weapon,
  ];
}

List<ScannableField> _collect$FireByHook(Object object) {
  object as _FireByHook;
  return const <ScannableField>[];
}

List<ScannableField> _collect$OneMessageState(Object object) {
  final owner = object as _OneMessageState;
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

List<ScannableField> _collect$OneMessageGame(Object object) {
  object as _OneMessageGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$CollidingState(Object object) {
  final owner = object as _CollidingState;
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

List<ScannableField> _collect$CollidingGame(Object object) {
  object as _CollidingGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$WatchedState(Object object) {
  final owner = object as _WatchedState;
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

List<ScannableField> _collect$WatchedGame(Object object) {
  object as _WatchedGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$Emote(Object object) {
  object as _Emote;
  return const <ScannableField>[];
}

List<ScannableField> _collect$SkewedState(Object object) {
  final owner = object as _SkewedState;
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

List<ScannableField> _collect$SkewedGame(Object object) {
  object as _SkewedGame;
  return const <ScannableField>[];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _messageTestDeclarations =
    GeneratedDeclarations(
      package: 'good_net/test/message_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Fire, _collect$Fire),
        DeclarationCollector(_Score, _collect$Score),
        DeclarationCollector(_Chat, _collect$Chat),
        DeclarationCollector(_Post, _collect$Post),
        DeclarationCollector(_TailKind, _collect$TailKind),
        DeclarationCollector(_InlineKind, _collect$InlineKind),
        DeclarationCollector(_Snapshot, _collect$Snapshot),
        DeclarationCollector(_RoundOver, _collect$RoundOver),
        DeclarationCollector(_Ready, _collect$Ready),
        DeclarationCollector(_NetGame, _collect$NetGame),
        DeclarationCollector(_NetState, _collect$NetState),
        DeclarationCollector(_Watcher, _collect$Watcher),
        DeclarationCollector(_FireRenamed, _collect$FireRenamed),
        DeclarationCollector(_FireByHook, _collect$FireByHook),
        DeclarationCollector(_OneMessageState, _collect$OneMessageState),
        DeclarationCollector(_OneMessageGame, _collect$OneMessageGame),
        DeclarationCollector(_CollidingState, _collect$CollidingState),
        DeclarationCollector(_CollidingGame, _collect$CollidingGame),
        DeclarationCollector(_WatchedState, _collect$WatchedState),
        DeclarationCollector(_WatchedGame, _collect$WatchedGame),
        DeclarationCollector(_Emote, _collect$Emote),
        DeclarationCollector(_SkewedState, _collect$SkewedState),
        DeclarationCollector(_SkewedGame, _collect$SkewedGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goodNetDeclarations,
      ],
    );

/// Installs [_messageTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_messageTestDeclarations],
);
