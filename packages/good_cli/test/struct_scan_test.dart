import 'dart:io';

import 'package:good_cli/src/generate/struct_scan.dart';
import 'package:test/test.dart';

// Two components on one struct declaring the same field name.
//
// To Dart this is an override and nothing is wrong. Both field initialisers
// run, so both columns are allocated and every row grows by both; the name
// reaches only the last one applied, and the other column is paid for in every
// row with no expression able to touch it. Measured on the engine at the time
// this was written: one mixin declaring `speed` gave a 64-bit row, two gave
// 128, and the read returned the later mixin's value with no error anywhere.
//
// The engine cannot report it. `Field.float64()` declares against the open
// descriptor and is never told which Dart field holds it, so two mixins each
// declaring `x` arrive as two anonymous registrations - indistinguishable from
// two columns that genuinely differ. The name is in the source and nowhere
// else, so these tests are about a source scan getting the *pairing* right:
// naming both sides, and staying quiet when it cannot see one of them.

/// A project directory with one or more library files.
Directory _project(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('good_shadow');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  File('${dir.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
  files.forEach((name, source) {
    File('${dir.path}/lib/$name')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(source);
  });
  return dir;
}

/// Writes a fake engine package and points [dir]'s package config at it, the
/// way a `pub get` would.
void _withEnginePackage(Directory dir, String source) {
  final engine = Directory('${dir.path}/engine/lib')
    ..createSync(recursive: true);
  File('${engine.path}/good.dart').writeAsStringSync(source);
  File('${dir.path}/.dart_tool/package_config.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    { "name": "good", "rootUri": "../engine", "packageUri": "lib/" }
  ]
}
''');
}

void main() {
  test('two mixins declaring one column name are reported with both files', () {
    final dir = _project(<String, String>{
      'velocity.dart': '''
mixin Velocity on Component {
  final speed = Field.float64();
}
''',
      'engine_bits.dart': '''
mixin Momentum on Component {
  final speed = Field.float64();
}
''',
      'player.dart': '''
class Player extends EntityStruct with Velocity, Momentum {}
''',
    });

    final scan = scanStructRules(dir);
    expect(scan.shadowed, hasLength(1));
    final hit = scan.shadowed.single;
    expect(hit.field, 'speed');
    expect(
      hit.winner,
      'Momentum',
      reason: 'the later mixin in the with clause is the one the name reaches',
    );
    expect(hit.loser, 'Velocity');
    expect(hit.winnerFile, endsWith('engine_bits.dart'));
    expect(hit.loserFile, endsWith('velocity.dart'));

    final message = shadowedFieldsMessage(scan);
    expect(message, contains('Momentum.speed shadows Velocity.speed'));
    expect(message, contains('velocity.dart'));
    expect(message, contains('engine_bits.dart'));
  });

  // #262 moved an array's element from the method name into an argument, and
  // the argument is written as a dot shorthand: `Field.array(.uint16, 4)`.
  // `_isColumn` recognises the first shape by the *receiver's* name, so what
  // matters here is that the shorthand sits in the argument list and leaves
  // `Field` where it was. The pair below is the discriminating one - the
  // second case is what the design would have looked like had the shorthand
  // reached the receiver too.
  test('an array declared with an element shorthand is still seen', () {
    final dir = _project(<String, String>{
      'grid.dart': '''
mixin Grid on Component {
  final cells = Field.array(.uint16, 16);
}
''',
      'tiles.dart': '''
mixin Tiles on Component {
  final cells = Field.array(.uint8, 4);
}
''',
      'board.dart': '''
class Board extends EntityStruct with Grid, Tiles {}
''',
    });

    final scan = scanStructRules(dir);
    expect(
      scan.shadowed,
      hasLength(1),
      reason: 'the dot shorthand is an argument; the receiver is still Field',
    );
    expect(scan.shadowed.single.field, 'cells');
    expect(scan.shadowed.single.winner, 'Tiles');
  });

  test('a declaration with no receiver at all falls through, and is why '
      'the element shorthand stayed in the argument list', () {
    final dir = _project(<String, String>{
      'grid.dart': '''
mixin Grid on Component {
  final cells = .array(.uint16, 16);
}
''',
      'tiles.dart': '''
mixin Tiles on Component {
  final cells = .array(.uint8, 4);
}
''',
      'board.dart': '''
class Board extends EntityStruct with Grid, Tiles {}
''',
    });

    expect(
      scanStructRules(dir).shadowed,
      isEmpty,
      reason: 'there is no receiver identifier to match, so the shadow check '
          'cannot see either declaration - a spelling this pass would have to '
          'learn before it could be used',
    );
  });

  test('the older bare-declaration form is seen when it names InitialPointer',
      () {
    // Both sides have to be `InitialPointer`. A collision is reported when
    // *either* declaration is a column (`_readStructs` ors the two), so a
    // `DataPointer` on the other side would carry this test on its own and
    // it would pass with `InitialPointer` missing from the set entirely.
    final dir = _project(<String, String>{
      'a.dart': '''
mixin Velocity on Component {
  late final InitialPointer<double> speed;
}
''',
      'b.dart': '''
mixin Momentum on Component {
  late final InitialPointer<double> speed;
}
''',
      'player.dart': '''
class Player extends EntityStruct with Velocity, Momentum {}
''',
    });

    final scan = scanStructRules(dir);
    expect(
      scan.shadowed,
      hasLength(1),
      reason: 'InitialPointer is what hasFloat64 returns, so a declaration '
          'written with it has to count as a column',
    );
    expect(scan.shadowed.single.field, 'speed');
  });

  test('distinct column names on the same struct are left alone', () {
    final dir = _project(<String, String>{
      'game.dart': '''
mixin Velocity on Component {
  final speed = Field.float64();
}
mixin Health on Component {
  final hitPoints = Field.float64();
}
class Player extends EntityStruct with Velocity, Health {}
''',
    });

    expect(scanStructRules(dir).shadowed, isEmpty);
  });

  test('a collision through the superclass chain is found', () {
    // `class Player extends Base with Health` applies Base first, so Base's own
    // mixins are part of the same applied order and can collide with Health.
    final dir = _project(<String, String>{
      'game.dart': '''
mixin Velocity on Component {
  final speed = Field.float64();
}
mixin Health on Component {
  final speed = Field.float64();
}
class Base extends EntityStruct with Velocity {}
class Player extends Base with Health {}
''',
    });

    final scan = scanStructRules(dir);
    expect(scan.shadowed.map((s) => '${s.winner}.${s.field}'), <String>[
      'Health.speed',
    ]);
    expect(scan.shadowed.single.loser, 'Velocity');
  });

  test('a mixin this pass cannot read is reported, not assumed clean', () {
    final dir = _project(<String, String>{
      'player.dart': '''
class Player extends EntityStruct with Transform2D, Velocity {}
mixin Velocity on Component {
  final speed = Field.float64();
}
''',
    });

    final scan = scanStructRules(dir);
    expect(scan.shadowed, isEmpty);
    expect(
      scan.unresolved.keys,
      contains('Player with Transform2D'),
      reason:
          'Transform2D is declared in no file this scan read, so its columns '
          'were never compared and the run has to say so',
    );
    expect(unreadPartsMessage(scan), contains('Player with Transform2D'));
  });

  test('a name declared in two files is reported instead of guessed', () {
    final dir = _project(<String, String>{
      'a.dart': '''
mixin Velocity on Component {
  final speed = Field.float64();
}
''',
      'b.dart': '''
mixin Velocity on Component {
  final other = Field.float64();
}
''',
      'player.dart': '''
mixin Health on Component {
  final speed = Field.float64();
}
class Player extends EntityStruct with Velocity, Health {}
''',
    });

    final scan = scanStructRules(dir);
    expect(
      scan.shadowed,
      isEmpty,
      reason:
          'one of the two Velocity declarations would collide with Health and '
          'the other would not. A parsed scan cannot tell which is applied, '
          'and a build error that fires wrongly is worse than the bug',
    );
    expect(scan.unresolved.keys, contains('Player with Velocity'));
    expect(scan.unresolved['Player with Velocity'], contains('2 declarations'));
  });

  test('an engine component collides with a user field of the same name', () {
    // The prefix rule (#133) makes this rare rather than impossible: the
    // engine now spells the column `childParent`, and a third-party
    // component author who picks the same name still shadows it. It only
    // surfaces because the scan reads the engine package the project
    // resolves.
    final dir = _project(<String, String>{
      'game.dart': '''
mixin Ownership on Component {
  final childParent = Field.optEntity();
}
class Crate extends EntityStruct with Child, Ownership {}
''',
    });
    _withEnginePackage(dir, '''
mixin Child on Component {
  final childParent = Field.optEntity();
  final childNextSibling = Field.optEntity();
}
''');

    final scan = scanStructRules(dir);
    expect(scan.shadowed, hasLength(1));
    expect(scan.shadowed.single.field, 'childParent');
    expect(scan.shadowed.single.loser, 'Child');
    expect(scan.shadowed.single.winner, 'Ownership');
    expect(
      scan.shadowed.single.loserFile,
      endsWith('good.dart'),
      reason: 'the engine side is named with its file, not just its type',
    );
  });

  test('without a package config the engine parts are reported unread', () {
    final dir = _project(<String, String>{
      'game.dart': '''
mixin Ownership on Component {
  final childParent = Field.optEntity();
}
class Crate extends EntityStruct with Child, Ownership {}
''',
    });

    final scan = scanStructRules(dir);
    expect(scan.shadowed, isEmpty);
    expect(scan.unresolved.keys, contains('Crate with Child'));
  });

  test('a project listed in its own package config is read once', () {
    // A package config lists the project's own package next to its
    // dependencies. The demo is called `goo2d_example`, which looks like an
    // engine package by name, so its `lib/` was being added a second time -
    // every declaration appeared twice, every mixin became two candidates, and
    // a real collision was reported as ambiguous instead of found.
    final dir = _project(<String, String>{
      'game.dart': '''
mixin Ownership on Component {
  final childParent = Field.optEntity();
}
class Crate extends EntityStruct with Child, Ownership {}
''',
    });
    final engine = Directory('${dir.path}/engine/lib')
      ..createSync(recursive: true);
    File('${engine.path}/good.dart').writeAsStringSync('''
mixin Child on Component {
  final childParent = Field.optEntity();
}
''');
    File('${dir.path}/.dart_tool/package_config.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    { "name": "goo2d_example", "rootUri": "../", "packageUri": "lib/" },
    { "name": "good", "rootUri": "../engine", "packageUri": "lib/" }
  ]
}
''');

    final scan = scanStructRules(dir);
    expect(scan.shadowed.map((s) => '${s.winner}.${s.field}'), <String>[
      'Ownership.childParent',
    ]);
    expect(scan.unresolved, isEmpty);
  });

  test('an explicit override is the author saying so, and passes', () {
    final dir = _project(<String, String>{
      'game.dart': '''
mixin Velocity on Component {
  final speed = Field.float64();
}
mixin Fast on Component {
  @override
  final speed = Field.float64();
}
class Player extends EntityStruct with Velocity, Fast {}
''',
    });

    expect(scanStructRules(dir).shadowed, isEmpty);
  });

  // --- #178: a private name belongs to its library, not to every file ------
  //
  // A `_`-prefixed name is library-private, so two libraries each declaring
  // `_dirty` declare two independent members: both columns are reachable, both
  // are wanted, and the row is legitimately the sum of them. Reported as a
  // collision, that stopped `good generate`, `good build` and `good create` on
  // correct code, and the message's advice - prefix it - cannot help a name
  // that has no cross-library collision to prefix away.
  //
  // The other half is what makes this narrow rather than a skip: a private
  // name *can* collide, when one library is split across files with `part`.
  // Dropping every `_` name would pass the first case here and lose that one.

  group('a private column name is private to its library', () {
    test('two libraries declaring one are independent', () {
      final dir = _project(<String, String>{
        'health.dart': '''
mixin Health on Component {
  final healthHp = Field.int32(100);
  final _dirty = Field.boolean();
}
''',
        'shield.dart': '''
mixin Shield on Component {
  final shieldCharge = Field.int32(50);
  final _dirty = Field.boolean();
}
''',
        'player.dart': '''
class Player extends EntityStruct with Health, Shield {}
''',
      });

      final scan = scanStructRules(dir);
      expect(
        scan.shadowed,
        isEmpty,
        reason:
            'neither _dirty is visible to the other library, so both columns '
            'are reachable and nothing is hidden',
      );
      expect(scan.unresolved, isEmpty);
    });

    test('two declarations in one library still collide', () {
      final dir = _project(<String, String>{
        'game.dart': '''
mixin Health on Component {
  final _dirty = Field.boolean();
}
mixin Shield on Component {
  final _dirty = Field.boolean();
}
class Player extends EntityStruct with Health, Shield {}
''',
      });

      final scan = scanStructRules(dir);
      expect(scan.shadowed, hasLength(1));
      expect(scan.shadowed.single.field, '_dirty');
      expect(scan.shadowed.single.winner, 'Shield');
      expect(scan.shadowed.single.loser, 'Health');
    });

    test('two parts of one library collide across their files', () {
      // The case that makes the file a proxy and not the answer. `part` puts
      // both declarations in one library, where a private name is one member,
      // so this is a real collision between two files.
      //
      // One part sits in a subdirectory, because the `part` URI is written
      // with forward slashes whatever the platform and has to come back as a
      // path that matches the one the scan walked to.
      final dir = _project(<String, String>{
        'game.dart': '''
part 'health.dart';
part 'parts/shield.dart';

class Player extends EntityStruct with Health, Shield {}
''',
        'health.dart': '''
part of 'game.dart';

mixin Health on Component {
  final _dirty = Field.boolean();
}
''',
        'parts/shield.dart': '''
part of '../game.dart';

mixin Shield on Component {
  final _dirty = Field.boolean();
}
''',
      });

      final scan = scanStructRules(dir);
      expect(scan.shadowed.map((s) => '${s.winner}.${s.field}'), <String>[
        'Shield._dirty',
      ]);
      expect(scan.shadowed.single.winnerFile, endsWith('shield.dart'));
      expect(scan.shadowed.single.loserFile, endsWith('health.dart'));
    });

    test('a third declaration is compared against its own library', () {
      // Health and Armour are one library, Shield another, applied in that
      // order. Health._dirty and Armour._dirty are one member and the second
      // hides the first; Shield._dirty is a different member and hides
      // neither. A check that compared each name against whichever
      // declaration claimed it last would have Shield in hand by the time
      // Armour is read, see two libraries, and let the real collision through.
      final dir = _project(<String, String>{
        'health.dart': '''
mixin Health on Component {
  final _dirty = Field.boolean();
}
mixin Armour on Component {
  final _dirty = Field.boolean();
}
''',
        'shield.dart': '''
mixin Shield on Component {
  final _dirty = Field.boolean();
}
''',
        'player.dart': '''
class Player extends EntityStruct with Health, Shield, Armour {}
''',
      });

      final scan = scanStructRules(dir);
      expect(scan.shadowed.map((s) => '${s.winner}.${s.field}'), <String>[
        'Armour._dirty',
      ]);
      expect(scan.shadowed.single.loser, 'Health');
    });

    test('a public name still collides across libraries', () {
      // The line this fix must not move: `speed` in two files is one member
      // and one of the two columns is unreachable.
      final dir = _project(<String, String>{
        'velocity.dart': '''
mixin Velocity on Component {
  final speed = Field.float64();
}
''',
        'momentum.dart': '''
mixin Momentum on Component {
  final speed = Field.float64();
}
''',
        'player.dart': '''
class Player extends EntityStruct with Velocity, Momentum {}
''',
      });

      expect(scanStructRules(dir).shadowed, hasLength(1));
    });
  });

  test('two plain fields colliding are not this check\'s business', () {
    final dir = _project(<String, String>{
      'game.dart': '''
mixin Velocity on Component {
  final int speed = 1;
}
mixin Fast on Component {
  final int speed = 2;
}
class Player extends EntityStruct with Velocity, Fast {}
''',
    });

    expect(
      scanStructRules(dir).shadowed,
      isEmpty,
      reason:
          'no column is allocated either side, so no row grows and nothing is '
          'unreachable that Dart does not already describe',
    );
  });

  test('a project with no lib directory scans clean', () {
    final dir = Directory.systemTemp.createTempSync('good_shadow_empty');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final scan = scanStructRules(dir);
    expect(scan.isEmpty, isTrue);
    expect(scan.unresolved, isEmpty);
  });

  // --- #64: a component mixin that stops chaining a declare-time hook ------
  //
  // `@mustCallSuper` cannot reach this. It reports only where the analyzer
  // finds a concrete super implementation to point at, and `Component`
  // declares describeType, describeAssets and describeStruct with no body - so
  // the annotation is inert exactly where mixins chain. A user's own struct
  // subclass is covered, because the lookup walks past the mixins to
  // `EntityStruct`. Library and third-party component mixins are the gap.
  //
  // Surveyed before any of this was written: all fourteen describeX overrides
  // across the engine's eleven component mixins chain, so no legitimate
  // pattern here overrides without calling super.

  group('a component mixin has to chain its declare-time hooks', () {
    test('an override that drops the call is named with its hook and file', () {
      final dir = _project(<String, String>{
        'velocity.dart': '''
mixin Velocity on Component {
  final speed = Field.float64();

  @override
  void describeType(ComponentDescriptor component) {
    component.has<Velocity>();
  }
}
''',
      });

      final scan = scanStructRules(dir);
      expect(scan.missingSuper, hasLength(1));
      final hit = scan.missingSuper.single;
      expect(hit.mixin, 'Velocity');
      expect(hit.hook, 'describeType');
      expect(hit.file, endsWith('velocity.dart'));
      expect(
        missingSuperMessage(scan),
        contains('Velocity.describeType does not call super.describeType()'),
      );
    });

    test('an override that chains is left alone', () {
      final dir = _project(<String, String>{
        'game.dart': '''
mixin Velocity on Component {
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Velocity>();
  }
}
''',
      });
      expect(scanStructRules(dir).missingSuper, isEmpty);
    });

    test('a mixin that overrides no hook at all is not mentioned', () {
      final dir = _project(<String, String>{
        'game.dart': '''
mixin Velocity on Component {
  final speed = Field.float64();
}
''',
      });
      final scan = scanStructRules(dir);
      expect(scan.missingSuper, isEmpty);
      expect(scan.unresolved, isEmpty);
    });

    test('a MultiComponent mixin is held to the same rule', () {
      final dir = _project(<String, String>{
        'game.dart': '''
mixin Renderable2D on MultiComponent {
  @override
  void describeStruct(DataDescriptor data) {
    data.hasFloat64();
  }
}
''',
      });
      expect(scanStructRules(dir).missingSuper.single.mixin, 'Renderable2D');
    });

    test('an arrow-bodied override counts as chaining', () {
      final dir = _project(<String, String>{
        'game.dart': '''
mixin Velocity on Component {
  @override
  void describeAssets(AssetDescriptor descriptor) =>
      super.describeAssets(descriptor);
}
''',
      });
      expect(scanStructRules(dir).missingSuper, isEmpty);
    });

    test('chaining a different hook does not count', () {
      // Calling super.describeStruct from describeType leaves the describeType
      // chain cut, and runs the other pass twice.
      final dir = _project(<String, String>{
        'game.dart': '''
mixin Velocity on Component {
  @override
  void describeType(ComponentDescriptor component) {
    super.describeStruct(component);
  }
}
''',
      });
      expect(scanStructRules(dir).missingSuper.single.hook, 'describeType');
    });

    test('the call has to be code, not a comment or a string', () {
      // Matched on the AST. A text search would call both of these chained.
      final dir = _project(<String, String>{
        'game.dart': '''
mixin Velocity on Component {
  @override
  void describeType(ComponentDescriptor component) {
    // super.describeType(component);
    final note = 'super.describeType(component)';
    component.has<Velocity>();
  }
}
''',
      });
      expect(scanStructRules(dir).missingSuper, hasLength(1));
    });

    test('a mixin constrained to another component mixin is covered', () {
      final dir = _project(<String, String>{
        'game.dart': '''
mixin Transform2D on Component {
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
  }
}
mixin Aimed on Transform2D {
  @override
  void describeStruct(DataDescriptor data) {
    data.hasFloat64();
  }
}
''',
      });
      final scan = scanStructRules(dir);
      expect(scan.missingSuper.single.mixin, 'Aimed');
      expect(scan.missingSuper.single.hook, 'describeStruct');
    });

    test('a mixin on an unrelated type is not this rule to apply', () {
      // `describeStruct` on a mixin that is not a component means nothing here,
      // and failing a build over it would be the false positive that makes the
      // check hostile.
      final dir = _project(<String, String>{
        'game.dart': '''
mixin Reporting on StringBuffer {
  void describeStruct(DataDescriptor data) {
    data.hasFloat64();
  }
}
''',
      });
      expect(scanStructRules(dir).missingSuper, isEmpty);
    });

    test('a hook on a mixin whose constraint went unread is reported', () {
      final dir = _project(<String, String>{
        'game.dart': '''
mixin Velocity on SomethingElsewhere {
  @override
  void describeType(ComponentDescriptor component) {
    component.has<Velocity>();
  }
}
''',
      });
      final scan = scanStructRules(dir);
      expect(
        scan.missingSuper,
        isEmpty,
        reason: 'nothing says this is a component, so nothing is failed over',
      );
      expect(
        scan.unresolved.keys,
        contains('Velocity on SomethingElsewhere'),
        reason: 'but it declares a declare-time hook, so it is worth saying',
      );
    });

    test('a struct subclass is left to @mustCallSuper', () {
      final dir = _project(<String, String>{
        'game.dart': '''
class Player extends EntityStruct {
  @override
  void describeStruct(DataDescriptor data) {
    data.hasFloat64();
  }
}
''',
      });
      expect(
        scanStructRules(dir).missingSuper,
        isEmpty,
        reason:
            'the analyzer already enforces this one, and reporting it twice '
            'would put two different errors on one line',
      );
    });

    test('a bodiless hook declaration overrides nothing and is skipped', () {
      final dir = _project(<String, String>{
        'game.dart': '''
mixin Velocity on Component {
  @override
  void describeType(ComponentDescriptor component);
}
''',
      });
      expect(scanStructRules(dir).missingSuper, isEmpty);
    });
  });
}
