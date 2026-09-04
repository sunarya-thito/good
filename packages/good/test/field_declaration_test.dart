import 'package:flutter_test/flutter_test.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'field_declaration_test.g.dart';

/// Declares its columns from the field declarations, with no `describeStruct`
/// at all.
class _Declared extends EntityStruct {
  final speed = Field.float64(3.0);
  final hp = Field.int32(100);
  final alive = Field.boolean(true);
}

/// A column declared from the hook rather than from a field.
///
/// It reserves a byte and hands the pointer back to nobody: the collect pass
/// reads a struct's fields before `describeStruct` runs, so a field this hook
/// assigned would be unassigned when the collector reached it. What the hook
/// still does is take space, which is what [_Mixed] is about.
mixin _Legacy on Component {
  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    data.hasUint8(7);
  }
}

/// Both forms on one struct. The field initialisers run during construction,
/// the mixin's `describeStruct` runs in the pass after it, so `own` is at a
/// lower offset than the byte the hook reserves, however the mixin list is
/// written.
class _Mixed extends EntityStruct with _Legacy {
  final own = Field.uint8(9);
}

/// [_Mixed] without the mixin, so the byte the hook reserves is the whole of
/// the difference between the two rows.
class _OwnOnly extends EntityStruct {
  final own = Field.uint8(9);
}

/// Same fields as [_Declared], declared identically. Two archetypes, and the
/// offsets have to agree - that is what makes a layout reproducible on the
/// second isolate.
class _Twin extends EntityStruct {
  final speed = Field.float64(3.0);
  final hp = Field.int32(100);
  final alive = Field.boolean(true);
}

class _Throws extends EntityStruct {
  final declaredBeforeTheThrow = Field.int32(1);

  _Throws() {
    throw StateError('constructor failed after declaring a column');
  }
}

class _After extends EntityStruct {
  final mark = Field.int32(5);
}

/// Registers a prefab whose constructor throws, swallows it, and registers a
/// second one - so the second's columns land in its own archetype only if the
/// declaration stack unwound.
class _Broken extends SceneStruct {
  Object? thrown;
  @sub
  final after = _After();

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    try {
      descriptor.has(_Throws.new);
    } catch (e) {
      thrown = e;
    }
  }
}

class _Level extends SceneStruct {
  late final Scene handle;

  @sub
  final declared = _Declared();
  @sub
  final mixed = _Mixed();
  @sub
  final ownOnly = _OwnOnly();
  @sub
  final twin = _Twin();
}

_Level _level() {
  final level = _Level()..initializeScene(MemoryPool(pageSize: 4096));
  level.handle = SceneRegistry.register(level);
  addTearDown(level.pool.dispose);
  return level;
}

void main() {
  _installDeclarations();

  setUp(() {
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('a field declared on the class is a real column with its default', () {
    final level = _level();
    final e = level.handle.addEntity(level.declared);
    expect(level.declared.speed[e], 3.0);
    expect(level.declared.hp[e], 100);
    expect(level.declared.alive[e], isTrue);

    level.declared.speed[e] = 12.5;
    level.declared.hp[e] = -4;
    level.declared.alive[e] = false;
    expect(level.declared.speed[e], 12.5);
    expect(level.declared.hp[e], -4);
    expect(level.declared.alive[e], isFalse);
  });

  test('the describeStruct pass reserves behind the fields', () {
    final level = _level();
    final e = level.handle.addEntity(level.mixed);
    expect(level.mixed.own[e], 9);

    // The mixin's hook declares a second byte, and `own` still addresses the
    // first: a hook that had reserved *ahead* of the field initialisers would
    // leave `own` reading the byte the hook seeded.
    expect(
      level.mixed.archetype.bitLength,
      level.ownOnly.archetype.bitLength + 8,
      reason: 'the hook took a byte of its own rather than aliasing `own`',
    );
    level.mixed.own[e] = 1;
    expect(level.mixed.own[e], 1);
  });

  test('two structs declaring the same fields get the same layout', () {
    final level = _level();
    // Eager initialisers, so the offsets come from declaration order and not
    // from whatever order something happened to read the fields in. Reading
    // the twin's columns in reverse first is exactly what a `late` initialiser
    // would have laid out differently.
    final b = level.handle.addEntity(level.twin);
    expect(level.twin.alive[b], isTrue);
    expect(level.twin.hp[b], 100);
    expect(level.twin.speed[b], 3.0);

    final a = level.handle.addEntity(level.declared);
    expect(level.declared.speed[a], 3.0);

    expect(level.twin.archetype.bitLength, level.declared.archetype.bitLength);
    expect(
      level.twin.archetype.archetypeId,
      isNot(level.declared.archetype.archetypeId),
    );
  });

  test('a constructor that throws does not leave the context open', () {
    // The stack has to unwind even when the object never finishes, or the
    // next declaration - here the scene's own second prefab - declares into
    // the abandoned archetype.
    final level = _Broken()..initializeScene(MemoryPool(pageSize: 4096));
    addTearDown(level.pool.dispose);
    expect(level.thrown, isA<StateError>());
    final handle = SceneRegistry.register(level);
    final e = handle.addEntity(level.after);
    expect(level.after.mark[e], 5);
  });
}
