// A getter that had degraded to `dynamic` would let this through and fail at
// run time instead. It must be a compile error.
//
// Expected: invalid_assignment
import 'package:spike403/probe_b_members.dart';

void main() {
  final String a = B3Sub().speed.initialValue;
  final String b = B4Sub().speed.initialValue;
  final String c = B8Sub().speed.initialValue;
  print('$a$b$c');
}
