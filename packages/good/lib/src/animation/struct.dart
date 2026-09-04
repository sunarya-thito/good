import 'package:flutter/widgets.dart' show Curve, Curves;

import 'package:meta/meta.dart';

import 'package:good/src/data.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scannable.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/time.dart';

/// What happens once an animation runs past its own length.
enum WrapMode {
  /// Stay on the last keyframe. The default, and what a one-shot entrance or
  /// death animation wants.
  clamp,

  /// Start again from zero. An idle bob, a spinning coin.
  loop,

  /// Play forwards, then backwards, then forwards. A breathing scale, a
  /// hovering platform - the shape you would otherwise author twice and have
  /// to keep symmetrical by hand.
  pingPong,
}

/// One instant of one animation: which clip, and how far into it.
///
/// **An `extension type` over `int`**, so producing one allocates nothing.
/// That is the whole reason sampling is shaped this way and not as an
/// animation *object* that owns state and gets ticked: a system samples this
/// per entity per frame, which is squarely rule 1 and rule 2 territory. A
/// sample is derived from the clock and thrown away.
///
/// 16 bits of clip id, 48 bits of microseconds - about 8.9 years of animation,
/// which is enough, and 65536 clips per timeline, which is more than enough.
extension type const TimelineSample._(int value) {
  const TimelineSample.pack(int clipId, int micros)
    : value = (clipId << 48) | micros;

  int get clipId => value >> 48;
  int get micros => value & 0xFFFFFFFFFFFF;

  /// How far into the clip this sample sits. Convenience for a caller doing
  /// its own maths; nothing in the sampling path uses it.
  Seconds get elapsed => Seconds.ofMicroseconds(micros);
}

/// How two keyframe values are blended.
///
/// [t] runs 0..1 between [a] and [b], already shaped by the keyframe's curve -
/// so an implementation is a straight linear blend and never has to know what
/// easing was asked for.
typedef TimelineLerp<T> = T Function(T a, T b, double t);

/// A curve of values over time, sampled by [operator[]].
///
/// Declared by the field that holds it and animated by one or more clips: the
/// same `positionX` track can be driven by an `enter` animation and a `die`
/// animation, and the [TimelineSample] says which one is being asked about. A
/// track with no keys in the clip being sampled reports its declared default,
/// so a clip only has to mention the tracks it actually moves.
///
/// ```dart
/// class Breath extends TimelineStruct {
///   final scale = Track.of(1.0);
/// }
/// ```
///
/// A plain [ScannableField] and not a `CompositeDeclaration`: a track
/// reserves no row space and resolves against nothing. It holds a default and
/// a blend, both of them arguments, which is why it could be produced by a
/// field initialiser the moment there was a spelling for one.
final class Track<T> implements ScannableField {
  @internal
  Track(this.defaultValue, this._lerp);

  /// Declares a track whose value is [defaultValue] wherever no clip keys it.
  ///
  /// [lerp] blends two keyframes. Leave it off for `double` and `int`, which
  /// are resolved here, where the field is written, once per track - a
  /// per-sample type test would be rule 11's mistake on the hottest path in
  /// the system. Any other type without a [lerp] becomes a **discrete**
  /// track: it holds each value until the next key, which is right for a
  /// sprite index or an enum and is the honest answer for a type with no
  /// arithmetic.
  static Track<T> of<T>(T defaultValue, {TimelineLerp<T>? lerp}) =>
      Track<T>(defaultValue, lerp ?? _defaultLerp<T>());

  /// What this track reads as outside any clip that animates it, and before
  /// its first keyframe.
  final T defaultValue;

  final TimelineLerp<T>? _lerp;

  /// Keys per clip, indexed by `TimelineSample.clipId`. Grown as clips declare
  /// against this track; a clip that never mentions it leaves an empty list,
  /// which is what makes the default-value fallback free instead of a lookup.
  final List<List<_Key<T>>> _clips = <List<_Key<T>>>[];

  List<_Key<T>> _keysFor(int clipId) {
    while (_clips.length <= clipId) {
      _clips.add(<_Key<T>>[]);
    }
    return _clips[clipId];
  }

