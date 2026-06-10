import 'package:flutter/services.dart';
import 'package:goo2d/src/game.dart';
import 'package:goo2d/src/component.dart';
import 'package:goo2d/src/lifecycle.dart';
import 'package:vector_math/vector_math_64.dart';

part 'keyboard.dart';

/// The various lifecycle phases of an [InputAction].
///
/// This enum is used to track the progression of an input interaction, from
/// its initial waiting state through execution to its final completion or
/// cancellation.
enum InputActionPhase {
  /// The action is currently disabled and will not process input.
  disabled,

  /// The action is active and waiting for a binding to be pressed.
  waiting,

  /// A binding has been pressed, but the action's trigger requirements
  /// have not yet been fully met.
  started,

  /// The action has been fully triggered and its logic is being executed.
  performed,

  /// The input interaction was interrupted before it could complete.
  canceled,
}

/// The fundamental behavior type of an [InputAction].
///
/// This determines how the action processes input values and how it
/// transitions between lifecycle phases.
enum InputActionType {
  /// The action represents a continuous range of values (e.g., joystick).
  value,

  /// The action represents a discrete momentary trigger (e.g., button).
  button,

  /// The action passes through raw input without any sophisticated
  /// phase management.
  passThrough,
}

/// The data payload provided to [InputAction] callbacks.
///
/// This class encapsulates all relevant information about an input event,
/// allowing listeners to inspect the current phase, read input values,
/// and identify the driving control.
///
/// ```dart
/// void onJump(CallbackContext context) {
///   if (context.phase == InputActionPhase.performed) {
///     print('Magnitude: ${context.magnitude}');
///   }
/// }
/// ```
///
/// See also:
/// * [InputAction], the component that generates these contexts.
/// * [InputEvent], the mechanism for dispatching these contexts.
class CallbackContext {
  /// The action that triggered this callback.
  ///
  /// This provides access to the underlying action state.
  final InputAction action;

  /// The phase the action was in when this callback was triggered.
  ///
  /// This indicates whether the action just started, was performed, or was canceled.
  final InputActionPhase phase;

  /// Reads the current value of the action as type [T].
  ///
  /// * [T]: The expected type of the input value.
  T readValue<T>() => action.readValue<T>();

  /// The magnitude of the current input value (e.g., how far a stick is tilted).
  ///
  /// This is used to evaluate variable-strength inputs like analog triggers.
  double get magnitude => action._getMagnitude();

  /// The specific input control currently driving this action.
  ///
  /// This allows listeners to know which hardware component triggered the action.
  InputControl? get control => action.activeControl;

  /// Creates a callback context for the specified [action] and [phase].
  ///
  /// * [action]: The action that triggered the callback.
  /// * [phase]: The phase the action was in.
  CallbackContext(this.action, this.phase);
}

/// A specialized event system for handling [InputAction] notifications.
///
/// This class provides a way to register and unregister listeners for
/// specific action phases (started, performed, canceled) using a concise
/// operator-based syntax.
///
/// ```dart
/// void setupAction(InputAction action) {
///   action.performed += (ctx) => print('Action Performed!');
/// }
/// ```
///
/// See also:
/// * [InputAction], which uses this for its phase notifications.
/// * [CallbackContext], the data provided to listeners.
class InputEvent {
  final List<void Function(CallbackContext)> _listeners = [];

  /// Adds a [listener] to this event.
  ///
  /// * [listener]: The callback to register.
  InputEvent operator +(void Function(CallbackContext) listener) {
    _listeners.add(listener);
    return this;
  }

  /// Removes a [listener] from this event.
  ///
  /// * [listener]: The callback to unregister.
  InputEvent operator -(void Function(CallbackContext) listener) {
    _listeners.remove(listener);
    return this;
  }

  /// Invokes all registered listeners with the provided [context].
  ///
  /// * [context]: The data to pass to listeners.
  void invoke(CallbackContext context) {
    for (var listener in List<void Function(CallbackContext)>.from(
      _listeners,
    )) {
      listener(context);
    }
  }

  /// Clears all registered listeners and releases resources.
  ///
  /// This prevents memory leaks and ensures no dead callbacks are triggered.
  void dispose() => _listeners.clear();
}

/// The system responsible for processing and dispatching user input.
///
/// [InputSystem] centralizes the state of all input hardware (keyboard,
/// mouse, gamepads) and coordinates the lifecycle of [InputAction] components.
/// It ensures that input events are processed consistently during the
/// engine's update phase.
///
/// ```dart
/// import 'package:flutter/services.dart';
///
/// void checkInput(GameEngine engine) {
///   final input = engine.getSystem<InputSystem>()!;
///   if (input.keyboard[LogicalKeyboardKey.space].isPressed) {
///     print('Jumping!');
///   }
/// }
/// ```
///
/// See also:
/// * [InputAction], the high-level component for handling input.
/// * [KeyboardState], for low-level keyboard access.
class InputSystem implements GameSystem {
  KeyboardState? _keyboard;

  /// The low-level state of the physical keyboard.
  ///
  /// This provides access to the current state of individual keys, allowing
  /// for frame-accurate checks of key presses and releases.
  KeyboardState get keyboard {
    assert(
      _keyboard != null,
      'KeyboardState is not ready. Did you call initialize() on GameEngine?',
    );
    return _keyboard!;
  }

