import 'dart:async';

import 'package:meta/meta.dart';

import 'package:good/src/command/param.dart';

/// What every command shape has in common: an identity on the wire, a record
/// layout, and somewhere to send to.
///
/// Not extended directly - pick the shape the call actually is:
/// [GameCommand] (parameters and a result), [SupplierCommand] (a result),
/// [SinkCommand] (parameters), [SignalCommand] (neither).
///
/// # Where the pointer code lives, and where it does not
///
/// Four one-line methods per command, and they are the same four idea twice:
/// [GameCommand.bufferFromParams] / [GameCommand.paramsFromBuffer] for the
/// parameters, [GameCommand.bufferFromResult] /
/// [GameCommand.resultFromBuffer] for the result. Nothing else - `execute`
/// and `call` are provided, so no command's own code ever touches the
/// framework's own machinery. All written **once**, and what matters is where
/// they are *absent* - every call site, and the handler:
///
/// ```dart
/// final result = await damage((amount: 25, crit: true));
/// ```
///
/// ```dart
/// descriptor.hasHandler(damage, (p) => p.amount * (p.crit ? 2 : 1));
/// ```
///
/// An earlier draft pushed the pointers out to the callers instead
/// (`damage.amount[call] = 25` at every site) on the grounds that it saved
/// the command author a couple of methods. That is less to write once and
/// more to write every time, which is the wrong way round, and it fell apart
/// completely under batching - each call needing its own handle, and every
/// field access naming both the command and the handle. A later draft kept
/// the typed call site but left the *handler* reading pointers; that is the
/// same mistake in miniature, since a handler that has to know the wire
/// format is a handler that cannot be tested as the function it is.
abstract class GameCommandBase {
  /// Declares this command's fields - the parameters *and* the results, in
  /// one record, since they are the same bytes travelling in both directions.
  void describeParams(ParamDescriptor descriptor);

  /// Position in the shared declaration order - what a record's header
  /// carries and what routes it back to this command on the other side.
  ///
  /// Assigned by [CommandDescriptor.has], identical on both isolate copies
  /// because both run the same pass in the same order. No hand-picked record
  /// type numbers and no name lookup (the typed-handle rule).
  int get index => _index;
  int _index = -1;

  /// Bytes one call of this command occupies, excluding header, mask and any
  /// variable-length tail.
  int get strideBytes => _layout.strideBytes;

  /// How this command's record is laid out. Held whole, not copied field by
  /// field: a batch needs the head stride, the field count and where the tail
  /// length lives, and three copies of one object's facts is three things to
  /// keep in step.
  @internal
  ParamLayout get layout => _layout;

  /// Empty until [bind] runs, so an undeclared command reports a zero stride
  /// and no fields instead of failing on a half-built object.
  ParamLayout _layout = ParamLayout();

  CommandSender? _sender;

  /// Whether a handler was registered anywhere - on either isolate.
  bool get hasHandler => _handlerSide != null;

  HandlerSide? _handlerSide;

  /// How this command travels once it has a handler - see [HandlerDelivery].
  HandlerDelivery _handlerDelivery = HandlerDelivery.tick;

  /// Whether this command is carried over the control port and run on
  /// arrival instead of being pumped inside the tick window.
  bool get isControlDelivered => _handlerDelivery == HandlerDelivery.receipt;
  Function? _handler;

  /// The registered handler, on the copy that runs it.
  ///
  /// Stored untyped and cast by each shape at dispatch, because Dart will not
  /// let a type parameter appear contravariantly in a superinterface - which
  /// `GameCommandBase<R Function(P)>` would need. The cast is exact by
  /// construction: the only way in is a registration method that named the
  /// concrete shape.
  @protected
  Function get handler {
    final handler = _handler;
    if (handler == null) {
      throw StateError(
        'a $runtimeType arrived on the isolate that does not handle it. Its '
        'handler was registered in '
        '${_handlerSide == HandlerSide.main ? 'Game' : 'GameState'}'
        '.describeCommands, and this is the other copy.',
      );
    }
    return handler;
  }

  @internal
  void bind(int index, ParamLayout descriptor, CommandSender sender) {
    _index = index;
    _layout = descriptor;
    describeParams(descriptor);
    descriptor.seal();
    _sender = sender;
  }

