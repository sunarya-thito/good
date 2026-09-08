// The phantom form analyses clean, which on its own is compatible with both
// type arguments having gone to `dynamic`. These must be compile errors: the
// width argument was inferred from the overridden member, and so was the
// value type.
//
// Expected: argument_type_not_assignable, then invalid_assignment
import 'package:spike403/probe_d_phantom.dart';

void main() {
  takesW16(DSub().speed);
  takesW8(DSub().hp);
  final String s = DSub().speed.initialValue;
  print(s);
}
