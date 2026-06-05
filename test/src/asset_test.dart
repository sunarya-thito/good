import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

class MockSource implements AssetSource {
  @override
  final String name;
  MockSource(this.name);

  @override
  Future<Uint8List> loadBytes() async => Uint8List(0);
}

class MockAsset extends GameAsset {
  @override
  final AssetSource source;

  @override
  bool isLoaded = false;
  int loadCount = 0;

  MockAsset(String name) : source = MockSource(name);

  @override
  Future<void> load() async {
    isLoaded = true;
    loadCount++;
  }

  @override
  void unload() {
    isLoaded = false;
  }
}

enum TestAssets with AssetEnum {
  assetA,
  assetB
  ;

  @override
  GameAsset createAsset() => MockAsset(name);

  @override
  AssetSource get source => MockSource(name);

  MockAsset get mock => asset as MockAsset;
}

void main() {
  setUp(() {
    AssetEnum.reset();
  });

  group('AssetEnum', () {
    test('should lazily register assets', () {
      // Accessing for the first time should register
      final assetA = TestAssets.assetA.mock;
      expect(assetA.source.name, equals('assetA'));
      expect(assetA.loadCount, equals(0));

      // Accessing again should return the same instance
      final assetA2 = TestAssets.assetA.mock;
      expect(assetA2, same(assetA));
    });

    test('should reset registries', () {
      final assetA = TestAssets.assetA.mock;
      AssetEnum.reset();
      final assetA2 = TestAssets.assetA.mock;
      expect(assetA2, isNot(same(assetA)));
    });
  });

  group('GameAsset', () {
    test('loadAll should load assets and report progress', () async {
      final assets = [TestAssets.assetA, TestAssets.assetB];
      final stream = GameAsset.loadAll(assets);

      final results = await stream.toList();

      expect(results.length, equals(2));
      expect(results[0].assetLoaded, equals(1));
      expect(results[0].assetCount, equals(2));
      expect(results[1].assetLoaded, equals(2));

      expect(TestAssets.assetA.mock.isLoaded, isTrue);
      expect(TestAssets.assetB.mock.isLoaded, isTrue);
    });
  });
}
