import 'package:meta/meta.dart';

import 'package:good/src/data.dart';
import 'package:good/src/struct.dart';

/// What `EntityStruct.of` declares against: whoever is registering prefabs
/// right now.
///
/// Separate from [DataDescriptor] because it declares a different thing. A
/// field initialiser reaching for `Field.float64` wants a column on the
/// archetype being built; one reaching for `EntityStruct.of` wants a whole
/// archetype of its own, registered with the same scene, plus a column on the
/// archetype being built to hold its handle. One is the row; the other is the
/// scene's prefab list, the archetype registry and the row.
@internal
abstract interface class PrefabRegistrar {
  /// Registers [create]'s prefab as a child of the archetype currently being
  /// declared, and returns it. See `EntityStruct.of`, which is the only
  /// caller.
  T declareChild<T extends EntityStruct>(T Function() create);
}

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
  /// The open data contexts, innermost last. A `null` entry is a barrier -
  /// see [pushBarrier].
  static final List<DataDescriptor?> _data = <DataDescriptor?>[];

  /// Opens a context. Every push is paired with a [popData] in a `finally`,
  /// so a constructor that throws does not leave the stack dirty.
  static void pushData(DataDescriptor descriptor) => _data.add(descriptor);

  /// Closes the stack for the duration of a pass that is **not** a
  /// constructor, so a `Field.*` call inside one reports itself instead of
  /// silently declaring against whatever is underneath.
  ///
  /// Only nesting makes this necessary, and nesting is what
  /// `EntityStruct.of` introduced: a child prefab's `describeStruct` runs
  /// while its *parent's* constructor is still on the stack, so a body that
  /// wrote `Field.float64()` instead of `data.hasFloat64()` would add a
  /// column to the parent's row and read it back from the child's. Before
  /// there was anything to nest inside, the stack was simply empty there and
  /// the same call threw.
  ///
  /// Popped by [popData], which pops either kind.
  static void pushBarrier() => _data.add(null);

  static void popData() => _data.removeLast();

  /// The innermost open context, or a `StateError` naming the one thing that
  /// puts a caller here: constructing a struct by hand instead of letting the
  /// framework construct it.
  static DataDescriptor get data {
    final descriptor = _data.isEmpty ? null : _data.last;
    if (descriptor == null) {
      throw StateError(
        'A Field was declared with no struct being constructed. Field.* '
        'reads the descriptor the framework opens around a constructor call, '
        'so the struct has to be built by the framework:\n'
        '  descriptor.has(MyStruct.new)   // not descriptor.has(MyStruct())\n'
        'Constructing one directly - in a test fixture, or to read a field '
        'off it - runs the initialisers with nothing to declare against, '
        'which is what this is. A describeStruct body is the other way to '
        'get here: it runs after the constructor, so it declares through the '
        'DataDescriptor it is handed rather than through Field.*.',
      );
    }
    return descriptor;
  }

  /// The open prefab registrations, innermost last - the second level of the
  /// stack, and the one `EntityStruct.of` declares against.
  static final List<PrefabRegistrar> _prefabs = <PrefabRegistrar>[];

  static void pushPrefabs(PrefabRegistrar registrar) => _prefabs.add(registrar);

  static void popPrefabs() => _prefabs.removeLast();

  static PrefabRegistrar get prefabs {
    if (_prefabs.isEmpty) {
      throw StateError(
        'EntityStruct.of was called with no prefab being registered. It '
        'declares an entity into whichever scope is open, and the scope it '
        'reads is opened around a prefab constructor - so it belongs in the '
        'field initialisers of an EntityStruct that a scene registers:\n'
        '  class Turret extends EntityStruct with Parent {\n'
        '    final barrel = EntityStruct.of(Barrel.new);\n'
        '  }\n'
        'A SceneStruct cannot use it yet. A scene is constructed by the user '
        'and only gets its MemoryPool at initializeScene, so its own field '
        'initialisers run before there is anything to declare into; scenes '
        'declare with `descriptor.has(Mote.new)` in describeScene.',
      );
    }
    return _prefabs.last;
  }
}
