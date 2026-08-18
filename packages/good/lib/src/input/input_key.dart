import 'package:flutter/gestures.dart'
    show
        kBackMouseButton,
        kForwardMouseButton,
        kMiddleMouseButton,
        kPrimaryMouseButton,
        kSecondaryMouseButton;
import 'package:flutter/services.dart' show PhysicalKeyboardKey;

/// One thing a human can hold down: a key on the keyboard, a button on the
/// mouse, or a button on a gamepad.
///
/// # Why `sealed`, and why every value is a `static const`
///
/// Both properties exist to make the declaration site read the way the owner
/// specified:
///
/// ```dart
/// triggerSkill = input.has<bool>(const TriggerBinding(.spacebar));
/// movement = input.has<Vector2>(const Vec2Binding(up: .w, down: .s, left: .a, right: .d));
/// ```
///
/// `.spacebar` is Dart's dot shorthand: it resolves against the *context
/// type*, which is `InputKey`, so every key has to be reachable as a static
/// member of this class. And a binding is a `const` value type (see
/// [InputBinding]), which means the keys it holds must be `const` too. Every
/// constructor is private, so the declared values below are the only ones a
/// caller can name - with one deliberate exception, [GamepadKey.call], which
/// builds a key for a player slot known at runtime and is therefore the one
/// place `==` rather than `identical` is doing the work.
///
/// # [id] is a build-local bit index, not a wire format
///
/// [id] is this key's bit position in the raw device-state block (see
/// `InputState`), assigned by hand below and checked by
/// `game_input_test.dart`. It is deliberately **not** what serialization uses:
/// both isolate copies run the same build so they always agree on ids, but a
/// *saved keybinding file* outlives the build it was written by. So [toJson]
/// writes [name] and inserting a new key in the middle of the table below
/// costs nothing but a recompile.
///
/// # Devices are additive
///
/// Gamepads landed exactly as this doc predicted they would: a [GamepadKey]
/// subclass, its values appended to [all] after the mouse buttons. No
/// existing id moved, no binding type changed, and `InputBinding.isActuated`
/// still asks nothing but "is this key down". Analog *axes* remain a
/// different shape (they are not a held/not-held bit); the sticks reach this
/// vocabulary through a deadzone rather than by being modelled honestly -
/// see [GamepadButton].
sealed class InputKey {
  const InputKey(this.id, this.name);

  /// Bit position in the raw device-state block. Stable within one build,
  /// meaningless across builds - see the class doc.
  final int id;

  /// The identifier this key is spelled with in Dart (`InputKey.arrowLeft`)
  /// and in JSON. The two are the same string on purpose: a keybinding file
  /// is readable, and a typo in one is greppable against the other.
  final String name;