  @internal
  void bindHandler(
    HandlerSide side,
    Function handler, {
    required bool install,
    HandlerDelivery delivery = HandlerDelivery.tick,
  }) {
    _handlerSide = side;
    _handlerDelivery = delivery;
    if (install) _handler = handler;
  }

  /// Unpacks this call, runs the handler, and packs whatever it returned.
  ///
  /// Per shape, because this is the one place the shapes genuinely differ -
  /// and it is what lets a handler be the plain function the command claims
  /// to be, with no buffer in its signature.
  @internal
  void invoke(ParamBuffer call);

  /// Reserves one call's bytes, in [batch] or in a batch of its own.
  ///
  /// Framework-internal: a command's own code never reserves anything, it
  /// only marshals. The batch-less form is what a bare `await damage(...)`
  /// uses - one call is a batch of one, so there is a single path and no
  /// special case. It is not a way to *get* a batch; see
  /// [CommandRegistry.createCommandBatch] for why that does not live here.
  ///
  /// [_requireSender] runs even when a batch was supplied: "is this command
  /// declared, and does anything anywhere handle it" is a question about the
  /// *command*, and answering it only on the batch-less path would mean an
  /// undeclared command sailed through as long as it was batched.
  ParamBuffer _reserve([CommandBatch? batch]) {
    final sender = _requireSender();
    final target = batch ?? sender.newBatch();
    // Where this call is going, decided by where its handler was registered -
    // and, for a batch that already holds calls, checked against theirs.
    target.routeTo(_handlerSide!, _handlerDelivery, runtimeType);
    return target.append(_index, _layout);
  }

  CommandSender _requireSender() {
    final sender = _sender;
    if (sender == null) {
      throw StateError(
        '$runtimeType was never declared. Add it to describeCommands - '
        '`myCommand = descriptor.has($runtimeType())` - and keep the handle '
        'it returns; a command built with `new` and called directly has no '
        'index, no layout and nowhere to send to.',
      );
    }
    if (!hasHandler) {
      throw StateError(
        'no handler is registered for $runtimeType, so sending one would be '
        'a message nothing reads. Register one with '
        'descriptor.hasHandler(myCommand, _onMyCommand) - in '
        'Game.describeCommands to run it on the Flutter isolate, or in '
        'GameState.describeCommands to run it on the game isolate.',
      );
    }
    return sender;
  }
}

/// A call with parameters and a result: `R Function(P)`, across an isolate.
///
/// ```dart
/// class Damage extends GameCommand<({int amount, bool crit}), int> {
///   late final ParamPointer<int> amount;
///   late final ParamPointer<int> crit;
///   late final ParamPointer<int> dealt;
///
///   @override
///   void describeParams(ParamDescriptor d) {
///     amount = d.hasUint16();
///     crit = d.hasUint1();
///     dealt = d.hasUint16();
///   }
///
///   @override
///   void bufferFromParams(ParamBuffer c, ({int amount, bool crit}) p) {
///     amount[c] = p.amount;
///     crit[c] = p.crit ? 1 : 0;
///   }
///
///   @override
///   ({int amount, bool crit}) paramsFromBuffer(ParamBuffer c) =>
///       (amount: amount[c], crit: crit[c] == 1);
///
///   @override
///   void bufferFromResult(ParamBuffer c, int r) => dealt[c] = r;
///
///   @override
///   int resultFromBuffer(ParamBuffer c) => dealt[c];
/// }
/// ```
///
/// Four marshalling methods beyond the schema, and neither [call] nor
/// [execute] is one of them - both are provided, in terms of those four:
///
/// ```dart
/// final dealt = await damage((amount: 25, crit: true));
/// ```
///
/// The handler is registered against the command and reads the record
/// directly, because unlike a call site there is exactly one of it:
///
/// ```dart
/// descriptor.hasHandler(damage, (c, call) {
///   c.dealt[call] = c.amount[call] * (c.crit[call] == 1 ? 2 : 1);
/// });
/// ```
abstract class GameCommand<P, R> extends GameCommandBase {
  /// Writes [params] into the record. One line per field.
  void bufferFromParams(ParamBuffer call, P params);

