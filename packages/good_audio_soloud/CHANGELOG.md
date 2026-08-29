## Unreleased

First release. `SoLoudAudioBackend` implements `good`'s `AudioBackend` over
SoLoud: open a device, upload a clip, start a voice, stop it, and report the
ones the engine finished.

Driven from the game isolate, which means driving flutter_soloud's FFI layer
directly - its public wrapper refuses every call from a non-root isolate. See
the README, and the comment at the top of `lib/src/soloud_backend.dart`, for
what that costs and why `flutter_soloud` is pinned to an exact version.

No looping, no loop points, no per-bus levels, no fades, no voice cap, no web.
