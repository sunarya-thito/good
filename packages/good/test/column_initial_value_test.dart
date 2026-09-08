// Every override in _Sergeant and _Scout below is a field overriding a field,
// which is what `overridden_fields` reports. The lint's own advice - override
// the getter instead - is what _Runner does, and the test on _Runner is what
// says that spelling does not work. A game writes `// ignore:
// overridden_fields` on each declaration; the file-level form keeps eight of
// them out of the fixtures here.
// ignore_for_file: overridden_fields

import 'package:flutter_test/flutter_test.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'column_initial_value_test.g.dart';

enum _Stance { idle, walking, running }

/// The component every prefab below shares. Its defaults are written once,
/// here, and are what a prefab that says nothing gets.
mixin _Body on Component {
  final speed = Field.float64(3);
  final hp = Field.int32(100);
  final alive = Field.boolean(true);
  final stance = Field.enumOf(_Stance.values, _Stance.idle);
  final leader = Field.entity(Entity(1));
  final shield = Field.optInt32();
  final aim = Field.optFloat64(0.5);
}

/// Takes the component as it comes.
class _Grunt extends EntityStruct with _Body {}

/// Moves the defaults it cares about, and nothing else.
class _Captain extends EntityStruct with _Body {
  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    speed.initialValue = 9.5;
    hp.initialValue = 250;
    alive.initialValue = false;
    stance.initialValue = _Stance.running;
    leader.initialValue = Entity(77);
    shield.initialValue = 30;
    aim.initialValue = null;
  }
}

/// Adjusts the inherited defaults instead of restating them, which is what
/// the getter is for: none of these lines names a number [_Body] chose.
class _Lieutenant extends EntityStruct with _Body {
  /// What each column read back as while it was being described, so a test
  /// can pin that the getter answers the *declared* default and not a zero.
  late final double sawSpeed;
  late final int sawHp;
  late final int? sawShield;
  late final double? sawAim;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    sawSpeed = speed.initialValue;
    sawHp = hp.initialValue;
    sawShield = shield.initialValue;
    sawAim = aim.initialValue;

    speed.initialValue *= 2;
    hp.initialValue += 50;
    alive.initialValue = !alive.initialValue;
    stance.initialValue = _Stance.values[stance.initialValue.index + 1];
    leader.initialValue = Entity(leader.initialValue.value + 1);
    aim.initialValue = aim.initialValue! + 0.25;
  }
}

/// Changes inherited initial values from its own fields, with no
/// `describeStruct` override anywhere in it.
///
/// Every column here is declared by [_Body], which [_Grunt] applies - so
/// `super` reaches through a superclass *and* a mixin application to the same
/// object, and hands that object back for the collector to lay out.
class _Sergeant extends _Grunt {
  @override
  late final speed = super.speed.initial(12);
  @override
  late final alive = super.alive.initial(false);
  @override
  late final stance = super.stance.initial(_Stance.running);
  @override
  late final leader = super.leader.initial(Entity(77));
  @override
  late final shield = super.shield.initial(30);
  @override
  late final aim = super.aim.initial(null);

  /// Adjusted, not restated: no line here names the number [_Body] chose.
  @override
  late final hp = super.hp.initial(super.hp.initialValue + 50);
}

/// The same override written by the class that applies the mixin itself,
/// where `super` is the mixin application rather than another prefab.
class _Scout extends EntityStruct with _Body {
  @override
  late final speed = super.speed.initial(20);
}

/// The same move written as a getter, which is the spelling `overridden_fields`
/// asks for and the one that does not work.
///
/// A getter body runs on every read, not once. The collector's read makes the
/// declaration correctly, and every read after `seal` runs `initial` again
/// against a sealed archetype.
class _Runner extends _Grunt {
  @override
  InitialPointer<double> get speed => super.speed.initial(15);
}

/// Restates the declaration rather than moving the inherited one.
///
/// The column [_Body] built is still there and is still what `super.speed`
/// names, but nothing reaches it: the collector reads `owner.speed` and gets
/// this one, twice - once for this class's field and once for [_Body]'s - so
/// the row holds one `speed`, and it is this one.
class _Cadet extends _Grunt {
  @override
  late final speed = Field.float64(99);
}

class _Squad extends SceneStruct {
  late final Scene handle;

  @prefab
  final grunt = _Grunt();
  @prefab
  final captain = _Captain();
  @prefab
  final lieutenant = _Lieutenant();
  @prefab
  final sergeant = _Sergeant();
  @prefab
  final scout = _Scout();
  @prefab
  final runner = _Runner();
  @prefab
  final cadet = _Cadet();
}

_Squad _squad() {
  final squad = _Squad()..initializeScene(MemoryPool(pageSize: 4096));
  squad.handle = SceneRegistry.register(squad);
  addTearDown(squad.pool.dispose);
  return squad;
}

