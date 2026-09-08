// The other half of the discriminating pair in probe A. `WideFast.hp` came out
// `Uint16Field`, so it cannot be passed where eight bits are wanted.
//
// Expected: argument_type_not_assignable
import 'package:spike403/probe_a_core.dart';
import 'package:spike403/widths.dart';

void main() {
  takesUint8(WideFast().hp);
}