  /// Which device this key belongs to - the JSON discriminator, and what
  /// [fromJson] switches on.
  String get kind;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'name': name,
  };

  /// Rebuilds a key from [toJson]'s output.
  ///
  /// This is the one place a `switch` over the sealed hierarchy is needed,
  /// and it is not the "registry" the design rules out: it is closed
  /// (`sealed` means the analyzer fails this switch when a device is added,
  /// rather than a lookup silently missing an entry) and it resolves nothing
  /// the caller could have told us instead - a JSON map genuinely does not
  /// know its own Dart type.
  static InputKey fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    switch (kind) {
      case KeyboardKey.kindName:
        return KeyboardKey.fromJson(json);
      case MouseButtonKey.kindName:
        return MouseButtonKey.fromJson(json);
      case GamepadKey.kindName:
        return GamepadKey.fromJson(json);
      default:
        throw FormatException(
          'unknown InputKey kind "$kind" - expected '
          '"${KeyboardKey.kindName}", "${MouseButtonKey.kindName}" or '
          '"${GamepadKey.kindName}"',
          json,
        );
    }
  }

  /// Looks up a key by [name] within a [kind], for [fromJson].
  ///
  /// A `Map` here is not a the typed-handle rule violation: nothing the framework
  /// *hands back* is being looked up by string. This is parsing a file the
  /// user wrote, where a string is all there is, and it runs when a save is
  /// loaded - never per tick and never per action.
  static InputKey _byName(
    Map<String, InputKey> table,
    Map<String, Object?> json,
  ) {
    final name = json['name'];
    final key = table[name];
    if (key == null) {
      throw FormatException(
        'no InputKey is named "$name" - it may have been renamed since this '
        'binding was saved',
        json,
      );
    }
    return key;
  }

  @override
  String toString() => 'InputKey.$name';

  // --- keyboard: letters --------------------------------------------------

  static const InputKey a = KeyboardKey._(0, 'a', PhysicalKeyboardKey.keyA);
  static const InputKey b = KeyboardKey._(1, 'b', PhysicalKeyboardKey.keyB);
  static const InputKey c = KeyboardKey._(2, 'c', PhysicalKeyboardKey.keyC);
  static const InputKey d = KeyboardKey._(3, 'd', PhysicalKeyboardKey.keyD);
  static const InputKey e = KeyboardKey._(4, 'e', PhysicalKeyboardKey.keyE);
  static const InputKey f = KeyboardKey._(5, 'f', PhysicalKeyboardKey.keyF);
  static const InputKey g = KeyboardKey._(6, 'g', PhysicalKeyboardKey.keyG);
  static const InputKey h = KeyboardKey._(7, 'h', PhysicalKeyboardKey.keyH);
  static const InputKey i = KeyboardKey._(8, 'i', PhysicalKeyboardKey.keyI);
  static const InputKey j = KeyboardKey._(9, 'j', PhysicalKeyboardKey.keyJ);
  static const InputKey k = KeyboardKey._(10, 'k', PhysicalKeyboardKey.keyK);
  static const InputKey l = KeyboardKey._(11, 'l', PhysicalKeyboardKey.keyL);
  static const InputKey m = KeyboardKey._(12, 'm', PhysicalKeyboardKey.keyM);
  static const InputKey n = KeyboardKey._(13, 'n', PhysicalKeyboardKey.keyN);
  static const InputKey o = KeyboardKey._(14, 'o', PhysicalKeyboardKey.keyO);
  static const InputKey p = KeyboardKey._(15, 'p', PhysicalKeyboardKey.keyP);
  static const InputKey q = KeyboardKey._(16, 'q', PhysicalKeyboardKey.keyQ);
  static const InputKey r = KeyboardKey._(17, 'r', PhysicalKeyboardKey.keyR);
  static const InputKey s = KeyboardKey._(18, 's', PhysicalKeyboardKey.keyS);
  static const InputKey t = KeyboardKey._(19, 't', PhysicalKeyboardKey.keyT);
  static const InputKey u = KeyboardKey._(20, 'u', PhysicalKeyboardKey.keyU);
  static const InputKey v = KeyboardKey._(21, 'v', PhysicalKeyboardKey.keyV);
  static const InputKey w = KeyboardKey._(22, 'w', PhysicalKeyboardKey.keyW);
  static const InputKey x = KeyboardKey._(23, 'x', PhysicalKeyboardKey.keyX);
  static const InputKey y = KeyboardKey._(24, 'y', PhysicalKeyboardKey.keyY);
  static const InputKey z = KeyboardKey._(25, 'z', PhysicalKeyboardKey.keyZ);

  // --- keyboard: digits ---------------------------------------------------

  static const InputKey digit0 = KeyboardKey._(
    26,
    'digit0',
    PhysicalKeyboardKey.digit0,
  );
  static const InputKey digit1 = KeyboardKey._(
    27,
    'digit1',
    PhysicalKeyboardKey.digit1,
  );
  static const InputKey digit2 = KeyboardKey._(
    28,
    'digit2',
    PhysicalKeyboardKey.digit2,
  );
  static const InputKey digit3 = KeyboardKey._(
    29,
    'digit3',
    PhysicalKeyboardKey.digit3,
  );
  static const InputKey digit4 = KeyboardKey._(
    30,
    'digit4',
    PhysicalKeyboardKey.digit4,
  );
  static const InputKey digit5 = KeyboardKey._(
    31,
    'digit5',
    PhysicalKeyboardKey.digit5,
  );
  static const InputKey digit6 = KeyboardKey._(
    32,
    'digit6',
    PhysicalKeyboardKey.digit6,
  );
  static const InputKey digit7 = KeyboardKey._(
    33,
    'digit7',
    PhysicalKeyboardKey.digit7,
  );
  static const InputKey digit8 = KeyboardKey._(
    34,
    'digit8',
    PhysicalKeyboardKey.digit8,
  );
  static const InputKey digit9 = KeyboardKey._(
    35,
    'digit9',
    PhysicalKeyboardKey.digit9,
  );

  // --- keyboard: function row --------------------------------------------

  static const InputKey f1 = KeyboardKey._(36, 'f1', PhysicalKeyboardKey.f1);
  static const InputKey f2 = KeyboardKey._(37, 'f2', PhysicalKeyboardKey.f2);
  static const InputKey f3 = KeyboardKey._(38, 'f3', PhysicalKeyboardKey.f3);
  static const InputKey f4 = KeyboardKey._(39, 'f4', PhysicalKeyboardKey.f4);
  static const InputKey f5 = KeyboardKey._(40, 'f5', PhysicalKeyboardKey.f5);
  static const InputKey f6 = KeyboardKey._(41, 'f6', PhysicalKeyboardKey.f6);
  static const InputKey f7 = KeyboardKey._(42, 'f7', PhysicalKeyboardKey.f7);
  static const InputKey f8 = KeyboardKey._(43, 'f8', PhysicalKeyboardKey.f8);
  static const InputKey f9 = KeyboardKey._(44, 'f9', PhysicalKeyboardKey.f9);
  static const InputKey f10 = KeyboardKey._(45, 'f10', PhysicalKeyboardKey.f10);
  static const InputKey f11 = KeyboardKey._(46, 'f11', PhysicalKeyboardKey.f11);
  static const InputKey f12 = KeyboardKey._(47, 'f12', PhysicalKeyboardKey.f12);

  // --- keyboard: arrows ---------------------------------------------------

  static const InputKey arrowUp = KeyboardKey._(
    48,
    'arrowUp',
    PhysicalKeyboardKey.arrowUp,
  );
  static const InputKey arrowDown = KeyboardKey._(
    49,
    'arrowDown',
    PhysicalKeyboardKey.arrowDown,
  );
  static const InputKey arrowLeft = KeyboardKey._(
    50,
    'arrowLeft',
    PhysicalKeyboardKey.arrowLeft,
  );
  static const InputKey arrowRight = KeyboardKey._(
    51,
    'arrowRight',
    PhysicalKeyboardKey.arrowRight,
  );

  // --- keyboard: whitespace and editing -----------------------------------

  static const InputKey spacebar = KeyboardKey._(
    52,
    'spacebar',
    PhysicalKeyboardKey.space,
  );
  static const InputKey enter = KeyboardKey._(
    53,
    'enter',
    PhysicalKeyboardKey.enter,
  );
  static const InputKey escape = KeyboardKey._(
    54,
    'escape',
    PhysicalKeyboardKey.escape,
  );
  static const InputKey tab = KeyboardKey._(55, 'tab', PhysicalKeyboardKey.tab);
  static const InputKey backspace = KeyboardKey._(
    56,
    'backspace',
    PhysicalKeyboardKey.backspace,
  );
  static const InputKey delete = KeyboardKey._(
    57,
    'delete',
    PhysicalKeyboardKey.delete,
  );
  static const InputKey insert = KeyboardKey._(
    58,
    'insert',
    PhysicalKeyboardKey.insert,
  );
  static const InputKey home = KeyboardKey._(
    59,
    'home',
    PhysicalKeyboardKey.home,
  );
  static const InputKey end = KeyboardKey._(60, 'end', PhysicalKeyboardKey.end);
  static const InputKey pageUp = KeyboardKey._(
    61,
    'pageUp',
    PhysicalKeyboardKey.pageUp,
  );
  static const InputKey pageDown = KeyboardKey._(
    62,
    'pageDown',
    PhysicalKeyboardKey.pageDown,
  );
  static const InputKey capsLock = KeyboardKey._(
    63,
    'capsLock',
    PhysicalKeyboardKey.capsLock,
  );

  // --- keyboard: modifiers ------------------------------------------------
  //
  // Left and right are separate keys because they are separate keys. A game
  // that wants either binds two actions, or one action per hand; collapsing
  // them here would make the distinction unrecoverable.

  static const InputKey shiftLeft = KeyboardKey._(
    64,
    'shiftLeft',
    PhysicalKeyboardKey.shiftLeft,
  );
  static const InputKey shiftRight = KeyboardKey._(
    65,
    'shiftRight',
    PhysicalKeyboardKey.shiftRight,
  );
  static const InputKey controlLeft = KeyboardKey._(
    66,
    'controlLeft',
    PhysicalKeyboardKey.controlLeft,
  );
  static const InputKey controlRight = KeyboardKey._(
    67,
    'controlRight',
    PhysicalKeyboardKey.controlRight,
  );
  static const InputKey altLeft = KeyboardKey._(
    68,
    'altLeft',
    PhysicalKeyboardKey.altLeft,
  );
  static const InputKey altRight = KeyboardKey._(
    69,
    'altRight',
    PhysicalKeyboardKey.altRight,
  );
  static const InputKey metaLeft = KeyboardKey._(
    70,
    'metaLeft',
    PhysicalKeyboardKey.metaLeft,
  );
  static const InputKey metaRight = KeyboardKey._(
    71,
    'metaRight',
    PhysicalKeyboardKey.metaRight,
  );

  // --- keyboard: punctuation ----------------------------------------------

  static const InputKey minus = KeyboardKey._(
    72,
    'minus',
    PhysicalKeyboardKey.minus,
  );
  static const InputKey equal = KeyboardKey._(
    73,
    'equal',
    PhysicalKeyboardKey.equal,
  );
  static const InputKey bracketLeft = KeyboardKey._(
    74,
    'bracketLeft',
    PhysicalKeyboardKey.bracketLeft,
  );
  static const InputKey bracketRight = KeyboardKey._(
    75,
    'bracketRight',
    PhysicalKeyboardKey.bracketRight,
  );
  static const InputKey backslash = KeyboardKey._(
    76,
    'backslash',
    PhysicalKeyboardKey.backslash,
  );
  static const InputKey semicolon = KeyboardKey._(
    77,
    'semicolon',
    PhysicalKeyboardKey.semicolon,
  );
  static const InputKey quote = KeyboardKey._(
    78,
    'quote',
    PhysicalKeyboardKey.quote,
  );
  static const InputKey comma = KeyboardKey._(
    79,
    'comma',
    PhysicalKeyboardKey.comma,
  );
  static const InputKey period = KeyboardKey._(
    80,
    'period',
    PhysicalKeyboardKey.period,
  );
  static const InputKey slash = KeyboardKey._(
    81,
    'slash',
    PhysicalKeyboardKey.slash,
  );
  static const InputKey backquote = KeyboardKey._(
    82,
    'backquote',
    PhysicalKeyboardKey.backquote,
  );

  // --- keyboard: numpad ---------------------------------------------------

  static const InputKey numpad0 = KeyboardKey._(
    83,
    'numpad0',
    PhysicalKeyboardKey.numpad0,
  );
  static const InputKey numpad1 = KeyboardKey._(
    84,
    'numpad1',
    PhysicalKeyboardKey.numpad1,
  );
  static const InputKey numpad2 = KeyboardKey._(
    85,
    'numpad2',
    PhysicalKeyboardKey.numpad2,
  );
  static const InputKey numpad3 = KeyboardKey._(
    86,
    'numpad3',
    PhysicalKeyboardKey.numpad3,
  );
  static const InputKey numpad4 = KeyboardKey._(
    87,
    'numpad4',
    PhysicalKeyboardKey.numpad4,
  );
  static const InputKey numpad5 = KeyboardKey._(
    88,
    'numpad5',
    PhysicalKeyboardKey.numpad5,
  );
  static const InputKey numpad6 = KeyboardKey._(
    89,
    'numpad6',
    PhysicalKeyboardKey.numpad6,
  );
  static const InputKey numpad7 = KeyboardKey._(
    90,
    'numpad7',
    PhysicalKeyboardKey.numpad7,
  );
  static const InputKey numpad8 = KeyboardKey._(
    91,
    'numpad8',
    PhysicalKeyboardKey.numpad8,
  );
  static const InputKey numpad9 = KeyboardKey._(
    92,
    'numpad9',
    PhysicalKeyboardKey.numpad9,
  );
  static const InputKey numpadAdd = KeyboardKey._(
    93,
    'numpadAdd',
    PhysicalKeyboardKey.numpadAdd,
  );
  static const InputKey numpadSubtract = KeyboardKey._(
    94,
    'numpadSubtract',
    PhysicalKeyboardKey.numpadSubtract,
  );
  static const InputKey numpadMultiply = KeyboardKey._(
    95,
    'numpadMultiply',
    PhysicalKeyboardKey.numpadMultiply,
  );
  static const InputKey numpadDivide = KeyboardKey._(
    96,
    'numpadDivide',
    PhysicalKeyboardKey.numpadDivide,
  );
  static const InputKey numpadDecimal = KeyboardKey._(
    97,
    'numpadDecimal',
    PhysicalKeyboardKey.numpadDecimal,
  );
  static const InputKey numpadEnter = KeyboardKey._(
    98,
    'numpadEnter',
    PhysicalKeyboardKey.numpadEnter,
  );

  // --- mouse buttons ------------------------------------------------------
  //
  // Buttons only. Mouse *position* is a follow-up (`MouseBinding`) and is
  // deliberately absent: a position is not a held/not-held bit, so it does
  // not belong in this block at all.

  static const InputKey leftMouseButton = MouseButtonKey._(
    99,
    'leftMouseButton',
    kPrimaryMouseButton,
  );
  static const InputKey rightMouseButton = MouseButtonKey._(
    100,
    'rightMouseButton',
    kSecondaryMouseButton,
  );
  static const InputKey middleMouseButton = MouseButtonKey._(
    101,
    'middleMouseButton',
    kMiddleMouseButton,
  );
  static const InputKey backMouseButton = MouseButtonKey._(
    102,
    'backMouseButton',
    kBackMouseButton,
  );
  static const InputKey forwardMouseButton = MouseButtonKey._(
    103,
    'forwardMouseButton',
    kForwardMouseButton,
  );

  // --- gamepad ------------------------------------------------------------
  //
  // Unlike everything above, these are not one id each: a gamepad button is
  // the same button on up to [GamepadKey.slotCount] pads, so each of the
  // constants below is the *slot 0* key and `InputKey.padLeft(1)` is the
  // same button on slot 1. See [GamepadKey] for what a slot is and how the
  // ids are laid out.

  static const GamepadKey padUp = GamepadKey._(
    GamepadButton.padUp,
    0,
    104,
    'padUp',
  );
  static const GamepadKey padDown = GamepadKey._(
    GamepadButton.padDown,
    0,
    105,
    'padDown',
  );
  static const GamepadKey padLeft = GamepadKey._(
    GamepadButton.padLeft,
    0,
    106,
    'padLeft',
  );
  static const GamepadKey padRight = GamepadKey._(
    GamepadButton.padRight,
    0,
    107,
    'padRight',
  );
  static const GamepadKey padA = GamepadKey._(GamepadButton.a, 0, 108, 'padA');
  static const GamepadKey padB = GamepadKey._(GamepadButton.b, 0, 109, 'padB');
  static const GamepadKey padX = GamepadKey._(GamepadButton.x, 0, 110, 'padX');
  static const GamepadKey padY = GamepadKey._(GamepadButton.y, 0, 111, 'padY');
  static const GamepadKey padLeftShoulder = GamepadKey._(
    GamepadButton.leftShoulder,
    0,
    112,
    'padLeftShoulder',
  );
  static const GamepadKey padRightShoulder = GamepadKey._(
    GamepadButton.rightShoulder,
    0,
    113,
    'padRightShoulder',
  );
  static const GamepadKey padLeftTrigger = GamepadKey._(
    GamepadButton.leftTrigger,
    0,
    114,
    'padLeftTrigger',
  );
  static const GamepadKey padRightTrigger = GamepadKey._(
    GamepadButton.rightTrigger,
    0,
    115,
    'padRightTrigger',
  );
  static const GamepadKey padLeftStick = GamepadKey._(
    GamepadButton.leftStick,
    0,
    116,
    'padLeftStick',
  );
  static const GamepadKey padRightStick = GamepadKey._(
    GamepadButton.rightStick,
    0,
    117,
    'padRightStick',
  );
  static const GamepadKey padStart = GamepadKey._(
    GamepadButton.start,
    0,
    118,
    'padStart',
  );
  static const GamepadKey padSelect = GamepadKey._(
    GamepadButton.select,
    0,
    119,
    'padSelect',
  );
  static const GamepadKey padLeftStickUp = GamepadKey._(
    GamepadButton.leftStickUp,
    0,
    120,
    'padLeftStickUp',
  );
  static const GamepadKey padLeftStickDown = GamepadKey._(
    GamepadButton.leftStickDown,
    0,
    121,
    'padLeftStickDown',
  );
  static const GamepadKey padLeftStickLeft = GamepadKey._(
    GamepadButton.leftStickLeft,
    0,
    122,
    'padLeftStickLeft',
  );
  static const GamepadKey padLeftStickRight = GamepadKey._(
    GamepadButton.leftStickRight,
    0,
    123,
    'padLeftStickRight',
  );
  static const GamepadKey padRightStickUp = GamepadKey._(
    GamepadButton.rightStickUp,
    0,
    124,
    'padRightStickUp',
  );
  static const GamepadKey padRightStickDown = GamepadKey._(
    GamepadButton.rightStickDown,
    0,
    125,
    'padRightStickDown',
  );
  static const GamepadKey padRightStickLeft = GamepadKey._(
    GamepadButton.rightStickLeft,
    0,
    126,
    'padRightStickLeft',
  );
  static const GamepadKey padRightStickRight = GamepadKey._(
    GamepadButton.rightStickRight,
    0,
    127,
    'padRightStickRight',
  );
  static const GamepadKey padHome = GamepadKey._(
    GamepadButton.home,
    0,
    128,
    'padHome',
  );
  static const GamepadKey padTouchpad = GamepadKey._(
    GamepadButton.touchpad,
    0,
    129,
    'padTouchpad',
  );

  /// Every key, indexed by [id] - `all[n].id == n` for every n, which
  /// `game_input_test.dart` checks directly because the ids above are written
  /// by hand.
  ///
  /// Public because a rebinding screen legitimately needs to enumerate what
  /// can be bound; nothing in the resolution path walks it.
  ///
  /// The gamepad tail is generated rather than written out: it is every
  /// button on every slot, which is [GamepadKey.slotCount] times as many
  /// entries as there are buttons, and hand-writing four near-identical
  /// blocks is exactly the kind of table a typo hides in. The generation
  /// order has to match [GamepadKey]'s own id formula, and the `all[n].id ==
  /// n` test is what holds the two together.
  static final List<InputKey> all = <InputKey>[
    ..._fixed,
    for (var slot = 0; slot < GamepadKey.slotCount; slot++)
      for (final button in GamepadButton.values) GamepadKey._at(button, slot),
  ];

  /// The keys whose ids are written by hand above - everything that is one
  /// physical control rather than one control times a slot.
  static const List<InputKey> _fixed = <InputKey>[
    a, b, c, d, e, f, g, h, i, j, k, l, m, //
    n, o, p, q, r, s, t, u, v, w, x, y, z,
    digit0, digit1, digit2, digit3, digit4,
    digit5, digit6, digit7, digit8, digit9,
    f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,
    arrowUp, arrowDown, arrowLeft, arrowRight,
    spacebar, enter, escape, tab, backspace, delete,
    insert, home, end, pageUp, pageDown, capsLock,
    shiftLeft, shiftRight, controlLeft, controlRight,
    altLeft, altRight, metaLeft, metaRight,
    minus, equal, bracketLeft, bracketRight, backslash,
    semicolon, quote, comma, period, slash, backquote,
    numpad0, numpad1, numpad2, numpad3, numpad4,
    numpad5, numpad6, numpad7, numpad8, numpad9,
    numpadAdd, numpadSubtract, numpadMultiply, numpadDivide,
    numpadDecimal, numpadEnter,
    leftMouseButton, rightMouseButton, middleMouseButton,
    backMouseButton, forwardMouseButton,
  ];

  /// How many bits the raw device-state block has to carry.
  static int get count => all.length;

  /// Two keys are the same key when they occupy the same bit.
  ///
  /// Identity would almost do - every keyboard and mouse key is a
  /// canonicalised `const` - but a slotted gamepad key
  /// (`InputKey.padA(1)`) is built at runtime from a slot number, so two
  /// calls produce two instances of the same button. Comparing [id] makes
  /// those equal, which is what a rebinding screen comparing a saved key
  /// against a declared one needs.
  @override
  bool operator ==(Object other) => other is InputKey && other.id == id;

  @override
  int get hashCode => id;
}

