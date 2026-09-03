import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ChangeNotifier, ValueListenable, VoidCallback;
import 'package:meta/meta.dart';

// The channel implementations moved here from `game.dart` with the window
// they needed. `GameRuntime` is what a resolved channel holds, and game.dart
// already imports this file - a cycle the analyzer is content with and one
// this library is already in twice over (scene.dart, system.dart).
import 'package:good/src/game.dart';
import 'package:good/src/scannable.dart';
import 'package:good/src/triple_buffer.dart';

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
abstract class StateChannel<T> implements ValueListenable<T>, ScannableField {
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

/// Declares published state - see `Game.describeState`. Same one-pass
/// declarative shape as `SystemDescriptor`/`BufferDescriptor`/
/// `CommandDescriptor`/`SceneDescriptor`, and the same *width* vocabulary as
/// `DataDescriptor`: a state channel is a fixed-width slot in
/// shared memory exactly as a component field is a fixed-width slice of a
/// row, so it is declared the same way and needs no codec.
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
/// # A Game, and nothing else
///
/// Nothing else may declare a channel, and the reason has nothing to do with
/// what is open where - nothing is. It is that a
/// channel's storage is allocated on **main, before the spawn**, and its
/// identity across the boundary is its index in that one declaration pass. A
/// `GameState` and a `GameSystem` are both built on the game isolate, after
/// that allocation, and a `SceneStruct` is loaded after boot and possibly
/// more than once. Publish from the `Game` and write through
/// `state.game.myChannel`, which is what `GameSystem.describeState` was
/// deleted in favour of.
///
/// # Collect, then resolve
///
/// A channel declared here comes back with no storage, no index and no run
/// behind it, because none of those exist yet - the `Game` this field belongs
/// to is still being constructed, and a `GameRuntime` needs the finished
/// object. It is appended to a list and nothing else happens, which is what
/// makes a declaration unable to fail. `Game.start` numbers the collected
/// channels and binds them to the run a step later, and the storage is
/// allocated a step after that, where it always was.
///
/// # Eager, always
///
/// `late final score = Channel.int32()` compiles and is wrong. The call runs
/// on the first *read*, by which point the collect pass has been and gone, so
/// the channel would exist holding no index and no storage, and the first
/// read of it would throw about a game that had not started. `good_tool
/// --declarations` refuses the shape rather than waiting for that.
abstract final class Channel {
  /// See [StateDescriptor.hasUint8].
  static StateChannel<int> uint8([int initial = 0]) =>
      declaredChannels.hasUint8(initial);

  /// See [StateDescriptor.hasInt8].
  static StateChannel<int> int8([int initial = 0]) =>
      declaredChannels.hasInt8(initial);

  /// See [StateDescriptor.hasUint16].
  static StateChannel<int> uint16([int initial = 0]) =>
      declaredChannels.hasUint16(initial);

  /// See [StateDescriptor.hasInt16].
  static StateChannel<int> int16([int initial = 0]) =>
      declaredChannels.hasInt16(initial);

  /// See [StateDescriptor.hasUint32].
  static StateChannel<int> uint32([int initial = 0]) =>
      declaredChannels.hasUint32(initial);

  /// See [StateDescriptor.hasInt32].
  static StateChannel<int> int32([int initial = 0]) =>
      declaredChannels.hasInt32(initial);

  /// See [StateDescriptor.hasUint64].
  static StateChannel<int> uint64([int initial = 0]) =>
      declaredChannels.hasUint64(initial);

  /// See [StateDescriptor.hasInt64].
  static StateChannel<int> int64([int initial = 0]) =>
      declaredChannels.hasInt64(initial);

  /// See [StateDescriptor.hasFloat32].
  static StateChannel<double> float32([double initial = 0]) =>
      declaredChannels.hasFloat32(initial);

  /// See [StateDescriptor.hasFloat64].
  static StateChannel<double> float64([double initial = 0]) =>
      declaredChannels.hasFloat64(initial);