  final List<InputAction> _actions = [];

  /// The number of times the input system has been updated this frame.
  ///
  /// This is used to track input events with sub-frame precision when
  /// multiple fixed-time updates occur in a single visual frame.
  int dynamicUpdateCount = 0;

  GameEngine? _game;

  @override
  GameEngine get game {
    assert(_game != null, 'InputSystem is not attached to a GameEngine');
    return _game!;
  }

  @override
  bool get gameAttached => _game != null;

  static final Map<Type, Object Function()> _defaultValues = {
    bool: () => false,
    double: () => 0.0,
    Vector2: () => Vector2.zero(),
  };

  /// Creates a new input system.
  ///
  /// This constructor is typically called by the [GameEngine] during its
  /// initialization process. It sets up the internal state necessary for
  /// processing input events across the application.
  InputSystem();

  @override
  Future<void> attach(GameEngine game) async {
    _game = game;
    _keyboard = KeyboardState(game);
  }

  /// Registers a default value [provider] for a specific input type [T].
  ///
  /// This is used by the input system to return safe default values when
  /// an action is disabled or has no active bindings.
  ///
  /// * [T]: The type of the input value.
  /// * [provider]: A function that returns a new default value instance.
  static void registerDefaultValue<T extends Object>(T Function() provider) =>
      _defaultValues[T] = provider;

  /// Retrieves the default value for a specific input type [T].
  ///
  /// * [T]: The type of the input value.
  static T getDefaultValue<T>() {
    final provider = _defaultValues[T];
    if (provider == null) throw UnimplementedError('No default value for $T');
    return provider() as T;
  }

  void _registerAction(InputAction action) => _actions.add(action);
  void _unregisterAction(InputAction action) => _actions.remove(action);

  /// Updates the state of all registered input actions.
  ///
  /// This is called internally by the engine during the update phase to
  /// synchronize action phases with the current hardware state.
  void update() {
    dynamicUpdateCount++;
    for (var action in _actions) {
      if (action.enabled) action._updatePhase();
    }
  }

  @override
  Future<void> dispose() async {
    _keyboard?.dispose();
    for (var action in List<InputAction>.from(_actions)) {
      action.dispose();
    }
    _actions.clear();
  }
}

/// The base interface for an individual input source (e.g., a key, a button).
///
/// [InputControl] tracks the raw state of an input hardware element, including
/// its current value and the timing of its most recent state changes.
///
/// ```dart
/// void checkControl(InputControl control) {
///   if (control.wasPressedThisFrame) {
///     print('Control pressed!');
///   }
/// }
/// ```
///
/// See also:
/// * [ButtonControl], a specific implementation for binary states.
///
/// * [T]: The type of the value produced by this control.
abstract class InputControl<T> {
  /// The [GameEngine] this control is associated with.
  ///
  /// This is used to access engine-level systems like the ticker for frame timing.
  GameEngine get game;

  /// The current raw value of the control.
  ///
  /// This provides the exact hardware state (e.g., a boolean for buttons, a Vector2 for sticks).
  T get value;

  /// The normalized magnitude of the current value (0.0 to 1.0).
  ///
  /// This is used for deadzone calculations and uniform threshold checks across different control types.
  double get magnitude;

  /// The frame index when the control was last pressed.
  ///
  /// This is used to determine if a press occurred during the current rendering frame.
  int lastFramePressed = -1;

  /// The frame index when the control was last released.
  ///
  /// This is used to determine if a release occurred during the current rendering frame.
  int lastFrameReleased = -1;

  /// The dynamic update index when the control was last pressed.
  ///
  /// This ensures input synchronization across variable-rate physics updates.
  int lastUpdatePressed = -1;

  /// The dynamic update index when the control was last released.
  ///
  /// This ensures release synchronization across variable-rate physics updates.
  int lastUpdateReleased = -1;

  /// Whether the control is currently in a pressed state.
  ///
  /// This is true as long as the control is held down or actuated.
  bool get isPressed;

  /// Whether the control was pressed during the current frame.
  ///
  /// This is useful for single-fire actions like jumping or shooting.
  bool get wasPressedThisFrame =>
      lastFramePressed == game.getSystem<TickerState>()?.frameCount;

  /// Whether the control was released during the current frame.
  ///
  /// This is useful for actions that trigger upon release, like charging a jump.
  bool get wasReleasedThisFrame =>
      lastFrameReleased == game.getSystem<TickerState>()?.frameCount;
}

/// A specialized [InputControl] for binary button states.
///
/// This is used for keyboard keys, mouse buttons, and gamepad buttons,
/// providing a simple true/false state and associated timing information.
///
/// ```dart
/// void testButton(GameEngine game) {
///   final jumpButton = ButtonControl(game);
///   jumpButton.press();
///   print(jumpButton.isPressed); // true
/// }
/// ```
///
/// See also:
/// * [KeyboardState], which manages a collection of these controls.
class ButtonControl extends InputControl<bool> {
  @override
  final GameEngine game;
  bool _isPressed = false;

  /// Creates a new button control associated with the provided [game].
  ///
  /// * [game]: The game engine instance to associate with.
  ButtonControl(this.game);

