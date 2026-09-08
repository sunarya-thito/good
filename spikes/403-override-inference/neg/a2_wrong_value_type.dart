// The value type must survive too - if the member had degraded to `dynamic`
// the access would analyse clean and fail only at run time.
//
// Expected: invalid_assignment
import 'package:spike403/probe_a_core.dart';

void main() {
  final String s = Fast().speed.initialValue;
  print(s);
}