  /// See [StateDescriptor.hasBool]. Named for the width and not the Dart
  /// type, the way `Field.boolean` is.
  static StateChannel<bool> boolean([bool initial = false]) =>
      declaredChannels.hasBool(initial);
}

/// Everything `Game` needs from a state channel without knowing its `T`.
///
/// A non-generic interface, not `_StateChannelBase<Object?>` in the list: the
/// whole point of these operations is that they are type-erased plumbing
/// (allocate, poll, free), and none of them wants to expose or launder the
/// channel's value type.
@internal
abstract class ChannelSlot implements ScannableField {
  int get encodedBytes;

  /// Gives this channel its declaration index and the run its storage belongs
  /// to - the resolve half of the collect-then-resolve split.
  ///
  /// A channel is created by a field initialiser, which runs while the `Game`
  /// that owns it is still being constructed: there is no runtime to bind to
  /// and no list to be numbered in yet. So creation appends and nothing else,
  /// and this is where the two facts arrive. Called once, from
  /// `StateChannelRegistry.resolveInto`, before anything allocates.
  void resolve(GameRuntime runtime, int index);

  /// Simulating copy: allocate the triple buffer and publish the initial
  /// value.
  void allocateAndSeed();

  /// Rebuilds the cached `ByteData` views from the pointers they came from.
  ///
  /// Called once on the spawned copy. The views are built by [_attach] from
  /// `Pointer.asTypedList`, and while the `Pointer` crosses the spawn at the
  /// same address, a typed-data view stored in a field is deep-copied **by
  /// value** - so without this the spawned copy would read and write a
  /// detached Dart heap buffer that the other copy never sees. Verified in
  /// `tool/spawn_inherit_spike.dart`.
  void reattach();

  void pollChanged();

  void release({required bool owned});
}

/// The fixed-width formats a [StateChannel] can carry - the same set
/// `DataDescriptor` offers for component fields, for the same reason: a
/// channel is a fixed number of bytes in shared memory, and a width is all
/// the information needed to read and write it.
enum _ChannelFormat {
  uint8(1),
  int8(1),
  uint16(2),
  int16(2),
  uint32(4),
  int32(4),
  uint64(8),
  int64(8),
  float32(4),
  float64(8),
  boolean(1);

  const _ChannelFormat(this.bytes);

