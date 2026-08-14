import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/archetype.dart';
import 'package:goo/src/asset.dart';
import 'package:goo/src/data.dart';
import 'package:goo/src/game.dart';
import 'package:goo/src/game_state.dart';
import 'package:goo/src/pool.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/struct.dart';
import 'package:goo/src/handle.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late InlineGameHandle run;


// Fixtures deliberately never touch dart:ui or a real file: the thing under
// test is the declare/load/unload lifecycle and the address bookkeeping, and
// a fake that *counts its decodes* is the only way to prove "shared assets
// are not reloaded" - a reload that happened to produce the same payload
// would pass an assertion about final state and fail this one.

/// The mutable half of an asset fixture, kept in a separate object because
/// `GameAsset`/`GameAssetSource` are `@immutable` - correctly, since a key is
/// a map key and a description of where bytes live, not a place to keep
/// state. A `final` field holding a mutable counter satisfies that and still
/// lets the tests below assert on decode counts.
class _Counts {
  int reads = 0;
  int decodes = 0;

  /// Instances handed out by `createInstance` - one per declaration. A second
  /// entry means a key was declared twice, which is exactly the bug
  /// `AssetDescriptor.has`'s idempotence exists to prevent.
  final List<_FakeInstance> created = <_FakeInstance>[];
}

/// Bytes from nowhere, with a read counter.
class _FakeSource extends GameAssetSource {
  _FakeSource(this.name, this.byteCount, this.counts);

  final String name;
  final int byteCount;
  final _Counts counts;

  int get reads => counts.reads;

  @override
  Future<Uint8List> load() async {
    counts.reads++;
    return Uint8List(byteCount);
  }

  @override
  String get description => name;
}

class _FakeInstance extends GameAssetInstance {
  int? _byteCount;
  bool disposed = false;

  /// The payload. Guarded exactly the way a real instance's is - see
  /// `Texture.image` in goo2d.
  int get byteCount {
    requireLoaded();
    return _byteCount!;
  }

  @override
  void onUnloaded() {
    super.onUnloaded();
    _byteCount = null;
    disposed = true;
  }
}

class _FakeAsset extends GameAsset<_FakeInstance> {
  _FakeAsset(String name, {int byteCount = 4})
    : this._(name, byteCount, _Counts());

  _FakeAsset._(String name, int byteCount, this.counts)
    : source = _FakeSource(name, byteCount, counts);

  @override
  final _FakeSource source;

  /// Read counts, decode counts and every instance this key produced. The
  /// assertion "nothing shared was reloaded" is about [_Counts.decodes], not
  /// about the resulting payload - a reload that happened to produce the same
  /// payload has to fail these tests.
  final _Counts counts;

  int get decodes => counts.decodes;
  List<_FakeInstance> get created => counts.created;

  @override
  _FakeInstance createInstance() {
    final instance = _FakeInstance();
    counts.created.add(instance);
    return instance;
  }

  @override
  Future<void> loadInto(_FakeInstance instance) async {
    counts.decodes++;
    final bytes = await source.load();
    instance._byteCount = bytes.length;
  }
}

/// A prefab that declares [key] and keeps the handle - the shape RULES.md
/// rule 6 asks for, and what every "did describeAssets run" assertion below
/// inspects.
class _Prop extends EntityStruct {
  _Prop(this.key);

  final GameAsset<_FakeInstance> key;

  int describeAssetsCalls = 0;
  late final _FakeInstance texture;
  late final DataPointer<_FakeInstance> spriteField;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    describeAssetsCalls++;
    texture = descriptor.has(key);
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    // The payoff of running describeAssets before describeStruct: the handle
    // is already addressed, so it can be this archetype's default row value.
    spriteField = data.hasObject(assets, texture);
  }
}

/// A prefab with no assets at all - proves the chained no-op base still runs
/// and costs nothing.
class _Bare extends EntityStruct {}

class _PropScene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  // A small pool by default: these tests never spawn much, and the 64 MiB
  // default page costs three times that in the pool's triple-buffered slots.
  _PropScene(this.prefabs, {this.sceneKey});

  final List<_Prop> prefabs;
  final GameAsset<_FakeInstance>? sceneKey;

  int describeAssetsCalls = 0;
  _FakeInstance? music;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    describeAssetsCalls++;
    final key = sceneKey;
    if (key != null) music = descriptor.has(key);
  }

  @override
  void describeScene(SceneDescriptor descriptor) {
    for (final prefab in prefabs) {
      descriptor.has(prefab);
    }
  }
}

