import 'dart:math';
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

extension ObjectExtension on Object? {
  T as<T>() => this as T;
  // because "is" is a reserved word, we can't have an "is<T>()" method, so we use "instanceof" instead.
  bool instanceof<T>() => this is T;
  bool isNot<T>() => this is! T;
}

/// Performs a linear interpolation between two values of type [T].
///
/// This function calculates the value at the specified fraction [t] along
/// the line between [a] and [b]. Type [T] must support the addition (+),
/// subtraction (-), and multiplication (*) operators, typically found in
/// types like [double] or [Offset].
///
/// ```dart
/// void example() {
///   final result = lerp(0.0, 10.0, 0.5); // Returns 5.0
///   final offset = lerp(Offset.zero, const Offset(10, 10), 0.2);
/// }
/// ```
///
/// * [a]: The starting value at [t] = 0.
/// * [b]: The ending value at [t] = 1.
/// * [t]: The interpolation fraction, usually between 0.0 and 1.0.
T lerp<T>(T a, T b, double t) {
  // convert a and b to dynamic, assuming they overload the operator
  return ((a as dynamic) + ((b as dynamic) - (a as dynamic)) * t) as T;
}

/// A collection of utility methods for working with lists of enums.
///
/// This extension provides convenient ways to retrieve subsets of enum
/// values based on their declaration order. It is particularly useful for
/// range-based lookups in state machines or categorized asset lists.
extension EnumListExtension<T extends Enum> on List<T> {
  /// Returns a subset of values between [a] and [b], including both ends.
  ///
  /// The range is determined by the [Enum.index] of the provided values.
  /// The order of [a] and [b] does not matter; the method automatically
  /// determines the minimum and maximum indices for the slice.
  ///
  /// * [a]: The first boundary enum.
  /// * [b]: The second boundary enum.
  List<T> betweenInclusive(T a, T b) {
    final indexMin = min(a.index, b.index);
    final indexMax = max(a.index, b.index);
    return sublist(indexMin, indexMax + 1);
  }

  /// Returns a subset of values between [a] and [b], excluding both ends.
  ///
  /// This method is useful for finding intermediate states or values
  /// strictly between two known boundaries. If the values are adjacent or
  /// identical, an empty list is returned.
  ///
  /// * [a]: The first boundary enum.
  /// * [b]: The second boundary enum.
  List<T> betweenExclusive(T a, T b) {
    final indexMin = min(a.index, b.index);
    final indexMax = max(a.index, b.index);
    return sublist(indexMin + 1, indexMax);
  }

  /// Returns a subset of values between [a] and [b] with optional boundaries.
  ///
  /// This is the most flexible range method, allowing you to explicitly
  /// include or exclude either the start or end value. It uses the index
  /// order defined in the enum declaration.
  ///
  /// * [a]: The first boundary enum.
  /// * [b]: The second boundary enum.
  /// * [includeA]: Whether to include the value with the lower index.
  /// * [includeB]: Whether to include the value with the higher index.
  List<T> between(T a, T b, {bool includeA = true, bool includeB = true}) {
    final indexMin = min(a.index, b.index);
    final indexMax = max(a.index, b.index);
    final start = includeA ? indexMin : indexMin + 1;
    final end = includeB ? indexMax + 1 : indexMax;
    return sublist(start, end);
  }
}

/// The result of a smooth damping calculation.
///
/// This container holds both the updated position and the resulting velocity
/// after a damping step. Returning both values allows the caller to persist
/// the velocity across frames, which is required for the algorithm's stability.
///
/// ```dart
/// void example(double current, double target, double velocity) {
///   final result = MathUtils.smoothDamp(current, target, velocity, 0.3, 0.016);
///   final newValue = result.value;
///   final newVelocity = result.velocity;
/// }
/// ```
///
/// See also:
/// * [MathUtils.smoothDamp] for the function that produces this result.
class SmoothDampResult<T> {
  /// The interpolated value for the current frame.
  ///
  /// This value is the position of the damped object at the current time
  /// step. It is calculated to move towards the target without overshooting,
  /// providing a smooth visual transition.
  final T value;

  /// The velocity of the value at the end of the damping step.
  ///
  /// This velocity must be stored and passed back into the next call to
  /// [MathUtils.smoothDamp] to ensure the simulation maintains physical
  /// continuity across frames.
  final T velocity;

