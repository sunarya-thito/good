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
part of 'message_test.dart';

List<ScannableField> _collect$Fire(Object object) {
  final owner = object as _Fire;
  return <ScannableField>[
    owner.angle,
    owner.weapon,
  ];
}

const List<Type> _supertypes$Fire = <Type>[
  _Fire,
  NetMessage,
  NetMessageBase,
  Scannable,
];

List<ScannableField> _collect$Score(Object object) {
  final owner = object as _Score;
  return <ScannableField>[
    owner.score,
  ];
}

const List<Type> _supertypes$Score = <Type>[
  _Score,
  NetMessage,
  NetMessageBase,
  Scannable,
];

List<ScannableField> _collect$Chat(Object object) {
  final owner = object as _Chat;
  return <ScannableField>[
    owner.text,
  ];
}

const List<Type> _supertypes$Chat = <Type>[
  _Chat,
  NetMessage,
  NetMessageBase,
  Scannable,
];

List<ScannableField> _collect$Post(Object object) {
  final owner = object as _Post;
  return <ScannableField>[
    owner.text,
    owner.blob,
  ];
}

const List<Type> _supertypes$Post = <Type>[
  _Post,
  NetMessage,
  NetMessageBase,
  Scannable,
];

List<ScannableField> _collect$TailKind(Object object) {
  final owner = object as _TailKind;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$TailKind = <Type>[
  _TailKind,
  NetMessage,
  NetMessageBase,
  Scannable,
];

List<ScannableField> _collect$InlineKind(Object object) {
  final owner = object as _InlineKind;
  return <ScannableField>[
    owner.value,
  ];
}

const List<Type> _supertypes$InlineKind = <Type>[
  _InlineKind,
  NetMessage,
  NetMessageBase,
  Scannable,
];

List<ScannableField> _collect$Snapshot(Object object) {
  final owner = object as _Snapshot;
  return <ScannableField>[
    owner.state,
  ];
}

const List<Type> _supertypes$Snapshot = <Type>[
  _Snapshot,
  NetMessage,
  NetMessageBase,
  Scannable,
];

List<ScannableField> _collect$RoundOver(Object object) {
  object as _RoundOver;
  return const <ScannableField>[];
}

const List<Type> _supertypes$RoundOver = <Type>[
  _RoundOver,
  NetSignal,
  NetMessageBase,
  Scannable,
];

List<ScannableField> _collect$Ready(Object object) {
  object as _Ready;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Ready = <Type>[
  _Ready,
  NetSignal,
  NetMessageBase,
  Scannable,
];

List<ScannableField> _collect$NetGame(Object object) {
  object as _NetGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$NetGame = <Type>[
  _NetGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$NetState(Object object) {
  final owner = object as _NetState;
  return <ScannableField>[
    owner.network,
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

const List<Type> _supertypes$NetState = <Type>[
  _NetState,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  MultiplayerState,
];

List<ScannableField> _collect$Watcher(Object object) {
  object as _Watcher;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Watcher = <Type>[
  _Watcher,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  NetPeerListener,
  NetSessionListener,
];

List<ScannableField> _collect$FireRenamed(Object object) {
  final owner = object as _FireRenamed;
  return <ScannableField>[
    owner.angle,
    owner.weapon,
  ];
}

const List<Type> _supertypes$FireRenamed = <Type>[
  _FireRenamed,
  NetMessage,
  NetMessageBase,
  Scannable,
];

List<ScannableField> _collect$FireByHook(Object object) {
  object as _FireByHook;
  return const <ScannableField>[];
}

const List<Type> _supertypes$FireByHook = <Type>[
  _FireByHook,
  NetMessage,
  NetMessageBase,
  Scannable,
];

List<ScannableField> _collect$OneMessageState(Object object) {
  final owner = object as _OneMessageState;
  return <ScannableField>[
    owner.network,
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

const List<Type> _supertypes$OneMessageState = <Type>[
  _OneMessageState,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  MultiplayerState,
];

List<ScannableField> _collect$OneMessageGame(Object object) {
  object as _OneMessageGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$OneMessageGame = <Type>[
  _OneMessageGame,
  _NetGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$CollidingState(Object object) {
  final owner = object as _CollidingState;
  return <ScannableField>[
    owner.network,
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

const List<Type> _supertypes$CollidingState = <Type>[
  _CollidingState,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  MultiplayerState,
];

List<ScannableField> _collect$CollidingGame(Object object) {
  object as _CollidingGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$CollidingGame = <Type>[
  _CollidingGame,
  _NetGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$WatchedState(Object object) {
  final owner = object as _WatchedState;
  return <ScannableField>[
    owner.watcher,
    owner.network,
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

const List<Type> _supertypes$WatchedState = <Type>[
  _WatchedState,
  _NetState,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  MultiplayerState,
];

List<ScannableField> _collect$WatchedGame(Object object) {
  object as _WatchedGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$WatchedGame = <Type>[
  _WatchedGame,
  _NetGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$Emote(Object object) {
  object as _Emote;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Emote = <Type>[
  _Emote,
  NetSignal,
  NetMessageBase,
  Scannable,
];

List<ScannableField> _collect$SkewedState(Object object) {
  final owner = object as _SkewedState;
  return <ScannableField>[
    owner.network,
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

const List<Type> _supertypes$SkewedState = <Type>[
  _SkewedState,
  _NetState,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  MultiplayerState,
];

List<ScannableField> _collect$SkewedGame(Object object) {
  object as _SkewedGame;
  return const <ScannableField>[];
}

const List<Type> _supertypes$SkewedGame = <Type>[
  _SkewedGame,
  _NetGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _messageTestDeclarations =
    GeneratedDeclarations(
      package: 'good_net/test/message_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Fire, _collect$Fire, _supertypes$Fire),
        DeclarationCollector(_Score, _collect$Score, _supertypes$Score),
        DeclarationCollector(_Chat, _collect$Chat, _supertypes$Chat),
        DeclarationCollector(_Post, _collect$Post, _supertypes$Post),
        DeclarationCollector(
          _TailKind,
          _collect$TailKind,
          _supertypes$TailKind,
        ),
        DeclarationCollector(
          _InlineKind,
          _collect$InlineKind,
          _supertypes$InlineKind,
        ),
        DeclarationCollector(
          _Snapshot,
          _collect$Snapshot,
          _supertypes$Snapshot,
        ),
        DeclarationCollector(
          _RoundOver,
          _collect$RoundOver,
          _supertypes$RoundOver,
        ),
        DeclarationCollector(_Ready, _collect$Ready, _supertypes$Ready),
        DeclarationCollector(_NetGame, _collect$NetGame, _supertypes$NetGame),
        DeclarationCollector(
          _NetState,
          _collect$NetState,
          _supertypes$NetState,
        ),
        DeclarationCollector(_Watcher, _collect$Watcher, _supertypes$Watcher),
        DeclarationCollector(
          _FireRenamed,
          _collect$FireRenamed,
          _supertypes$FireRenamed,
        ),
        DeclarationCollector(
          _FireByHook,
          _collect$FireByHook,
          _supertypes$FireByHook,
        ),
        DeclarationCollector(
          _OneMessageState,
          _collect$OneMessageState,
          _supertypes$OneMessageState,
        ),
        DeclarationCollector(
          _OneMessageGame,
          _collect$OneMessageGame,
          _supertypes$OneMessageGame,
        ),
        DeclarationCollector(
          _CollidingState,
          _collect$CollidingState,
          _supertypes$CollidingState,
        ),
        DeclarationCollector(
          _CollidingGame,
          _collect$CollidingGame,
          _supertypes$CollidingGame,
        ),
        DeclarationCollector(
          _WatchedState,
          _collect$WatchedState,
          _supertypes$WatchedState,
        ),
        DeclarationCollector(
          _WatchedGame,
          _collect$WatchedGame,
          _supertypes$WatchedGame,
        ),
        DeclarationCollector(_Emote, _collect$Emote, _supertypes$Emote),
        DeclarationCollector(
          _SkewedState,
          _collect$SkewedState,
          _supertypes$SkewedState,
        ),
        DeclarationCollector(
          _SkewedGame,
          _collect$SkewedGame,
          _supertypes$SkewedGame,
        ),
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