MemoryPool _pool() => MemoryPool(pageSize: 4096);

/// The table under test. Instance state now, not a global static - a `Game`
/// owns one (see `Game.assets`), and a fixture with no `Game` supplies its
/// own, which is what these tests are. Replaced per test rather than reset,
/// so there is no shared state between them to forget to clear.
late GameAssets assets;

/// Brings a scene up with no `Game` at all - `initializeScene` is public for
/// exactly this, and nothing in the asset pass needs a boot.
_PropScene _bringUp(_PropScene scene) {
  scene.initializeScene(_pool(), assets: assets);
  scene.handle = SceneRegistry.register(scene);
  addTearDown(scene.pool.dispose);
  return scene;
}

void main() {
  setUp(() => assets = GameAssets());

  tearDown(() {
    assets.reset();
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('describeAssets', () {
    test('runs once for the scene and once for every registered prefab', () {
      final a = _Prop(_FakeAsset('a'));
      final b = _Prop(_FakeAsset('b'));
      final scene = _bringUp(
        _PropScene([a, b], sceneKey: _FakeAsset('music')),
      );

      expect(
        scene.describeAssetsCalls,
        1,
        reason: 'a scene declares its own prefab-less assets (music, UI '
            'chrome) exactly once, from initializeScene',
      );
      expect(
        a.describeAssetsCalls,
        1,
        reason: 'every prefab the scene registers gets the pass too - and '
            'exactly once, or the same key would be declared twice',
      );
      expect(b.describeAssetsCalls, 1);
      expect(
        scene.declaredAssets.length,
        3,
        reason: "a scene's footprint is the union of its own assets and every "
            'registered prefab\'s',
      );
    });

    test('the scene\'s own assets are declared before any prefab\'s', () {
      final scene = _bringUp(
        _PropScene(
          [_Prop(_FakeAsset('prop'))],
          sceneKey: _FakeAsset('music'),
        ),
      );

      expect(
        scene.music!.address < scene.prefabs.first.texture.address,
        isTrue,
        reason: 'addresses are handed out in declaration order, and the order '
            'inside one scene has to be fixed and reproducible - it is what '
            'both isolate copies independently replay to agree',
      );
    });

    test('a prefab that declares nothing still chains the no-op base', () {
      final host = _BareScene(_Bare());
      final pool = _pool();
      addTearDown(pool.dispose);

      expect(() => host.initializeScene(pool, assets: assets), returnsNormally);
      expect(
        host.declaredAssets,
        isEmpty,
        reason: 'no declaration means no address consumed - the pass costs a '
            'prefab with no assets nothing at all',
      );
    });

    test('the returned handle is an instance, and the key is not', () {
      final key = _FakeAsset('typed');
      final scene = _bringUp(_PropScene([_Prop(key)]));
      final handle = scene.prefabs.first.texture;

      expect(
        handle,
        isA<GameAssetInstance>(),
        reason: 'only a GameAssetInstance is assignable to an asset-typed '
            'component field - that is what makes `field[e] = handle` compile',
      );
      expect(
        key,
        isNot(isA<GameAssetInstance>()),
        reason: 'and the raw undeclared key is deliberately a different type, '
            'so `field[e] = key` cannot compile - the whole reason every '
            'asset is routed through describeAssets',
      );
    });

    test('the declared handle works as a row default and resolves back', () {
      final key = _FakeAsset('default');
      final scene = _bringUp(_PropScene([_Prop(key)]));
      final prop = scene.prefabs.first;
      final entity = scene.handle.addEntity(prop);

      expect(
        prop.spriteField[entity],
        same(prop.texture),
        reason: 'the row stores the declared address and resolves it through '
            'GlobalObjectRegistry - no heap reference in the row, and no '
            'asset manager threaded through the read',
      );
    });
  });

  group('sharing', () {
    test('two prefabs declaring one key get the identical instance', () {
      final shared = _FakeAsset('shared');
      final a = _Prop(shared);
      final b = _Prop(shared);
      final scene = _bringUp(_PropScene([a, b]));

      expect(
        identical(a.texture, b.texture),
        isTrue,
        reason: 'two prefabs using one texture must be one decode and one '
            'address, not two - which only holds if has() is idempotent per '
            'key',
      );
      expect(a.texture.address, b.texture.address);
      expect(
        shared.created.length,
        1,
        reason: 'and the second declaration must not even construct a second '
            'instance, or the first would silently be the orphan',
      );
      expect(
        scene.declaredAssets.length,
        1,
        reason: "the scene's footprint counts the asset once, so the "
            'transition diff cannot double-count it either',
      );
    });

    test('a scene and a prefab declaring one key share it too', () {
      final shared = _FakeAsset('shared');
      final prop = _Prop(shared);
      final scene = _bringUp(
        _PropScene([prop], sceneKey: shared),
      );

      expect(identical(scene.music, prop.texture), isTrue);
      expect(
        scene.declaredAssets.length,
        1,
        reason: 'the scene and its prefabs declare into one descriptor, so '
            'this is the same declaration, not two that happen to match',
      );
    });

    test('two separate keys for the same bytes are two assets', () {
      final a = _Prop(_FakeAsset('same-bytes'));
      final b = _Prop(_FakeAsset('same-bytes'));
      _bringUp(_PropScene([a, b]));

      expect(
        identical(a.texture, b.texture),
        isFalse,
        reason: 'keys are identity-compared - construct one shared static '
            'final key when you mean one asset; two keys naming the same file '
            'are deliberately two assets',
      );
      expect(a.texture.address, isNot(b.texture.address));
    });
  });

  group('cross-copy address agreement', () {
    test('two independent boot passes assign the same addresses', () {
      // Exactly what the two isolate copies do: the same user code runs the
      // same describe passes in the same order on two heaps. Simulated here
      // by running the pass twice from a clean registry, as the existing
      // cross-isolate-agreement tests do.
      List<int> run() {
        final scene = _PropScene(
          [_Prop(_FakeAsset('a')), _Prop(_FakeAsset('b'))],
          sceneKey: _FakeAsset('music'),
        );
        scene.initializeScene(_pool(), assets: assets);
        final addresses = <int>[
          scene.music!.address,
          for (final prefab in scene.prefabs) prefab.texture.address,
        ];
        scene.pool.dispose();
        return addresses;
      }

      final first = run();
      assets.reset();
      assets.reset();
      ArchetypeRegistry.reset();
      ComponentTypeRegistry.reset();
      final second = run();

      expect(
        second,
        first,
        reason: 'address assignment is first-declaration order and nothing '
            'else, so the copy that cannot decode still writes the exact '
            'address the copy that can will resolve',
      );
    });

    test('an unloaded key re-declares to a fresh address, not the old one', () {
      final key = _FakeAsset('recycled');
      final first = assets.declare(key);
      final firstAddress = first.address;
      assets.unload(key);
      final second = assets.declare(key);

      expect(identical(first, second), isFalse);
      expect(
        second.address,
        isNot(firstAddress),
        reason: 'GlobalObjectRegistry only ever appends and nulls; recycling '
            'an address would let a stale row silently resolve to whatever '
            'was declared next',
      );
    });
  });

  group('declared but not loaded', () {
    test('the address is usable immediately, the payload is not', () {
      final key = _FakeAsset('unloaded');
      final instance = assets.declare(key);

      expect(
        instance.address,
        isNonNegative,
        reason: 'the game isolate writes this address into rows without ever '
            'decoding anything - that is the whole point of the split',
      );
      expect(instance.isLoaded, isFalse);
      expect(
        () => instance.byteCount,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('unloaded'), contains('never loaded')),
          ),
        ),
        reason: 'reading a payload that was never decoded must name the asset '
            'and say it was never loaded - not null-deref three frames deeper',
      );
    });

    test('the payload reads normally once loaded', () async {
      final key = _FakeAsset('loaded', byteCount: 17);
      final instance = assets.declare(key);
      await assets.load(key);

      expect(instance.isLoaded, isTrue);
      expect(instance.byteCount, 17);
    });

    test('address on a hand-built instance throws rather than defaulting', () {
      expect(
        () => _FakeInstance().address,
        throwsStateError,
        reason: 'an instance that never went through a describeAssets pass '
            'has nothing for a DataPointer row to point at, and address 0 is '
            'a legitimate other asset',
      );
    });
  });

  group('assets.load', () {
    test('decodes once, then returns the cached instance', () async {
      final key = _FakeAsset('once');
      assets.declare(key);

      final a = await assets.load(key);
      final b = await assets.load(key);

      expect(identical(a, b), isTrue);
      expect(key.decodes, 1, reason: 'a repeat load must not re-decode');
      expect(key.source.reads, 1, reason: 'nor re-read the source bytes');
    });

    test('two overlapping loads share one decode', () async {
      final key = _FakeAsset('concurrent');
      assets.declare(key);

      final results = await Future.wait(<Future<_FakeInstance>>[
        assets.load(key),
        assets.load(key),
      ]);

      expect(identical(results[0], results[1]), isTrue);
      expect(
        key.decodes,
        1,
        reason: 'the second caller joins the in-flight decode; two decodes '
            'would leave one payload orphaned and, for a real texture, leak '
            'a ui.Image',
      );
    });

    test('an undeclared key is refused, by name and with the fix', () {
      final key = _FakeAsset('never-declared');
      expect(
        () => assets.load(key),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('never-declared'), contains('describeAssets')),
          ),
        ),
        reason: 'lazily declaring here would assign an address on this copy '
            'alone, and every address after it would then disagree with the '
            'other copy - a silent corruption, so it fails loudly instead',
      );
    });

    test('tryGet is a non-throwing peek that ignores load state', () async {
      final key = _FakeAsset('peek');
      expect(assets.tryGet(key), isNull);

      final declared = assets.declare(key);
      expect(
        assets.tryGet(key),
        same(declared),
        reason: 'declared-but-unloaded is the normal steady state on the game '
            'isolate, not an absence',
      );

      await assets.load(key);
      expect(assets.tryGet(key), same(declared));
    });
  });

  group('assets.unload', () {
    test('frees the address, releases the payload, drops the declaration',
        () async {
      final key = _FakeAsset('doomed');
      final instance = assets.declare(key);
      await assets.load(key);
      final address = instance.address;

      assets.unload(key);

      expect(assets.tryGet(key), isNull);
      expect(instance.disposed, isTrue,
          reason: 'onUnloaded is where a real instance releases its ui.Image');
      expect(instance.isLoaded, isFalse);
      expect(assets.tryResolve<_FakeInstance>(address), isNull);
      expect(
        () => assets.resolve<_FakeInstance>(address),
        throwsStateError,
        reason: 'a row still holding the freed address fails loudly on next '
            'read - unloading something still referenced is a caller bug',
      );
    });

    test('unloading something never declared is a no-op', () {
      expect(() => assets.unload(_FakeAsset('absent')), returnsNormally);
    });

    test('unloadAll clears every declaration', () async {
      final keys = <_FakeAsset>[
        for (var i = 0; i < 5; i++) _FakeAsset('bulk$i'),
      ];
      final instances = <_FakeInstance>[
        for (final key in keys) assets.declare(key),
      ];
      for (final key in keys) {
        await assets.load(key);
      }

      assets.unloadAll();

      for (var i = 0; i < keys.length; i++) {
        expect(assets.tryGet(keys[i]), isNull);
        expect(assets.tryResolve(instances[i].address), isNull);
        expect(instances[i].disposed, isTrue);
      }
    });
  });

  group('assets.reset', () {
    test('genuinely clears, so declaring again is a fresh decode', () async {
      final key = _FakeAsset('sticky');
      assets.declare(key);
      await assets.load(key);
      expect(key.decodes, 1);

      assets.reset();

      expect(
        assets.tryGet(key),
        isNull,
        reason: 'a leftover declaration would make every later test in the '
            'process see this one\'s state - the exact order-dependence this '
            'hook exists to remove',
      );
      assets.declare(key);
      await assets.load(key);
      expect(
        key.decodes,
        2,
        reason: 'and the re-declared instance really is unloaded, rather than '
            'a cached one that reset only pretended to drop',
      );
      expect(
        key.created.length,
        2,
        reason: 'reset drops the instance too, not just the loaded flag',
      );
    });

    test('releases payloads so a native handle is not leaked', () async {
      final key = _FakeAsset('native');
      final instance = assets.declare(key);
      await assets.load(key);

      assets.reset();

      expect(instance.disposed, isTrue);
    });
  });

  group('GlobalObjectRegistry', () {
    test('tryResolve is null for a never-registered or out-of-range address',
        () {
      expect(assets.tryResolve<_FakeInstance>(0), isNull);
      expect(assets.tryResolve<_FakeInstance>(-1), isNull);
      expect(assets.tryResolve<_FakeInstance>(999), isNull);
    });

    test('tryResolve is null for the wrong type at a valid address', () {
      final instance = assets.declare(_FakeAsset('typed'));
      expect(
        assets.tryResolve<_Unrelated>(instance.address),
        isNull,
      );
    });
  });

  group('loadScene asset diffing', () {
    test('a first load decodes exactly the scene\'s declared set', () async {
      final music = _FakeAsset('music');
      final prop = _FakeAsset('prop');
      final unused = _FakeAsset('unused');
      await _boot(
        _DiffGame(() => _PropScene([_Prop(prop)], sceneKey: music)),
      );

      expect(music.decodes, 1, reason: "the scene's own prefab-less asset");
      expect(prop.decodes, 1, reason: 'and every registered prefab\'s');
      expect(
        unused.decodes,
        0,
        reason: 'a key nothing declared is not part of the scene, so nothing '
            'about a scene load should touch it',
      );
      expect(assets.tryGet(unused), isNull);
    });

    test('an asset shared by two loaded scenes is decoded once', () async {
      final shared = _FakeAsset('shared');
      final onlyA = _FakeAsset('only-a');
      final onlyB = _FakeAsset('only-b');

      await _boot(
        _DiffGame(() => _PropScene([_Prop(onlyA)], sceneKey: shared)),
      );
      expect(shared.decodes, 1);
      expect(onlyA.decodes, 1);

      // Loading no longer *replaces*: both scenes are resident now, and both
      // hold a claim on `shared`.
      await run.state.loadScene(
        _PropScene([_Prop(onlyB)], sceneKey: shared),
      );

      expect(
        shared.decodes,
        1,
        reason: 'the second scene raises the claim count rather than decoding '
            'again - asserted against the decode counter, because a reload '
            'producing an identical payload would satisfy any assertion about '
            'final state',
      );
      expect(assets.tryGet(shared)?.isLoaded, isTrue);
      expect(onlyB.decodes, 1, reason: 'what only the new scene needs loads');
      expect(
        assets.tryGet(onlyA)?.isLoaded,
        isTrue,
        reason: 'loading no longer unloads anything - the first scene is still '
            'resident and still claims its own asset. Freeing is what '
            'unloadScene is for, and that is the whole reason a claim count '
            'replaced the pairwise previous->next diff',
      );
    });

    test('a shared asset outlives the first unload and dies with the last',
        () async {
      final shared = _FakeAsset('shared');
      final onlyA = _FakeAsset('only-a');
      final onlyB = _FakeAsset('only-b');
      await _boot(
        _DiffGame(() => _PropScene([_Prop(onlyA)], sceneKey: shared)),
      );
      final first = run.state.sceneHandle!;
      final second = await run.state.loadScene(
        _PropScene([_Prop(onlyB)], sceneKey: shared),
      );

      run.state.unloadScene(first);

      expect(assets.tryGet(onlyA), isNull,
          reason: 'nothing else claimed it, so it goes with its scene');
      expect(
        assets.tryGet(shared)?.isLoaded,
        isTrue,
        reason: 'the second scene still claims it - this is exactly what the '
            'old pairwise previous->next diff could not express, because with '
            'A and C sharing an atlas and B not, A->B freed it and B->C '
            'decoded it again',
      );

      run.state.unloadScene(second);
      expect(assets.tryGet(shared), isNull,
          reason: 'the last claim released is what frees it');
      expect(assets.tryGet(onlyB), isNull,
          reason: 'and the asset only the second scene claimed goes with it');
    });

    test('onProgress is monotonic and ends at exactly 1.0', () async {
      final keys = <_FakeAsset>[
        for (var i = 0; i < 4; i++) _FakeAsset('step$i'),
      ];
      await _boot(_DiffGame(() => GameSceneStub()));

      final reports = <SceneLoadProgress>[];
      await run.state.loadScene(
        _PropScene(
          [for (var i = 1; i < keys.length; i++) _Prop(keys[i])],
          sceneKey: keys.first,
        ),
        onProgress: reports.add,
      );

      expect(reports, isNotEmpty);
      for (var i = 1; i < reports.length; i++) {
        expect(
          reports[i].progress,
          greaterThanOrEqualTo(reports[i - 1].progress),
          reason: 'a loading bar that goes backwards is a bug in the reporter, '
              'not something every consumer should have to clamp',
        );
      }
      expect(
        reports.last.progress,
        1.0,
        reason: 'the terminal report is exactly 1.0, so "hide the loading '
            'screen" can key off equality rather than a threshold',
      );
      expect(
        reports.first.label,
        contains('step0'),
        reason: 'each report names what was just loaded',
      );
    });

    test('a transition needing no decodes still reports a single 1.0',
        () async {
      final shared = _FakeAsset('shared');
      await _boot(
        _DiffGame(() => _PropScene([], sceneKey: shared)),
      );

      final reports = <SceneLoadProgress>[];
      await run.state.loadScene(
        _PropScene([], sceneKey: shared),
        onProgress: reports.add,
      );

      expect(shared.decodes, 1);
      expect(
        reports.map((r) => r.progress).toList(),
        <double>[1.0],
        reason: 'no decodes means nothing to report fractions of - but the '
            'caller still has to be told it is done, without having to '
            'special-case the empty case itself',
      );
    });

    test('loading one declaration twice gives two scenes sharing its assets',
        () async {
      final key = _FakeAsset('same-scene');
      await _boot(_DiffGame(() => _PropScene([_Prop(key)])));
      final struct = run.state.scene!;
      final first = run.state.sceneHandle!;

      // The same *declaration*, loaded again. It is not a no-op any more -
      // it is a second resident instance with its own pages - but its assets
      // are already decoded, so it costs no decode.
      final second = await run.state.loadScene(struct);

      expect(key.decodes, 1);
      expect(second, isNot(first));
      expect(run.state.loadedScenes.length, 2);

      run.state.unloadScene(second);
      expect(assets.tryGet(key)?.isLoaded, isTrue,
          reason: 'the first load still claims it');
    });

    test('the world layout exists before the bring-up future completes', () {
      final game = _DiffGame(() => _PropScene([_Prop(_FakeAsset('sync'))]));
      expect(ArchetypeRegistry.count, 0, reason: 'nothing registered yet');

      // Deliberately not awaited. The claim is that `loadScene`'s registering
      // half runs before its first `await`, so the world *layout* exists the
      // instant bring-up has been called - only the content is still arriving.
      // An async function runs synchronously up to its own first await, which
      // is what makes that observable at all.
      final starting = Game.startInline(game);

      // Asserted through the archetype registry rather than through the state.
      // The run is what owns the state now, and the run does not exist until
      // its future completes - so "before the future completes" and "reachable
      // through the handle" are mutually exclusive by construction. Registering
      // an archetype is what the synchronous half *does*, so it is the more
      // direct evidence anyway.
      expect(
        ArchetypeRegistry.count,
        greaterThan(0),
        reason: 'the entity layout is registered synchronously; it is the '
            'asset content that is still arriving',
      );

      addTearDown(() async {
        final run = await starting;
        if (run.isRunning) await run.stop();
      });
    });
  });
}

