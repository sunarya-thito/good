import 'package:flutter/foundation.dart' show ValueListenable;

import 'package:good/src/declare.dart';

// --- published cross-isolate state ---------------------------------------

/// A typed, cross-isolate published value: **written by the game isolate,
/// readable on both**, backed by a `TripleBuffer` so a reader always sees a
/// whole, self-consistent snapshot and the writer never blocks.
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
/// Both isolates can listen, and the *timing* differs by side. That is
/// inherent, not incidental:
///
///  * On the **game isolate**, a write notifies that copy's listeners
///    synchronously, inside the same call - the writer is right there.
///  * On the **main isolate**, the copy has no idea a write happened until
///    the game isolate's tick-completed message lands. So its listeners fire
///    on the next tick notification, reconciled *before* the runtime's own
///    tick listeners run - a widget repainting off a tick sees this channel
///    already up to date for the tick it is about to draw, never one tick
///    behind.
///
/// # Writing
///
/// `value` has a setter, and the setter is only meaningful on the copy that
/// **runs the tick loop**. Writing through the main-isolate copy is a
/// programmer error, not a runtime fallback: a `TripleBuffer` has exactly one
/// writer, and a write from there would be invisible to the simulation. It
/// `assert`s (the assert-not-print rule) and does nothing.
///
/// Owning the storage is a different question from being allowed to write it,
/// and since boot moved to main the two answers differ: in the spawned
/// configuration main allocates and frees the channel's memory and still may
/// not write to it. `GameRuntime.owns` and `GameRuntime.simulates` are the two
/// flags; the setter checks the second.
///
/// **Direction is game -> main only.** A main -> game channel is a genuinely
/// different design (the game isolate would have to poll it inside the tick
/// window, and two writers on one `TripleBuffer` is not what that primitive
/// is), and main -> game already has a purpose-built lane in `GameCommand`/
/// the command ring.
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
  /// value and not the `TripleBuffer`'s pre-publish state.
  @override
  T get value;

  /// Publishes [newValue]. Legal only on the copy that owns the simulation;
  /// see the class doc.
  ///
  /// Allocation-free: the encode target is a `ByteData` view over native
  /// memory built once at bring-up, not per call.
  set value(T newValue);
}

