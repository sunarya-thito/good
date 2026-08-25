import 'package:good/src/input/input_key.dart';

/// One thing a human can push **part way**: a stick's displacement along one
/// direction, a trigger's pull, an on-screen joystick's offset.
///
/// The analog half of the input vocabulary, and deliberately a second
/// vocabulary rather than a widening of [InputKey]. A key is one *bit* in the
/// raw device-state block and an axis is one `float32` in it, so nothing that
/// indexes bits could ever carry a half-pushed stick - which is the whole
/// reason [GamepadButton.leftStickUp] and friends exist and are lossy. A
/// control that is genuinely both appears in both tables: a physical stick
/// reaches the block as four thresholded bits *and*, since this exists, as two
/// axes, and the game picks which reading it wants by picking a binding.
///
/// ```dart
/// // proportional - a stick half-pushed moves at half speed
/// move = input.has<Vector2>(
///   const StickBinding(x: .padLeftStickX, y: .padLeftStickY),
/// );
///
/// // thresholded - the same stick as a d-pad, still available, unchanged
/// move = input.has<Vector2>(
///   const Vec2Binding(
///     up: .padLeftStickUp,
///     down: .padLeftStickDown,
///     left: .padLeftStickLeft,
///     right: .padLeftStickRight,
///   ),
/// );
/// ```
///
/// # The range is -1..1, with 0 at rest
///
/// That is what an axis *is*, and it is the same convention the rest of the
/// engine already uses: **+1 is up and +1 is right**, matching the world's own
/// `+y` up, so adding `stick.value` straight to a `transformOffset` moves the
/// thing the way the player pushed. A trigger has no negative half and so
/// reports 0..1.
///
/// The value is whatever the device reported, unshaped - no deadzone, no
/// response curve, no normalization. A stick pushed diagonally to its corner
/// therefore has a length above 1 on hardware whose gate allows it, exactly as
/// [Vec2Binding] hands back (1, 1). Shaping is the game's, because which shape
/// is right is the game's question: `GamepadCollector.stickDeadzone` still
/// applies to the *bit* path and is untouched by any of this.
///
/// # Why the same shape as [InputKey], and not `String`
///
/// Every value is a `static const` on this class so `.padLeftStickX` resolves
/// through Dart's dot shorthand against the context type, and so a binding
/// holding one stays `const`. Every constructor is private, so the values
/// below are the only axes a caller can name. [GamepadAxis.call] is the one
/// deliberate exception - it builds an axis for a player slot known at
/// runtime.
///
/// # [id] is a build-local float index, not a wire format
///
/// [id] is this axis's position in the raw block's float section, counted in
/// floats, assigned by hand below and checked by `game_analog_test.dart`.
/// Serialization writes [name] instead, so inserting an axis in the middle of
/// the table costs nothing but a recompile - the same split [InputKey.id]
/// makes, for the same reason: a saved binding outlives the build that wrote
/// it.
sealed class InputAxis {
  const InputAxis(this.id, this.name);

  /// Position in the raw block's axis section, counted in floats. Stable
  /// within one build, meaningless across builds - see the class doc.
  final int id;

  /// The identifier this axis is spelled with in Dart (`InputAxis.padLeftStickX`)
  /// and in JSON, the same string in both so a typo in a save file is
  /// greppable against the declaration.
  final String name;

