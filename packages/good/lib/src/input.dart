import 'package:meta/meta.dart';

import 'package:good/src/declare.dart';
import 'package:good/src/input/gamepad.dart';
import 'package:good/src/input/input_binding.dart';
import 'package:good/src/input/input_state.dart';
import 'package:good/src/triple_buffer.dart';

/// One declared **action**: a named thing the player can do, its current
/// value, its edges, and the binding that produces them.
///
/// ```dart
/// class PlayerActionSystem extends GameSystem with FixedTickable {
///   late final Input<Vector2> movement;
///   late final Input<bool> triggerSkill;
///
///   @override
///   void describeInputs(InputDescriptor input) {
///     super.describeInputs(input);
///     movement = input.has<Vector2>(const Vec2Binding(up: .w, down: .s, left: .a, right: .d));
///     triggerSkill = input.has<bool>(const TriggerBinding(.spacebar));
///   }
///
///   @override
///   void onMounted() {
///     triggerSkill.pressed += (event) => castSkill();
///     triggerSkill.released += (event) => stopCasting();
///   }
///
///   @override
///   void onFixedUpdate() {
///     transform.transformOffsetX[player] += movement.value.x * speed;
///     if (triggerSkill.wasPressedThisFrame) castSkill();
///   }
/// }
/// ```
///
/// This is the typed-handle rule applied to input: `describeInputs` hands back
/// a typed handle you keep in a `late final` field, exactly like a
/// `StateChannel` and `describeBuffers`' `BufferHandle`.
/// There is no `getAction('jump')`, so there is no string to misspell and
/// nothing to search at use time.
///
/// # Poll or subscribe - both, and they answer different questions
///
/// [value], [wasPressedThisFrame] and [wasReleasedThisFrame] are for a
/// system that is already running per tick and just wants to know the state.
/// [pressed] and [released] are for everything else: code that should run
/// *because* the player did something, once, at the moment they did it.
///
/// They are two streams and not one "changed" callback. A single stream would
/// hand every listener the job of working out which edge it just saw - and a
/// `Vec2Binding` changes value constantly while held without either edge
/// happening, so "changed" is not even a useful proxy.
///
/// # A listener is an instance method, and it is bound after construction
///
/// The declaration and the subscription are two lines and two moments, and
/// they cannot be folded into one. `final fire = Input.of(binding) + onFire`
/// is the shape that keeps being proposed (#221); Dart refuses every spelling
/// of it, because an instance member cannot be named from a field
/// initialiser:
///
/// - `+ onFire`, a tear-off, is `implicit_this_reference_in_initializer`;
/// - `+ ((event) => onFire(event))` is the *same* error - the restriction
///   reaches inside the function literal, so a closure does not defer the
///   reference;
/// - `+ ((event) => this.onFire(event))` is `invalid_reference_to_this`.
///
/// What does compile in that position is a `static` method, a top-level
/// function, or a closure that captures nothing - and all three are the same
/// answer wearing three hats: the callback cannot reach the object that
/// declared the action. That is almost always what an input handler wants,
/// so the field-initialiser form buys one line and gives up the receiver.
///
/// `late final fire = Input.of(...) + onFire` does compile, and is the trap
/// [Input.of] already names: the initialiser runs on the first *read*, by
/// which point boot has sealed the registry.
///
/// Two sites do work, because in both of them `this` is in scope:
///
/// ```dart
/// class PlayerSystem extends GameSystem {
///   final fire = Input.of(.trigger(.spacebar));
///
///   new() {
///     fire.pressed += onFire;      // the constructor body - prefer this
///   }
///
///   void onFire(InputEvent<bool> event) => cast();
/// }
/// ```
///
/// The constructor body is the one to reach for: the subscription sits beside
/// the declaration, which is what the shorter form was wanted for, and it
/// needs no mixin. `onMounted` is the other, and it is **required** when the
/// action is declared in `describeInputs` instead of on a field - that makes
/// it a `late final` the constructor body cannot read yet, which throws.
///
/// Nothing about the no-closure rule forces any of this - a listener body is
/// hot, but building one at construction or at mount is boot-time work and
/// explicitly fine. It is the compiler.
///
/// # `action += listener` cannot work either, and not for that reason
///
/// The subscription is on [pressed]/[released] and not on the action itself,
/// and a `final` field is why. `a += b` is `a = a + b`, so it needs a setter;
/// an action lives in a `final` field, because the typed-handle rule is what
/// keeps anything from reassigning it. `fire += onFire` is
/// `assignment_to_final`, and adding an `operator +` to this class would not
/// change that - the analyzer reports the two independently.
///
/// [pressed] is a getter with a setter beside it for exactly this reason, so
/// `fire.pressed += onFire` compiles where `fire += onFire` cannot. It also
/// has to say *which edge*, which one operator on the action could not.
///
/// # When any of this updates
///
/// Once per fixed tick, at the top of `GameState.runFixedStep`, before
/// commands are applied and before any system runs. So every system in a tick
/// sees the same input snapshot, and a value cannot shift underneath two
/// systems in the same tick. [pressed]/[released] listeners are called from
/// there too - on the game isolate, inside the tick window, synchronously.
///
/// That also means the resolution *only happens on the copy that simulates*.
/// An action declared by a `GameSystem` is only ever reachable from there -
/// systems are constructed on that copy and nowhere else - but an action
/// declared in `Game.describeInputs` is a different matter: that pass runs on
/// both copies, so main holds its own `Input` object for it. Main's never
/// resolves. It reads its default forever, and assigning a binding through it
/// changes nothing in the simulation. Rebind on the simulating side - from a
/// system's tick, a `GameCommand`, or the `GameState` - like every other
/// gameplay mutation.
///
/// # Sub-tick presses are not captured
///
/// Edges are computed by diffing the raw device state against the previous
/// resolution, so a key that goes down *and* back up between two fixed ticks
/// is never seen. At a 60Hz tick that is a press shorter than ~16ms, which is
/// shorter than a human press; a synthetic input source that can produce one (a
/// replay, a bot) should hold the key for at least a tick.
abstract class Input<T> {
  /// This action's value as of the most recent resolution.
  ///
  /// **Read-only, and do not hold it past the tick.** For a `T` with
  /// reference semantics - `Vector2` - this returns the *one* instance this
  /// action owns and mutates in place on every resolution, not a fresh copy
  /// per read (a fresh one would be a heap allocation per read per tick,
  /// the no-allocation rule). Storing it in a field means storing something that
  /// silently changes under you next tick; copy the numbers out, or
  /// `Vector2.copy(movement.value)` if you really need to keep one.
  ///
  /// Throws a [StateError] if the action has never resolved and has no
  /// default anywhere - see [InputDescriptor.has].
  T get value;

