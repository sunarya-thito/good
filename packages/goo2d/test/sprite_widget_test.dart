import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/widgets.dart' hide Texture;
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

import 'png_fixture.dart';

// SpriteWidget, the main-isolate widget side of #120: does a handle the engine
// already decoded reach a Flutter widget with the right pixels, does a frame of
// a sheet name the right rectangle, does an unloaded handle stay quiet, and
// does any of it cost a second decode.
//
// Every pixel assertion below is a plain `test`, not a `testWidgets`. Image
// work inside `testWidgets` needs `tester.runAsync`, and getting that wrong
// does not fail - it hangs, and leaves a `flutter_tester` behind. The painter a
// `SpriteWidget` builds is reachable without a tree, so the raster path never
// needs one; the two `testWidgets` here pump a real tree and do no image work.

/// [SpriteWidget.build] ignores its context, so this is enough to get at the
/// `CustomPaint` it returns. `noSuchMethod` covers the rest of `BuildContext`,
/// and a build that started reading it would come back null rather than
/// silently working.
class _NoContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Traps every `Canvas` call, so "an unloaded handle draws nothing" is a claim
/// about the whole surface rather than about `drawImageRect` alone.
class _SpyCanvas implements Canvas {
  final List<String> calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    // Symbol("drawImageRect") -> drawImageRect
    calls.add(name.substring(name.indexOf('"') + 1, name.lastIndexOf('"')));
    return null;
  }
}

/// Declares some textures the way a scene does - `initializeScene` is the one
/// supported way to run a `describeAssets` pass outside a full `Game` boot.
class _TextureScene extends SceneStruct {
  _TextureScene(this.keys);

  final List<TextureKey> keys;
  final List<TextureAsset> textures = <TextureAsset>[];

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    for (final key in keys) {
      textures.add(descriptor.has(key));
    }
  }
}

late Assets assets;

/// Handles for [images], decoded only when [load] says so - so an unloaded
/// handle here is a *declared* one that never decoded, which is the state a
/// widget built before its scene finished loading actually sees.
Future<List<TextureAsset>> _handles(
  List<Uint8List> images, {
  bool load = true,
}) async {
  final keys = <TextureKey>[
    for (var i = 0; i < images.length; i++)
      TextureKey(MemorySource(images[i], name: 'tex$i')),
  ];
  final scene = _TextureScene(keys)
    ..initializeScene(MemoryPool(pageSize: 4096), assets: assets);
  SceneRegistry.register(scene);
  addTearDown(scene.pool.dispose);
  if (load) {
    for (final key in keys) {
      await assets.load(key);
    }
  }
  return scene.textures;
}

/// The painter [widget] builds, without pumping a tree.
CustomPainter _painterOf(SpriteWidget widget) =>
    (widget.build(_NoContext()) as CustomPaint).painter!;

/// What [widget] asks to be laid out at.
Size _preferredSizeOf(SpriteWidget widget) =>
    (widget.build(_NoContext()) as CustomPaint).size;

