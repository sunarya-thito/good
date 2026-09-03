import 'dart:io';

import 'package:good_cli/src/assets/pack.dart';
import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/scene_scan.dart';
import 'package:test/test.dart';

import '_temp.dart';

// Which scene needs which asset, and therefore which chunk each asset lands
// in.
//
// This is the pass that replaced directory grouping. What makes it worth
// testing carefully is that being *wrong* is invisible at build time: a
// misattributed asset still ships, still loads, and only shows up as a loading
// screen reading more chunks than it should - or, if one were dropped, as a
// game that fails much later. So the cases below are mostly about attribution,
// and one is about what happens when attribution fails.

Directory _project(String source, {List<String> assets = const <String>[]}) {
  final dir = testTempDir('good_scenes');
  File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: demo
flutter:
  assets:
    - assets/
''');
  for (final name in assets) {
    File('${dir.path}/assets/$name')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('bytes');
  }
  File('${dir.path}/lib/game.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(source);
  return dir;
}

SceneUsage _scan(Directory dir) => scanScenes(dir, scanAssets(dir));

void main() {
  test('a scene gets the assets it declares itself', () {
    final dir = _project(
      '''
class MenuScene extends SceneStruct {
  @override
  void describeAssets(AssetDescriptor descriptor) {
    logo = descriptor.has(Textures.logo);
  }
}
''',
      assets: <String>['logo.webp', 'other.webp'],
    );
    final usage = _scan(dir);
    expect(usage.byScene, {
      'MenuScene': {'assets/logo.webp'},
    });
  });

  test('a scene inherits the assets of the prefabs it registers', () {
    // The reason this needs to follow references at all: a scene's asset set
    // is not written in one place.
    final dir = _project(
      '''
class FieldScene extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(Bullet.new);
  }
}

class Bullet extends EntityStruct {
  @override
  void describeAssets(AssetDescriptor descriptor) {
    hit = descriptor.has(Textures.hit);
  }
}
''',
      assets: <String>['hit.webp'],
    );
    expect(_scan(dir).byScene['FieldScene'], {'assets/hit.webp'});
  });

  test('every way of naming a prefab is recognised', () {
    // `Bullet.new` is the spelling `SceneDescriptor.has` takes, and a prefab
    // with constructor arguments is wrapped in a closure. `Bullet()` and
    // `new Bullet()` no longer compile against it, but source that has not
    // been migrated is still worth reading rather than dropping into
    // `unresolved` - missing a prefab silently detaches it from its scene,
    // and the grouping still *looks* plausible.
    final dir = _project(
      '''
class A extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(Bullet.new);
  }
}

class B extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(new Bullet());
  }
}

class C extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(Bullet());
  }
}

class D extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(() => Bullet(speed: 5));
  }
}

class Bullet extends EntityStruct {
  @override
  void describeAssets(AssetDescriptor descriptor) {
    hit = descriptor.has(Textures.hit);
  }
}
''',
      assets: <String>['hit.webp'],
    );
    final usage = _scan(dir);
    for (final scene in ['A', 'B', 'C', 'D']) {
      expect(usage.byScene[scene], {'assets/hit.webp'}, reason: scene);
    }
    expect(usage.unresolved, isEmpty);
  });

  test('a scene declared as a mixin on SceneStruct counts', () {
    // How penguincivilwar writes one.
    final dir = _project(
      '''
mixin FieldScene on SceneStruct {
  @override
  void describeAssets(AssetDescriptor descriptor) {
    bg = descriptor.has(Textures.bg);
  }
}
''',
      assets: <String>['bg.webp'],
    );
    expect(_scan(dir).byScene['FieldScene'], {'assets/bg.webp'});
  });

  test('a class picks up assets from the scene mixin it applies', () {
    final dir = _project(
      '''
mixin FieldAssets on SceneStruct {
  @override
  void describeAssets(AssetDescriptor descriptor) {
    bg = descriptor.has(Textures.bg);
  }
}

class Level extends SceneStruct with FieldAssets {}
''',
      assets: <String>['bg.webp'],
    );
    expect(_scan(dir).byScene['Level'], {'assets/bg.webp'});
  });

  test('a prefab cycle terminates instead of recursing forever', () {
    final dir = _project(
      '''
class S extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(A.new);
  }
}

class A extends EntityStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(B.new);
  }
  @override
  void describeAssets(AssetDescriptor descriptor) {
    x = descriptor.has(Textures.bg);
  }
}

class B extends EntityStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(A.new);
  }
}
''',
      assets: <String>['bg.webp'],
    );
    expect(_scan(dir).byScene['S'], {'assets/bg.webp'});
  });

  test('an asset named in a field initialiser lands in its scene', () {
    // #194: the declaration is not in a method body at all. Read from the
    // field or the asset is attributed to no scene, and `_planByScene` puts
    // it in the shared chunk - which still ships, and still costs the scene a
    // chunk read it did not need.
    final dir = _project(
      '''
class FieldScene extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(Plane.new);
  }
}