  /// Whether this action became held on the most recent resolution - true on
  /// exactly the one tick the edge landed on, false again on the next even if
  /// the key is still down.
  bool get wasPressedThisFrame;

  /// Whether this action stopped being held on the most recent resolution.
  /// The mirror of [wasPressedThisFrame], and never true on the same
  /// resolution as it.
  bool get wasReleasedThisFrame;

  /// What currently produces this action's value, or null if it is unbound.
  ///
  /// An unbound action is a legitimate, declared state - not an error and not
  /// a missing declaration. It resolves to its default and fires nothing,
  /// which is what an action the player has not assigned a key to *should*
  /// do.
  InputBinding<T>? get binding;

  /// Rebinds this action. Takes effect on the next resolution - i.e. at the
  /// top of the next fixed tick, so a rebind never changes what a tick
  /// already in progress sees.
  ///
  /// ```dart
  /// triggerSkill.binding = const TriggerBinding(.enter);
  /// ```
  ///
  /// Rebinding while the old binding is held produces a [released] on the
  /// next resolution (unless the new binding happens to be held too), so
  /// every [pressed] stays paired. Unbinding entirely does not: an unbound
  /// action fires nothing, by definition, so a [pressed] outstanding at that
  /// moment goes unanswered. If that matters, unbind from the `released`
  /// handler.
  set binding(InputBinding<T>? binding);

