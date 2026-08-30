/// A span of simulated time, in seconds.
///
/// The unit lives in the type, so a call site says what its number means
/// without anyone opening the signature:
///
/// ```dart
/// ..track(frame).key(0).key(3, Seconds(1.0))
/// ```
///
/// **An `extension type` over `double`**, so one costs nothing: it erases to
/// the very `double` it wraps, `identical(Seconds(1.5), 1.5)` is true, and
/// passing, returning or storing one allocates nothing. That is the whole
/// reason this is not a `Duration`. `Game.fixedTimeStep` can be a `Duration`
/// because it is a constant declared once and read for its microseconds;
/// `GameState.time` is *computed* per read, and `animate(offset:)` is handed a
/// column value per entity per frame, so a class there would be a heap object
/// on the hot path (rule 1).
///
/// There is no `implements` clause, and that is what makes a migration safe in
/// both directions: a bare `1.5` is not a `Seconds`, and a `Seconds` is not a
/// `double`. Neither converts without saying so.
///
/// What it cannot do, all following from the erasure:
///
///  * **Nothing tells one apart at run time.** `1.5 is Seconds` is `true` and
///    `Seconds(1.5).runtimeType` is `double`, so a dynamic channel - a
///    coroutine `yield`, an `Object?` slot - gets no help from this type.
///  * **It cannot declare `toString`**, which Dart refuses on every extension
///    type, so the unit never reaches a printed value or an error message.
///  * **It is not an `Object`.** The supertype is `Object?`, so a `List<Object>`
///    has no room for one.
///
/// Storage is unchanged: everything downstream of this is integer
/// microseconds, and [inMicroseconds] is the conversion.
extension type const Seconds(double inSeconds) {
  /// No time at all - the default wherever a duration is optional.
  static const Seconds zero = Seconds(0);

  /// From whole microseconds, which is what the engine stores.
  const Seconds.ofMicroseconds(int microseconds)
    : inSeconds = microseconds / 1000000.0;

  /// From whole milliseconds, the unit a tuned animation is usually written
  /// in.
  const Seconds.ofMilliseconds(int milliseconds)
    : inSeconds = milliseconds / 1000.0;

  /// From a [Duration], for the declared constants that stay one -
  /// `Game.fixedTimeStep` above all.
  Seconds.ofDuration(Duration duration)
    : inSeconds = duration.inMicroseconds / 1000000.0;

  /// Rounded to whole microseconds. Every keyframe time and every sample
  /// position in the engine is this number.
  int get inMicroseconds => (inSeconds * 1000000.0).round();

  /// Rounded to whole milliseconds.
  int get inMilliseconds => (inSeconds * 1000.0).round();

  /// A `Duration` carrying the same span, for the `dart:async` APIs that take
  /// one. Allocates, so it belongs outside the per-frame path.
  Duration toDuration() => Duration(microseconds: inMicroseconds);

  Seconds operator +(Seconds other) => Seconds(inSeconds + other.inSeconds);

  Seconds operator -(Seconds other) => Seconds(inSeconds - other.inSeconds);

  /// Negation, which is what `animate(offset: -startedAt)` is written with.
  Seconds operator -() => Seconds(-inSeconds);

  /// Scaled by a plain number - half a clip, three times a beat.
  Seconds operator *(num factor) => Seconds(inSeconds * factor);

  /// How many times [other] fits in this, as a plain number. Dividing two
  /// spans cancels the unit, so the result is not a [Seconds].
  double operator /(Seconds other) => inSeconds / other.inSeconds;

  bool operator <(Seconds other) => inSeconds < other.inSeconds;

  bool operator <=(Seconds other) => inSeconds <= other.inSeconds;

  bool operator >(Seconds other) => inSeconds > other.inSeconds;

  bool operator >=(Seconds other) => inSeconds >= other.inSeconds;
}
