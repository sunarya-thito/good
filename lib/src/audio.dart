import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as soloud;
import 'package:goo2d/src/component.dart';
import 'package:goo2d/src/lifecycle.dart';
import 'package:goo2d/src/asset.dart';
import 'package:goo2d/src/transform.dart';
import 'package:goo2d/src/ticker.dart';
import 'package:goo2d/src/game.dart';

/// Defines the point of hearing within the 3D spatial audio environment.
///
/// The [AudioListener] component acts as the "ears" of the game. When [AudioSource]
/// components are set to use spatial blending, their relative volume and
/// panning are calculated based on their distance and orientation relative
/// to the [GameObject] that holds this listener.
///
/// Typically, an [AudioListener] is attached to the main camera or the
/// player character. Only one listener should be active at a time for
/// consistent spatial calculations.
///
/// ```dart
/// GameObjectWidget(
///   children: [
///     ComponentWidget(Camera.new),
///     ComponentWidget(AudioListener.new),
///   ],
/// );
/// ```
///
/// See also:
/// * [AudioSource] for the components that emit sound.
class AudioListener extends Component {}

/// Emits audio within the game world with support for 2D and 3D spatialization.
///
/// [AudioSource] is the primary component for playing [GameAudio] clips. It
/// supports standard playback controls (play, pause, stop, loop) as well as
/// dynamic adjustment of volume, pitch, and stereo panning.
///
/// When [spatialBlend] is greater than 0, the source transitions from 2D
/// stereo panning to 3D spatial audio. In 3D mode, the sound's position is
/// calculated relative to the active [AudioListener] in the scene.
///
/// ```dart
/// enum MyAudio with AssetEnum, AudioAssetEnum {
///   explosion;
///   @override
///   AssetSource get source => AssetSource.local('explosion.mp3');
/// }
///
/// class PlayerSound extends Behavior with LifecycleListener {
///   late final AudioSource _explosion;
///
///   @override
///   void onMounted() {
///     _explosion = AudioSource()
///       ..clip = MyAudio.explosion
///       ..volume = 0.8
///       ..spatialBlend = 1.0;
///     addComponent(_explosion);
///   }
///
///   void playExplosion() => _explosion.play();
/// }
/// ```
///
/// See also:
/// * [AudioListener] for the component that hears these sounds.
/// * [GameAudio] for the asset representing the sound data.
class AudioSource extends Behavior implements LifecycleListener, LateTickable {
  /// The audio asset to be played by this source.
  ///
  /// Setting this property determines which sound effect or music track is
  /// emitted by the component. If the clip is changed while the source is
  /// playing, the current playback will continue until stopped or until
  /// [play] is called again with the new clip.
  GameAudio? clip;

  /// Whether the audio should start playing automatically when mounted.
  ///
  /// This property allows for declarative sound triggers, where a sound
  /// starts immediately as soon as its parent GameObject enters the scene.
  /// This is commonly used for environmental loops or character spawn sounds.
  bool playOnAwake = true;

  /// Whether the audio should restart after reaching the end.
  ///
  /// When true, the [clip] will play indefinitely until [stop] is called.
  /// This is ideal for background music and ambient loops. The looping
  /// behavior is handled efficiently by the underlying audio engine.
  bool loop = false;

  /// The master volume level for this source, ranging from 0.0 to 1.0.
  ///
  /// This property controls the loudness of the playback. It is applied
  /// as a multiplier to the original audio data. Changes to this value
  /// take effect immediately for currently playing audio.
  double volume = 1.0;

  /// The playback speed and pitch multiplier (1.0 is normal speed).
  ///
  /// This adjusts both the speed of playback and the resulting pitch.
  /// A value of 2.0 plays twice as fast (one octave higher), while 0.5
  /// plays at half speed (one octave lower).
  double pitch = 1.0;

  /// The stereo pan for 2D audio, ranging from -1.0 (full left) to 1.0 (full right).
  ///
  /// This property is only used when [spatialBlend] is 0.
  double panStereo = 0.0;

  /// The degree to which the sound is affected by 3D spatial calculations.
  ///
  /// A value of 0.0 makes the sound 2D (using [panStereo]), while 1.0 makes
  /// it fully spatialized based on its distance from the [AudioListener].
  double spatialBlend = 1.0;

  soloud.SoundHandle? _handle;

  /// Whether this source is currently emitting sound.
  ///
  /// This property returns true if there is an active voice handle in the
  /// audio engine that is currently valid. It may return false if the
  /// audio has naturally finished playing or was stopped manually.
  bool get isPlaying =>
      _handle != null && soloud.SoLoud.instance.getIsValidVoiceHandle(_handle!);

  @override
  void onMounted() {
    if (playOnAwake && clip != null) {
      play();
    }
  }

  @override
  void onUnmounted() {
    stop();
  }

  /// Begins playback of the assigned [clip].
  ///
  /// This method is used to trigger sound effects or start music tracks. The
  /// [clip] must be fully loaded before calling this method; failure to do so
  /// will trigger an assertion error in debug mode. Any currently playing
  /// audio on this source will be stopped before the new playback begins.
  void play() {
    if (clip == null) return;
    assert(clip!.isLoaded, 'Audio clip must be loaded before calling play()');

    stop();

    // SoLoud.instance.play is typically synchronous in latest versions
    _handle = soloud.SoLoud.instance.play(
      clip!.audioSource,
      volume: volume,
      paused: false,
      looping: loop,
    );

    if (_handle != null) {
      game.audio?.registerHandle(_handle!);
      soloud.SoLoud.instance.setRelativePlaySpeed(_handle!, pitch);
      _update3dParameters();
    }
  }

