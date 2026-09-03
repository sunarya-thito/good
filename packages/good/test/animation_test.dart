import 'package:flutter/widgets.dart' show Curves;
import 'package:flutter_test/flutter_test.dart';
import 'package:good/good.dart';

part 'animation_test.g.dart';

/// The live run under test.
late Game run;

// Timeline animation: declared clips, sampled by an int.
//
// The design being tested is that an animation is a **declaration plus a
// clock**, with no per-entity animation object anywhere. What an entity stores
// is one double - when it started - and `animate(offset: -startedAt)` turns
// that into a `TimelineSample`, which is an int. Everything else is derived.

class _EnemyTimeline extends TimelineStruct {
  late final Track<double> x;
  late final Track<double> y;
  late final Track<int> frame;

  late final TimelineAnimation entrance;
  late final TimelineAnimation blink;

  @override
  void describeTrack(TimelineDescriptor descriptor) {
    x = descriptor.has<double>(0);
    y = descriptor.has<double>(-1);
    frame = descriptor.has<int>(0);
  }

  @override
  void describeAnimation(TimelineAnimationDescriptor descriptor) {
    // 0 -> 100 over one second, hold two, back to 0 over one. Four seconds.
    entrance = descriptor.has()
      ..track(x)
          .key(0.0)
          .key(100.0, Seconds(1.0))
          .hold(Seconds(2.0))
          .key(0.0, Seconds(1.0));
    // A second clip over the *same* struct's tracks. `y` is keyed here and
    // nowhere in `entrance`, which is what the default-value fallback is for.
    blink = descriptor.has()
      ..track(y).key(0.0).key(10.0, Seconds(1.0))
      ..track(frame).key(0).key(3, Seconds(1.0));
  }
}

class _Enemy extends EntityStruct {
  late final _EnemyTimeline timeline;
  final startedAt = Field.float64();
  final px = Field.float64();

  @override
  void describeAnimation(AnimationTypeDescriptor descriptor) {
    super.describeAnimation(descriptor);
    timeline = descriptor.has(_EnemyTimeline());
  }
}

/// A timeline whose clip is declared and never keyed.
class _Bare extends TimelineStruct {
  late final TimelineAnimation empty;

  @override
  void describeTrack(TimelineDescriptor descriptor) {}

  @override
  void describeAnimation(TimelineAnimationDescriptor descriptor) {
    empty = descriptor.has();
  }
}

class _Scene extends SceneStruct {
  late final _Enemy enemy;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    enemy = descriptor.has(_Enemy.new);
  }
}

class _State extends GameState<_Game> {
  @override
  void onMounted() => loadScene(_Scene());
}

class _Game extends Game {
  @override
  int get pageSize => 4096;

  /// 10 Hz, so one `advance` is exactly one step and 0.1s of simulated time -
  /// which makes every expectation below an exact number rather than a
  /// tolerance.
  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 100);

  @override
  GameState createState() => _State();
}

/// A coroutine with no end, so a test can watch something stop it.
Iterable _forever() sync* {
  while (true) {
    yield null;
  }
}

const Duration _step = Duration(milliseconds: 100);

/// Advances [steps] fixed steps, one `advance` each.
///
/// Not `advance(_step * n)`: a single advance is capped at
/// `Game.maxFixedStepsPerAdvance` so that a stalled frame cannot spiral, so
/// asking for ten steps' worth of wall clock in one call runs five and drops
/// the rest. One call per step is also what a real game does.
void _tick(int steps) {
  for (var i = 0; i < steps; i++) {
    run.advance(_step);
  }
}

Future<_Game> _boot() async {
  final game = await Game.startInline(_Game.new);
  addTearDown(() async {
    if (game.isRunning) await game.stop();
  });
  return game;
}