  @override
  bool get value => _isPressed;
  @override
  bool get isPressed => _isPressed;
  @override
  double get magnitude => _isPressed ? 1.0 : 0.0;

  /// Sets the button to a pressed state and records the current timing.
  ///
  /// This updates the frame and update indices to the current engine state.
  void press() {
    if (!_isPressed) {
      lastFramePressed = game.getSystem<TickerState>()?.frameCount ?? -1;
      lastUpdatePressed =
          game.getSystem<InputSystem>()?.dynamicUpdateCount ?? -1;
    }
    _isPressed = true;
  }

  /// Sets the button to a released state and records the current timing.
  ///
  /// This updates the frame and update indices to the current engine state.
  void release() {
    if (_isPressed) {
      lastFrameReleased = game.getSystem<TickerState>()?.frameCount ?? -1;
      lastUpdateReleased =
          game.getSystem<InputSystem>()?.dynamicUpdateCount ?? -1;
    }
    _isPressed = false;
  }
}

/// Manages the runtime state and events for the physical keyboard.
///
/// [KeyboardState] interfaces with the platform's hardware keyboard system,
/// translating raw key events into [ButtonControl] updates that can be
/// consumed by the engine's update loop.
///
/// ```dart
/// import 'package:flutter/services.dart';
///
/// void checkSpace(KeyboardState keyboard) {
///   final space = keyboard[LogicalKeyboardKey.space];
///   if (space.wasPressedThisFrame) {
///     print('Space pressed!');
///   }
/// }
/// ```
///
/// See also:
/// * [InputSystem], which provides access to this state.
/// * [ButtonControl], the representation of an individual key.
class KeyboardState {
  /// The [GameEngine] this keyboard state is associated with.
  ///
  /// This ensures hardware keyboard events are correctly synced with the engine's lifecycle.
  final GameEngine game;
  final Map<LogicalKeyboardKey, ButtonControl> _keys = {};

  /// Creates a new keyboard state and registers a hardware event handler.
  ///
  /// * [game]: The engine instance.
  KeyboardState(this.game) {
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /// Accesses the [ButtonControl] associated with a specific [key].
  ///
  /// If no control exists for the key, one will be created lazily.
  ///
  /// * [key]: The logical keyboard key to retrieve.
  ButtonControl operator [](LogicalKeyboardKey key) =>
      _keys.putIfAbsent(key, () => ButtonControl(game));

  bool _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    final control = this[key];
    if (event is KeyDownEvent) {
      control.press();
    } else if (event is KeyUpEvent) {
      control.release();
    }
    return false;
  }

  /// Removes the hardware event handler and releases resources.
  ///
  /// This must be called when the input system is destroyed to prevent memory leaks from dangling Flutter event listeners.
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
  }
}

/// A declarative mapping between raw input controls and an [InputAction].
///
/// [InputBinding] allows developers to define how various input sources
/// (keys, buttons, sticks) should contribute to a single high-level action.
/// It supports simple mappings, key-specific mappings, and complex
/// composite mappings (e.g., WASD to a vector).
///
/// ```dart
/// import 'package:flutter/services.dart';
/// void configureInput() {
///   final moveAction = InputAction()
///     ..bindings = [
///       InputBinding.composite(
///         up: InputBinding.key(LogicalKeyboardKey.keyW),
///         down: InputBinding.key(LogicalKeyboardKey.keyS),
///         left: InputBinding.key(LogicalKeyboardKey.keyA),
///         right: InputBinding.key(LogicalKeyboardKey.keyD),
///       ),
///     ];
/// }
/// ```
///
/// See also:
/// * [InputAction], the component that uses these bindings.
/// * [BindingState], the runtime instance of a binding.
abstract class InputBinding {
  const InputBinding._();

  /// Creates a runtime state instance for this binding.
  ///
  /// This bridges the declarative binding definition with live engine input data.
  ///
  /// * [game]: The engine instance.
  BindingState createState(GameEngine game);

  /// Whether the binding is currently considered pressed.
  ///
  /// This evaluates the live state of the underlying controls.
  ///
  /// * [game]: The engine instance.
  bool isPressed(GameEngine game);

  /// Whether the binding was pressed during the current frame.
  ///
  /// This evaluates the frame-specific timing of the underlying controls.
  ///
  /// * [game]: The engine instance.
  bool wasPressedThisFrame(GameEngine game);

  /// Whether the binding was released during the current frame.
  ///
  /// This evaluates the frame-specific timing of the underlying controls.
  ///
  /// * [game]: The engine instance.
  bool wasReleasedThisFrame(GameEngine game);

  /// The normalized magnitude of the binding's current value.
  ///
  /// This evaluates the combined strength of all underlying controls.
  ///
  /// * [game]: The engine instance.
  double magnitude(GameEngine game);

  /// Reads the current value of the binding as type [T].
  ///
  /// This converts the raw control data into the expected gameplay type (e.g. a 2D Vector).
  ///
  /// * [game]: The engine instance.
  T readValue<T>(GameEngine game);

  /// Creates a simple binding from a raw [control].
  ///
  /// * [control]: The raw control to bind to.
  const factory InputBinding(InputControl control) = SimpleInputBinding;

