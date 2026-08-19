import 'dart:async';

import 'package:gamepads/gamepads.dart' as pads;
import 'package:meta/meta.dart';

import 'package:good/src/input/input_key.dart';
import 'package:good/src/input/input_state.dart';

/// Turns connected gamepads into bits in the raw input block.
///
/// The mirror image of what `GameView` does for the keyboard: it lives on the
/// Flutter isolate, it writes through the same [InputDevice] as every other
/// device, and the game isolate never learns that a gamepad exists - it reads
/// [InputKey.padA] exactly the way it reads [InputKey.spacebar].
///
/// # Slots, not device ids
///
/// A pad is assigned the first free **slot** when it is first heard from, and
/// keeps it until [releaseSlot]. Bindings name slots (see [GamepadKey]), so a
/// saved keybinding survives the player unplugging their controller - which
/// an OS device id would not.
///
/// Slot 0 is not assignable: it is the OR of every real slot, which is what
/// makes `.padA` mean "the A button on whichever pad someone picked up". The
/// single-player case therefore needs no setup at all.
///
/// # Normalisation is the plugin's job, not this class's
///
/// `package:gamepads` reports platform-specific keys at its lower layer
/// (Windows says `"dpadUp"`, Android says `"KEYCODE_DPAD_UP"`, Linux says
/// `"5"`, macOS says an SF Symbol name) and normalises them against an SDL
/// controller database at its upper one. This subscribes to the **upper**
/// stream, so what arrives here is already the standard Xbox-style layout and
/// there is no per-platform table in this repo to drift out of date. Events
/// the plugin cannot normalise are dropped by the plugin before this sees
/// them.
///
/// # Analog is thresholded, not carried
///
/// A stick becomes four bits and a trigger becomes one, at [stickDeadzone] /
/// [triggerThreshold]. That is lossy on purpose: the whole binding vocabulary
/// is held/not-held, so this is what lets `Vec2Binding(up: .padLeftStickUp,
/// ...)` work at all. A game that wants proportional movement needs an analog
/// binding type, which does not exist yet.
final class GamepadCollector {
  @internal
  GamepadCollector(this._device);

  final InputDevice _device;

  /// Which slot each pad was given, in first-heard order.
  final Map<String, int> _slots = <String, int>{};

  StreamSubscription<pads.NormalizedGamepadEvent>? _subscription;

  /// How far a stick has to be pushed before its direction counts as held.
  ///
  /// Half travel by default. Too low and a resting stick with a little drift
  /// walks the player into a wall; too high and the pad feels dead.
  double stickDeadzone = 0.5;

  /// How far a trigger has to be pulled before it counts as pressed.
  double triggerThreshold = 0.5;

  /// Whether [attach] has been called and not undone.
  bool get isAttached => _subscription != null;

  /// Starts listening to the OS.
  ///
  /// Called by `GameView` when it mounts, for the same reason it registers
  /// the keyboard handler there: a game with no widget on screen has no
  /// business holding an OS subscription open. Calling it twice is a no-op
  /// rather than a second subscription.
  void attach() {
    if (_subscription != null) return;
    _subscription = pads.Gamepads.normalizedEvents.listen(handleEvent);
  }

  /// Stops listening, and releases every slot - a pad that was held down when
  /// the view went away is not held down any more, and leaving those bits set
  /// would strand whatever they were driving.
  Future<void> detach() async {
    final subscription = _subscription;
    _subscription = null;
    // Taken out of the map *before* releasing any of them: `releaseSlot`
    // removes its own entry, which would be a concurrent modification of the
    // very thing being iterated.
    final slots = _slots.values.toList(growable: false);
    _slots.clear();
    for (var i = 0; i < slots.length; i++) {
      releaseSlot(slots[i]);
    }
    await subscription?.cancel();
  }

  /// Applies one normalised event.
  ///
  /// Public and taking the plugin's own event type so the whole translation -
  /// slot assignment, deadzones, which bit - can be driven directly by a
  /// test, with no OS, no plugin registration and no gamepad. [attach] does
  /// nothing this does not, beyond subscribing.
  void handleEvent(pads.NormalizedGamepadEvent event) {
    final slot = _slotFor(event.gamepadId);
    if (slot == null) return;
    final button = event.button;
    if (button != null) {
      final mapped = _buttons[button.index];
      if (mapped == null) return;
      _device.setGamepadButton(slot, mapped, event.value != 0);
      return;
    }
    final axis = event.axis;
    if (axis == null) return;
    _applyAxis(slot, axis, event.value);
  }

  /// Which slot [gamepadId] holds, assigning one if this is the first time it
  /// has been heard from.
  ///
  /// Null when every slot is taken. That pad is then inert - reporting it
  /// through a slot someone else owns would give two players one controller,
  /// which is worse than a controller that does nothing.
  int? _slotFor(String gamepadId) {
    final existing = _slots[gamepadId];
    if (existing != null) return existing;
    for (var slot = 1; slot < GamepadKey.slotCount; slot++) {
      if (!_slots.containsValue(slot)) {
        _slots[gamepadId] = slot;
        return slot;
      }
    }
    assert(
      false,
      'a ${GamepadKey.slotCount - 1}-slot game has no seat left for gamepad '
      '"$gamepadId", so it will not do anything. Release a slot when a player '
      'leaves, or raise GamepadKey.slotCount - every slot costs '
      '${GamepadKey.buttonCount} bits in the raw input block whether it is '
      'occupied or not, which is why it is not simply generous.',
    );
    return null;
  }