  /// Fires on the resolution where this action becomes held.
  ///
  /// ```dart
  /// triggerSkill.pressed += (event) => castSkill();
  /// ```
  ///
  /// `+=` is the subscription: [InputEventStream.operator +] appends and
  /// returns the same stream, which the setter then accepts back.
  ///
  /// Subscribe from a constructor body or from `onMounted`, **not from a
  /// tick** - `+=` in `onFixedUpdate` adds a subscriber sixty times a second.
  /// A `GameSystem` gets `onMounted` by mixing in
  /// `GameSystemLifecycleListener`; `GameState.mount` fires every system's
  /// `mountEvent` after the game's own `onMounted` has run.
  ///
  /// Those two are the only sites where the listener can be an ordinary
  /// instance method - see this class's doc for why the declaration itself
  /// cannot take one, and why the `+=` goes here rather than on the action.
  InputEventStream<T> get pressed;

  /// Only exists so `pressed += listener` compiles - `a.b += c` is
  /// `a.b = a.b + c`, so a stream needs a setter to assign the stream
  /// `operator +` just handed back. Assigning any *other* stream is a
  /// programmer error and asserts (the assert-not-print rule).
  set pressed(InputEventStream<T> stream);

  /// Fires on the resolution where this action stops being held. See
  /// [pressed].
  InputEventStream<T> get released;

  /// See [pressed]'s setter.
  set released(InputEventStream<T> stream);

  /// Declares an action on the field that holds it:
  ///
  /// ```dart
  /// class PlayerSystem extends GameSystem with FixedTickable {
  ///   final fire = Input.of(.trigger(.spacebar));
  ///   final movement = Input.of(.vec2(up: .w, down: .s, left: .a, right: .d));
  ///   final attack = Input.of(
  ///     .composite(.trigger(.leftMouseButton), .trigger(.spacebar)),
  ///   );
  /// }
  /// ```
  ///
  /// [binding] is statically an `InputBinding<V>?`, so a **dot shorthand**
  /// resolves against it: `InputBinding` carries one static per concrete
  /// binding - `.trigger`, `.vec2`, `.axis`, `.stick`, `.mouse`, `.contact`,
  /// `.composite`, `.compositeFromList` - and `V` is inferred from the one
  /// you name, so no type argument is written here at all. The long form
  /// (`const TriggerBinding(.spacebar)`) still works and is what a
  /// `static const` table of defaults wants, since a shorthand call is a
  /// method call and cannot be `const`.
  ///
  /// The same action [InputDescriptor.has] declares in a `describeInputs`
  /// body - on a `Game` or on a `GameSystem` - said where it is read. The
  /// arguments are that method's, positionally and with the same meaning:
  /// [binding] is optional and an action without one is *unbound* until
  /// something assigns `action.binding`; [defaultValue] is this action's own
  /// fallback and beats the type-level one from
  /// [InputDescriptor.hasDefaultValue].
  ///
  /// `V` is inferred from [binding]. An unbound action has nothing to infer
  /// from, so it is written: `Input.of<bool>()`.
  ///
  /// # A Game or a GameSystem
  ///
  /// Both are framework-built - `Game.start(MyGame.new)` and
  /// `descriptor.has(PlayerSystem.new)` - so in both there is a constructor
  /// call for the registry to be open around. They declare into the same
  /// registry in the end, but not at the same moment or on the same isolate:
  /// a game's actions are declared on main, before the spawn, and ride the
  /// copy; a system's are declared on the copy that ticks. Nothing depends on
  /// the resulting numbering, which is why the two copies are allowed to
  /// disagree about it - what crosses the boundary is the fixed-size block of
  /// raw key bits, the same 16 bytes whatever a game declares.
  ///
  /// [InputDescriptor.hasDefaultValue] has no field form anywhere. It hands
  /// nothing back, so there is no field to put it on; declare it in
  /// `describeInputs`, from the `Game` or from a system.
  ///
  /// # Eager, always
  ///
  /// `late final fire = Input.of(...)` compiles and is wrong. The call runs
  /// on the first *read*, by which point boot has sealed the registry and the
  /// action is refused outright. It does not get that far:
  /// `DeclarationContext.inputs` throws first, naming the shape.
  static Input<V> of<V>([InputBinding<V>? binding, V? defaultValue]) =>
      DeclarationContext.inputs.has<V>(binding, defaultValue);
}