  /// Pauses the current playback without resetting the playhead.
  ///
  /// Use this when you want to temporarily suspend a sound, such as when the
  /// game is paused, so it can be resumed later from the same position. It
  /// sends a pause command to the underlying audio engine while keeping the
  /// voice handle active.
  void pause() {
    if (_handle != null) {
      soloud.SoLoud.instance.setPause(_handle!, true);
    }
  }

  /// Resumes playback from the current position if it was previously paused.
  ///
  /// This method is the counterpart to [pause], allowing a sound to continue
  /// from where it left off. If the sound was not paused, this method has no
  /// effect.
  void unPause() {
    if (_handle != null) {
      soloud.SoLoud.instance.setPause(_handle!, false);
    }
  }

  /// Immediately terminates playback and releases the voice handle.
  ///
  /// This should be used when a sound is no longer needed or must be stopped
  /// abruptly. Unlike [pause], stopping a sound will free its voice resources
  /// and reset the internal handle to null.
  void stop() {
    if (_handle != null && soloud.SoLoud.instance.isInitialized) {
      if (soloud.SoLoud.instance.getIsValidVoiceHandle(_handle!)) {
        soloud.SoLoud.instance.stop(_handle!);
      }
      game.audio?.unregisterHandle(_handle!);
      _handle = null;
    }
  }

  @override
  void onLateUpdate(double dt) {
    if (isPlaying) {
      _update3dParameters();
    }
  }

  void _update3dParameters() {
    if (_handle == null) return;

    final transform = tryGetComponent<ObjectTransform>();
    if (transform == null) return;

    if (spatialBlend <= 0.0) {
      // 2D Mode
      soloud.SoLoud.instance.setPan(_handle!, panStereo);
      // Reset 3D position to origin so it sounds "center" if somehow it was 3D before
      soloud.SoLoud.instance.set3dSourceParameters(_handle!, 0, 0, 0, 0, 0, 0);
      return;
    }

    // 3D Mode with Relative Positioning
    // Find the listener in this game instance.
    // We check the main camera first, then look for any AudioListener component.
    AudioListener? listener;
    if (game.cameras.isReady) {
      listener = game.cameras.main.gameObject.tryGetComponent<AudioListener>();
    }

    listener ??= game.cameras.allCameras
        .map((c) => c.gameObject.tryGetComponent<AudioListener>())
        .whereType<AudioListener>()
        .firstOrNull;

    if (listener == null) {
      // No listener in this game instance, fallback to "at origin"
      soloud.SoLoud.instance.set3dSourceParameters(_handle!, 0, 0, 0, 0, 0, 0);
      return;
    }

    final listenerTransform = listener.gameObject
        .tryGetComponent<ObjectTransform>();

    // Calculate relative position
    final sourceWorldPos = transform.position;
    final listenerWorldPos = listenerTransform?.position ?? Vector2.zero();

    double dx = sourceWorldPos.x - listenerWorldPos.x;
    double dy = sourceWorldPos.y - listenerWorldPos.y;

    // Rotate relative position by inverse of listener rotation
    final angle = -(listenerTransform?.angle ?? 0.0);
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);

    final rx = dx * cosA - dy * sinA;
    final ry = dx * sinA + dy * cosA;

    // We set velocity to 0 for now as we don't track it explicitly in this simplified version
    soloud.SoLoud.instance.set3dSourceParameters(_handle!, rx, ry, 0, 0, 0, 0);

    // Update other properties if they changed
    soloud.SoLoud.instance.setVolume(_handle!, volume);
    soloud.SoLoud.instance.setRelativePlaySpeed(_handle!, pitch);
  }
}

/// A Flutter widget that plays looping background music on a named channel.
///
/// Place [BackgroundMusic] anywhere in the widget tree inside a [Game]. When
/// [audio] changes, the [transition] policy is applied to blend between tracks.
/// When [channel] changes, the old track is hard-stopped and the new track
/// starts fresh on the new channel.
///
/// Multiple [BackgroundMusic] widgets can coexist using different [channel]
/// values (e.g. `0` for music, `1` for ambient).
///
/// ```dart
/// BackgroundMusic(
///   audio: MyAudio.menuTheme,
///   transition: CrossFadeMusicTransition(duration: 1.5),
///   child: MyGameWidget(),
/// )
/// ```
class BackgroundMusic extends StatefulWidget {
  final GameAudio audio;
  final int channel;
  final Widget? child;
  final MusicTransition transition;

  const BackgroundMusic({
    super.key,
    required this.audio,
    this.channel = 0,
    this.child,
    this.transition = const MusicTransition.noTransition(),
  });

  @override
  State<BackgroundMusic> createState() => _BackgroundMusicState();
}

class _BackgroundMusicState extends State<BackgroundMusic> {
  AudioSystem? _audio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_audio == null) {
      _audio = GameProvider.of(context).audio;
      _audio?.transitionMusic(
        channel: widget.channel,
        newAudio: widget.audio,
        transition: widget.transition,
        owner: this,
      );
    }
  }

  @override
  void didUpdateWidget(covariant BackgroundMusic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel != widget.channel) {
      // Hard cut on old channel, fresh start on new.
      _audio?.releaseMusic(
        channel: oldWidget.channel,
        owner: this,
        transition: const NoMusicTransition(),
      );
      _audio?.transitionMusic(
        channel: widget.channel,
        newAudio: widget.audio,
        transition: widget.transition,
        owner: this,
      );
    } else if (oldWidget.audio != widget.audio) {
      _audio?.transitionMusic(
        channel: widget.channel,
        newAudio: widget.audio,
        transition: widget.transition,
        owner: this,
      );
    }
  }

  @override
  void dispose() {
    _audio?.releaseMusic(
      channel: widget.channel,
      owner: this,
      transition: widget.transition,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}