  /// Reads the parameters back out - what the handler is handed.
  P paramsFromBuffer(ParamBuffer call);

  /// Writes what the handler returned into the record.
  void bufferFromResult(ParamBuffer call, R result);

  /// Reads the result out of a call whose batch has been sent.
  R resultFromBuffer(ParamBuffer call);

  /// Reserves a call and writes [params] into it, without sending. Provided.
  ///
  /// Usually reached through [CommandBatchCalls.execute], which wraps this
  /// and hands back a typed key instead of a raw buffer:
  ///
  /// ```dart
  /// final batch = game.createCommandBatch();
  /// final a = batch.execute(damage, (amount: 1, crit: false));
  /// final b = batch.execute(heal, 5);
  /// final results = await batch.send();
  /// print(a[results]);
  /// ```
  ParamBuffer execute(P params, [CommandBatch? batch]) {
    final call = _reserve(batch);
    bufferFromParams(call, params);
    return call;
  }

  /// Sends one call and waits for its result. Provided, not overridden.
  ///
  /// The batch is made here and not reached through `buffer.batch`, because a
  /// [ParamBuffer] belongs to the shared record layer and that
  /// layer has no transport in it - a batch of *records* is a buffer, and
  /// only a [CommandBatch] is a channel. Same shape in all four commands.
  Future<R> call(P params) async {
    final batch = _requireSender().newBatch();
    final buffer = execute(params, batch);
    await batch.send();
    return resultFromBuffer(buffer);
  }

  @override
  @internal
  void invoke(ParamBuffer call) => bufferFromResult(
    call,
    (handler as R Function(P))(paramsFromBuffer(call)),
  );
}

/// A call that takes nothing and returns something: `R Function()`.
///
/// "Ask the other side for X" - the save-file list, the window title, a
/// platform capability: anything the asking isolate cannot see for itself.
abstract class SupplierCommand<R> extends GameCommandBase {
  /// Writes what the handler returned into the record.
  void bufferFromResult(ParamBuffer call, R result);

  /// Reads the result out of a call whose batch has been sent.
  R resultFromBuffer(ParamBuffer call);

  /// Nothing to write, so there is nothing to override either.
  ParamBuffer execute([CommandBatch? batch]) => _reserve(batch);

  Future<R> call() async {
    final batch = _requireSender().newBatch();
    final buffer = execute(batch);
    await batch.send();
    return resultFromBuffer(buffer);
  }

  @override
  @internal
  void invoke(ParamBuffer call) =>
      bufferFromResult(call, (handler as R Function())());
}

/// A call that takes something and returns nothing: `void Function(P)`.
///
/// The workhorse - "spawn this", "play that", "log this". Still awaitable:
/// knowing the other side has *run* it is a different question from what it
/// produced, and a caller sequencing work needs the first even when there is
/// no second.
abstract class SinkCommand<P> extends GameCommandBase {
  /// Writes [params] into the record. One line per field.
  void bufferFromParams(ParamBuffer call, P params);

  /// Reads the parameters back out - what the handler is handed.
  P paramsFromBuffer(ParamBuffer call);

  /// Reserves a call and writes [params] into it, without sending. Provided.
  ParamBuffer execute(P params, [CommandBatch? batch]) {
    final call = _reserve(batch);
    bufferFromParams(call, params);
    return call;
  }

  Future<void> call(P params) {
    final batch = _requireSender().newBatch();
    execute(params, batch);
    return batch.send();
  }

  @override
  @internal
  void invoke(ParamBuffer call) =>
      (handler as void Function(P))(paramsFromBuffer(call));
}

/// A call that takes and returns nothing: `void Function()`.
///
/// "Do the thing." No [describeParams] body needed either - the default
/// declares an empty record, so a signal is three lines including the class.
abstract class SignalCommand extends GameCommandBase {
  /// Nothing to declare. Overridable anyway, for a signal that grows a field
  /// later and would otherwise have to change class.
  @override
  @mustCallSuper
  void describeParams(ParamDescriptor descriptor) {}

  ParamBuffer execute([CommandBatch? batch]) => _reserve(batch);

  Future<void> call() {
    final batch = _requireSender().newBatch();
    execute(batch);
    return batch.send();
  }

