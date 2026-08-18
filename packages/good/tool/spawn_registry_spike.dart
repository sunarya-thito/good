// Third spike: of the state that would have to be "passed over" to the game
// isolate, which parts are actually sendable?
//
// The registries hold three shapes the previous spikes did not cover:
//   - `Type` objects, as ComponentTypeRegistry's map keys
//   - a closure, as HeapObjectRegistry legitimately stores
//   - an object with a non-sendable native handle (stood in for here by a
//     ReceivePort, which is unsendable for the same reason dart:ui.Image is)
//
// Anything that fails here cannot be carried by making it reachable from the
// Game - it has to keep being rebuilt on the far side instead.

import 'dart:isolate';

class Marker {}

class Holder {
  Holder(this.label);
  final String label;
  Map<Type, int> types = <Type, int>{};
  List<Object?> objects = <Object?>[];
}

void _entry(List<Object> m) {
  final holder = m[0] as Holder;
  final reply = m[1] as SendPort;
  reply.send(<Object>[
    holder.types.length,
    holder.types[Marker] ?? -1,
    holder.objects.length,
  ]);
}

Future<void> _try(String what, Holder holder) async {
  final port = ReceivePort();
  try {
    await Isolate.spawn<List<Object>>(_entry, <Object>[holder, port.sendPort]);
    final reply = (await port.first) as List;
    print('  $what: SENDABLE  (types=${reply[0]}, Marker->${reply[1]}, '
        'objects=${reply[2]})');
  } catch (e) {
    final msg = e.toString().split('\n').first;
    print('  $what: NOT SENDABLE - $msg');
  } finally {
    port.close();
  }
}

Future<void> main() async {
  print('Can these be carried on the Game so they ride the spawn?');
  print('');

  final types = Holder('types')..types[Marker] = 7;
  await _try('Map<Type,int> (ComponentTypeRegistry)      ', types);

  final closure = Holder('closure')..objects.add(() => 42);
  await _try('a closure   (HeapObjectRegistry)           ', closure);

  final native = Holder('native')..objects.add(ReceivePort());
  await _try('a native handle (stands in for ui.Image)   ', native);
  (native.objects.first as ReceivePort).close();
}
