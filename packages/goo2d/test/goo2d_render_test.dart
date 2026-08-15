import 'dart:ffi' hide Size;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;


// The seam: GameRenderer2D writes bytes, DrawCanvas2D reads them, and nothing
// in between re-derives the layout. render_2d_test.dart checks the producer
// against hand-decoded bytes and draw_canvas_2d_test.dart checks the consumer
// against hand-encoded ones - each would keep passing if both drifted the
// same way. This is the test that would not.

/// A 2x1 PNG: opaque red pixel, opaque blue pixel.
final Uint8List _png2x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR42mP4z8AAQv8BD/kD'
  '/Zh51wAAAAAASUVORK5CYII=',
);

class _Sprite extends EntityStruct
    with Transform2D, WorldTransform2D, Child, Parent, Renderable2D {
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    quad = descriptor.has();
  }
}

/// Two sprites off one texture and one off none, at three depths - the shape
/// that makes the record's texture field, the run split and the z order all
/// observable in a single crossing.
class _Billboard extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  static final TextureAsset tileAsset =
      TextureAsset(MemoryImageSource(_png2x1, name: 'tile.png'));

  late final Texture tile;
  late final Sprite front;
  late final Sprite middle;
  late final Sprite back;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    tile = descriptor.has(tileAsset);
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    // Declared out of depth order, so the run order below is the *sort's*
    // output rather than the declaration's.
    front = descriptor.has(texture: tile, width: 2, height: 2, zIndex: 2);
    back = descriptor.has(texture: tile, width: 2, height: 2, zIndex: 0);
    middle = descriptor.has(width: 2, height: 2, color: 0xFFFF0000, zIndex: 1);
  }
}

class _Scene extends SceneStruct {
  /// This fixture's handle, captured when the framework mounts it. Entity
  /// creation lives on `Scene` now - one `SceneStruct` can back several loaded
  /// scenes - and a loaded scene is handed its own handle at mount.
  late Scene handle;

  @override
  void onSceneMounted(Scene scene) => handle = scene;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Scene();

  late final _Sprite sprite;
  late final _Billboard billboard;

  @override
  void describeScene(SceneDescriptor descriptor) {
    sprite = descriptor.has(_Sprite());
    billboard = descriptor.has(_Billboard());
  }
}

class _GameState extends GameState2D<_Game> {
  @override
  void onMounted() {
    loadScene(_Scene());
  }
}

/// `with Renderer2D`: the frame buffers are declared and allocated by the
/// `Game` half now, so a hand-declared `GameRenderer2D` in a game without it
/// would have nowhere to write.
class _Game extends Game2D {
  /// The view under test - this fixture's spelling of `defaultCamera`.
  CameraView get view => defaultCamera;

  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState2D<_Game> createState() => _GameState();
}

/// Exactly the two steps `GameView` performs on a tick notification.
DrawCanvas2D _present(_Game game) {
  final canvas = DrawCanvas2D(assets: assets);
  final frames = run.state.getSystem<GameRenderer2D>().framesFor(game.view).buffer;
  final slot = frames.beginRead();
  expect(slot, isNotNull, reason: 'the renderer published a frame this tick');
  expect(
    canvas.ingestFrame(
      ByteData.sublistView(slot!.asTypedList(frames.readUsedBytes)),
      frames.readUsedBytes,
    ),
    isTrue,
  );
  return canvas;
}

Future<_Game> _boot() async {
  final game = _Game();
  run = await Game.startInline(game);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  // A booted Game owns its own table - point the fixture's handle at it, so
  // the load below names the declaration the game actually made.
  assets = game.assets;
  // `loadScene` returns the "world is ready" future, but `onMounted` is a void
  // callback and cannot hand it back - so a real PNG decode is still in flight
  // when `start` resolves. Awaiting the same key again is free (GameAssets
  // dedupes an in-flight load) and is what makes "is it decoded yet" a fact
  // rather than a race.
  await assets.load(_Billboard.tileAsset);
  return game;
}

