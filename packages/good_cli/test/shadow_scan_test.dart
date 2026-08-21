import 'dart:io';

import 'package:good_cli/src/generate/shadow_scan.dart';
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

    final scan = scanShadowedFields(dir);
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

    expect(scanShadowedFields(dir).shadowed, isEmpty);
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

    final scan = scanShadowedFields(dir);
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

    final scan = scanShadowedFields(dir);
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

    final scan = scanShadowedFields(dir);
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
    // The case the issue calls the likeliest: `Child` declares `parent`
    // unprefixed, and `parent` is exactly what a user's own component would
    // name a field. It only surfaces because the scan reads the engine package
    // the project resolves.
    final dir = _project(<String, String>{
      'game.dart': '''
mixin Ownership on Component {
  final parent = Field.optEntity();
}
class Crate extends EntityStruct with Child, Ownership {}
''',
    });
    _withEnginePackage(dir, '''
mixin Child on Component {
  final parent = Field.optEntity();
  final nextSibling = Field.optEntity();
}
''');

    final scan = scanShadowedFields(dir);
    expect(scan.shadowed, hasLength(1));
    expect(scan.shadowed.single.field, 'parent');
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
  final parent = Field.optEntity();
}
class Crate extends EntityStruct with Child, Ownership {}
''',
    });

    final scan = scanShadowedFields(dir);
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
  final parent = Field.optEntity();
}
class Crate extends EntityStruct with Child, Ownership {}
''',
    });
    final engine = Directory('${dir.path}/engine/lib')
      ..createSync(recursive: true);
    File('${engine.path}/good.dart').writeAsStringSync('''
mixin Child on Component {
  final parent = Field.optEntity();
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

    final scan = scanShadowedFields(dir);
    expect(scan.shadowed.map((s) => '${s.winner}.${s.field}'), <String>[
      'Ownership.parent',
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

    expect(scanShadowedFields(dir).shadowed, isEmpty);
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
      scanShadowedFields(dir).shadowed,
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
    final scan = scanShadowedFields(dir);
    expect(scan.isEmpty, isTrue);
    expect(scan.unresolved, isEmpty);
  });
}
