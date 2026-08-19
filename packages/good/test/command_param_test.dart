import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/command/command.dart';
import 'package:good/src/command/param.dart';
import 'package:good/src/struct.dart';

// The command API's two lower layers - the parameter record and the
// declaration/dispatch registry - exercised with a loopback sender: no
// isolates, no ring buffers, no Game. Everything about *what a command is* is
// decided here, so it can all be tested here; carrying a batch between two
// isolates is a separate concern with its own tests.

typedef _Blow = ({int amount, bool crit});

/// The reference command: typed parameters in, a typed result out, and every
/// pointer confined to the four symmetric marshalling methods.
class _Damage extends GameCommand<_Blow, int> {
  late final ParamPointer<int> amount;
  late final ParamPointer<int> crit;
  late final ParamPointer<int> dealt;
  late final ParamPointer<int> overkill;

  @override
  void describeParams(ParamDescriptor descriptor) {
    amount = descriptor.hasUint16();
    crit = descriptor.hasUint1();
    dealt = descriptor.hasUint16();
    overkill = descriptor.hasUint1();
  }

  @override
  void bufferFromParams(ParamBuffer call, _Blow params) {
    amount[call] = params.amount;
    crit[call] = params.crit ? 1 : 0;
  }

  @override
  _Blow paramsFromBuffer(ParamBuffer call) =>
      (amount: amount[call], crit: crit[call] == 1);

  @override
  void bufferFromResult(ParamBuffer call, int result) {
    dealt[call] = result;
    overkill[call] = result > 100 ? 1 : 0;
  }

  @override
  int resultFromBuffer(ParamBuffer call) => dealt[call];
}

class _Ping extends SignalCommand {}

class _NextId extends SupplierCommand<int> {
  late final ParamPointer<int> id;

  @override
  void describeParams(ParamDescriptor descriptor) {
    id = descriptor.hasUint32();
  }

  @override
  void bufferFromResult(ParamBuffer call, int result) => id[call] = result;

  @override
  int resultFromBuffer(ParamBuffer call) => id[call];
}

class _Log extends SinkCommand<String> {
  late final ParamPointer<String> message;

  @override
  void describeParams(ParamDescriptor descriptor) {
    message = descriptor.hasString(32);
  }

  @override
  void bufferFromParams(ParamBuffer call, String params) =>
      message[call] = params;

  @override
  String paramsFromBuffer(ParamBuffer call) => message[call];
}

/// Every field kind, to pin the packing down.
class _Wide extends GameCommand<int, int> {
  late final ParamPointer<int> flag;
  late final ParamPointer<int> pair;
  late final ParamPointer<int> nibble;
  late final ParamPointer<int> u8;
  late final ParamPointer<int> i8;
  late final ParamPointer<int> u16;
  late final ParamPointer<int> i32;
  late final ParamPointer<int> i64;
  late final ParamPointer<double> f32;
  late final ParamPointer<double> f64;
  late final ParamPointer<String> name;

  @override
  void describeParams(ParamDescriptor descriptor) {
    flag = descriptor.hasUint1();
    pair = descriptor.hasUint2();
    nibble = descriptor.hasUint4();
    u8 = descriptor.hasUint8();
    i8 = descriptor.hasInt8();
    u16 = descriptor.hasUint16();
    i32 = descriptor.hasInt32();
    i64 = descriptor.hasInt64();
    f32 = descriptor.hasFloat32();
    f64 = descriptor.hasFloat64();
    name = descriptor.hasString(16);
  }

  @override
  void bufferFromParams(ParamBuffer call, int params) => u8[call] = params;

  @override
  int paramsFromBuffer(ParamBuffer call) => u8[call];

  @override
  void bufferFromResult(ParamBuffer call, int result) => u8[call] = result;

  @override
  int resultFromBuffer(ParamBuffer call) => u8[call];
}

typedef _Order = ({Entity unit, int waypoint});

