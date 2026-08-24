import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/gestures.dart'
    show PointerCancelEvent, PointerDeviceKind, PointerEvent;
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyUpEvent, PhysicalKeyboardKey;
import 'package:meta/meta.dart';

import 'package:good/src/camera_view.dart';
import 'package:good/src/input/input_key.dart';
import 'package:good/src/triple_buffer.dart';

/// The **raw device state** for one moment: one bit per [InputKey], nothing
/// else.
///
/// This is what crosses the isolate boundary, and it is deliberately *not*
/// the resolved `Input<T>` values. Two reasons, both structural:
///
///  * resolution needs the bindings, and bindings are mutable at runtime
///    (`triggerSkill.binding = ...`) on whichever copy the game logic runs
///    on - shipping resolved values would mean shipping the binding changes
///    back the other way and resolving on the wrong side of the boundary;
///  * the bit block is a fixed 16 bytes no matter how many actions a game
///    declares, so the wire cost of input does not grow with the game.
///
/// # Reading, and why it is a copy
///
/// [attach] **copies** the published block into this object once per fixed
/// tick, at the top of `GameState.runFixedStep`, and every action resolved
/// during that tick reads the copy. That is what makes an input snapshot
/// *coherent* - two systems in one tick cannot disagree about whether a key
/// was down.
///
/// It used to keep the slot `Pointer` and read shared memory directly, which
/// was a real hazard rather than an optimisation. `TripleBuffer` rotates its
/// slots blindly: a reader gets two publishes of grace before the writer comes
/// back around and overwrites the slot it is holding. The writer here is
/// `InputDevice` on the Flutter isolate, publishing on **every change** -
/// including every pointer move, several of which can arrive inside one
/// Flutter frame. Holding a slot for an entire fixed tick against that is
/// asking for a torn read: a key spuriously up for one tick, or a pointer X
/// from one event paired with a Y from the next.
///
/// The copy is 40 bytes - 16 of key bits plus six `float32`s - so the window
/// in which the writer could interfere shrinks from a whole tick to a couple
/// of dozen loads. It also makes the coherence promise above actually
/// *guaranteed*, rather than true only while the margin happens to hold.
///
/// [isDown] is a bounds-free index, a shift and a mask against a plain
/// `Uint8List`: no allocation, no map, nothing per call (the no-allocation,
/// hot-event and no-closure rules). [attach] allocates nothing either - it is
/// an indexed copy, deliberately not `Pointer.asTypedList`, which builds a view
/// object per call.
final class InputState {
  @internal
  InputState();

  /// This tick's key bits, copied from the published slot by [attach].
  final Uint8List _bits = Uint8List(bitBlockBytes);

  /// This tick's pointer block, likewise. A separate array rather than a
  /// `Float32List.view` over [_bits]' buffer: two independent plain-Dart
  /// arrays have no aliasing to reason about and nothing that a deep copy
  /// across `Isolate.spawn` could reattach to the wrong storage.
  final Float32List _floats = Float32List(7);

  /// Whether anything has ever been published - false on a game with no
  /// widget attached, or for the handful of ticks before the first device
  /// event. Every key then reads as up, which is exactly right: nothing is
  /// being held, because there is nothing to hold it with.
  bool _attached = false;

  /// Bytes of key bits: one bit per declared key, rounded up to a whole
  /// 64-bit word so what follows stays naturally aligned. 16 bytes today.
  static final int bitBlockBytes = ((InputKey.count + 63) >> 6) << 3;

  /// Where the pointer block starts - immediately after the key bits.
  ///
  /// Six `float32`s: the pointer in window coordinates, the pointer in the
  /// view's own coordinates, and the view's size. All three are known on the
  /// Flutter isolate at the moment the event arrives, so all three are
  /// *captured* rather than derived - deriving view coordinates on the game
  /// isolate would mean shipping the view's origin as well and doing the
  /// subtraction a `RenderBox` already did.
  ///
  /// World coordinates are deliberately **not** here: they need the active
  /// camera, which is an entity on the game isolate, so they are resolved
  /// there. See `MousePosition`.
  static final int _pointerOffset = bitBlockBytes;

  /// Bytes in the whole block.
  static final int byteLength = bitBlockBytes + 28;

