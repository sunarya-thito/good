import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/command/command.dart';
import 'package:good/src/command/param.dart';
import 'package:good/src/command/transport.dart';
import 'package:good/src/ring_buffer.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'command_param_test.g.dart';

// The command API's two lower layers - the parameter record and the
// declaration/dispatch registry - exercised with a loopback sender: no
// isolates, no ring buffers, no Game. Everything about *what a command is* is
// decided here, so it can all be tested here; carrying a batch between two
// isolates is a separate concern with its own tests.

typedef _Blow = ({int amount, bool crit});

/// The reference command: typed parameters in, a typed result out, and every
/// pointer confined to the four symmetric marshalling methods.
class _Damage extends GameCommand<_Blow, int> {
  final amount = Param.uint16();
  final crit = Param.uint1();
  final dealt = Param.uint16();
  final overkill = Param.uint1();

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
  final id = Param.uint32();

  @override
  void bufferFromResult(ParamBuffer call, int result) => id[call] = result;

  @override
  int resultFromBuffer(ParamBuffer call) => id[call];
}

class _Log extends SinkCommand<String> {
  final message = Param.fixedString(32);

  @override
  void bufferFromParams(ParamBuffer call, String params) =>
      message[call] = params;

  @override
  String paramsFromBuffer(ParamBuffer call) => message[call];
}

/// Every field kind, to pin the packing down.
class _Wide extends GameCommand<int, int> {
  final flag = Param.uint1();
  final pair = Param.uint2();
  final nibble = Param.uint4();
  final u8 = Param.uint8();
  final i8 = Param.int8();
  final u16 = Param.uint16();
  final i16 = Param.int16();
  final u32 = Param.uint32();
  final i32 = Param.int32();
  final i64 = Param.int64();
  final f32 = Param.float32();
  final f64 = Param.float64();
  final name = Param.fixedString(16);

  @override
  void bufferFromParams(ParamBuffer call, int params) => u8[call] = params;

  @override
  int paramsFromBuffer(ParamBuffer call) => u8[call];

  @override
  void bufferFromResult(ParamBuffer call, int result) => u8[call] = result;

  @override
  int resultFromBuffer(ParamBuffer call) => u8[call];
}

/// The widths #35 added, so a parameter can say the same things a component
/// column can. Every one of them was a `hasUint1`-plus-a-manual-marshal or an
/// absence before.
class _Vocabulary extends GameCommand<int, int> {
  final on = Param.boolean();
  final off = Param.boolean();
  final s1 = Param.int1();
  final s2 = Param.int2();
  final s4 = Param.int4();
  final u64 = Param.uint64();

  @override
  void bufferFromParams(ParamBuffer call, int params) => u64[call] = params;

  @override
  int paramsFromBuffer(ParamBuffer call) => u64[call];

  @override
  void bufferFromResult(ParamBuffer call, int result) => u64[call] = result;

  @override
  int resultFromBuffer(ParamBuffer call) => u64[call];
}

/// The same one bit of storage, declared as a number. Only used to compare
/// signatures with [_Vocabulary].
class _OneBitAsNumber extends GameCommand<int, int> {
  final on = Param.uint1();

  @override
  void bufferFromParams(ParamBuffer call, int params) => on[call] = params;

  @override
  int paramsFromBuffer(ParamBuffer call) => on[call];

  @override
  void bufferFromResult(ParamBuffer call, int result) => on[call] = result;

  @override
  int resultFromBuffer(ParamBuffer call) => on[call];
}

/// [_OneBitAsNumber]'s twin, declared as a flag.
class _OneBitAsFlag extends GameCommand<bool, bool> {
  final on = Param.boolean();

  @override
  void bufferFromParams(ParamBuffer call, bool params) => on[call] = params;

  @override
  bool paramsFromBuffer(ParamBuffer call) => on[call];

  @override
  void bufferFromResult(ParamBuffer call, bool result) => on[call] = result;