  @override
  @internal
  void invoke(ParamBuffer call) => (handler as void Function())();
}

/// A place in a batch, and the type of what will come back from it.
///
/// ```dart
/// final batch = game.createCommandBatch();
/// final hit = batch.execute(damage, (amount: 1, crit: false));
/// final id = batch.supply(nextId);
/// final results = await batch.send();
/// print(hit[results]);   // int, typed by the key
/// print(id[results]);    // int, from a different command entirely
/// ```
///
/// The key carries `R`, so reading a result names neither the command again
/// nor a buffer - and it takes a [CommandResults], which only exists once
/// the batch has actually been sent.
final class CommandKey<R> {
  const CommandKey._(this._command, this._call);

  final R Function(ParamBuffer) _command;
  final ParamBuffer _call;

  /// This call's result, out of [results].
  R operator [](CommandResults results) {
    if (!identical(results.batch, _call.batch)) {
      throw StateError(
        'this key belongs to a different batch than the results it was '
        'indexed with. A key is a place in one batch; another batch has its '
        'own.',
      );
    }
    return _command(_call);
  }
}

/// Building calls into a batch - one message, whatever mix of commands.
///
/// An extension, not methods on `CommandBatch` itself: the batch lives a
/// layer down, in the record format, and knows nothing about
/// command shapes. The call sites read the same either way.
extension CommandBatchCalls on CommandBatch {
  /// Adds a [GameCommand] call, and returns the key its result will arrive
  /// under.
  CommandKey<R> execute<P, R>(GameCommand<P, R> command, P params) =>
      CommandKey<R>._(command.resultFromBuffer, command.execute(params, this));

  /// Adds a [SupplierCommand] call - nothing to pass, something to get back.
  CommandKey<R> supply<R>(SupplierCommand<R> command) =>
      CommandKey<R>._(command.resultFromBuffer, command.execute(this));

  /// Adds a [SinkCommand] call. No key: there is no result to key.
  void sink<P>(SinkCommand<P> command, P params) =>
      command.execute(params, this);

  /// Adds a [SignalCommand] call.
  void signal(SignalCommand command) => command.execute(this);
}

/// Declares a game's commands, and who handles them.
///
/// ```dart
/// class MyGame extends Game {
///   late final Damage damage;
///
///   @override
///   void describeCommands(CommandDescriptor descriptor) {
///     super.describeCommands(descriptor);
///     damage = descriptor.has(Damage());
///     // handled on the Flutter isolate, so callable from the game isolate
///     descriptor.hasHandler(damage, _onDamage);
///   }
///
///   void _onDamage(Damage c, ParamBuffer call) {
///     c.dealt[call] = c.amount[call] * 2;
///   }
/// }
/// ```
///
/// **Commands are declared on `Game` only.** Both isolate copies run that
/// pass, in the same order, which is what makes an index mean the same thing
/// on both sides - the same argument that makes archetype ids agree.
/// `GameState.describeCommands` may only *handle* commands the `Game`
/// declared; a command declared there would have an index on one isolate and
/// none on the other, which is the same as having none.
abstract class CommandDescriptor {
  /// Declares [command] and returns it, for the `late final` field to keep.
  T has<T extends GameCommandBase>(T command);

  /// Registers what runs when [command] arrives.
  ///
  /// Registers what runs when [command] arrives: **the function the command
  /// claims to be**, with no buffer in its signature and no pointer in its
  /// body.
  ///
  /// ```dart
  /// descriptor.hasHandler(damage, (p) => p.amount * (p.crit ? 2 : 1));
  /// ```
  ///
  /// One method per shape, not one method for all four, because Dart
  /// will not let a handler type ride on the command's own type (a type
  /// parameter cannot appear contravariantly in a superinterface, which
  /// `GameCommandBase<R Function(P)>` would need). Four names is the price of
  /// each one being checked at this line instead of casting on the far
  /// isolate.
  void hasHandler<P, R>(GameCommand<P, R> command, R Function(P) handler);

  /// Registers a [SupplierCommand]'s handler: takes nothing, returns an `R`.
  void hasSupplier<R>(SupplierCommand<R> command, R Function() handler);

