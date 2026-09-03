import 'package:flutter/widgets.dart' show Curve, Curves;

import 'package:meta/meta.dart';

import 'package:good/src/data.dart';
import 'package:good/src/declare.dart';
import 'package:good/src/game_state.dart';
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
/// Declared with [of] on a [TimelineStruct] field and animated by one or more
/// clips: the same `positionX` track can be driven by an `enter` animation and
/// a `die` animation, and the [TimelineSample] says which one is being asked
/// about. A track with no keys in the clip being sampled reports its declared
/// default, so a clip only has to mention the tracks it actually moves.
final class Track<T> {
  Track._(this.defaultValue, this._lerp);

  /// Declares a track whose value is [defaultValue] wherever no clip keys it,
  /// and returns the handle to keep in a field.
  ///
  /// ```dart
  /// class EnemyTimeline extends TimelineStruct {
  ///   final x = Track.of(0.0);
  ///   final frame = Track.of(0);
  /// }
  /// ```
  ///
  /// [lerp] blends two keyframes. Leave it off for `double`, `int` and
  /// `bool`, which are resolved here, at declare time, once per track - a
  /// per-sample type test would be a branch on the hottest path in the
  /// system. Any other type without a [lerp] becomes a **discrete** track: it
  /// holds each value until the next key, which is right for a sprite index
  /// or an enum and is the honest answer for a type with no arithmetic.
  ///
  /// Declares nothing outside the timeline that holds it, so a
  /// [TimelineStruct] can be constructed anywhere.
  static Track<T> of<T>(T defaultValue, {TimelineLerp<T>? lerp}) =>
      Track<T>._(defaultValue, lerp ?? _defaultLerp<T>());

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
/// **A class, extended once per clip**, and held on a [TimelineStruct] field
/// by [of]:
///
/// ```dart
/// class Breath extends TimelineStruct {
///   final scale = Track.of<double>(1.0);
///   final pulse = TimelineAnimation.of(PulseAnimation.new);
/// }
///
/// class PulseAnimation extends TimelineAnimation<Breath> {
///   @override
///   void describeAnimation(AnimationDescriptor descriptor) {
///     descriptor.track(timeline.scale).key(1.0).key(1.12, Seconds(0.5));
///   }
/// }
/// ```
///
/// The clip keys tracks the *timeline* owns, so its body has to name members
/// of another object - which is why [of] takes a constructor tear-off rather
/// than a closure over the timeline's fields. A field initialiser has no
/// `this`, so `PulseAnimation.new` names no sibling and nothing has to be
/// filled in afterwards.
///
/// [T] is the timeline this clip animates. It is checked when the timeline
/// adopts the clip, so `timeline` below is the concrete type and not a cast
/// the reader has to trust.
abstract class TimelineAnimation<T extends TimelineStruct> {
  /// Declares a clip on the timeline being constructed and hands back the
  /// instance, so the timeline keeps it in a field.
  ///
  /// Takes the constructor, not an instance: `TimelineAnimation.of(Pulse())`
  /// would work too, and reads as though the clip were already attached to
  /// something. It is not - the timeline picks it up in its own constructor,
  /// one line after the field initialiser that made it.
  static C of<C extends TimelineAnimation>(C Function() create) {
    final clip = create();
    DeclarationContext.addClip(clip);
    return clip;
  }

  TimelineStruct? _owner;

  int _clipId = -1;

  /// Position in the declaring timeline's clip list - what a [TimelineSample]
  /// carries, and what a [Track] indexes its keys by.
  int get clipId {
    _requireOwner('clipId');
    return _clipId;
  }

  /// The timeline whose tracks this clip keys - what a [describeAnimation]
  /// body reaches its keys through.
  T get timeline {
    _requireOwner('timeline');
    return _owner! as T;
  }

  /// Keys this clip's tracks. Runs once, when the owning timeline is bound to
  /// a scene, and is the one hook left on this path: a clip's body names
  /// tracks on *another* object, which no field initialiser can do.
  void describeAnimation(AnimationDescriptor descriptor);

  void _requireOwner(String member) {
    if (_owner != null) return;
    throw StateError(
      '$runtimeType.$member was read before any timeline adopted this clip. '
      'A clip is adopted by the TimelineStruct whose field declares it - '
      '`final pulse = TimelineAnimation.of($runtimeType.new);` - so one built '
      'with `$runtimeType()` belongs to no timeline and has no tracks to key.',
    );
  }