  final int bytes;
}

/// Shared body of every channel: the declaration (index, format, initial
/// value), the cached `ByteData` views over the three slots, the read and
/// write paths, and change notification.
///
/// One class for both isolate roles, not a read-only subclass and a writable
/// one: `StateChannel` has a setter on both sides, and the split is enforced
/// by [owned] and an `assert` (the assert-not-print rule) instead of by the
/// type system. That trade buys one declared type usable from Flutter on the
/// main isolate, which is what `ValueListenable` requires. A write from there
/// is a programmer error, not something a caller should be handed two types to
/// reason about.
abstract class _StateChannelBase<T>
    with ChangeNotifier
    implements StateChannel<T>, ChannelSlot {
  _StateChannelBase({required this.format, required this.initialValue})
    : _lastSeen = initialValue;

  /// Position in the shared declaration order, and what this channel's error
  /// messages name it by.
  ///
  /// Both isolate copies run the same declarations and so number the channels
  /// the same way. Correspondence across the boundary comes from that shared
  /// order; nothing sends this field.
  ///
  /// `-1` until [resolve], which is not a state a caller can observe: a
  /// channel is numbered in `Game._bootMain`, before the storage exists and
  /// so before any read or write can succeed.
  int index = -1;
  final _ChannelFormat format;
  final T initialValue;

  /// The **run** this channel's storage belongs to - held instead of two
  /// booleans, because the two questions it answers (who owns the storage, who
  /// may write) have different answers here.
  ///
  /// Null between the field initialiser that created this channel and
  /// [resolve]. It cannot be `final`, because the object that owns the run
  /// does not exist yet while its own fields are initialising - which is the
  /// whole reason declaration and resolution are two steps here.
  GameRuntime? _runtime;

  @override
  void resolve(GameRuntime runtime, int index) {
    _runtime = runtime;
    this.index = index;
  }

  GameRuntime get _run {
    final runtime = _runtime;
    if (runtime != null) return runtime;
    throw StateError(
      'a state channel was reached before the game that declared it '
      'started. Channel.* hands back a declaration, and it becomes a live '
      'channel when Game.start (or Game.startInline) binds it to a run and '
      'allocates its storage - so `await` the start before reading or '
      'writing one.',
    );
  }

  /// Whether this copy allocated the storage, and so must free it. Main, in
  /// the spawned configuration.
  bool get owned => _run.owns;

  /// Whether this copy may *write*. The simulating one - which after the boot
  /// inversion is a different copy from the one that owns the memory.
  ///
  /// A `TripleBuffer` requires one writer, not a particular isolate, so
  /// allocate-here/write-there is legal; `InputDevice` has always been the
  /// mirror image of it.
  bool get _mayWrite => _run.simulates;

  TripleBuffer? _buffer;

  // Built once, when storage is attached: one ByteData per slot, each
  // exactly encodedBytes long, wrapping that slot's native memory.
  //
  // Two jobs. It keeps both the read and the write path allocation-free -
  // `Pointer.asTypedList` plus `ByteData.sublistView` per access would be
  // two objects per read, 60 times a second, which is exactly what
  // Game._commandScratch already exists to avoid on the command path. And
  // because each view is *exactly* encodedBytes long, a write past the
  // declared width hits the view's own bounds check instead of silently
  // scribbling into whatever native memory follows.
  List<int> _slotAddresses = const <int>[];
  List<ByteData> _slotViews = const <ByteData>[];

  // The last value *this copy* saw, seeded with initialValue because that is
  // provably what the first read returns (it is published the instant storage
  // is allocated). So listeners never fire for the initial value, and never
  // fire on a tick where nothing new was published.
  T _lastSeen;

  @override
  int get encodedBytes => format.bytes;

  /// Reads this channel's value out of [view], which is exactly
  /// [encodedBytes] long.
  T readFrom(ByteData view);

  /// Writes [value] into [view], which is exactly [encodedBytes] long.
  void writeTo(ByteData view, T value);

  void _attach(TripleBuffer buffer) {
    _buffer = buffer;
    final addresses = buffer.slotAddresses;
    _slotAddresses = addresses;
    _slotViews = <ByteData>[
      for (final address in addresses)
        ByteData.sublistView(
          Pointer<Uint8>.fromAddress(address).asTypedList(encodedBytes),
        ),
    ];
  }

  @override
  void reattach() {
    final buffer = _buffer;
    if (buffer != null) _attach(buffer);
  }

  @override
  void allocateAndSeed() {
    assert(owned, 'only the owning copy allocates channel storage');
    _attach(TripleBuffer(encodedBytes));
    // Immediately, not on the first tick: until this lands, latestView() is
    // null and hasPublished is false, and no reader on either copy may
    // observe that state.
    _publish(initialValue);
  }

  /// The cached view for the slot [pointer] names. Three addresses, compared
  /// as ints - no map, no allocation.
  ByteData _viewFor(Pointer<Uint8> pointer) {
    final address = pointer.address;
    for (var i = 0; i < _slotAddresses.length; i++) {
      if (_slotAddresses[i] == address) return _slotViews[i];
    }
    throw StateError(
      'state channel #$index resolved a triple-buffer slot it has no view '
      'for - the channel was attached to different storage than it is being '
      'read through.',
    );
  }

  @override
  T get value {
    final buffer = _buffer;
    if (buffer == null) {
      throw StateError(
        'state channel #$index is declared but not connected on this copy of '
        'Game. Call start() (and await it) first - the simulating copy '
        'allocates the storage and announces its address, and a handle copy '
        'only has a view once that message has landed.',
      );
    }
    final slot = buffer.latestView();
    if (slot == null) {
      // Unreachable in normal operation: allocateAndSeed() publishes the
      // initial value before this channel is announced, so latestView() is
      // non-null from the moment either copy can reach it. Stated loudly
      // rather than papered over with a fallback, because a null here means
      // the seed publish was skipped - a bootstrap bug, not a missing value.
      throw StateError(
        'state channel #$index has storage but nothing published in it. The '
        'declared initial value is published as soon as the storage is '
        'allocated, so this should be unreachable.',
      );
    }
    return readFrom(_viewFor(slot));
  }

  @override
  set value(T newValue) {
    if (!_mayWrite) {
      assert(
        false,
        'state channel #$index was written on the Game copy that does not '
        'simulate. A state channel is written by the copy that runs the tick '
        'loop (the game isolate, or the single copy under '
        'start(inline: true)) and read by both; a write from the handle the '
        'main isolate holds after start() would be invisible to the '
        'simulation. Send a GameCommand instead. See the class doc on '
        'StateChannel.',
      );
      return;
    }
    // The read-only lane promised to answer through its reply and write
    // nothing, and this is a write. The receipt lane is deliberately *not*
    // held to it: publishing on a channel is the answer leg a control command
    // has instead of a reply, which is what `_controlCannotAnswer` tells a
    // caller to reach for. See `HandlerWindow` (#245).
    _run.state?.pool.requireChannelWritable();
    _publish(newValue);
  }

  void _publish(T newValue) {
    final buffer = _buffer;
    if (buffer == null) {
      throw StateError(
        'state channel #$index has no storage yet - written before the Game '
        'has finished booting.',
      );
    }
    // copyFromLatest: false. `true` exists for in-place partial mutation -
    // a writer that touches some fields of last tick's snapshot and leaves
    // the rest (which is how MemoryPool's pages are written). A channel write
    // is the opposite: it hands over a complete new value and writeTo is
    // contracted to write all of it, so copying the previous slot forward
    // first would be a full memcpy of every channel, every tick, whose every
    // byte is then overwritten.
    final slot = buffer.beginWrite(copyFromLatest: false);
    writeTo(_viewFor(slot), newValue);
    buffer.publish();
    // Synchronously, because the writer is right here: this is the game
    // isolate's half of the two-speed notification described on StateChannel.
    // The other copy cannot know anything happened until the tick message
    // lands, and reconciles in pollChanged().
    if (newValue == _lastSeen) return;
    _lastSeen = newValue;
    notifyListeners();
  }

  /// Re-baselines [_lastSeen] the moment anyone starts caring.
  ///
  /// Without this, [pollChanged] would have to decode this channel every
  /// single tick even when nothing listens, purely so that a listener added
  /// later had something honest to compare against - a decode per declared
  /// channel per tick, forever, for nobody (the hot-path rules). Doing it
  /// here instead makes the no-listener case free and gives a late-arriving
  /// listener exactly the same guarantee: it is told about changes that
  /// happen *after* it started listening, never about one that predates it.
  @override
  void addListener(VoidCallback listener) {
    if (_buffer != null) _lastSeen = value;
    super.addListener(listener);
  }

  @override
  void pollChanged() {
    // Two field reads on a channel nobody listens to, which is the
    // overwhelmingly common case. The simulating copy keeps _lastSeen fresh
    // in _publish anyway; this exists for the handle copy, which cannot know
    // a write happened until the tick message lands.
    if (_buffer == null || !hasListeners) return;
    final current = value;
    if (current == _lastSeen) return;
    _lastSeen = current;
    notifyListeners();
  }

  @override
  void release({required bool owned}) {
    if (owned) _buffer?.dispose();
    _buffer = null;
    _slotAddresses = const <int>[];
    _slotViews = const <ByteData>[];
  }
}

/// Every integer width, in one class: the format is a field, so a channel of
/// each width is one object and not one class per width.
final class _IntStateChannel extends _StateChannelBase<int> {
  _IntStateChannel({required super.format, required super.initialValue});