  /// Creates a [SmoothDampResult] with the given [value] and [velocity].
  ///
  /// This constructor is typically called only by the [MathUtils]
  /// damping functions to package the calculation results.
  ///
  /// * [value]: The current position/value.
  /// * [velocity]: The current speed/velocity.
  const SmoothDampResult(this.value, this.velocity);
}

/// A suite of mathematical utilities for game development.
///
/// This class provides static methods for common game-related math
/// operations that are not available in the standard Dart math library.
/// It focuses on interpolation, damping, and vector manipulation.
///
/// ```dart
/// void example(double current, double target, double velocity) {
///   final result = MathUtils.smoothDamp(
///     current,
///     target,
///     velocity,
///     0.3,
///     0.016,
///   );
/// }
/// ```
///
/// See also:
/// * [SmoothDampResult] for the data structure returned by damping methods.
class MathUtils {
  /// Smoothly dampens a [double] value towards a target over time.
  ///
  /// This algorithm is similar to Unity's `SmoothDamp`. it provides a
  /// pleasant, spring-like motion that is critically damped, meaning it
  /// reaches the target as quickly as possible without oscillating.
  ///
  /// * [current]: The current value of the simulation.
  /// * [target]: The value we are trying to reach.
  /// * [currentVelocity]: The current velocity, passed back from the previous call.
  /// * [smoothTime]: Approximately the time it will take to reach the target.
  /// * [dt]: The time elapsed since the last frame.
  /// * [maxSpeed]: An optional limit on the maximum damping speed.
  static SmoothDampResult<double> smoothDamp(
    double current,
    double target,
    double currentVelocity,
    double smoothTime,
    double dt, [
    double maxSpeed = double.infinity,
  ]) {
    smoothTime = max(0.0001, smoothTime);
    final omega = 2.0 / smoothTime;
    final x = omega * dt;
    final exp = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x);

    double change = current - target;
    final maxChange = maxSpeed * smoothTime;
    change = change.clamp(-maxChange, maxChange);

    final temp = (currentVelocity + omega * change) * dt;
    final newVelocity = (currentVelocity - omega * temp) * exp;
    double newValue = target + (change + temp) * exp;

    // Prevent overshooting
    if ((target - current > 0) == (newValue > target)) {
      newValue = target;
      return SmoothDampResult(newValue, 0);
    }

    return SmoothDampResult(newValue, newVelocity);
  }

  /// Smoothly dampens an [Vector2] towards a target position over time.
  ///
  /// This is the 2D version of [smoothDamp], applying the algorithm to
  /// both X and Y coordinates simultaneously. It maintains a constant
  /// smooth time regardless of the distance or direction of travel.
  ///
  /// * [current]: The current position offset.
  /// * [target]: The destination offset.
  /// * [currentVelocity]: The current 2D velocity offset.
  /// * [smoothTime]: Approximately the time it will take to reach the target.
  /// * [dt]: The time elapsed since the last frame.
  /// * [maxSpeed]: An optional limit on the maximum damping speed.
  static SmoothDampResult<Vector2> smoothDampVector2(
    Vector2 current,
    Vector2 target,
    Vector2 currentVelocity,
    double smoothTime,
    double dt, [
    double maxSpeed = double.infinity,
  ]) {
    smoothTime = max(0.0001, smoothTime);
    final omega = 2.0 / smoothTime;
    final x = omega * dt;
    final exp = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x);

    Vector2 change = current - target;
    final maxChange = maxSpeed * smoothTime;
    if (change.length > maxChange) {
      change = change / change.length * maxChange;
    }

    final temp = (currentVelocity + change * omega) * dt;
    final newVelocity = (currentVelocity - change * (omega * omega * dt)) * exp;
    final newValue = target + (change + temp) * exp;

    return SmoothDampResult(newValue, newVelocity);
  }
}

extension OffsetExtension on Offset {
  Vector2 get asVector2 => Vector2(dx, dy);
}

extension Vector2Extension on Vector2 {
  Offset get asOffset => Offset(x, y);
}

extension SizeExtension on Size {
  Vector2 get asVector2 => Vector2(width, height);
}
