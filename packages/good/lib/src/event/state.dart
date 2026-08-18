import 'package:flutter/foundation.dart' show ValueListenable;

// --- published cross-isolate state ---------------------------------------

/// A typed, cross-isolate published value: **owned and written by the game
/// isolate, readable on both**, backed by a `TripleBuffer` so a reader always
/// sees a whole, self-consistent snapshot and the writer never blocks.
///
/// # Reading, and who gets told when
///
/// This is a `ValueListenable`, so the Flutter-facing shape works with no
/// adapter at all:
///
/// ```dart
/// ValueListenableBuilder(valueListenable: game.myState, builder: ...)
/// ```
///
/// Both isolates can listen, and the *timing* differs by side, which is
/// inherent rather than incidental:
///
///  * On the **game isolate**, a write notifies that copy's listeners
///    synchronously, inside the same call - the writer is right there.
///  * On the **main isolate**, the copy has no idea a write happened until
///    the game isolate's tick-completed message lands. So its listeners fire
///    on the next tick notification, reconciled *before* `addTickListener`'s
///    own callbacks run - a widget repainting off a tick sees this channel
///    already up to date for the tick it is about to draw, rather than one
///    tick behind.
///
/// # Writing
///
/// `value` has a setter, and the setter is only meaningful on the copy that
/// owns the storage. Writing through the main-isolate copy is a programmer
/// error, not a runtime fallback: it does not own the memory, and the write
/// would be invisible to the simulation. It `assert`s (the assert-not-print
/// rule) and does nothing.
///
/// **Direction is game -> main only.** A main -> game channel is a genuinely
/// different design (the game isolate would have to poll it inside the tick
/// window, and two writers on one `TripleBuffer` is not what that primitive
/// is), and main -> game already has a purpose-built lane in `GameCommand`/
/// the command ring. Deliberately out of scope here.
///
/// # Why the value types are fixed-width and few
///
/// A channel is a fixed number of raw bytes in shared memory, so the same
/// vocabulary the component layout already uses ([StateDescriptor.hasUint8]
/// and friends) is the whole of what a channel can be. There is no
/// caller-supplied codec: an explicit `encode`/`decode` pair per channel was
/// the previous design and it bought nothing that a width does not, while
/// giving every declaration two more ways to be wrong (a codec that writes
/// more bytes than it declared, and a `T` with no meaningful `==` silently
/// firing listeners every tick).
abstract class StateChannel<T> implements ValueListenable<T> {
  /// The most recently published value visible to this copy.
  ///
  /// Never a torn read once bring-up has completed: the declared initial
  /// value is published the moment the channel's backing storage is
  /// allocated, before the first tick and before `start()`'s future
  /// completes, so a reader that beats the first real write sees the initial
  /// value rather than the `TripleBuffer`'s pre-publish state.
  @override
  T get value;

  /// Publishes [newValue]. Legal only on the copy that owns the simulation;
  /// see the class doc.
  ///
  /// Allocation-free: the encode target is a `ByteData` view over native
  /// memory built once at bring-up, not per call.
  set value(T newValue);
}

/// Declares published state - see `Game.describeState`. Same one-pass
/// declarative shape as `SystemDescriptor`/`BufferDescriptor`/
/// `CommandDescriptor`/`SceneDescriptor`, and deliberately the same *width*
/// vocabulary as `DataDescriptor`: a state channel is a fixed-width slot in
/// shared memory exactly as a component field is a fixed-width slice of a
/// row, so it is declared the same way and needs no codec.
///
/// Each method takes the initial value the channel holds from bring-up until
/// something writes to it. It is published as soon as the storage exists -
/// before the first tick and before `start()` completes - so no reader on
/// either copy ever observes an unpublished channel.
abstract class StateDescriptor {
  StateChannel<int> hasUint8([int initial = 0]);
  StateChannel<int> hasInt8([int initial = 0]);
  StateChannel<int> hasUint16([int initial = 0]);
  StateChannel<int> hasInt16([int initial = 0]);
  StateChannel<int> hasUint32([int initial = 0]);
  StateChannel<int> hasInt32([int initial = 0]);
  StateChannel<int> hasUint64([int initial = 0]);
  StateChannel<int> hasInt64([int initial = 0]);
  StateChannel<double> hasFloat32([double initial = 0]);
  StateChannel<double> hasFloat64([double initial = 0]);
  StateChannel<bool> hasBool([bool initial = false]);
}
