/// C: the value types the vocabulary actually has, and whether any of them
/// forces a wrapper at a call site.
///
/// `Field.uint8(10)` must keep taking a plain `int`; `Field.uint8(Uint8(10))`
/// is the shape #403 rejects. The same has to hold for `.initial`.
library;

import 'widths.dart';

enum Team { red, blue }

class CBase {
  final speed = Field.uint8(10);
  final gravity = Field.float64(9.8);
  final alive = Field.boolean(true);
  final owner = Field.entity(const Entity(3));
  final ammo = Field.optUint8(7);
  final team = Field.enumOf(Team.values, Team.red);
}

class CSub extends CBase {
  @override
  final speed = .initial(20);

  @override
  final gravity = .initial(1.6);

  @override
  final alive = .initial(false);

  @override
  final owner = .initial(const Entity(9));

  @override
  final ammo = .initial(null);

  // The generic case. `E` has to come from the overridden member's type
  // argument, not from the argument passed here.
  @override
  final team = .initial(Team.blue);
}

/// A named constructor works where a static does, which matters because a
/// static cannot be inherited - every width class would have to declare its
/// own either way.
final class Int32Field extends InitialPointer<int> {
  Int32Field(super.initialValue);

  Int32Field.initial(super.initialValue);
}

class CtorBase {
  final hp = Int32Field(10);
}

class CtorSub extends CtorBase {
  @override
  final hp = .initial(20);
}

void checkStaticTypes() {
  final int speed = CSub().speed.initialValue;
  final double gravity = CSub().gravity.initialValue;
  final bool alive = CSub().alive.initialValue;
  final Entity owner = CSub().owner.initialValue;
  final int? ammo = CSub().ammo.initialValue;
  final Team team = CSub().team.initialValue;
  final Int32Field hp = CtorSub().hp;
  print('$speed $gravity $alive $owner $ammo $team $hp');
}
