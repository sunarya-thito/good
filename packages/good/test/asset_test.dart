import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/scene_handle.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/data.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/struct.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// Fixtures deliberately never touch dart:ui or a real file: the thing under
// test is the declare/load/unload lifecycle and the address bookkeeping, and
// a fake that *counts its decodes* is the only way to prove "shared assets
// are not reloaded" - a reload that happened to produce the same payload
// would pass an assertion about final state and fail this one.

/// The mutable half of an asset fixture, kept out of the key because
/// `AssetKey`/`AssetSource` are `@immutable` - correctly, since a key is an
/// identity and a description of where bytes live, not a place to keep state.
///
/// Keyed by source **name**, not held per key object, and that is forced by
/// the design under test: an asset's identity is `(payload type, source)`, so
/// two separately-constructed `_FakeAsset('x')` *are* one asset. A counter
/// living on the key instance would then be split across two objects for one
/// asset, and every decode assertion would read whichever half the test
/// happened to keep.
class _Counts {
  static final Map<String, _Counts> _byName = <String, _Counts>{};

  static _Counts of(String name) => _byName.putIfAbsent(name, () => _Counts());

  static void resetAll() => _byName.clear();

  int reads = 0;
  int decodes = 0;
}

/// Bytes from nowhere, with a read counter.
class _FakeSource extends AssetSource {
  const _FakeSource(this.name, this.byteCount);

  final String name;
  final int byteCount;

  _Counts get counts => _Counts.of(name);
  int get reads => counts.reads;

  @override
  Future<Uint8List> load() async {
    counts.reads++;
    return Uint8List(byteCount);
  }

  @override
  Future<AssetAvailability> check() async => AssetAvailability.present;

  @override
  String get description => name;

  // Value equality, which `AssetSource`'s doc requires and which the whole
  // identity scheme rests on.
  @override
  bool operator ==(Object other) =>
      other is _FakeSource &&
      other.name == name &&
      other.byteCount == byteCount;

  @override
  int get hashCode => Object.hash(_FakeSource, name, byteCount);
}

/// The decoded payload. A plain class - it is not the addressed thing any
/// more, so it has no address, no loaded flag and no base class. `Asset<T>`
/// carries all of that now, once, for every payload type there will ever be.
class _FakePayload {
  _FakePayload(this.byteCount);

  final int byteCount;
  bool disposed = false;
}

/// The one loader for [_FakePayload], registered per test.
///
/// Everything that used to be a per-key override lives here: there is one of
/// these for the payload type, not one per asset, which is what leaves the key
/// as pure data.
class _FakeLoader extends AssetLoader<_FakePayload> {
  const _FakeLoader();

  @override
  Future<_FakePayload> load(AssetKey<_FakePayload> key) async {
    final source = key.source as _FakeSource;
    source.counts.decodes++;
    final bytes = await source.load();
    return _FakePayload(bytes.length);
  }

  @override
  void unload(_FakePayload value) => value.disposed = true;

  @override
  AssetInfo describe(_FakePayload value) => _FakeInfo(value.byteCount);
}

/// What decoding discovered, replicated to copies that cannot decode.
class _FakeInfo extends AssetInfo {
  const _FakeInfo(this.byteCount);

  final int byteCount;
}

/// A key, with the counters the tests assert on reachable from it.
class _FakeAsset extends AssetKey<_FakePayload> {
  _FakeAsset(String name, {int byteCount = 4})
    : super(_FakeSource(name, byteCount));

  @override
  _FakeSource get source => super.source as _FakeSource;

  /// Decode counts. The assertion "nothing shared was reloaded" is about this,
  /// not about the resulting payload - a reload that happened to produce the
  /// same payload has to fail these tests.
  int get decodes => source.counts.decodes;
}

/// A prefab that declares [key] and keeps the handle - the shape the
/// typed-handle rule asks for, and what every "did describeAssets run"
/// assertion below inspects.
class _Prop extends EntityStruct {
  _Prop(this.key);

  final _FakeAsset key;

