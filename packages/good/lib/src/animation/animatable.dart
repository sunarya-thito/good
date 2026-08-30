import 'package:meta/meta.dart';

import 'package:good/src/animation/struct.dart';
import 'package:good/src/coroutine/coroutine.dart';
import 'package:good/src/time.dart';

/// Timelines, on every `EntityStruct`.
///
/// **Nothing to mix in** - `EntityStruct` has it, the same way it has
/// `Coroutines`. [describeAnimation] defaults to declaring nothing, so a prefab
/// with no timelines costs one empty call at registration and nothing after.
///
/// `on Coroutines` works here where it could not for `Coroutines` itself: an
/// `on` bound is checked against the applying class's superclass, and by the
/// time `EntityStruct` applies this one, `Coroutines` is already in its chain.
/// [startAnimation] is why the bound exists - a pushed animation *is* a
/// coroutine.
///
/// ```dart
/// class Enemy extends EntityStruct with Transform2D, Animations {
///   late final EnemyTimeline timeline;
///   late final DataPointer<double> startedAt;
///
///   @override
///   void describeAnimation(AnimationTypeDescriptor descriptor) {
///     super.describeAnimation(descriptor);
///     timeline = descriptor.has(EnemyTimeline());
///   }
///
///   void enter(Entity self) =>
///       startedAt[self] = simulationState.time.inSeconds;
///
///   void update(Entity self) {
///     final at = timeline.entrance.animate(
///       offset: -Seconds(startedAt[self]),
///     );
///     transformOffsetX[self] = timeline.x[at];
///   }
/// }
/// ```
///
/// # There is no per-entity animation state
///
/// A timeline is a *declaration*, shared by every entity of the archetype
/// exactly as the struct is. What varies per entity is one `double` - when it
/// started - which lives in the entity's own row like any other component
/// field. Everything else is derived from that and the clock by
/// [TimelineAnimation.animate], which allocates nothing.
///
/// The alternative - an animation *instance* per playing entity, ticked by the
/// engine - is what most engines do and what this does not. It would mean a
/// heap object per animating entity, a list to walk, and update
/// order mattering. Sampling has none of those: a system reads the value it
/// wants, when it wants it, and two systems sampling the same track in one tick
/// agree by construction.
mixin Animations on Coroutines {
  /// Declares this struct's timelines. Runs once, at registration.
  ///
  /// Empty by default and not abstract, which is what lets `EntityStruct`
  /// mix this in for everyone: an abstract member here would make every prefab
  /// in every game implement it, including the overwhelming majority that
  /// animate nothing.
  @mustCallSuper
  void describeAnimation(AnimationTypeDescriptor descriptor) {}

  /// Plays [animation] into [bindings], as a coroutine, and completes when it
  /// finishes.
  ///
  /// The **push** half of the API, for the case sampling handles badly: a
  /// one-shot that has to run to completion and then be awaited - an entrance,
  /// a door opening, a cutscene beat - where the caller wants `await` rather
  /// than a flag to check every tick.
  ///
  /// Costs a coroutine and a `TrackBinding` per bound track, so it is for the
  /// occasional event, not the per-entity update loop. Reach for
  /// [TimelineAnimation.animate] there; it costs nothing.
  ///
  /// Runs on the coroutine scheduler, so writes land inside the tick window -
  /// see [Coroutine].
  CoroutineFuture startAnimation(
    TimelineAnimation animation,
    List<TrackBinding> bindings, {
    Seconds duration = Seconds.zero,
    WrapMode wrapMode = WrapMode.clamp,
    bool reverse = false,
  }) => simulationState.coroutines.start(
    animation,
    animation.play(
      bindings,
      duration: duration,
      wrapMode: wrapMode,
      reverse: reverse,
    ),
  );

  /// Stops a single running animation.
  ///
  /// Safe to call if the animation has already finished or been stopped.
  /// Bound tracks retain whatever value the last tick wrote.
  void stopAnimation(CoroutineFuture handle) => handle.stop();

  /// Stops every coroutine currently playing [animation].
  ///
  /// Bound tracks retain whatever value the last tick wrote.
  void stopAnimations(TimelineAnimation animation) =>
      simulationState.coroutines.stopAllOf(animation);
}

/// Declares the timelines a struct owns - see [Animations.describeAnimation].
abstract class AnimationTypeDescriptor {
  /// Declares [struct] and returns it, for the `late final` field to keep
  /// (rule 6).
  T has<T extends TimelineStruct>(T struct);
}
