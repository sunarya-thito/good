// #403's `.initial(20)` needs a *static* named `initial`; #198's fallback
// `super.speed.initial(20)` needs an *instance* method of the same name. Dart
// permits only one of them, so the two spellings cannot both exist.
//
// Expected: conflicting_static_and_instance

abstract class Base<T> {
  Base(this.initialValue);

  T initialValue;

  Base<T> initial(T newValue) {
    initialValue = newValue;
    return this;
  }
}

final class Narrow extends Base<int> {
  Narrow(super.initialValue);

  static Narrow initial(int initialValue) => Narrow(initialValue);
}