/// The table under test. Instance state on the `Game` now, so a fixture with
/// no `Game` owns its own.
late GameAssets assets;

void main() {
  setUp(() => assets = GameAssets());

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    assets.reset();
    assets.reset();
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('a hierarchy simulated on one end comes out as geometry on the other',
      () async {
    final game = await _boot();
    final scene = run.state.getScene<_Scene>();

    final parent = scene.addEntity(scene.sprite);
    scene.sprite
      ..transformOffsetX[parent] = 100
      ..transformOffsetY[parent] = 100
      ..transformScaleX[parent] = 2
      ..transformScaleY[parent] = 2;

    final child = scene.addEntity(scene.sprite, parent: parent);
    scene.sprite.transformOffsetX[child] = 10;
    scene.sprite.quad
      ..width[child] = 4
      ..height[child] = 4
      ..color[child] = 0xFF00FF00;

    run.state.advance(const Duration(milliseconds: 10));

    final canvas = _present(game);
    addTearDown(canvas.dispose);

    expect(canvas.frameTick, 1);
    expect(canvas.vertexCount, 6, reason: 'only the child is sized');
    // Child at parent-local (10,0) under a 2x scale: centre (120,100), half
    // extent 4 after scaling. Vertex order is the fan split 0-1-2 / 0-2-3.
    expect(canvas.positions, [
      116, 96, //
      124, 96, //
      124, 104, //
      116, 96, //
      124, 104, //
      116, 104, //
    ]);
    expect(canvas.colors.first.toUnsigned(32), 0xFF00FF00);
    expect(canvas.runCount, 1);
    expect(canvas.runTextureAt(0), DrawSpriteData2D.noTexture,
        reason: 'no texture was ever set on this prefab, so the sentinel has '
            'to survive the crossing as faithfully as a real address would');
  });

  test('a texture address survives the crossing and drives the run split',
      () async {
    final game = await _boot();
    final scene = run.state.getScene<_Scene>();
    scene.addEntity(scene.billboard);

    run.state.advance(const Duration(milliseconds: 10));
    final canvas = _present(game);
    addTearDown(canvas.dispose);

    final address = scene.billboard.tile.address;
    expect(canvas.vertexCount, 18, reason: 'three sprites, six vertices each');
    expect(
      [for (var r = 0; r < canvas.runCount; r++) canvas.runTextureAt(r)],
      [address, DrawSpriteData2D.noTexture, address],
      reason: 'z 0,1,2 is back, middle, front - so the two same-texture '
          'sprites are separated by the untextured one and must stay in three '
          'runs. Merging them would be one fewer draw call and the middle '
          'sprite painted over something that is meant to be in front of it.',
    );
    expect(canvas.texCoords.sublist(0, 12), [0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1],
        reason: 'a plain sprite samples the whole texture, and the producer '
            'writes the UVs in the same fan split the positions use');
  });

  test('the address the producer wrote resolves to a shader on replay',
      () async {
    final game = await _boot();
    final scene = run.state.getScene<_Scene>();
    scene.addEntity(scene.billboard);
    run.state.advance(const Duration(milliseconds: 10));
    final canvas = _present(game);
    addTearDown(canvas.dispose);

    expect(scene.billboard.tile.isLoaded, isTrue,
        reason: 'loadScene decodes the scene declared assets on the isolate '
            'that can - which is the half of the arrangement that makes an '
            'address written by a producer that cannot decode resolvable here');

    // The full trip: bytes the producer wrote -> address -> registry -> live
    // Texture -> ui.Image -> ImageShader -> a real Picture. Nothing in this
    // chain is stubbed, and a stale or mis-encoded address would throw rather
    // than paint nothing.
    final recorder = PictureRecorder();
    expect(() => canvas.replay(Canvas(recorder)), returnsNormally);
    final picture = recorder.endRecording();
    addTearDown(picture.dispose);
    expect(picture, isNotNull);
  });
}