class _Unrelated extends GameAssetInstance {}

class _BareScene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _BareScene(this._prefab);

  final _Bare _prefab;

  @override
  void describeScene(SceneDescriptor descriptor) => descriptor.has(_prefab);
}

class GameSceneStub extends SceneStruct {
  GameSceneStub();
}

/// A game whose state loads whatever scene the test handed it - the inline
/// single-copy path, which is also the "this copy decodes" path.
class _DiffGame extends Game {
  _DiffGame(this.first);

  final SceneStruct Function() first;

  @override
  GameState createState() => _DiffState();
}

class _DiffState extends GameState<_DiffGame> {
  /// The boot load's future. `onMounted` cannot be async and `start()` does
  /// not await what a state loads, so a test that wants "the first scene has
  /// finished decoding" has to await this rather than trust that enough
  /// microtasks happened to drain on the way out of `start()`.
  Future<void>? loading;

  @override
  void onMounted() {
    loading = loadScene(game.first());
  }
}

Future<T> _boot<T extends Game>(T game) async {
  run = await Game.startInline(game);
  // A booted Game owns its own table, so the fixture's handle points at that
  // one from here on - these tests are asserting about the assets the game
  // actually declared and loaded, not about a table nothing is using.
  assets = game.assets;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  final state = run.state;
  if (state is _DiffState) await state.loading;
  return game;
}
