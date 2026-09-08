/// F: the shape the engine would actually have to take, and whether the
/// nullable axis needs classes of its own.
///
/// `data_layout.dart` already has a private class per byte-aligned width
/// (`_Uint8Field`, `_Int16Field`, `_Float64Field` and the rest), so the
/// public width type would be an abstract class those implement rather than
/// a new concrete one. The sub-byte widths share `_SubByteUintField`
/// parameterised by bit count and every nullable column shares
/// `_DefaultableOptionalField<T>`, so those are the two places where a public
/// type per width does not already have an implementation behind it.
library;

// The public face. Abstract, because the implementation is private and
// registers a column through the descriptor.
abstract class PublicInitialPointer<T> {
  T initialValue = null as T;
}

abstract class PublicUint8Field extends PublicInitialPointer<int> {
  static PublicUint8Field initial(int initialValue) =>
      _PrivateUint8Field(initialValue);
}

abstract class PublicUint16Field extends PublicInitialPointer<int> {
  static PublicUint16Field initial(int initialValue) =>
      _PrivateUint16Field(initialValue);
}

// The sub-byte widths, which share one implementation parameterised by bit
// count. Two public types, one private class - the public type is not the
// implementation, so this costs nothing structurally.
abstract class PublicUint2Field extends PublicInitialPointer<int> {
  static PublicUint2Field initial(int initialValue) =>
      _PrivateSubByteField2(initialValue);
}

abstract class PublicUint4Field extends PublicInitialPointer<int> {
  static PublicUint4Field initial(int initialValue) =>
      _PrivateSubByteField4(initialValue);
}

class _PrivateUint8Field extends PublicUint8Field {
  _PrivateUint8Field(int initialValue) {
    this.initialValue = initialValue;
  }
}

class _PrivateUint16Field extends PublicUint16Field {
  _PrivateUint16Field(int initialValue) {
    this.initialValue = initialValue;
  }
}

class _PrivateSubByteField2 extends PublicUint2Field {
  _PrivateSubByteField2(int initialValue) {
    this.initialValue = initialValue;
  }

  final int bits = 2;
}

class _PrivateSubByteField4 extends PublicUint4Field {
  _PrivateSubByteField4(int initialValue) {
    this.initialValue = initialValue;
  }

  final int bits = 4;
}

/// The nullable axis as a type parameter rather than seventeen more classes.
/// `NullableUint8Field<int>` and `NullableUint8Field<int?>` are the two
/// columns `Field.uint8` and `Field.optUint8` build today.
abstract class NullableUint8Field<T extends int?>
    extends PublicInitialPointer<T> {
  static NullableUint8Field<T> initial<T extends int?>(T initialValue) =>
      _PrivateNullableUint8Field<T>(initialValue);
}

class _PrivateNullableUint8Field<T extends int?> extends NullableUint8Field<T> {
  _PrivateNullableUint8Field(T initialValue) {
    this.initialValue = initialValue;
  }
}

abstract final class PublicFields {
  static PublicUint8Field uint8([int initialValue = 0]) =>
      _PrivateUint8Field(initialValue);
  static PublicUint16Field uint16([int initialValue = 0]) =>
      _PrivateUint16Field(initialValue);
  static PublicUint2Field uint2([int initialValue = 0]) =>
      _PrivateSubByteField2(initialValue);
  static NullableUint8Field<int> nUint8([int initialValue = 0]) =>
      _PrivateNullableUint8Field<int>(initialValue);
  static NullableUint8Field<int?> optUint8([int? initialValue]) =>
      _PrivateNullableUint8Field<int?>(initialValue);
}

class FBase {
  final speed = PublicFields.uint8(10);
  final hp = PublicFields.uint16(10);
  final flags = PublicFields.uint2(1);
  final ammo = PublicFields.nUint8(7);
  final spare = PublicFields.optUint8(7);
}

class FSub extends FBase {
  @override
  final speed = .initial(20);

  @override
  final hp = .initial(20);

  @override
  final flags = .initial(3);

  @override
  final ammo = .initial(9);

  // The nullable half of the same width class, which is what says the
  // nullable axis can ride on a type parameter.
  @override
  final spare = .initial(null);
}

PublicUint8Field takesU8(PublicUint8Field field) => field;

PublicUint16Field takesU16(PublicUint16Field field) => field;

PublicUint2Field takesU2(PublicUint2Field field) => field;

NullableUint8Field<int> takesNonNull(NullableUint8Field<int> field) => field;

NullableUint8Field<int?> takesNullable(NullableUint8Field<int?> field) => field;

void checkStaticTypes() {
  takesU8(FSub().speed);
  takesU16(FSub().hp);
  takesU2(FSub().flags);
  takesNonNull(FSub().ammo);
  takesNullable(FSub().spare);
}