  /// Creates a binding from a specific keyboard [key].
  ///
  /// * [key]: The logical keyboard key.
  const factory InputBinding.key(LogicalKeyboardKey key) = KeyInputBinding;

  /// Creates a 2D composite binding from four directional bindings.
  ///
  /// * [up]: The binding for the upward direction.
  /// * [down]: The binding for the downward direction.
  /// * [left]: The binding for the leftward direction.
  /// * [right]: The binding for the rightward direction.
  const factory InputBinding.composite({
    required InputBinding up,
    required InputBinding down,
    required InputBinding left,
    required InputBinding right,
  }) = CompositeBinding;
}

/// The runtime instance of an [InputBinding].
///
/// [BindingState] maintains the connection between a declarative binding
/// definition and the live [InputControl] instances in the engine. It provides
/// a unified interface for reading state regardless of the binding's
/// complexity.
///
/// ```dart
/// void checkBinding(BindingState state) {
///   if (state.wasPressedThisFrame) {
///     print('Binding activated!');
///   }
/// }
/// ```
///
/// See also:
/// * [InputBinding], the declarative definition for this state.
/// * [InputAction], which manages a collection of these states.
abstract class BindingState {
  /// The [GameEngine] this state is associated with.
  ///
  /// This allows the state to query global engine systems during evaluation.
  final GameEngine game;

  /// Creates a new binding state.
  ///
  /// * [game]: The game engine instance.
  BindingState(this.game);

  /// Reads the current raw value of the binding.
  ///
  /// This extracts the live data from all underlying active controls.
  Object? read();

  /// The normalized magnitude of the binding's current value.
  ///
  /// This is used to determine how strongly the input is being actuated.
  double get magnitude;

  /// Whether any part of the binding is currently pressed.
  ///
  /// This evaluates to true if the input threshold is met by active controls.
  bool get isPressed;

  /// The specific input control currently driving this binding state.
  ///
  /// This provides exact hardware attribution for the action.
  InputControl? get activeControl;

  /// Whether any part of the binding was released during the current frame.
  ///
  /// This is used for input events that trigger strictly on release.
  bool get wasReleasedThisFrame;

  /// Whether any part of the binding was released during the current dynamic update.
  ///
  /// This provides sub-frame synchronization for fixed-timestep physics.
  bool get wasReleasedThisDynamicUpdate;

  /// Whether any part of the binding was pressed during the current frame.
  ///
  /// This is used for input events that trigger strictly on initial press.
  bool get wasPressedThisFrame;

  /// Whether any part of the binding was pressed during the current dynamic update.
  ///
  /// This provides sub-frame synchronization for fixed-timestep physics.
  bool get wasPressedThisDynamicUpdate;

  /// Attempts to read the current value as type [T], returning null on failure.
  ///
  /// * [T]: The expected type of the input value.
  T? asValue<T>() {
    final val = read();
    try {
      return val as T;
    } catch (_) {
      return null;
    }
  }
}

/// A binding that maps directly to a single [InputControl].
///
/// This provides a 1:1 mapping between a raw hardware control and an [InputAction].
///
/// ```dart
/// void testSimpleBinding(GameEngine game) {
///   final binding = SimpleInputBinding(ButtonControl(game));
/// }
/// ```
///
/// See also:
/// * [InputBinding], the base class.
class SimpleInputBinding extends InputBinding {
  /// The control that this binding is mapped to.
  ///
  /// This control provides the underlying state for the binding.
  final InputControl control;

  /// Creates a simple binding for the provided [control].
  ///
  /// * [control]: The control to bind to.
  const SimpleInputBinding(this.control) : super._();

  @override
  BindingState createState(GameEngine game) =>
      SimpleBindingState(game, control);

  @override
  bool isPressed(GameEngine game) => control.isPressed;
  @override
  bool wasPressedThisFrame(GameEngine game) => control.wasPressedThisFrame;
  @override
  bool wasReleasedThisFrame(GameEngine game) => control.wasReleasedThisFrame;
  @override
  double magnitude(GameEngine game) => control.magnitude;
  @override
  T readValue<T>(GameEngine game) => control.value is T
      ? control.value as T
      : InputSystem.getDefaultValue<T>();
}

/// The runtime state for a [SimpleInputBinding].
///
/// This evaluates the live value of the associated control.
///
/// ```dart
/// void testSimpleState(GameEngine game, InputControl control) {
///   final state = SimpleBindingState(game, control);
/// }
/// ```
///
/// See also:
/// * [SimpleInputBinding], the declarative definition.
class SimpleBindingState extends BindingState {
  /// The control providing the input for this state.
  ///
  /// This control is evaluated during each frame to update the binding state.
  final InputControl control;

  /// Creates a simple binding state for the provided [game] and [control].
  ///
  /// * [game]: The game engine instance.
  /// * [control]: The control providing the input.
  SimpleBindingState(super.game, this.control);

