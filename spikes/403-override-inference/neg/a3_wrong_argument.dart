// The shorthand's argument is checked against the width class's static, so a
// value of the wrong type cannot reach it.
//
// Expected: argument_type_not_assignable
import 'package:spike403/widths.dart';

class Player {
  final speed = Field.uint8(10);
}

class Broken extends Player {
  // ignore: overridden_fields
  @override
  final speed = .initial('nope');
}
