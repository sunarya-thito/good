// The negative for every member kind in probe B at once. Each of the nine
// overrides must have come out `Uint8Field`, so each of these must be a
// compile error. Nine clean lines in the probe plus nine errors here is what
// the pair of them says; either half alone says nothing.
//
// Expected: nine argument_type_not_assignable
import 'package:spike403/probe_b_members.dart';
import 'package:spike403/widths.dart';

void main() {
  takesUint16(B1Sub().speed);
  takesUint16(B2Sub().speed);
  takesUint16(B3Sub().speed);
  takesUint16(B4Sub().speed);
  takesUint16(B5Sub().speed);
  takesUint16(B6Sub().speed);
  takesUint16(B7Leaf().speed);
  takesUint16(B8Sub().speed);
  takesUint16(B9Sub().speed);
}