  /// Whether [key] is currently held.
  bool isDown(InputKey key) {
    if (!_attached) return false;
    final id = key.id;
    return _bits[id >> 3] & (1 << (id & 7)) != 0;
  }

  double _float(int index) => _attached ? _floats[index] : 0;

  /// The pointer in window coordinates, origin at the window's top-left.
  double get pointerScreenX => _float(0);
  double get pointerScreenY => _float(1);

  /// The pointer within the `GameView`'s own rect, origin at its top-left.
  /// Independent of where the view sits in the window, which is what makes it
  /// the space a HUD or a hit test should work in.
  double get pointerViewX => _float(2);
  double get pointerViewY => _float(3);

  /// The `GameView`'s size in logical pixels, or zero before it has laid out
  /// (or on a game with no widget at all).
  double get viewWidth => _float(4);
  double get viewHeight => _float(5);

  /// Which `CameraView` the pointer is currently over, as its table address,
  /// or -1 when it is over none - because no `GameView` is showing one, or
  /// because the position was driven by [InputDevice.movePointer] without
  /// naming a view.
  ///
  /// Stored **one-based** - 0 means "no view", 1 means view 0 - so that the
  /// zero-filled block a fresh `calloc` hands back already reads as "over
  /// nothing" rather than as "over the first declared view". Getting that
  /// backwards makes a headless game, and every game before its first pointer
  /// event, silently claim the pointer is over view 0.
  ///
  /// A float purely to reuse this block's existing float section: a view
  /// address is a small integer and is exact in float32 far beyond any
  /// plausible number of views.
  int get pointerView => _float(6).toInt() - 1;

  /// Copies the newest published snapshot into this state. Called exactly
  /// once per fixed tick - see the class doc on why it copies.
  ///
  /// An indexed loop rather than `Pointer.asTypedList` + `setAll`:
  /// `asTypedList` builds a view object per call, which on a per-tick path is a
  /// heap allocation per tick (the no-allocation rule). Forty-odd loads is
  /// cheaper than the object would be, never mind the collection.
  @internal
  void attach(Pointer<Uint8>? slot) {
    if (slot == null) {
      _attached = false;
      return;
    }
    for (var i = 0; i < _bits.length; i++) {
      _bits[i] = slot[i];
    }
    final floats = (slot + _pointerOffset).cast<Float>();
    for (var i = 0; i < _floats.length; i++) {
      _floats[i] = floats[i];
    }
    _attached = true;
  }
}

/// The **write** end of [InputState]: where raw device events become bits.
///
/// # Which isolate this lives on
///
/// The Flutter one, always - the isolate that has an engine attached and can
/// therefore receive a `KeyEvent` at all. That makes input the mirror image
/// of a `StateChannel`: same `TripleBuffer` primitive, roles swapped, main ->
/// game instead of game -> main. The storage is still allocated and freed by
/// the simulating copy (like every other shared allocation in the engine, so
/// there is exactly one owner to reason about at shutdown) and announced to
/// the other copy at bring-up; only the *direction of writing* is reversed,
/// which is a convention between the two ends and not a property of the
/// buffer.
///
/// On the single-copy inline path (`Game.start(inline: true)`, and every web
/// build) one copy owns both ends. That works unchanged: a `TripleBuffer`'s
/// writer may read its own published slot.
///
/// # A game with no widget gets no input
///
/// Nothing here polls the OS. Events arrive because a [GameView] is in the
/// tree and forwards them (`HardwareKeyboard` for keys, a `Listener` for
/// mouse buttons). A headless game - a test, a dedicated server, a `Game`
/// that was started but never shown - therefore sees every key as up
/// forever, and every declared action resolves to its default. **That is
/// correct, not a bug**: there is no keyboard attached to a process nobody
/// is looking at. Such a host that genuinely wants input (a replay, a bot,
/// an integration test) writes it here directly through [press]/[release] -
/// the same single write path the widget uses, not a second one.
///
/// # Publishing rate
///
/// One publish per *change*, not per event: a key held down produces a
/// stream of `KeyRepeatEvent`s and a mouse drag produces a `PointerMoveEvent`
/// per frame, and neither moves a bit. `TripleBuffer`'s documented
/// safety margin (a reader must finish before the writer publishes twice)
/// is comfortable here for the same reason it is on the way out: a human
/// generates key changes milliseconds apart at best, and a reader copies 16
/// bytes.
final class InputDevice {
  @internal
  InputDevice(this._buffer) {
    final addresses = _buffer.slotAddresses;
    _slotAddresses = addresses;
    _slotViews = <Uint8List>[
      for (final address in addresses)
        Pointer<Uint8>.fromAddress(address).asTypedList(InputState.byteLength),
    ];
    // Seed an all-keys-up snapshot immediately, so a reader that ticks before
    // the first real device event sees a published block rather than the
    // TripleBuffer's pre-publish state. It reads the same as "nothing held",
    // but it means the two situations never have to be told apart.
    _publish();
  }

