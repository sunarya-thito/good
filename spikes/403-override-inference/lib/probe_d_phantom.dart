/// D: the cheaper alternative to a class per width - one generic class with
/// the width as a phantom second type parameter, which is the shape the #403
/// draft sketches as `Field<int, uint8>`.
///
/// Probed because the class count is #403's only real cost, and this shape
/// would replace it with marker types that need no members. The question is
/// whether the dot shorthand still resolves, since it now has to infer the
/// static's type arguments from the context type rather than take a concrete
/// class whole.
library;

/// Markers. They appear only as a type argument, so they need no members and
/// are never instantiated.
final class W8 {}

final class W16 {}

final class W32 {}

class PhantomField<T, W> {
  PhantomField(this.initialValue);

  T initialValue;

  static PhantomField<T, W> initial<T, W>(T initialValue) =>
      PhantomField<T, W>(initialValue);
}

abstract final class PhantomFields {
  static PhantomField<int, W8> uint8([int initialValue = 0]) =>
      PhantomField<int, W8>(initialValue);
  static PhantomField<int, W16> uint16([int initialValue = 0]) =>
      PhantomField<int, W16>(initialValue);
}

class DBase {
  final speed = PhantomFields.uint8(10);
  final hp = PhantomFields.uint16(10);
}

class DSub extends DBase {
  @override
  final speed = .initial(20);

  @override
  final hp = .initial(20);
}

PhantomField<int, W8> takesW8(PhantomField<int, W8> field) => field;

PhantomField<int, W16> takesW16(PhantomField<int, W16> field) => field;

void checkStaticTypes() {
  takesW8(DSub().speed);
  takesW16(DSub().hp);
  final int value = DSub().speed.initialValue;
  print(value);
}
