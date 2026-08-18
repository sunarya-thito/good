// Proof-of-concept: passing a raw FFI pointer address across Isolate.spawn
// and reading/writing the same native memory from both isolates with zero
// copying. This is the mechanism `MemoryPool` (../lib/src/pool.dart) and
// `RingBuffer` (../lib/src/ring_buffer.dart) build on for real - kept here
// as a minimal, runnable reference, not part of the package's public API.
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart'; // Required for calloc and free

void main() async {
  print('--- FFI Shared Memory Test ---');

  // 1. Allocate unmanaged C-memory (e.g., 100 bytes for sprite data)
  final int bufferSize = 100;
  final Pointer<Uint8> sharedMemoryPointer = calloc<Uint8>(bufferSize);

  // 2. Create a Dart Uint8List "view" into that C-memory for the Main Isolate.
  // This does NOT copy the data into Dart. It is a direct window to the RAM.
  final Uint8List mainRenderView = sharedMemoryPointer.asTypedList(bufferSize);

  // 3. Get the raw memory address as an integer. This is what we send across the port.
  final int memoryAddress = sharedMemoryPointer.address;
  print('Main: Allocated memory at address $memoryAddress');

  // 4. Setup communication
  final receivePort = ReceivePort();

  // 5. Spawn the Game Isolate, passing the raw address and port
  await Isolate.spawn(gameTickIsolate, {
    'sendPort': receivePort.sendPort,
    'address': memoryAddress,
    'size': bufferSize,
  });

  // 6. Listen for "render ticks" from the game isolate
  await for (final message in receivePort) {
    if (message == 'tick') {
      // READ the memory directly! No materializing, no copying.
      final spriteId = mainRenderView[0];
      final xPos = mainRenderView[1];
      final yPos = mainRenderView[2];

      print('Main (Render): Sprite $spriteId is at X: $xPos, Y: $yPos');
    } else if (message == 'done') {
      break;
    }
  }

  // 7. CRITICAL: Free the C-memory when done to prevent memory leaks!
  calloc.free(sharedMemoryPointer);
  print('Main: Memory freed. Exiting.');
}

// --- GAME ISOLATE ---
void gameTickIsolate(Map<String, dynamic> args) async {
  final SendPort mainPort = args['sendPort'];
  final int address = args['address'];
  final int size = args['size'];

  // 1. Reconstruct the C-pointer from the raw integer address
  final Pointer<Uint8> sharedPointer = Pointer<Uint8>.fromAddress(address);

  // 2. Create a Dart Uint8List "view" into that C-memory for the Game Isolate
  final Uint8List gameWriteView = sharedPointer.asTypedList(size);

  // 3. Run the Game Loop (Simulating 20 TPS)
  for (int i = 1; i <= 5; i++) {
    // Write directly to the shared RAM
    gameWriteView[0] = 42; // Sprite ID
    gameWriteView[1] = 100 + i; // X position moving
    gameWriteView[2] = 50; // Y position static

    // Send a tiny signal to Main that a tick finished
    // (Sending a simple string or int has almost zero overhead)
    mainPort.send('tick');

    // Wait 50ms (simulating a 20 ticks-per-second loop)
    await Future.delayed(const Duration(milliseconds: 50));
  }

  mainPort.send('done');
}