void main() {
  _installDeclarations();

  setUp(() {
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  tearDown(SceneRegistry.reset);

  test('a default moved in describeStruct is what a fresh row holds', () {
    final squad = _squad();
    final e = squad.handle.addEntity(squad.captain);

    expect(squad.captain.speed[e], 9.5);
    expect(squad.captain.hp[e], 250);
    expect(squad.captain.alive[e], isFalse);
    expect(squad.captain.stance[e], _Stance.running);
    expect(squad.captain.leader[e], Entity(77));
    expect(squad.captain.shield[e], 30);
    expect(squad.captain.aim[e], isNull);
  });

  test('a second prefab mixing the same component keeps the component\'s '
      'own defaults', () {
    final squad = _squad();
    final captain = squad.handle.addEntity(squad.captain);
    final grunt = squad.handle.addEntity(squad.grunt);

    expect(squad.grunt.speed[grunt], 3);
    expect(squad.grunt.hp[grunt], 100);
    expect(squad.grunt.alive[grunt], isTrue);
    expect(squad.grunt.stance[grunt], _Stance.idle);
    expect(squad.grunt.leader[grunt], Entity(1));
    expect(squad.grunt.shield[grunt], isNull);
    expect(squad.grunt.aim[grunt], 0.5);

    // And the one that did move them still has, so this is two archetypes
    // and not one shared column.
    expect(squad.captain.speed[captain], 9.5);
  });

  test('every row of the prefab starts there, not just the first', () {
    final squad = _squad();
    final a = squad.handle.addEntity(squad.captain);
    final b = squad.handle.addEntity(squad.captain);

    squad.captain.hp[a] = 1;

    expect(squad.captain.hp[a], 1);
    expect(
      squad.captain.hp[b],
      250,
      reason:
          'per row, stamped from the '
          'prototype',
    );
  });

  test('a moved default is still only a default', () {
    final squad = _squad();
    final e = squad.handle.addEntity(squad.captain);

    squad.captain.speed[e] = -1;
    expect(squad.captain.speed[e], -1);
  });

  test('setting a default after the archetype is sealed says which of the '
      'two spellings was meant', () {
    final squad = _squad();

    expect(
      () => squad.captain.hp.initialValue = 5,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('sealed'),
            contains('_Captain'),
            contains('initialValue'),
            contains('near[entity]'),
          ),
        ),
      ),
    );
  });

  test('the throw catches every column kind, wrappers included', () {
    final squad = _squad();

    expect(() => squad.grunt.speed.initialValue = 1, throwsStateError);
    expect(() => squad.grunt.alive.initialValue = false, throwsStateError);
    expect(
      () => squad.grunt.stance.initialValue = _Stance.walking,
      throwsStateError,
    );
    expect(() => squad.grunt.leader.initialValue = Entity(2), throwsStateError);
    expect(() => squad.grunt.shield.initialValue = 1, throwsStateError);
    expect(() => squad.grunt.aim.initialValue = null, throwsStateError);
  });

  test('the getter answers the declared default while describing, before '
      'anything has moved it', () {
    final squad = _squad();

    expect(squad.lieutenant.sawSpeed, 3);
    expect(squad.lieutenant.sawHp, 100);
    expect(squad.lieutenant.sawShield, isNull);
    expect(squad.lieutenant.sawAim, 0.5);
  });

  test('a prefab can adjust an inherited default instead of restating it', () {
    final squad = _squad();
    final e = squad.handle.addEntity(squad.lieutenant);

    expect(squad.lieutenant.speed[e], 6);
    expect(squad.lieutenant.hp[e], 150);
    expect(squad.lieutenant.alive[e], isFalse);
    expect(squad.lieutenant.stance[e], _Stance.walking);
    expect(squad.lieutenant.leader[e], Entity(2));
    expect(squad.lieutenant.aim[e], 0.75);
  });

  test('a column reached twice takes its row space once', () {
    final squad = _squad();
    final e = squad.handle.addEntity(squad.cadet);

    // Every declaration a collector lists for _Cadet is `owner.speed` or one
    // of _Body's other fields, and `owner.speed` is listed twice - its own
    // and _Body's - reading the same object both times. Reserving that twice
    // throws out of _Field._storage.
    expect(squad.cadet.speed[e], 99);
    expect(squad.cadet.hp[e], 100);
    expect(squad.cadet.aim[e], 0.5);

    squad.cadet.speed[e] = 1;
    squad.cadet.hp[e] = 2;
    expect(squad.cadet.speed[e], 1);
    expect(squad.cadet.hp[e], 2);
  });

  test('a subclass changes an inherited initial value from its own field, '
      'and the spawned row holds it', () {
    final squad = _squad();
    final e = squad.handle.addEntity(squad.sergeant);

    expect(squad.sergeant.speed[e], 12);
    expect(squad.sergeant.alive[e], isFalse);
    expect(squad.sergeant.stance[e], _Stance.running);
    expect(squad.sergeant.leader[e], Entity(77));
    expect(squad.sergeant.shield[e], 30);
    expect(squad.sergeant.aim[e], isNull);
  });

  test('the override adjusts the inherited value instead of restating it', () {
    final squad = _squad();
    final e = squad.handle.addEntity(squad.sergeant);

    expect(squad.sergeant.hp[e], 150);
  });

  test('the mixin\'s own prefab can override it too, where super is the '
      'mixin application', () {
    final squad = _squad();
    final e = squad.handle.addEntity(squad.scout);

    expect(squad.scout.speed[e], 20);
    expect(squad.scout.hp[e], 100, reason: 'the rest of _Body is untouched');
  });

  test('the override moves the inherited column rather than adding one, so '
      'every other column still reads', () {
    final squad = _squad();
    final e = squad.handle.addEntity(squad.sergeant);

    // A version handing back a copy would leave _Body's column unrealized and
    // the row a column short. Writing and reading each one is what says the
    // row is laid out, not the pointer.
    squad.sergeant.speed[e] = -1;
    squad.sergeant.hp[e] = 7;
    squad.sergeant.stance[e] = _Stance.walking;
    squad.sergeant.aim[e] = 0.25;

    expect(squad.sergeant.speed[e], -1);
    expect(squad.sergeant.hp[e], 7);
    expect(squad.sergeant.stance[e], _Stance.walking);
    expect(squad.sergeant.aim[e], 0.25);
  });

  test('a prefab that overrides nothing keeps the component\'s values, so '
      'this is per archetype', () {
    final squad = _squad();
    final sergeant = squad.handle.addEntity(squad.sergeant);
    final grunt = squad.handle.addEntity(squad.grunt);
    final scout = squad.handle.addEntity(squad.scout);

    expect(squad.grunt.speed[grunt], 3);
    expect(squad.grunt.hp[grunt], 100);
    expect(squad.sergeant.speed[sergeant], 12);
    expect(squad.scout.speed[scout], 20);
  });

  test('the moved value reads back off the pointer after seal too', () {
    final squad = _squad();

    // A guard, not a discriminator, and it is worth saying which: reading the
    // pointer cannot tell a mutated column from a returned copy, because what
    // the collector reads and lays out is whatever the overriding field
    // holds - the copy, if it were one. The spawned rows above are the
    // assertions that answer for the prototype row.
    expect(squad.sergeant.speed.initialValue, 12);
    expect(squad.sergeant.hp.initialValue, 150);
  });

  test(
    'initial is the setter, so it refuses after the archetype is sealed',
    () {
      final squad = _squad();

      expect(() => squad.sergeant.speed.initial(1), throwsStateError);
      expect(() => squad.sergeant.aim.initial(1), throwsStateError);
    },
  );

  test('written as a getter it is unreadable once the archetype is sealed, '
      'which is why the override is a late field', () {
    // Registering it works: the collector\'s read runs the body once, while
    // the archetype is still open, and the column is declared and realized.
    final squad = _squad();
    final e = squad.handle.addEntity(squad.runner);

    // Every read after that runs the body again, now against a sealed
    // archetype - so the column is unreachable through the name that
    // declared it. A late field runs once and holds what it made.
    expect(
      () => squad.runner.speed[e],
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('sealed'), contains('_Runner')),
        ),
      ),
    );
    expect(() => squad.runner.speed.initialValue, throwsStateError);
  });

  test('reading a default after seal is allowed - it is still true', () {
    final squad = _squad();

    // Only the write becomes a lie at seal; the stored value is exactly what
    // every row allocated from here on gets.
    expect(squad.captain.hp.initialValue, 250);
    expect(squad.grunt.hp.initialValue, 100);
    expect(squad.captain.alive.initialValue, isFalse);
    expect(squad.captain.stance.initialValue, _Stance.running);
    expect(squad.captain.leader.initialValue, Entity(77));
    expect(squad.captain.shield.initialValue, 30);
    expect(squad.captain.aim.initialValue, isNull);
    expect(squad.grunt.aim.initialValue, 0.5);

    final e = squad.handle.addEntity(squad.captain);
    expect(squad.captain.hp[e], squad.captain.hp.initialValue);
  });

  test('a rejected set leaves the sealed default alone', () {
    final squad = _squad();

    try {
      squad.captain.hp.initialValue = 5;
    } on StateError {
      // expected
    }
    final e = squad.handle.addEntity(squad.captain);
    expect(squad.captain.hp[e], 250);
  });
}
