import 'package:flutter_test/flutter_test.dart';
import 'package:good/good.dart';

// What these are for: a test that only round-trips a number through the
// wrapper - `Seconds(1.5).inSeconds == 1.5` - passes with every conversion
// factor in the file multiplied by anything, because the seconds path never
// touches one. Every assertion here crosses a unit boundary, so a factor that
// is out by a thousand changes the number it reads.
void main() {
  group('a unit crossing', () {
    test('milliseconds in, microseconds out', () {
      expect(Seconds.ofMilliseconds(250).inMicroseconds, 250000);
      expect(Seconds.ofMilliseconds(250).inSeconds, closeTo(0.25, 1e-12));
      expect(
        Seconds.ofMilliseconds(250).inSeconds,
        isNot(closeTo(250, 1e-9)),
        reason: 'a milliseconds value read as seconds is 250, not 0.25',
      );
    });

    test('microseconds in, seconds and milliseconds out', () {
      const step = Seconds.ofMicroseconds(16667);
      expect(step.inSeconds, closeTo(0.016667, 1e-12));
      expect(step.inMilliseconds, 17, reason: '16.667 rounds, not truncates');
      expect(Seconds.ofMicroseconds(1000000).inSeconds, 1.0);
    });

    test('a Duration in, the same microseconds out', () {
      expect(
        Seconds.ofDuration(const Duration(microseconds: 16667)).inMicroseconds,
        16667,
      );
      expect(
        Seconds.ofDuration(const Duration(milliseconds: 100)).inMicroseconds,
        100000,
      );
      expect(
        Seconds.ofDuration(const Duration(minutes: 2)).inSeconds,
        closeTo(120, 1e-9),
        reason: 'a Duration is microseconds, so minutes have to survive it',
      );
    });

    test('out to a Duration, through microseconds and not whole seconds', () {
      expect(
        Seconds(0.25).toDuration(),
        const Duration(microseconds: 250000),
        reason:
            'Duration.inSeconds truncates; a quarter second that came back as '
            'zero would be a rounding path, not a conversion',
      );
      expect(Seconds(1.5).toDuration().inMicroseconds, 1500000);
    });

    test('the three constructors agree on one span', () {
      expect(Seconds(0.25).inMicroseconds, 250000);
      expect(Seconds.ofMilliseconds(250).inMicroseconds, 250000);
      expect(Seconds.ofMicroseconds(250000).inMicroseconds, 250000);
      expect(
        Seconds.ofDuration(const Duration(milliseconds: 250)).inMicroseconds,
        250000,
      );
    });
  });

  group('arithmetic', () {
    test('zero is none of it', () {
      expect(Seconds.zero.inSeconds, 0.0);
      expect(Seconds.zero.inMicroseconds, 0);
    });

    test('adding and subtracting stay in seconds', () {
      expect((Seconds(1.5) + Seconds(0.75)).inSeconds, closeTo(2.25, 1e-12));
      expect((Seconds(1.5) - Seconds(0.75)).inSeconds, closeTo(0.75, 1e-12));
    });

    test('negation flips the sign, which is what offset: is written with', () {
      expect((-Seconds(1.5)).inSeconds, -1.5);
      expect((-Seconds(-1.5)).inSeconds, 1.5);
      expect(-Seconds.zero < Seconds(1e-9), isTrue);
    });

    test('scaling by a number keeps the unit, dividing cancels it', () {
      expect((Seconds(1.5) * 2).inSeconds, closeTo(3.0, 1e-12));
      expect((Seconds(1.5) * 0.5).inSeconds, closeTo(0.75, 1e-12));
      expect(Seconds(3.0) / Seconds(1.5), closeTo(2.0, 1e-12));
    });

    test('the comparisons order spans, and are not all the same one', () {
      expect(Seconds(1.0) < Seconds(2.0), isTrue);
      expect(Seconds(2.0) < Seconds(1.0), isFalse);
      expect(Seconds(1.0) > Seconds(2.0), isFalse);
      expect(Seconds(2.0) > Seconds(1.0), isTrue);
      expect(Seconds(1.0) <= Seconds(1.0), isTrue);
      expect(Seconds(1.0) < Seconds(1.0), isFalse);
      expect(Seconds(1.0) >= Seconds(1.0), isTrue);
      expect(Seconds(1.0) > Seconds(1.0), isFalse);
      expect(-Seconds(1.0) < Seconds.zero, isTrue);
    });
  });

  group('the erasure, pinned because the API rests on it', () {
    test('a Seconds is the very double it wraps', () {
      expect(identical(Seconds(1.5), 1.5), isTrue);
      expect(Seconds(1.5).runtimeType, double);
    });

    test('nothing tells one apart at run time', () {
      // The documented limitation, and the reason a coroutine `yield` is left
      // reading `is num`. A change that made `Seconds` a real class would fail
      // here before it silently changed what the scheduler accepts.
      expect(1.5 is Seconds, isTrue);
      expect(Seconds(1.5) is num, isTrue);
      final Object? held = Seconds(1.5);
      expect(held is double, isTrue);
    });
  });
}
