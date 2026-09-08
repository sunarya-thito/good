/// B: which member kinds the mechanic works across, and how many hops of
/// inference it survives.
///
/// The engine's declarations are a mix, and #265 landed
/// `@override final textCapacity = 8;` over an abstract getter, so at least
/// one of these directions is already in the tree.
library;

import 'widths.dart';

// B1 - field over field, with the base's own type written out. The control
// for hop count: if this worked and B2 did not, the failure would be the
// second hop rather than the mechanic.
class B1Base {
  final Uint8Field speed = Field.uint8(10);
}

class B1Sub extends B1Base {
  @override
  final speed = .initial(20);
}

// B2 - field over field, base type inferred from the static's return type.
// Two hops.
class B2Base {
  final speed = Field.uint8(10);
}

class B2Sub extends B2Base {
  @override
  final speed = .initial(20);
}

// B3 - field over an abstract getter. This is #265's shape.
abstract class B3Base {
  Uint8Field get speed;
}

class B3Sub extends B3Base {
  @override
  final speed = .initial(20);
}

// B4 - field over a concrete getter.
class B4Base {
  Uint8Field get speed => Field.uint8(10);
}

class B4Sub extends B4Base {
  @override
  final speed = .initial(20);
}

// B5 - `late final` over a field. The `super.speed.initial(20)` form needs
// `late`, so the question is whether `late` costs the inference anything.
class B5Base {
  final speed = Field.uint8(10);
}

class B5Sub extends B5Base {
  @override
  late final speed = .initial(20);
}

// B6 - field over a field a mixin declares. Components are mixins here.
mixin B6Mixin {
  final speed = Field.uint8(10);
}

class B6Sub with B6Mixin {
  @override
  final speed = .initial(20);
}

// B7 - two levels of override. The middle one's type is itself inferred from
// a shorthand, so this is three hops.
class B7Base {
  final speed = Field.uint8(10);
}

class B7Mid extends B7Base {
  @override
  final speed = .initial(20);
}

class B7Leaf extends B7Mid {
  @override
  final speed = .initial(30);
}

// B8 - field over a field reached through an interface rather than a
// superclass.
abstract interface class B8Interface {
  Uint8Field get speed;
}

class B8Sub implements B8Interface {
  @override
  final speed = .initial(20);
}

// B9 - a getter over a field, which is what #198 first proposed. Included so
// the report can say whether the shorthand reaches it too.
class B9Base {
  final speed = Field.uint8(10);
}

class B9Sub extends B9Base {
  @override
  Uint8Field get speed => .initial(20);
}

void checkStaticTypes() {
  takesUint8(B1Sub().speed);
  takesUint8(B2Sub().speed);
  takesUint8(B3Sub().speed);
  takesUint8(B4Sub().speed);
  takesUint8(B5Sub().speed);
  takesUint8(B6Sub().speed);
  takesUint8(B7Leaf().speed);
  takesUint8(B8Sub().speed);
  takesUint8(B9Sub().speed);
}