  int describeAssetsCalls = 0;
  late final Asset<_FakePayload> texture;
  late final DataPointer<Asset<_FakePayload>> spriteField;

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
    spriteField = data.hasPacked(assets.of<_FakePayload>(), texture);
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
  final _FakeAsset? sceneKey;

  int describeAssetsCalls = 0;
  Asset<_FakePayload>? music;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    describeAssetsCalls++;
    final key = sceneKey;
    if (key != null) music = descriptor.has(key);
  }

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    for (final prefab in prefabs) {
      descriptor.has(() => prefab);
    }
  }
}

MemoryPool _pool() => MemoryPool(pageSize: 4096);

/// The table under test. Instance state now, not a global static - a `Game`
/// owns one (see `Game.assets`), and a fixture with no `Game` supplies its
/// own, which is what these tests are. Replaced per test rather than reset,
/// so there is no shared state between them to forget to clear.
late Assets assets;

/// Brings a scene up with no `Game` at all - `initializeScene` is public for
/// exactly this, and nothing in the asset pass needs a boot.
_PropScene _bringUp(_PropScene scene) {
  scene.initializeScene(_pool(), assets: assets);
  scene.handle = SceneRegistry.register(scene);
  addTearDown(scene.pool.dispose);
  return scene;
}

void main() {
  setUp(() {
    assets = Assets();
    _Counts.resetAll();
    AssetLoaders.register<_FakePayload>(const _FakeLoader());
  });

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
      final scene = _bringUp(_PropScene([a, b], sceneKey: _FakeAsset('music')));

      expect(
        scene.describeAssetsCalls,
        1,
        reason:
            'a scene declares its own prefab-less assets (music, UI '
            'chrome) exactly once, from initializeScene',
      );
      expect(
        a.describeAssetsCalls,
        1,
        reason:
            'every prefab the scene registers gets the pass too - and '
            'exactly once, or the same key would be declared twice',
      );
      expect(b.describeAssetsCalls, 1);
      expect(
        scene.declaredAssets.length,
        3,
        reason:
            "a scene's footprint is the union of its own assets and every "
            'registered prefab\'s',
      );
    });

    test('the scene\'s own assets are declared before any prefab\'s', () {
      final scene = _bringUp(
        _PropScene([_Prop(_FakeAsset('prop'))], sceneKey: _FakeAsset('music')),
      );

      expect(
        scene.music!.pack() < scene.prefabs.first.texture.pack(),
        isTrue,
        reason:
            'addresses are handed out in declaration order, and the order '
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
        reason:
            'no declaration means no address consumed - the pass costs a '
            'prefab with no assets nothing at all',
      );
    });

    test('the returned handle is addressable, and the key is not', () {
      final key = _FakeAsset('typed');
      final scene = _bringUp(_PropScene([_Prop(key)]));
      final handle = scene.prefabs.first.texture;

      expect(
        handle,
        isA<IntRepresentable>(),
        reason:
            'only an IntRepresentable is assignable to a packed component '
            'field - that is what makes `field[e] = handle` compile',
      );
      expect(
        key,
        isNot(isA<IntRepresentable>()),
        reason:
            'and the raw undeclared key is deliberately a different type, '
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
        reason:
            'the row stores the declared address and resolves it through '
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
        reason:
            'two prefabs using one texture must be one decode and one '
            'address, not two - which only holds if has() is idempotent per '
            'key',
      );
      expect(a.texture.pack(), b.texture.pack());
      expect(
        assets.tryGetAt(a.texture.pack()),
        same(a.texture),
        reason:
            'and the second declaration must not have built a second handle '
            'over the address, or the first would silently be the orphan',
      );
      expect(
        scene.declaredAssets.length,
        1,
        reason:
            "the scene's footprint counts the asset once, so the "
            'transition diff cannot double-count it either',
      );
    });

    test('a scene and a prefab declaring one key share it too', () {
      final shared = _FakeAsset('shared');
      final prop = _Prop(shared);
      final scene = _bringUp(_PropScene([prop], sceneKey: shared));

      expect(identical(scene.music, prop.texture), isTrue);
      expect(
        scene.declaredAssets.length,
        1,
        reason:
            'the scene and its prefabs declare into one descriptor, so '
            'this is the same declaration, not two that happen to match',
      );
    });

    test('two separately-constructed keys for one file are one asset', () {
      final a = _Prop(_FakeAsset('same-bytes'));
      final b = _Prop(_FakeAsset('same-bytes'));
      final scene = _bringUp(_PropScene([a, b]));

      // This assertion is inverted from what it used to be, deliberately.
      // Keys were identity-compared, so two keys naming one file were two
      // assets, two addresses and two decodes - which was survivable only
      // because every key was a shared `static final`. It stopped being
      // survivable once a key became plain enough to write inline at a call
      // site (`AssetKey<T>(BundleSource('x'))`), where two call sites naming
      // one file is the normal case rather than a mistake.
      expect(
        identical(a.texture, b.texture),
        isTrue,
        reason:
            'identity is (payload type, source), so two keys naming one file '
            'are one asset - one address and one decode',
      );
      expect(a.texture.pack(), b.texture.pack());
      expect(
        scene.declaredAssets.length,
        1,
        reason: 'and the scene footprint counts it once, not twice',
      );
    });

    test('one source decoded as two payload types is two assets', () {
      // The other half of the identity rule: the *type* is part of it, so a
      // file read two ways is two assets rather than a collision.
      final asTexture = assets.declare(_FakeAsset('dual'));
      final asOther = assets.declare(
        const AssetKey<_Unrelated>(_FakeSource('dual', 4)),
      );

      expect(asTexture.pack(), isNot(asOther.pack()));
    });
  });

  group('cross-copy address agreement', () {
    test('two independent boot passes assign the same addresses', () {
      // Exactly what the two isolate copies do: the same user code runs the
      // same describe passes in the same order on two heaps. Simulated here
      // by running the pass twice from a clean registry, as the existing
      // cross-isolate-agreement tests do.
      List<int> run() {
        final scene = _PropScene([
          _Prop(_FakeAsset('a')),
          _Prop(_FakeAsset('b')),
        ], sceneKey: _FakeAsset('music'));
        scene.initializeScene(_pool(), assets: assets);
        final addresses = <int>[
          scene.music!.pack(),
          for (final prefab in scene.prefabs) prefab.texture.pack(),
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
        reason:
            'address assignment is first-declaration order and nothing '
            'else, so the copy that cannot decode still writes the exact '
            'address the copy that can will resolve',
      );
    });

    test('an unloaded key re-declares to a fresh address, not the old one', () {
      final key = _FakeAsset('recycled');
      final first = assets.declare(key);
      final firstAddress = first.pack();
      assets.unload(key);
      final second = assets.declare(key);

      expect(identical(first, second), isFalse);
      expect(
        second.pack(),
        isNot(firstAddress),
        reason:
            'GlobalObjectRegistry only ever appends and nulls; recycling '
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
        instance.pack(),
        isNonNegative,
        reason:
            'the game isolate writes this address into rows without ever '
            'decoding anything - that is the whole point of the split',
      );
      expect(instance.isLoaded, isFalse);
      expect(
        () => instance.value,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('unloaded'), contains('never loaded')),
          ),
        ),
        reason:
            'reading a payload that was never decoded must name the asset '
            'and say it was never loaded - not null-deref three frames deeper',
      );
      expect(
        instance.info,
        isNull,
        reason: 'and nothing has been discovered about it yet either',
      );
    });

    test('the payload reads normally once loaded', () async {
      final key = _FakeAsset('loaded', byteCount: 17);
      final instance = assets.declare(key);
      await assets.load(key);

      expect(instance.isLoaded, isTrue);
      expect(instance.value.byteCount, 17);
      expect(
        (instance.info as _FakeInfo).byteCount,
        17,
        reason:
            'what the loader discovered is published alongside the payload, '
            'so a copy that cannot decode can still be told it',
      );
    });

    test('an address nothing issued throws rather than defaulting', () {
      // This replaces a test that asserted `_FakeInstance().address` threw.
      // A hand-built handle is no longer constructible at all - `Asset` has a
      // private constructor and only `Assets` calls it - so that hazard is
      // gone by construction rather than guarded at runtime. What remains
      // worth pinning is the other half of it: an int that never named an
      // asset must not quietly unpack to asset 0.
      expect(
        () => assets.of<_FakePayload>().unpack(0),
        throwsStateError,
        reason:
            'an int that never went through a describeAssets pass '
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

      final results = await Future.wait(<Future<Asset<_FakePayload>>>[
        assets.load(key),
        assets.load(key),
      ]);

      expect(identical(results[0], results[1]), isTrue);
      expect(
        key.decodes,
        1,
        reason:
            'the second caller joins the in-flight decode; two decodes '
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
        reason:
            'lazily declaring here would assign an address on this copy '
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
        reason:
            'declared-but-unloaded is the normal steady state on the game '
            'isolate, not an absence',
      );

      await assets.load(key);
      expect(assets.tryGet(key), same(declared));
    });
  });

  group('assets.unload', () {
    test(
      'frees the address, releases the payload, drops the declaration',
      () async {
        final key = _FakeAsset('doomed');
        final instance = assets.declare(key);
        await assets.load(key);
        final address = instance.pack();
        // Captured before the unload, which is what drops the handle's
        // reference to it - the payload object outlives the handle's link to
        // it precisely so a disposal can be observed.
        final payload = instance.value;

        assets.unload(key);

        expect(assets.tryGet(key), isNull);
        expect(
          payload.disposed,
          isTrue,
          reason:
              'AssetLoader.unload is where a real loader releases its '
              'ui.Image',
        );
        expect(instance.isLoaded, isFalse);
        expect(assets.of<_FakePayload>().tryUnpack(address), isNull);
        expect(
          () => assets.of<_FakePayload>().unpack(address),
          throwsStateError,
          reason:
              'a row still holding the freed address fails loudly on next '
              'read - unloading something still referenced is a caller bug',
        );
      },
    );

    test('unloading something never declared is a no-op', () {
      expect(() => assets.unload(_FakeAsset('absent')), returnsNormally);
    });

    test('unloadAll clears every declaration', () async {
      final keys = <_FakeAsset>[
        for (var i = 0; i < 5; i++) _FakeAsset('bulk$i'),
      ];
      final instances = <Asset<_FakePayload>>[
        for (final key in keys) assets.declare(key),
      ];
      for (final key in keys) {
        await assets.load(key);
      }
      final payloads = <_FakePayload>[for (final a in instances) a.value];

      assets.unloadAll();

      for (var i = 0; i < keys.length; i++) {
        expect(assets.tryGet(keys[i]), isNull);
        expect(assets.tryGetAt(instances[i].pack()), isNull);
        expect(payloads[i].disposed, isTrue);
      }
    });
  });

  group('assets.reset', () {
    test('genuinely clears, so declaring again is a fresh decode', () async {
      final key = _FakeAsset('sticky');
      final first = assets.declare(key);
      await assets.load(key);
      expect(key.decodes, 1);

      assets.reset();

      expect(
        assets.tryGet(key),
        isNull,
        reason:
            'a leftover declaration would make every later test in the '
            'process see this one\'s state - the exact order-dependence this '
            'hook exists to remove',
      );
      final second = assets.declare(key);
      await assets.load(key);
      expect(
        key.decodes,
        2,
        reason:
            'and the re-declared handle really is unloaded, rather than '
            'a cached one that reset only pretended to drop',
      );
      expect(
        identical(first, second),
        isFalse,
        reason: 'reset drops the handle too, not just the loaded flag',
      );
    });

    test('releases payloads so a native handle is not leaked', () async {
      final key = _FakeAsset('native');
      final instance = assets.declare(key);
      await assets.load(key);
      final payload = instance.value;

      assets.reset();

      expect(payload.disposed, isTrue);
    });
  });

  group('address unpacking', () {
    test('tryUnpack is null for a never-declared or out-of-range address', () {
      expect(assets.of<_FakePayload>().tryUnpack(0), isNull);
      expect(assets.of<_FakePayload>().tryUnpack(-1), isNull);
      expect(assets.of<_FakePayload>().tryUnpack(999), isNull);
    });

    test('tryUnpack is null for the wrong type at a valid address', () {
      final instance = assets.declare(_FakeAsset('typed'));
      expect(assets.of<_Unrelated>().tryUnpack(instance.pack()), isNull);
    });
  });

  group('loadScene asset diffing', () {
    test('a first load decodes exactly the scene\'s declared set', () async {
      final music = _FakeAsset('music');
      final prop = _FakeAsset('prop');
      final unused = _FakeAsset('unused');
      await _boot(
        () => _DiffGame(() => _PropScene([_Prop(prop)], sceneKey: music)),
      );

      expect(music.decodes, 1, reason: "the scene's own prefab-less asset");
      expect(prop.decodes, 1, reason: 'and every registered prefab\'s');
      expect(
        unused.decodes,
        0,
        reason:
            'a key nothing declared is not part of the scene, so nothing '
            'about a scene load should touch it',
      );
      expect(assets.tryGet(unused), isNull);
    });

    test('an asset shared by two loaded scenes is decoded once', () async {
      final shared = _FakeAsset('shared');
      final onlyA = _FakeAsset('only-a');
      final onlyB = _FakeAsset('only-b');

      await _boot(
        () => _DiffGame(() => _PropScene([_Prop(onlyA)], sceneKey: shared)),
      );
      expect(shared.decodes, 1);
      expect(onlyA.decodes, 1);

      // Loading no longer *replaces*: both scenes are resident now, and both
      // hold a claim on `shared`.
      await run.state.loadScene(_PropScene([_Prop(onlyB)], sceneKey: shared));

      expect(
        shared.decodes,
        1,
        reason:
            'the second scene raises the claim count rather than decoding '
            'again - asserted against the decode counter, because a reload '
            'producing an identical payload would satisfy any assertion about '
            'final state',
      );
      expect(assets.tryGet(shared)?.isLoaded, isTrue);
      expect(onlyB.decodes, 1, reason: 'what only the new scene needs loads');
      expect(
        assets.tryGet(onlyA)?.isLoaded,
        isTrue,
        reason:
            'loading no longer unloads anything - the first scene is still '
            'resident and still claims its own asset. Freeing is what '
            'unloadScene is for, and that is the whole reason a claim count '
            'replaced the pairwise previous->next diff',
      );
    });

    test('a shared asset outlives the first unload and dies with the last', () async {
      final shared = _FakeAsset('shared');
      final onlyA = _FakeAsset('only-a');
      final onlyB = _FakeAsset('only-b');
      await _boot(
        () => _DiffGame(() => _PropScene([_Prop(onlyA)], sceneKey: shared)),
      );
      final first = run.state.loadedScenes.single;
      final second = await run.state.loadScene(
        _PropScene([_Prop(onlyB)], sceneKey: shared),
      );

      run.state.unloadScene(first);

      expect(
        assets.tryGet(onlyA),
        isNull,
        reason: 'nothing else claimed it, so it goes with its scene',
      );
      expect(
        assets.tryGet(shared)?.isLoaded,
        isTrue,
        reason:
            'the second scene still claims it - this is exactly what the '
            'old pairwise previous->next diff could not express, because with '
            'A and C sharing an atlas and B not, A->B freed it and B->C '
            'decoded it again',
      );

      run.state.unloadScene(second);
      expect(
        assets.tryGet(shared),
        isNull,
        reason: 'the last claim released is what frees it',
      );
      expect(
        assets.tryGet(onlyB),
        isNull,
        reason: 'and the asset only the second scene claimed goes with it',
      );
    });

    test('onProgress is monotonic and ends at exactly 1.0', () async {
      final keys = <_FakeAsset>[
        for (var i = 0; i < 4; i++) _FakeAsset('step$i'),
      ];
      await _boot(() => _DiffGame(() => GameSceneStub()));

      final reports = <SceneLoadProgress>[];
      await run.state.loadScene(
        _PropScene([
          for (var i = 1; i < keys.length; i++) _Prop(keys[i]),
        ], sceneKey: keys.first),
        onProgress: reports.add,
      );

      expect(reports, isNotEmpty);
      for (var i = 1; i < reports.length; i++) {
        expect(
          reports[i].progress,
          greaterThanOrEqualTo(reports[i - 1].progress),
          reason:
              'a loading bar that goes backwards is a bug in the reporter, '
              'not something every consumer should have to clamp',
        );
      }
      expect(
        reports.last.progress,
        1.0,
        reason:
            'the terminal report is exactly 1.0, so "hide the loading '
            'screen" can key off equality rather than a threshold',
      );
      expect(
        reports.first.label,
        contains('step0'),
        reason: 'each report names what was just loaded',
      );
    });

    test(
      'a transition needing no decodes still reports a single 1.0',
      () async {
        final shared = _FakeAsset('shared');
        await _boot(() => _DiffGame(() => _PropScene([], sceneKey: shared)));

        final reports = <SceneLoadProgress>[];
        await run.state.loadScene(
          _PropScene([], sceneKey: shared),
          onProgress: reports.add,
        );

        expect(shared.decodes, 1);
        expect(
          reports.map((r) => r.progress).toList(),
          <double>[1.0],
          reason:
              'no decodes means nothing to report fractions of - but the '
              'caller still has to be told it is done, without having to '
              'special-case the empty case itself',
        );
      },
    );

    test(
      'loading one declaration twice gives two scenes sharing its assets',
      () async {
        final key = _FakeAsset('same-scene');
        await _boot(() => _DiffGame(() => _PropScene([_Prop(key)])));
        final struct = run.state.scene!;
        final first = run.state.loadedScenes.single;

        // The same *declaration*, loaded again. It is not a no-op any more -
        // it is a second resident instance with its own pages - but its assets
        // are already decoded, so it costs no decode.
        final second = await run.state.loadScene(struct);

        expect(key.decodes, 1);
        expect(second, isNot(first));
        expect(run.state.loadedScenes.length, 2);

        run.state.unloadScene(second);
        expect(
          assets.tryGet(key)?.isLoaded,
          isTrue,
          reason: 'the first load still claims it',
        );
      },
    );

    test('the world layout exists before the bring-up future completes', () {
      expect(ArchetypeRegistry.count, 0, reason: 'nothing registered yet');

      // Deliberately not awaited. The claim is that `loadScene`'s registering
      // half runs before its first `await`, so the world *layout* exists the
      // instant bring-up has been called - only the content is still arriving.
      // An async function runs synchronously up to its own first await, which
      // is what makes that observable at all.
      final starting = Game.startInline(
        () => _DiffGame(() => _PropScene([_Prop(_FakeAsset('sync'))])),
      );

      // Asserted through the archetype registry rather than through the state.
      // The run is what owns the state now, and the run does not exist until
      // its future completes - so "before the future completes" and "reachable
      // through the handle" are mutually exclusive by construction. Registering
      // an archetype is what the synchronous half *does*, so it is the more
      // direct evidence anyway.
      expect(
        ArchetypeRegistry.count,
        greaterThan(0),
        reason:
            'the entity layout is registered synchronously; it is the '
            'asset content that is still arriving',
      );

      addTearDown(() async {
        final run = await starting;
        if (run.isRunning) await run.stop();
      });
    });
  });
}

class _Unrelated {}

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
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    descriptor.has(() => _prefab);
  }
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

Future<T> _boot<T extends Game>(T Function() create) async {
  final game = await Game.startInline(create);
  run = game;
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
