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
part of 'swarm_origin_flash_test.dart';

List<ScannableField> _collect$OriginProbe(Object object) {
  final owner = object as _OriginProbe;
  return <ScannableField>[
    owner._renderables,
  ];
}

const List<Type> _supertypes$OriginProbe = <Type>[
  _OriginProbe,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  Tickable,
];

List<ScannableField> _collect$ProbedState(Object object) {
  final owner = object as _ProbedState;
  return <ScannableField>[
    owner.probe,
    owner.fixedPhaseStart,
    owner.presentPhaseStart,
    owner.critterSystem,
    owner.fixedPhaseEnd,
    owner.renderPhaseStart,
    owner.renderPhaseEnd,
    owner.demoStats,
    owner.worldTransform,
    owner.renderer,
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

const List<Type> _supertypes$ProbedState = <Type>[
  _ProbedState,
  SceneGraphState,
  // DemoState: the library this part belongs to does not import it.
  GameState2D,
  GameState,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  Renderer2DState,
];

List<ScannableField> _collect$ProbedGame(Object object) {
  final owner = object as _ProbedGame;
  return <ScannableField>[
    owner.caseMicros,
    owner.systemMicros,
    owner.bestSystemMicros,
    owner.stepMicros,
    owner.presentMicros,
    owner.advanceMicros,
    owner.intervalMicros,
    owner.renderMicros,
    owner.stepsPerAdvance,
    owner.spawnedCount,
    owner.spritesDrawn,
  ];
}

const List<Type> _supertypes$ProbedGame = <Type>[
  _ProbedGame,
  SceneGraphGame,
  // DemoGame: the library this part belongs to does not import it.
  Game2D,
  Game,
  // RandomOwner: the library this part belongs to does not import it.
  Scannable,
  Renderer2D,
];

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _swarmOriginFlashTestDeclarations =
    GeneratedDeclarations(
      package: 'goo2d/example/test/swarm_origin_flash_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(
          _OriginProbe,
          _collect$OriginProbe,
          _supertypes$OriginProbe,
        ),
        DeclarationCollector(
          _ProbedState,
          _collect$ProbedState,
          _supertypes$ProbedState,
        ),
        DeclarationCollector(
          _ProbedGame,
          _collect$ProbedGame,
          _supertypes$ProbedGame,
        ),
      ],
      dependencies: <GeneratedDeclarations>[
        goo2dDeclarations,
      ],
    );

/// Installs [_swarmOriginFlashTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_swarmOriginFlashTestDeclarations],
);