  /// Registers a [SinkCommand]'s handler: takes a `P`, returns nothing.
  void hasSink<P>(SinkCommand<P> command, void Function(P) handler);

  /// Registers a [SignalCommand]'s handler: takes and returns nothing.
  void hasSignal(SignalCommand command, void Function() handler);

  /// Registers a [SinkCommand]'s handler to run **when the message arrives**
  /// instead of inside the next tick window.
  ///
  /// This is what a control signal needs. A tick-delivered command is pumped
  /// from `GameState.runFixedStep`, so it arrives only if the tick runs -
  /// which makes it useless for anything that *stops* the tick, because the
  /// message that starts it again would be waiting on the tick it stopped.
  /// A receipt-delivered command is carried over the control port and run
  /// from the port callback, with no tick involved.
  ///
  /// ```dart
  /// // in GameState.describeCommands
  /// descriptor.hasControlSink(setTimeScale, (s) => state.timeScale = s);
  /// ```
  ///
  /// Four things are true of it that are not true of [hasSink], and all four
  /// follow from there being no tick:
  ///
  /// **The future completes on send, not on execution.** `await` on a control
  /// command means "handed to the port", not "done". A tick-delivered command
  /// resolves when the far side has run it and replied; there is no reply leg
  /// here, because a reply would be pumped by the tick this exists to work
  /// without.
  ///
  /// **The handler must not write component data.** There is no open write
  /// window outside a tick: `MemoryPool.beginTick` copies each page's
  /// published bytes over the write slot, so a write landing outside one is
  /// erased by the next tick with nothing said. A debug assert in
  /// `data_layout.dart` catches it.
  ///
  /// **That assert has one hole**, and it is worth knowing before you trust
  /// the guard: it stays silent while a page has never published, which is
  /// scene bootstrap and nothing else. A running game is covered; a control
  /// handler that writes during bring-up is not.
  ///
  /// **There is no ordering against tick-delivered commands.** They travel by
  /// different carriers, so two calls sent in order can run in either. That
  /// is inherent to working while the tick is stopped, not a defect.
  void hasControlSink<P>(SinkCommand<P> command, void Function(P) handler);

  /// [hasControlSink] for a [SignalCommand] - takes and returns nothing.
  void hasControlSignal(SignalCommand command, void Function() handler);

  /// Always throws. A receipt-delivered command **cannot answer**.
  ///
  /// It exists so the name someone reaches for explains itself instead of
  /// being absent. A control command completes when it reaches the port, and
  /// its handler runs with no tick and no reply leg - so there is nowhere for
  /// an `R` to come from. Use [hasHandler], which is tick-delivered and does
  /// reply, or restate the call as a [SinkCommand] and publish the answer
  /// through a `StateChannel`.
  void hasControlHandler<P, R>(
    GameCommand<P, R> command,
    R Function(P) handler,
  );

  /// Always throws, for the same reason as [hasControlHandler].
  void hasControlSupplier<R>(SupplierCommand<R> command, R Function() handler);
}

/// The registry behind [CommandDescriptor], owned by `Game`.
@internal
final class CommandRegistry implements ParamLayouts {
  CommandRegistry(this.sender, {required this.simulating, this.inline = false});

  final CommandSender sender;

  /// Which copy this is. A handler is *declared* on both copies and
  /// *installed* on one: the declaration is what makes both sides agree that
  /// a handler exists (so a sender can refuse early), and the install is what
  /// actually runs it.
  /// Which side this copy runs handlers for. Not `final`: main declares every
  /// command before the spawn with this false, and the spawned copy - which
  /// inherits that value through the deep copy - flips it via
  /// [markSimulating] as part of taking over the simulating role.
  bool simulating;

  /// Whether this is the single-copy configuration (`Game.start(inline:
  /// true)`, and every web build). There is no other copy to send to, so this
  /// one installs *both* sides' handlers - see [handles].
  final bool inline;

  /// Whether a handler registered on [side] runs on this copy.
  ///
  /// The one rule behind two questions that must never disagree: which
  /// handlers get installed here (in [declareHandler]), and whether a batch
  /// bound for [side] needs to cross an isolate boundary at all (in the
  /// transport). Splitting them would let a copy install a handler it then
  /// posted work to itself for, or post work away that it was holding the
  /// only handler for.
  /// Called on the spawned copy, before anything dispatches. See [simulating].
  void markSimulating() => simulating = true;

