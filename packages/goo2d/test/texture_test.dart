import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

/// A 2x1 PNG - the smallest thing that proves the decode really happened and
/// that width and height are not simply both 1 by accident.
final Uint8List _png2x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR42mP4z8AAQv8BD/kD'
  '/Zh51wAAAAAASUVORK5CYII=',
);

/// Serves [_png2x1] under one path and nothing else - so the "wrong path"
/// case is a real bundle miss rather than a stub that answers everything.
class _FakeBundle extends CachingAssetBundle {
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    if (key != 'assets/tile.png') {
      throw FlutterError('no asset bundled at $key');
    }
    loads++;
    // Deliberately handed back as a *view* into a larger buffer, the way a
    // bundle that packs several assets together does - if AssetBundleSource
    // ignored offsetInBytes/lengthInBytes the decode below would fail.
    final padded = Uint8List(_png2x1.length + 8)..setAll(4, _png2x1);
    return ByteData.sublistView(padded, 4, 4 + _png2x1.length);
  }
}

/// The one legitimate way to declare an asset outside a full `Game` boot:
/// bring a scene up by hand. `initializeScene` is public for exactly this.
class _TextureScene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _TextureScene(this.key) : super();

  final TextureKey key;

  late final TextureAsset texture;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    texture = descriptor.has(key);
  }
}

_TextureScene _declare(TextureKey key) {
  final scene = _TextureScene(key)..initializeScene(MemoryPool(pageSize: 4096), assets: assets);
  scene.handle = SceneRegistry.register(scene);
  addTearDown(scene.pool.dispose);
  return scene;
}

/// The table under test. Instance state on the `Game` now, so a fixture with
/// no `Game` owns its own.
late Assets assets;

void main() {
  setUp(() {
    assets = Assets();
    AssetLoaders.register<Texture>(const TextureLoader());
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    assets.reset();
    assets.reset();
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('Texture', () {
    test('declares to an address before anything is decoded', () {
      final key = TextureKey(MemorySource(_png2x1, name: 'tile'));
      final scene = _declare(key);

      expect(
        scene.texture.pack(),
        isNonNegative,
        reason: 'the address is what a component row stores, and it exists '
            'from declaration - which is the only reason the game isolate, '
            'which can never decode a pixel, can populate a texture field',
      );
      expect(scene.texture.isLoaded, isFalse);
    });

    test('reading .image before it is loaded names the asset and throws', () {
      final key = TextureKey(MemorySource(_png2x1, name: 'tile.png'));
      final scene = _declare(key);

      expect(
        () => scene.texture.value.image,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('tile.png'), contains('never loaded')),
          ),
        ),
        reason: 'this is the game isolate\'s permanent state, so it has to '
            'fail by name rather than null-dereference somewhere in a paint',
      );
      expect(() => scene.texture.value.width, throwsStateError);
      expect(() => scene.texture.value.height, throwsStateError);
    });

    test('load decodes real PNG bytes into a ui.Image', () async {
      final key = TextureKey(MemorySource(_png2x1, name: 'tile'));
      final scene = _declare(key);

      await assets.load(key);

      expect(scene.texture.isLoaded, isTrue);
      expect(scene.texture.value.width, 2);
      expect(
        scene.texture.value.height,
        1,
        reason: 'the dimensions come out of the codec, so a 2x1 source that '
            'reads back 2x1 is proof an actual decode ran',
      );
      expect(scene.texture.value.image.width, 2);
    });

    test('the same instance the declaration returned is the loaded one',
        () async {
      final key = TextureKey(MemorySource(_png2x1));
      final scene = _declare(key);

      final loaded = await assets.load(key);

      expect(
        identical(loaded, scene.texture),
        isTrue,
        reason: 'the handle a prefab kept in its field must be the object the '
            'decode filled in - otherwise every row written at declare time '
            'would point at an empty orphan',
      );
    });

    test('the address round-trips through the asset table', () async {
      final key = TextureKey(MemorySource(_png2x1));
      final scene = _declare(key);
      await assets.load(key);

      expect(
        assets.of<Texture>().unpack(scene.texture.pack()),
        same(scene.texture),
        reason: 'this is the exact lookup a DataPointer<Texture> read makes - '
            'the row holds the Uint32, the registry turns it back into the '
            'decoded image',
      );
    });

    test('unloading disposes the image and frees the address', () async {
      final key = TextureKey(MemorySource(_png2x1));
      final scene = _declare(key);
      await assets.load(key);
      final texture = scene.texture;
      final payload = texture.value;
      final address = texture.pack();

      assets.unload(key);

      expect(texture.isLoaded, isFalse);
      expect(
        () => texture.value.image,
        throwsStateError,
        reason: 'a ui.Image holds engine memory the Dart GC does not account '
            'for, so unloading really disposes it - reading afterwards must '
            'not hand back a disposed image',
      );
      expect(assets.tryGetAt(address), isNull);
      expect(
        payload,
        isNotNull,
        reason:
            'the payload object outlives the handle link that was dropped, '
            'which is what let the disposal above be observed at all',
      );
    });

    test('the declared handle is addressable and its key is not', () {
      final key = TextureKey(MemorySource(_png2x1));
      final scene = _declare(key);

      expect(scene.texture, isA<IntRepresentable>());
      expect(
        key,
        isNot(isA<IntRepresentable>()),
        reason: 'the type split is what makes `textureField[e] = someKey` a '
            'compile error and `textureField[e] = declaredHandle` legal',
      );
    });
  });

  group('BundleSource', () {
    test('reads the declared path out of the bundle and decodes it', () async {
      final bundle = _FakeBundle();
      final key = TextureKey(BundleSource('assets/tile.png', bundle: bundle));
      final scene = _declare(key);

      await assets.load(key);

      expect(bundle.loads, 1);
      expect(scene.texture.value.width, 2);
      expect(scene.texture.value.height, 1);
    });

    test('names itself by path, so diagnostics point at the right file', () {
      final key = TextureKey(const BundleSource('assets/tile.png'));
      expect(key.source.description, 'assets/tile.png');
      expect(
        key.debugLabel,
        contains('assets/tile.png'),
        reason: 'an "asset was never loaded" message is only useful if it '
            'says which asset',
      );
    });

    test('a missing path fails loudly rather than decoding garbage', () {
      final key = TextureKey(
        BundleSource('assets/absent.png', bundle: _FakeBundle()),
      );
      _declare(key);
      expect(assets.load(key), throwsFlutterError);
    });
  });

  group('sharing across scenes', () {
    test('one key declared by two scenes is one instance and one decode',
        () async {
      final key = TextureKey(MemorySource(_png2x1));
      final first = _declare(key);
      final second = _declare(key);

      await assets.load(key);
      await assets.load(key);

      expect(identical(first.texture, second.texture), isTrue);
      expect(first.texture.pack(), second.texture.pack());
      expect(
        second.texture.value.image.width,
        2,
        reason: 'the second scene sees the already-decoded image, which is '
            'what makes a transition between two scenes sharing a UI atlas '
            'free of a decode round trip',
      );
    });
  });
}
