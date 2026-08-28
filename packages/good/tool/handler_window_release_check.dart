// #245: does the guard still fire when the asserts are gone?
//
//   dart compile exe packages/good/tool/handler_window_release_check.dart -o build/hw.exe
//   ./build/hw.exe
//
// AOT, and that is the whole point of the file. `flutter test` has no release
// mode - there is no `--release`, no way to turn asserts off - so a suite that
// only ever runs with them on cannot see the row of #245's table that mattered
// most: the write that lands in the write slot in a shipped build, is erased by
// the next `beginTick`, and says nothing on the way out because the `assert`
// that would have caught it is not in the binary.
//
// `dart compile exe` produces a binary with asserts disabled, which is the same
// state a `flutter build` ships. [_assertsAreOff] is the control that proves it
// rather than assuming it: if that check ever reports that asserts are on, every
// other line here is measuring the wrong build and says so.
//
// # What this can and cannot reach
//
// It imports `package:good/src/pool.dart` and nothing else, because that is
// the whole of what compiles without Flutter - `archetype.dart` pulls in
// `struct.dart`, which pulls in `game_state.dart`, which pulls in `dart:ui`.
// So what runs here is the primitive: `MemoryPool`'s window, the write epoch
// the row cache compares against, and the two refusals every mutating path in
// the engine calls.
//
// The call sites that reach them - `ArchetypeStorage.rowWrite`,
// `allocateRow`, `Entity.destroy`, `GameState.unloadScene`, the state
// channel's setter, and `CommandTransport` opening the window in the first
// place - are covered in `test/game_test.dart` under JIT. That split is
// honest: those are plain unconditional calls with no `assert` anywhere on the
// path, so the build cannot change whether they run, and this file is what
// proves the thing they run into does not vanish.
import 'dart:io';

import 'package:good/src/pool.dart';

int _failures = 0;

void _check(String what, bool ok) {
  stdout.writeln('${ok ? 'ok  ' : 'FAIL'}  $what');
  if (!ok) _failures++;
}

/// True when this binary has asserts compiled out.
///
/// The control. Every other line below is only worth reading if this is true,
/// because with asserts on the old `data_layout` assertion would be doing the
/// work and the new guard could be absent without anything here noticing.
bool _assertsAreOff() {
  try {
    assert(false, 'asserts are enabled');
    return true;
  } on AssertionError {
    return false;
  }
}

/// What a refusal threw, or null if it did not.
String? _refusal(void Function() body) {
  try {
    body();
    return null;
  } on StateError catch (error) {
    return error.message;
  }
}

void main() {
  final off = _assertsAreOff();
  _check('this binary has asserts compiled out', off);
  if (!off) {
    stdout.writeln(
      '\nasserts are on, so this run proves nothing about a release build. '
      'Compile with `dart compile exe`, not `dart run --enable-asserts`.',
    );
    exit(1);
  }

  final pool = MemoryPool(pageSize: 4096, maxPages: 4);

  // 1. The ordinary state: nothing is refused, and the write path compares
  //    exactly the number it always compared.
  _check(
    'with no handler running, the world is mutable',
    _refusal(() => pool.requireWorldMutable('x')) == null,
  );
  _check(
    'and the write epoch tracks the read epoch',
    pool.writeEpoch == pool.epoch,
  );

  // 2. A receipt-delivered handler. The world is refused; a state channel is
  //    not, because publishing on one is the answer leg the lane has instead
  //    of a reply.
  final beforeReceipt = pool.openHandlerWindow(HandlerWindow.receipt);
  final worldRefusal = _refusal(
    () => pool.requireWorldMutable('A scene was unloaded'),
  );
  _check(
    'a receipt handler is refused the world with asserts off',
    worldRefusal != null && worldRefusal.contains('receipt-delivered'),
  );
  _check(
    'and the write epoch no longer matches any cache',
    pool.writeEpoch != pool.epoch,
  );
  _check(
    'a receipt handler may still publish on a state channel',
    _refusal(pool.requireChannelWritable) == null,
  );

  // 3. A tick window opened from inside that handler wins: `stepOnce` is a
  //    receipt-delivered handler that runs a whole fixed step.
  pool.beginTick();
  _check(
    'a fixed step run from inside a receipt handler may write',
    _refusal(() => pool.requireWorldMutable('x')) == null &&
        pool.writeEpoch == pool.epoch,
  );
  pool.commitTick();
  _check(
    'and the window closes over it again when the step commits',
    _refusal(() => pool.requireWorldMutable('x')) != null &&
        pool.writeEpoch != pool.epoch,
  );
  pool.closeHandlerWindow(beforeReceipt);

  // 4. The read-only lane, which is held to the stricter promise.
  final beforeReadOnly = pool.openHandlerWindow(HandlerWindow.readOnly);
  final channelRefusal = _refusal(pool.requireChannelWritable);
  _check(
    'a read-only handler is refused a state channel too',
    channelRefusal != null && channelRefusal.contains('read-only'),
  );
  _check(
    'and the world with it',
    _refusal(() => pool.requireWorldMutable('x')) != null,
  );
  pool.closeHandlerWindow(beforeReadOnly);

  // 5. Nesting restores the kind, not just the fact - a receipt handler can
  //    send a receipt batch of its own.
  final outer = pool.openHandlerWindow(HandlerWindow.readOnly);
  final inner = pool.openHandlerWindow(HandlerWindow.receipt);
  pool.closeHandlerWindow(inner);
  _check(
    'closing an inner window restores the outer one, kind and all',
    _refusal(pool.requireChannelWritable) != null,
  );
  pool.closeHandlerWindow(outer);
  _check(
    'and closing the outer one puts everything back',
    _refusal(() => pool.requireWorldMutable('x')) == null &&
        pool.writeEpoch == pool.epoch,
  );

  pool.dispose();
  stdout.writeln(
    _failures == 0
        ? '\nall checks passed with asserts off'
        : '\n$_failures check(s) failed',
  );
  exit(_failures == 0 ? 0 : 1);
}
