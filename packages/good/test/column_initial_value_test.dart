import 'package:flutter_test/flutter_test.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';

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

class _Squad extends SceneStruct {
  late final Scene handle;

  late final _Grunt grunt;
  late final _Captain captain;
  late final _Lieutenant lieutenant;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    grunt = descriptor.has(_Grunt.new);
    captain = descriptor.has(_Captain.new);
    lieutenant = descriptor.has(_Lieutenant.new);
  }
}

_Squad _squad() {
  final squad = _Squad()..initializeScene(MemoryPool(pageSize: 4096));
  squad.handle = SceneRegistry.register(squad);
  addTearDown(squad.pool.dispose);
  return squad;
}

void main() {
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
