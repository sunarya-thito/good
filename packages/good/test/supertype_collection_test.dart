import 'package:flutter_test/flutter_test.dart';
import 'package:good/src/data.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';
import 'package:good/src/struct.dart';

part 'supertype_collection_test.g.dart';

/// A component that declares no column at all.
///
/// The case the field list cannot carry. Nothing an instance of `_Player`
/// holds is attributable to this mixin, so `collectDeclarations` reads the
/// same three columns whether it is applied or not - and "which components
/// does this prefab apply" had no answer until the type list was emitted
/// beside them.
mixin _Tagged on Component {}

mixin _Positioned on Component {
  final x = Field.float64();
}

mixin _Damaged on Component {
  final hp = Field.int32(3);
}

class _Player extends EntityStruct with _Positioned, _Damaged, _Tagged {
  final name = Field.int32();
}

/// A prefab that applies no component of its own, so the only name in its
/// list that is not part of `EntityStruct` is its own.
class _Bare extends EntityStruct {}

/// The case a table keyed by `Type` misses outright: the literal `_Spawner`
/// is `_Spawner<EntityStruct>` and every instance's `runtimeType` is
/// `_Spawner<something>`, and nothing at run time takes the arguments off
/// either. See `DeclarationCollector.generic`.
class _Spawner<T extends EntityStruct> extends EntityStruct with _Tagged {
  final rate = Field.float64(2);
}

void main() {
  setUp(() {
    // Each test gets the table fresh: the last one installs a hand-built one
    // in its place.
    DeclarationRegistry.reset();
    _installDeclarations();
  });

  test('a prefab reports its own class and every component it applies', () {
    final player = _Player();

    // The prefab class itself, because a prefab registers itself as a
    // component - `EntityStruct.describeType` is
    // `component.has(type: runtimeType)` - so a query matches on it the same
    // way it matches on a mixin.
    expect(
      collectSupertypes(player),
      containsAll(<Type>[_Player, _Positioned, _Damaged, _Tagged]),
    );

    // What that list could not have been read off. `_Tagged` declares no
    // column, so these three are everything an instance holds and none of
    // them is attributable to it.
    expect(collectDeclarations(player), <Object>[
      player.name,
      player.hp,
      player.x,
    ]);
  });

  test('the two lists are in two orders, and both are the walk', () {
    final player = _Player();
    final types = collectSupertypes(player).toList();

    expect(types.first, _Player);

    // The `with` clause left to right, which is the order it is written in.
    expect(
      types.indexOf(_Positioned),
      lessThan(types.indexOf(_Damaged)),
      reason: 'the type list follows the with clause as written',
    );
    expect(types.indexOf(_Damaged), lessThan(types.indexOf(_Tagged)));

    // Depth first, not breadth first: what `extends` names is walked to the
    // top before the first name in the `with` clause is reached at all.
    expect(types.indexOf(MultiComponent), lessThan(types.indexOf(_Positioned)));

    // And the field list runs the other way over the same clause, because
    // Dart initialises a mixin application before the one written to its
    // left. Two orders off one walk, which is why neither is described as
    // "the" order anywhere.
    expect(collectDeclarations(player), <Object>[
      player.name,
      player.hp,
      player.x,
    ]);
  });

  test('a type reached twice keeps one place', () {
    // `Component` is above `EntityStruct` and above each of the three mixins
    // through their `on` clauses, so a walk that did not drop a repeat would
    // list it four times and OR its bit in four times.
    final types = collectSupertypes(_Player()).toList();
    expect(types.where((type) => type == Component), hasLength(1));
  });

  test('a prefab that applies nothing still reports itself', () {
    expect(collectSupertypes(_Bare()), contains(_Bare));
  });

  test('a generic prefab is reached through the instance, not its Type', () {
    final spawner = _Spawner<_Player>();

    // The miss a `Type` key takes. Both lines have to hold for the rest of
    // this test to be about anything.
    expect(spawner.runtimeType, isNot(_Spawner));
    expect(spawner, isA<_Spawner<dynamic>>());

    expect(collectSupertypes(spawner), containsAll(<Type>[_Spawner, _Tagged]));

    // One entry serves every instantiation, for the reason the field list
    // has one: what a class is does not vary by type argument, and the
    // generator cannot see across libraries to enumerate the arguments
    // anybody writes.
    expect(
      collectSupertypes(_Spawner<_Bare>()).toList(),
      collectSupertypes(_Spawner<_Player>()).toList(),
    );
  });

  test('a class no table holds throws rather than reporting no types', () {
    DeclarationRegistry.reset();
    DeclarationRegistry.installGenerated(const <GeneratedDeclarations>[
      GeneratedDeclarations(
        package: 'good/test/supertype_collection_test.dart hand-built',
        collectors: <DeclarationCollector>[
          DeclarationCollector(_Bare, _collect$Bare, _supertypes$Bare),
        ],
      ),
    ]);

    expect(collectSupertypes(_Bare()), contains(_Bare));

    // A block body and not `() => collectSupertypes(...)`. The return type is
    // an `Iterable`, so an expression body hands the matcher one and a lazy
    // implementation that only threw on the first `moveNext` would pass -
    // while every caller that asked and never iterated got silence.
    expect(
      () {
        collectSupertypes(_Player());
      },
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('No generated collector for _Player'),
            contains('which types it is'),
          ),
        ),
      ),
    );
  });
}