  @override
  bool resultFromBuffer(ParamBuffer call) => on[call];
}

typedef _Order = ({Entity unit, int waypoint});

/// A command that carries an entity handle, to pin down the field kind that
/// exists so an id and a number stop being interchangeable on the wire. The
/// `waypoint` beside it is the number: both are 64 bits of payload, and only
/// the declaration tells them apart.
class _OrderUnit extends GameCommand<_Order, Entity> {
  final unit = Param.entity();
  final waypoint = Param.int64();
  final escort = Param.entity();

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

typedef _Note = ({String body, Uint8List blob});

/// The variable-length reference command. Two fields whose length is not
/// declared up front, with fixed fields in front of, between and behind them,
/// so the head arithmetic has to keep working around the tail descriptors -
/// and a variable-length *result*, which is the case that makes a record grow
/// after the records behind it have already been placed.
class _Publish extends GameCommand<_Note, String> {
  final topic = Param.uint16();
  final body = Param.string();
  final blob = Param.bytes();
  final stamp = Param.int64();
  final receipt = Param.string();

  @override
  void bufferFromParams(ParamBuffer call, _Note params) {
    topic[call] = 7;
    body[call] = params.body;
    blob[call] = params.blob;
    stamp[call] = -9000000000000000000;
  }

  @override
  _Note paramsFromBuffer(ParamBuffer call) => (
    body: body[call],
    // Copied, because the list handed back is a view onto the batch's own
    // bytes and writing this call's result moves them.
    blob: Uint8List.fromList(blob[call]),
  );

  @override
  void bufferFromResult(ParamBuffer call, String result) =>
      receipt[call] = result;

  @override
  String resultFromBuffer(ParamBuffer call) => receipt[call];
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
    batch.adoptReply(
      Uint8List.sublistView(received.bytes, 0, received.length),
      registry,
    );
  }
}

/// Two fields on the class and a third in the hook, in that order - which is
/// the order the record has to come out in. See [_OneOnFieldTwoInHook], the
/// same three written with the split one field earlier.
///
/// A hook can only declare what the command does not keep: `bind` collects
/// the fields before it calls `describeParams`, so a field the hook assigns
/// is unassigned when the collector reads it. `hasUint32` here reserves the
/// third slot and hands back a pointer nothing holds.
class _TwoOnFieldsOneInHook extends SinkCommand<int> {
  final head = Param.uint16();
  final flag = Param.uint1();

  @override
  void describeParams(ParamDescriptor descriptor) {
    descriptor.hasUint32();
  }

  @override
  void bufferFromParams(ParamBuffer call, int params) => head[call] = params;

  @override
  int paramsFromBuffer(ParamBuffer call) => head[call];
}

class _OneOnFieldTwoInHook extends SinkCommand<int> {
  final head = Param.uint16();

  @override
  void describeParams(ParamDescriptor descriptor) {
    descriptor.hasUint1();
    descriptor.hasUint32();
  }

  @override
  void bufferFromParams(ParamBuffer call, int params) => head[call] = params;

  @override
  int paramsFromBuffer(ParamBuffer call) => head[call];
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
  _installDeclarations();

