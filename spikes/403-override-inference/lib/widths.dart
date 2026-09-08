/// A stand-in for `good`'s field vocabulary, cut down to what #403 turns on.
///
/// The only difference from `packages/good/lib/src/data.dart` is the one
/// #403 proposes: each width is its own concrete class, so `Field.uint8` and
/// `Field.uint16` have different static types instead of both being
/// `InitialPointer<int>`.
library;

abstract class DataPointer<T> {
  const DataPointer();

  T operator [](int instance);
}

abstract class InitialPointer<T> extends DataPointer<T> {
  InitialPointer(this.initialValue);

  T initialValue;

  /// The `super.speed.initial(20)` form #198 recorded: mutate in place and
  /// hand back the same object, so it is one column and not two. Named
  /// `withInitial` and not `initial` because the two cannot coexist - see
  /// `neg/e1_static_instance_collision.dart`.
  InitialPointer<T> withInitial(T newValue) {
    initialValue = newValue;
    return this;
  }

  @override
  T operator [](int instance) => initialValue;
}

final class Uint8Field extends InitialPointer<int> {
  Uint8Field(super.initialValue);

  static Uint8Field initial(int initialValue) => Uint8Field(initialValue);

  /// Narrowed to the concrete class. Inherited, `withInitial` returns
  /// `InitialPointer<int>`, which is not assignable to the `Uint8Field` an
  /// overriding field must have.
  @override
  Uint8Field withInitial(int newValue) {
    initialValue = newValue;
    return this;
  }

  int get bitWidth => 8;
}

final class Uint16Field extends InitialPointer<int> {
  Uint16Field(super.initialValue);

  static Uint16Field initial(int initialValue) => Uint16Field(initialValue);

  int get bitWidth => 16;
}

final class Float64Field extends InitialPointer<double> {
  Float64Field(super.initialValue);

  static Float64Field initial(double initialValue) =>
      Float64Field(initialValue);
}

final class BoolField extends InitialPointer<bool> {
  BoolField(super.initialValue);

  static BoolField initial(bool initialValue) => BoolField(initialValue);
}

final class OptUint8Field extends InitialPointer<int?> {
  OptUint8Field(super.initialValue);

  static OptUint8Field initial(int? initialValue) =>
      OptUint8Field(initialValue);
}

extension type const Entity(int index) {}

final class EntityField extends InitialPointer<Entity> {
  EntityField(super.initialValue);

  static EntityField initial(Entity initialValue) => EntityField(initialValue);
}

/// The one width that cannot be a plain class, because the value type is a
/// type parameter rather than a fixed type.
final class EnumField<E extends Enum> extends InitialPointer<E> {
  EnumField(this.values, super.initialValue);

  final List<E> values;

  static EnumField<E> initial<E extends Enum>(E initialValue) =>
      EnumField<E>(const [], initialValue);
}

abstract final class Field {
  static Uint8Field uint8([int initialValue = 0]) => Uint8Field(initialValue);
  static Uint16Field uint16([int initialValue = 0]) =>
      Uint16Field(initialValue);
  static Float64Field float64([double initialValue = 0.0]) =>
      Float64Field(initialValue);
  static BoolField boolean([bool initialValue = false]) =>
      BoolField(initialValue);
  static OptUint8Field optUint8([int? initialValue]) =>
      OptUint8Field(initialValue);
  static EntityField entity([Entity initialValue = const Entity(0)]) =>
      EntityField(initialValue);
  static EnumField<E> enumOf<E extends Enum>(List<E> values, E initialValue) =>
      EnumField<E>(values, initialValue);
}

/// Where a probe has to name a type to prove which one it got. Passing a
/// `Uint8Field` to [takesUint16] must be a compile error, and that is what
/// discriminates "the override inferred the width" from "the override
/// inferred something that merely analyses clean".
Uint8Field takesUint8(Uint8Field field) => field;

Uint16Field takesUint16(Uint16Field field) => field;

InitialPointer<int> takesInitialInt(InitialPointer<int> field) => field;