  bool handles(HandlerSide side) =>
      inline || side == (simulating ? HandlerSide.game : HandlerSide.main);

  final List<GameCommandBase> _commands = <GameCommandBase>[];

  int get length => _commands.length;

  GameCommandBase operator [](int index) => _commands[index];

  GameCommandBase? tryAt(int index) =>
      index >= 0 && index < _commands.length ? _commands[index] : null;

  @override
  ParamLayout layoutOf(int index) => _requireAt(index).layout;

  GameCommandBase _requireAt(int index) {
    final command = tryAt(index);
    if (command != null) return command;
    throw StateError(
      'a command record names index $index, and this copy declared only '
      '$length commands. The two isolate copies disagree about the command '
      'list, which means describeCommands did not run identically on both.',
    );
  }

  bool _sealed = false;

  void seal() => _sealed = true;

  /// A batch to build calls into.
  ///
  /// Here and not on a command: `damage.newBatch()` reads as "a batch of
  /// damage commands", and a batch is nothing of the kind - it is a mixed
  /// sequence, and mixing is most of the point. It comes from the thing that
  /// owns the channel, which is the game, and is exposed as
  /// `Game.createCommandBatch()`.
  CommandBatch createCommandBatch() => sender.newBatch();

  /// Runs every call in [batch] against its handler, in order.
  ///
  /// Order is the order they were appended: a batch is a sequence, not a set,
  /// and a game that spawns a unit and then orders it around relies on that.
  void dispatch(CommandBatch batch) {
    for (var i = 0; i < batch.callCount; i++) {
      _requireAt(batch.indexAt(i)).invoke(batch.callAt(i));
    }
  }

  T declare<T extends GameCommandBase>(T command) {
    _requireOpen();
    for (var i = 0; i < _commands.length; i++) {
      if (_commands[i].runtimeType == command.runtimeType) {
        throw StateError(
          '${command.runtimeType} is declared twice. One instance is one '
          'command, and its position in this pass is its identity on the '
          'wire, so a second one would be a different command with the same '
          'name.',
        );
      }
    }
    command.bind(_commands.length, ParamLayout(), sender);
    _commands.add(command);
    return command;
  }

  void declareHandler(
    GameCommandBase command,
    Function handler,
    HandlerSide side, [
    HandlerDelivery delivery = HandlerDelivery.tick,
  ]) {
    _requireOpen();
    if (command.index < 0 || tryAt(command.index) != command) {
      throw StateError(
        '${command.runtimeType} has no handler to register against because it '
        'was never declared. Commands are declared in Game.describeCommands; '
        'GameState.describeCommands can only handle them.',
      );
    }
    if (command.hasHandler) {
      throw StateError(
        '${command.runtimeType} already has a handler. A command runs on one '
        'isolate - two handlers would be two answers to "where does this '
        'go".',
      );
    }
    // Installed on **both** copies, unconditionally. It used to be installed
    // only where `handles(side)` was true, which worked when each copy ran its
    // own declaration pass and so evaluated that for itself. Now main declares
    // once, before the spawn, with `simulating: false` - so a game-side
    // handler would be stored nowhere and the game isolate would inherit a
    // command with no handler at all. Who *dispatches* is still decided by
    // [handles], in the transport; this only decides who is holding the
    // function, and a handler that is never dispatched costs one field.
    command.bindHandler(side, handler, install: true, delivery: delivery);
  }

  void _requireOpen() {
    if (!_sealed) return;
    throw StateError(
      'commands can only be declared during boot, in describeCommands - the '
      'index a command gets is its identity on the wire, and both isolate '
      'copies have already agreed on the list.',
    );
  }
}

/// The message both descriptors give for a control handler on a shape that
/// returns something. One function so the two sides cannot drift.
Never _controlCannotAnswer(Type command, String method) {
  throw StateError(
    '$command returns a value, so it cannot be registered with $method. A '
    'receipt-delivered command is carried over the control port and run when '
    'the port callback fires, which is what lets it work while the fixed '
    'tick is stopped - and it is also why there is no reply leg: a reply '
    'would be pumped inside the tick window it exists to work without, so '
    'the caller would wait forever. Register it with hasHandler or '
    'hasSupplier, which are tick-delivered and do reply, or make it a '
    'SinkCommand and publish the answer on a StateChannel.',
  );
}