  /// Which device this axis belongs to - the JSON discriminator, and what
  /// [fromJson] switches on.
  String get kind;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'name': name,
  };

  /// Rebuilds an axis from [toJson]'s output.
  ///
  /// Closed over the sealed hierarchy, so adding a device is a compile error
  /// here rather than a lookup that silently misses - the same switch
  /// [InputKey.fromJson] makes, and not the name-resolved registry the design
  /// rules forbid: a JSON map genuinely does not know its own Dart type.
  static InputAxis fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    switch (kind) {
      case VirtualAxis.kindName:
        return VirtualAxis.fromJson(json);
      case GamepadAxis.kindName:
        return GamepadAxis.fromJson(json);
      default:
        throw FormatException(
          'unknown InputAxis kind "$kind" - expected '
          '"${VirtualAxis.kindName}" or "${GamepadAxis.kindName}"',
          json,
        );
    }
  }

  static InputAxis _byName(
    Map<String, InputAxis> table,
    Map<String, Object?> json,
  ) {
    final name = json['name'];
    final axis = table[name];
    if (axis == null) {
      throw FormatException(
        'no InputAxis is named "$name" - it may have been renamed since this '
        'binding was saved',
        json,
      );
    }
    return axis;
  }

  @override
  String toString() => 'InputAxis.$name';

  // --- on-screen controls -------------------------------------------------

  static const VirtualAxis virtualLeftStickX = VirtualAxis._(
    0,
    'virtualLeftStickX',
  );
  static const VirtualAxis virtualLeftStickY = VirtualAxis._(
    1,
    'virtualLeftStickY',
  );
  static const VirtualAxis virtualRightStickX = VirtualAxis._(
    2,
    'virtualRightStickX',
  );
  static const VirtualAxis virtualRightStickY = VirtualAxis._(
    3,
    'virtualRightStickY',
  );

  // --- gamepad, on the "any pad" slot -------------------------------------

  static const GamepadAxis padLeftStickX = GamepadAxis._(
    GamepadAnalog.leftStickX,
    0,
    4,
    'padLeftStickX',
  );
  static const GamepadAxis padLeftStickY = GamepadAxis._(
    GamepadAnalog.leftStickY,
    0,
    5,
    'padLeftStickY',
  );
  static const GamepadAxis padRightStickX = GamepadAxis._(
    GamepadAnalog.rightStickX,
    0,
    6,
    'padRightStickX',
  );
  static const GamepadAxis padRightStickY = GamepadAxis._(
    GamepadAnalog.rightStickY,
    0,
    7,
    'padRightStickY',
  );
  static const GamepadAxis padLeftTrigger = GamepadAxis._(
    GamepadAnalog.leftTrigger,
    0,
    8,
    'padLeftTrigger',
  );
  static const GamepadAxis padRightTrigger = GamepadAxis._(
    GamepadAnalog.rightTrigger,
    0,
    9,
    'padRightTrigger',
  );

  /// Every axis, indexed by [id] - `all[n].id == n` for every n, which
  /// `game_analog_test.dart` checks directly because the ids above are written
  /// by hand.
  ///
  /// Public because a rebinding screen legitimately needs to enumerate what
  /// can be bound; nothing in the resolution path walks it.
  ///
  /// The gamepad tail is generated for the same reason [InputKey.all]'s is:
  /// it is every axis on every slot, and four near-identical hand-written
  /// blocks is exactly the table a typo hides in. The generation order has to
  /// match [GamepadAxis]' own id formula, and `all[n].id == n` is what holds
  /// the two together.
  static final List<InputAxis> all = <InputAxis>[
    ..._fixed,
    for (var slot = 0; slot < GamepadKey.slotCount; slot++)
      for (final analog in GamepadAnalog.values) GamepadAxis._at(analog, slot),
  ];

  /// The axes whose ids are written by hand above and belong to no slot.
  static const List<InputAxis> _fixed = <InputAxis>[
    virtualLeftStickX, virtualLeftStickY, //
    virtualRightStickX, virtualRightStickY,
  ];

  /// How many `float32`s the raw device-state block has to carry for axes.
  static int get count => all.length;

  /// Two axes are the same axis when they occupy the same float.
  ///
  /// Identity would almost do - every axis here is a canonicalised `const` -
  /// but a slotted one (`InputAxis.padLeftStickX(1)`) is built at runtime from
  /// a slot number, so two calls produce two instances of the same axis.
  @override
  bool operator ==(Object other) => other is InputAxis && other.id == id;

  @override
  int get hashCode => id;
}

/// An axis driven by something on screen rather than by hardware - an
/// on-screen joystick, a slider, a drag area.
///
/// Nothing in the engine writes these: they exist so a widget can, through
/// `InputDevice.setVirtualAxis`, and so the game reading the value cannot tell
/// which kind of source filled it in. A binding names an [InputAxis]; whether
/// a thumb or a thumbstick moved it is not a question it can ask.
///
/// Four of them, named after the two sticks a touch game draws, because that
/// is the layout they exist to serve: one to move with, one to aim with. They
/// are not slotted - an on-screen control belongs to whoever is holding the
/// device.
final class VirtualAxis extends InputAxis {
  const VirtualAxis._(super.id, super.name);

  static const String kindName = 'virtualAxis';

  @override
  String get kind => kindName;

  static VirtualAxis fromJson(Map<String, Object?> json) =>
      InputAxis._byName(_byName, json) as VirtualAxis;

  static final Map<String, InputAxis> _byName = <String, InputAxis>{
    for (final axis in InputAxis.all)
      if (axis is VirtualAxis) axis.name: axis,
  };
}

/// Which analog control on a pad, independent of which pad.
///
/// The axis counterpart of [GamepadButton], and a class rather than an `enum`
/// for the same concrete reason: [GamepadAxis] computes its [InputAxis.id]
/// from [index] inside a `const` constructor, and `someEnumValue.index` is not
/// a constant expression in Dart while a final field of a `const` object is.
///
/// [name] is written out rather than derived, for the reason [InputAxis.name]
/// exists at all: it goes into a save file, so it has to survive a Dart
/// rename.
final class GamepadAnalog {
  const GamepadAnalog._(this.index, this.name);

  /// Position in [values], and this axis's offset within a slot's block of
  /// floats.
  final int index;

  /// What a saved binding spells this axis.
  final String name;

  static const GamepadAnalog leftStickX = GamepadAnalog._(0, 'padLeftStickX');
  static const GamepadAnalog leftStickY = GamepadAnalog._(1, 'padLeftStickY');
  static const GamepadAnalog rightStickX = GamepadAnalog._(2, 'padRightStickX');
  static const GamepadAnalog rightStickY = GamepadAnalog._(3, 'padRightStickY');