  final TripleBuffer _buffer;

  /// This copy's authoritative picture of what is held. The published slots
  /// are write-only from here; keeping the truth in one plain [Uint8List]
  /// means a publish is a single bulk copy and never a read-modify-write of
  /// shared memory.
  final Uint8List _mirror = Uint8List(InputState.byteLength);

  /// The pointer block of [_mirror], typed. A view over the same bytes rather
  /// than a second buffer, so [_publish] stays one bulk copy of one array -
  /// writing a coordinate here *is* writing the mirror.
  ///
  /// Alignment is satisfied by construction: the block starts at
  /// [InputState.bitBlockBytes], which is rounded up to a whole 64-bit word,
  /// and a `Float32List` needs only 4.
  late final Float32List _mirrorFloats = Float32List.view(
    _mirror.buffer,
    InputState.bitBlockBytes,
    7,
  );

  // One cached view per slot, built once. `Pointer.asTypedList` allocates,
  // so doing it per publish would be a heap object per keystroke - the same
  // reason `_StateChannelBase` caches its slot views.
  List<int> _slotAddresses = const <int>[];
  List<Uint8List> _slotViews = const <Uint8List>[];

  static const List<InputKey> _mouseButtons = <InputKey>[
    InputKey.leftMouseButton,
    InputKey.rightMouseButton,
    InputKey.middleMouseButton,
    InputKey.backMouseButton,
    InputKey.forwardMouseButton,
  ];

  static Map<int, InputKey>? _keyboardByUsage;

  /// Marks [key] held, and publishes if that changed anything.
  void press(InputKey key) {
    if (_setBit(key.id, true)) _publish();
  }

  /// The slot the reading end currently sees, which moves on every publish
  /// and only then.
  ///
  /// Here so a test can observe *whether a write cost a publish*, not just
  /// whether the bytes came out right - the "publish per change, not per
  /// event" rule in this class's doc is a claim about frequency, and nothing
  /// about the resolved values can tell a no-op write apart from one that
  /// happened to land on the same numbers. A counter maintained for the sake
  /// of the test would put a `++` on the write path to prove the write path
  /// stays cheap; this is already there.
  @visibleForTesting
  int get publishedAddress => _buffer.latestView()?.address ?? 0;

  /// Marks [key] released, and publishes if that changed anything.
  void release(InputKey key) {
    if (_setBit(key.id, false)) _publish();
  }

  /// Releases everything at once - every key, every mouse button, every
  /// gamepad bit - and publishes if that changed anything.
  ///
  /// An OS that takes focus away sends no key-up. The last thing this heard
  /// was the press, and a latest-value block goes on saying so forever, so
  /// backgrounding a game with a movement key held leaves the character
  /// walking into a wall until the player thinks to press and release that
  /// key themselves. `GameView` calls this when the app is hidden and when
  /// the last view showing the game goes away, which is the rule
  /// `GamepadCollector.detach` was already following on its own: what was
  /// held down when the view went away is not held down any more, and
  /// leaving those bits set strands whatever they were driving.
  ///
  /// # Nothing is re-asserted when the app comes back
  ///
  /// A key the player genuinely never let go of produces no fresh key-down
  /// on the way back, because the OS never sent the up either - so it reads
  /// released until they lift it and press it again. That is deliberate and
  /// it is the right way round: a false "not held" corrects itself the next
  /// time the key moves, while a false "held" corrects itself never. Knowing
  /// the true state would mean polling the OS for the whole keyboard on
  /// resume, and nothing here polls anything.
  ///
  /// A pad is the exception that needs no special case: it is a physical
  /// device that keeps sending events, so the next one re-sets its own bits.
  ///
  /// # The pointer's position is deliberately untouched
  ///
  /// Where the cursor is is not something anyone is holding down, and zeroing
  /// it would teleport it to the window's top-left corner - a real visible
  /// jump for anything aiming at it, in exchange for nothing.
  void releaseAll() {
    var changed = false;
    for (var i = 0; i < InputState.bitBlockBytes; i++) {
      if (_mirror[i] == 0) continue;
      _mirror[i] = 0;
      changed = true;
    }
    if (changed) _publish();
  }