  /// Which slot [gamepadId] holds, or null if it has never been heard from.
  /// For a settings screen that wants to say "press a button on player 2's
  /// controller" and then show which one answered.
  int? slotOf(String gamepadId) => _slots[gamepadId];

  /// Clears every bit [slot] owns, and forgets whichever pad held it.
  ///
  /// The disconnect path: the platform stream reports no disconnect events,
  /// so a game that cares polls `Gamepads.list()` and calls this. Without it
  /// a pad unplugged mid-jump leaves the jump button held forever.
  void releaseSlot(int slot) {
    for (var i = 0; i < GamepadButton.values.length; i++) {
      _device.setGamepadButton(slot, GamepadButton.values[i], false);
    }
    _slots.removeWhere((_, value) => value == slot);
  }

  void _applyAxis(int slot, pads.GamepadAxis axis, double value) {
    switch (axis) {
      case pads.GamepadAxis.leftStickX:
        _applyStick(
          slot,
          value,
          GamepadButton.leftStickLeft,
          GamepadButton.leftStickRight,
        );
      case pads.GamepadAxis.leftStickY:
        // The plugin reports +1 as up, and so does this vocabulary - and so,
        // now, does the world. Which of the two bits carries which axis sign
        // is still a `Vec2Binding` question and not this one; all this does
        // is name the bit.
        _applyStick(
          slot,
          value,
          GamepadButton.leftStickDown,
          GamepadButton.leftStickUp,
        );
      case pads.GamepadAxis.rightStickX:
        _applyStick(
          slot,
          value,
          GamepadButton.rightStickLeft,
          GamepadButton.rightStickRight,
        );
      case pads.GamepadAxis.rightStickY:
        _applyStick(
          slot,
          value,
          GamepadButton.rightStickDown,
          GamepadButton.rightStickUp,
        );
      case pads.GamepadAxis.leftTrigger:
        _device.setGamepadButton(
          slot,
          GamepadButton.leftTrigger,
          value >= triggerThreshold,
        );
      case pads.GamepadAxis.rightTrigger:
        _device.setGamepadButton(
          slot,
          GamepadButton.rightTrigger,
          value >= triggerThreshold,
        );
    }
  }

  /// One axis, two opposed bits. Both are written every time, not just the
  /// one that changed: an axis swinging from -1 to +1 in a single event has
  /// to release the old direction as well as press the new one, and a stick
  /// held both left and right is not a state that should be reachable.
  void _applyStick(
    int slot,
    double value,
    GamepadButton negative,
    GamepadButton positive,
  ) {
    _device.setGamepadButton(slot, negative, value <= -stickDeadzone);
    _device.setGamepadButton(slot, positive, value >= stickDeadzone);
  }

  /// The plugin's button vocabulary translated into this one, indexed by the
  /// plugin's own enum index.
  ///
  /// A `List` rather than a `Map` because the plugin's enum is dense and this
  /// runs per event; `null` means "no bit for that button here", which is not
  /// an error - the two vocabularies are allowed to differ, and dropping a
  /// button nothing can bind beats inventing a key for it.
  static final List<GamepadButton?> _buttons = _buildButtonTable();

  static List<GamepadButton?> _buildButtonTable() {
    final table = List<GamepadButton?>.filled(
      pads.GamepadButton.values.length,
      null,
    );
    // Written as an explicit switch rather than by name-matching the two
    // enums: they genuinely disagree in places (`leftBumper`/`leftShoulder`,
    // `back`/`select`), and a name match would silently drop exactly those.
    for (final button in pads.GamepadButton.values) {
      table[button.index] = switch (button) {
        pads.GamepadButton.a => GamepadButton.a,
        pads.GamepadButton.b => GamepadButton.b,
        pads.GamepadButton.x => GamepadButton.x,
        pads.GamepadButton.y => GamepadButton.y,
        pads.GamepadButton.leftBumper => GamepadButton.leftShoulder,
        pads.GamepadButton.rightBumper => GamepadButton.rightShoulder,
        pads.GamepadButton.leftTrigger => GamepadButton.leftTrigger,
        pads.GamepadButton.rightTrigger => GamepadButton.rightTrigger,
        pads.GamepadButton.back => GamepadButton.select,
        pads.GamepadButton.start => GamepadButton.start,
        pads.GamepadButton.home => GamepadButton.home,
        pads.GamepadButton.leftStick => GamepadButton.leftStick,
        pads.GamepadButton.rightStick => GamepadButton.rightStick,
        pads.GamepadButton.dpadUp => GamepadButton.padUp,
        pads.GamepadButton.dpadDown => GamepadButton.padDown,
        pads.GamepadButton.dpadLeft => GamepadButton.padLeft,
        pads.GamepadButton.dpadRight => GamepadButton.padRight,
        pads.GamepadButton.touchpad => GamepadButton.touchpad,
      };
    }
    return table;
  }
}