/// A key on the keyboard, named by **physical position** rather than by the
/// character it produces.
///
/// [physicalKey] is what the collector matches `KeyEvent.physicalKey`
/// against, and that choice is load-bearing in two ways. A logical key
/// changes when a modifier is held (`shift`+`1` produces `!`), so a
/// logical-key binding held across a shift press would see a release it never
/// got and stick down. And a logical key changes with the keyboard layout, so
/// WASD would land on ZQSD for a French user - whereas the physical positions
/// stay where the player's fingers are, which is what every action game
/// means by "WASD".
///
/// The cost, stated plainly: [name] describes the US-layout label of that
/// position, so a rebinding screen showing `InputKey.q` to an AZERTY user is
/// naming the key their keyboard prints "a" on. Showing the *logical* label
/// for a physical key is a real feature (Flutter can do it) and is not one
/// this class does.
final class KeyboardKey extends InputKey {
  const KeyboardKey._(super.id, super.name, this.physicalKey);

  static const String kindName = 'keyboard';

  /// The Flutter key this binds to - matched by `usbHidUsage`, which is the
  /// stable, layout-independent identity of a physical key position.
  final PhysicalKeyboardKey physicalKey;

  @override
  String get kind => kindName;

  static KeyboardKey fromJson(Map<String, Object?> json) =>
      InputKey._byName(_byName, json) as KeyboardKey;

