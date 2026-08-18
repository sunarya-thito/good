// Follow-up to spawn_pointer_spike.dart. Pointers cross intact - but a
// described `Game` carries more than pointers, and this checks the two things
// the deep-copy model might silently fail to carry:
//
//   1. STATIC registry state (ArchetypeRegistry._storages and friends).
//   2. CACHED typed-data views over native memory
//      (_StateChannelBase._slotViews is a List<ByteData> built once from
//      Pointer.asTypedList).
//
// Both matter: (1) is what Query.run() walks, and (2) is what every state
// channel read and write goes through.

import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Stands in for ArchetypeRegistry: mutable static state, populated on main.
abstract final class Registry {
  static final List<String> entries = <String>[];
}

/// Stands in for _StateChannelBase: a Pointer plus a cached view built from it.
class Cached {
  Cached(this.bytes) : block = calloc<Uint8>(bytes) {
    view = ByteData.sublistView(block.asTypedList(bytes));
  }

  final int bytes;
  final Pointer<Uint8> block;
  late final ByteData view;
}

void _entry(List<Object> message) {
  final cached = message[0] as Cached;
  final reply = message[1] as SendPort;

  // Write through the CACHED view, as a state channel does.
  cached.view.setUint8(0, 0x99);
  // And read the same byte straight off the pointer, bypassing the cache.
  final direct = cached.block.asTypedList(cached.bytes)[0];

  reply.send(<Object>[Registry.entries.length, direct, cached.block.address]);
}

Future<void> main() async {
  Registry.entries.addAll(['archetype0', 'archetype1', 'archetype2']);
  final cached = Cached(16);
  cached.view.setUint8(0, 0x11);

  final port = ReceivePort();
  await Isolate.spawn<List<Object>>(_entry, <Object>[cached, port.sendPort]);
  final reply = (await port.first) as List;
  port.close();

  final registryCount = reply[0] as int;
  final directAfterWrite = reply[1] as int;
  final sameAddress = reply[2] as int == cached.block.address;
  final mainSees = cached.block.asTypedList(16)[0];

  print('1. STATIC REGISTRY');
  print('   main populated ${Registry.entries.length}, child saw $registryCount');
  print(registryCount == Registry.entries.length
      ? '   -> CROSSES'
      : '   -> DOES NOT CROSS. Statics are per-isolate; the child starts empty.');
  print('');
  print('2. CACHED TYPED-DATA VIEW');
  print('   pointer address identical: $sameAddress');
  print('   child wrote 0x99 through its cached view;');
  print('   child then read 0x${directAfterWrite.toRadixString(16)} straight off the pointer,');
  print('   main now reads 0x${mainSees.toRadixString(16)} off the same pointer.');
  print(mainSees == 0x99
      ? '   -> VIEW STILL POINTS AT NATIVE MEMORY'
      : '   -> VIEW WAS COPIED BY VALUE. The child wrote into a detached Dart\n'
        '      heap buffer; the shared native memory never changed.');

  calloc.free(cached.block);
}
