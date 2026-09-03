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
part of 'audio_mixer_test.dart';

List<ScannableField> _collect$MusicScene(Object object) {
  final owner = object as _MusicScene;
  return <ScannableField>[
    owner.theme,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$AlsoMusicScene(Object object) {
  final owner = object as _AlsoMusicScene;
  return <ScannableField>[
    owner.theme,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$EffectScene(Object object) {
  final owner = object as _EffectScene;
  return <ScannableField>[
    owner.hit,
    owner.mountedEvent,
    owner.unmountedEvent,
  ];
}

List<ScannableField> _collect$AudioState(Object object) {
  final owner = object as _AudioState;
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

List<ScannableField> _collect$AudioGame(Object object) {
  object as _AudioGame;
  return const <ScannableField>[];
}

/// Every fixture this library declares, and how to read one.
///
/// It carries the package's own generated table as a
/// dependency, so installing this installs the collectors for
/// the engine classes a fixture is built on as well.
const GeneratedDeclarations _audioMixerTestDeclarations =
    GeneratedDeclarations(
      package: 'good/test/audio_mixer_test.dart',
      collectors: <DeclarationCollector>[
        DeclarationCollector(_MusicScene, _collect$MusicScene),
        DeclarationCollector(_AlsoMusicScene, _collect$AlsoMusicScene),
        DeclarationCollector(_EffectScene, _collect$EffectScene),
        DeclarationCollector(_AudioState, _collect$AudioState),
        DeclarationCollector(_AudioGame, _collect$AudioGame),
      ],
      dependencies: <GeneratedDeclarations>[
        goodDeclarations,
      ],
    );

/// Installs [_audioMixerTestDeclarations].
///
/// Called first thing in this library's `main`. Nothing runs
/// on import in Dart, so a table that is never installed is a
/// table nothing has - and the first registration says so by
/// naming the class it could not collect.
void _installDeclarations() => DeclarationRegistry.installGenerated(
  const <GeneratedDeclarations>[_audioMixerTestDeclarations],
);
