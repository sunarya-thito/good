import 'package:good/src/declare.dart';
import 'package:good/src/struct.dart';
import 'package:meta/meta.dart';

/// What a [RandomStream] needs from the `Game` that declared it. Kept as an
/// interface so this file does not import `game.dart`, which imports most of
/// the engine.
@internal
abstract interface class RandomOwner {
  /// Whether this copy owns the simulation - see [RandomStream.nextInt].
  bool get randomDrawAllowed;

  /// The fixed tick the simulation is on, which is what makes a per-entity
  /// draw change from one tick to the next.
  int get randomTick;

  /// Names the copy in the error a forbidden draw throws.
  String get randomOwnerLabel;
}

/// A seeded stream of random numbers that replays identically.
///
/// Declared on a field of the `Game` that owns it, like every other handle in
/// this engine - there are no stream names and nothing to look up:
///
/// ```dart
/// class MyGame extends Game {
///   final loot = RandomStream.of();
///   final terrain = RandomStream.of();
/// }
/// ```
///
/// # Why more than one stream
///
/// Streams are independent, and that is the point, not a convenience.
/// With one shared stream, a system that draws a different number of times
/// than it did yesterday shifts every draw after it, so adding a particle
/// effect changes the loot table. Two things make that happen without anyone
/// touching the drawing code: a system that is disabled mid-run, which the
/// engine now does by itself when one throws, and a scene that loads or
/// unloads a different number of entities.
///
/// Give unrelated consumers their own stream and neither can reach the other.
///
/// # This is not replay
///
/// A seeded stream is one of the things deterministic replay needs, and on its
/// own it delivers none of it. A replay also needs the player's input recorded
/// per tick, the tick each command landed on, and something to say about
/// asset loads finishing at a different moment. Control commands - pause, time
/// scale, visibility - are explicitly unordered against tick-delivered ones
/// (see `SinkCommand.handledOnControl`), so their arrival is not
/// reproducible either. See #63; this issue is the random numbers and nothing
/// more.
final class RandomStream {
  RandomStream._();

  /// Declares one stream, independent of every other one.
  ///
  /// Takes nothing: the field it is assigned to is the identity (the
  /// typed-handle rule), and the seed belongs to the `Game`, which supplies it
  /// once every field has declared.
  ///
  /// # Eager, always
  ///
  /// `late final loot = RandomStream.of()` compiles and is wrong. The call
  /// runs on the first *read*, long after boot handed the collected streams
  /// their numbering, so the stream would have no seed at all. It does not get
  /// that far: `DeclarationContext.randoms` throws first, naming the shape.
  static RandomStream of() => DeclarationContext.randoms.declare();

  /// Null until boot resolves the declaration - see [RandomRegistry].
  RandomOwner? _owner;

  /// Declaration order, which is this stream's identity. Two streams declared
  /// from one seed differ because this is mixed into their starting state.
  /// Negative until resolved.
  int _index = -1;

  int _seed = 0;

  /// Where the stream has got to. Both copies of the `Game` carry one, having
  /// ridden the spawn together, and only the simulating copy ever moves it.
  int _state = 0;

  /// Gives this stream its declaration index and the seed derived for it - the
  /// resolve half of the collect-then-resolve split. Called once, from
  /// [RandomRegistry.resolveInto].
  void _resolve(RandomOwner owner, int index, int seed) {
    _owner = owner;
    _index = index;
    _seed = seed;
    _state = seed;
  }

  RandomOwner get _resolvedOwner {
    final owner = _owner;
    if (owner == null) {
      throw StateError(
        'a RandomStream was used before the game that declared it started. '
        'RandomStream.of() collects the declaration, and the seed and the '
        'numbering are handed out by Game.start - a stream has neither until '
        'then. Await Game.start(MyGame.new) first.',
      );
    }
    return owner;
  }

  /// Puts the stream back where it started.
  ///
  /// For a replay, and for a test that wants two runs to line up. It does not
  /// reseed - the seed is the `Game`'s.
  void reset() {
    _resolvedOwner;
    _state = _seed;
  }

  int _advance() {
    final owner = _resolvedOwner;
    if (!owner.randomDrawAllowed) {
      throw StateError(
        'a RandomStream was drawn from on ${owner.randomOwnerLabel}, which '
        'does not own the simulation. Randomness is simulation state: a draw '
        'here would advance a stream the game isolate knows nothing about, '
        'and the two copies would stop agreeing. Draw from a system, a '
        'coroutine or a command handler - all of which run on the simulating '
        'copy.',
      );
    }
    _state = _mix(_state + _gamma);
    return _state;
  }