/// What a [pressed]/[released] listener is handed: the action's value at the
/// moment the edge landed.
///
/// # One instance per stream, reused
///
/// The engine fires these from inside the fixed tick, so a fresh event per
/// firing would be a heap allocation on the hot path - the same reason
/// `GameState` keeps one `FixedTickEvent` for every tick
/// of every system. [value] is therefore only meaningful *during* the
/// callback: keeping the event and reading it later reads whatever the next
/// edge put there.
final class InputEvent<T> {
  InputEvent._();

  late T _value;

  /// The action's value on the resolution that fired this event. For a
  /// `Vector2` action this is the same read-only, mutated-in-place instance
  /// [Input.value] returns.
  T get value => _value;
}

/// A listener on one edge of one action.
typedef InputListener<T> = void Function(InputEvent<T> event);

/// The subscribable half of [Input.pressed]/[Input.released].
///
/// Not a `Stream`: a broadcast stream allocates per event and schedules a
/// microtask per listener, which is the wrong shape for something dispatched
/// from inside a fixed tick - and it would deliver the callback *after* the
/// tick that produced it had already finished. This is a plain listener list
/// called synchronously, the same trade `Game.addTickListener` makes.
final class InputEventStream<T> {
  InputEventStream._();

  final List<InputListener<T>> _listeners = <InputListener<T>>[];

  // One event object for every firing of this stream - see InputEvent's doc.
  final InputEvent<T> _event = InputEvent<T>._();

  /// Appends [listener] and returns this stream, so that
  /// `action.pressed += listener` reads as a subscription.
  InputEventStream<T> operator +(InputListener<T> listener) {
    _listeners.add(listener);
    return this;
  }

  /// Removes [listener], the inverse of [operator +]:
  /// `action.pressed -= listener`.
  ///
  /// Compared by `==`, which is what makes this usable for the listeners
  /// that matter. Two tear-offs of the same instance method on the same
  /// receiver are `==` (never `identical`), so `fire.pressed -= onFire`
  /// removes what `fire.pressed += onFire` added even though the two
  /// expressions built different objects. Two closures written the same way
  /// are never equal, so a closure subscription can only be undone through a
  /// reference kept from the `+=`.
  InputEventStream<T> operator -(InputListener<T> listener) {
    _listeners.remove(listener);
    return this;
  }

  /// Whether anything is subscribed. Lets a caller skip work it would only
  /// do to feed a listener nobody registered.
  bool get hasListeners => _listeners.isNotEmpty;

  void _fire(T value) {
    if (_listeners.isEmpty) return;
    _event._value = value;
    for (var i = 0; i < _listeners.length; i++) {
      _listeners[i](_event);
    }
  }
}

/// Declares a game's input actions - see `Game.describeInputs` and
/// `GameSystem.describeInputs`. Same one-pass declarative shape as
/// `SystemDescriptor`/`BufferDescriptor`/`StateDescriptor`.
///
/// One descriptor is shared by every `describeInputs` pass in a boot (the
/// `Game`'s runs first, then every declared system's, in declaration order),
/// which is what lets a system register a type-level default for a `T` only
/// it uses and have the actions the `Game` declared see it.
///
/// **Not available on `SceneStruct` or `Component`**, for exactly the reason
/// a state channel is not (see `Channel`): a scene is loaded after boot, and
/// possibly several times over a run, so it can never own a stable
/// declaration index or have its declarations mirrored on the other isolate
/// copy. A scene-scoped action is declared by a `GameSystem` instead - the
/// system outlives the scene and is already where the per-tick work is.
abstract class InputDescriptor {
  /// Registers the value every action of type [T] falls back to when it has
  /// no default of its own.
  ///
  /// `Game.describeInputs` ships with `hasDefaultValue<bool>(false)`,
  /// `hasDefaultValue<Vector2>(Vector2.zero())` and an empty
  /// `PointerContacts`, so the built-in binding types work out of the box -
  /// `CursorPosition` is the exception, since a position with no pointer
  /// behind it is not a place and `MouseBinding` resolves on the first tick
  /// anyway. Declaring a `T` **twice** in one boot is an
  /// error, not a silent overwrite: two sources each believing they set the
  /// fallback for a type is a disagreement, and picking the last one to run
  /// would make the answer depend on system declaration order.
  void hasDefaultValue<T>(T value);