  static final Map<String, InputKey> _byName = <String, InputKey>{
    for (final key in InputKey.all)
      if (key is KeyboardKey) key.name: key,
  };
}

/// A button on the mouse.
///
/// It binds exactly like a keyboard key - `TriggerBinding(.leftMouseButton)`
/// is a perfectly ordinary trigger - because from an action's point of view
/// there is no difference: both are one bit that is either held or not. Mouse
/// *position* is a different shape entirely and is a follow-up
/// (`MouseBinding`/`MousePosition`), not something this type grows into.
final class MouseButtonKey extends InputKey {
  const MouseButtonKey._(super.id, super.name, this.buttonMask);

  static const String kindName = 'mouse';

  /// The bit this button occupies in `PointerEvent.buttons`, which is how the
  /// collector reads the whole mouse's state out of one event.
  final int buttonMask;

  @override
  String get kind => kindName;

  static MouseButtonKey fromJson(Map<String, Object?> json) =>
      InputKey._byName(_byName, json) as MouseButtonKey;

  static final Map<String, InputKey> _byName = <String, InputKey>{
    for (final key in InputKey.all)
      if (key is MouseButtonKey) key.name: key,
  };
}

/// One button on a gamepad, in the standard Xbox-style layout every platform
/// is normalised onto.
///
/// The four `*Stick*` directions at the end are **not** buttons on any real
/// pad: they are the analog sticks, thresholded into held/not-held bits by
/// the collector (see `GamepadCollector.stickDeadzone`). That is what lets
/// `Vec2Binding(up: .padLeftStickUp, ...)` work at all - a `Vec2Binding`
/// composes four bits, and an analog axis is not a bit. It is a deliberate
/// simplification and a lossy one: a stick half-pushed reads exactly like a
/// stick slammed, so a game that wants real analog movement needs an analog
/// binding type, which is a follow-up and not this.
///
/// The order here is the id order within a slot - see [GamepadKey].
/// A class rather than an `enum`, for one concrete reason: [GamepadKey]
/// computes its own [InputKey.id] from [index] inside a `const` constructor,
/// and Dart does not allow `someEnumValue.index` in a constant expression -
/// while a final field of a `const` object is fine. The cost is writing
/// [index] and [name] out by hand; the alternative was passing the ordinal
/// separately at every [GamepadKey] declaration, which is the same table with
/// an extra chance to get it wrong.
///
/// [name] is here rather than derived, for the reason [InputKey.name] exists:
/// it goes into a save file, so it has to survive a Dart rename.
final class GamepadButton {
  const GamepadButton._(this.index, this.name);

