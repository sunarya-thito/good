import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_example/main.dart';

/// The example app itself, started the way its own `_MyAppState` starts it.
///
/// `Game.start` spawns, and `Isolate.spawn` sends the game as a deep copy: no
/// `main` and no constructor runs on the copy that boots, so the only record
/// of what this library declares that reaches it is `Game.declarations`. This
/// file's own `main` deliberately installs nothing - if it did, it would be
/// installing on the isolate that is not the one under test.
///
/// Nothing else exercises `lib/main.dart`, and it booted on main and threw on
/// the game isolate for as long as its table was installed from a `main`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the example game boots on the isolate it is spawned onto', () async {
    final game = await Game.start(MyAwesomeGame.new);
    addTearDown(game.stop);
    expect(game.isRunning, isTrue);
  });
}