  /// The left trigger's pull, 0..1. The same control [GamepadButton.leftTrigger]
  /// reports as one bit at `GamepadCollector.triggerThreshold`; both are
  /// written on every event, and a game binds whichever reading it wants.
  static const GamepadAnalog leftTrigger = GamepadAnalog._(4, 'padLeftTrigger');
  static const GamepadAnalog rightTrigger = GamepadAnalog._(
    5,
    'padRightTrigger',
  );

  /// Every analog control, indexed by [index] - `values[n].index == n`,
  /// checked by `game_analog_test.dart` because this table is written by hand.
  static const List<GamepadAnalog> values = <GamepadAnalog>[
    leftStickX, leftStickY, //
    rightStickX, rightStickY,
    leftTrigger, rightTrigger,
  ];

  @override
  String toString() => 'GamepadAnalog.$name';
}

/// One analog control on a pad, on a **player slot** rather than on a
/// particular physical device.
///
/// ```dart
/// aim   = input.has<Vector2>(const StickBinding(x: .padRightStickX, y: .padRightStickY));
/// p2Aim = input.has<Vector2>(
///   StickBinding(x: InputAxis.padRightStickX(2), y: InputAxis.padRightStickY(2)),
/// );
/// ```
///
/// Slots work exactly as they do for buttons, and are the same seats - this
/// reads [GamepadKey.slotCount] rather than declaring its own, because how
/// many players a game seats is one fact. **Slot 0 means "any connected
/// pad"**: for a bit that is the OR of every real slot, and for an axis it is
/// the one furthest from rest, which is the same idea for a value that has a
/// magnitude. Two players pushing two sticks on slot 0 is therefore "whoever
/// is pushing hardest", which is meaningless for two players and exactly right
/// for the single-player case slot 0 exists to serve.
///
/// # Ids
///
/// `firstId + slot * axisCount + analog.index`. [_at] computes it; the slot-0
/// constants on [InputAxis] write it out, because a `const` constructor cannot
/// read a field off one of its own parameters and those constants have to be
/// `const` for `.padLeftStickX` to work in a `const` binding.
/// `game_analog_test.dart` holds the two spellings together.
final class GamepadAxis extends InputAxis {
  const GamepadAxis._(this.analog, this.slot, super.id, super.name);

  /// The computed form - what [call] and [InputAxis.all]'s generated gamepad
  /// tail both go through, so a runtime `padLeftStickX(2)` and the table can
  /// never disagree about which float they mean.
  factory GamepadAxis._at(GamepadAnalog analog, int slot) {
    assert(
      slot >= 0 && slot < GamepadKey.slotCount,
      'a gamepad slot is 0..${GamepadKey.slotCount - 1}, and 0 means "any '
      'connected pad" - $slot is not a seat that exists',
    );
    return GamepadAxis._(
      analog,
      slot,
      firstId + slot * axisCount + analog.index,
      slot == 0 ? analog.name : '${analog.name}@$slot',
    );
  }

  static const String kindName = 'gamepadAxis';

  /// The float the gamepad block starts at: right after the axes that belong
  /// to no slot. Asserted against `InputAxis._fixed`'s own length by
  /// `game_analog_test.dart`, since both are written out by hand.
  static const int firstId = 4;

  /// How many floats one slot occupies - `GamepadAnalog.values.length`,
  /// written out because the id arithmetic above has to be a constant
  /// expression. `game_analog_test.dart` checks the two against each other.
  static const int axisCount = 6;

  /// Which control this is, independent of slot.
  final GamepadAnalog analog;

  /// Which player slot, `0` being any connected pad.
  final int slot;

  /// The same axis on [slot] - see the class doc on the tear-off.
  GamepadAxis call(int slot) => GamepadAxis._at(analog, slot);

  @override
  String get kind => kindName;

  /// Carries the slot as its own field rather than folding it into the name,
  /// so a saved binding stays readable and a slot can be *remapped* on load
  /// without rewriting the axis.
  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'name': analog.name,
    if (slot != 0) 'slot': slot,
  };

  static GamepadAxis fromJson(Map<String, Object?> json) {
    final axis = InputAxis._byName(_byName, json) as GamepadAxis;
    final slot = json['slot'];
    if (slot == null) return axis;
    if (slot is! int || slot < 0 || slot >= GamepadKey.slotCount) {
      throw FormatException(
        'a gamepad slot must be an integer in 0..${GamepadKey.slotCount - 1}, '
        'not $slot',
        json,
      );
    }
    return axis(slot);
  }

  /// Slot-0 axes by name - the slot is restored separately, from its own
  /// field, so this table holds one entry per control rather than one per
  /// control per slot.
  static final Map<String, InputAxis> _byName = <String, InputAxis>{
    for (final analog in GamepadAnalog.values)
      analog.name: GamepadAxis._at(analog, 0),
  };
}