  /// Position in [values], and this button's offset within a slot's block of
  /// bits.
  final int index;

  /// What a saved binding spells this button.
  final String name;

  static const GamepadButton padUp = GamepadButton._(0, 'padUp');
  static const GamepadButton padDown = GamepadButton._(1, 'padDown');
  static const GamepadButton padLeft = GamepadButton._(2, 'padLeft');
  static const GamepadButton padRight = GamepadButton._(3, 'padRight');
  static const GamepadButton a = GamepadButton._(4, 'padA');
  static const GamepadButton b = GamepadButton._(5, 'padB');
  static const GamepadButton x = GamepadButton._(6, 'padX');
  static const GamepadButton y = GamepadButton._(7, 'padY');
  static const GamepadButton leftShoulder = GamepadButton._(
    8,
    'padLeftShoulder',
  );
  static const GamepadButton rightShoulder = GamepadButton._(
    9,
    'padRightShoulder',
  );
  static const GamepadButton leftTrigger = GamepadButton._(
    10,
    'padLeftTrigger',
  );
  static const GamepadButton rightTrigger = GamepadButton._(
    11,
    'padRightTrigger',
  );
  static const GamepadButton leftStick = GamepadButton._(12, 'padLeftStick');
  static const GamepadButton rightStick = GamepadButton._(13, 'padRightStick');
  static const GamepadButton start = GamepadButton._(14, 'padStart');
  static const GamepadButton select = GamepadButton._(15, 'padSelect');
  static const GamepadButton leftStickUp = GamepadButton._(
    16,
    'padLeftStickUp',
  );
  static const GamepadButton leftStickDown = GamepadButton._(
    17,
    'padLeftStickDown',
  );
  static const GamepadButton leftStickLeft = GamepadButton._(
    18,
    'padLeftStickLeft',
  );
  static const GamepadButton leftStickRight = GamepadButton._(
    19,
    'padLeftStickRight',
  );
  static const GamepadButton rightStickUp = GamepadButton._(
    20,
    'padRightStickUp',
  );
  static const GamepadButton rightStickDown = GamepadButton._(
    21,
    'padRightStickDown',
  );
  static const GamepadButton rightStickLeft = GamepadButton._(
    22,
    'padRightStickLeft',
  );
  static const GamepadButton rightStickRight = GamepadButton._(
    23,
    'padRightStickRight',
  );