  @override
  int readFrom(ByteData view) => switch (format) {
    _ChannelFormat.uint8 => view.getUint8(0),
    _ChannelFormat.int8 => view.getInt8(0),
    _ChannelFormat.uint16 => view.getUint16(0, Endian.little),
    _ChannelFormat.int16 => view.getInt16(0, Endian.little),
    _ChannelFormat.uint32 => view.getUint32(0, Endian.little),
    _ChannelFormat.int32 => view.getInt32(0, Endian.little),
    _ChannelFormat.uint64 => view.getUint64(0, Endian.little),
    _ => view.getInt64(0, Endian.little),
  };

  @override
  void writeTo(ByteData view, int value) {
    switch (format) {
      case _ChannelFormat.uint8:
        view.setUint8(0, value);
      case _ChannelFormat.int8:
        view.setInt8(0, value);
      case _ChannelFormat.uint16:
        view.setUint16(0, value, Endian.little);
      case _ChannelFormat.int16:
        view.setInt16(0, value, Endian.little);
      case _ChannelFormat.uint32:
        view.setUint32(0, value, Endian.little);
      case _ChannelFormat.int32:
        view.setInt32(0, value, Endian.little);
      case _ChannelFormat.uint64:
        view.setUint64(0, value, Endian.little);
      default:
        view.setInt64(0, value, Endian.little);
    }
  }
}

final class _DoubleStateChannel extends _StateChannelBase<double> {
  _DoubleStateChannel({required super.format, required super.initialValue});

