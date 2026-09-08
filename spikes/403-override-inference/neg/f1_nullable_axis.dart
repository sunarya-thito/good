// The nullable axis on a type parameter is only worth anything if it still
// discriminates. `null` must not reach the non-nullable half, the two halves
// must not be interchangeable, and a public width type must not accept
// another width's.
//
// Expected: three errors and one pass. The pass is the finding:
// `takesNullable(FSub().ammo)` is accepted, because Dart generics are
// covariant and `NullableUint8Field<int>` is a subtype of
// `NullableUint8Field<int?>`. It does not weaken the override - an overriding
// field is checked against the exact inherited type, which is what the first
// error shows - but a nullable parameter elsewhere will take a non-nullable
// column, which seventeen separate classes would have refused.
import 'package:spike403/probe_f_shape.dart';

class Bad extends FBase {
  // ignore: overridden_fields
  @override
  final ammo = .initial(null);
}

void main() {
  takesNonNull(FSub().spare);
  takesNullable(FSub().ammo);
  takesU16(FSub().speed);
}