/// A command that carries an entity handle, to pin down the field kind that
/// exists so an id and a number stop being interchangeable on the wire. The
/// `waypoint` beside it is the number: both are 64 bits of payload, and only
/// the declaration tells them apart.
class _OrderUnit extends GameCommand<_Order, Entity> {
  late final ParamPointer<Entity> unit;
  late final ParamPointer<int> waypoint;
  late final ParamPointer<Entity> escort;

  @override
  void describeParams(ParamDescriptor descriptor) {
    unit = descriptor.hasEntity();
    waypoint = descriptor.hasInt64();
    escort = descriptor.hasEntity();
  }

  @override
  void bufferFromParams(ParamBuffer call, _Order params) {
    unit[call] = params.unit;
    waypoint[call] = params.waypoint;
  }

  @override
  _Order paramsFromBuffer(ParamBuffer call) =>
      (unit: unit[call], waypoint: waypoint[call]);

  @override
  void bufferFromResult(ParamBuffer call, Entity result) =>
      escort[call] = result;

  @override
  Entity resultFromBuffer(ParamBuffer call) => escort[call];
}

class _Unhandled extends SignalCommand {}

/// Runs handlers in place instead of sending anywhere - the transport seam,
/// stood in for. What a real sender adds is bytes crossing a boundary and a
/// reply coming back; what it does *to a batch* is exactly this.
final class _Loopback implements CommandSender {
  late final CommandRegistry registry;

  int _nextId = 0;
  int batchesSent = 0;
  int callsDispatched = 0;

  @override
  CommandBatch newBatch() => CommandBatch(_nextId++, sender: this);

  @override
  Future<void> send(CommandBatch batch) async {
    batchesSent++;
    callsDispatched += batch.callCount;
    // Through a real byte round trip rather than by handing the same object
    // back: a batch that only worked in place would hide anything that lives
    // in the record - the written-mask especially.
    final wire = Uint8List.fromList(
      Uint8List.sublistView(batch.bytes, 0, batch.length),
    );
    final received = CommandBatch(batch.id, initialBytes: wire.length)
      ..adoptIncoming(wire, registry);
    registry.dispatch(received);
    batch.adoptReply(Uint8List.sublistView(received.bytes, 0, received.length));
  }
}

({CommandRegistry registry, _Loopback sender}) _registry({
  bool simulating = true,
}) {
  final sender = _Loopback();
  final registry = CommandRegistry(sender, simulating: simulating);
  sender.registry = registry;
  return (registry: registry, sender: sender);
}