  /// Declares one action and returns the handle to keep in a `late final`
  /// field.
  ///
  /// [binding] is optional - an action declared without one is *unbound*: it
  /// reads its default and fires nothing until something assigns
  /// `action.binding`. That is the shape of an action whose key the player
  /// has not chosen yet, and it is a normal state, not a half-declaration.
  ///
  /// [defaultValue] is this action's own fallback, and takes precedence over
  /// the type-level one from [hasDefaultValue]. If neither exists, reading
  /// [Input.value] before the action has ever resolved throws a [StateError]
  /// naming the action. The engine does **not** infer a default from [T]:
  /// zero and false are real, meaningful values to a game, and
  /// inventing one turns a forgotten declaration into a number that is
  /// quietly wrong instead of an error that says so.
  Input<T> has<T>([InputBinding<T>? binding, T? defaultValue]);
}

/// Everything the input registry needs from an action without knowing its
/// `T` - the same type-erasure trick `_ChannelSlot` uses for state channels,
/// and for the same reason: sealing and resolving are plumbing that has no
/// business laundering the value type.
abstract class _ActionSlot {
  /// Resolves each action's own default now that every source has had its
  /// chance to register one, and gives it the storage its binding wants.
  void seal(InputRegistry registry);

  void resolve(InputState state);
}

/// The one [InputDescriptor] implementation, and the owner of everything the
/// input system allocates: the declared actions, the type-level defaults, the
/// cross-isolate raw-state buffer, and the read/write ends over it.
///
/// Internal: a `Game` owns exactly one of these and drives it through boot,
/// each tick, and shutdown. Users see [InputDescriptor] and [Input].
@internal
final class InputRegistry implements InputDescriptor {
  final List<_ActionSlot> _actions = <_ActionSlot>[];

  /// Fallback values by `T`. A `Map<Type, ...>` searched at *declare* time
  /// only - actions carry their resolved default in a field from [seal]
  /// onwards, so nothing looks anything up per tick.
  final Map<Type, Object?> _typeDefaults = <Type, Object?>{};

  /// The reader's window onto the raw block, re-pointed once per fixed tick.
  /// One instance for the whole game: every action resolves through the same
  /// snapshot, which is what makes a tick's input coherent.
  ///
  /// Built on first use and not in the field initialiser, because its size
  /// depends on [maxContacts] and the registry is opened before the `Game`
  /// that answers for it exists - the declaration windows have to be open
  /// while the game's fields initialise. See `Game._construct`.
  InputState? _sizedState;

  InputState get _state => _sizedState ??= InputState(_maxContacts);

  int _maxContacts = 1;

  /// How many contacts the raw block carries, from `Game.maxPointerContacts`.
  ///
  /// Written once, by `Game._construct`, before anything reads or allocates
  /// the block. Refuses a later change instead of resizing: the buffer is
  /// allocated from this figure and both isolate copies index it by the same
  /// offsets, so a second answer would leave one copy reading a table that
  /// starts somewhere else.
  int get maxContacts => _maxContacts;

