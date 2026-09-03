import 'package:flutter_test/flutter_test.dart';
import 'package:good/src/data.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';
import 'package:good/src/struct.dart';

part 'generic_declaration_test.g.dart';

/// What a collector is keyed by is a `Type`, and a `Type` for a generic class
/// is not the one an instance of it hands back. The literal `_Spawner` is
/// `_Spawner<EntityStruct>` - Dart instantiates to bounds - and
/// `_Spawner<_Enemy>().runtimeType` is `_Spawner<_Enemy>`. Nothing at run
/// time can take the arguments off either, so the two never met and every
/// generic scanned class threw on the way to its own collector.
///
/// `good_tool --check` cannot see it. The generator writes the entry it means
/// to write, and the file it would write is the file on disk; what is wrong
/// is that no lookup can present the key. So this asks the question the tool
/// cannot: it registers instances and checks what comes back.
class _Enemy extends EntityStruct {
  final hp = Field.int32(3);
}

class _Pickup extends EntityStruct {
  final value = Field.int32(1);
}

class _Spawner<T extends EntityStruct> extends EntityStruct {
  final rate = Field.float64(2);
  final budget = Field.int32(10);
}

/// Two generic classes, one above the other. Both answer `is` for a
/// `_Derived`, so both collectors claim it and they read different lists -
/// which the registry refuses rather than picking from. Here so the refusal
/// is a fact that runs, not a paragraph.
class _Base<T extends EntityStruct> extends EntityStruct {
  final base = Field.int32();
}

class _Derived<T extends EntityStruct> extends _Base<T> {
  final derived = Field.int32();
}

void main() {
  setUp(() {
    // Each test gets the table fresh: one of them installs a hand-built one
    // in its place, and a second install of the generated table over the top
    // of that is what `installGenerated` throws about.
    DeclarationRegistry.reset();
    _installDeclarations();
  });

  test('a generic class is not the Type its own literal is', () {
    final spawner = _Spawner<_Enemy>();

    // The miss, written down. Both lines have to hold for the rest of this
    // file to be testing anything: if `runtimeType` did equal the literal
    // there would have been no defect, and if the `is` were false the type
    // test the generator writes could not stand in for it.
    expect(spawner.runtimeType, isNot(_Spawner));
    expect(spawner, isA<_Spawner<dynamic>>());
  });

  test('every instantiation of a generic class reaches its one collector', () {
    final enemies = _Spawner<_Enemy>();
    final pickups = _Spawner<_Pickup>();

    // The same class at two type arguments, and one entry serving both. A
    // collector reads field *names*, and a field list does not vary by type
    // argument - which is why one entry is right and why the generator, which
    // cannot see across libraries to enumerate instantiations, has enough.
    expect(
      collectDeclarations(enemies),
      containsAll(<Object>[enemies.rate, enemies.budget]),
    );
    expect(
      collectDeclarations(pickups),
      containsAll(<Object>[pickups.rate, pickups.budget]),
    );
    expect(
      collectDeclarations(pickups).length,
      collectDeclarations(enemies).length,
    );
  });

  test('a class with no type parameters is still matched exactly', () {
    final enemy = _Enemy();
    expect(enemy.runtimeType, _Enemy);
    expect(collectDeclarations(enemy), contains(enemy.hp));
  });

  test('a class no table holds still throws, generic entries and all', () {
    // The guarantee the type test had to be added without weakening: a miss
    // means "never scanned", and it has to keep meaning that with a walk over
    // generic entries sitting behind the exact lookup. `_Enemy` is left out
    // of this table on purpose.
    DeclarationRegistry.reset();
    DeclarationRegistry.installGenerated(const <GeneratedDeclarations>[
      GeneratedDeclarations(
        package: 'good/test/generic_declaration_test.dart hand-built',
        collectors: <DeclarationCollector>[
          DeclarationCollector.generic(_Spawner, _collect$Spawner, _is$Spawner),
        ],
      ),
    ]);

    expect(collectDeclarations(_Spawner<_Enemy>()), isNotEmpty);
    expect(
      () => collectDeclarations(_Enemy()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('No generated collector for _Enemy'),
        ),
      ),
    );
  });

  test('two generic collectors that both match refuse rather than pick', () {
    expect(
      () => collectDeclarations(_Derived<_Enemy>()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('_Base'), contains('_Derived')),
        ),
      ),
    );

    // The one above it still answers - the refusal is about the pair, not
    // about either class being unreachable.
    final base = _Base<_Enemy>();
    expect(collectDeclarations(base), contains(base.base));
  });
}
