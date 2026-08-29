/// The SoLoud audio backend for the `good` game engine.
///
/// One type, and it is an implementation of `good`'s `AudioBackend`. A game
/// names it once, in `Game.createAudioBackend`, and then never again: sounds
/// are played through `GameState.audio`, which is `good`'s API and knows
/// nothing about SoLoud.
///
/// It is a package of its own because a native audio engine is a plugin - a
/// platform build on five targets, plus `path_provider` - and a game that
/// ships no sound should not have to compile one.
library;

export 'src/soloud_backend.dart';