  set maxContacts(int value) {
    if (value < 1) {
      throw ArgumentError.value(
        value,
        'maxPointerContacts',
        'a game has room for at least one contact - a block with none can '
            'never report a press, and Game.maxPointerContacts is what sizes '
            'it. Override it with the number of fingers the game reads at '
            'once.',
      );
    }
    if (_sizedState != null || _buffer != null || _sealed) {
      throw StateError(
        'the contact count changed after the input block was sized. '
        'Game.maxPointerContacts is read once, while the game is being '
        'constructed, because the block is allocated from it and both '
        'isolate copies index the table by offsets computed from it. Make it '
        'a constant getter, not something that can answer twice.',
      );
    }
    _maxContacts = value;
  }

  /// The snapshot every action resolves through. Exposed for the two facts
  /// on it that are not input actions and that nothing binds to - the view's
  /// size (see `Game.viewWidth`) - so nothing has to copy them into a second
  /// place that could disagree with this one.
  InputState get state => _state;

  TripleBuffer? _buffer;
  InputDevice? _device;
  GamepadCollector? _gamepads;
  bool _sealed = false;

  /// Whose `describeInputs` is currently running, for diagnostics. Set by
  /// `Game._boot` before each call; a plain label, not the object, because
  /// that is all an error message wants.
  String _source = 'Game';

  int get actionCount => _actions.length;

  /// The write end, on the copy that has a Flutter engine attached; null on
  /// the game-isolate copy, which reads input and never produces it.
  InputDevice? get device => _device;

  /// The gamepad reader, alive exactly as long as [device] is - it writes
  /// through it. Null on the game-isolate copy and before `start()`, for the
  /// same reason the device is.
  GamepadCollector? get gamepads => _gamepads;

  /// The live storage, non-null on the simulating copy from `Game._boot`
  /// onwards - what the input buffer's announcement reads addresses off.
  TripleBuffer? get buffer => _buffer;

  set source(String source) => _source = source;

  /// What [source] currently reads, so `SystemDescriptor.has` can put it back
  /// after a system's constructor has run. Without the restore, a field
  /// declaration would leave the label pointing at a system that has finished
  /// declaring, and the `describeInputs` pass that follows would attribute
  /// its actions to the wrong one.
  String get currentSource => _source;

  // --- declaration --------------------------------------------------------

  @override
  void hasDefaultValue<T>(T value) {
    _checkOpen();
    if (_typeDefaults.containsKey(T)) {
      throw StateError(
        'a default value for $T is registered twice in this game\'s '
        'describeInputs passes (the second by $_source). One type has one '
        'fallback: two sources each setting it disagree about what an '
        'unbound $T action reads, and resolving that by "last one wins" '
        'would make the answer depend on system declaration order. Pass a '
        'per-action default to has<$T>() instead if only some actions want '
        'the other value.',
      );
    }
    _typeDefaults[T] = value;
  }

  @override
  Input<T> has<T>([InputBinding<T>? binding, T? defaultValue]) {
    _checkOpen();
    assert(
      null is! T,
      'Input<$T> has a nullable value type, which this system cannot '
      'represent: null is how "no default was declared" is spelled, so a '
      'null default and a missing one would be the same thing. Declare the '
      'non-nullable type.',
    );
    // Positional, because a private field's initializing formal cannot be a
    // named parameter: index, declaring source, binding, default, has-default.
    final action = _InputAction<T>(
      _actions.length,
      _source,
      binding,
      defaultValue,
      defaultValue != null,
    );
    _actions.add(action);
    return action;
  }

  void _checkOpen() {
    if (_sealed) {
      throw StateError(
        'an input action was declared after boot finished. Inputs are '
        'declared once, up front, in describeInputs - the raw device-state '
        'buffer they resolve against is allocated and announced at bring-up, '
        'and both isolate copies have to end up with the same declared set. '
        'Declare the action unbound and assign action.binding at runtime; '
        'that is what rebinding is.',
      );
    }
  }

  /// Closes the declaration window and gives every action its resolved
  /// default and its storage. Runs at the end of `Game._boot`, once every
  /// source has declared, which is the earliest point at which a
  /// type-level default registered by the *last* system is visible to an
  /// action declared by the `Game`.
  void seal() {
    for (var i = 0; i < _actions.length; i++) {
      _actions[i].seal(this);
    }
    _sealed = true;
  }