  @override
  Object? read() => control.value;
  @override
  double get magnitude => control.magnitude;
  @override
  bool get isPressed => control.isPressed;
  @override
  InputControl? get activeControl => isPressed ? control : null;
  @override
  bool get wasReleasedThisFrame => control.wasReleasedThisFrame;
  @override
  bool get wasReleasedThisDynamicUpdate =>
      control.lastUpdateReleased ==
      game.getSystem<InputSystem>()?.dynamicUpdateCount;
  @override
  bool get wasPressedThisFrame => control.wasPressedThisFrame;
  @override
  bool get wasPressedThisDynamicUpdate =>
      control.lastUpdatePressed ==
      game.getSystem<InputSystem>()?.dynamicUpdateCount;
}

/// A binding that maps to a specific [LogicalKeyboardKey].
///
/// This allows declarative mapping of keyboard input to game actions.
///
/// ```dart
/// import 'package:flutter/services.dart';
/// void configureKey() {
///   final jump = InputBinding.key(LogicalKeyboardKey.space);
/// }
/// ```
///
/// See also:
/// * [InputBinding], the base class.
class KeyInputBinding extends InputBinding {
  /// The keyboard key that this binding is mapped to.
  ///
  /// This key's state is queried from the engine's keyboard system.
  final LogicalKeyboardKey key;

  /// Creates a key binding for the provided [key].
  ///
  /// * [key]: The logical keyboard key.
  const KeyInputBinding(this.key) : super._();

  @override
  BindingState createState(GameEngine game) => KeyBindingState(game, key);

  @override
  bool isPressed(GameEngine game) =>
      game.getSystem<InputSystem>()?.keyboard[key].isPressed ?? false;
  @override
  bool wasPressedThisFrame(GameEngine game) =>
      game.getSystem<InputSystem>()?.keyboard[key].wasPressedThisFrame ?? false;
  @override
  bool wasReleasedThisFrame(GameEngine game) =>
      game.getSystem<InputSystem>()?.keyboard[key].wasReleasedThisFrame ??
      false;
  @override
  double magnitude(GameEngine game) =>
      game.getSystem<InputSystem>()?.keyboard[key].magnitude ?? 0.0;
  @override
  T readValue<T>(GameEngine game) {
    final control = game.getSystem<InputSystem>()?.keyboard[key];
    return control?.value is T
        ? control!.value as T
        : InputSystem.getDefaultValue<T>();
  }
}

/// The runtime state for a [KeyInputBinding].
///
/// This monitors the engine's keyboard state for the specified key.
///
/// ```dart
/// import 'package:flutter/services.dart';
/// void testKeyState(GameEngine game) {
///   final state = KeyBindingState(game, LogicalKeyboardKey.space);
/// }
/// ```
///
/// See also:
/// * [KeyInputBinding], the declarative definition.
class KeyBindingState extends BindingState {
  /// The keyboard key being tracked.
  ///
  /// The state of this key determines if the binding is considered pressed.
  final LogicalKeyboardKey key;
  ButtonControl? _control;

  /// Creates a key binding state for the provided [game] and [key].
  ///
  /// * [game]: The game engine instance.
  /// * [key]: The keyboard key to track.
  KeyBindingState(super.game, this.key) {
    _control = game.getSystem<InputSystem>()?.keyboard[key];
  }

  @override
  Object? read() => _control?.value ?? false;
  @override
  double get magnitude => (_control?.value ?? false) ? 1.0 : 0.0;
  @override
  bool get isPressed => _control?.isPressed ?? false;
  @override
  InputControl? get activeControl =>
      (_control?.isPressed ?? false) ? _control : null;
  @override
  bool get wasReleasedThisFrame => _control?.wasReleasedThisFrame ?? false;
  @override
  bool get wasReleasedThisDynamicUpdate =>
      _control?.lastUpdateReleased ==
      game.getSystem<InputSystem>()?.dynamicUpdateCount;
  @override
  bool get wasPressedThisFrame => _control?.wasPressedThisFrame ?? false;
  @override
  bool get wasPressedThisDynamicUpdate =>
      _control?.lastUpdatePressed ==
      game.getSystem<InputSystem>()?.dynamicUpdateCount;
}

/// A binding that combines four directional inputs into a single 2D vector.
///
/// This is commonly used for WASD or arrow key movement, allowing the engine
/// to calculate a normalized direction vector and magnitude from discrete
/// button presses.
///
/// ```dart
/// import 'package:flutter/services.dart';
/// void configureComposite() {
///   final moveBinding = InputBinding.composite(
///     up: InputBinding.key(LogicalKeyboardKey.keyW),
///     down: InputBinding.key(LogicalKeyboardKey.keyS),
///     left: InputBinding.key(LogicalKeyboardKey.keyA),
///     right: InputBinding.key(LogicalKeyboardKey.keyD),
///   );
/// }
/// ```
///
/// See also:
/// * [InputBinding], the base class.
class CompositeBinding extends InputBinding {
  /// The binding for the upward direction.
  ///
  /// When active, this contributes a positive Y value to the final vector.
  final InputBinding up;

  /// The binding for the downward direction.
  ///
  /// When active, this contributes a negative Y value to the final vector.
  final InputBinding down;

  /// The binding for the leftward direction.
  ///
  /// When active, this contributes a negative X value to the final vector.
  final InputBinding left;

  /// The binding for the rightward direction.
  ///
  /// When active, this contributes a positive X value to the final vector.
  final InputBinding right;