  void _adopt(TimelineStruct owner, int clipId) {
    if (_owner != null) {
      throw StateError(
        '$runtimeType is already a clip of ${_owner.runtimeType}. A clip '
        'instance belongs to one timeline - `TimelineAnimation.of` takes a '
        'constructor so that each declaration gets its own, and handing back '
        'an existing clip instead gives two timelines one clip id.',
      );
    }
    if (owner is! T) {
      throw StateError(
        '$runtimeType animates a $T, but was declared on '
        '${owner.runtimeType}. A clip keys the tracks of the timeline it is '
        'declared on, so `class $runtimeType extends '
        'TimelineAnimation<${owner.runtimeType}>` is what belongs on a '
        '${owner.runtimeType} field. A clip declared anywhere other than a '
        'TimelineStruct field lands here too, on whichever timeline is built '
        'next.',
      );
    }
    _owner = owner;
    _clipId = clipId;
  }

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
  TrackAnimator<K> track<K>(Track<K> track) {
    final id = clipId;
    final keys = track._keysFor(id);
    if (keys.isNotEmpty) {
      throw StateError(
        'this track is already keyed in clip $id. One track has one curve '
        'per clip - to blend two shapes, declare two clips and sample both.',
      );
    }
    return TrackAnimator<K>._(this, keys);
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

    var micros = (timeline.state.time + offset).inMicroseconds;
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
    final startedAt = timeline.state.time;
    final length = duration > Seconds.zero ? duration : this.length;
    while (true) {
      final elapsed = timeline.state.time - startedAt;
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

/// Keys one clip's tracks - see [TimelineAnimation.describeAnimation].
///
/// One method, and the tracks it takes belong to the clip's own
/// [TimelineAnimation.timeline]. Passing anything else is a compile error, so
/// a clip cannot key a track it does not animate.
abstract class AnimationDescriptor {
  /// Starts keying [track] in this clip, from time zero.
  TrackAnimator<T> track<T>(Track<T> track);
}

/// A set of tracks and the clips that animate them.
///
/// Declared on an `EntityStruct` field with [of], and shared by every entity
/// of that archetype - exactly like the struct itself. Per-entity progress is
/// one `double` of start time in the entity's own row; see
/// [TimelineAnimation.animate].
///
/// ```dart
/// class EnemyTimeline extends TimelineStruct {
///   final x = Track.of(0.0);
///   final entrance = TimelineAnimation.of(EntranceAnimation.new);
/// }
///
/// class EntranceAnimation extends TimelineAnimation<EnemyTimeline> {
///   @override
///   void describeAnimation(AnimationDescriptor descriptor) {
///     descriptor.track(timeline.x).key(0).key(100, Seconds(1));
///   }
/// }
/// ```
///
/// The tracks are the *timeline's*, and every clip keys the same ones - which
/// is what lets an entity read `timeline.x[at]` without knowing which clip is
/// playing, and what makes a track no clip keys report its declared default.
abstract class TimelineStruct {
  /// Adopts the clips this timeline's field initialisers just declared, in
  /// declaration order.
  ///
  /// A superclass constructor runs after the subclass's field initialisers,
  /// so this is the first line of code after them and the buffer holds
  /// exactly this timeline's clips.
  TimelineStruct() {
    final declared = DeclarationContext.takeClips();
    for (var i = 0; i < declared.length; i++) {
      // Cast rather than a type test: the buffer is written by
      // `TimelineAnimation.of` and nothing else, so anything else in it is a
      // bug in this file and should say so rather than be skipped.
      final clip = declared[i] as TimelineAnimation;
      clip._adopt(this, _clips.length);
      _clips.add(clip);
    }
  }

  /// Declares [timeline] on the prefab being constructed and returns it, so
  /// the prefab keeps the typed handle in its field.
  ///
  /// ```dart
  /// class Enemy extends EntityStruct with Transform2D {
  ///   final timeline = TimelineStruct.of(EnemyTimeline());
  /// }
  /// ```
  ///
  /// Takes an instance and not a constructor: a timeline declares nothing
  /// outside itself - a [Track] is a value and a clip is keyed against tracks
  /// the timeline already holds - so there is no window to build it inside
  /// of. What the declaration buys it is the scene, and therefore the clock
  /// [TimelineAnimation.animate] samples against.
  ///
  /// Throws when no prefab is being constructed.
  static T of<T extends TimelineStruct>(T timeline) {
    DeclarationContext.addDeclared(timeline);
    return timeline;
  }

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
        'being handed to `TimelineStruct.of(...)` on a prefab field; one '
        'constructed by hand has no clock to sample against.',
      );
    }
    return scene.state;
  }

  final List<TimelineAnimation> _clips = <TimelineAnimation>[];

  /// Every clip declared here, in declaration order - which is clip-id order.
  @internal
  List<TimelineAnimation> get clips => _clips;

  /// Keys every clip. Called once, when the owning struct is registered.
  ///
  /// The clips are already here - they were adopted in the constructor. What
  /// this adds is the scene, and therefore the clock, which is why keying
  /// waits for it rather than happening at adoption.
  @internal
  void initializeTimeline(SceneStruct scene) {
    if (_scene != null) return;
    _scene = scene;
    for (var i = 0; i < _clips.length; i++) {
      _clips[i].describeAnimation(_AnimationDescriptor(_clips[i]));
    }
  }
}

/// Picks the blend for [T] **once, at declare time**.
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

final class _AnimationDescriptor implements AnimationDescriptor {
  _AnimationDescriptor(this._clip);

  final TimelineAnimation _clip;

  @override
  TrackAnimator<T> track<T>(Track<T> track) => _clip.track<T>(track);
}