  bool hasDefaultFor(Type type) => _typeDefaults.containsKey(type);

  Object? defaultFor(Type type) => _typeDefaults[type];

  // --- storage ------------------------------------------------------------

  /// Simulating copy: allocate the raw device-state block. Nothing is seeded
  /// with a published snapshot here - the *writer* does that when the device
  /// is created, and until then an unpublished buffer reads as "every key
  /// up", which is the truth.
  void allocate() {
    _buffer = TripleBuffer(InputState.byteLengthFor(_maxContacts));
  }

  /// Handle copy: take a view over the simulating copy's allocation. The
  /// write end is built on top of it here, because this is the copy Flutter
  /// runs on and therefore the only one that can see a key event at all.
  void adopt({required int latestAddress, required List<int> slotAddresses}) {
    _buffer = TripleBuffer.fromAddresses(
      slotBytes: InputState.byteLengthFor(_maxContacts),
      latestAddress: latestAddress,
      slotAddresses: slotAddresses,
    );
  }

  /// Builds the write end. Called on whichever copy runs on the Flutter
  /// isolate: the single copy under `start(inline: true)`, or the handle copy
  /// once the game isolate has announced the buffer's address.
  void createDevice() {
    final buffer = _buffer;
    if (buffer == null) {
      throw StateError(
        'the input device was created before the raw input buffer existed - '
        'the simulating copy allocates it during boot and announces its '
        'address before start() completes.',
      );
    }
    final device = InputDevice(buffer, _maxContacts);
    _device = device;
    _gamepads = GamepadCollector(device);
  }

  /// Drops the write end without touching the storage.
  ///
  /// The spawned copy inherits main's [InputDevice] through the deep copy and
  /// must not keep it: it only ever reads input, and two live write ends on
  /// one `TripleBuffer` is precisely what that primitive forbids.
  void releaseDevice() {
    _gamepads?.detach();
    _gamepads = null;
    _device = null;
  }

  void release({required bool owned}) {
    // Detach BEFORE the storage goes. `detach` releases every occupied slot,
    // and releasing a slot publishes a button change, which writes through
    // the buffer - so disposing first lands that write on freed memory and
    // reads a garbage slot index back out of it.
    //
    // Dropped without awaiting the cancel: `release` is the teardown path
    // and the subscription's own cleanup does not need to gate a `stop()`.
    // Detaching at all matters because the stream outlives this registry.
    _gamepads?.detach();
    _gamepads = null;
    _device = null;
    if (owned) _buffer?.dispose();
    _buffer = null;
    _state.attach(null);
  }

  // --- the resolution pass ------------------------------------------------

  /// Updates every declared action from the newest published device
  /// snapshot. Called once per fixed tick, before commands and before any
  /// system runs.
  ///
  /// Hot path, and allocation-free end to end: a 40-byte copy of the snapshot,
  /// then per action a couple of virtual calls that do bit tests and (for a
  /// vector) write two doubles into storage the action already owns. No
  /// closures, no iterators, no per-tick objects (the no-allocation, hot-event
  /// and no-closure rules).
  void resolve() {
    final buffer = _buffer;
    // Copied once, not per action: every action in this tick reads the same
    // bytes, so two systems cannot disagree about what was held - and the
    // writer cannot change them underneath the tick. See `InputState`.
    _state.attach(buffer?.latestView());
    for (var i = 0; i < _actions.length; i++) {
      _actions[i].resolve(_state);
    }
  }
}

/// The one [Input] implementation - what `describeInputs` hands back.
final class _InputAction<T> implements Input<T>, _ActionSlot {
  _InputAction(
    this.index,
    this.source,
    this._binding,
    this._default,
    this._hasDefault,
  );

  /// Position in the shared declaration order, and what diagnostics name this
  /// action by together with [source]. There is no user-supplied name to use
  /// instead - the whole point of rule 6 is that the field name is the name,
  /// and a field name is not something the framework can see.
  final int index;

  /// The `runtimeType` of whatever declared this action.
  final String source;