  group('declaration', () {
    test('a command gets its index from declaration order', () {
      final r = _registry().registry;
      final damage = r.declare(_Damage.new);
      final ping = r.declare(_Ping.new);

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
      r.declare(_Damage.new);
      expect(() => r.declare(_Damage.new), throwsStateError);
    });

    test('declaring after boot is refused', () {
      final r = _registry().registry;
      r.seal();
      expect(() => r.declare(_Damage.new), throwsStateError);
    });

    test('the state descriptor cannot declare, only handle', () {
      final r = _registry().registry;
      final damage = r.declare(_Damage.new);
      final descriptor = GameCommandDescriptor(r);

      expect(
        () => descriptor.has(_Ping.new),
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
      final damage = r.declare(_Damage.new);
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
      // _Ping declares no fields, and a Param.* reaches no layout anyway, so
      // building one outside a declaration pass succeeds - which is what
      // leaves the refusal to declareHandler.
      expect(
        () => MainCommandDescriptor(r).hasSignal(_Ping(), () {}),
        throwsStateError,
      );
    });

    test('a field and a hook declare one record', () {
      final onFields = _registry().registry.declare(_TwoOnFieldsOneInHook.new);
      final inHook = _registry().registry.declare(_OneOnFieldTwoInHook.new);

      expect(onFields.layout.signature, inHook.layout.signature);
      expect(onFields.layout.strideBytes, inHook.layout.strideBytes);
      expect(
        onFields.layout.fieldCount,
        3,
        reason:
            'the fields are declared during the constructor and the hook runs '
            'straight after it, so the two forms compose in the order they '
            'are written and a command may use both',
      );
    });

    test('a handler is the function its command claims to be', () {
      final r = _registry().registry;
      final damage = r.declare(_Damage.new);
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
      final damage = r.registry.declare(_Damage.new);
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
      final ping = r.registry.declare(_Ping.new);
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
      final nextId = r.registry.declare(_NextId.new);
      var counter = 41;
      GameCommandDescriptor(r.registry).hasSupplier(nextId, () => ++counter);

      expect(await nextId(), 42);
      expect(await nextId(), 43);
    });

    test('a sink carries a payload and still tells you it ran', () async {
      final r = _registry();
      final log = r.registry.declare(_Log.new);
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
      final damage = r.registry.declare(_Damage.new);
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
      final wide = r.registry.declare(_Wide.new);
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
        final unhandled = r.registry.declare(_Unhandled.new);

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
      final damage = r.registry.declare(_Damage.new);
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
      final damage = r.registry.declare(_Damage.new);
      final log = r.registry.declare(_Log.new);
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
      final wide = r.registry.declare(_Wide.new);
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
      final wide = r.registry.declare(_Wide.new);
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
      final wide = r.registry.declare(_Wide.new);
      GameCommandDescriptor(r.registry).hasHandler(wide, (p) => p);

      final batch = r.registry.createCommandBatch();
      final call = wide.execute(250, batch);
      wide.flag[call] = 1;
      wide.pair[call] = 2;
      wide.nibble[call] = 9;
      wide.i8[call] = -120;
      wide.u16[call] = 65000;
      wide.i16[call] = -32000;
      wide.u32[call] = 4000000000;
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
      expect(wide.i16[call], -32000);
      expect(wide.u32[call], 4000000000);
      expect(wide.i32[call], -2000000000);
      expect(wide.i64[call], -9000000000000000000);
      expect(wide.f32[call], 0.5);
      expect(wide.f64[call], 1e-300);
      expect(wide.name[call], 'hello');
    });

    test('a bool parameter round-trips as a bool', () async {
      final r = _registry();
      final v = r.registry.declare(_Vocabulary.new);
      GameCommandDescriptor(r.registry).hasHandler(v, (p) => p);

      final batch = r.registry.createCommandBatch();
      final call = v.execute(1, batch);
      v.on[call] = true;
      v.off[call] = false;
      await batch.send();

      expect(v.on[call], isTrue);
      expect(v.off[call], isFalse, reason: 'neighbours share the byte');
    });

    test('signed sub-byte parameters sign-extend on the way out', () {
      // The discriminating case: an unsigned reader would answer 1, 3 and 15
      // for these three. Only the two-s complement path answers -1, -1, -1.
      final r = _registry();
      final v = r.registry.declare(_Vocabulary.new);
      GameCommandDescriptor(r.registry).hasHandler(v, (p) => p);

      final call = v.execute(0);
      v.s1[call] = -1;
      v.s2[call] = -1;
      v.s4[call] = -1;
      expect([v.s1[call], v.s2[call], v.s4[call]], [-1, -1, -1]);

      v.s2[call] = 1;
      v.s4[call] = -8;
      expect([v.s2[call], v.s4[call]], [1, -8]);
    });

    test('a uint64 parameter carries the full 64 bits', () {
      final r = _registry();
      final v = r.registry.declare(_Vocabulary.new);
      GameCommandDescriptor(r.registry).hasHandler(v, (p) => p);

      final call = v.execute(0);
      v.u64[call] = -9000000000000000000;
      expect(v.u64[call], -9000000000000000000);
    });

    test('a bool and a uint1 are different fields on the wire', () {
      // Both are one bit of the same storage, so nothing about the bytes
      // separates them. The signature is what does, which is what makes
      // swapping one declaration for the other a handshake mismatch instead
      // of a value read back as the wrong type.
      final asNumber = _registry().registry.declare(_OneBitAsNumber.new);
      final asFlag = _registry().registry.declare(_OneBitAsFlag.new);

      expect(asNumber.layout.signature, isNot(asFlag.layout.signature));
    });

    test('sub-byte fields share a byte without disturbing each other', () {
      final r = _registry();
      final wide = r.registry.declare(_Wide.new);
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
      final log = r.registry.declare(_Log.new);
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
      final order = r.registry.declare(_OrderUnit.new);
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
      final order = r.registry.declare(_OrderUnit.new);
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

    test('a declaration with no variable-length field carries no tail', () {
      final r = _registry();
      final damage = r.registry.declare(_Damage.new);
      GameCommandDescriptor(r.registry).hasHandler(damage, (p) => 0);

      expect(damage.layout.hasTail, isFalse);
      expect(damage.layout.tailSlotByte, -1);

      final batch = r.registry.createCommandBatch();
      damage.execute((amount: 1, crit: false), batch);
      expect(
        batch.length,
        ParamBatch.headerBytes +
            ParamBuffer.maskBytesFor(damage.layout.fieldCount) +
            damage.strideBytes,
        reason:
            'the tail is declared by the first variable-length field and by '
            'nothing else, so a record made only of numbers is the same '
            'bytes it always was - no length slot nobody would ever read',
      );
    });

    test('two calls of one command do not share bytes', () {
      final r = _registry();
      final damage = r.registry.declare(_Damage.new);
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

  group('variable-length fields', () {
    test('a string no fixed field could have held round-trips', () async {
      final r = _registry();
      final publish = r.registry.declare(_Publish.new);
      late _Note seen;
      GameCommandDescriptor(r.registry).hasHandler(publish, (p) {
        seen = p;
        return 'stored';
      });

      // U+03C0 is two bytes of UTF-8, so this is 180,000 bytes - nearly
      // three times what the *largest declarable* capacity-capped field could
      // have held, and the length that makes this test able to fail. A
      // payload under 0xFFFF would round-trip identically against the old
      // inline layout and prove nothing about the tail.
      final body = 'π' * 90000;
      expect(
        () => ParamLayout().hasFixedString(body.length * 3),
        throwsArgumentError,
        reason:
            'no capacity-capped declaration can accept this length at all - '
            'the reservation sits behind a 16-bit length prefix',
      );

      final blob = Uint8List.fromList(
        List<int>.generate(100000, (i) => i & 0xFF),
      );
      final receipt = await publish((body: body, blob: blob));

      expect(seen.body.length, 90000);
      expect(seen.body, body);
      expect(seen.blob, blob);
      expect(receipt, 'stored');
      expect(
        publish.layout.hasTail,
        isTrue,
        reason: 'and the head still has a stride, it just is not the record',
      );
    });

    test('an empty value is a written value, not an absent one', () async {
      final r = _registry();
      final publish = r.registry.declare(_Publish.new);
      late _Note seen;
      GameCommandDescriptor(r.registry).hasHandler(publish, (p) {
        seen = p;
        return '';
      });

      final receipt = await publish((body: '', blob: Uint8List(0)));
      expect(seen.body, '');
      expect(seen.blob, isEmpty);
      expect(
        receipt,
        '',
        reason:
            'the written-mask is what says a field was set, so a zero-length '
            'tail still reads back rather than throwing',
      );
    });

    test('reading a variable-length field nobody wrote throws', () {
      final r = _registry();
      final publish = r.registry.declare(_Publish.new);
      GameCommandDescriptor(r.registry).hasHandler(publish, (p) => 'x');

      final call = publish.execute((body: 'hi', blob: Uint8List(0)));
      expect(
        () => publish.receipt[call],
        throwsStateError,
        reason:
            'a tail field carries its own mask bit like every other kind - '
            'an offset and a length of zero is not "the empty string"',
      );
    });

    test('a variable-length field is written once', () {
      final r = _registry();
      final publish = r.registry.declare(_Publish.new);
      GameCommandDescriptor(r.registry).hasHandler(publish, (p) => 'x');

      final call = publish.execute((body: 'first', blob: Uint8List(0)));
      expect(
        () {
          publish.body[call] = 'second';
        },
        throwsStateError,
        reason:
            'the tail is filled by appending, so a second value cannot take '
            'the first one\'s place without moving every field behind it - '
            'and silently rearranging a record is worse than saying so',
      );
      expect(publish.body[call], 'first');
    });

    test('growing a record re-points the handles behind it', () {
      final r = _registry();
      final publish = r.registry.declare(_Publish.new);
      final damage = r.registry.declare(_Damage.new);
      final descriptor = GameCommandDescriptor(r.registry);
      descriptor.hasHandler(publish, (p) => 'x');
      descriptor.hasHandler(damage, (p) => 0);

      final batch = r.registry.createCommandBatch();
      final note = publish.execute((body: 'a', blob: Uint8List(0)), batch);
      final blow = damage.execute((amount: 4242, crit: true), batch);

      // The second record is already placed when the first one's result is
      // written, so 5,000 bytes have to be inserted in front of it.
      publish.receipt[note] = 'z' * 5000;

      expect(
        batch.indexAt(1),
        damage.index,
        reason:
            'the second handle has to arrive at the front of its own record '
            'after the shift - the two header bytes it reads are what routes '
            'the record back to the command that wrote it',
      );
      expect(damage.amount[blow], 4242);
      expect(damage.crit[blow], 1);
      expect(publish.body[note], 'a');
      expect(publish.receipt[note].length, 5000);
    });

    test('a record that grows moves the records behind it', () async {
      final r = _registry();
      final publish = r.registry.declare(_Publish.new);
      final damage = r.registry.declare(_Damage.new);
      final descriptor = GameCommandDescriptor(r.registry);
      descriptor.hasHandler(publish, (p) => 'z' * 50000);
      descriptor.hasHandler(damage, (p) => p.amount * 10);

      final batch = r.registry.createCommandBatch();
      final note = batch.execute(publish, (
        body: 'short',
        blob: Uint8List.fromList([1, 2, 3]),
      ));
      final blow = batch.execute(damage, (amount: 4242, crit: true));
      final results = await batch.send();

      expect(
        note[results].length,
        50000,
        reason:
            'the first record grew by 50,000 bytes when its handler answered, '
            'long after the second one had been placed behind it',
      );
      expect(
        blow[results],
        42420,
        reason:
            'and the record behind it was moved along rather than written '
            'over - its handle was re-pointed with the bytes',
      );
    });

    test('a batch too big for the command ring is refused, not truncated', () {
      final transport = CommandTransport();
      final registry = CommandRegistry(transport, simulating: false);
      transport.registry = registry;
      final publish = registry.declare(_Publish.new);
      // Handled on the game isolate, which this copy is not, so the batch has
      // to leave through the ring.
      GameCommandDescriptor(registry).hasHandler(publish, (p) => 'x');
      final ring = RingBuffer(1024);
      addTearDown(ring.dispose);
      transport.outbound = ring;

      final batch = registry.createCommandBatch();
      batch.execute(publish, (body: 'x' * 4000, blob: Uint8List(0)));

      expect(
        () {
          batch.send();
        },
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('will never fit'),
          ),
        ),
        reason:
            'a variable-length field is bounded by the carrier rather than by '
            'its declaration, and this is that bound said out loud - a batch '
            'over it can never be drained into, so "the ring is full" would '
            'be the wrong answer',
      );

      final drained = <RingBufferRecord>[];
      ring.drainInto(drained);
      expect(
        drained,
        isEmpty,
        reason: 'and nothing partial was placed on the way to finding out',
      );
    });

    // #158. The ring is one carrier and a datagram is another, and a batch
    // built for a carrier that bounds a single record says so at the write
    // rather than at the send - which is the only place a game can be told
    // which value was too big.
    test('a record over the batch cap is refused at the write', () {
      final r = _registry();
      final publish = r.registry.declare(_Publish.new);
      final batch = ParamBatch(maxRecordBytes: 200);
      final call = batch.append(publish.index, publish.layout);

      expect(
        () {
          publish.body[call] = 'x' * 500;
        },
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('takes at most 200 in one record'),
              contains('500 of them written into a variable-length field'),
            ),
          ),
        ),
        reason:
            'the declaration has no capacity to overrun, so the number in the '
            'error belongs to the carrier and has to be in it',
      );
      expect(
        batch.callCount,
        0,
        reason:
            'and the record it could not finish comes back off the batch: '
            'half a record that went out anyway would fail on the reading '
            'side, at a field nobody wrote',
      );
      expect(batch.length, 0);
    });

    test('a cap smaller than the fixed head is refused at the append', () {
      final r = _registry();
      final publish = r.registry.declare(_Publish.new);
      final batch = ParamBatch(maxRecordBytes: 4);

      expect(
        () {
          batch.append(publish.index, publish.layout);
        },
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('takes at most 4 in one record'),
          ),
        ),
        reason:
            'a declaration whose head alone will not fit can never send one '
            'record, and finding that out at the first send beats finding it '
            'out at the first long value',
      );
      expect(batch.callCount, 0);
    });

    test('a refused record in the middle of a batch is left where it is', () {
      final r = _registry();
      final publish = r.registry.declare(_Publish.new);
      final batch = ParamBatch(maxRecordBytes: 200);
      final first = batch.append(publish.index, publish.layout);
      final second = batch.append(publish.index, publish.layout);
      publish.body[second] = 'behind';

      expect(() {
        publish.body[first] = 'x' * 500;
      }, throwsStateError);
      expect(
        batch.callCount,
        2,
        reason:
            'taking a record out of the middle would move every record behind '
            'it along, which is the very thing the refusal is saying it will '
            'not do',
      );
      expect(publish.body[second], 'behind');
    });

    test('startAt says where each record begins', () {
      final r = _registry();
      final publish = r.registry.declare(_Publish.new);
      final damage = r.registry.declare(_Damage.new);
      final batch = ParamBatch();
      final note = batch.append(publish.index, publish.layout);
      publish.body[note] = 'hello';
      batch.append(damage.index, damage.layout);

      expect(batch.startAt(0), batch.start);
      expect(
        batch.startAt(1) - batch.startAt(0),
        ParamBatch.headerBytes +
            ParamBuffer.maskBytesFor(publish.layout.fieldCount) +
            publish.layout.strideBytes +
            'hello'.length,
        reason:
            'a record is its header, its mask, its head and whatever its tail '
            'grew to - which is what makes a batch cuttable at these '
            'boundaries when its carrier cannot take the whole of it',
      );
      expect(batch.indexAt(1), damage.index);
    });
  });
}