  /// The value at [sample].
  ///
  /// A binary search over this clip's keys, then one blend. No allocation, no
  /// per-entity state, and no ordering requirement against anything else -
  /// which is what lets two systems sample the same track in the same tick and
  /// get the same answer.
  T operator [](TimelineSample sample) {
    final clipId = sample.clipId;
    if (clipId >= _clips.length) return defaultValue;
    final keys = _clips[clipId];
    if (keys.isEmpty) return defaultValue;

    final micros = sample.micros;
    if (micros <= keys[0].micros) return keys[0].value;
    final last = keys[keys.length - 1];
    if (micros >= last.micros) return last.value;

    // Binary search for the last key at or before `micros`.
    var low = 0;
    var high = keys.length - 1;
    while (low + 1 < high) {
      final mid = (low + high) >> 1;
      if (keys[mid].micros <= micros) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final from = keys[low];
    final to = keys[high];
    final span = to.micros - from.micros;
    if (span <= 0) return to.value;

    final raw = (micros - from.micros) / span;
    // The curve belongs to the key being moved *towards*, which is what makes
    // `.key(v, d, Curves.easeIn)` read as "ease into v" rather than "ease out
    // of whatever came before".
    final t = to.curve.transform(raw);
    final lerp = _lerp;
    // No lerp means a discrete track: hold the previous value until the next
    // key is reached. Correct for a sprite index or an enum, and the honest
    // fallback for a type with no arithmetic - see `Track.of`.
    if (lerp == null) return from.value;
    return lerp(from.value, to.value, t);
  }

  /// Binds this track to a piece of component data, for the push-style API -
  /// see `Animations.startAnimation`.
  TrackBinding<T> bind(DataBinding<T> binding) =>
      TrackBinding<T>(this, binding);
}

final class _Key<T> {
  _Key(this.micros, this.value, this.curve);

  final int micros;
  final T value;
  final Curve curve;
}

/// A [Track] paired with the data it should be written into.
final class TrackBinding<T> {
  @internal
  TrackBinding(this.track, this.binding);

  final Track<T> track;
  final DataBinding<T> binding;

  /// Writes this track's value at [sample] into the bound data.
  @internal
  void apply(TimelineSample sample) => binding.value = track[sample];
}

/// One animation clip: a set of tracks with keyframes, and a length.
///
/// Declared in [TimelineStruct.describeAnimation] and keyed there:
///
/// ```dart
/// toTheLeft = descriptor.has()
///   ..track(positionX)
///       .key(0)
///       .key(100, Seconds(1.0), Curves.easeIn)
///       .hold(Seconds(2.0))
///       .key(0, Seconds(1.0), Curves.easeOut);
/// ```
final class TimelineAnimation {
  @internal
  TimelineAnimation(this.clipId, this._owner);

  /// Position in the declaring timeline's clip list - what a [TimelineSample]
  /// carries, and what a [Track] indexes its keys by.
  ///
  /// This is why a clip is still declared from a hook where a [Track] is a
  /// field: the id is a position in a list the timeline owns, and it has to
  /// be settled before `..track(x).key(...)` runs, because keying writes
  /// straight into `Track._clips[clipId]`. A field initialiser has no
  /// timeline to take a position in.
  final int clipId;

  final TimelineStruct _owner;

  int _lengthMicros = 0;

  /// How long the clip runs: the furthest keyframe on any of its tracks.
  /// Derived, not declared, so adding a key to one track cannot leave a
  /// separately-stated duration wrong (rule 10).
  Seconds get length => Seconds.ofMicroseconds(_lengthMicros);

  /// Starts keying [track] in this clip, from time zero.
  ///
  /// Called once per track per clip at declare time. Keying the same track
  /// twice in one clip would produce two overlapping key lists with no
  /// defensible blend, so it throws instead of picking one.
  TrackAnimator<T> track<T>(Track<T> track) {
    final keys = track._keysFor(clipId);
    if (keys.isNotEmpty) {
      throw StateError(
        'this track is already keyed in clip $clipId. One track has one curve '
        'per clip - to blend two shapes, declare two clips and sample both.',
      );
    }
    return TrackAnimator<T>._(this, keys);
  }