  /// Whether [key] is held according to *this* copy's picture. The same
  /// answer `InputState.isDown` gives on the reading side one tick later;
  /// here so a caller writing synthetic input can check its own bookkeeping
  /// without reaching into shared memory.
  bool isDown(InputKey key) => _mirror[key.id >> 3] & (1 << (key.id & 7)) != 0;

  /// Translates one Flutter key event. Returns false unconditionally, i.e.
  /// "not handled": the engine *observes* the keyboard, it does not consume
  /// it, so a text field or a `Shortcuts` widget in the same tree keeps
  /// working while a game is running.
  @internal
  bool handleKeyEvent(KeyEvent event) {
    final key = _keyboardFor(event.physicalKey);
    // A key nobody can bind (a media key, a browser back key) is not an
    // error - there is simply no bit for it.
    if (key == null) return false;
    if (event is KeyDownEvent) {
      press(key);
    } else if (event is KeyUpEvent) {
      release(key);
    }
    // KeyRepeatEvent deliberately falls through: the key is already down and
    // repeat is a text-entry concept, not a held-state change.
    return false;
  }

  /// Translates one Flutter pointer event's *button mask*.
  ///
  /// The whole mouse's state comes off `PointerEvent.buttons` in one go
  /// rather than being inferred from which event class arrived, because
  /// Flutter reports a second button pressed mid-drag as a move with a wider
  /// mask, not as a second down event. Reading the mask covers every case
  /// with one code path.
  ///
  /// Touch and stylus are ignored: mouse *buttons* are in scope here and a
  /// finger is not one. A tap-as-click mapping is a real decision to make
  /// alongside pointer position, and belongs with it.
  @internal
  void handlePointerEvent(PointerEvent event, {int viewAddress = -1}) {
    if (event.kind != PointerDeviceKind.mouse) return;
    // A cancel means the gesture was taken away, not that the user let go
    // somewhere we can see - treat every button as released.
    final buttons = event is PointerCancelEvent ? 0 : event.buttons;
    var changed = false;
    for (var i = 0; i < _mouseButtons.length; i++) {
      final key = _mouseButtons[i] as MouseButtonKey;
      if (_setBit(key.id, buttons & key.buttonMask != 0)) changed = true;
    }
    // `localPosition` is already relative to the widget the `Listener` wraps,
    // so the view-space figure costs nothing to capture here and would cost
    // the view's window origin to reconstruct on the other side.
    if (_setPointer(
      event.position.dx,
      event.position.dy,
      event.localPosition.dx,
      event.localPosition.dy,
      viewAddress,
    )) {
      changed = true;
    }
    if (changed) _publish();
  }

  /// Sets one gamepad button on one player slot, and publishes if that
  /// changed anything.
  ///
  /// Also maintains slot 0, which is not a seat but the **OR** of every real
  /// slot - that is what makes a binding to `.padA` mean "the A button on
  /// whichever pad someone picked up", so a single-player game needs no
  /// controller setup at all. Recomputed from the other slots' bits rather
  /// than counted, so a slot cleared by `GamepadCollector.releaseSlot`
  /// correctly stops holding it down.
  ///
  /// [slot] is 1-based here: writing to slot 0 directly would fight the OR
  /// on the next real event.
  void setGamepadButton(int slot, GamepadButton button, bool down) {
    assert(
      slot >= 1 && slot < GamepadKey.slotCount,
      'slot 0 is the "any pad" aggregate and is derived, not written - pass '
      'the seat the pad actually holds (1..${GamepadKey.slotCount - 1}), not '
      '$slot',
    );
    final base = GamepadKey.firstId + button.index;
    var changed = _setBit(base + slot * GamepadKey.buttonCount, down);
    var any = false;
    for (var i = 1; i < GamepadKey.slotCount; i++) {
      if (_isBitSet(base + i * GamepadKey.buttonCount)) {
        any = true;
        break;
      }
    }
    if (_setBit(base, any)) changed = true;
    if (changed) _publish();
  }

