// The generic case is the one that could quietly widen: if `E` came from the
// argument instead of from the overridden member's type argument, a member of
// some other enum would be accepted and the column would change type. It must
// be a compile error. The nullable case is the other half - a non-nullable
// width must not accept `null`.
//
// Expected: argument_type_not_assignable on both
import 'package:spike403/probe_c_values.dart';

enum Other { one }

class Bad extends CBase {
  // ignore: overridden_fields
  @override
  final team = .initial(Other.one);

  // ignore: overridden_fields
  @override
  final speed = .initial(null);
}