  /// The guide/home button. Many platforms reserve it for the OS and never
  /// deliver it; it is here because the ones that do deliver it should not
  /// have nowhere to put it.
  static const GamepadButton home = GamepadButton._(24, 'padHome');

  /// Clicking the touchpad surface - DualSense and DualShock only.
  static const GamepadButton touchpad = GamepadButton._(25, 'padTouchpad');

  /// Every button, indexed by [index] - `values[n].index == n`, checked by
  /// `game_input_test.dart` for the same reason the [InputKey.all] invariant
  /// is checked: both tables are written by hand.
  static const List<GamepadButton> values = <GamepadButton>[
    padUp, padDown, padLeft, padRight, //
    a, b, x, y,
    leftShoulder, rightShoulder,
    leftTrigger, rightTrigger,
    leftStick, rightStick,
    start, select,
    leftStickUp, leftStickDown, leftStickLeft, leftStickRight,
    rightStickUp, rightStickDown, rightStickLeft, rightStickRight,
    home, touchpad,
  ];

  @override
  String toString() => 'GamepadButton.$name';
}

/// A button on a gamepad, on a **player slot** rather than on a particular
/// physical device.
///
/// ```dart
/// confirm   = input.has<bool>(const TriggerBinding(.padA));       // any pad
/// p2Confirm = input.has<bool>(TriggerBinding(InputKey.padA(1)));  // slot 1
/// ```
///
/// # Why a slot and not a device id
///
/// An OS device id is not stable across a reconnect, let alone a reboot, so a
/// saved keybinding naming one would break the first time the player
/// unplugged their pad. A slot is a seat at the couch: the collector assigns
/// connected pads to slots in connection order, and a binding names the seat.
///
/// **Slot 0 means "any connected pad"** - its bits are the OR of every real
/// slot's, so the single-player case (which is what `.padA` gives you with no
/// extra syntax) works no matter which pad the player picked up.
///
/// # The `call` tear-off
///
/// [call] is an ordinary instance method, which is what makes
/// `InputKey.padA` usable *as a value* and `InputKey.padA(1)` usable as the
/// same button on another slot - the second is calling the first. The one
/// cost: `InputKey.padA(1)` is a method call, so a binding built from it
/// cannot be `const`. That is one allocation during `describeInputs`, which
/// runs once at boot.
///
/// # Ids
///
/// `firstId + slot * GamepadButton.values.length + button.index`. [_at]
/// computes it; the slot-0 constants in [InputKey] write it out, because a
/// `const` constructor cannot read a field off one of its own parameters
/// (the same restriction that made [GamepadButton] a class instead of an
/// `enum`) and the slot-0 keys have to be `const` for `.padA` to work in a
/// `const` binding. `game_input_test.dart` holds the two spellings together -
/// it is the same `all[n].id == n` check every other key in this file
/// already relies on.
final class GamepadKey extends InputKey {
  const GamepadKey._(this.button, this.slot, super.id, super.name);