/// `CommandDescriptor` as seen by `Game.describeCommands` - may declare
/// commands, and registers handlers that run on the **Flutter** isolate.
@internal
final class MainCommandDescriptor implements CommandDescriptor {
  MainCommandDescriptor(this._registry);

  final CommandRegistry _registry;

  @override
  T has<T extends GameCommandBase>(T command) => _registry.declare(command);

  @override
  void hasHandler<P, R>(GameCommand<P, R> command, R Function(P) handler) =>
      _registry.declareHandler(command, handler, HandlerSide.main);

  @override
  void hasSupplier<R>(SupplierCommand<R> command, R Function() handler) =>
      _registry.declareHandler(command, handler, HandlerSide.main);

  @override
  void hasSink<P>(SinkCommand<P> command, void Function(P) handler) =>
      _registry.declareHandler(command, handler, HandlerSide.main);

  @override
  void hasSignal(SignalCommand command, void Function() handler) =>
      _registry.declareHandler(command, handler, HandlerSide.main);

  @override
  void hasControlSink<P>(SinkCommand<P> command, void Function(P) handler) =>
      _registry.declareHandler(
        command,
        handler,
        HandlerSide.main,
        HandlerDelivery.receipt,
      );

  @override
  void hasControlSignal(SignalCommand command, void Function() handler) =>
      _registry.declareHandler(
        command,
        handler,
        HandlerSide.main,
        HandlerDelivery.receipt,
      );

  @override
  void hasControlHandler<P, R>(
    GameCommand<P, R> command,
    R Function(P) handler,
  ) => _controlCannotAnswer(command.runtimeType, 'hasControlHandler');

  @override
  void hasControlSupplier<R>(
    SupplierCommand<R> command,
    R Function() handler,
  ) => _controlCannotAnswer(command.runtimeType, 'hasControlSupplier');
}

/// `CommandDescriptor` as seen by `GameState.describeCommands` - registers
/// handlers that run on the **game** isolate, and refuses to declare.
@internal
final class GameCommandDescriptor implements CommandDescriptor {
  GameCommandDescriptor(this._registry);

  final CommandRegistry _registry;

  @override
  T has<T extends GameCommandBase>(T command) {
    throw StateError(
      'commands are declared on the Game, not the GameState: '
      '${command.runtimeType} declared here would have an index on the game '
      'isolate and none on the Flutter one, which is the same thing as not '
      'having one. Declare it in Game.describeCommands and handle it here.',
    );
  }

  @override
  void hasHandler<P, R>(GameCommand<P, R> command, R Function(P) handler) =>
      _registry.declareHandler(command, handler, HandlerSide.game);

  @override
  void hasSupplier<R>(SupplierCommand<R> command, R Function() handler) =>
      _registry.declareHandler(command, handler, HandlerSide.game);

  @override
  void hasSink<P>(SinkCommand<P> command, void Function(P) handler) =>
      _registry.declareHandler(command, handler, HandlerSide.game);

  @override
  void hasSignal(SignalCommand command, void Function() handler) =>
      _registry.declareHandler(command, handler, HandlerSide.game);

  @override
  void hasControlSink<P>(SinkCommand<P> command, void Function(P) handler) =>
      _registry.declareHandler(
        command,
        handler,
        HandlerSide.game,
        HandlerDelivery.receipt,
      );

  @override
  void hasControlSignal(SignalCommand command, void Function() handler) =>
      _registry.declareHandler(
        command,
        handler,
        HandlerSide.game,
        HandlerDelivery.receipt,
      );

  @override
  void hasControlHandler<P, R>(
    GameCommand<P, R> command,
    R Function(P) handler,
  ) => _controlCannotAnswer(command.runtimeType, 'hasControlHandler');

  @override
  void hasControlSupplier<R>(
    SupplierCommand<R> command,
    R Function() handler,
  ) => _controlCannotAnswer(command.runtimeType, 'hasControlSupplier');
}