  @override
  double readFrom(ByteData view) => format == _ChannelFormat.float32
      ? view.getFloat32(0, Endian.little)
      : view.getFloat64(0, Endian.little);

  @override
  void writeTo(ByteData view, double value) {
    if (format == _ChannelFormat.float32) {
      view.setFloat32(0, value, Endian.little);
    } else {
      view.setFloat64(0, value, Endian.little);
    }
  }
}

/// One byte, not one bit: a channel is its own allocation, never a field
/// packed into a shared row, so there is nothing to save by sub-byte packing
/// and a whole byte to gain in read/write simplicity.
final class _BoolStateChannel extends _StateChannelBase<bool> {
  _BoolStateChannel({required super.initialValue})
    : super(format: _ChannelFormat.boolean);

  @override
  bool readFrom(ByteData view) => view.getUint8(0) != 0;

  @override
  void writeTo(ByteData view, bool value) => view.setUint8(0, value ? 1 : 0);
}

/// The two halves of `StateDescriptor`, with the one difference between them
/// left open: what becomes of a channel once it has been built.
abstract base class _ChannelDescriptor implements StateDescriptor {
  const _ChannelDescriptor();

  /// [declaredChannels] hands the channel straight back; a
  /// [StateChannelRegistry] records it first.
  StateChannel<T> _declared<T>(StateChannel<T> channel);

  StateChannel<int> _int(_ChannelFormat format, int initial) =>
      _declared(_IntStateChannel(format: format, initialValue: initial));

  StateChannel<double> _float(_ChannelFormat format, double initial) =>
      _declared(_DoubleStateChannel(format: format, initialValue: initial));

  @override
  StateChannel<int> hasUint8([int initial = 0]) =>
      _int(_ChannelFormat.uint8, initial);

  @override
  StateChannel<int> hasInt8([int initial = 0]) =>
      _int(_ChannelFormat.int8, initial);

  @override
  StateChannel<int> hasUint16([int initial = 0]) =>
      _int(_ChannelFormat.uint16, initial);

  @override
  StateChannel<int> hasInt16([int initial = 0]) =>
      _int(_ChannelFormat.int16, initial);

  @override
  StateChannel<int> hasUint32([int initial = 0]) =>
      _int(_ChannelFormat.uint32, initial);

  @override
  StateChannel<int> hasInt32([int initial = 0]) =>
      _int(_ChannelFormat.int32, initial);

  @override
  StateChannel<int> hasUint64([int initial = 0]) =>
      _int(_ChannelFormat.uint64, initial);

  @override
  StateChannel<int> hasInt64([int initial = 0]) =>
      _int(_ChannelFormat.int64, initial);

  @override
  StateChannel<double> hasFloat32([double initial = 0]) =>
      _float(_ChannelFormat.float32, initial);

  @override
  StateChannel<double> hasFloat64([double initial = 0]) =>
      _float(_ChannelFormat.float64, initial);

  @override
  StateChannel<bool> hasBool([bool initial = false]) =>
      _declared(_BoolStateChannel(initialValue: initial));
}

/// The descriptor a `Channel.*` static declares against.
///
/// `const`, holding nothing and reaching nothing: `Channel.int32()` builds a
/// channel with no index, no run and no storage and hands it back, so a field
/// initialiser on a `Game` needs no descriptor open around it. That is the
/// whole difference between this and the window it replaced - there is no
/// stack, so there is no innermost entry for a channel to be attributed to,
/// and a lazily-initialised one cannot land on whichever `Game` happens to be
/// under construction when it finally runs.
///
/// What it costs is that nothing here knows the channel exists. A game's
/// channels reach its run by being read off the constructed instance and
/// handed to [StateChannelRegistry.declare].
const StateDescriptor declaredChannels = _DeclaredChannels();

final class _DeclaredChannels extends _ChannelDescriptor {
  const _DeclaredChannels();