  /// A uniform integer in `0 <= value < max`.
  int nextInt(int max) {
    if (max < 1) {
      throw ArgumentError.value(max, 'max', 'must be at least 1');
    }
    return (_advance() >>> 1) % max;
  }

  /// A uniform double in `0.0 <= value < 1.0`, with 53 bits of mantissa.
  double nextDouble() => (_advance() >>> 11) * _doubleUnit;

  /// A coin flip.
  bool nextBool() => _advance() & 1 == 1;

  /// A value for [entity] on this tick, **without advancing the stream**.
  ///
  /// This is the per-entity form, and it is a hash and not a draw for a reason
  /// worth stating: a stream drawn once per entity is sensitive to how
  /// many entities there are and in what order, so loading or unloading a
  /// scene shifts every value after it. A hash of the seed, the stream, the
  /// tick and the entity has no position to shift, so that whole failure mode
  /// cannot arise at all.
  ///
  /// The same entity asked twice on the same tick gets the same answer. On the
  /// next tick it gets a different one.
  int intFor(Entity entity, int max) {
    if (max < 1) {
      throw ArgumentError.value(max, 'max', 'must be at least 1');
    }
    return (_hashFor(entity) >>> 1) % max;
  }

  /// [intFor] as a double in `0.0 <= value < 1.0`.
  double doubleFor(Entity entity) => (_hashFor(entity) >>> 11) * _doubleUnit;

  int _hashFor(Entity entity) {
    final owner = _resolvedOwner;
    if (!owner.randomDrawAllowed) {
      throw StateError(
        'a RandomStream was read for an entity on ${owner.randomOwnerLabel}, '
        'which does not own the simulation - and does not have the tick that '
        'would make the answer mean anything.',
      );
    }
    var h = _seed ^ _mix(_index + _gamma);
    h = _mix(h ^ _mix(owner.randomTick + _gamma));
    return _mix(h ^ _mix(entity.value + _gamma));
  }
}

/// Collects a game's random streams from the fields that declare one.
///
/// **Collect only.** [declare] creates a stream with no index, no seed and no
/// owner and appends it; [resolveInto] numbers the lot afterwards and derives
/// each one's seed. That split is what a field initialiser needs: it runs
/// while the `Game` is still being constructed, so at the moment
/// `RandomStream.of()` is called there is no owner to draw against and
/// `Game.randomSeed` - an overridable getter - cannot be read.
///
/// One registry per game, because a stream's index is mixed into its seed and
/// so is part of the sequence it produces.
@internal
final class RandomRegistry {
  final List<RandomStream> _collected = <RandomStream>[];

  /// How many streams were declared. Diagnostics and tests.
  int get streamCount => _collected.length;

  /// A new stream, independent of every other one, with nothing resolved yet.
  RandomStream declare() {
    final stream = RandomStream._();
    _collected.add(stream);
    return stream;
  }

  /// Numbers every collected stream and derives its seed from [seed], in
  /// declaration order. Called once, from `Game._bootMain`.
  void resolveInto(RandomOwner owner, int seed) {
    for (var i = 0; i < _collected.length; i++) {
      // Mixed rather than added: two streams one apart should not produce
      // sequences one step apart.
      _collected[i]._resolve(owner, i, _mix(seed ^ _mix(i + _gamma)));
    }
  }
}

// --- the algorithm ---------------------------------------------------------
//
// SplitMix64, and it is written out here rather than taken from `dart:math`
// **on purpose**. `Random` gives no guarantee that a seed produces the same
// sequence on a different Dart SDK, so a replay recorded today could stop
// matching after an SDK upgrade with nothing in the game having changed. This
// one is fixed: the constants below are part of the engine's contract, and a
// change to any of them is a breaking change to every recorded replay.
//
// Sixty-four bit arithmetic is safe here because this kernel cannot run on the
// web at all - `dart:ffi` is imported by `archetype.dart`, `data_layout.dart`,
// `game.dart` and two more, so the storage layer requires a native platform.
// Dart's native `int` is 64-bit two's complement and both `*` and `+` wrap,
// which is exactly what this needs.

const int _gamma = 0x9E3779B97F4A7C15;
const double _doubleUnit = 1.0 / (1 << 53);

int _mix(int z) {
  var x = z;
  x = (x ^ (x >>> 30)) * 0xBF58476D1CE4E5B9;
  x = (x ^ (x >>> 27)) * 0x94D049BB133111EB;
  return x ^ (x >>> 31);
}
