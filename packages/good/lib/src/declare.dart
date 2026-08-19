import 'package:meta/meta.dart';

import 'package:good/src/data.dart';

/// The descriptor a field initialiser declares against, for the duration of
/// one object's construction.
///
/// A field like `final speed = Field.float64(3.0);` has no descriptor in
/// scope - it is an initialiser, so it cannot see `this`, let alone an
/// argument some later method would have been handed. So the framework puts
/// the descriptor here first and constructs the object second:
/// `SceneDescriptor.has` takes `Mote.new` rather than `Mote()` for exactly
/// that reason.
///
/// # Why a stack
///
/// Declaration nests. A scene declares prefabs, and a prefab's own fields
/// declare columns, so a second context opens while the first is still
/// wanted. A single slot cleared on the way out loses the outer one, and
/// anything declared after the nested call fails - which is not hypothetical,
/// it is what a one-slot version does the moment a scene has a field after
/// its first prefab.
///
/// # Why the initialisers must be eager
///
/// `late final speed = Field.float64(3.0)` compiles and is wrong. A `late`
/// initialiser runs on the first *read*, so the offsets a struct's fields get
/// depend on the order something happened to touch them - two instances of one
/// prefab, read in different orders, lay out differently, and the render
/// isolate and the game isolate then disagree about where a column is. Field
/// initialisers here are eager, always.
@internal
abstract final class DeclarationContext {
  static final List<DataDescriptor> _data = <DataDescriptor>[];

  /// Opens a context. Every push is paired with a [popData] in a `finally`,
  /// so a constructor that throws does not leave the stack dirty.
  static void pushData(DataDescriptor descriptor) => _data.add(descriptor);

  static void popData() => _data.removeLast();

  /// The innermost open context, or a `StateError` naming the one thing that
  /// puts a caller here: constructing a struct by hand instead of letting the
  /// framework construct it.
  static DataDescriptor get data {
    if (_data.isEmpty) {
      throw StateError(
        'A Field was declared with no struct being constructed. Field.* '
        'reads the descriptor the framework opens around a constructor call, '
        'so the struct has to be built by the framework:\n'
        '  descriptor.has(MyStruct.new)   // not descriptor.has(MyStruct())\n'
        'Constructing one directly - in a test fixture, or to read a field '
        'off it - runs the initialisers with nothing to declare against, '
        'which is what this is.',
      );
    }
    return _data.last;
  }
}
