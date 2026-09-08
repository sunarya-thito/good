// A clean analysis of probe A proves nothing on its own. This is the negative
// that must fail: the overriding field's type is `Uint8Field` and not merely
// `InitialPointer<int>`, so handing it to something that wants sixteen bits
// has to be a compile error.
//
// Expected: argument_type_not_assignable
import 'package:spike403/probe_a_core.dart';
import 'package:spike403/widths.dart';

void main() {
  takesUint16(Fast().speed);
}