_EnemyTimeline _timeline() => run.state.singleScene<_Scene>().enemy.timeline;

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('declaring', () {
    test('a clip is as long as its furthest keyframe', () async {
      run = await _boot();
      expect(
        _timeline().entrance.length.inSeconds,
        closeTo(4.0, 1e-9),
        reason:
            '0 + 1s rise + 2s hold + 1s fall - derived from the keys '
            'rather than declared beside them, so they cannot disagree',
      );
      expect(_timeline().blink.length.inSeconds, closeTo(1.0, 1e-9));
    });

    test('clips get their own ids, and a sample carries which', () async {
      run = await _boot();
      final timeline = _timeline();
      expect(timeline.entrance.clipId, 0);
      expect(timeline.blink.clipId, 1);

      final sample = TimelineSample.pack(1, 250000);
      expect(sample.clipId, 1);
      expect(sample.micros, 250000);
      expect(sample.elapsed.inSeconds, closeTo(0.25, 1e-9));
    });

    test('a keyframe written in milliseconds lands in microseconds', () async {
      run = await _boot();
      // A key placed with `Seconds.ofMilliseconds(250)` has to sit at 250000
      // microseconds. A seconds round-trip cannot see this: it would pass with
      // the milliseconds factor set to anything, because nothing on that path
      // divides by a thousand.
      final track = Track<double>(0, (a, b, t) => a + (b - a) * t);
      _timeline().blink
          .track(track)
          .key(0.0)
          .key(100.0, Seconds.ofMilliseconds(250));

      expect(track[TimelineSample.pack(1, 250000)], closeTo(100.0, 1e-9));
      expect(
        track[TimelineSample.pack(1, 125000)],
        closeTo(50.0, 1e-9),
        reason: 'halfway in time is halfway in value on a linear track',
      );
      expect(
        track[TimelineSample.pack(1, 250)],
        lessThan(1.0),
        reason:
            '250 microseconds in is a thousandth of the way, which is what '
            'fails if 250 milliseconds were stored as 250 microseconds',
      );
    });

    test('keying one track twice in one clip is refused', () async {
      run = await _boot();
      final timeline = _timeline();
      expect(
        () => timeline.entrance.track(timeline.x),
        throwsStateError,
        reason:
            'two key lists on one track in one clip have no defensible '
            'blend - two shapes means two clips',
      );
    });

    test('a keyframe cannot arrive before the one it follows', () async {
      run = await _boot();
      // Nothing downstream refuses a negative duration - the write head just
      // moves backwards and the key lands at a negative time - so this guard
      // is the only thing between a typo and a clip nothing can sample. The
      // assertion is on the message and the argument name, not on the type:
      // `RangeError` is an `ArgumentError`, so `throwsArgumentError` would
      // pass on a range failure raised somewhere else entirely.
      final track = Track<double>(0, (a, b, t) => a + (b - a) * t);
      expect(
        () => _timeline().blink.track(track).key(0.0, Seconds(-1.0)),
        throwsA(
          isA<ArgumentError>()
              .having(
                (e) => e.message,
                'message',
                'a keyframe cannot arrive before the one it follows',
              )
              .having((e) => e.name, 'name', 'duration')
              .having((e) => e.invalidValue, 'invalidValue', -1.0),
        ),
      );
    });

    test('hold() with nothing to hold is refused', () async {
      run = await _boot();
      final timeline = _timeline();
      expect(
        () => timeline.blink.track(timeline.x).hold(Seconds(1.0)),
        throwsStateError,
      );
    });
  });

  group('sampling', () {
    test('a track reads its keys, interpolated', () async {
      run = await _boot();
      final timeline = _timeline();

      expect(timeline.x[TimelineSample.pack(0, 0)], 0.0);
      expect(
        timeline.x[TimelineSample.pack(0, 500000)],
        closeTo(50.0, 1e-9),
        reason: 'halfway up the first second',
      );
      expect(timeline.x[TimelineSample.pack(0, 1000000)], closeTo(100.0, 1e-9));
      expect(
        timeline.x[TimelineSample.pack(0, 2000000)],
        closeTo(100.0, 1e-9),
        reason: 'inside the hold',
      );
      expect(
        timeline.x[TimelineSample.pack(0, 3500000)],
        closeTo(50.0, 1e-9),
        reason: 'halfway back down',
      );
      expect(
        timeline.x[TimelineSample.pack(0, 9000000)],
        closeTo(0.0, 1e-9),
        reason: 'past the end clamps to the last key',
      );
    });

    test('a track not keyed in the sampled clip reads its default', () async {
      run = await _boot();
      final timeline = _timeline();
      // `y` is keyed in `blink` (clip 1) and never in `entrance` (clip 0).
      expect(
        timeline.y[TimelineSample.pack(0, 500000)],
        -1,
        reason:
            'the declared default, so a clip only has to mention the '
            'tracks it actually moves',
      );
      expect(timeline.y[TimelineSample.pack(1, 500000)], closeTo(5.0, 1e-9));
    });

    test('an int track rounds rather than truncates', () async {
      run = await _boot();
      final timeline = _timeline();
      // 0 -> 3 over a second: at halfway the honest answer is 2 (1.5 rounded),
      // not 1. Truncating would make a 0..1 track never reach 1 until the end.
      expect(timeline.frame[TimelineSample.pack(1, 500000)], 2);
      expect(timeline.frame[TimelineSample.pack(1, 1000000)], 3);
    });

    test('a type with no lerp holds each value until the next key', () async {
      run = await _boot();
      // A discrete track: no arithmetic on String, and no lerp supplied, so
      // it steps rather than guessing. Declared here rather than on the
      // fixture because the fallback is what is under test.
      final track = Track<String>('idle', null);
      final clip = _timeline().blink;
      clip.track(track).key('a').key('b', Seconds(1.0));

      expect(track[TimelineSample.pack(1, 0)], 'a');
      expect(
        track[TimelineSample.pack(1, 999999)],
        'a',
        reason: 'held right up to the next key',
      );
      expect(track[TimelineSample.pack(1, 1000000)], 'b');
    });

    test('the curve belongs to the key being moved towards', () async {
      run = await _boot();
      final timeline = _timeline();
      final eased = Track<double>(0, (a, b, t) => a + (b - a) * t);
      timeline.blink
          .track(eased)
          .key(0.0)
          .key(100.0, Seconds(1.0), Curves.easeIn);

      // easeIn starts slow, so halfway through the *time* is well below
      // halfway through the value.
      expect(eased[TimelineSample.pack(1, 500000)], lessThan(50.0));
    });
  });

  group('animate() against the clock', () {
    test('offset is how one clip serves entities that started apart', () async {
      run = await _boot();
      final timeline = _timeline();
      final state = run.state;

      _tick(10); // t = 1.0s
      expect(state.time.inSeconds, closeTo(1.0, 1e-9));

      // Two entities, started a second apart, sampling the same clip.
      final early = timeline.entrance.animate(offset: -Seconds(0.0));
      final late = timeline.entrance.animate(offset: -Seconds(1.0));
      expect(early.micros, 1000000);
      expect(
        late.micros,
        0,
        reason:
            'the whole reason a clip needs no per-entity state: the '
            'entity stores when it started and the sample is derived',
      );
    });

    test('clamp stops at the end, loop wraps, pingPong comes back', () async {
      run = await _boot();
      final timeline = _timeline();
      _tick(50); // t = 5.0s, past the 4s clip

      expect(
        timeline.entrance.animate().micros,
        4000000,
        reason: 'clamp holds the last frame',
      );
      expect(
        timeline.entrance.animate(wrapMode: WrapMode.loop).micros,
        1000000,
        reason: '5s into a 4s loop is 1s in',
      );
      // pingPong: 5s of an 8s cycle is 3s past the turn, so 4 - 3 = 1... but
      // measured from the fold: phase 5 > 4, so 8 - 5 = 3.
      expect(
        timeline.entrance.animate(wrapMode: WrapMode.pingPong).micros,
        3000000,
      );
    });

    test('reverse plays the same keys backwards', () async {
      run = await _boot();
      final timeline = _timeline();
      _tick(10); // t = 1.0s

      expect(timeline.entrance.animate().micros, 1000000);
      expect(
        timeline.entrance.animate(reverse: true).micros,
        3000000,
        reason: '1s into a 4s clip, reversed, is 3s in',
      );
    });

    test('duration rescales the clip onto its own key times', () async {
      run = await _boot();
      final timeline = _timeline();
      _tick(10); // t = 1.0s

      // The same four seconds of keys played over two. One second in is
      // halfway, which on the original key times is two seconds.
      final sample = timeline.entrance.animate(duration: Seconds(2.0));
      expect(sample.micros, 2000000);
      expect(
        timeline.x[sample],
        closeTo(100.0, 1e-9),
        reason: 'halfway through a 2s playback is the middle of the hold',
      );
    });

    test(
      'a clip with no keys samples at zero rather than dividing by it',
      () async {
        run = await _boot();
        _tick(10);
        // A clip nothing ever keyed has zero length, and `animate` must not
        // divide by it. Built by hand rather than declared on the fixture,
        // because a declared-but-unkeyed clip is exactly the state a
        // half-written timeline is in.
        final bare = _Bare()
          ..initializeTimeline(run.state.singleScene<_Scene>());
        expect(bare.empty.length.inSeconds, 0.0);
        expect(bare.empty.animate().micros, 0);
        expect(
          bare.empty.animate(wrapMode: WrapMode.loop).micros,
          0,
          reason: 'and a modulo by zero would have thrown here',
        );
      },
    );
  });

  group('startAnimation pushes into component data', () {
    test('it writes each tick and completes at the end of the clip', () async {
      run = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final enemy = scene.enemy;
      final entity = run.state.loadedScenes.single.addEntity(enemy);

      final handle = enemy.startAnimation(
        enemy.timeline.entrance,
        <TrackBinding>[enemy.timeline.x.bind(enemy.px.bind(entity))],
      );

      run.advance(_step); // first resume: writes t=0
      expect(enemy.px[entity], closeTo(0.0, 1e-9));

      _tick(5); // half a second in
      expect(
        enemy.px[entity],
        closeTo(50.0, 1e-6),
        reason:
            'the coroutine samples and writes inside the tick window, '
            'so the value lands in the row like any other write',
      );

      expect(handle.isDone, isFalse);
      _tick(40); // well past the four-second clip
      expect(
        handle.isDone,
        isTrue,
        reason:
            'a clamped clip has an end, and the handle is how a caller '
            'waits for it',
      );
      await handle;
    });

    test('a stopped animation stops writing and leaves the last value', () async {
      run = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final enemy = scene.enemy;
      final loaded = run.state.loadedScenes.single;
      final stopped = loaded.addEntity(enemy);
      final control = loaded.addEntity(enemy);

      final handle = enemy.startAnimation(
        enemy.timeline.entrance,
        <TrackBinding>[enemy.timeline.x.bind(enemy.px.bind(stopped))],
      );
      // The same clip on a second entity, never stopped. Without it, "still
      // 50" would be satisfied by a clip that never moved in the first place,
      // and the test could not fail for the reason it claims to.
      final running = enemy.startAnimation(
        enemy.timeline.entrance,
        <TrackBinding>[enemy.timeline.x.bind(enemy.px.bind(control))],
      );

      run.advance(_step); // first resume: writes t=0
      _tick(5); // half a second into a 0 -> 100 ramp
      expect(enemy.px[stopped], closeTo(50.0, 1e-6));
      expect(enemy.px[control], closeTo(50.0, 1e-6));

      enemy.stopAnimation(handle);
      _tick(10); // the ramp finishes and holds at 100

      expect(
        enemy.px[stopped],
        closeTo(50.0, 1e-6),
        reason: 'a stopped animation leaves the bound track holding whatever '
            'the last tick wrote - nothing resets or restores it',
      );
      expect(
        enemy.px[control],
        closeTo(100.0, 1e-6),
        reason: 'and the one still running went on writing, so the value '
            'above really did stay put rather than never having moved',
      );
      expect(handle.isDone, isTrue);
      expect(running.isDone, isFalse, reason: 'stopping one stops only one');

      enemy.stopAnimation(running);
      await Future.wait(<Future<void>>[handle, running]);
    });

    test('stopAnimations stops every coroutine playing that timeline', () async {
      run = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final enemy = scene.enemy;
      final loaded = run.state.loadedScenes.single;
      final e1 = loaded.addEntity(enemy);
      final e2 = loaded.addEntity(enemy);
      final e3 = loaded.addEntity(enemy);

      final h1 = enemy.startAnimation(
        enemy.timeline.entrance,
        <TrackBinding>[enemy.timeline.x.bind(enemy.px.bind(e1))],
        wrapMode: WrapMode.loop,
      );
      final h2 = enemy.startAnimation(
        enemy.timeline.entrance,
        <TrackBinding>[enemy.timeline.x.bind(enemy.px.bind(e2))],
        wrapMode: WrapMode.loop,
      );
      final h3 = enemy.startAnimation(
        enemy.timeline.blink,
        <TrackBinding>[enemy.timeline.y.bind(enemy.px.bind(e3))],
        wrapMode: WrapMode.loop,
      );

      _tick(5);
      expect(h1.isDone, isFalse);
      expect(h2.isDone, isFalse);
      expect(h3.isDone, isFalse);

      // Stop every coroutine playing `entrance`.
      enemy.stopAnimations(enemy.timeline.entrance);
      expect(h1.isDone, isTrue);
      expect(h2.isDone, isTrue);
      expect(h3.isDone, isFalse, reason: 'blink is a different timeline clip and keeps running');

      _tick(10);
      expect(h3.isDone, isFalse);
      enemy.stopAnimation(h3);
      expect(h3.isDone, isTrue);
      await Future.wait(<Future<void>>[h1, h2, h3]);
    });

    test('an animation is owned by its timeline, not by what started it', () async {
      run = await _boot();
      final scene = run.state.singleScene<_Scene>();
      final enemy = scene.enemy;
      final entity = run.state.loadedScenes.single.addEntity(enemy);

      final plain = enemy.startCoroutine(_forever);
      final animation = enemy.startAnimation(
        enemy.timeline.entrance,
        <TrackBinding>[enemy.timeline.x.bind(enemy.px.bind(entity))],
        wrapMode: WrapMode.loop,
      );

      _tick(5);
      expect(plain.isDone, isFalse);
      expect(animation.isDone, isFalse);

      // `stopAllCoroutines` groups by owner, and an animation's owner is the
      // timeline now rather than the struct that started it. That regrouping
      // is the whole reason `stopAnimations` can exist - and it is a change
      // in what this call takes down, so it is pinned here rather than left
      // to be discovered.
      enemy.stopAllCoroutines();
      expect(plain.isDone, isTrue);
      expect(
        animation.isDone,
        isFalse,
        reason: 'the prefab no longer owns the animations it started',
      );

      enemy.stopAnimations(enemy.timeline.entrance);
      expect(animation.isDone, isTrue);
      await Future.wait(<Future<void>>[plain, animation]);
    });
  });
}
