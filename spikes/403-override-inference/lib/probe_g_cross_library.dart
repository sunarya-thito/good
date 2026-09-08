/// G: the override in a different library from the declaration it overrides.
///
/// That is the case the feature exists for - a component lives in `good` or
/// `goo2d` and the prefab overriding it lives in the game.
library;

import 'probe_a_core.dart';
import 'widths.dart';

class GameFast extends Player {
  @override
  final speed = .initial(30);
}

void checkStaticTypes() {
  takesUint8(GameFast().speed);
  final int value = GameFast().speed.initialValue;
  print(value);
}