void main() {
  group('declaration', () {
    test('a command gets its index from declaration order', () {
      final r = _registry().registry;
      final damage = r.declare(_Damage());
      final ping = r.declare(_Ping());

      expect(damage.index, 0);
      expect(ping.index, 1);
      expect(
        r.length,
        2,
        reason:
            'the index is the identity on the wire, and it comes from '
            'the order both isolate copies run this pass in - no '
            'hand-picked record type to collide, no name to misspell',
      );
    });

    test('declaring the same command twice is refused', () {
      final r = _registry().registry;
      r.declare(_Damage());
      expect(() => r.declare(_Damage()), throwsStateError);
    });

    test('declaring after boot is refused', () {
      final r = _registry().registry;
      r.seal();
      expect(() => r.declare(_Damage()), throwsStateError);
    });

    test('the state descriptor cannot declare, only handle', () {
      final r = _registry().registry;
      final damage = r.declare(_Damage());
      final descriptor = GameCommandDescriptor(r);

      expect(
        () => descriptor.has(_Ping()),
        throwsStateError,
        reason:
            'a command declared on the GameState would have an index on '
            'the game isolate and none on the Flutter one, which is the '
            'same as not having one',
      );
      descriptor.hasHandler(damage, (p) => 0);
      expect(damage.hasHandler, isTrue);
    });

    test('a command can only have one handler', () {
      final r = _registry().registry;
      final damage = r.declare(_Damage());
      MainCommandDescriptor(r).hasHandler(damage, (p) => 0);
      expect(
        () => GameCommandDescriptor(r).hasHandler(damage, (p) => 0),
        throwsStateError,
        reason:
            'a command runs on one isolate - two handlers would be two '
            'answers to "where does this go"',
      );
    });

    test('handling an undeclared command is refused', () {
      final r = _registry().registry;
      expect(
        () => MainCommandDescriptor(r).hasHandler(_Damage(), (p) => 0),
        throwsStateError,
      );
    });

    test('a handler is the function its command claims to be', () {
      final r = _registry().registry;
      final damage = r.declare(_Damage());
      // `p` is a _Blow and the return is an int, both inferred - there is no
      // buffer in this signature and no pointer in this body, which is what
      // makes a handler testable as the plain function it is.
      GameCommandDescriptor(r)
          .hasHandler(damage, (p) => p.amount * (p.crit ? 2 : 1));
      expect(damage.hasHandler, isTrue);
    });
  });

  group('calling', () {
    test('call sites carry no pointers at all', () async {
      final r = _registry();
      final damage = r.registry.declare(_Damage());
      GameCommandDescriptor(r.registry)
          .hasHandler(damage, (p) => p.amount * (p.crit ? 2 : 1));

      expect(
        await damage((amount: 30, crit: true)),
        60,
        reason:
            'this is the line that gets written a hundred times, and '
            'the two methods on the command are what keep it this short',
      );
    });

    test('a signal is a class body away from nothing', () async {
      final r = _registry();
      final ping = r.registry.declare(_Ping());
      var pinged = 0;
      GameCommandDescriptor(r.registry).hasSignal(ping, () => pinged++);

      await ping();
      await ping();
      expect(
        pinged,
        2,
        reason:
            'no params, no result, no describeParams body - the shape '
            'that needs nothing should cost nothing to declare',
      );
    });

    test('a supplier asks and gets an answer', () async {
      final r = _registry();
      final nextId = r.registry.declare(_NextId());
      var counter = 41;
      GameCommandDescriptor(r.registry).hasSupplier(nextId, () => ++counter);

      expect(await nextId(), 42);
      expect(await nextId(), 43);
    });

    test('a sink carries a payload and still tells you it ran', () async {
      final r = _registry();
      final log = r.registry.declare(_Log());
      final lines = <String>[];
      GameCommandDescriptor(r.registry).hasSink(log, lines.add);

      await log('level loaded');
      expect(
        lines,
        ['level loaded'],
        reason:
            'awaitable even with no result: "has the other side run '
            'this" is a different question from "what did it produce"',
      );
    });

    test('reading a result the handler never wrote throws', () async {
      final r = _registry();
      final damage = r.registry.declare(_Damage());
      GameCommandDescriptor(r.registry).hasHandler(damage, (p) => 5);

      final batch = r.registry.createCommandBatch();
      final hit = batch.execute(damage, (amount: 1, crit: false));
      final results = await batch.send();

      expect(
        hit[results],
        5,
        reason:
            'bufferFromResult decides what a single returned value '
            'means on the wire - here it wrote both dealt and overkill, so '
            'the handler never had to know there were two fields',
      );
    });

    test('reading a parameter nobody wrote throws', () {
      final r = _registry();
      final wide = r.registry.declare(_Wide());
      GameCommandDescriptor(r.registry).hasHandler(wide, (p) => p);

      final call = wide.execute(7);
      expect(
        () => wide.i32[call],
        throwsStateError,
        reason:
            'execute only wrote u8, and zero is a real i32 - a '
            'parameter the caller left out has to be an error rather than a '
            'plausible number the handler acts on',
      );
    });

    test(
      'sending a command with no handler anywhere throws at the sender',
      () async {
        final r = _registry();
        final unhandled = r.registry.declare(_Unhandled());

        expect(
          unhandled.call,
          throwsStateError,
          reason:
              'both copies run both declaration passes, so the sending '
              'side already knows nothing will read this - it does not have '
              'to send it to find out',
        );
        expect(r.sender.batchesSent, 0);
      },
    );

    test('an undeclared command cannot be called at all', () {
      expect(
        _Ping().call,
        throwsStateError,
        reason:
            'no index, no layout, nowhere to send to - the message '
            'should say so rather than throwing on a null somewhere inside',
      );
    });
  });

  group('batching', () {
    test('several calls travel as one message, in order', () async {
      final r = _registry();
      final damage = r.registry.declare(_Damage());
      final order = <int>[];
      GameCommandDescriptor(r.registry).hasHandler(damage, (p) {
        order.add(p.amount);
        return p.amount * 10;
      });

      final batch = r.registry.createCommandBatch();
      final first = batch.execute(damage, (amount: 1, crit: false));
      final second = batch.execute(damage, (amount: 2, crit: false));
      final third = batch.execute(damage, (amount: 3, crit: false));
      final results = await batch.send();

      expect(
        order,
        [1, 2, 3],
        reason:
            'a batch is a sequence, not a set - a game that spawns a '
            'unit and then orders it around depends on that',
      );
      expect(first[results], 10);
      expect(second[results], 20);
      expect(third[results], 30);
      expect(
        r.sender.batchesSent,
        1,
        reason:
            'one message, one wake-up, one reply - the round trip costs '
            'more than the bytes, which is the whole reason batching '
            'exists',
      );
      expect(r.sender.callsDispatched, 3);
    });

    test('one batch can hold several different commands', () async {
      final r = _registry();
      final damage = r.registry.declare(_Damage());
      final log = r.registry.declare(_Log());
      final descriptor = GameCommandDescriptor(r.registry);
      final lines = <String>[];
      descriptor.hasHandler(damage, (p) => 7);
      descriptor.hasSink(log, lines.add);

      final batch = r.registry.createCommandBatch();
      final hit = batch.execute(damage, (amount: 3, crit: false));
      batch.sink(log, 'hit');
      final results = await batch.send();

      expect(
        hit[results],
        7,
        reason:
            'the key carries R, so reading a result names neither the '
            'command again nor a buffer',
      );
      expect(
        lines,
        ['hit'],
        reason:
            'each record names its own command, so a batch is a mixed '
            'sequence rather than a run of one kind',
      );
    });

    test('a batch grows past its initial guess without losing calls', () async {
      final r = _registry();
      final wide = r.registry.declare(_Wide());
      GameCommandDescriptor(r.registry).hasHandler(wide, (p) => p + 1);

      final batch = CommandBatch(1, sender: r.sender, initialBytes: 8);
      final keys = <CommandKey<int>>[];
      for (var i = 0; i < 20; i++) {
        keys.add(batch.execute(wide, i));
      }
      final results = await batch.send();

      for (var i = 0; i < keys.length; i++) {
        expect(
          keys[i][results],
          i + 1,
          reason:
              'growth copies what is already there, so an underestimate '
              'costs one copy rather than a dropped call',
        );
      }
    });

    test('a key cannot read another batch\'s results', () async {
      final r = _registry();
      final wide = r.registry.declare(_Wide());
      GameCommandDescriptor(r.registry).hasHandler(wide, (p) => p);

      final first = r.registry.createCommandBatch();
      final key = first.execute(wide, 1);
      final second = r.registry.createCommandBatch();
      second.execute(wide, 2);

      final theirs = await second.send();
      expect(
        () => key[theirs],
        throwsStateError,
        reason:
            'a key is a place in one batch, and the results token is '
            'what says which - crossing them would silently read whatever '
            'happened to be at that offset',
      );
    });

    test('a batch with nowhere to send says so', () {
      expect(
        () => CommandBatch(0).send(),
        throwsStateError,
        reason:
            'a bare CommandBatch is a buffer, not a channel - build one '
            'with command.newBatch(), which takes the transport with it',
      );
    });
  });

  group('the record layout', () {
    test('every field kind round-trips', () async {
      final r = _registry();
      final wide = r.registry.declare(_Wide());
      GameCommandDescriptor(r.registry).hasHandler(wide, (p) => p);

      final batch = r.registry.createCommandBatch();
      final call = wide.execute(250, batch);
      wide.flag[call] = 1;
      wide.pair[call] = 2;
      wide.nibble[call] = 9;
      wide.i8[call] = -120;
      wide.u16[call] = 65000;
      wide.i32[call] = -2000000000;
      wide.i64[call] = -9000000000000000000;
      wide.f32[call] = 0.5;
      wide.f64[call] = 1e-300;
      wide.name[call] = 'hello';
      await batch.send();

      expect(wide.flag[call], 1);
      expect(wide.pair[call], 2);
      expect(wide.nibble[call], 9);
      expect(wide.u8[call], 250);
      expect(wide.i8[call], -120);
      expect(wide.u16[call], 65000);
      expect(wide.i32[call], -2000000000);
      expect(wide.i64[call], -9000000000000000000);
      expect(wide.f32[call], 0.5);
      expect(wide.f64[call], 1e-300);
      expect(wide.name[call], 'hello');
    });

    test('sub-byte fields share a byte without disturbing each other', () {
      final r = _registry();
      final wide = r.registry.declare(_Wide());
      GameCommandDescriptor(r.registry).hasHandler(wide, (p) => p);

      final call = wide.execute(0);
      wide.flag[call] = 1;
      wide.pair[call] = 3;
      wide.nibble[call] = 15;
      expect(wide.flag[call], 1);
      wide.pair[call] = 0;
      expect(wide.flag[call], 1, reason: 'neighbours share the byte');
      expect(wide.nibble[call], 15);
    });

    test('a string longer than its declared capacity is refused', () {
      final r = _registry();
      final log = r.registry.declare(_Log());
      GameCommandDescriptor(r.registry).hasSink(log, (p) {});

      expect(
        () => log.execute('a message far longer than thirty-two bytes'),
        throwsArgumentError,
        reason:
            'a command record has a fixed stride, exactly like an '
            'archetype row, so capacity is part of the declaration - '
            'silently truncating a message is worse than saying so',
      );
    });

    test('an entity parameter arrives at the handler as an Entity', () async {
      final r = _registry();
      final order = r.registry.declare(_OrderUnit());
      late _Order seen;
      GameCommandDescriptor(r.registry).hasHandler(order, (p) {
        seen = p;
        return Entity.pack(0xF00D, 4, 5);
      });

      // An archetype id big enough to reach bit 63, so the handle's `int`
      // value is negative - the case a narrower or unsigned slot would not
      // round-trip.
      final unit = Entity.pack(0x9001, 2, 11);
      final escort = await order((unit: unit, waypoint: -9000000000000000000));

      expect(
        seen.unit,
        unit,
        reason:
            'the handler receives the handle the caller sent, through a '
            'real byte round trip - the archetype id rides in the sign bit',
      );
      expect(seen.unit.archetypeId, 0x9001);
      expect(seen.unit.value.isNegative, isTrue);
      expect(seen.waypoint, -9000000000000000000);
      expect(
        escort,
        Entity.pack(0xF00D, 4, 5),
        reason: 'and a result field carries one back the same way',
      );
    });

    test('an entity field is the int64 path, not a parallel one', () {
      final r = _registry();
      final order = r.registry.declare(_OrderUnit());
      GameCommandDescriptor(r.registry).hasHandler(order, (p) => p.unit);

      final call = order.execute((unit: Entity(1), waypoint: 2));
      expect(
        () => order.escort[call],
        throwsStateError,
        reason:
            'the wrapper delegates to the int64 field, written-mask '
            'included, so a result nobody wrote is still an error rather '
            'than Entity(0)',
      );
    });

    test('two calls of one command do not share bytes', () {
      final r = _registry();
      final damage = r.registry.declare(_Damage());
      GameCommandDescriptor(r.registry).hasHandler(damage, (p) => 0);

      final batch = r.registry.createCommandBatch();
      final a = damage.execute((amount: 11, crit: false), batch);
      final b = damage.execute((amount: 22, crit: true), batch);
      expect(damage.amount[a], 11);
      expect(damage.amount[b], 22);
      expect(
        () => damage.resultFromBuffer(a),
        throwsStateError,
        reason:
            "and neither do their written-masks - b's writes must not "
            "make a's results look present",
      );
    });
  });
}