  void _grewTo(int micros) {
    if (micros > _lengthMicros) _lengthMicros = micros;
  }

  /// The [TimelineSample] for this clip *right now*.
  ///
  /// [offset] is added to the current simulated time, so an entity that
  /// started its animation at `startTime` passes `-startTime[entity]` and gets
  /// its own progress out of a shared clip. That is what keeps a clip a pure
  /// declaration with no per-entity state: the entity stores one double, and
  /// everything else is derived.
  ///
  /// [duration] overrides the clip's natural [length] - the same keys played
  /// faster or slower. Zero (the default) means use the natural length.
  ///
  /// Allocation-free: a `TimelineSample` is an `int` and a [Seconds] is a
  /// `double`.
  TimelineSample animate({
    Seconds offset = Seconds.zero,
    Seconds duration = Seconds.zero,
    WrapMode wrapMode = WrapMode.clamp,
    bool reverse = false,
  }) {
    final lengthMicros = duration > Seconds.zero
        ? duration.inMicroseconds
        : _lengthMicros;
    if (lengthMicros <= 0) return TimelineSample.pack(clipId, 0);

    var micros = (_owner.state.time + offset).inMicroseconds;
    switch (wrapMode) {
      case WrapMode.clamp:
        if (micros < 0) micros = 0;
        if (micros > lengthMicros) micros = lengthMicros;
      case WrapMode.loop:
        micros = micros % lengthMicros;
        if (micros < 0) micros += lengthMicros;
      case WrapMode.pingPong:
        final cycle = lengthMicros * 2;
        var phase = micros % cycle;
        if (phase < 0) phase += cycle;
        micros = phase <= lengthMicros ? phase : cycle - phase;
    }
    if (reverse) micros = lengthMicros - micros;

    // Rescaled onto the clip's own key times, so `duration` genuinely means
    // "play the same keys over this long" rather than "cut them off early".
    if (duration > Seconds.zero &&
        lengthMicros != _lengthMicros &&
        _lengthMicros > 0) {
      micros = (micros * _lengthMicros / lengthMicros).round();
    }
    return TimelineSample.pack(clipId, micros);
  }

  @internal
  Iterable play(
    List<TrackBinding> bindings, {
    required Seconds duration,
    required WrapMode wrapMode,
    required bool reverse,
  }) sync* {
    final startedAt = _owner.state.time;
    final length = duration > Seconds.zero ? duration : this.length;
    while (true) {
      final elapsed = _owner.state.time - startedAt;
      final sample = animate(
        offset: -startedAt,
        duration: duration,
        wrapMode: wrapMode,
        reverse: reverse,
      );
      for (var i = 0; i < bindings.length; i++) {
        bindings[i].apply(sample);
      }
      // A looping or ping-ponging clip has no end to wait for, so this runs
      // until something stops it - which is what the returned handle is for.
      if (wrapMode == WrapMode.clamp && elapsed >= length) return;
      yield null;
    }
  }
}

/// Builds one track's keyframes inside one clip. Chainable.
final class TrackAnimator<T> {
  TrackAnimator._(this._clip, this._keys);

  final TimelineAnimation _clip;
  final List<_Key<T>> _keys;

  int _atMicros = 0;

  /// Reaches [value] [duration] after the previous keyframe, easing along
  /// [curve].
  ///
  /// Durations are **relative**: each call advances the write head, so
  /// `.key(0).key(100, Seconds(1.0)).key(0, Seconds(1.0))` is a two-second
  /// clip. Absolute times would make inserting a keyframe mean renumbering
  /// every one after it.
  ///
  /// The first key is normally placed at zero with the default
  /// [Seconds.zero].
  TrackAnimator<T> key(
    T value, [
    Seconds duration = Seconds.zero,
    Curve curve = Curves.linear,
  ]) {
    if (duration < Seconds.zero) {
      throw ArgumentError.value(
        duration.inSeconds,
        'duration',
        'a keyframe cannot arrive before the one it follows',
      );
    }
    _atMicros += duration.inMicroseconds;
    _keys.add(_Key<T>(_atMicros, value, curve));
    _clip._grewTo(_atMicros);
    return this;
  }

