/// A: does an overriding field with no type annotation take its type from the
/// member it overrides, before its initialiser is type-checked?
///
/// Everything in #403 rests on this. If it holds, `.initial(20)`'s context
/// type is the overridden field's type and the width comes down with it.
library;

import 'widths.dart';

class Player {
  // The base's own type is inferred too - from `Field.uint8`'s return type,
  // not from an annotation. That is the second hop.
  final speed = Field.uint8(10);
}

class Fast extends Player {
  @override
  final speed = .initial(20);
}

/// The same shorthand text, one class over, resolving to a different type.
/// Nothing but the overridden member's type can account for the difference,
/// so this is what rules out an ambient resolution of `.initial`.
class Wide {
  final hp = Field.uint16(10);
}

class WideFast extends Wide {
  @override
  final hp = .initial(20);
}

void checkStaticTypes() {
  takesUint8(Fast().speed);
  takesUint16(WideFast().hp);

  // Also a supertype, which says the hierarchy is intact rather than the
  // member having degraded to something that swallows every argument.
  takesInitialInt(Fast().speed);

  // A member only the width class declares.
  final int width = Fast().speed.bitWidth;
  assert(width == 8);

  final int value = Fast().speed.initialValue;
  assert(value == 20);
}