  /// The computed form - what [call] and [InputKey.all]'s generated gamepad
  /// tail both go through, so a runtime `padA(2)` and the table can never
  /// disagree about which bit they mean.
  factory GamepadKey._at(GamepadButton button, int slot) {
    assert(
      slot >= 0 && slot < slotCount,
      'a gamepad slot is 0..${slotCount - 1}, and 0 means "any connected '
      'pad" - $slot is not a seat that exists',
    );
    return GamepadKey._(
      button,
      slot,
      firstId + slot * buttonCount + button.index,
      slot == 0 ? button.name : '${button.name}@$slot',
    );
  }

  static const String kindName = 'gamepad';

  /// How many slots exist, slot 0 (the aggregate "any pad") included - so
  /// three real seats plus "any". Every slot costs [GamepadButton] bits in
  /// the raw block whether a pad is connected to it or not, which is the
  /// reason this is a small number rather than a generous one.
  static const int slotCount = 4;

  /// How many bits one slot occupies - `GamepadButton.values.length`,
  /// written out because the id arithmetic below has to be a constant
  /// expression. `game_input_test.dart` checks the two against each other.
  static const int buttonCount = 26;

  /// The id the gamepad block starts at: right after the last hand-written
  /// key. Asserted against [GamepadButton]'s own length by
  /// `game_input_test.dart`, since both are written out by hand.
  static const int firstId = 104;