  @override
  StateChannel<T> _declared<T>(StateChannel<T> channel) => channel;
}

/// Collects a game's state channels, from the fields that declare one and
/// from the `describeState` body that does.
///
/// **Collect only.** A channel arrives here with no index, no run and no
/// storage; [resolveInto] numbers the lot afterwards and hands them to the
/// game, and `_bootAllocate` allocates a step after that. That split is not
/// tidiness - a field initialiser runs while the `Game` is still being
/// constructed, so at the moment `Channel.int32()` is called there is no game
/// to be numbered in and no `GameRuntime` to bind to.
///
/// One registry per game, not one per source, because a channel's identity
/// across the isolate boundary is its index in a single order. Fields first
/// and the hook second, which is the order they are handed over in.
@internal
final class StateChannelRegistry extends _ChannelDescriptor {
  final List<ChannelSlot> _collected = <ChannelSlot>[];

  /// The game this registry collected for, from [resolveInto] onwards. Only
  /// a diagnostic reads it - the registry exists before the game does.
  Game? _game;
  bool _sealed = false;

  @override
  StateChannel<T> _declared<T>(StateChannel<T> channel) {
    _checkOpen();
    _collected.add(channel as ChannelSlot);
    return channel;
  }

  /// Records the channels a constructed game's field initialisers produced,
  /// ahead of anything `describeState` goes on to add.
  ///
  /// A declaration that is not a channel is skipped rather than refused: a
  /// column and an event are declarations too, and what they resolve against
  /// is a row layout and an owner's listeners. This registry numbers channels
  /// in one shared order, and says so by taking only what it can number.
  void declare(Iterable<ScannableField> declarations) {
    for (final declaration in declarations) {
      if (declaration is! ChannelSlot) continue;
      _checkOpen();
      _collected.add(declaration);
    }
  }

  /// Numbers every collected channel, binds it to [runtime] and hands it to
  /// [game], in declaration order. Called once, from `Game._bootMain`, after
  /// both declaring sources have spoken and before anything allocates.
  void resolveInto(Game game, GameRuntime runtime) {
    _game = game;
    final channels = game.stateChannels;
    for (var i = 0; i < _collected.length; i++) {
      final channel = _collected[i];
      channel.resolve(runtime, channels.length);
      channels.add(channel);
    }
  }

  void seal() => _sealed = true;

  void _checkOpen() {
    if (!_sealed) return;
    final owner = _game?.runtimeType.toString() ?? 'this game';
    throw StateError(
      'a state channel was declared after $owner\'s boot finished. State '
      'channels are declared once, up front - on a field of the Game, or in '
      'describeState - because their storage is allocated and announced at '
      'bring-up and their index has to match the other isolate copy\'s.',
    );
  }
}