  /// Creates a composite binding from four directional inputs.
  ///
  /// * [up]: The binding for the upward direction.
  /// * [down]: The binding for the downward direction.
  /// * [left]: The binding for the leftward direction.
  /// * [right]: The binding for the rightward direction.
  const CompositeBinding({
    required this.up,
    required this.down,
    required this.left,
    required this.right,
  }) : super._();

  @override
  BindingState createState(GameEngine game) => CompositeBindingState(
    game,
    up.createState(game),
    down.createState(game),
    left.createState(game),
    right.createState(game),
  );

  @override
  bool isPressed(GameEngine game) =>
      up.isPressed(game) ||
      down.isPressed(game) ||
      left.isPressed(game) ||
      right.isPressed(game);
  @override
  bool wasPressedThisFrame(GameEngine game) =>
      up.wasPressedThisFrame(game) ||
      down.wasPressedThisFrame(game) ||
      left.wasPressedThisFrame(game) ||
      right.wasPressedThisFrame(game);
  @override
  bool wasReleasedThisFrame(GameEngine game) =>
      up.wasReleasedThisFrame(game) ||
      down.wasReleasedThisFrame(game) ||
      left.wasReleasedThisFrame(game) ||
      right.wasReleasedThisFrame(game);
  @override
  double magnitude(GameEngine game) {
    final u = up.magnitude(game);
    final d = down.magnitude(game);
    final l = left.magnitude(game);
    final r = right.magnitude(game);
    return Vector2(r - l, d - u).length.clamp(0.0, 1.0);
  }

  @override
  T readValue<T>(GameEngine game) {
    if (T == Vector2) {
      final u = up.magnitude(game);
      final d = down.magnitude(game);
      final l = left.magnitude(game);
      final r = right.magnitude(game);
      return Vector2(r - l, d - u) as T;
    }
    return InputSystem.getDefaultValue<T>();
  }
}

/// The runtime state for a [CompositeBinding].
///
/// This aggregates the states of four directional bindings into a single 2D vector.
///
/// ```dart
/// void testCompositeState(GameEngine game, BindingState up, BindingState down, BindingState left, BindingState right) {
///   final state = CompositeBindingState(game, up, down, left, right);
/// }
/// ```
///
/// See also:
/// * [CompositeBinding], the declarative definition.
class CompositeBindingState extends BindingState {
  /// The runtime state for the upward direction.
  ///
  /// When active, this contributes a positive Y value to the final vector.
  final BindingState up;

  /// The runtime state for the downward direction.
  ///
  /// When active, this contributes a negative Y value to the final vector.
  final BindingState down;

  /// The runtime state for the leftward direction.
  ///
  /// When active, this contributes a negative X value to the final vector.
  final BindingState left;

  /// The runtime state for the rightward direction.
  ///
  /// When active, this contributes a positive X value to the final vector.
  final BindingState right;

  /// Creates a composite binding state for the provided [game] and directional states.
  ///
  /// * [game]: The game engine instance.
  /// * [up]: The runtime state for the upward direction.
  /// * [down]: The runtime state for the downward direction.
  /// * [left]: The runtime state for the leftward direction.
  /// * [right]: The runtime state for the rightward direction.
  CompositeBindingState(super.game, this.up, this.down, this.left, this.right);

  @override
  Object? read() {
    double x = 0, y = 0;
    if (up.isPressed) y += 1;
    if (down.isPressed) y -= 1;
    if (left.isPressed) x -= 1;
    if (right.isPressed) x += 1;
    return Vector2(x, y);
  }

  @override
  double get magnitude => (read() as Vector2).length;
  @override
  bool get isPressed => magnitude > 0;
  @override
  InputControl? get activeControl {
    return up.activeControl ??
        down.activeControl ??
        left.activeControl ??
        right.activeControl;
  }

  @override
  bool get wasReleasedThisFrame =>
      up.wasReleasedThisFrame ||
      down.wasReleasedThisFrame ||
      left.wasReleasedThisFrame ||
      right.wasReleasedThisFrame;
  @override
  bool get wasReleasedThisDynamicUpdate =>
      up.wasReleasedThisDynamicUpdate ||
      down.wasReleasedThisDynamicUpdate ||
      left.wasReleasedThisDynamicUpdate ||
      right.wasReleasedThisDynamicUpdate;
  @override
  bool get wasPressedThisFrame =>
      up.wasPressedThisFrame ||
      down.wasPressedThisFrame ||
      left.wasPressedThisFrame ||
      right.wasPressedThisFrame;
  @override
  bool get wasPressedThisDynamicUpdate =>
      up.wasPressedThisDynamicUpdate ||
      down.wasPressedThisDynamicUpdate ||
      left.wasPressedThisDynamicUpdate ||
      right.wasPressedThisDynamicUpdate;
}

/// A component that translates physical input events into logical game actions.
///
/// [InputAction] is the primary way for developers to handle player input.
/// It provides a high-level abstraction over raw hardware events, allowing
/// for declarative binding configurations, phase-based lifecycle management
/// (started, performed, canceled), and event-driven callbacks.
///
/// ```dart
/// void setupJump(Component host) {
///   host.addComponent(InputAction()
///     ..bindings = [Keyboard.space]
///     ..performed += (ctx) => print('Jump!'));
/// }
/// ```
///
/// See also:
/// * [InputBinding], which defines the mappings for this action.
/// * [InputSystem], which processes actions during the engine update.
/// * [CallbackContext], the data provided to action callbacks.
class InputAction extends Behavior with LifecycleListener, MultiComponent {
  @override
  String name = '';

