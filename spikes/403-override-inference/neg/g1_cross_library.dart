// The control for G. Resolution across libraries must still be exact.
//
// Expected: two errors
import 'package:spike403/probe_g_cross_library.dart';
import 'package:spike403/widths.dart';

void main() {
  takesUint16(GameFast().speed);
  final String s = GameFast().speed.initialValue;
  print(s);
}