  final InputEventStream<T> _pressed = InputEventStream<T>._();
  final InputEventStream<T> _released = InputEventStream<T>._();

  InputBinding<T>? _binding;

  /// The value this action reads when it has not resolved - its own declared
  /// default, or the type-level one, filled in at [seal].
  T? _default;
  bool _hasDefault;

  /// The instance [resolve] writes into and [value] hands out. Created once,
  /// from the binding, and never replaced while a binding exists.
  T? _storage;

  /// Whether [_storage] holds a value from an actual resolution. False for an
  /// unbound action (which reads its default) and before the first tick.
  bool _hasResolvedValue = false;

  bool _isDown = false;
  bool _wasPressed = false;
  bool _wasReleased = false;

  @override
  void seal(InputRegistry registry) {
    if (!_hasDefault && registry.hasDefaultFor(T)) {
      _default = registry.defaultFor(T) as T;
      _hasDefault = true;
    }
    final binding = _binding;
    if (binding != null) _storage ??= binding.createStorage();
  }

  @override
  void resolve(InputState state) {
    final binding = _binding;
    if (binding == null) {
      // Unbound: reads its default, fires nothing. Deliberately no synthetic
      // release even if it was held when it was unbound - see Input.binding.
      _hasResolvedValue = false;
      _isDown = false;
      _wasPressed = false;
      _wasReleased = false;
      return;
    }
    final down = binding.isActuated(state);
    // Mutually exclusive by construction, which is the "never both on one
    // resolution" guarantee: `down && !was` and `!down && was` cannot hold
    // together for any pair of bools.
    _wasPressed = down && !_isDown;
    _wasReleased = !down && _isDown;
    _isDown = down;
    final value = binding.resolve(state, _storage as T);
    _storage = value;
    _hasResolvedValue = true;
    if (_wasPressed) {
      _pressed._fire(value);
    } else if (_wasReleased) {
      _released._fire(value);
    }
  }

  @override
  T get value {
    if (_hasResolvedValue) return _storage as T;
    if (_hasDefault) return _default as T;
    throw StateError(
      'input action #$index declared by $source (Input<$T>) has no default '
      'value and has not resolved, so there is nothing to read. Give it one '
      'at the declaration - has<$T>(binding, someDefault) - or a fallback '
      'for the whole type with hasDefaultValue<$T>(someDefault) in a '
      'describeInputs pass. The engine will not invent one: for a game, zero '
      'and false are real values, so guessing here would turn a missing '
      'declaration into a silently wrong number instead of this message. '
      '(If $T is bool or Vector2, the likely cause is a describeInputs '
      'override that does not call super - Game.describeInputs is where the '
      'built-in fallbacks are registered.)',
    );
  }

  @override
  bool get wasPressedThisFrame => _wasPressed;

  @override
  bool get wasReleasedThisFrame => _wasReleased;

  @override
  InputBinding<T>? get binding => _binding;

  @override
  set binding(InputBinding<T>? binding) {
    _binding = binding;
    if (binding != null && _storage == null) _storage = binding.createStorage();
  }

  @override
  InputEventStream<T> get pressed => _pressed;

  @override
  set pressed(InputEventStream<T> stream) => _assertOwnStream(stream, _pressed);

  @override
  InputEventStream<T> get released => _released;

  @override
  set released(InputEventStream<T> stream) =>
      _assertOwnStream(stream, _released);

  /// The whole body of both stream setters: they exist so `+=` compiles (see
  /// [Input.pressed]) and the only value they can legitimately receive is the
  /// stream `operator +` just returned.
  void _assertOwnStream(InputEventStream<T> given, InputEventStream<T> own) {
    assert(
      identical(given, own),
      'an input action\'s event stream cannot be replaced. The setter exists '
      'only so `action.pressed += listener` compiles - that expands to '
      '`action.pressed = action.pressed + listener`, and `+` returns the same '
      'stream. Assigning some other stream here would silently drop every '
      'listener already on this one.',
    );
  }

  @override
  String toString() => 'Input<$T>(#$index of $source, binding: $_binding)';
}