  /// The type of input this action represents.
  ///
  /// This determines how the action transitions between phases and how
  /// it processes values from its bindings.
  InputActionType type = InputActionType.button;

  List<InputBinding> _bindings = [];

  /// The list of bindings associated with this action.
  ///
  /// When bindings are updated, the action will automatically recreate its
  /// runtime states to reflect the new configuration.
  List<InputBinding> get bindings => _bindings;

  /// Sets the bindings for this action.
  ///
  /// This automatically recreates the runtime states to reflect the new configuration.
  ///
  /// * [value]: The list of bindings to associate with this action.
  set bindings(List<InputBinding> value) {
    _bindings = value;
    if (isAttached) {
      _recreateRuntimeStates();
    }
  }

  final List<BindingState> _runtimeStates = [];

  bool _enabled = true;
  InputActionPhase _phase = InputActionPhase.waiting;
  InputControl? _activeControl;

  int _lastUpdateStarted = -1;
  int _lastUpdatePerformed = -1;
  int _lastUpdateCanceled = -1;
  int _lastFrameStarted = -1;
  int _lastFramePerformed = -1;
  int _lastFrameCanceled = -1;

  final InputEvent _started = InputEvent();
  final InputEvent _performed = InputEvent();
  final InputEvent _canceled = InputEvent();

  /// Triggered when the action enters the [InputActionPhase.started] phase.
  ///
  /// Use the `+=` operator to add a callback that executes when this event fires.
  InputEvent get started => _started;

  /// Triggered when the action enters the [InputActionPhase.performed] phase.
  ///
  /// Use the `+=` operator to add a callback that executes when this event fires.
  InputEvent get performed => _performed;

  /// Triggered when the action enters the [InputActionPhase.canceled] phase.
  ///
  /// Use the `+=` operator to add a callback that executes when this event fires.
  InputEvent get canceled => _canceled;

  /// Internal setter for the started event.
  ///
  /// This must exist to satisfy Dart's `+=` operator overloading requirements,
  /// but performs no internal state changes as the event manages its own listeners.
  ///
  /// * [value]: The event to set (ignored).
  set started(InputEvent value) {}

  /// Internal setter for the performed event.
  ///
  /// This must exist to satisfy Dart's `+=` operator overloading requirements,
  /// but performs no internal state changes as the event manages its own listeners.
  ///
  /// * [value]: The event to set (ignored).
  set performed(InputEvent value) {}

  /// Internal setter for the canceled event.
  ///
  /// This must exist to satisfy Dart's `+=` operator overloading requirements,
  /// but performs no internal state changes as the event manages its own listeners.
  ///
  /// * [value]: The event to set (ignored).
  set canceled(InputEvent value) {}