class Plane extends EntityStruct {
  final texture = Asset.of(Textures.plane);
}
''',
      assets: <String>['plane.webp', 'other.webp'],
    );
    final usage = _scan(dir);
    expect(usage.byScene, {
      'FieldScene': {'assets/plane.webp'},
    });
    expect(usage.unresolved, isEmpty);
  });

  test('a child prefab declared in a field initialiser is followed', () {
    // Predates #194: `EntityStruct.of` in an initialiser ships and is used,
    // and its child contributed nothing here, so the child's own assets were
    // attributed to no scene.
    final dir = _project(
      '''
class FieldScene extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(Turret.new);
  }
}

class Turret extends EntityStruct {
  final barrel = EntityStruct.of(Barrel.new);
  final texture = Asset.of(Textures.turret);
}

class Barrel extends EntityStruct {
  final texture = Asset.of(Textures.barrel);
}
''',
      assets: <String>['turret.webp', 'barrel.webp'],
    );
    expect(_scan(dir).byScene['FieldScene'], {
      'assets/turret.webp',
      'assets/barrel.webp',
    });
  });

  test('an asset named inside another declaration is still read', () {
    final dir = _project(
      '''
class FieldScene extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(Plane.new);
  }
}

class Plane extends EntityStruct {
  final sprite = Sprite.of(width: 64, texture: Asset.of(Textures.plane));
}
''',
      assets: <String>['plane.webp'],
    );
    expect(_scan(dir).byScene['FieldScene'], {'assets/plane.webp'});
  });

  test('a static field initialiser is not read as a declaration', () {
    // A static initialiser is lazy, so it runs on first read rather than in
    // the pass both isolate copies replay - it is refused at run time, and
    // reading it here would attribute an asset no scene ever declares.
    final dir = _project(
      '''
class FieldScene extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(Plane.new);
  }
}

class Plane extends EntityStruct {
  static final shared = Asset.of(Textures.plane);
}
''',
      assets: <String>['plane.webp'],
    );
    expect(_scan(dir).byScene['FieldScene'], isEmpty);
  });

  test('an unreadable key in a field initialiser is reported', () {
    final dir = _project(
      '''
class FieldScene extends SceneStruct {
  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(Plane.new);
  }
}

class Plane extends EntityStruct {
  final texture = Asset.of(keys[index]);
}
''',
      assets: <String>['plane.webp'],
    );
    final usage = _scan(dir);
    expect(usage.byScene['FieldScene'], isEmpty);
    expect(
      usage.unresolved,
      contains('Plane.describeAssets'),
      reason:
          'an asset this pass cannot attribute has to be reported, so it '
          'lands in the shared chunk on purpose rather than by accident',
    );
  });

  test('a key it cannot read is reported, never silently dropped', () {
    final dir = _project(
      '''
class S extends SceneStruct {
  @override
  void describeAssets(AssetDescriptor descriptor) {
    x = descriptor.has(keys[index]);
  }
}
''',
      assets: <String>['bg.webp'],
    );
    final usage = _scan(dir);
    expect(usage.unresolved, isNotEmpty);
    expect(usage.byScene['S'], isEmpty);
  });

  group('grouping', () {
    test('an asset used by one scene goes in that scene chunk', () {
      final plan = planPack(
        ['assets/a.webp', 'assets/b.webp'],
        assetRoot: 'assets/',
        byScene: {
          'MenuScene': {'assets/a.webp'},
          'FieldScene': {'assets/b.webp'},
        },
      );
      expect(plan.chunks.map((c) => c.name), [
        'chunk_fieldscene.dat',
        'chunk_menuscene.dat',
      ]);
      expect(
        plan.chunks.firstWhere((c) => c.name == 'chunk_menuscene.dat').members,
        ['assets/a.webp'],
      );
    });

    test('an asset used by two scenes goes in the shared chunk', () {
      final plan = planPack(
        ['assets/shared.webp'],
        assetRoot: 'assets/',
        byScene: {
          'A': {'assets/shared.webp'},
          'B': {'assets/shared.webp'},
        },
      );
      expect(plan.chunks.single.name, 'chunk_shared.dat');
    });

    test('an unattributed asset still ships, in the shared chunk', () {
      // The important one. An asset this pass could not attribute may be
      // loaded by code it cannot read; dropping it would produce a build that
      // simply fails, which is far worse than one that reads an extra chunk.
      final plan = planPack(
        ['assets/orphan.webp'],
        assetRoot: 'assets/',
        byScene: {'A': <String>{}},
      );
      expect(plan.assetCount, 1);
      expect(plan.chunks.single.name, 'chunk_shared.dat');
    });

    test('the report says it grouped by scene, and how much is shared', () {
      final plan = planPack(
        ['assets/a.webp', 'assets/s.webp'],
        assetRoot: 'assets/',
        byScene: {
          'A': {'assets/a.webp', 'assets/s.webp'},
          'B': {'assets/s.webp'},
        },
      );
      expect(plan.grouping, contains('grouped by scene'));
      expect(plan.grouping, contains('2 scene(s)'));
      expect(plan.grouping, contains('1 asset(s) shared'));
    });

    test('no scene information falls back to directory grouping', () {
      final plan = planPack(
        ['assets/a.webp', 'assets/ui/b.webp'],
        assetRoot: 'assets/',
        byScene: const <String, Set<String>>{},
      );
      expect(plan.chunks.map((c) => c.name), [
        'chunk_root.dat',
        'chunk_ui.dat',
      ]);
    });
  });
}
