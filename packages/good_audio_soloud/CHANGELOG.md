## Unreleased

First release. `SoLoudAudioBackend` implements `good`'s `AudioBackend` over
SoLoud: open a device, upload a clip, start a voice at a volume, change that
volume, stop it, and report the ones the engine finished.

Driven from the game isolate, which means driving flutter_soloud's FFI layer
directly - its public wrapper refuses every call from a non-root isolate. See
the README, and the comment at the top of `lib/src/soloud_backend.dart`, for
what that costs and why `flutter_soloud` is pinned to an exact version.

No looping, no loop points, no fades, no web.

An `AudioBus` reaches this package as a number on `play` and `setVoiceVolume`:
`AudioMixer` multiplies the bus level by the master level and hands over the
product, and SoLoud's `busId` stays 0. The voice budget is counted in `good`
too. `setMaxActiveVoiceCount` is not called and would not do the job - it caps
how many voices SoLoud *mixes* per buffer, not how many may be alive, so a cap
of 4 reads back as 4 and then permits 59 concurrent voices.