  bool _isBitSet(int id) => _mirror[id >> 3] & (1 << (id & 7)) != 0;

  /// Moves the pointer, and publishes if that changed anything.
  ///
  /// The [press]/[release] of positions: the same single write path
  /// [handlePointerEvent] uses, exposed so a host with no widget (a replay, a
  /// bot, a test) can drive the cursor without having to fabricate a Flutter
  /// `PointerEvent` - which would mean knowing about device kinds and button
  /// masks to move a mouse one pixel.
  ///
  /// [viewX]/[viewY] default to the screen coordinates, which is exactly right
  /// when the view fills the window and is the only sensible answer when there
  /// is no view at all. Pass them when the distinction matters.
  void movePointer({
    required double screenX,
    required double screenY,
    double? viewX,
    double? viewY,
    CameraView? view,
  }) {
    if (_setPointer(
      screenX,
      screenY,
      viewX ?? screenX,
      viewY ?? screenY,
      view?.pack() ?? -1,
    )) {
      _publish();
    }
  }

  /// Records the `GameView`'s current size, so the game isolate can resolve a
  /// pointer against the view without knowing anything about the widget tree.
  ///
  /// Called on layout rather than per event: the size changes when the window
  /// resizes, which is orders of magnitude rarer than the pointer moving.
  void setViewSize(double width, double height) {
    if (_setFloat(4, width) | _setFloat(5, height)) _publish();
  }

  bool _setPointer(
    double screenX,
    double screenY,
    double viewX,
    double viewY,
    int viewAddress,
  ) {
    // Bitwise `|`, not `||`: every one of these must run. Short-circuiting
    // would leave later coordinates unwritten as soon as an earlier one
    // happened to be unchanged.
    return _setFloat(0, screenX) |
        _setFloat(1, screenY) |
        _setFloat(2, viewX) |
        _setFloat(3, viewY) |
        _setFloat(6, (viewAddress + 1).toDouble());
  }

  bool _setFloat(int index, double value) {
    // Compared after the float32 round-trip the mirror already stores, so a
    // value that cannot change the published bytes does not count as a
    // change and does not trigger a publish.
    final rounded = _mirrorFloats[index];
    if (rounded == value) return false;
    _mirrorFloats[index] = value;
    return _mirrorFloats[index] != rounded;
  }

  bool _setBit(int id, bool down) {
    final index = id >> 3;
    final mask = 1 << (id & 7);
    final before = _mirror[index];
    final after = down ? before | mask : before & ~mask;
    if (after == before) return false;
    _mirror[index] = after;
    return true;
  }

  void _publish() {
    // copyFromLatest: false - [_mirror] is the complete picture and every
    // byte of the slot is about to be overwritten, so copying the previous
    // slot forward first would be a memcpy whose every byte is then
    // discarded (the same call the state channels make, for the same
    // reason).
    final slot = _buffer.beginWrite(copyFromLatest: false);
    _viewFor(slot).setAll(0, _mirror);
    _buffer.publish();
  }

  Uint8List _viewFor(Pointer<Uint8> pointer) {
    final address = pointer.address;
    for (var i = 0; i < _slotAddresses.length; i++) {
      if (_slotAddresses[i] == address) return _slotViews[i];
    }
    throw StateError(
      'the input device resolved a triple-buffer slot it has no view for - '
      'the device was attached to different storage than it is writing '
      'through.',
    );
  }

  /// The binding-table lookup, built once on first use.
  ///
  /// Not a the typed-handle rule violation and not on the hot path: it
  /// translates a device event (which really does only identify itself by a USB
  /// HID usage code) into an [InputKey], once per key press, on the Flutter
  /// isolate. Resolution - the thing that runs per action per tick - never
  /// comes near it.
  static InputKey? _keyboardFor(PhysicalKeyboardKey physical) {
    var table = _keyboardByUsage;
    if (table == null) {
      table = <int, InputKey>{};
      for (final key in InputKey.all) {
        if (key is KeyboardKey) table[key.physicalKey.usbHidUsage] = key;
      }
      _keyboardByUsage = table;
    }
    return table[physical.usbHidUsage];
  }
}