/// Paints [widget] into a [width] x [height] image and hands back a reader over
/// its pixels, as the same `0xRRGGBBAA` a [Texel] returns.
Future<Texel> _rasterize(SpriteWidget widget, int width, int height) async {
  final recorder = PictureRecorder();
  final painter = _painterOf(widget);
  painter.paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  addTearDown(picture.dispose);
  final image = await picture.toImage(width, height);
  addTearDown(image.dispose);
  final pixels = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
  return (int x, int y) => pixels.getUint32((y * width + x) * 4);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    assets = Assets();
    AssetLoaders.register<Texture>(const TextureLoader());
  });

  tearDown(() {
    assets.reset();
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('spy sanity', () {
    test('the spy traps the call the unloaded test claims never happens', () {
      // Without this, "calls is empty" would pass just as happily against a
      // spy whose noSuchMethod trapped nothing.
      final spy = _SpyCanvas();
      spy.drawRect(Rect.zero, Paint());
      expect(spy.calls, ['drawRect']);
    });
  });

  group('whole texture', () {
    test('every texel of the image lands on its own pixel', () async {
      final textures = await _handles(<Uint8List>[png64x32]);
      final raster = await _rasterize(
        SpriteWidget(textures[0], filter: TextureFilter.nearest),
        64,
        32,
      );
      expectRegion(
        raster,
        left: 0,
        top: 0,
        width: 64,
        height: 32,
        expected: wideTexel,
        reason: 'the default frame must be the whole texture, unflipped',
      );
    });

    test('the widget prefers the texture own pixel size', () async {
      final textures = await _handles(<Uint8List>[png64x32]);
      expect(_preferredSizeOf(SpriteWidget(textures[0])), const Size(64, 32));
    });
  });

  group('sheet frame', () {
    // A 2x2 grid over the 64x32 sheet: cell (cx, cy) is the 32x16 rectangle at
    // (cx * 32, cy * 16). Every texel of that sheet is a different colour - red
    // carries the column and green the row - so a source rect off by one cell
    // does not report "not equal", it reports the column and row it actually
    // sampled.
    for (var index = 0; index < 4; index++) {
      final cellX = index % 2;
      final cellY = index ~/ 2;
      test(
        'cell $index samples the rectangle at (${cellX * 32}, ${cellY * 16})',
        () async {
          final textures = await _handles(<Uint8List>[png64x32]);
          final raster = await _rasterize(
            SpriteWidget(
              textures[0],
              frame: SpriteFrame.grid(columns: 2, rows: 2, index: index),
              filter: TextureFilter.nearest,
            ),
            32,
            16,
          );
          expectRegion(
            raster,
            left: 0,
            top: 0,
            width: 32,
            height: 16,
            expected: (x, y) => wideTexel(cellX * 32 + x, cellY * 16 + y),
            reason: 'cell $index sampled the wrong region of the sheet',
          );
        },
      );
    }

    test('a pixel frame samples the rectangle it names', () async {
      final textures = await _handles(<Uint8List>[png64x32]);
      final raster = await _rasterize(
        SpriteWidget(
          textures[0],
          frame: const SpriteFrame.pixels(
            x: 12,
            y: 5,
            width: 8,
            height: 4,
            sheetWidth: 64,
            sheetHeight: 32,
          ),
          filter: TextureFilter.nearest,
        ),
        8,
        4,
      );
      expectRegion(
        raster,
        left: 0,
        top: 0,
        width: 8,
        height: 4,
        expected: (x, y) => wideTexel(12 + x, 5 + y),
        reason: 'SpriteFrame.pixels must convert back to the pixels it took',
      );
    });

    test('the preferred size is the frame, not the sheet', () async {
      final textures = await _handles(<Uint8List>[png64x32]);
      expect(
        _preferredSizeOf(
          SpriteWidget(
            textures[0],
            frame: const SpriteFrame.grid(columns: 2, rows: 2, index: 3),
          ),
        ),
        const Size(32, 16),
      );
    });
  });

  group('an unloaded handle', () {
    test('draws nothing rather than throwing', () async {
      final textures = await _handles(<Uint8List>[png64x32], load: false);
      expect(textures[0].isLoaded, isFalse);
      final spy = _SpyCanvas();
      // `Asset.value` throws on a handle that never decoded, so a painter that
      // reached for the image at all comes out of this as a StateError rather
      // than as an empty call log.
      _painterOf(SpriteWidget(textures[0])).paint(spy, const Size(64, 32));
      expect(spy.calls, isEmpty);
    });

    test('takes no space', () async {
      final textures = await _handles(<Uint8List>[png64x32], load: false);
      expect(_preferredSizeOf(SpriteWidget(textures[0])), Size.zero);
    });
  });

  group('in a widget tree', () {
    testWidgets('it lays out and paints, and adds nothing to the imageCache', (
      tester,
    ) async {
      // The whole argument for this widget. `Image.asset` on the same file
      // decodes a second copy into `imageCache` and leaves the engine's copy
      // held - measured at 512 KiB for a 256x256 image rather than 256.
      // Drawing the handle the engine already decoded costs nothing extra, and
      // this is the assertion that says so.
      final cache = PaintingBinding.instance.imageCache..clear();
      // The decode is the only real async work, and it happens before the pump
      // - `runAsync` is what lets it complete against the fake clock. The pump
      // itself only paints.
      final textures = await tester.runAsync(
        () => _handles(<Uint8List>[png64x32]),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SpriteWidget(
              textures![0],
              frame: const SpriteFrame.grid(columns: 2, rows: 2, index: 3),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(SpriteWidget)), const Size(32, 16));
      expect(cache.currentSizeBytes, 0);
      expect(cache.currentSize, 0);
      expect(cache.liveImageCount, 0);
    });

    testWidgets('the imageCache counter that assertion reads can be non-zero', (
      tester,
    ) async {
      // Without this, `currentSizeBytes == 0` would pass just as happily
      // against a binding whose cache never counts anything - and the whole
      // claim above is that the number *would* have moved for the alternative.
      // This is that alternative: the same bytes through Flutter's own image
      // path, in the same harness.
      final cache = PaintingBinding.instance.imageCache..clear();
      addTearDown(cache.clear);
      await tester.runAsync(() async {
        final decoded = Completer<void>();
        final stream = MemoryImage(png64x32).resolve(ImageConfiguration.empty);
        late ImageStreamListener listener;
        listener = ImageStreamListener((info, _) {
          info.dispose();
          stream.removeListener(listener);
          decoded.complete();
        });
        stream.addListener(listener);
        await decoded.future;
      });
      // 64 x 32 x 4 bytes, held by Flutter on top of whatever the engine
      // already holds.
      expect(cache.currentSizeBytes, 8192);
    });

    testWidgets('an unloaded handle leaves the tree standing', (tester) async {
      final textures = await tester.runAsync(
        () => _handles(<Uint8List>[png64x32], load: false),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: SpriteWidget(textures![0])),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SpriteWidget), findsOneWidget);
    });
  });
}
