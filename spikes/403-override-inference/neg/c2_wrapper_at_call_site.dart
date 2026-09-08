// The shape #403 rejects, kept as a control so the report can say what it
// costs rather than assert it. If the width is the *value* type - an
// extension type over `int` - then every literal at every call site has to be
// wrapped, at the declaration and at the override alike.
//
// Expected: two argument_type_not_assignable, which is exactly the cost

extension type const Uint8Value(int value) implements int {}

final class WidthAsValue<T> {
  WidthAsValue(this.initialValue);

  T initialValue;

  static WidthAsValue<T> initial<T>(T initialValue) =>
      WidthAsValue<T>(initialValue);
}

class WrapBase {
  final speed = WidthAsValue<Uint8Value>(const Uint8Value(10));
}

class WrapSub extends WrapBase {
  // ignore: overridden_fields
  @override
  final speed = .initial(20);
}

void plainIntIsRejected() {
  WidthAsValue<Uint8Value>(10);
}