/// The registrar [Channel] declares against - `Game.start` opens one around
/// the game's constructor and every `Channel.*` field initialiser lands in
/// it.
///
/// The same *width* vocabulary as `DataDescriptor`: a state channel is a
/// fixed-width slot in shared memory exactly as a component field is a
/// fixed-width slice of a row, so it is declared the same way and needs no
/// codec.
///
/// Each method takes the initial value the channel holds from bring-up until
/// something writes to it. It is published as soon as the storage exists -
/// before the first tick and before `start()` completes - so no reader on
/// either copy ever observes an unpublished channel.
/// # What this offers, and what it does not
///
/// The byte-and-wider widths `DataDescriptor` has, plus `bool`. What is
/// absent is absent because a channel is **its own** fixed run of bytes in
/// shared memory, not a slice of a packed row:
///
///  * **The sub-byte widths** (`uint1`..`int4`) would each take a whole byte
///    here, since there is no neighbouring field to share one with, so they
///    would buy nothing over [hasUint8] and would only add a second spelling
///    for the same storage. The one case worth its own name is the flag, and
///    that is [hasBool].
///  * **Arrays, packed values and heap objects** have no counterpart. A
///    channel is published whole and compared for equality on every write
///    (see [StateChannel]), which a run of elements and a registry index do
///    not support; a value with an `IntRepresentation` goes in a component
///    column, which is where entity-scoped state belongs anyway.
///  * **`hasEntity`** is deliberately absent, and not for a storage reason: a
///    handle names a row that is recycled, so a channel holding one across
///    ticks would come to name a different entity - the warning
///    `DataDescriptor.hasEntity` carries, with nothing here to bound it.
abstract class StateDescriptor {
  /// See [Channel.uint8].
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

/// Declares a published state channel on the field that holds it:
///
/// ```dart
/// class MyGame extends Game {
///   final score = Channel.int32();
///   final alive = Channel.boolean(true);
/// }
/// ```
///
/// One static per [StateDescriptor] method, minus the `has` that only read as
/// noise once the declaration moved onto the field - the same trade `Field`,
/// `Query`, `Param`, `Event` and `Input.of` made before it. Each takes the
/// same initial value its `has` counterpart does.
///
/// The name is `Channel` and not `State`, which is the obvious first guess:
/// `State` is `package:flutter/material.dart`'s, and every file putting a
/// `GameView` in a layout imports that. This one pairs with [StateChannel],
/// which is the type it hands back.
///
/// # The lane this is
///
/// Published state is the "one scalar value, read by the UI" lane, and it is
/// not any of the three that already exist:
///
///  * component data (lane 1) is per-entity and lives in the pool's pages;
///  * commands and their rings (lane 2) are bulk, and run both ways;
///  * `SendPort` control messages (lane 3) are rare and unordered relative to
///    ticks.
///
/// One value, coherent per tick, with no per-read message and no string-keyed
/// lookup. What comes back is a typed [StateChannel] kept in a field, exactly
/// like `describeStruct`'s `DataPointer`s, a `Query` and `describeBuffers`'
/// `BufferHandle`.
///
/// # A Game, and nothing else
///
/// `Game.start` and `Game.startInline` take a constructor -
/// `Game.start(MyGame.new)` - so the framework builds the game and there is a
/// call for the descriptor to be open around.
///
/// Nothing else may declare a channel: a channel's storage is allocated on
/// **main, before the spawn**, and its identity across the boundary is its
/// index in that one declaration pass. A `GameState` and a `GameSystem` are
/// both built on the game isolate, after that allocation, and a `SceneStruct`
/// is loaded after boot and possibly more than once. Publish scene-derived
/// and system-derived values from the `Game` and write through
/// `state.game.myChannel`.
///
/// # Collect, then resolve
///
/// A channel comes back with no storage, no index and no run behind it,
/// because none of those exist yet - the `Game` this field belongs to is
/// still being constructed, and a `GameRuntime` needs the finished object. It is appended to a list and nothing else happens, which is what
/// makes a declaration unable to fail. `Game.start` numbers the collected
/// channels and binds them to the run a step later, and the storage is
/// allocated a step after that, where it always was.
///
/// # Eager, always
///
/// `late final score = Channel.int32()` compiles and is wrong. The call runs
/// on the first *read*, by which point the descriptor is sealed and the
/// storage allocated, so the channel would have no buffer to publish into and
/// no index for the other isolate to know it by. It does not get that far:
/// `DeclarationContext.channels` throws first, naming the shape.
abstract final class Channel {
  /// See [StateDescriptor.hasUint8].
  static StateChannel<int> uint8([int initial = 0]) =>
      DeclarationContext.channels.hasUint8(initial);

  /// See [StateDescriptor.hasInt8].
  static StateChannel<int> int8([int initial = 0]) =>
      DeclarationContext.channels.hasInt8(initial);

  /// See [StateDescriptor.hasUint16].
  static StateChannel<int> uint16([int initial = 0]) =>
      DeclarationContext.channels.hasUint16(initial);

  /// See [StateDescriptor.hasInt16].
  static StateChannel<int> int16([int initial = 0]) =>
      DeclarationContext.channels.hasInt16(initial);

  /// See [StateDescriptor.hasUint32].
  static StateChannel<int> uint32([int initial = 0]) =>
      DeclarationContext.channels.hasUint32(initial);

  /// See [StateDescriptor.hasInt32].
  static StateChannel<int> int32([int initial = 0]) =>
      DeclarationContext.channels.hasInt32(initial);

  /// See [StateDescriptor.hasUint64].
  static StateChannel<int> uint64([int initial = 0]) =>
      DeclarationContext.channels.hasUint64(initial);

  /// See [StateDescriptor.hasInt64].
  static StateChannel<int> int64([int initial = 0]) =>
      DeclarationContext.channels.hasInt64(initial);

  /// See [StateDescriptor.hasFloat32].
  static StateChannel<double> float32([double initial = 0]) =>
      DeclarationContext.channels.hasFloat32(initial);

  /// See [StateDescriptor.hasFloat64].
  static StateChannel<double> float64([double initial = 0]) =>
      DeclarationContext.channels.hasFloat64(initial);

  /// See [StateDescriptor.hasBool]. Named for the width and not the Dart
  /// type, the way `Field.boolean` is.
  static StateChannel<bool> boolean([bool initial = false]) =>
      DeclarationContext.channels.hasBool(initial);
}