  /// Holds the previous value for [duration] before the next [key].
  ///
  /// Sugar for repeating the last keyframe, and worth having: written by hand
  /// it means naming the same value twice, and the two copies then have to be
  /// kept in step by whoever edits the clip (rule 10).
  TrackAnimator<T> hold(Seconds duration) {
    if (_keys.isEmpty) {
      throw StateError(
        'hold() has nothing to hold - key() a value first, so there is '
        'something for the clip to sit on.',
      );
    }
    return key(_keys[_keys.length - 1].value, duration);
  }
}

/// Declares a timeline's clips - see [TimelineStruct.describeAnimation].
abstract class TimelineAnimationDescriptor {
  TimelineAnimation has();
}

/// A set of tracks and the clips that animate them.
///
/// Declared on an `EntityStruct` through `Animations.describeAnimation`, and
/// shared by every entity of that archetype - exactly like the struct itself.
/// Per-entity progress is one `double` of start time in the entity's own row;
/// see [TimelineAnimation.animate].
abstract class TimelineStruct implements Scannable {
  void describeAnimation(TimelineAnimationDescriptor descriptor);

  SceneStruct? _scene;

  /// The simulation this timeline is sampled against - its clock is what
  /// [TimelineAnimation.animate] reads.
  ///
  /// Resolved through the **scene**, lazily, and that indirection is
  /// load-bearing: `initializeScene` is public precisely so a test or a
  /// headless tool can bring a scene up with no `Game` at all, and declaring a
  /// timeline is as meaningful there as declaring a layout or an asset. Only
  /// *sampling* needs a clock. Reading the state eagerly at declare time broke
  /// every headless fixture in the suite.
  @internal
  GameState get state {
    final scene = _scene;
    if (scene == null) {
      throw StateError(
        '$runtimeType has not been declared yet. A TimelineStruct is bound by '
        'being returned from `descriptor.has(...)` in describeAnimation; one '
        'constructed by hand has no clock to sample against.',
      );
    }
    return scene.state;
  }

  final List<TimelineAnimation> _clips = <TimelineAnimation>[];

  /// Every clip declared here, in declaration order - which is clip-id order.
  @internal
  List<TimelineAnimation> get clips => _clips;

  /// Runs the clip declaration pass. Called once, when the owning struct is
  /// registered.
  ///
  /// There is no track pass to run first: a track is built by the field
  /// initialiser that holds it, so every one of them already exists by the
  /// time this object does. Clips still need this, and cannot be fields for
  /// the reason [TimelineAnimation.clipId] gives - a clip's id is its
  /// position in this timeline's list, and a field initialiser has no
  /// timeline to be positioned in.
  @internal
  void initializeTimeline(SceneStruct scene) {
    if (_scene != null) return;
    _scene = scene;
    describeAnimation(_AnimationDescriptor(this));
  }
}

/// Picks the blend for [T] **once, where the track is written**.
///
/// Dart cannot ask "does T support `+`, `-` and `*`" statically, and asking per
/// sample would be a type test on the hot path. So the three arithmetic types
/// the engine actually stores are resolved here and everything else falls back
/// to discrete - a caller who wants otherwise passes a `lerp`.
TimelineLerp<T>? _defaultLerp<T>() {
  if (T == double) {
    return ((double a, double b, double t) => a + (b - a) * t)
        as TimelineLerp<T>;
  }
  if (T == int) {
    // Rounded rather than truncated: a track from 0 to 10 should read 5 at the
    // halfway point, not 4.
    return ((int a, int b, double t) => a + ((b - a) * t).round())
        as TimelineLerp<T>;
  }
  return null;
}

final class _AnimationDescriptor implements TimelineAnimationDescriptor {
  _AnimationDescriptor(this._owner);

  final TimelineStruct _owner;

  @override
  TimelineAnimation has() {
    final clip = TimelineAnimation(_owner._clips.length, _owner);
    _owner._clips.add(clip);
    return clip;
  }
}
