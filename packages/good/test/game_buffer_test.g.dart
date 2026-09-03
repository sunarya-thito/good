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
part of 'game_buffer_test.dart';

List<ScannableField> _collect$Empty(Object object) {
  final owner = object as _Empty;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$EmptyScene(Object object) {
  final owner = object as _EmptyScene;
  return <ScannableField>[
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$PingSystem(Object object) {
  final owner = object as _PingSystem;
  return <ScannableField>[
    owner.mountEvent,
    owner.unmountEvent,
  ];
}

List<ScannableField> _collect$BufferState(Object object) {
  final owner = object as _BufferState;
  return <ScannableField>[
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

List<ScannableField> _collect$BufferGame(Object object) {
  object as _BufferGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$TwoBufferGame(Object object) {
  object as _TwoBufferGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$TinyBufferGame(Object object) {
  object as _TinyBufferGame;
  return const <ScannableField>[];
}

List<ScannableField> _collect$BareState(Object object) {
  final owner = object as _BareState;
  return <ScannableField>[
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

List<ScannableField> _collect$BareGame(Object object) {
  object as _BareGame;
  return const <ScannableField>[];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _gameBufferTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/game_buffer_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_Empty, _collect$Empty),
        DeclarationCollector(_EmptyScene, _collect$EmptyScene),
        DeclarationCollector(_PingSystem, _collect$PingSystem),
        DeclarationCollector(_BufferState, _collect$BufferState),
        DeclarationCollector(_BufferGame, _collect$BufferGame),
        DeclarationCollector(_TwoBufferGame, _collect$TwoBufferGame),
        DeclarationCollector(_TinyBufferGame, _collect$TinyBufferGame),
        DeclarationCollector(_BareState, _collect$BareState),
        DeclarationCollector(_BareGame, _collect$BareGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_gameBufferTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_gameBufferTestDeclarations],
);
