// Does `Isolate.spawn` accept a message whose object graph contains a
// `dart:ffi` Pointer?
//
// This gates the scene overhaul's boot-order inversion. Today `Game._boot()`
// runs *after* the spawn on both copies, and `Game`'s class doc states as a
// hard requirement that the object must hold "no unsendable state before
// start(): no ReceivePort, no Pointer, no initialized scene". Describing
// everything on the main isolate first would break that rule by construction:
// a described Game holds every sealed ArchetypeStorage (each with a calloc'd
// `Pointer<Uint8> _defaultRow`) and a MemoryPool full of pages.
//
// If pointers are sendable, the handoff stays a plain deep copy and the game
// isolate wakes up fully described. If not, main has to send a numeric layout
// description and the game isolate has to rebuild its storage from it - much
// more machinery, and it needs costing before Landing 3 is planned.
//
// A standalone `dart run` script rather than a test, per the standing rule in
// this repo: cross-isolate work belongs in tool/, never in the Flutter test
// runner (see ring_buffer_stress.dart's doc for the VM crash that established
// it).

import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Stands in for a described `Game`: a plain object holding native memory the
/// same way `ArchetypeStorage` holds its default row.
class DescribedThing {
  DescribedThing(this.label, this.bytes) : block = calloc<Uint8>(bytes);

  final String label;
  final int bytes;
  final Pointer<Uint8> block;

  /// Mirrors the nesting a real Game has: Game -> ArchetypeStorage -> Pointer,
  /// and Game -> MemoryPool -> MemoryPage -> TripleBuffer -> Pointer.
  final List<DescribedThing> children = <DescribedThing>[];

  void write(int value) {
    final view = block.asTypedList(bytes);
    for (var i = 0; i < bytes; i++) {
      view[i] = value;
    }
  }

  void dispose() {
    for (final child in children) {
      child.dispose();
    }
    calloc.free(block);
  }
}

void _entry(List<Object> message) {
  final thing = message[0] as DescribedThing;
  final reply = message[1] as SendPort;
  // Two questions, not one. First: did the graph arrive at all? Second, and
  // the one that actually matters: does the copied Pointer still address the
  // *same* native memory the parent wrote to, or did the copy give us a
  // dangling or duplicated address?
  final view = thing.block.asTypedList(thing.bytes);
  final childView =
      thing.children.first.block.asTypedList(thing.children.first.bytes);
  reply.send(<Object>[
    thing.label,
    thing.block.address,
    view[0],
    thing.children.first.block.address,
    childView[0],
  ]);
}

Future<void> main() async {
  final root = DescribedThing('root', 64)..write(0xAB);
  final child = DescribedThing('child', 32)..write(0xCD);
  root.children.add(child);

  print('parent: root block @${root.block.address}, child @${child.block.address}');

  final fromChild = ReceivePort();
  try {
    await Isolate.spawn<List<Object>>(_entry, <Object>[root, fromChild.sendPort]);
  } catch (error) {
    print('');
    print('RESULT: NOT SENDABLE - Isolate.spawn rejected the message.');
    print('  $error');
    print('');
    print('  The boot-order inversion cannot hand the game isolate a described');
    print('  Game by deep copy. Main must send a numeric layout description');
    print('  and the game isolate must rebuild its ArchetypeStorages from it.');
    fromChild.close();
    root.dispose();
    return;
  }

  final reply = (await fromChild.first) as List;
  fromChild.close();

  final sameRoot = reply[1] as int == root.block.address;
  final sameChild = reply[3] as int == child.block.address;
  final rootValue = reply[2] as int;
  final childValue = reply[4] as int;

  print('child : root block @${reply[1]}, child @${reply[3]}');
  print('');
  if (sameRoot && sameChild && rootValue == 0xAB && childValue == 0xCD) {
    print('RESULT: SENDABLE, and the addresses are shared.');
    print('  Both pointers arrived at the same addresses and read back the');
    print('  bytes the parent wrote (0x${rootValue.toRadixString(16)}, '
        '0x${childValue.toRadixString(16)}).');
    print('  A described Game can cross by plain deep copy.');
  } else {
    print('RESULT: sent, but NOT shared as-is.');
    print('  addresses match: root=$sameRoot child=$sameChild');
    print('  values read back: 0x${rootValue.toRadixString(16)} / '
        '0x${childValue.toRadixString(16)} (expected 0xab / 0xcd)');
  }

  root.dispose();
}
