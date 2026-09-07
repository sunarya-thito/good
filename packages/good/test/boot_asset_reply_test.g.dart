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
part of 'boot_asset_reply_test.dart';

List<ScannableField> _collect$SynchronousScene(Object object) {
  final owner = object as _SynchronousScene;
  return <ScannableField>[
    owner.blob,
  ];
}

const List<Type> _supertypes$SynchronousScene = <Type>[
  _SynchronousScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$YieldingScene(Object object) {
  final owner = object as _YieldingScene;
  return <ScannableField>[
    owner.blob,
  ];
}

const List<Type> _supertypes$YieldingScene = <Type>[
  _YieldingScene,
  SceneStruct,
  // Coroutines: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$Reporter(Object object) {
  object as _Reporter;
  return const <ScannableField>[];
}

const List<Type> _supertypes$Reporter = <Type>[
  _Reporter,
  GameSystem,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
  ScannableField,
  FixedTickable,
];

List<ScannableField> _collect$BootLoadState(Object object) {
  final owner = object as _BootLoadState;
  return <ScannableField>[
    owner.reporter,
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

const List<Type> _supertypes$BootLoadState = <Type>[
  _BootLoadState,
  GameState,
  // GameListenerBase: the library this part belongs to does not import it.
  // GameListener: the library this part belongs to does not import it.
  // EventBus: the library this part belongs to does not import it.
  Scannable,
  // Coroutines: the library this part belongs to does not import it.
];

List<ScannableField> _collect$SynchronousGame(Object object) {
  final owner = object as _SynchronousGame;
  return <ScannableField>[
    owner.loaded,
  ];
}

const List<Type> _supertypes$SynchronousGame = <Type>[
  _SynchronousGame,
  _BootLoadGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

List<ScannableField> _collect$YieldingGame(Object object) {
  final owner = object as _YieldingGame;
  return <ScannableField>[
    owner.loaded,
  ];
}

const List<Type> _supertypes$YieldingGame = <Type>[
  _YieldingGame,
  _BootLoadGame,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _bootAssetReplyTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/boot_asset_reply_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(
          _SynchronousScene,
          _collect$SynchronousScene,
          _supertypes$SynchronousScene,
        ),
        DeclarationCollector(
          _YieldingScene,
          _collect$YieldingScene,
          _supertypes$YieldingScene,
        ),
        DeclarationCollector(
          _Reporter,
          _collect$Reporter,
          _supertypes$Reporter,
        ),
        DeclarationCollector(
          _BootLoadState,
          _collect$BootLoadState,
          _supertypes$BootLoadState,
        ),
        DeclarationCollector(
          _SynchronousGame,
          _collect$SynchronousGame,
          _supertypes$SynchronousGame,
        ),
        DeclarationCollector(
          _YieldingGame,
          _collect$YieldingGame,
          _supertypes$YieldingGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_bootAssetReplyTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_bootAssetReplyTestDeclarations],
);