  /// Creates a new input action.
  ///
  /// This action starts with no bindings and is enabled by default.
  InputAction();

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      _phase = InputActionPhase.waiting;
    }
    if (isAttached) {
      if (value) {
        game.getSystem<InputSystem>()?._registerAction(this);
      } else {
        game.getSystem<InputSystem>()?._unregisterAction(this);
      }
    }
  }

  @override
  void onMounted() {
    _recreateRuntimeStates();
    if (enabled) {
      game.getSystem<InputSystem>()?._registerAction(this);
    }
  }

  void _recreateRuntimeStates() {
    _runtimeStates.clear();
    for (var b in _bindings) {
      _runtimeStates.add(b.createState(game));
    }
  }

  @override
  void onUnmounted() {
    if (enabled) {
      game.getSystem<InputSystem>()?._unregisterAction(this);
    }
  }

  /// The current lifecycle phase of the action.
  ///
  /// This helps determine the state of an interaction, such as whether a button is currently held down.
  InputActionPhase get phase => _phase;

  /// Whether the action was performed during the current frame.
  ///
  /// This is a convenience alias for [wasPerformedThisFrame].
  bool get triggered => wasPerformedThisFrame;

  /// Whether the action is currently in an active phase (started or performed).
  ///
  /// This allows querying for continuous input states like holding a button.
  bool get inProgress =>
      _phase == InputActionPhase.started ||
      _phase == InputActionPhase.performed;

  /// The specific input control currently driving this action.
  ///
  /// This helps identify which device (e.g., keyboard vs gamepad) triggered the event.
  InputControl? get activeControl => _activeControl;

  /// Whether the action entered the started phase during the current frame.
  ///
  /// This is used to query input state synchronously during the render loop.
  bool get wasPressedThisFrame =>
      _lastFrameStarted == game.getSystem<TickerState>()?.frameCount;

  /// Whether the action entered the performed phase during the current frame.
  ///
  /// This is used to query input state synchronously during the render loop.
  bool get wasPerformedThisFrame =>
      _lastFramePerformed == game.getSystem<TickerState>()?.frameCount;

  /// Whether the action entered the canceled phase during the current frame.
  ///
  /// This is used to query input state synchronously during the render loop.
  bool get wasCanceledThisFrame =>
      _lastFrameCanceled == game.getSystem<TickerState>()?.frameCount;

  /// Whether the action was completed during the current frame.
  ///
  /// This is an alias for [wasCanceledThisFrame], indicating the end of the interaction.
  bool get wasCompletedThisFrame => wasCanceledThisFrame;

  /// Whether any of the action's bindings were released during the current frame.
  ///
  /// This is used to query input state synchronously during the render loop.
  bool get wasReleasedThisFrame {
    for (var b in _runtimeStates) {
      if (b.wasReleasedThisFrame) return true;
    }
    return false;
  }

  /// Whether the action entered the started phase during the current dynamic update.
  ///
  /// This provides sub-frame synchronization for fixed-timestep physics.
  bool get wasPressedThisDynamicUpdate =>
      _lastUpdateStarted == game.getSystem<InputSystem>()?.dynamicUpdateCount;

  /// Whether the action entered the performed phase during the current dynamic update.
  ///
  /// This provides sub-frame synchronization for fixed-timestep physics.
  bool get wasPerformedThisDynamicUpdate =>
      _lastUpdatePerformed == game.getSystem<InputSystem>()?.dynamicUpdateCount;

  /// Whether the action entered the canceled phase during the current dynamic update.
  ///
  /// This provides sub-frame synchronization for fixed-timestep physics.
  bool get wasCanceledThisDynamicUpdate =>
      _lastUpdateCanceled == game.getSystem<InputSystem>()?.dynamicUpdateCount;

  /// Whether the action was completed during the current dynamic update.
  ///
  /// This provides sub-frame synchronization for fixed-timestep physics.
  bool get wasCompletedThisDynamicUpdate => wasCanceledThisDynamicUpdate;

  /// Whether any of the action's bindings were released during the current dynamic update.
  ///
  /// This provides sub-frame synchronization for fixed-timestep physics.
  bool get wasReleasedThisDynamicUpdate {
    for (var b in _runtimeStates) {
      if (b.wasReleasedThisDynamicUpdate) return true;
    }
    return false;
  }

  /// Enables the action, allowing it to process input and trigger events.
  ///
  /// This is useful for toggling specific player abilities or UI contexts.
  void enable() => enabled = true;

  /// Disables the action, preventing it from processing input.
  ///
  /// This resets the action's phase to waiting and cancels any ongoing interactions.
  void disable() {
    enabled = false;
    _phase = InputActionPhase.waiting;
  }

  /// Reads the current value of the action as type [T].
  ///
  /// This will check all active bindings and return the first valid value
  /// found, or a default value if no bindings are active or the action
  /// is disabled.
  ///
  /// * [T]: The expected type of the input value.
  T readValue<T>() {
    if (!_enabled) return InputSystem.getDefaultValue<T>();
    for (var state in _runtimeStates) {
      final val = state.asValue<T>();
      if (val != null) return val;
    }
    return InputSystem.getDefaultValue<T>();
  }

  double _getMagnitude() {
    double maxMag = 0;
    for (var b in _runtimeStates) {
      final mag = b.magnitude;
      if (mag > maxMag) maxMag = mag;
    }
    return maxMag;
  }

  void _updatePhase() {
    bool currentlyPressed = false;
    InputControl? drivingControl;

    for (var b in _runtimeStates) {
      if (b.isPressed) {
        currentlyPressed = true;
        drivingControl = b.activeControl;
        break;
      }
    }

    final updateCount = game.getSystem<InputSystem>()?.dynamicUpdateCount ?? -1;
    final currentFrame = game.getSystem<TickerState>()?.frameCount ?? -1;

    if (_phase == InputActionPhase.waiting && currentlyPressed) {
      _phase = InputActionPhase.started;
      _activeControl = drivingControl;
      _lastUpdateStarted = updateCount;
      _lastFrameStarted = currentFrame;
      started.invoke(CallbackContext(this, _phase));

      if (type == InputActionType.button) {
        _phase = InputActionPhase.performed;
        _lastUpdatePerformed = updateCount;
        _lastFramePerformed = currentFrame;
        performed.invoke(CallbackContext(this, _phase));
      }
    } else if (_phase == InputActionPhase.started &&
        type == InputActionType.value) {
      _phase = InputActionPhase.performed;
      _lastUpdatePerformed = updateCount;
      _lastFramePerformed = currentFrame;
      performed.invoke(CallbackContext(this, _phase));
    } else if (_phase == InputActionPhase.performed) {
      if (!currentlyPressed) {
        _phase = InputActionPhase.canceled;
        _lastUpdateCanceled = updateCount;
        _lastFrameCanceled = currentFrame;
        canceled.invoke(CallbackContext(this, _phase));
        _phase = InputActionPhase.waiting;
        _activeControl = null;
      } else {
        _activeControl = drivingControl;
        if (type == InputActionType.value) {
          _lastUpdatePerformed = updateCount;
          _lastFramePerformed = currentFrame;
        }
      }
    }
  }

  /// Disposes of the action and its internal events.
  ///
  /// This must be called when the action is no longer needed to free resources and prevent memory leaks.
  void dispose() {
    disable();
    _started.dispose();
    _performed.dispose();
    _canceled.dispose();
  }
}