  /// Which button this is, independent of slot.
  final GamepadButton button;

  /// Which player slot, `0` being any connected pad.
  final int slot;

  /// The same button on [slot] - see the class doc on the tear-off.
  GamepadKey call(int slot) => GamepadKey._at(button, slot);

  @override
  String get kind => kindName;

  /// Carries the slot as its own field rather than folding it into the name,
  /// so a saved binding stays readable and a slot can be *remapped* on load
  /// (a settings screen moving player 2 to another seat) without rewriting
  /// the button.
  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'name': _names[button.index],
    if (slot != 0) 'slot': slot,
  };

  static GamepadKey fromJson(Map<String, Object?> json) {
    final key = InputKey._byName(_byName, json) as GamepadKey;
    final slot = json['slot'];
    if (slot == null) return key;
    if (slot is! int || slot < 0 || slot >= slotCount) {
      throw FormatException(
        'a gamepad slot must be an integer in 0..${slotCount - 1}, not $slot',
        json,
      );
    }
    return key(slot);
  }

  /// Every button's name, indexed by [GamepadButton.index]. Written out
  /// rather than taken from the enum's own `name`, for the same reason
  /// [InputKey.name] exists at all: this string goes into a save file, so it
  /// has to survive an enum member being renamed in Dart.
  static const List<String> _names = <String>[
    'padUp', 'padDown', 'padLeft', 'padRight', //
    'padA', 'padB', 'padX', 'padY',
    'padLeftShoulder', 'padRightShoulder',
    'padLeftTrigger', 'padRightTrigger',
    'padLeftStick', 'padRightStick',
    'padStart', 'padSelect',
    'padLeftStickUp', 'padLeftStickDown',
    'padLeftStickLeft', 'padLeftStickRight',
    'padRightStickUp', 'padRightStickDown',
    'padRightStickLeft', 'padRightStickRight',
  ];

  /// Slot-0 keys by name - the slot is restored separately, from its own
  /// field, so this table holds one entry per button rather than one per
  /// button per slot.
  static final Map<String, InputKey> _byName = <String, InputKey>{
    for (final button in GamepadButton.values)
      button.name: GamepadKey._at(button, 0),
  };
}
